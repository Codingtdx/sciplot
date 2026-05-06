import Foundation

extension ComposerSession {
    struct ProjectSnapshot: Equatable {
        let project: ComposerRequestPayload
    }

    var currentProjectSnapshot: ProjectSnapshot? {
        guard hasProjectContent else {
            return nil
        }
        return ProjectSnapshot(project: project)
    }

    var isProjectDirty: Bool {
        guard let currentProjectSnapshot else {
            return false
        }
        guard let lastSavedProjectSnapshot = runtimeState.lastSavedProjectSnapshot else {
            return true
        }
        return currentProjectSnapshot != lastSavedProjectSnapshot
    }

    var hasProjectContent: Bool {
        !project.panels.isEmpty || !project.regions.isEmpty || !project.texts.isEmpty
    }

    func buildProjectPayload(projectDisplayName: String?) -> ComposerProjectPayload? {
        guard hasProjectContent else {
            return nil
        }
        return ComposerProjectPayload(
            sessionKind: "composer",
            version: 2,
            project: project,
            embeddedPanels: [],
            projectDisplayName: projectDisplayName
        )
    }

    func emptyProjectPayload(projectDisplayName: String?) -> ComposerProjectPayload {
        ComposerProjectPayload(
            sessionKind: "composer",
            version: 2,
            project: ComposerRequestPayload(),
            embeddedPanels: [],
            projectDisplayName: projectDisplayName
        )
    }

    func restoreProjectPayload(_ payload: ComposerProjectPayload) {
        asyncCoordination.preview.cancel()
        project = payload.project
        previewResponse = nil
        exportURL = nil
        errorMessage = nil
        activeDragPanelID = nil
        runtimeState.selectionAnchorCell = nil
        let previousFocusedPanelID = focusedPanelID
        focusedPanelID = previousFocusedPanelID.flatMap { panelID in
            project.panels.contains(where: { $0.id == panelID }) ? panelID : nil
        } ?? project.panels.first?.id
        let previousSelectedRegionID = selectedRegionID
        selectedRegionID = previousSelectedRegionID.flatMap { regionID in
            project.regions.contains(where: { $0.id == regionID }) ? regionID : nil
        }
        selectedCells = []
        undoManager?.removeAllActions(withTarget: self)
        runtimeState.lastSavedProjectSnapshot = currentProjectSnapshot
        if hasProjectContent {
            schedulePreview()
        }
    }

    func markProjectSaved(_ payload: ComposerProjectPayload?) {
        if let payload {
            project = payload.project
        }
        runtimeState.lastSavedProjectSnapshot = currentProjectSnapshot
    }

    func newSession() {
        asyncCoordination.preview.cancel()
        project = ComposerRequestPayload()
        previewResponse = nil
        exportURL = nil
        errorMessage = nil
        focusedPanelID = nil
        selectedRegionID = nil
        selectedCells = []
        activeDragPanelID = nil
        isImportMenuPresented = false
        isImportPresented = false
        isPreviewing = false
        isExporting = false
        runtimeState.selectionAnchorCell = nil
        runtimeState.lastSavedProjectSnapshot = nil
        undoManager?.removeAllActions(withTarget: self)
    }
}
