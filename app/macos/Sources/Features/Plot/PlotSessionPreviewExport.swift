import Foundation

extension PlotSession {
    private var sourceTablePageLimit: Int { 50 }
    private var fitAnalysisPageLimit: Int { 50 }

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

    func openProject(_ url: URL) async {
        guard let client else {
            errorMessage = "The sidecar is not ready yet."
            return
        }
        resetDataWorkbookState()
        errorMessage = nil
        do {
            let response = try await client.openProject(.init(projectPath: url.path))
            await restoreProject(from: response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveProject() async {
        if let projectURL {
            await saveProject(to: projectURL)
            return
        }
        await saveProjectAs()
    }

    func saveProjectAs() async {
        guard let destinationURL = chooseProjectSaveLocation(suggestedProjectFilename) else {
            return
        }
        await saveProject(to: destinationURL)
    }

    func saveProject(to destinationURL: URL) async {
        guard let client else {
            errorMessage = "The sidecar is not ready yet."
            return
        }
        guard let selectedFileURL, let payload = buildProjectPayload() else {
            errorMessage = "Import a plot source before saving a project."
            return
        }
        isSavingProject = true
        errorMessage = nil
        defer { isSavingProject = false }
        do {
            let response = try await client.saveProject(
                .init(
                    projectPath: destinationURL.path,
                    sourcePath: selectedFileURL.path,
                    payload: payload
                )
            )
            if let plotPayload = response.payload.plot {
                applyNormalizedProjectState(
                    plotPayload,
                    projectURL: URL(fileURLWithPath: response.projectPath),
                    scheduleRefresh: false
                )
            } else {
                projectURL = URL(fileURLWithPath: response.projectPath)
                runtimeState.lastSavedProjectSnapshot = currentProjectSnapshot
            }
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
                    fitOptions: fitOptions,
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
        guard !userExportURLs.isEmpty else {
            return
        }
        do {
            try WorkspaceBridge.reveal(userExportURLs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openLatestExport(id: String) {
        guard let item = latestExportItems.first(where: { $0.id == id }) else {
            return
        }
        do {
            try WorkspaceBridge.open(item.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openCurrentSource() {
        guard let selectedFileURL else {
            return
        }
        do {
            try WorkspaceBridge.open(selectedFileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealCurrentSource() {
        guard let selectedFileURL else {
            return
        }
        do {
            try WorkspaceBridge.reveal([selectedFileURL])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openExampleDataTemplate(named filename: String) {
        do {
            try WorkspaceBridge.open(exampleDataTemplateURL(named: filename))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealExampleDataTemplates() {
        do {
            try WorkspaceBridge.reveal(availableExampleDataTemplateURLs())
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
            if isUserCancellationError(error) {
                errorMessage = nil
                isPreviewing = false
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
            options: renderOptions,
            fitOptions: fitOptions
        )
    }

    func resetRenderOptions(for templateID: String) {
        let template = metadata?.templates.first { $0.id == templateID }
        let recommendationSummary = recommendedPreviewConfigSummary(for: templateID)
        let resolvedStyle = defaultStyle(
            for: template,
            recommendedStyleID: recommendationSummary["style_preset"]?.stringValue
        )

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
            stylePreset: resolvedStyle,
            palettePreset: defaultPalette(
                for: template,
                recommendedPaletteID: recommendationSummary["palette_preset"]?.stringValue,
                styleID: resolvedStyle
            ),
            useSidecar: recommendationSummary["use_sidecar"]?.boolValue ?? true,
            visualThemeID: defaultThemeID(
                for: template,
                recommendedThemeID: recommendationSummary["visual_theme_id"]?.stringValue,
                styleID: resolvedStyle
            )
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

    func styleSummary(for styleID: String) -> MetaStyleResponse? {
        metadata?.styles.first { $0.id == styleID }
    }

    func defaultStyle(for template: MetaTemplateSummary?, recommendedStyleID: String? = nil) -> String {
        if let template,
           let recommendedStyleID,
           template.availableStyles.contains(recommendedStyleID)
        {
            return recommendedStyleID
        }

        if let template,
           let defaultStyle = template.defaultOptions["style_preset"]?.stringValue,
           template.availableStyles.contains(defaultStyle)
        {
            return defaultStyle
        }

        if let template, let defaultStyle = metadata?.defaults.stylePreset, template.availableStyles.contains(defaultStyle) {
            return defaultStyle
        }

        return template?.availableStyles.first ?? metadata?.defaults.stylePreset ?? "nature"
    }

    func recommendedPalette(for styleID: String, template: MetaTemplateSummary? = nil) -> String {
        let fallback = template?.availablePalettes.first ?? metadata?.defaults.palettePreset ?? "colorblind_safe"
        guard let recommendedPaletteID = styleSummary(for: styleID)?.recommendedPalettePreset else {
            return fallback
        }
        if let template, template.availablePalettes.contains(recommendedPaletteID) {
            return recommendedPaletteID
        }
        guard let metadata, metadata.palettes.contains(where: { $0.id == recommendedPaletteID }) else {
            return fallback
        }
        return recommendedPaletteID
    }

    func defaultPalette(
        for template: MetaTemplateSummary?,
        recommendedPaletteID: String? = nil,
        styleID: String? = nil
    ) -> String {
        if let template,
           let recommendedPaletteID,
           template.availablePalettes.contains(recommendedPaletteID)
        {
            return recommendedPaletteID
        }

        if let styleID {
            return recommendedPalette(for: styleID, template: template)
        }

        if let template,
           let defaultPalette = template.defaultOptions["palette_preset"]?.stringValue,
           template.availablePalettes.contains(defaultPalette)
        {
            return defaultPalette
        }

        if let template, let defaultPalette = metadata?.defaults.palettePreset, template.availablePalettes.contains(defaultPalette) {
            return defaultPalette
        }

        return template?.availablePalettes.first ?? metadata?.defaults.palettePreset ?? "colorblind_safe"
    }

    func styleRecommendedThemeID(for styleID: String) -> String? {
        let validThemeIDs = Set(metadata?.visualThemes.map(\.id) ?? [])
        guard let themeID = styleSummary(for: styleID)?.recommendedVisualThemeID else {
            return metadata?.visualThemes.first?.id
        }
        return validThemeIDs.contains(themeID) ? themeID : metadata?.visualThemes.first?.id
    }

    func defaultThemeID(
        for template: MetaTemplateSummary?,
        recommendedThemeID: String? = nil,
        styleID: String? = nil
    ) -> String? {
        let validThemeIDs = Set(metadata?.visualThemes.map(\.id) ?? [])
        if let recommendedThemeID, validThemeIDs.contains(recommendedThemeID) {
            return recommendedThemeID
        }
        if let styleID, let recommendedThemeID = styleRecommendedThemeID(for: styleID), validThemeIDs.contains(recommendedThemeID) {
            return recommendedThemeID
        }
        if let template,
           let defaultThemeID = template.defaultOptions["visual_theme_id"]?.stringValue,
           validThemeIDs.contains(defaultThemeID)
        {
            return defaultThemeID
        }
        return metadata?.visualThemes.first?.id
    }

    func selectStylePreset(_ styleID: String) {
        let template = selectedTemplateSummary
        updateRenderOptions(policy: .immediate) { options in
            options.stylePreset = styleID
            options.palettePreset = recommendedPalette(for: styleID, template: template)
            options.visualThemeID = styleRecommendedThemeID(for: styleID)
        }
    }

    func normalizedRenderOptionsForCurrentTemplate(_ options: RenderOptionsPayload) -> RenderOptionsPayload {
        var resolved = options
        resolved.xAxisBreaks = normalizedAxisBreaks(resolved.xAxisBreaks)
        resolved.yAxisBreaks = normalizedAxisBreaks(resolved.yAxisBreaks)

        if let template = selectedTemplateSummary {
            if !template.availableStyles.contains(resolved.stylePreset) {
                resolved.stylePreset = defaultStyle(for: template)
            }
            if !template.availablePalettes.contains(resolved.palettePreset) {
                resolved.palettePreset = defaultPalette(for: template, styleID: resolved.stylePreset)
            }
            let validThemeIDs = Set(metadata?.visualThemes.map(\.id) ?? [])
            if resolved.visualThemeID == nil || !validThemeIDs.contains(resolved.visualThemeID ?? "") {
                resolved.visualThemeID = defaultThemeID(for: template, styleID: resolved.stylePreset)
            }
            if !template.editableOptions.contains("extra_x_axis") {
                resolved.extraXAxis = nil
            } else {
                resolved.extraXAxis?.bindingMode = "conversion"
                resolved.extraXAxis?.seriesIDs = []
            }
            if !template.editableOptions.contains("extra_y_axis") {
                resolved.extraYAxis = nil
            } else {
                let supportsSeriesBinding = Set(["curve", "point_line", "scatter"]).contains(template.id)
                if var extraYAxis = resolved.extraYAxis {
                    if !supportsSeriesBinding {
                        extraYAxis.bindingMode = "conversion"
                    }
                    if extraYAxis.bindingMode != "series_assignment" {
                        extraYAxis.seriesIDs = []
                    } else {
                        let validSeriesIDs = Set(seriesAssignmentCandidateIDs)
                        if !validSeriesIDs.isEmpty {
                            extraYAxis.seriesIDs = extraYAxis.seriesIDs.filter { validSeriesIDs.contains($0) }
                        }
                    }
                    resolved.extraYAxis = extraYAxis
                }
            }
            if !template.editableOptions.contains("x_axis_breaks") || (resolved.xscale ?? "linear") != "linear" {
                resolved.xAxisBreaks = nil
            }
            if !template.editableOptions.contains("y_axis_breaks") || (resolved.yscale ?? "linear") != "linear" {
                resolved.yAxisBreaks = nil
            }
        } else if let metadata {
            let validStyles = Set(metadata.styles.map(\.id))
            let validPalettes = Set(metadata.palettes.map(\.id))
            let validThemes = Set(metadata.visualThemes.map(\.id))

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
            if resolved.visualThemeID == nil || !validThemes.contains(resolved.visualThemeID ?? "") {
                resolved.visualThemeID = styleRecommendedThemeID(for: resolved.stylePreset)
            }
            resolved.extraXAxis?.bindingMode = "conversion"
            resolved.extraXAxis?.seriesIDs = []
            resolved.extraYAxis?.bindingMode = "conversion"
            resolved.extraYAxis?.seriesIDs = []
            resolved.xAxisBreaks = nil
            resolved.yAxisBreaks = nil
        }

        if hasEnabledExtraAxes(in: resolved) {
            resolved.xAxisBreaks = nil
            resolved.yAxisBreaks = nil
        }
        if hasEnabledSplitAxisBreaks(in: resolved.xAxisBreaks) {
            resolved.yAxisBreaks = nil
        } else if hasEnabledSplitAxisBreaks(in: resolved.yAxisBreaks) {
            resolved.xAxisBreaks = nil
        }

        return resolved
    }

    func sanitizeRenderOptionsForCurrentTemplateIfNeeded() {
        let resolved = normalizedRenderOptionsForCurrentTemplate(renderOptions)

        guard resolved != renderOptions else {
            return
        }
        renderOptions = resolved
        notifyRenderOptionsDidChange()
    }

    private func hasEnabledExtraAxes(in options: RenderOptionsPayload) -> Bool {
        (options.extraXAxis?.enabled ?? false) || (options.extraYAxis?.enabled ?? false)
    }

    private func normalizedAxisBreaks(_ breaks: [AxisBreakPayload]?) -> [AxisBreakPayload]? {
        guard let breaks, !breaks.isEmpty else {
            return nil
        }
        let displayMode = breaks.first(where: { $0.displayMode == "split" }) != nil ? "split" : "compress"
        return breaks.map { axisBreak in
            var normalized = axisBreak
            normalized.displayMode = displayMode
            return normalized
        }
    }

    private func hasEnabledSplitAxisBreaks(in breaks: [AxisBreakPayload]?) -> Bool {
        guard let breaks else {
            return false
        }
        return breaks.contains { $0.enabled && $0.displayMode == "split" }
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

    func notifyFitOptionsDidChange() {
        fitOptionsDidChange?(fitOptions)
    }

    func buildProjectPayload() -> ProjectBundlePayload? {
        guard let selectedFileURL, let selectedTemplateID = effectiveTemplateID else {
            return nil
        }
        return ProjectBundlePayload(
            version: 1,
            selectedWorkbench: "plot",
            plot: PlotProjectPayload(
                sessionKind: "plot",
                sourceFilename: selectedFileURL.lastPathComponent,
                sourceMediaType: nil,
                embeddedSourceRelpath: "sources/plot/primary/\(selectedFileURL.lastPathComponent)",
                sourceSHA256: "",
                sheet: selectedSheet,
                selectedTemplateID: selectedTemplateID,
                renderOptions: renderOptions,
                fitOptions: fitOptions,
                projectDisplayName: projectURL?.deletingPathExtension().lastPathComponent ?? selectedFileURL.deletingPathExtension().lastPathComponent,
                sourceProvenance: PlotProjectSourceProvenancePayload(
                    originalInputPath: sourceProvenance.originalInputPath ?? selectedFileURL.path,
                    savedInputMtimeNs: sourceProvenance.savedInputMtimeNs ?? sourceProvenanceForCurrentURL(selectedFileURL).savedInputMtimeNs,
                    savedAt: sourceProvenance.savedAt
                )
            ),
            dataStudio: nil,
            composer: nil,
            codeConsole: nil,
            artifacts: ["manifest_relpath": .string("artifacts/manifest.json")]
        )
    }

    func selectDataWorkbookTab(_ tab: PlotDataWorkbookTab) {
        guard dataWorkbookTab != tab else {
            return
        }
        dataWorkbookTab = tab
        refreshDataWorkbookIfNeeded()
    }

    func refreshDataWorkbookIfNeeded() {
        guard isDataWorkbookPresented else {
            return
        }
        switch dataWorkbookTab {
        case .sourceData:
            loadSourceTablePreview(offset: sourceTableOffset)
        case .fit:
            if fitAnalysisAvailability.isEnabled {
                loadFitAnalysis(offset: fitAnalysisOffset)
            }
        }
    }

    func resetDataWorkbookState() {
        sourceTableResponse = nil
        fitAnalysisResponse = nil
        sourceTableErrorMessage = nil
        fitAnalysisErrorMessage = nil
        isLoadingSourceTable = false
        isLoadingFitAnalysis = false
        sourceTableOffset = 0
        fitAnalysisOffset = 0
        fitAnalysisSelectedSeriesID = nil
        dataWorkbookTab = .sourceData
    }

    func loadSourceTablePreview(offset: Int = 0) {
        guard let client, let selectedFileURL else {
            return
        }
        let resolvedOffset = max(0, offset)
        sourceTableOffset = resolvedOffset
        isLoadingSourceTable = true
        sourceTableErrorMessage = nil
        Task {
            do {
                let response = try await client.sourceTablePreview(
                    .init(
                        inputPath: selectedFileURL.path,
                        sheet: selectedSheet,
                        offset: resolvedOffset,
                        limit: sourceTablePageLimit
                    )
                )
                sourceTableResponse = response
                isLoadingSourceTable = false
            } catch {
                if isUserCancellationError(error) {
                    sourceTableErrorMessage = nil
                } else {
                    sourceTableErrorMessage = error.localizedDescription
                }
                isLoadingSourceTable = false
            }
        }
    }

    func pageSourceTable(by delta: Int) {
        let nextOffset = max(0, (sourceTableResponse?.offset ?? sourceTableOffset) + delta * sourceTablePageLimit)
        loadSourceTablePreview(offset: nextOffset)
    }

    func loadFitAnalysis(offset: Int = 0) {
        guard let client, let selectedFileURL else {
            return
        }
        guard fitAnalysisAvailability.isEnabled else {
            fitAnalysisErrorMessage = fitAnalysisAvailability.reason
            return
        }
        let resolvedOffset = max(0, offset)
        fitAnalysisOffset = resolvedOffset
        isLoadingFitAnalysis = true
        fitAnalysisErrorMessage = nil
        Task {
            do {
                let response = try await client.fitAnalysis(
                    .init(
                        inputPath: selectedFileURL.path,
                        sheet: selectedSheet,
                        modelID: fitOptions.modelID,
                        seriesID: fitAnalysisSelectedSeriesID,
                        offset: resolvedOffset,
                        limit: fitAnalysisPageLimit
                    )
                )
                fitAnalysisResponse = response
                isLoadingFitAnalysis = false
            } catch {
                if isUserCancellationError(error) {
                    fitAnalysisErrorMessage = nil
                } else {
                    fitAnalysisErrorMessage = error.localizedDescription
                }
                isLoadingFitAnalysis = false
            }
        }
    }

    func pageFitAnalysis(by delta: Int) {
        let nextOffset = max(0, (fitAnalysisResponse?.offset ?? fitAnalysisOffset) + delta * fitAnalysisPageLimit)
        loadFitAnalysis(offset: nextOffset)
    }

    func selectFitAnalysisSeries(id: String?) {
        fitAnalysisSelectedSeriesID = id
        loadFitAnalysis(offset: 0)
    }

    func sourceProvenanceForCurrentURL(_ url: URL) -> PlotProjectSourceProvenancePayload {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
            .map { Int($0.timeIntervalSince1970 * 1_000_000_000) }
        return PlotProjectSourceProvenancePayload(
            originalInputPath: url.path,
            savedInputMtimeNs: mtime,
            savedAt: nil
        )
    }
}
