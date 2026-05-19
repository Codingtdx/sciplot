import Foundation
import Observation

@MainActor
@Observable
final class DataStudioSession {
    typealias DirectoryChooser = @MainActor (_ title: String, _ message: String) -> URL?
    typealias WorkbookSaveChooser = @MainActor (_ suggestedName: String) -> URL?
    typealias ComparisonFigureFormatChooser = @MainActor (_ title: String, _ message: String) -> ExportGraphicFormat?
    typealias ComparisonOutputMaterializer = @MainActor (_ sourceURLs: [URL], _ format: ExportGraphicFormat) throws -> [URL]
    typealias ProjectSaveChooser = @MainActor (_ suggestedName: String) -> URL?
    typealias OpenProjectDocumentHandler = @MainActor (_ url: URL) async -> Void
    typealias OpenInPlotHandler = @MainActor (
        _ url: URL,
        _ sheet: SheetValue,
        _ templateID: String?,
        _ options: RenderOptionsPayload?,
        _ fitOptions: FitOptionsPayload?
    ) -> Void

    let plotSession: PlotSession

    let comparisonRefreshDelayNanoseconds: UInt64 = 150_000_000

    @ObservationIgnored var client: (any SidecarClienting)?
    @ObservationIgnored var runtimeState = RuntimeState()
    @ObservationIgnored let chooseDirectory: DirectoryChooser
    @ObservationIgnored let chooseWorkbookSaveLocation: WorkbookSaveChooser
    @ObservationIgnored let chooseComparisonFigureFormat: ComparisonFigureFormatChooser
    @ObservationIgnored let materializeComparisonOutputs: ComparisonOutputMaterializer
    @ObservationIgnored let chooseProjectSaveLocation: ProjectSaveChooser
    @ObservationIgnored var openProjectDocumentHandler: OpenProjectDocumentHandler?
    @ObservationIgnored let asyncCoordination = AsyncCoordination()
    @ObservationIgnored var importPanelPresentationRevision = 0
    @ObservationIgnored weak var undoManager: UndoManager?

    var templates: [DataStudioTemplateResponse] = []
    var selectedTemplateID: String?
    var recommendedTemplateMatches: [DataStudioTemplateMatchResponse] = []
    var importPreview: ImportPreviewResponse?
    var importSelection: ImportSelectionPayload?
    var sourcePreview: SourceTablePreviewResponse?
    var templatePreview: DataStudioTemplatePreviewResponse?
    var hoveredSuggestionID: String?
    var selectedSuggestionIDs: [String] = []
    var hoveredPreviewRanges: [DataStudioPreviewRangeResponse] = []
    var pinnedPreviewRanges: [DataStudioPreviewRangeResponse] = []
    var selectedCandidateIDs: [String] = []
    var templateDraftLabel = ""
    var templateDraftDescription = ""
    var templateDraftOutputKind = "curve_metrics"
    var templateDraftComparisonEnabled = false
    var templateDraftXColumnName: String?
    var templateDraftYColumnNames: [String] = []
    var templateDraftMetricColumnNames: [String] = []
    var templateDraftSampleNameByYColumn: [String: String] = [:]
    var templateDraftBindingLabelByColumn: [String: String] = [:]
    var templateDraftUnitHintByColumn: [String: String] = [:]
    var templateDraftSourceEncoding = ""
    var templateDraftSourceDelimiter = ""
    var templateDraftSourceSheetName = ""
    var templateDraftSegmentPolicy = "single_table"
    var validatedTemplateDraftRequest: DataStudioCreateTemplateRequest?
    var selectedPreviewSegmentID: String?

    var importFlow: DataStudioImportFlowState = .idle
    var pendingImportDisposition: DataStudioImportDisposition = .addToCurrentSession
    var pendingImportKind: DataStudioImportKind = .rawFiles
    var selectedPreviewSheetName: String?
    var selectedPreviewBlockID: String?
    var showAdvancedCandidates = false

    var importedSourceURLs: [URL] = []
    var projectURL: URL?
    var workbooks: [DataStudioWorkbookItem] = []
    var groupStates: [DataStudioGroupStatePayload] = []
    var specimenStatesByWorkbookPath: [String: [DataStudioSpecimenStatePayload]] = [:]
    var draftSpecimenStatesByWorkbookPath: [String: [DataStudioSpecimenStatePayload]] = [:]
    var workbookPreviewByPath: [String: DataStudioWorkbookPreviewResponse] = [:]
    var baselineWorkbookPreviewByPath: [String: DataStudioWorkbookPreviewResponse] = [:]
    var focusedWorkbookPath: String?
    var specimenFilterAnchor: DataStudioSpecimenFilterAnchor?
    var focusedWorkbookPreviewRefreshState: DataStudioWorkbookPreviewRefreshState = .idle
    var baselineWorkbookPreviewRefreshState: DataStudioWorkbookPreviewRefreshState = .idle

    var comparisonSet: DataStudioComparisonSetResponse?
    var comparisonContextCacheKey: String?
    var comparisonContextMaterializedAt: String?
    var selectedRecipeID: String?
    var selectedFigureFamilyID: String?
    var selectedFigureTemplateID: String?
    var figurePreferences: [DataStudioFigurePreferencePayload] = []
    var isAnalysisPresented = false
    var analysisTarget: DataStudioAnalysisTarget = .focusedWorkbook
    var analysisTab: DataStudioAnalysisTab = .sourceData
    var analysisSourceTableResponse: SourceTablePreviewResponse?
    var analysisFitResponse: FitAnalysisResponse?
    var analysisSourceTableErrorMessage: String?
    var analysisFitErrorMessage: String?
    var analysisSelectedSeriesID: String?
    var analysisSourceTableOffset = 0
    var analysisFitOffset = 0
    var isLoadingAnalysisSourceTable = false
    var isLoadingAnalysisFit = false
    var focusedWorkbookFitOptions = FitOptionsPayload(enabled: true, modelID: "linear")
    var comparisonExportResponse: DataStudioComparisonExportResponse?
    var comparisonExportDestinationURL: URL?
    var comparisonFigureItems: [DataStudioExportFigureItem] = []
    var comparisonFilteredWorkbookItems: [DataStudioExportFilteredWorkbookItem] = []
    var selectedComparisonFigureID: String?

    var previewWarning: String?
    var isPreviewStale = false
    var errorMessage: String?
    var currentActivity: DataStudioActivity = .idle
    var isBusy = false
    var isSavingProject = false
    var openInPlotHandler: OpenInPlotHandler?

    var importWizardStep: DataStudioImportWizardStep {
        get { importFlow.wizardStep ?? .kind }
        set { importFlow = .wizard(step: newValue) }
    }

    init(
        plotSession: PlotSession = PlotSession(),
        chooseDirectory: @escaping DirectoryChooser = { title, message in
            NativeExportCoordinator.chooseDirectory(title: title, message: message)
        },
        chooseWorkbookSaveLocation: @escaping WorkbookSaveChooser = {
            NativeExportCoordinator.chooseWorkbookSaveLocation(suggestedName: $0)
        },
        chooseComparisonFigureFormat: @escaping ComparisonFigureFormatChooser = { title, message in
            NativeExportCoordinator.chooseComparisonFigureExportFormat(title: title, message: message)
        },
        materializeComparisonOutputs: @escaping ComparisonOutputMaterializer = {
            try NativeExportCoordinator.materializeComparisonOutputs(sourceURLs: $0, format: $1)
        },
        chooseProjectSaveLocation: @escaping ProjectSaveChooser = {
            NativePanels.choosePlotProjectSaveLocation(suggestedName: $0)
        }
    ) {
        self.plotSession = plotSession
        self.chooseDirectory = chooseDirectory
        self.chooseWorkbookSaveLocation = chooseWorkbookSaveLocation
        self.chooseComparisonFigureFormat = chooseComparisonFigureFormat
        self.materializeComparisonOutputs = materializeComparisonOutputs
        self.chooseProjectSaveLocation = chooseProjectSaveLocation
        self.plotSession.renderOptionsDidChange = { [weak self] options in
            Task { @MainActor [weak self] in
                self?.storeCurrentFigureOptions(options)
            }
        }
        self.plotSession.fitOptionsDidChange = { [weak self] options in
            Task { @MainActor [weak self] in
                self?.storeCurrentFigureFitOptions(options)
            }
        }
    }

    func configure(client: any SidecarClienting) {
        self.client = client
        plotSession.configure(client: client)
    }

    func attachUndoManager(_ undoManager: UndoManager?) {
        self.undoManager = undoManager
        plotSession.attachUndoManager(undoManager)
    }

    func apply(meta: SidecarMetaResponse, contract: PlotContractResponse) {
        runtimeState.meta = meta
        runtimeState.contract = contract
        selectedFigureTemplateID = migrateLegacyFigureTemplateID(selectedFigureTemplateID)
        selectedRecipeID = migrateLegacyComparisonRecipeID(selectedRecipeID)
        figurePreferences = figurePreferences.map(migrateLegacyFigurePreference(_:))
        plotSession.apply(meta: meta, contract: contract)
    }

    func refreshTemplates() async {
        guard let client else {
            return
        }
        currentActivity = .loadingTemplates
        defer { currentActivity = .idle }
        do {
            let response = try await client.fetchDataStudioTemplates()
            templates = response.templates.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            if let selectedTemplateID,
               !templates.contains(where: { $0.id == selectedTemplateID })
            {
                self.selectedTemplateID = nil
            }
        } catch {
            if isUserCancellationError(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    var hasSessionContent: Bool {
        DerivedState.hasSessionContent(workbooks: workbooks)
    }

    func undoSnapshot() -> UndoSnapshot {
        UndoSnapshot(
            groupStates: groupStates,
            specimenStatesByWorkbookPath: specimenStatesByWorkbookPath,
            selectedFigureFamilyID: selectedFigureFamilyID,
            selectedFigureTemplateID: selectedFigureTemplateID,
            selectedRecipeID: selectedRecipeID,
            figurePreferences: figurePreferences
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
        groupStates = snapshot.groupStates
        specimenStatesByWorkbookPath = snapshot.specimenStatesByWorkbookPath
        draftSpecimenStatesByWorkbookPath = snapshot.specimenStatesByWorkbookPath
        selectedFigureFamilyID = snapshot.selectedFigureFamilyID
        selectedFigureTemplateID = migrateLegacyFigureTemplateID(snapshot.selectedFigureTemplateID)
        selectedRecipeID = migrateLegacyComparisonRecipeID(snapshot.selectedRecipeID)
        figurePreferences = snapshot.figurePreferences.map(migrateLegacyFigurePreference(_:))
        previewWarning = nil
        isPreviewStale = false
        scheduleComparisonContextRebuild()
    }

    func resetContentState() {
        asyncCoordination.comparisonRefresh.cancel()
        asyncCoordination.workbookPreview.cancelAll()
        asyncCoordination.baselineWorkbookPreview.cancelAll()
        workbooks = []
        groupStates = []
        specimenStatesByWorkbookPath = [:]
        draftSpecimenStatesByWorkbookPath = [:]
        workbookPreviewByPath = [:]
        baselineWorkbookPreviewByPath = [:]
        focusedWorkbookPath = nil
        specimenFilterAnchor = nil
        focusedWorkbookPreviewRefreshState = .idle
        baselineWorkbookPreviewRefreshState = .idle
        comparisonSet = nil
        comparisonContextCacheKey = nil
        comparisonContextMaterializedAt = nil
        comparisonExportResponse = nil
        comparisonExportDestinationURL = nil
        comparisonFigureItems = []
        comparisonFilteredWorkbookItems = []
        selectedComparisonFigureID = nil
        selectedRecipeID = nil
        projectURL = nil
        importedSourceURLs = []
        recommendedTemplateMatches = []
        asyncCoordination.sourcePreview.cancel()
        sourcePreview = nil
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
        selectedPreviewSegmentID = nil
        selectedPreviewSheetName = nil
        selectedPreviewBlockID = nil
        showAdvancedCandidates = false
        importFlow = .idle
        isAnalysisPresented = false
        analysisTarget = .focusedWorkbook
        analysisTab = .sourceData
        analysisSourceTableResponse = nil
        analysisFitResponse = nil
        analysisSourceTableErrorMessage = nil
        analysisFitErrorMessage = nil
        analysisSelectedSeriesID = nil
        analysisSourceTableOffset = 0
        analysisFitOffset = 0
        isLoadingAnalysisSourceTable = false
        isLoadingAnalysisFit = false
        focusedWorkbookFitOptions = FitOptionsPayload(enabled: true, modelID: "linear")
        plotSession.clearPreviewContext(preserveRenderOptions: true)
        previewWarning = nil
        isPreviewStale = false
        errorMessage = nil
        currentActivity = .idle
        runtimeState.lastSavedProjectSnapshot = nil
    }

    var currentProjectSnapshot: ProjectSnapshot? {
        guard !orderedWorkbooks.isEmpty else {
            return nil
        }
        return ProjectSnapshot(
            selectedTemplateID: selectedTemplateID,
            selectedWorkbookID: focusedWorkbook?.response.workbookID,
            primaryWorkbookID: focusedWorkbook?.response.workbookID,
            selectedRecipeID: currentRecipe?.id,
            workbookPaths: orderedWorkbooks.map { $0.response.workbookPath },
            comparisonRecipeIDs: selectedExportRecipeIDs,
            selectedFigureFamilyID: selectedFigureFamilyID,
            selectedFigureTemplateID: selectedFigureTemplateID,
            groupStates: requestGroupStates,
            specimenStates: requestSpecimenStates,
            figurePreferences: figurePreferences,
            importedPaths: importedSourceURLs.map(\.path),
            templateDraftPath: importedSourceURLs.first?.path
        )
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

    var saveProjectAvailability: ActionAvailability {
        if isSavingProject {
            return .disabled("Project save is already in progress.")
        }
        guard client != nil else {
            return .disabled("The sidecar is not ready yet.")
        }
        guard currentProjectSnapshot != nil else {
            return .disabled("Import workbook groups before saving a project.")
        }
        return .enabled()
    }

    var suggestedProjectFilename: String {
        if let projectURL {
            return projectURL.lastPathComponent
        }
        if let focusedWorkbook {
            return focusedWorkbook.workbookURL.deletingPathExtension().lastPathComponent + ".sciplot"
        }
        return "data-studio-project.sciplot"
    }
}

extension DataStudioSession {
    struct ProjectSnapshot: Equatable {
        let selectedTemplateID: String?
        let selectedWorkbookID: String?
        let primaryWorkbookID: String?
        let selectedRecipeID: String?
        let workbookPaths: [String]
        let comparisonRecipeIDs: [String]
        let selectedFigureFamilyID: String?
        let selectedFigureTemplateID: String?
        let groupStates: [DataStudioGroupStatePayload]
        let specimenStates: [DataStudioSpecimenStatePayload]
        let figurePreferences: [DataStudioFigurePreferencePayload]
        let importedPaths: [String]
        let templateDraftPath: String?
    }

    struct UndoSnapshot: Equatable {
        let groupStates: [DataStudioGroupStatePayload]
        let specimenStatesByWorkbookPath: [String: [DataStudioSpecimenStatePayload]]
        let selectedFigureFamilyID: String?
        let selectedFigureTemplateID: String?
        let selectedRecipeID: String?
        let figurePreferences: [DataStudioFigurePreferencePayload]
    }

    struct RuntimeState {
        var meta: SidecarMetaResponse?
        var contract: PlotContractResponse?
        var isApplyingUndoRedo = false
        var lastSavedProjectSnapshot: ProjectSnapshot?
    }

    struct BulkAutoKeepPresentation {
        let eligibleWorkbookPaths: [String]
        let availability: ActionAvailability
        let help: String
    }

    @MainActor
    final class AsyncCoordination {
        let comparisonRefresh = AsyncLatestTaskCoordinator()
        let workbookPreview = KeyedAsyncLatestTaskCoordinator<String>()
        let baselineWorkbookPreview = KeyedAsyncLatestTaskCoordinator<String>()
        let sourcePreview = AsyncLatestTaskCoordinator()
    }

    enum DerivedState {
        static func hasSessionContent(workbooks: [DataStudioWorkbookItem]) -> Bool {
            !workbooks.isEmpty
        }
    }
}
