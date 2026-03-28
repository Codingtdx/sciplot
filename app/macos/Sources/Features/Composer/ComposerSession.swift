import Foundation
import Observation

enum ComposerStage: String, CaseIterable, Identifiable {
    case assets
    case compose
    case review
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assets:
            return "Assets"
        case .compose:
            return "Compose"
        case .review:
            return "Review"
        case .export:
            return "Export"
        }
    }
}

enum ComposerImportKind: String, CaseIterable, Identifiable {
    case graph
    case asset

    var id: String { rawValue }
}

@MainActor
@Observable
final class ComposerSession {
    @ObservationIgnored private var client: (any SidecarClienting)?
    @ObservationIgnored private weak var undoManager: UndoManager?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var dragSnapshot: ComposerRequestPayload?
    @ObservationIgnored private let previewDelayNanoseconds: UInt64

    var stage: ComposerStage = .compose
    var project = ComposerRequestPayload()
    var previewResponse: ComposerPreviewResponse?
    var exportURL: URL?
    var errorMessage: String?
    var selectedPanelID: String?
    var pendingImportKind: ComposerImportKind = .graph
    var isImportPresented = false
    var isPreviewing = false
    var isExporting = false

    init(previewDelayNanoseconds: UInt64 = 300_000_000) {
        self.previewDelayNanoseconds = previewDelayNanoseconds
    }

    func configure(client: any SidecarClienting) {
        self.client = client
        schedulePreview()
    }

    func attachUndoManager(_ undoManager: UndoManager?) {
        self.undoManager = undoManager
    }

    func beginImport(kind: ComposerImportKind) {
        pendingImportKind = kind
        isImportPresented = true
    }

    func handleImportedAssets(_ urls: [URL]) async {
        guard let client else {
            return
        }

        do {
            let response = try await client.importComposerPanels(
                .init(
                    project: project,
                    filePaths: urls.map(\.path),
                    kind: pendingImportKind.rawValue
                )
            )
            let previous = project
            project = response
            selectedPanelID = project.panels.last?.id
            registerUndo(previousProject: previous, actionName: "Import Panels")
            schedulePreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportComposition() async {
        guard let client else {
            return
        }

        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let response = try await client.composeExport(project)
            exportURL = URL(fileURLWithPath: response.outputPath)
            stage = .export
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealLatestExport() {
        if let exportURL {
            WorkspaceBridge.reveal([exportURL])
        }
    }

    func selectPanel(_ panelID: String?) {
        selectedPanelID = panelID
    }

    func updateSelectedPanel(label: String) {
        mutateProject(actionName: "Edit Panel Label") { project in
            guard let index = project.panels.firstIndex(where: { $0.id == selectedPanelID }) else {
                return
            }
            project.panels[index].label = label.isEmpty ? nil : label
        }
    }

    func updateSelectedPanel(hidden: Bool) {
        mutateProject(actionName: "Toggle Panel Visibility") { project in
            guard let index = project.panels.firstIndex(where: { $0.id == selectedPanelID }) else {
                return
            }
            project.panels[index].hidden = hidden
        }
    }

    func updateSelectedPanel(locked: Bool) {
        mutateProject(actionName: "Toggle Panel Lock") { project in
            guard let index = project.panels.firstIndex(where: { $0.id == selectedPanelID }) else {
                return
            }
            project.panels[index].locked = locked
        }
    }

    func beginPanelDrag() {
        dragSnapshot = project
    }

    func dragSelectedPanel(translation: CGSize, scale: Double) {
        guard let panelID = selectedPanelID else {
            return
        }

        let sourceProject = dragSnapshot ?? project
        guard let index = sourceProject.panels.firstIndex(where: { $0.id == panelID }) else {
            return
        }

        let origin = sourceProject.panels[index]
        project.panels[index].xMm = max(0.0, origin.xMm + Double(translation.width / scale))
        project.panels[index].yMm = max(0.0, origin.yMm + Double(translation.height / scale))
    }

    func endPanelDrag() {
        guard let dragSnapshot else {
            return
        }

        registerUndo(previousProject: dragSnapshot, actionName: "Move Panel")
        self.dragSnapshot = nil
        schedulePreview()
    }

    func schedulePreview() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(nanoseconds: self.previewDelayNanoseconds)
            await self.requestPreview()
        }
    }

    var selectedPanel: ComposerPanelPayload? {
        project.panels.first { $0.id == selectedPanelID }
    }

    private func requestPreview() async {
        guard let client else {
            return
        }

        isPreviewing = true
        defer { isPreviewing = false }

        do {
            previewResponse = try await client.composePreview(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mutateProject(actionName: String, mutation: (inout ComposerRequestPayload) -> Void) {
        let previous = project
        mutation(&project)
        registerUndo(previousProject: previous, actionName: actionName)
        schedulePreview()
    }

    private func registerUndo(previousProject: ComposerRequestPayload, actionName: String) {
        guard let undoManager else {
            return
        }

        let currentProject = project
        undoManager.registerUndo(withTarget: self) { session in
            session.project = previousProject
            session.registerUndo(previousProject: currentProject, actionName: actionName)
            session.schedulePreview()
        }
        undoManager.setActionName(actionName)
    }
}
