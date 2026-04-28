import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class PlotSession {
    typealias PlotExportFormatChooser = @MainActor (_ isMultiOutput: Bool) -> ExportGraphicFormat?
    typealias PlotExportDestinationChooser = @MainActor (_ suggestedName: String, _ isMultiOutput: Bool, _ format: ExportGraphicFormat) -> URL?
    typealias PlotExportMaterializer = @MainActor (_ sourceURLs: [URL], _ destinationURL: URL) throws -> [URL]
    typealias PlotProjectSaveChooser = @MainActor (_ suggestedName: String) -> URL?

    struct UndoSnapshot: Equatable {
        let selectedSheet: SheetValue
        let selectedTemplateID: String?
        let renderOptions: RenderOptionsPayload
        let fitOptions: FitOptionsPayload
    }

    struct ProjectSnapshot: Equatable {
        let sourcePath: String
        let selectedSheet: SheetValue
        let selectedTemplateID: String
        let renderOptions: RenderOptionsPayload
        let fitOptions: FitOptionsPayload
    }

    struct RuntimeState {
        var inspectedInputPath: String?
        var inspectedSheet: SheetValue?
        var stagedExternalPinnedSheet: SheetValue?
        var stagedExternalPinnedTemplateID: String?
        var isApplyingUndoRedo = false
        var lastSavedProjectSnapshot: ProjectSnapshot?
    }

    @MainActor
    final class AsyncCoordination {
        let inspection = AsyncLatestTaskCoordinator()
        let preview = AsyncLatestTaskCoordinator()
    }

    let previewDebounceNanoseconds: UInt64 = 250_000_000

    @ObservationIgnored var client: (any SidecarClienting)?
    @ObservationIgnored let chooseExportFormat: PlotExportFormatChooser
    @ObservationIgnored let chooseExportDestination: PlotExportDestinationChooser
    @ObservationIgnored let materializeExport: PlotExportMaterializer
    @ObservationIgnored let chooseProjectSaveLocation: PlotProjectSaveChooser
    @ObservationIgnored var runtimeState = RuntimeState()
    @ObservationIgnored let asyncCoordination = AsyncCoordination()
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored var renderOptionsDidChange: ((RenderOptionsPayload) -> Void)?
    @ObservationIgnored var fitOptionsDidChange: ((FitOptionsPayload) -> Void)?

    var isImporterPresented = false
    var isDataWorkbookPresented = false
    var selectedFileURL: URL?
    var projectURL: URL?
    var selectedSheet: SheetValue = .index(0)
    var inspectionResponse: InspectFileResponse?
    var metadata: SidecarMetaResponse?
    var contract: PlotContractResponse?
    var selectedTemplateID: String?
    var renderOptions = RenderOptionsPayload()
    var fitOptions = FitOptionsPayload()
    var previewResponse: RenderPreviewResponse?
    var preflightResponse: PreflightRenderResponse?
    var exportResponse: ExportRenderResponse?
    var errorMessage: String?
    var isInspecting = false
    var isPreviewing = false
    var isRunningPreflight = false
    var isExporting = false
    var isSavingProject = false
    var userExportURLs: [URL] = []
    var dataWorkbookTab: PlotDataWorkbookTab = .sourceData
    var sourceTableResponse: SourceTablePreviewResponse?
    var fitAnalysisResponse: FitAnalysisResponse?
    var sourceTableErrorMessage: String?
    var fitAnalysisErrorMessage: String?
    var isLoadingSourceTable = false
    var isLoadingFitAnalysis = false
    var sourceTableOffset = 0
    var fitAnalysisOffset = 0
    var fitAnalysisSelectedSeriesID: String?
    var selectedPlotTool: PlotTool = .select
    var selectedPlotAdjustmentCategory: PlotAdjustmentCategory = .figure
    var canvasSelection: PlotCanvasSelection = .figure
    var selectedReferenceGuideID: String?
    var selectedTextAnnotationID: String?
    var selectedShapeAnnotationID: String?
    var sourceProvenance = PlotProjectSourceProvenancePayload(
        originalInputPath: nil,
        savedInputMtimeNs: nil,
        savedAt: nil
    )

    var exportAvailability: ActionAvailability {
        if isExporting {
            return .disabled("Export is already in progress.")
        }
        guard client != nil else {
            return .disabled("The sidecar is not ready yet.")
        }
        guard selectedFileURL != nil else {
            return .disabled("Import a source file before exporting.")
        }
        guard effectiveTemplateID != nil else {
            return .disabled("Choose a template before exporting.")
        }
        guard !needsInspection else {
            return .disabled("Wait for inspect to finish before exporting.")
        }
        return .enabled()
    }

    var saveProjectAvailability: ActionAvailability {
        if isSavingProject {
            return .disabled("Project save is already in progress.")
        }
        guard client != nil else {
            return .disabled("The sidecar is not ready yet.")
        }
        guard currentProjectSnapshot != nil else {
            return .disabled("Import a plot source before saving a project.")
        }
        guard !needsInspection else {
            return .disabled("Wait for inspect to finish before saving the project.")
        }
        return .enabled()
    }

    var revealOutputAvailability: ActionAvailability {
        guard !latestExportItems.isEmpty else {
            return .disabled("Export a plot first.")
        }
        return .enabled()
    }

    var latestExportItems: [ExportedFileItem] {
        userExportURLs.map { ExportedFileItem(url: $0) }
    }

    init(
        chooseExportFormat: @escaping PlotExportFormatChooser = {
            NativeExportCoordinator.choosePlotExportFormat(isMultiOutput: $0)
        },
        chooseExportDestination: @escaping PlotExportDestinationChooser = {
            NativeExportCoordinator.choosePlotExportLocation(
                suggestedName: $0,
                isMultiOutput: $1,
                format: $2
            )
        },
        materializeExport: @escaping PlotExportMaterializer = {
            try NativeExportCoordinator.materializePlotOutputs(sourceURLs: $0, destinationURL: $1)
        },
        chooseProjectSaveLocation: @escaping PlotProjectSaveChooser = {
            NativePanels.choosePlotProjectSaveLocation(suggestedName: $0)
        }
    ) {
        self.chooseExportFormat = chooseExportFormat
        self.chooseExportDestination = chooseExportDestination
        self.materializeExport = materializeExport
        self.chooseProjectSaveLocation = chooseProjectSaveLocation
    }

    var hasSessionContent: Bool {
        selectedFileURL != nil || inspectionResponse != nil || effectiveTemplateID != nil
    }

    var hasRenderableSelection: Bool {
        selectedFileURL != nil && effectiveTemplateID != nil && !needsInspection
    }

    var needsInspection: Bool {
        DerivedState.needsInspection(
            selectedFileURL: selectedFileURL,
            inspectedInputPath: runtimeState.inspectedInputPath,
            inspectedSheet: runtimeState.inspectedSheet,
            selectedSheet: selectedSheet,
            inspectionResponse: inspectionResponse
        )
    }

    var liveStatusSymbol: String {
        DerivedState.liveStatusSymbol(
            hasError: errorMessage != nil,
            isInspecting: isInspecting,
            isPreviewing: isPreviewing,
            previewResponse: previewResponse
        )
    }

    var selectedSourceFilename: String? {
        selectedFileURL?.lastPathComponent
    }

    var selectedSourcePath: String? {
        selectedFileURL?.path
    }

    func configure(client: any SidecarClienting) {
        self.client = client
    }

    func attachUndoManager(_ undoManager: UndoManager?) {
        self.undoManager = undoManager
    }

    func apply(meta: SidecarMetaResponse, contract: PlotContractResponse) {
        metadata = meta
        self.contract = contract
        selectedTemplateID = migrateLegacyTemplateID(selectedTemplateID)
        let validStyleIDs = Set(meta.styles.map(\.id))
        let validPaletteIDs = Set(meta.palettes.map(\.id))
        let validThemeIDs = Set(meta.visualThemes.map(\.id))

        renderOptions.stylePreset = validStyleIDs.contains(renderOptions.stylePreset)
            ? renderOptions.stylePreset
            : meta.defaults.stylePreset
        renderOptions.palettePreset = validPaletteIDs.contains(renderOptions.palettePreset)
            ? renderOptions.palettePreset
            : meta.defaults.palettePreset
        if let themeID = renderOptions.visualThemeID, !validThemeIDs.contains(themeID) {
            renderOptions.visualThemeID = nil
        }
        schedulePreviewRefresh(policy: .immediate)
    }

    func showDataWorkbook() {
        isDataWorkbookPresented = true
    }

    func dismissDataWorkbook() {
        isDataWorkbookPresented = false
    }
}

extension PlotSession {
    static func migrateLegacyTemplateID(_ templateID: String?) -> String? {
        switch templateID {
        case "grouped_bar_error", "grouped_bar_compare":
            return "bar"
        default:
            return templateID
        }
    }

    func migrateLegacyTemplateID(_ templateID: String?) -> String? {
        Self.migrateLegacyTemplateID(templateID)
    }

    enum DerivedState {
        static func needsInspection(
            selectedFileURL: URL?,
            inspectedInputPath: String?,
            inspectedSheet: SheetValue?,
            selectedSheet: SheetValue,
            inspectionResponse: InspectFileResponse?
        ) -> Bool {
            guard let selectedFileURL else {
                return false
            }
            guard let inspectedInputPath, let inspectedSheet else {
                return true
            }
            return inspectedInputPath != selectedFileURL.path || inspectedSheet != selectedSheet || inspectionResponse == nil
        }

        static func liveStatusSymbol(
            hasError: Bool,
            isInspecting: Bool,
            isPreviewing: Bool,
            previewResponse: RenderPreviewResponse?
        ) -> String {
            if hasError {
                return "exclamationmark.triangle.fill"
            }
            if isInspecting || isPreviewing {
                return "arrow.triangle.2.circlepath"
            }
            if previewResponse != nil {
                return "checkmark.circle.fill"
            }
            return "circle.dashed"
        }
    }
}
