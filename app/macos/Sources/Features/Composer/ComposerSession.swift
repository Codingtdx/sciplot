import Foundation
import Observation

@MainActor
@Observable
final class ComposerSession {
    typealias ComposerExportFormatChooser = @MainActor () -> ExportGraphicFormat?
    typealias ComposerExportDestinationChooser = @MainActor (_ suggestedName: String, _ format: ExportGraphicFormat) -> URL?
    typealias ComposerExportMaterializer = @MainActor (_ intermediatePDFURL: URL, _ destinationURL: URL) throws -> Void

    struct RuntimeState {
        var selectionAnchorCell: ComposerGridCell?
        var lastSavedProjectSnapshot: ProjectSnapshot?
    }

    @MainActor
    final class AsyncCoordination {
        let preview = AsyncLatestTaskCoordinator()
    }

    @ObservationIgnored var client: (any SidecarClienting)?
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored var runtimeState = RuntimeState()
    @ObservationIgnored let asyncCoordination = AsyncCoordination()
    @ObservationIgnored let previewDelayNanoseconds: UInt64
    @ObservationIgnored let chooseExportFormat: ComposerExportFormatChooser
    @ObservationIgnored let chooseExportDestination: ComposerExportDestinationChooser
    @ObservationIgnored let materializeExport: ComposerExportMaterializer

    var project = ComposerRequestPayload()
    var previewResponse: ComposerPreviewResponse?
    var exportURL: URL?
    var errorMessage: String?
    var focusedPanelID: String?
    var selectedRegionID: String?
    var selectedCells: Set<ComposerGridCell> = []
    var pendingImportKind: ComposerImportKind = .graph
    var isImportMenuPresented = false
    var isImportPresented = false
    var isPreviewing = false
    var isExporting = false
    var activeDragPanelID: String?

    var exportAvailability: ActionAvailability {
        if isExporting {
            return .disabled("Export is already in progress.")
        }
        guard client != nil else {
            return .disabled("The sidecar is not ready yet.")
        }
        guard !project.panels.isEmpty else {
            return .disabled("Import at least one panel before exporting.")
        }
        if previewResponse?.exportPreflight?.status == "blocked" {
            return .disabled(previewResponse?.exportPreflight?.help ?? "Resolve Composer export preflight blockers.")
        }
        return .enabled()
    }

    var revealOutputAvailability: ActionAvailability {
        guard exportURL != nil else {
            return .disabled("Export a composition first.")
        }
        return .enabled()
    }

    var latestExportItems: [ExportedFileItem] {
        guard let exportURL else {
            return []
        }
        return [ExportedFileItem(url: exportURL)]
    }

    init(
        previewDelayNanoseconds: UInt64 = 300_000_000,
        chooseExportFormat: @escaping ComposerExportFormatChooser = {
            NativeExportCoordinator.chooseComposerExportFormat()
        },
        chooseExportDestination: @escaping ComposerExportDestinationChooser = {
            NativeExportCoordinator.chooseComposerExportLocation(suggestedName: $0, format: $1)
        },
        materializeExport: @escaping ComposerExportMaterializer = {
            try NativeExportCoordinator.materializeComposerExport(
                intermediatePDFURL: $0,
                destinationURL: $1
            )
        }
    ) {
        self.previewDelayNanoseconds = previewDelayNanoseconds
        self.chooseExportFormat = chooseExportFormat
        self.chooseExportDestination = chooseExportDestination
        self.materializeExport = materializeExport
    }

    func configure(client: any SidecarClienting) {
        self.client = client
        if hasPreviewableContent {
            schedulePreview()
        }
    }

    private var hasPreviewableContent: Bool {
        !project.panels.isEmpty || !project.regions.isEmpty || !project.texts.isEmpty
    }

    func attachUndoManager(_ undoManager: UndoManager?) {
        self.undoManager = undoManager
    }

    func showImportMenu() {
        isImportMenuPresented = true
    }

    func beginImport(kind: ComposerImportKind) {
        isImportMenuPresented = false
        pendingImportKind = kind
        isImportPresented = true
    }

}
