import Foundation

extension DataStudioSession {
    func beginImportFlow() {
        clearImportFlowError()
        if hasSessionContent {
            pendingImportDisposition = .addToCurrentSession
            importFlow = .wizard(step: .scope)
        } else {
            pendingImportDisposition = .addToCurrentSession
            importFlow = .wizard(step: .kind)
        }
    }

    func chooseImportDisposition(_ disposition: DataStudioImportDisposition) {
        clearImportFlowError()
        pendingImportDisposition = disposition
        importFlow = .wizard(step: .kind)
    }

    func chooseImportKind(_ kind: DataStudioImportKind) {
        clearImportFlowError()
        pendingImportKind = kind
        importFlow = .idle
        scheduleImportPanelPresentation()
    }

    func dismissImportScope() {
        clearImportFlowError()
        importFlow = .idle
        pendingImportDisposition = .addToCurrentSession
    }

    func dismissImportChooser() {
        clearImportFlowError()
        importFlow = .idle
        pendingImportDisposition = .addToCurrentSession
        pendingImportKind = .rawFiles
    }

    func goBackInImportWizard() {
        switch importWizardStep {
        case .scope:
            break
        case .kind:
            if hasSessionContent {
                importFlow = .wizard(step: .scope)
            }
        case .resolver:
            importFlow = .wizard(step: .kind)
        case .createTemplate:
            returnToImportResolver()
        }
    }

    func dismissImportWizard() {
        clearImportFlowError()
        resetImportPresentationState()
        discardPendingSourcePreview()
    }

    func handleImportPanelResult(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            Task { await handleImportedFiles(urls) }
        case let .failure(error):
            handleImportPanelFailure(error)
        }
    }

    func handleImportPanelFailure(_ error: Error) {
        resetImportPresentationState()
        if isUserCancellationError(error) {
            clearImportFlowError()
            return
        }
        errorMessage = error.localizedDescription
    }

    func handleImportedFiles(_ urls: [URL]) async {
        if let projectURL = urls.first(where: { FileTypeCatalog.isProjectURL($0) }) {
            if let openProjectDocumentHandler {
                await openProjectDocumentHandler(projectURL)
            } else {
                await openProject(projectURL)
            }
            return
        }
        switch pendingImportKind {
        case .rawFiles:
            await handleImportedRawFiles(urls)
        case .existingWorkbook:
            await handleImportedWorkbooks(urls)
        }
    }

    func openProject(_ url: URL) async {
        guard let client else {
            errorMessage = "The sidecar is not ready yet."
            return
        }
        do {
            let response = try await client.openProject(.init(projectPath: url.path))
            await restoreProject(from: response)
        } catch {
            if isUserCancellationError(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func handleImportedRawFiles(_ urls: [URL]) async {
        guard let sampleURL = urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first, let client else {
            return
        }
        if pendingImportDisposition == .startNewSession {
            resetContentState()
        }
        importedSourceURLs = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        currentActivity = .previewingSource
        errorMessage = nil
        defer {
            currentActivity = .idle
            pendingImportDisposition = .addToCurrentSession
        }
        do {
            if templates.isEmpty {
                let response = try await client.fetchDataStudioTemplates()
                templates = response.templates.sorted {
                    $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                }
            }
            let importProfile = try await client.importPreview(
                .init(inputPath: sampleURL.path, sheet: .index(0), offset: 0, limit: 50)
            )
            importPreview = importProfile
            if importProfile.status != "enabled" {
                sourcePreview = nil
                recommendedTemplateMatches = []
                selectedTemplateID = nil
                importFlow = .wizard(step: .resolver)
                return
            }
            let basePreview = try await client.sourceTablePreview(
                .init(inputPath: sampleURL.path, sheet: .index(0), offset: 0, limit: 50)
            )
            let resolvedPreview: SourceTablePreviewResponse
            if let firstSegment = basePreview.segments.first {
                resolvedPreview = try await client.sourceTablePreview(
                    .init(
                        inputPath: sampleURL.path,
                        sheet: basePreview.sheet,
                        offset: 0,
                        limit: 50,
                        encoding: basePreview.encoding,
                        delimiter: basePreview.delimiter,
                        segmentID: firstSegment.id
                    )
                )
            } else {
                resolvedPreview = basePreview
            }
            sourcePreview = resolvedPreview
            selectedPreviewSegmentID = resolvedPreview.selectedSegmentID ?? resolvedPreview.segments.first?.id
            selectedPreviewSheetName = resolvedPreview.sheet.displayString
            selectedPreviewBlockID = selectedPreviewSegmentID
            configureDraftDefaults(from: resolvedPreview, sampleURL: sampleURL)
            let recommendationResponse = try? await client.recommendDataStudioTemplates(
                .init(
                    sourcePath: sampleURL.path,
                    importProfile: importProfile.profile,
                    importDiagnostics: importProfile.diagnostics,
                    selectedSheetOrSegment: importProfile.selectedSheetOrSegment
                )
            )
            recommendedTemplateMatches = rankedRecommendedMatches(
                recommendationResponse?.matches ?? [],
                availableTemplates: templates
            )
            selectedTemplateID = recommendedTemplateMatches.first?.templateID
            importFlow = .wizard(step: .resolver)
        } catch {
            if isUserCancellationError(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func importWithSelectedTemplate() async {
        guard let selectedTemplateID else {
            errorMessage = "Choose a parse template before importing the current raw files."
            return
        }
        importFlow = .idle
        await Task.yield()
        await buildWorkbookFromPendingRawFiles(templateID: selectedTemplateID)
    }

    func handleImportedWorkbooks(_ urls: [URL], refreshContext: Bool = true) async {
        guard let client else {
            return
        }
        let sorted = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !sorted.isEmpty else {
            return
        }
        if pendingImportDisposition == .startNewSession {
            resetContentState()
        }
        isBusy = true
        currentActivity = .importingWorkbooks
        errorMessage = nil
        defer {
            isBusy = false
            currentActivity = .idle
            pendingImportDisposition = .addToCurrentSession
        }
        do {
            for url in sorted {
                let imported = try await client.importDataStudioWorkbook(.init(workbookPath: url.path))
                if imported.workbooks.isEmpty {
                    throw NSError(
                        domain: "DataStudioImport",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) did not resolve to any importable workbook groups."]
                    )
                }
                for workbook in imported.workbooks {
                    upsertWorkbook(workbook, shouldFocus: true)
                }
            }
            if refreshContext {
                await rebuildComparisonContext(refreshWorkbookPreviews: true)
                autoOpenFocusedWorkbookInPlotIfComparisonUnavailable()
            }
            resetImportPresentationState()
            discardPendingSourcePreview()
        } catch {
            if isUserCancellationError(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func buildWorkbookFromPendingRawFiles(templateID: String) async {
        guard let client else {
            return
        }
        let sourceURLs = importedSourceURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !sourceURLs.isEmpty else {
            errorMessage = "Import raw files before building a workbook."
            return
        }
        let inferredGroupName = inferGroupName(from: sourceURLs)
        let suggestedName = "\(inferredGroupName).xlsx"
        guard let outputURL = chooseWorkbookSaveLocation(suggestedName) else {
            return
        }
        let chosenGroupName = outputURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupName = chosenGroupName.isEmpty ? inferredGroupName : chosenGroupName
        isBusy = true
        currentActivity = .buildingWorkbook
        errorMessage = nil
        defer {
            isBusy = false
            currentActivity = .idle
        }
        do {
            let workbook = try await client.buildDataStudioWorkbook(
                .init(
                    filePaths: sourceURLs.map(\.path),
                    outputPath: outputURL.path,
                    templateID: templateID,
                    groupName: groupName
                )
            )
            upsertWorkbook(workbook, shouldFocus: true)
            await rebuildComparisonContext(refreshWorkbookPreviews: true)
            autoOpenFocusedWorkbookInPlotIfComparisonUnavailable()
            resetImportPresentationState()
            discardPendingSourcePreview()
        } catch {
            if isUserCancellationError(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func scheduleImportPanelPresentation() {
        importPanelPresentationRevision += 1
        let revision = importPanelPresentationRevision
        importFlow = .idle
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.importPanelPresentationRevision == revision else {
                return
            }
            self.importFlow = .importer(kind: self.pendingImportKind)
        }
    }

    func clearImportFlowError() {
        errorMessage = nil
    }

    func resetImportPresentationState() {
        importFlow = .idle
        pendingImportDisposition = .addToCurrentSession
        pendingImportKind = .rawFiles
    }

    func discardPendingSourcePreview() {
        asyncCoordination.sourcePreview.cancel()
        importedSourceURLs = []
        importPreview = nil
        sourcePreview = nil
        recommendedTemplateMatches = []
        templatePreview = nil
        hoveredSuggestionID = nil
        selectedSuggestionIDs = []
        hoveredPreviewRanges = []
        pinnedPreviewRanges = []
        selectedCandidateIDs = []
        templateDraftLabel = ""
        templateDraftDescription = ""
        templateDraftOutputKind = "curve_metrics"
        templateDraftComparisonEnabled = false
        templateDraftXColumnName = nil
        templateDraftYColumnNames = []
        templateDraftMetricColumnNames = []
        templateDraftSampleNameByYColumn = [:]
        templateDraftBindingLabelByColumn = [:]
        templateDraftUnitHintByColumn = [:]
        templateDraftSourceEncoding = ""
        templateDraftSourceDelimiter = ""
        templateDraftSourceSheetName = ""
        templateDraftSegmentPolicy = "single_table"
        validatedTemplateDraftRequest = nil
        selectedPreviewSheetName = nil
        selectedPreviewBlockID = nil
        selectedPreviewSegmentID = nil
        showAdvancedCandidates = false
        if case .wizard(step: .createTemplate) = importFlow {
            importFlow = .wizard(step: .resolver)
        }
    }

    func stableColumnToken(_ value: String) -> String {
        let pieces = value.lowercased().unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }
        let token = pieces.joined().split(separator: "_").joined(separator: "_")
        return token.isEmpty ? UUID().uuidString : token
    }

    func inferGroupName(from urls: [URL]) -> String {
        guard let first = urls.first else {
            return "DataStudio_Group"
        }
        return first.deletingPathExtension().lastPathComponent
    }

    func autoOpenFocusedWorkbookInPlotIfComparisonUnavailable() {
        guard comparisonSet != nil else {
            return
        }
        guard selectedExportRecipeIDs.isEmpty else {
            return
        }
        guard let focusedWorkbook else {
            return
        }
        openInPlotHandler?(
            focusedWorkbook.workbookURL,
            .name(focusedWorkbook.response.preferredSheet),
            nil,
            nil,
            nil
        )
    }
}

extension SheetValue {
    var displayString: String {
        switch self {
        case let .index(value):
            return String(value)
        case let .name(value):
            return value
        }
    }
}
