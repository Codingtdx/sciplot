import Foundation
import Observation

@MainActor
@Observable
final class DataStudioSession {
    typealias DirectoryChooser = @MainActor (_ title: String, _ message: String) -> URL?
    typealias WorkbookSaveChooser = @MainActor (_ suggestedName: String) -> URL?
    typealias ComparisonFigureFormatChooser = @MainActor (_ title: String, _ message: String) -> ExportGraphicFormat?
    typealias ComparisonOutputMaterializer = @MainActor (_ sourceURLs: [URL], _ format: ExportGraphicFormat) throws -> [URL]
    typealias OpenInPlotHandler = @MainActor (_ url: URL, _ sheet: SheetValue, _ templateID: String?, _ options: RenderOptionsPayload?) -> Void

    let plotSession: PlotSession

    let comparisonRefreshDelayNanoseconds: UInt64 = 150_000_000

    @ObservationIgnored var client: (any SidecarClienting)?
    @ObservationIgnored var runtimeState = RuntimeState()
    @ObservationIgnored let chooseDirectory: DirectoryChooser
    @ObservationIgnored let chooseWorkbookSaveLocation: WorkbookSaveChooser
    @ObservationIgnored let chooseComparisonFigureFormat: ComparisonFigureFormatChooser
    @ObservationIgnored let materializeComparisonOutputs: ComparisonOutputMaterializer
    @ObservationIgnored let asyncCoordination = AsyncCoordination()
    @ObservationIgnored var importPanelPresentationRevision = 0
    @ObservationIgnored weak var undoManager: UndoManager?

    var templates: [DataStudioTemplateResponse] = []
    var selectedTemplateID: String?
    var sourcePreview: DataStudioRawFilePreviewResponse?
    var sourceMatches: [DataStudioTemplateMatchResponse] = []
    var hoveredSuggestionID: String?
    var selectedSuggestionIDs: [String] = []
    var hoveredPreviewRanges: [DataStudioPreviewRangeResponse] = []
    var pinnedPreviewRanges: [DataStudioPreviewRangeResponse] = []
    var selectedCandidateIDs: [String] = []
    var templateDraftLabel = ""
    var templateDraftDescription = ""

    var importFlow: DataStudioImportFlowState = .idle
    var pendingImportDisposition: DataStudioImportDisposition = .addToCurrentSession
    var pendingImportKind: DataStudioImportKind = .rawFiles
    var isGuidePresented = false
    var selectedPreviewSheetName: String?
    var selectedPreviewBlockID: String?
    var showAdvancedCandidates = false

    var importedSourceURLs: [URL] = []
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
    var openInPlotHandler: OpenInPlotHandler?

    var importWizardStep: DataStudioImportWizardStep {
        get { importFlow.wizardStep ?? .kind }
        set { importFlow = .wizard(step: newValue) }
    }

    var isImportWizardPresented: Bool {
        get { importFlow.isWizardPresented }
        set {
            if newValue {
                if case let .wizard(step) = importFlow {
                    importFlow = .wizard(step: step)
                } else {
                    importFlow = .wizard(step: hasSessionContent ? .scope : .kind)
                }
            } else if importFlow.isWizardPresented {
                importFlow = .idle
            }
        }
    }

    var isImportScopePresented: Bool {
        get { importFlow.wizardStep == .scope }
        set {
            if newValue {
                importFlow = .wizard(step: .scope)
            } else if importFlow.wizardStep == .scope {
                importFlow = .idle
            }
        }
    }

    var isImportChooserPresented: Bool {
        get { importFlow.wizardStep == .kind }
        set {
            if newValue {
                importFlow = .wizard(step: .kind)
            } else if importFlow.wizardStep == .kind {
                importFlow = .idle
            }
        }
    }

    var isImportResolverPresented: Bool {
        get { importFlow.wizardStep == .resolver }
        set {
            if newValue {
                importFlow = .wizard(step: .resolver)
            } else if importFlow.wizardStep == .resolver {
                importFlow = .idle
            }
        }
    }

    var isCreateTemplateEditorPresented: Bool {
        get { importFlow.wizardStep == .createTemplate }
        set {
            if newValue {
                importFlow = .wizard(step: .createTemplate)
            } else if importFlow.wizardStep == .createTemplate {
                importFlow = .idle
            }
        }
    }

    var isImportPresented: Bool {
        get { importFlow.isImporterPresented }
        set {
            if newValue {
                importFlow = .importer(kind: pendingImportKind)
            } else if importFlow.isImporterPresented {
                importFlow = .idle
            }
        }
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
        }
    ) {
        self.plotSession = plotSession
        self.chooseDirectory = chooseDirectory
        self.chooseWorkbookSaveLocation = chooseWorkbookSaveLocation
        self.chooseComparisonFigureFormat = chooseComparisonFigureFormat
        self.materializeComparisonOutputs = materializeComparisonOutputs
        self.plotSession.renderOptionsDidChange = { [weak self] options in
            Task { @MainActor [weak self] in
                self?.storeCurrentFigureOptions(options)
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
            if selectedTemplateID == nil {
                selectedTemplateID = templates.first?.id
            } else if !templates.contains(where: { $0.id == selectedTemplateID }) {
                selectedTemplateID = templates.first?.id
            }
        } catch {
            if isUserCancelled(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func showGuide() {
        isGuidePresented = true
    }

    func dismissGuide() {
        isGuidePresented = false
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
        importedSourceURLs = []
        sourcePreview = nil
        sourceMatches = []
        hoveredSuggestionID = nil
        selectedSuggestionIDs = []
        hoveredPreviewRanges = []
        pinnedPreviewRanges = []
        selectedCandidateIDs = []
        templateDraftLabel = ""
        templateDraftDescription = ""
        selectedPreviewSheetName = nil
        selectedPreviewBlockID = nil
        showAdvancedCandidates = false
        importFlow = .idle
        plotSession.clearPreviewContext(preserveRenderOptions: true)
        previewWarning = nil
        isPreviewStale = false
        errorMessage = nil
        currentActivity = .idle
    }

    func isUserCancelled(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return true
        }
        if nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue {
            return true
        }
        return false
    }
}

extension DataStudioSession {
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
    }

    enum DerivedState {
        static func hasSessionContent(workbooks: [DataStudioWorkbookItem]) -> Bool {
            !workbooks.isEmpty
        }
    }
}
