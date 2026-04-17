import Foundation

extension PlotSession {
    func runPreflight() async {
        guard let request = currentRenderRequest() else {
            return
        }

        isRunningPreflight = true
        errorMessage = nil
        defer { isRunningPreflight = false }

        do {
            preflightResponse = try await client?.preflightRender(request)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportCurrentSelection() async {
        guard
            let client,
            let selectedFileURL,
            let selectedTemplateID = effectiveTemplateID,
            hasRenderableSelection
        else {
            return
        }

        let isMultiOutput = isMultiOutputTemplate(templateID: selectedTemplateID)
        guard let exportFormat = chooseExportFormat(isMultiOutput) else {
            return
        }
        guard let destinationURL = chooseExportDestination(
            suggestedPlotExportFilename(
                templateID: selectedTemplateID,
                format: exportFormat,
                isMultiOutput: isMultiOutput
            ),
            isMultiOutput,
            exportFormat
        ) else {
            return
        }

        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let response = try await client.exportRender(
                .init(
                    inputPath: selectedFileURL.path,
                    sheet: selectedSheet,
                    template: selectedTemplateID,
                    options: renderOptions,
                    outputDir: nil
                )
            )
            let sourceURLs = response.outputs.map { URL(fileURLWithPath: $0) }
            userExportURLs = try materializeExport(sourceURLs, destinationURL)
            exportResponse = response
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealLatestExport() {
        if !userExportURLs.isEmpty {
            WorkspaceBridge.reveal(userExportURLs)
        }
    }

    func openLatestExport(id: String) {
        guard let item = latestExportItems.first(where: { $0.id == id }) else {
            return
        }
        WorkspaceBridge.open(item.url)
    }

    func openCurrentSource() {
        guard let selectedFileURL else {
            return
        }
        WorkspaceBridge.open(selectedFileURL)
    }

    func revealCurrentSource() {
        guard let selectedFileURL else {
            return
        }
        WorkspaceBridge.reveal([selectedFileURL])
    }

    func openExampleDataTemplate(named filename: String) {
        do {
            WorkspaceBridge.open(try exampleDataTemplateURL(named: filename))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealExampleDataTemplates() {
        do {
            WorkspaceBridge.reveal(try availableExampleDataTemplateURLs())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelPreviewTask() {
        asyncCoordination.preview.cancel()
    }

    func waitUntilPreviewFinishes(for _: URL?) async {
        await asyncCoordination.preview.wait()
    }

    func setTemplate(_ templateID: String, shouldResetRenderOptions: Bool) {
        let migratedTemplateID = migrateLegacyTemplateID(templateID) ?? templateID
        selectedTemplateID = migratedTemplateID
        if shouldResetRenderOptions {
            resetRenderOptions(for: migratedTemplateID)
        }
        invalidateSubmissionArtifacts()
        errorMessage = nil
    }

    func schedulePreviewRefresh(policy: PlotPreviewRefreshPolicy) {
        guard let request = currentRenderRequest() else {
            return
        }

        isPreviewing = true
        errorMessage = nil

        let delay = policy == .debounced ? previewDebounceNanoseconds : 0
        asyncCoordination.preview.schedule(delayNanoseconds: delay) { [weak self] revision in
            guard let self else { return }
            await self.performPreview(request: request, revision: revision)
        }
    }

    func performPreview(request: RenderRequest, revision: Int) async {
        guard let client else {
            if asyncCoordination.preview.isLatest(revision) {
                isPreviewing = false
            }
            return
        }

        do {
            let response = try await client.renderPreview(request)
            guard asyncCoordination.preview.isLatest(revision), !Task.isCancelled else {
                return
            }
            previewResponse = response
            isPreviewing = false
            errorMessage = nil
        } catch {
            guard asyncCoordination.preview.isLatest(revision), !Task.isCancelled else {
                return
            }
            errorMessage = error.localizedDescription
            isPreviewing = false
        }
    }

    func currentRenderRequest() -> RenderRequest? {
        guard
            let selectedFileURL,
            let selectedTemplateID = effectiveTemplateID,
            !needsInspection
        else {
            return nil
        }

        sanitizeRenderOptionsForCurrentTemplateIfNeeded()

        return .init(
            inputPath: selectedFileURL.path,
            sheet: selectedSheet,
            template: selectedTemplateID,
            options: renderOptions
        )
    }

    func resetRenderOptions(for templateID: String) {
        let template = metadata?.templates.first { $0.id == templateID }
        let recommendationSummary = recommendedPreviewConfigSummary(for: templateID)
        let preservedThemeID = metadata?.visualThemes.contains(where: { $0.id == renderOptions.visualThemeID }) == true
            ? renderOptions.visualThemeID
            : metadata?.visualThemes.first?.id

        renderOptions = RenderOptionsPayload(
            size: recommendationSummary["size"]?.stringValue ?? template?.defaultSize,
            xscale: recommendationSummary["xscale"]?.stringValue,
            yscale: recommendationSummary["yscale"]?.stringValue,
            reverseX: recommendationSummary["reverse_x"]?.boolValue ?? false,
            seriesOrder: nil,
            xLabelOverride: nil,
            yLabelOverride: nil,
            baseline: recommendationSummary["baseline"]?.stringValue,
            showColorbar: recommendationSummary["show_colorbar"]?.boolValue,
            stylePreset: defaultStyle(for: template),
            palettePreset: defaultPalette(for: template),
            useSidecar: recommendationSummary["use_sidecar"]?.boolValue ?? true,
            visualThemeID: preservedThemeID
        )
        notifyRenderOptionsDidChange()
    }

    func recommendedPreviewConfigSummary(for templateID: String) -> [String: JSONValue] {
        let selected = inspectionResponse?.inspection.recommendations.first { $0.templateID == templateID }
            ?? compatibleRecommendations.first { $0.templateID == templateID }
            ?? inspectionResponse?.inspection.recommendations.first
            ?? inspectionResponse?.inspection.primaryRecommendation.first
        return selected?.previewConfigSummary ?? [:]
    }

    func defaultStyle(for template: MetaTemplateSummary?) -> String {
        if let template, template.availableStyles.contains(renderOptions.stylePreset) {
            return renderOptions.stylePreset
        }

        if let template, let defaultStyle = metadata?.defaults.stylePreset, template.availableStyles.contains(defaultStyle) {
            return defaultStyle
        }

        return template?.availableStyles.first ?? metadata?.defaults.stylePreset ?? "nature"
    }

    func defaultPalette(for template: MetaTemplateSummary?) -> String {
        if let template, template.availablePalettes.contains(renderOptions.palettePreset) {
            return renderOptions.palettePreset
        }

        if let template, let defaultPalette = metadata?.defaults.palettePreset, template.availablePalettes.contains(defaultPalette) {
            return defaultPalette
        }

        return template?.availablePalettes.first ?? metadata?.defaults.palettePreset ?? "colorblind_safe"
    }

    func sanitizeRenderOptionsForCurrentTemplateIfNeeded() {
        var resolved = renderOptions

        if let template = selectedTemplateSummary {
            if !template.availableStyles.contains(resolved.stylePreset) {
                resolved.stylePreset = defaultStyle(for: template)
            }
            if !template.availablePalettes.contains(resolved.palettePreset) {
                resolved.palettePreset = defaultPalette(for: template)
            }
        } else if let metadata {
            let validStyles = Set(metadata.styles.map(\.id))
            let validPalettes = Set(metadata.palettes.map(\.id))

            if !validStyles.contains(resolved.stylePreset) {
                resolved.stylePreset = validStyles.contains(metadata.defaults.stylePreset)
                    ? metadata.defaults.stylePreset
                    : (metadata.styles.first?.id ?? "nature")
            }
            if !validPalettes.contains(resolved.palettePreset) {
                resolved.palettePreset = validPalettes.contains(metadata.defaults.palettePreset)
                    ? metadata.defaults.palettePreset
                    : (metadata.palettes.first?.id ?? "colorblind_safe")
            }
        }

        guard resolved != renderOptions else {
            return
        }
        renderOptions = resolved
        notifyRenderOptionsDidChange()
    }

    func suggestedPlotExportFilename(
        templateID: String,
        format: ExportGraphicFormat,
        isMultiOutput: Bool
    ) -> String {
        if !isMultiOutput,
           let latest = userExportURLs.first
        {
            return NativeExportCoordinator.suggestedGraphicFilename(
                from: latest.lastPathComponent,
                format: format
            )
        }
        if !isMultiOutput,
           let exportResponse,
           let firstOutput = exportResponse.outputs.first
        {
            return NativeExportCoordinator.suggestedGraphicFilename(
                from: URL(fileURLWithPath: firstOutput).lastPathComponent,
                format: format
            )
        }
        if let selectedFileURL {
            let stem = "\(selectedFileURL.deletingPathExtension().lastPathComponent)_\(templateID)"
            return NativeExportCoordinator.suggestedGraphicFilename(from: stem, format: format)
        }
        return NativeExportCoordinator.suggestedGraphicFilename(from: templateID, format: format)
    }

    func isMultiOutputTemplate(templateID: String) -> Bool {
        guard templateID == "point_line" || templateID == "curve" else {
            return false
        }
        guard let model = inspectionResponse?.inspection.model else {
            return false
        }
        return model == "frequency_sweep" || model == "temperature_sweep" || model == "stress_relaxation"
    }

    func exampleDataTemplateURL(named filename: String) throws -> URL {
        let rootURL = try RepoLocator().locateRepositoryRoot()
        let url = rootURL
            .appendingPathComponent("examples", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    func availableExampleDataTemplateURLs() throws -> [URL] {
        try [
            "curve_table.csv",
            "replicate_table.csv",
        ].map(exampleDataTemplateURL(named:))
    }

    func invalidateSubmissionArtifacts() {
        preflightResponse = nil
        exportResponse = nil
        userExportURLs = []
    }

    func notifyRenderOptionsDidChange() {
        renderOptionsDidChange?(renderOptions)
    }
}
