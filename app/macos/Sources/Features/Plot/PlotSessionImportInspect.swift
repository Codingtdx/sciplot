import Foundation

extension PlotSession {
    func importFile(_ url: URL) {
        prepareSource(url: url, sheet: .index(0), resetTemplate: true)
        scheduleInspection()
    }

    func importFileAndInspect(_ url: URL) async {
        importFile(url)
        await waitUntilInspectionFinishes(for: url)
    }

    func seedFromDataStudio(workbookURL: URL, preferredSheet: SheetValue) {
        prepareSource(url: workbookURL, sheet: preferredSheet, resetTemplate: true)
        scheduleInspection()
    }

    func setSelectedSheet(_ sheet: SheetValue) {
        guard selectedFileURL != nil else {
            selectedSheet = sheet
            return
        }
        guard selectedSheet != sheet || needsInspection else {
            return
        }
        let previousSnapshot = undoSnapshot()
        selectedSheet = sheet
        _ = asyncCoordination.preview.beginNow()
        isPreviewing = false
        invalidateSubmissionArtifacts()
        errorMessage = nil
        scheduleInspection()
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Change Sheet")
    }

    func selectSheetAndReinspect(_ sheet: SheetValue) async {
        setSelectedSheet(sheet)
        guard selectedFileURL != nil else {
            return
        }
        await waitUntilInspectionFinishes(for: selectedFileURL)
    }

    func clearPreviewContext(preserveRenderOptions: Bool = true) {
        cancelInspectionTask()
        cancelPreviewTask()
        selectedFileURL = nil
        selectedSheet = .index(0)
        inspectionResponse = nil
        previewResponse = nil
        preflightResponse = nil
        exportResponse = nil
        userExportURLs = []
        errorMessage = nil
        isInspecting = false
        isPreviewing = false
        isRunningPreflight = false
        isExporting = false
        selectedTemplateID = nil
        runtimeState.inspectedInputPath = nil
        runtimeState.inspectedSheet = nil
        if !preserveRenderOptions {
            renderOptions = RenderOptionsPayload(
                stylePreset: metadata?.defaults.stylePreset ?? "nature",
                palettePreset: metadata?.defaults.palettePreset ?? "colorblind_safe",
                visualThemeID: nil
            )
            notifyRenderOptionsDidChange()
        }
    }

    func chooseTemplate(_ templateID: String) {
        let migratedTemplateID = migrateLegacyTemplateID(templateID) ?? templateID
        guard selectedTemplateID != migratedTemplateID else {
            return
        }
        let previousSnapshot = undoSnapshot()
        setTemplate(migratedTemplateID, shouldResetRenderOptions: true)
        schedulePreviewRefresh(policy: .immediate)
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Change Template")
    }

    func updateRenderOptions(
        policy: PlotPreviewRefreshPolicy = .debounced,
        mutate: (inout RenderOptionsPayload) -> Void
    ) {
        let previousSnapshot = undoSnapshot()
        mutate(&renderOptions)
        guard previousSnapshot.renderOptions != renderOptions else {
            return
        }
        notifyRenderOptionsDidChange()
        invalidateSubmissionArtifacts()
        errorMessage = nil
        schedulePreviewRefresh(policy: policy)
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Edit Plot Options")
    }

    func cancelInspectionTask() {
        asyncCoordination.inspection.cancel()
    }

    func waitUntilInspectionFinishes(for _: URL?) async {
        await asyncCoordination.inspection.wait()
    }

    func prepareSource(url: URL, sheet: SheetValue, resetTemplate: Bool) {
        cancelInspectionTask()
        _ = asyncCoordination.preview.beginNow()
        isPreviewing = false
        selectedFileURL = url
        selectedSheet = sheet
        inspectionResponse = nil
        runtimeState.inspectedInputPath = nil
        runtimeState.inspectedSheet = nil
        if resetTemplate {
            selectedTemplateID = nil
        }
        runtimeState.stagedExternalPinnedSheet = nil
        runtimeState.stagedExternalPinnedTemplateID = nil
        invalidateSubmissionArtifacts()
        errorMessage = nil
    }

    func scheduleInspection() {
        guard let request = currentInspectionRequest() else {
            return
        }

        isInspecting = true
        errorMessage = nil

        asyncCoordination.inspection.schedule { [weak self] revision in
            guard let self else { return }
            await self.performInspection(request: request, revision: revision)
        }
    }

    func performInspection(request: FileRequest, revision: Int) async {
        guard let client else {
            if asyncCoordination.inspection.isLatest(revision) {
                isInspecting = false
            }
            return
        }

        do {
            let response = try await client.inspectFile(request)
            guard asyncCoordination.inspection.isLatest(revision), !Task.isCancelled else {
                return
            }
            applyInspectionResponse(response)
            isInspecting = false
        } catch {
            guard asyncCoordination.inspection.isLatest(revision), !Task.isCancelled else {
                return
            }
            if isUserCancellationError(error) {
                errorMessage = nil
                isInspecting = false
                return
            }
            errorMessage = error.localizedDescription
            isInspecting = false
        }
    }

    func applyInspectionResponse(_ response: InspectFileResponse) {
        inspectionResponse = response
        let resolvedSheet = runtimeState.stagedExternalPinnedSheet ?? response.sheet
        selectedSheet = resolvedSheet
        runtimeState.inspectedInputPath = response.inputPath
        runtimeState.inspectedSheet = resolvedSheet
        invalidateSubmissionArtifacts()
        errorMessage = nil

        if shouldAutoSelectTemplate(after: response, preservingTemplateID: runtimeState.stagedExternalPinnedTemplateID) {
            let preferredTemplateID = response.inspection.recommendations.first?.templateID
                ?? response.inspection.primaryRecommendation.first?.templateID
                ?? selectedTemplateID
            if let preferredTemplateID {
                setTemplate(preferredTemplateID, shouldResetRenderOptions: true)
            }
        }

        schedulePreviewRefresh(policy: .immediate)
    }

    func shouldAutoSelectTemplate(
        after _: InspectFileResponse,
        preservingTemplateID: String? = nil
    ) -> Bool {
        if let preservingTemplateID, selectedTemplateID == preservingTemplateID {
            return false
        }
        guard let selectedTemplateID else {
            return true
        }
        return !compatibleTemplateIDs.contains(selectedTemplateID)
    }

    func currentInspectionRequest() -> FileRequest? {
        guard let selectedFileURL else {
            return nil
        }
        return .init(inputPath: selectedFileURL.path, sheet: selectedSheet)
    }
}
