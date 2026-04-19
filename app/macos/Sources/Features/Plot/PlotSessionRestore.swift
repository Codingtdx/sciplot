import Foundation

extension PlotSession {
    func loadExternalFigure(
        inputURL: URL,
        sheet: SheetValue,
        preferredTemplateID: String? = nil,
        preferredOptions: RenderOptionsPayload? = nil
    ) async {
        stageExternalFigure(
            inputURL: inputURL,
            sheet: sheet,
            preferredTemplateID: preferredTemplateID,
            preferredOptions: preferredOptions
        )
        await finishLoadingStagedExternalFigure(
            preferredTemplateID: preferredTemplateID,
            preferredOptions: preferredOptions
        )
    }

    func stageExternalFigure(
        inputURL: URL,
        sheet: SheetValue,
        preferredTemplateID: String? = nil,
        preferredOptions: RenderOptionsPayload? = nil
    ) {
        prepareSource(url: inputURL, sheet: sheet, resetTemplate: true)
        runtimeState.stagedExternalPinnedSheet = sheet
        let migratedTemplateID = migrateLegacyTemplateID(preferredTemplateID)
        runtimeState.stagedExternalPinnedTemplateID = migratedTemplateID
        if let migratedTemplateID {
            selectedTemplateID = migratedTemplateID
        }
        if let preferredOptions {
            renderOptions = preferredOptions
            notifyRenderOptionsDidChange()
        }
    }

    func finishLoadingStagedExternalFigure(
        preferredTemplateID: String? = nil,
        preferredOptions: RenderOptionsPayload? = nil,
        expectedInputURL: URL? = nil,
        expectedSheet: SheetValue? = nil
    ) async {
        guard let inputURL = expectedInputURL ?? selectedFileURL else {
            return
        }
        defer {
            runtimeState.stagedExternalPinnedSheet = nil
            runtimeState.stagedExternalPinnedTemplateID = nil
        }
        let targetSheet = expectedSheet ?? selectedSheet
        scheduleInspection()
        await waitUntilInspectionFinishes(for: inputURL)
        guard errorMessage == nil else {
            return
        }
        guard selectedFileURL == inputURL, selectedSheet == targetSheet else {
            return
        }

        var didResetRenderOptionsDuringTemplateSelection = false
        if let preferredTemplateID = migrateLegacyTemplateID(preferredTemplateID),
           selectedTemplateID != preferredTemplateID,
           (compatibleTemplateIDs.contains(preferredTemplateID) || templateSummary(for: preferredTemplateID) != nil)
        {
            chooseTemplate(preferredTemplateID)
            didResetRenderOptionsDuringTemplateSelection = true
        }
        guard selectedFileURL == inputURL, selectedSheet == targetSheet else {
            return
        }

        if let preferredOptions {
            cancelPreviewTask()
            isPreviewing = false
            applyExternalRenderOptions(preferredOptions)
        } else if selectedTemplateID != nil {
            if !didResetRenderOptionsDuringTemplateSelection {
                cancelPreviewTask()
                isPreviewing = false
                resetCurrentTemplateRenderOptionsForExternalFigure()
            }
            await waitUntilPreviewFinishes(for: inputURL)
        } else {
            await waitUntilPreviewFinishes(for: inputURL)
        }
    }

    func resetCurrentTemplateRenderOptionsForExternalFigure() {
        guard let selectedTemplateID else {
            return
        }
        setTemplate(selectedTemplateID, shouldResetRenderOptions: true)
        schedulePreviewRefresh(policy: .immediate)
    }

    func applyExternalRenderOptions(_ options: RenderOptionsPayload) {
        guard let template = selectedTemplateSummary else {
            renderOptions = options
            notifyRenderOptionsDidChange()
            schedulePreviewRefresh(policy: .immediate)
            return
        }

        var resolved = options
        resolved.size = template.allowedSizes.contains(options.size ?? "") ? options.size : template.defaultSize
        if !template.availableStyles.contains(resolved.stylePreset) {
            resolved.stylePreset = defaultStyle(for: template)
        }
        if !template.availablePalettes.contains(resolved.palettePreset) {
            resolved.palettePreset = defaultPalette(for: template)
        }
        let validThemeIDs = Set(metadata?.visualThemes.map(\.id) ?? [])
        if resolved.visualThemeID == nil || !validThemeIDs.contains(resolved.visualThemeID ?? "") {
            resolved.visualThemeID = defaultThemeID(for: template)
        }
        renderOptions = resolved
        notifyRenderOptionsDidChange()
        invalidateSubmissionArtifacts()
        errorMessage = nil
        schedulePreviewRefresh(policy: .immediate)
    }

    func undoSnapshot() -> UndoSnapshot {
        UndoSnapshot(
            selectedSheet: selectedSheet,
            selectedTemplateID: selectedTemplateID,
            renderOptions: renderOptions
        )
    }

    func registerUndo(previousSnapshot: UndoSnapshot, actionName: String) {
        guard let undoManager else {
            return
        }
        guard !runtimeState.isApplyingUndoRedo else {
            return
        }

        let currentSnapshot = undoSnapshot()
        guard currentSnapshot != previousSnapshot else {
            return
        }

        undoManager.registerUndo(withTarget: self) { session in
            session.runtimeState.isApplyingUndoRedo = true
            session.restore(from: previousSnapshot)
            session.runtimeState.isApplyingUndoRedo = false
            session.registerUndo(previousSnapshot: currentSnapshot, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    func restore(from snapshot: UndoSnapshot) {
        selectedSheet = snapshot.selectedSheet
        selectedTemplateID = migrateLegacyTemplateID(snapshot.selectedTemplateID)
        renderOptions = snapshot.renderOptions
        notifyRenderOptionsDidChange()
        invalidateSubmissionArtifacts()
        errorMessage = nil

        guard selectedFileURL != nil else {
            return
        }
        if needsInspection {
            scheduleInspection()
        } else {
            schedulePreviewRefresh(policy: .immediate)
        }
    }
}
