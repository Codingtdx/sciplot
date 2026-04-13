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

    private let comparisonRefreshDelayNanoseconds: UInt64 = 150_000_000

    @ObservationIgnored private var client: (any SidecarClienting)?
    @ObservationIgnored private var runtimeState = RuntimeState()
    @ObservationIgnored private let chooseDirectory: DirectoryChooser
    @ObservationIgnored private let chooseWorkbookSaveLocation: WorkbookSaveChooser
    @ObservationIgnored private let chooseComparisonFigureFormat: ComparisonFigureFormatChooser
    @ObservationIgnored private let materializeComparisonOutputs: ComparisonOutputMaterializer
    @ObservationIgnored private let asyncCoordination = AsyncCoordination()
    @ObservationIgnored private var importPanelPresentationRevision = 0
    @ObservationIgnored private weak var undoManager: UndoManager?

    let plotSession: PlotSession

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

    var isImportScopePresented = false
    var isImportChooserPresented = false
    var isImportWizardPresented = false
    var importWizardStep: DataStudioImportWizardStep = .kind
    var pendingImportDisposition: DataStudioImportDisposition = .addToCurrentSession
    var pendingImportKind: DataStudioImportKind = .rawFiles
    var isImportPresented = false
    var isImportResolverPresented = false
    var isCreateTemplateEditorPresented = false
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

    var exportAvailability: ActionAvailability {
        if currentActivity == .exportingComparison {
            return .disabled("Export is already in progress.")
        }
        guard client != nil else {
            return .disabled("The sidecar is not ready yet.")
        }
        guard comparisonSet != nil else {
            return .disabled("Import workbook groups before exporting.")
        }
        guard !selectedExportRecipeIDs.isEmpty else {
            return .disabled("Choose at least one figure family before exporting.")
        }
        return .enabled()
    }

    var autoKeepAllAvailability: ActionAvailability {
        bulkAutoKeepPresentation.availability
    }

    var autoKeepAllHelp: String {
        bulkAutoKeepPresentation.help
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
            errorMessage = error.localizedDescription
        }
    }

    func beginImportFlow() {
        clearImportFlowError()
        isImportWizardPresented = true
        if hasSessionContent {
            pendingImportDisposition = .addToCurrentSession
            importWizardStep = .scope
            isImportScopePresented = true
        } else {
            pendingImportDisposition = .addToCurrentSession
            importWizardStep = .kind
            isImportChooserPresented = true
        }
    }

    func chooseImportDisposition(_ disposition: DataStudioImportDisposition) {
        clearImportFlowError()
        pendingImportDisposition = disposition
        isImportScopePresented = false
        importWizardStep = .kind
        isImportChooserPresented = true
    }

    func chooseImportKind(_ kind: DataStudioImportKind) {
        clearImportFlowError()
        pendingImportKind = kind
        importWizardStep = .kind
        isImportScopePresented = false
        isImportChooserPresented = false
        isImportResolverPresented = false
        isCreateTemplateEditorPresented = false
        isImportWizardPresented = false
        scheduleImportPanelPresentation()
    }

    func dismissImportScope() {
        clearImportFlowError()
        isImportWizardPresented = false
        importWizardStep = .kind
        isImportScopePresented = false
        pendingImportDisposition = .addToCurrentSession
    }

    func dismissImportChooser() {
        clearImportFlowError()
        isImportWizardPresented = false
        importWizardStep = .kind
        isImportChooserPresented = false
        pendingImportDisposition = .addToCurrentSession
        pendingImportKind = .rawFiles
    }

    var canGoBackInImportWizard: Bool {
        switch importWizardStep {
        case .scope:
            return false
        case .kind:
            return hasSessionContent
        case .resolver, .createTemplate:
            return true
        }
    }

    func goBackInImportWizard() {
        switch importWizardStep {
        case .scope:
            break
        case .kind:
            if hasSessionContent {
                importWizardStep = .scope
                isImportScopePresented = true
                isImportChooserPresented = false
            }
        case .resolver:
            importWizardStep = .kind
            isImportResolverPresented = false
            isCreateTemplateEditorPresented = false
            isImportChooserPresented = true
        case .createTemplate:
            returnToImportResolver()
        }
    }

    func dismissImportWizard() {
        clearImportFlowError()
        isImportWizardPresented = false
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
        if isUserCancelled(error) {
            clearImportFlowError()
            return
        }
        errorMessage = error.localizedDescription
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

    var orderedWorkbooks: [DataStudioWorkbookItem] {
        let stateByPath = Dictionary(uniqueKeysWithValues: groupStates.map { ($0.workbookPath, $0) })
        return workbooks.sorted { lhs, rhs in
            let leftState = stateByPath[lhs.response.workbookPath]
            let rightState = stateByPath[rhs.response.workbookPath]
            let leftOrder = leftState?.sortOrder ?? Int.max
            let rightOrder = rightState?.sortOrder ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    var orderedGroups: [DataStudioGroupRowItem] {
        orderedWorkbooks.compactMap { workbook in
            guard let state = groupState(for: workbook.response.workbookPath) else {
                return nil
            }
            return DataStudioGroupRowItem(workbook: workbook, state: state)
        }
    }

    var focusedWorkbook: DataStudioWorkbookItem? {
        guard let focusedWorkbookPath else {
            return orderedWorkbooks.first
        }
        return orderedWorkbooks.first(where: { $0.response.workbookPath == focusedWorkbookPath }) ?? orderedWorkbooks.first
    }

    var specimenFilterWorkbookPath: String? {
        specimenFilterAnchor?.workbookPath
    }

    var isSpecimenFilterPresented: Bool {
        specimenFilterAnchor != nil
    }

    var focusedWorkbookPreview: DataStudioWorkbookPreviewResponse? {
        guard let focusedWorkbook else {
            return nil
        }
        return workbookPreview(for: focusedWorkbook.response.workbookPath)
    }

    var includedGroups: [DataStudioGroupRowItem] {
        orderedGroups.filter(\.state.includeInCompare)
    }

    func workbookPreview(for workbookPath: String) -> DataStudioWorkbookPreviewResponse? {
        workbookPreviewByPath[workbookPath]
    }

    func baselineWorkbookPreview(for workbookPath: String) -> DataStudioWorkbookPreviewResponse? {
        baselineWorkbookPreviewByPath[workbookPath]
    }

    func specimenStates(for workbookPath: String) -> [DataStudioSpecimenStatePayload] {
        specimenStatesByWorkbookPath[workbookPath] ?? []
    }

    func draftSpecimenStates(for workbookPath: String) -> [DataStudioSpecimenStatePayload] {
        draftSpecimenStatesByWorkbookPath[workbookPath] ?? specimenStates(for: workbookPath)
    }

    func draftRepresentativeSpecimenID(for workbookPath: String) -> String? {
        selectedRepresentativeSpecimenID(in: draftSpecimenStates(for: workbookPath))
    }

    func draftRepresentativeFilename(for workbookPath: String) -> String? {
        specimenFilename(
            for: workbookPath,
            specimenId: draftRepresentativeSpecimenID(for: workbookPath)
        )
    }

    func suggestedAutoIncludedSpecimenIDs(for workbookPath: String) -> Set<String> {
        Set(
            baselineWorkbookPreview(for: workbookPath)?
                .specimens
                .filter { $0.autoRuleRole == "keep" }
                .map(\.specimenId) ?? []
        )
    }

    var selectedComparisonFigure: DataStudioExportFigureItem? {
        guard let selectedComparisonFigureID else {
            return comparisonFigureItems.first
        }
        return comparisonFigureItems.first(where: { $0.id == selectedComparisonFigureID }) ?? comparisonFigureItems.first
    }

    var latestComparisonWorkbookURL: URL? {
        guard let path = comparisonExportResponse?.comparisonSet.comparisonWorkbookPath else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    func displayedMetrics(for workbook: DataStudioWorkbookItem) -> [DataStudioMetricSummaryResponse] {
        workbookPreview(for: workbook.response.workbookPath)?.metrics ?? workbook.response.metrics
    }

    func displayedReplicateBadge(for workbook: DataStudioWorkbookItem) -> String {
        if let preview = workbookPreview(for: workbook.response.workbookPath), preview.supported {
            return "\(preview.includedSpecimenCount) / \(preview.totalSpecimenCount) included"
        }
        return "\(workbook.response.parsedSampleCount) reps"
    }

    func workbookHasWarnings(_ workbook: DataStudioWorkbookItem) -> Bool {
        if let preview = workbookPreview(for: workbook.response.workbookPath), !preview.warnings.isEmpty {
            return true
        }
        return workbook.response.failedSampleCount > 0 || !workbook.response.warnings.isEmpty
    }

    func hasPendingFilterChanges(for workbookPath: String) -> Bool {
        normalizedSpecimenStates(draftSpecimenStates(for: workbookPath)) != normalizedSpecimenStates(specimenStates(for: workbookPath))
    }

    func specimenFilterMode(for workbookPath: String) -> DataStudioSpecimenFilterMode {
        let excludedIDs = Set(
            specimenStates(for: workbookPath)
                .filter { !$0.included }
                .map(\.specimenId)
        )
        if excludedIDs.isEmpty {
            return .off
        }
        let baselineSuggested = Set(baselineWorkbookPreview(for: workbookPath)?.suggestedExclusionIds ?? [])
        if !baselineSuggested.isEmpty, excludedIDs == baselineSuggested {
            return .auto
        }
        return .manual
    }

    func specimenFilterPresentation(for workbookPath: String) -> DataStudioSpecimenFilterPresentation {
        let mode = specimenFilterMode(for: workbookPath)
        let hasPendingChanges = hasPendingFilterChanges(for: workbookPath)
        let baselinePreview = baselineWorkbookPreview(for: workbookPath)
        let appliedPreview = workbookPreview(for: workbookPath)
        let appliedRefreshing: Bool
        switch focusedWorkbookPreviewRefreshState {
        case let .refreshing(currentPath):
            appliedRefreshing = currentPath == workbookPath
        default:
            appliedRefreshing = false
        }
        let baselineRefreshing: Bool
        switch baselineWorkbookPreviewRefreshState {
        case let .refreshing(currentPath):
            baselineRefreshing = currentPath == workbookPath
        default:
            baselineRefreshing = false
        }
        let isBusy = appliedRefreshing || baselineRefreshing || currentActivity == .previewingComparison
        let totalSpecimenCount = appliedPreview?.totalSpecimenCount ?? baselinePreview?.totalSpecimenCount ?? 0
        let appliedIncludedCount = appliedPreview?.includedSpecimenCount ?? totalSpecimenCount
        let autoKeepCount = baselinePreview?.specimens.filter { $0.autoRuleRole == "keep" }.count ?? 0
        let autoFilterSupported = baselinePreview?.supported == true && (baselinePreview?.suggestionSupported ?? false)
        let autoFilterReason: String?
        if baselinePreview?.supported == false {
            autoFilterReason = baselinePreview?.unsupportedReason
        } else if baselinePreview?.suggestionSupported == false {
            autoFilterReason = baselinePreview?.suggestionSupportReason
        } else {
            autoFilterReason = nil
        }
        let title: String
        switch mode {
        case .off:
            title = "All Specimens"
        case .auto:
            title = "Auto Keep 5"
        case .manual:
            title = "Manual Keep \(appliedIncludedCount)"
        }
        let help = hasPendingChanges ? "Advanced manual edits are still draft." : (autoFilterReason ?? mode.defaultHelp)

        let sortDescriptor = specimenFilterSortDescriptor(for: baselinePreview)
        let rankedSourceRows = sortedSpecimenRows(
            baselinePreview?.specimens ?? [],
            descriptor: sortDescriptor,
            groupByDisposition: true
        )
        let rankedRows = rankedSourceRows.enumerated().map { index, specimen in
            let disposition = specimenFilterDisposition(for: specimen)
            let showsCutoffAfter = disposition == .keep
                && rankedSourceRows.dropFirst(index + 1).contains(where: { specimenFilterDisposition(for: $0) != .keep })
            return DataStudioSpecimenFilterRankedRow(
                id: specimen.specimenId,
                rank: index + 1,
                sortValue: specimenFilterSortValue(for: specimen, descriptor: sortDescriptor),
                distanceFromMeanScore: specimen.distanceFromMeanScore,
                disposition: disposition,
                showsCutoffAfter: showsCutoffAfter
            )
        }
        let canApplyAuto = autoFilterSupported
            && !isBusy
            && autoKeepCount > 0
            && (mode != .auto || hasPendingChanges)
        let canTurnOff = !isBusy && (appliedIncludedCount < totalSpecimenCount || hasPendingChanges)

        return DataStudioSpecimenFilterPresentation(
            mode: mode,
            title: title,
            help: help,
            rowBadge: hasPendingChanges ? "Edited" : nil,
            hasPendingChanges: hasPendingChanges,
            isBusy: isBusy,
            autoFilterSupported: autoFilterSupported,
            autoFilterReason: autoFilterReason,
            canApplyAuto: canApplyAuto,
            canTurnOff: canTurnOff,
            sortDescriptor: sortDescriptor,
            rankedRows: rankedRows,
            advancedRows: sortedSpecimenRows(
                baselinePreview?.specimens ?? [],
                descriptor: sortDescriptor,
                groupByDisposition: false
            )
        )
    }

    func draftSpecimenIncluded(for workbookPath: String, specimenId: String) -> Bool {
        draftSpecimenStates(for: workbookPath)
            .first(where: { $0.specimenId == specimenId })?
            .included ?? true
    }

    func draftSpecimenSelectedAsRepresentative(for workbookPath: String, specimenId: String) -> Bool {
        draftRepresentativeSpecimenID(for: workbookPath) == specimenId
    }

    var createTemplateSuggestions: [DataStudioBindingSuggestionResponse] {
        sourcePreview?.bindingSuggestions ?? []
    }

    var createTemplatePrimaryCurveSuggestion: DataStudioBindingSuggestionResponse? {
        preferredCreateTemplateSuggestion(kind: "curve_pair")
    }

    var createTemplatePrimaryMetricSuggestion: DataStudioBindingSuggestionResponse? {
        preferredCreateTemplateSuggestion(
            kind: "metric_group",
            preferredBlockID: createTemplatePrimaryCurveSuggestion?.blockID
        )
    }

    var createTemplatePrimaryMetadataSuggestion: DataStudioBindingSuggestionResponse? {
        preferredCreateTemplateSuggestion(
            kind: "metadata_group",
            preferredBlockID: createTemplatePrimaryCurveSuggestion?.blockID
        )
    }

    var createTemplatePrimaryStructureSuggestion: DataStudioBindingSuggestionResponse? {
        preferredCreateTemplateSuggestion(
            kind: "structure_rows",
            preferredBlockID: createTemplatePrimaryCurveSuggestion?.blockID
        )
    }

    var createTemplateSecondaryCurveSuggestions: [DataStudioBindingSuggestionResponse] {
        let primaryID = createTemplatePrimaryCurveSuggestion?.id
        return createTemplateSuggestions.filter { suggestion in
            suggestion.kind == "curve_pair" && suggestion.id != primaryID
        }
    }

    var createTemplateFocusedSuggestion: DataStudioBindingSuggestionResponse? {
        if let hoveredSuggestionID,
           let suggestion = suggestion(for: hoveredSuggestionID)
        {
            return suggestion
        }
        let preferredKinds = ["curve_pair", "metric_group", "metadata_group", "structure_rows"]
        for kind in preferredKinds {
            if let suggestion = selectedSuggestion(for: kind) {
                return suggestion
            }
        }
        return createTemplatePrimaryCurveSuggestion
            ?? createTemplatePrimaryMetricSuggestion
            ?? createTemplatePrimaryMetadataSuggestion
            ?? createTemplatePrimaryStructureSuggestion
            ?? createTemplateSuggestions.first
    }

    var createTemplatePreviewCaption: String? {
        guard let suggestion = createTemplateFocusedSuggestion else {
            return nil
        }
        switch suggestion.kind {
        case "curve_pair":
            return "Previewing Recommended Curve in \(previewLocation(for: suggestion))"
        case "metric_group":
            return "Previewing Recommended Metrics"
        case "metadata_group":
            return "Previewing Recommended Metadata"
        case "structure_rows":
            return "Previewing Detected Structure"
        default:
            return "Previewing Suggested Binding"
        }
    }

    var selectedTemplateSummaryItems: [DataStudioTemplateSummaryItem] {
        var items: [DataStudioTemplateSummaryItem] = []
        if let value = selectedCurveSummary {
            items.append(.init(id: "curve", title: "Curve", value: value))
        }
        if let value = selectedMetricSummary {
            items.append(.init(id: "metrics", title: "Metrics", value: value))
        }
        if let value = selectedMetadataSummary {
            items.append(.init(id: "metadata", title: "Metadata", value: value))
        }
        if let value = selectedStructureSummary {
            items.append(.init(id: "structure", title: "Structure", value: value))
        }
        return items
    }

    var activePreviewRanges: [DataStudioPreviewRangeResponse] {
        hoveredPreviewRanges.isEmpty ? pinnedPreviewRanges : hoveredPreviewRanges
    }

    var figureFamilies: [DataStudioFigureFamilyItem] {
        guard let comparisonSet else {
            return []
        }
        var grouped: [String: [DataStudioComparisonRecipeResponse]] = [:]
        var titles: [String: String] = [:]
        var metricIDs: [String: String?] = [:]
        for recipe in comparisonSet.recipes {
            let familyID: String
            let title: String
            if let metricID = recipe.metricID, !metricID.isEmpty {
                familyID = normalizeFigureFamilyID(metricID)
                title = metricID
                metricIDs[familyID] = metricID
            } else {
                familyID = "representative_curve"
                title = "Representative Curve"
                metricIDs[familyID] = nil
            }
            grouped[familyID, default: []].append(recipe)
            titles[familyID] = title
        }
        return grouped.keys.sorted(by: figureFamilyComparator).map { familyID in
            DataStudioFigureFamilyItem(
                id: familyID,
                title: titles[familyID] ?? familyID,
                metricID: metricIDs[familyID] ?? nil,
                recipes: grouped[familyID, default: []]
            )
        }
    }

    var currentFigureFamily: DataStudioFigureFamilyItem? {
        guard !figureFamilies.isEmpty else {
            return nil
        }
        if let selectedFigureFamilyID,
           let match = figureFamilies.first(where: { $0.id == selectedFigureFamilyID })
        {
            return match
        }
        return figureFamilies.first
    }

    var availableFigureTemplates: [DataStudioFigureTemplateItem] {
        guard let family = currentFigureFamily else {
            return []
        }
        var seen: Set<String> = []
        return family.recipes
            .filter(\.supported)
            .compactMap { recipe in
                guard seen.insert(recipe.templateID).inserted else {
                    return nil
                }
                return DataStudioFigureTemplateItem(
                    id: recipe.templateID,
                    label: displayLabel(forTemplateID: recipe.templateID),
                    recipeID: recipe.id
                )
            }
    }

    var currentFigureTemplateID: String? {
        currentRecipe?.templateID
    }

    var currentRecipe: DataStudioComparisonRecipeResponse? {
        guard let family = currentFigureFamily else {
            return nil
        }
        let selectedTemplateID = selectedTemplateID(forFamilyID: family.id)
        if let selectedTemplateID,
           let exact = family.recipes.first(where: { $0.templateID == selectedTemplateID && $0.supported })
        {
            return exact
        }
        return preferredRecipe(in: family)
    }

    var currentRecipeLabel: String {
        currentRecipe?.label ?? "No figure"
    }

    var comparisonStatusText: String {
        if let comparisonSet {
            let workbookName = URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath).lastPathComponent
            if isPreviewStale {
                return "\(includedGroups.count) group(s) · \(currentRecipeLabel) · showing last successful preview from \(workbookName)"
            }
            return "\(includedGroups.count) group(s) · \(currentRecipeLabel) · \(workbookName)"
        }
        if !workbooks.isEmpty {
            return "\(includedGroups.count) group(s) in compare"
        }
        return "No workbook groups loaded"
    }

    var previewStatusSymbol: String {
        if currentActivity == .previewingComparison {
            return "arrow.triangle.2.circlepath"
        }
        if isPreviewStale {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle"
    }

    var focusTitle: String {
        if let focusedWorkbook {
            return displayName(for: focusedWorkbook)
        }
        return "Data Studio"
    }

    var selectedSourceFilename: String? {
        focusedWorkbook?.workbookURL.lastPathComponent
    }

    var canExportComparison: Bool {
        comparisonSet != nil && !selectedExportRecipeIDs.isEmpty
    }

    var showsCompactEmptyInspector: Bool {
        orderedGroups.isEmpty
    }

    var showsInspectorActions: Bool {
        !showsCompactEmptyInspector
    }

    var canOpenCurrentFigureInPlot: Bool {
        currentFigureSourceURL != nil && currentFigureTemplateID != nil
    }

    var currentFigureSourceURL: URL? {
        if let comparisonSet, currentRecipe != nil {
            return URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath)
        }
        return plotSession.selectedFileURL ?? focusedWorkbook?.workbookURL
    }

    var currentFigureSheet: SheetValue {
        if let currentRecipe {
            return .name(currentRecipe.sheetName)
        }
        if plotSession.selectedFileURL != nil {
            return plotSession.selectedSheet
        }
        return .name(focusedWorkbook?.response.preferredSheet ?? "Representative_Curve")
    }

    var currentFigureRenderOptions: RenderOptionsPayload {
        if let currentRecipe,
           let options = preferredRenderOptions(
               forFamilyID: currentFigureFamily?.id,
               templateID: currentRecipe.templateID
           )
        {
            return options
        }
        return plotSession.renderOptions
    }

    func handleImportedFiles(_ urls: [URL]) async {
        switch pendingImportKind {
        case .rawFiles:
            await handleImportedRawFiles(urls)
        case .existingWorkbook:
            await handleImportedWorkbooks(urls)
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
            let response = try await client.previewDataStudioSource(.init(inputPath: sampleURL.path))
            sourcePreview = response.preview
            sourceMatches = response.matches
            selectedSuggestionIDs = defaultSuggestionSelection(from: response.preview)
            selectedCandidateIDs = flattenedCandidateSelection(
                fromSuggestionIDs: selectedSuggestionIDs,
                preview: response.preview
            )
            templateDraftLabel = inferGroupName(from: importedSourceURLs)
            templateDraftDescription = "Template created from \(sampleURL.lastPathComponent)."
            selectInitialPreviewContext(from: response.preview)
            hoveredSuggestionID = nil
            hoveredPreviewRanges = []
            syncPinnedPreviewRanges()
            showAdvancedCandidates = false

            let directMatches = response.matches.filter(\.autoSelected)
            if directMatches.count == 1, let match = directMatches.first {
                selectedTemplateID = match.templateID
                await buildWorkbookFromPendingRawFiles(templateID: match.templateID)
            } else {
                selectedTemplateID = response.matches.first?.templateID ?? templates.first?.id
                importWizardStep = .resolver
                isImportResolverPresented = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importWithSelectedTemplate() async {
        guard let selectedTemplateID else {
            errorMessage = "Choose a parse template before importing the current raw files."
            return
        }
        isImportResolverPresented = false
        await Task.yield()
        await buildWorkbookFromPendingRawFiles(templateID: selectedTemplateID)
    }

    func beginCreateTemplateEditor() {
        guard let sourcePreview else {
            errorMessage = "Import a sample source file before creating a parse template."
            return
        }
        if selectedPreviewBlockID == nil {
            selectInitialPreviewContext(from: sourcePreview)
        }
        isImportResolverPresented = false
        hoveredSuggestionID = nil
        hoveredPreviewRanges = []
        reconcileSuggestionSelection()
        syncPinnedPreviewRanges()
        showAdvancedCandidates = false
        importWizardStep = .createTemplate
        isCreateTemplateEditorPresented = true
    }

    func dismissCreateTemplateEditor() {
        clearImportFlowError()
        returnToImportResolver()
    }

    func returnToImportResolver() {
        isCreateTemplateEditorPresented = false
        importWizardStep = .resolver
        isImportResolverPresented = true
    }

    func saveTemplateDraft() async {
        guard let template = await createTemplateFromDraft() else {
            return
        }
        selectedTemplateID = template.id
        isCreateTemplateEditorPresented = false
        importWizardStep = .resolver
        isImportResolverPresented = true
    }

    func saveTemplateAndContinueImport() async {
        guard let template = await createTemplateFromDraft() else {
            return
        }
        selectedTemplateID = template.id
        isCreateTemplateEditorPresented = false
        await Task.yield()
        await buildWorkbookFromPendingRawFiles(templateID: template.id)
    }

    private func createTemplateFromDraft() async -> DataStudioTemplateResponse? {
        guard let sourceURL = importedSourceURLs.first, let client else {
            errorMessage = "Import a sample source file before saving a new parse template."
            return nil
        }
        let label = templateDraftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            errorMessage = "Provide a parse template name before saving it."
            return nil
        }
        currentActivity = .creatingTemplate
        errorMessage = nil
        defer { currentActivity = .idle }
        do {
            let template = try await client.createDataStudioTemplate(
                .init(
                    sourcePath: sourceURL.path,
                    label: label,
                    acceptedCandidateIDs: selectedCandidateIDs,
                    templateID: nil,
                    description: templateDraftDescription
                )
            )
            if let index = templates.firstIndex(where: { $0.id == template.id }) {
                templates[index] = template
            } else {
                templates.append(template)
            }
            templates.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            return template
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func dismissImportResolver() {
        clearImportFlowError()
        isImportWizardPresented = false
        isImportResolverPresented = false
        resetImportPresentationState()
        discardPendingSourcePreview()
    }

    func selectPreviewSheet(name: String) {
        guard let preview = sourcePreview else {
            return
        }
        selectedPreviewSheetName = name
        let blocks = preview.sheets.first(where: { $0.sheetName == name })?.blocks ?? []
        if let selectedPreviewBlockID,
           blocks.contains(where: { $0.id == selectedPreviewBlockID })
        {
            return
        }
        selectedPreviewBlockID = blocks.first?.id
    }

    func selectPreviewBlock(id: String) {
        guard let preview = sourcePreview else {
            return
        }
        for sheet in preview.sheets where sheet.blocks.contains(where: { $0.id == id }) {
            selectedPreviewSheetName = sheet.sheetName
            selectedPreviewBlockID = id
            return
        }
    }

    func setHoveredSuggestion(id: String?) {
        hoveredSuggestionID = id
        guard let id, let suggestion = suggestion(for: id) else {
            hoveredPreviewRanges = []
            return
        }
        hoveredPreviewRanges = suggestion.previewRanges
        focusPreview(onSuggestion: suggestion)
    }

    func toggleSuggestion(id: String) {
        if selectedSuggestionIDs.contains(id) {
            if let suggestion = suggestion(for: id) {
                selectedCandidateIDs.removeAll { suggestion.candidateIDs.contains($0) }
            }
            selectedSuggestionIDs.removeAll { $0 == id }
        } else {
            selectedSuggestionIDs.append(id)
            if let suggestion = suggestion(for: id) {
                for candidateID in suggestion.candidateIDs where !selectedCandidateIDs.contains(candidateID) {
                    selectedCandidateIDs.append(candidateID)
                }
            }
        }
        reconcileSuggestionSelection()
        syncPinnedPreviewRanges()
        if let suggestion = suggestion(for: id) {
            focusPreview(onSuggestion: suggestion)
        }
    }

    func setCandidateSelection(id: String, isSelected: Bool) {
        if isSelected {
            if !selectedCandidateIDs.contains(id) {
                selectedCandidateIDs.append(id)
            }
        } else {
            selectedCandidateIDs.removeAll { $0 == id }
        }
        reconcileSuggestionSelection()
        syncPinnedPreviewRanges()
        if let candidate = sourcePreview?.fieldCandidates.first(where: { $0.id == id }) {
            focusPreview(on: candidate)
        }
    }

    func focusPreview(on candidate: DataStudioFieldCandidateResponse) {
        selectedPreviewSheetName = candidate.sheetName
        if let blockID = candidate.blockID {
            selectedPreviewBlockID = blockID
        } else if let firstBlock = sourcePreview?
            .sheets
            .first(where: { $0.sheetName == candidate.sheetName })?
            .blocks
            .first
        {
            selectedPreviewBlockID = firstBlock.id
        }
    }

    func focusPreview(onSuggestion suggestion: DataStudioBindingSuggestionResponse) {
        selectedPreviewSheetName = suggestion.sheetName
        if let blockID = suggestion.blockID {
            selectedPreviewBlockID = blockID
        }
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
            }
            isImportWizardPresented = false
            resetImportPresentationState()
            discardPendingSourcePreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func newSession() {
        resetContentState()
    }

    func clearCurrentSession() {
        resetContentState()
    }

    func focusWorkbook(path: String?) {
        let resolvedPath = path ?? orderedWorkbooks.first?.response.workbookPath
        focusedWorkbookPath = resolvedPath
        guard let resolvedPath else {
            closeSpecimenFilter()
            return
        }
        ensureSpecimenFilterDataPreloaded(for: resolvedPath)
        if let specimenFilterAnchor {
            self.specimenFilterAnchor = specimenFilterAnchor.retargeted(to: resolvedPath)
        }
    }

    func updateDisplayName(for workbookPath: String, to displayName: String) {
        let previousSnapshot = undoSnapshot()
        setGroupState(
            workbookPath: workbookPath,
            displayName: displayName,
            includeInCompare: groupState(for: workbookPath)?.includeInCompare ?? true
        )
        scheduleComparisonContextRebuild()
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Rename Group")
    }

    func updateCompareInclusion(for workbookPath: String, includeInCompare: Bool) {
        let previousSnapshot = undoSnapshot()
        setGroupState(
            workbookPath: workbookPath,
            displayName: groupState(for: workbookPath)?.displayName ?? "",
            includeInCompare: includeInCompare
        )
        scheduleComparisonContextRebuild()
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Toggle Compare Inclusion")
    }

    func openSpecimenFilter(for workbookPath: String, anchor: DataStudioSpecimenFilterAnchor) {
        if let currentPath = specimenFilterWorkbookPath,
           currentPath != workbookPath,
           hasPendingFilterChanges(for: currentPath)
        {
            revertDraftSpecimenStates(for: currentPath)
        }
        focusedWorkbookPath = workbookPath
        specimenFilterAnchor = anchor
        primeDraftSpecimenStates(for: workbookPath)
        ensureSpecimenFilterDataPreloaded(for: workbookPath)
    }

    func openSpecimenFilter(for workbookPath: String) {
        openSpecimenFilter(for: workbookPath, anchor: .focusedStrip(workbookPath: workbookPath))
    }

    func closeSpecimenFilter() {
        guard let workbookPath = specimenFilterWorkbookPath else {
            dismissSpecimenFilter()
            return
        }
        if hasPendingFilterChanges(for: workbookPath) {
            revertDraftSpecimenStates(for: workbookPath)
        }
        dismissSpecimenFilter()
    }

    func retryPreviewRefresh() {
        guard let workbookPath = specimenFilterWorkbookPath ?? focusedWorkbook?.response.workbookPath else {
            Task { await rebuildComparisonContext() }
            return
        }
        scheduleWorkbookPreviewRefresh(for: workbookPath, rebuildComparisonContext: true)
        scheduleBaselineWorkbookPreviewRefresh(for: workbookPath)
    }

    func applySuggestedExclusions(for workbookPath: String) {
        let includedIDs = suggestedAutoIncludedSpecimenIDs(for: workbookPath)
        guard !includedIDs.isEmpty else {
            return
        }
        let allSpecimenIDs = Set(allKnownSpecimenIDs(for: workbookPath))
        applyCommittedSpecimenStates(
            for: workbookPath,
            includedIDs: includedIDs,
            explicitlyExcludedIDs: allSpecimenIDs.subtracting(includedIDs),
            actionName: "Use Auto Keep 5"
        )
    }

    func applySuggestedExclusionsToAllWorkbooks() {
        let presentation = bulkAutoKeepPresentation
        guard presentation.availability.isEnabled else {
            return
        }
        let previousSnapshot = undoSnapshot()
        var changedWorkbookPaths: [String] = []
        for workbookPath in presentation.eligibleWorkbookPaths {
            let includedIDs = suggestedAutoIncludedSpecimenIDs(for: workbookPath)
            guard !includedIDs.isEmpty else {
                continue
            }
            let allSpecimenIDs = Set(allKnownSpecimenIDs(for: workbookPath))
            let previousStates = normalizedSpecimenStates(specimenStates(for: workbookPath))
            setSpecimenInclusion(
                for: workbookPath,
                includedIDs: includedIDs,
                explicitlyExcludedIDs: allSpecimenIDs.subtracting(includedIDs)
            )
            if normalizedSpecimenStates(specimenStates(for: workbookPath)) != previousStates {
                changedWorkbookPaths.append(workbookPath)
            }
        }
        guard !changedWorkbookPaths.isEmpty else {
            return
        }
        for workbookPath in changedWorkbookPaths {
            scheduleWorkbookPreviewRefresh(for: workbookPath, rebuildComparisonContext: false)
        }
        scheduleComparisonContextRebuild()
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Use Auto Keep 5 for All Groups")
    }

    func restoreAllSpecimens(for workbookPath: String) {
        let specimenIDs = allKnownSpecimenIDs(for: workbookPath)
        guard !specimenIDs.isEmpty else {
            return
        }
        applyCommittedSpecimenStates(
            for: workbookPath,
            includedIDs: Set(specimenIDs),
            explicitlyExcludedIDs: [],
            actionName: "Turn Off Filter"
        )
    }

    func updateDraftSpecimenInclusion(for workbookPath: String, specimenId: String, included: Bool) {
        primeDraftSpecimenStates(for: workbookPath)
        let currentStates = upsertSpecimenState(
            in: draftSpecimenStates(for: workbookPath),
            workbookPath: workbookPath,
            specimenId: specimenId,
            included: included
        )
        draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(currentStates)
    }

    func updateDraftRepresentativeSelection(for workbookPath: String, specimenId: String) {
        primeDraftSpecimenStates(for: workbookPath)
        let currentStates = setRepresentativeSelection(
            in: draftSpecimenStates(for: workbookPath),
            workbookPath: workbookPath,
            specimenId: specimenId
        )
        draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(currentStates)
    }

    func restoreAutoRepresentativeSelection(for workbookPath: String) {
        primeDraftSpecimenStates(for: workbookPath)
        let currentStates = setRepresentativeSelection(
            in: draftSpecimenStates(for: workbookPath),
            workbookPath: workbookPath,
            specimenId: nil
        )
        draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(currentStates)
    }

    func applyManualFilter(for workbookPath: String, completion: (() -> Void)? = nil) {
        primeDraftSpecimenStates(for: workbookPath)
        let draftStates = normalizedSpecimenStates(draftSpecimenStates(for: workbookPath))
        let previousSnapshot = undoSnapshot()
        specimenStatesByWorkbookPath[workbookPath] = draftStates
        scheduleWorkbookPreviewRefresh(for: workbookPath, rebuildComparisonContext: true)
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Apply Specimen Filter Changes")
        completion?()
    }

    func revertDraftSpecimenStates(for workbookPath: String) {
        draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(specimenStates(for: workbookPath))
    }

    func updateSpecimenInclusion(for workbookPath: String, specimenId: String, included: Bool) {
        let previousSnapshot = undoSnapshot()
        let currentStates = upsertSpecimenState(
            in: specimenStates(for: workbookPath),
            workbookPath: workbookPath,
            specimenId: specimenId,
            included: included
        )
        specimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(currentStates)
        scheduleWorkbookPreviewRefresh(for: workbookPath, rebuildComparisonContext: true)
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Toggle Specimen Inclusion")
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        let previousSnapshot = undoSnapshot()
        var ordered = orderedGroups.map(\.state)
        ordered.move(fromOffsets: source, toOffset: destination)
        groupStates = ordered.enumerated().map { index, state in
            DataStudioGroupStatePayload(
                workbookPath: state.workbookPath,
                displayName: state.displayName,
                includeInCompare: state.includeInCompare,
                sortOrder: index
            )
        }
        scheduleComparisonContextRebuild()
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Reorder Groups")
    }

    func removeWorkbook(path: String) {
        asyncCoordination.workbookPreview.cancel(for: path)
        asyncCoordination.baselineWorkbookPreview.cancel(for: path)
        workbooks.removeAll { $0.response.workbookPath == path }
        groupStates.removeAll { $0.workbookPath == path }
        specimenStatesByWorkbookPath.removeValue(forKey: path)
        draftSpecimenStatesByWorkbookPath.removeValue(forKey: path)
        workbookPreviewByPath.removeValue(forKey: path)
        baselineWorkbookPreviewByPath.removeValue(forKey: path)
        if specimenFilterWorkbookPath == path {
            dismissSpecimenFilter()
        }
        selectedComparisonFigureID = nil
        reindexGroupStates()
        if focusedWorkbookPath == path {
            focusedWorkbookPath = orderedWorkbooks.first?.response.workbookPath
        }
        Task { await rebuildComparisonContext() }
    }

    func selectFigureFamily(id: String) {
        let previousSnapshot = undoSnapshot()
        cacheCurrentFigureOptions()
        selectedFigureFamilyID = id
        syncFigureSelection()
        stageCurrentFigurePreview()
        Task { await refreshDisplayedFigureHandlingFailure() }
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Change Figure Family")
    }

    func selectFigureTemplate(id: String) {
        guard let family = currentFigureFamily else {
            return
        }
        let previousSnapshot = undoSnapshot()
        cacheCurrentFigureOptions()
        setFigurePreference(familyID: family.id, selectedTemplateID: id)
        selectedFigureTemplateID = id
        syncFigureSelection()
        stageCurrentFigurePreview()
        Task { await refreshDisplayedFigureHandlingFailure() }
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Change Figure Template")
    }

    func openCurrentFigureInPlot() {
        guard
            let inputURL = currentFigureSourceURL,
            let templateID = currentFigureTemplateID
        else {
            return
        }
        openInPlotHandler?(inputURL, currentFigureSheet, templateID, currentFigureRenderOptions)
    }

    func revealFocusedWorkbook() {
        guard let focusedWorkbook else {
            return
        }
        WorkspaceBridge.reveal([focusedWorkbook.workbookURL])
    }

    func openFocusedWorkbook() {
        guard let focusedWorkbook else {
            return
        }
        WorkspaceBridge.open(focusedWorkbook.workbookURL)
    }

    func revealLatestExport() {
        if let comparisonExportDestinationURL {
            WorkspaceBridge.reveal([comparisonExportDestinationURL])
        } else if let focusedWorkbook {
            WorkspaceBridge.reveal([focusedWorkbook.workbookURL])
        }
    }

    func openLatestComparisonWorkbook() {
        guard let latestComparisonWorkbookURL else {
            return
        }
        WorkspaceBridge.open(latestComparisonWorkbookURL)
    }

    func openSelectedComparisonFigure() {
        guard let selectedComparisonFigure else {
            return
        }
        WorkspaceBridge.open(selectedComparisonFigure.url)
    }

    func openFilteredWorkbook(id: String) {
        guard let item = comparisonFilteredWorkbookItems.first(where: { $0.id == id }) else {
            return
        }
        WorkspaceBridge.open(item.url)
    }

    func selectComparisonFigure(id: String) {
        selectedComparisonFigureID = id
    }

    func exportComparisonBundle() async {
        guard let client, comparisonSet != nil else {
            errorMessage = "Import at least one workbook group before exporting a Data Studio figure bundle."
            return
        }
        let recipeIDs = selectedExportRecipeIDs
        guard !recipeIDs.isEmpty else {
            errorMessage = "Choose at least one figure family before exporting the Data Studio bundle."
            return
        }
        guard let directoryURL = chooseDirectory(
            "Export Data Studio Bundle",
            "Choose a destination folder for the comparison workbook, filtered workbooks, and figure outputs."
        ) else {
            return
        }
        guard let figureFormat = chooseComparisonFigureFormat(
            "Comparison Figure Format",
            "Choose whether the exported Data Studio figures should stay as editable PDF or convert to 300 dpi TIFF."
        ) else {
            return
        }

        cacheCurrentFigureOptions()
        isBusy = true
        currentActivity = .exportingComparison
        errorMessage = nil
        defer {
            isBusy = false
            currentActivity = .idle
        }

        do {
            let response = try await client.exportDataStudioComparison(
                .init(
                    workbookPaths: orderedWorkbooks.map { $0.response.workbookPath },
                    outputDir: directoryURL.path,
                    groupStates: requestGroupStates,
                    specimenStates: requestSpecimenStates,
                    selectedRecipeIDs: recipeIDs,
                    figureOptionsByRecipeID: exportFigureOptionsByRecipeID()
                )
            )
            comparisonExportResponse = response
            comparisonSet = response.comparisonSet
            comparisonFilteredWorkbookItems = response.filteredWorkbooks.map { output in
                DataStudioExportFilteredWorkbookItem(
                    id: output.path,
                    response: output,
                    url: URL(fileURLWithPath: output.path)
                )
            }
            let sourceURLs = response.figureOutputs.map { URL(fileURLWithPath: $0.path) }
            let materialized = try materializeComparisonOutputs(sourceURLs, figureFormat)
            comparisonFigureItems = zip(response.figureOutputs, materialized).map { output, url in
                DataStudioExportFigureItem(id: output.path, response: output, url: url)
            }
            selectedComparisonFigureID = comparisonFigureItems.first?.id
            comparisonExportDestinationURL = directoryURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func normalizeSessionPayload() async -> DataStudioSessionResponse? {
        guard let client else {
            return nil
        }
        cacheCurrentFigureOptions()
        let payload: [String: JSONValue] = [
            "version": .number(1),
            "selected_template_id": selectedTemplateID.map(JSONValue.string) ?? .null,
            "selected_workbook_id": focusedWorkbook.map { .string($0.response.workbookID) } ?? .null,
            "primary_workbook_id": focusedWorkbook.map { .string($0.response.workbookID) } ?? .null,
            "selected_recipe_id": currentRecipe.map { .string($0.id) } ?? .null,
            "workbook_paths": .array(orderedWorkbooks.map { .string($0.response.workbookPath) }),
            "comparison_recipe_ids": .array(selectedExportRecipeIDs.map(JSONValue.string)),
            "selected_figure_family_id": selectedFigureFamilyID.map(JSONValue.string) ?? .null,
            "selected_figure_template_id": selectedFigureTemplateID.map(JSONValue.string) ?? .null,
            "group_states": .array(requestGroupStates.map(jsonValue(for:))),
            "specimen_states": .array(requestSpecimenStates.map(jsonValue(for:))),
            "figure_preferences": .array(
                figurePreferences
                    .sorted { $0.familyID.localizedCaseInsensitiveCompare($1.familyID) == .orderedAscending }
                    .map(jsonValue(for:))
            ),
            "imported_paths": .array(importedSourceURLs.map { .string($0.path) }),
            "template_draft_path": importedSourceURLs.first.map { .string($0.path) } ?? .null,
        ]
        do {
            return try await client.normalizeDataStudioSession(.init(payload: payload))
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func restoreSession(from payload: DataStudioSessionResponse) async {
        resetContentState()
        selectedTemplateID = payload.selectedTemplateID
        selectedFigureFamilyID = payload.selectedFigureFamilyID
        selectedFigureTemplateID = payload.selectedFigureTemplateID
        selectedRecipeID = payload.selectedRecipeID
        importedSourceURLs = payload.importedPaths.map(URL.init(fileURLWithPath:))
        figurePreferences = payload.figurePreferences

        if !payload.workbookPaths.isEmpty {
            pendingImportDisposition = .addToCurrentSession
            await handleImportedWorkbooks(payload.workbookPaths.map(URL.init(fileURLWithPath:)), refreshContext: false)
        }

        if !payload.groupStates.isEmpty {
            applyRestoredGroupStates(payload.groupStates)
        } else {
            reindexGroupStates()
        }
        applyRestoredSpecimenStates(payload.specimenStates)

        focusedWorkbookPath = resolveRestoredWorkbookPath(
            selectedWorkbookID: payload.selectedWorkbookID,
            primaryWorkbookID: payload.primaryWorkbookID
        )

        await rebuildComparisonContext(refreshWorkbookPreviews: true)
    }

    func renameSelectedTemplate(to newLabel: String) async {
        guard let client, let selectedTemplate = selectedTemplate else {
            return
        }
        guard !selectedTemplate.builtin else {
            errorMessage = "Built-in parse templates cannot be renamed."
            return
        }
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Parse template name cannot be empty."
            return
        }
        errorMessage = nil
        do {
            let response = try await client.updateDataStudioTemplate(
                templateID: selectedTemplate.id,
                request: .init(newID: nil, newLabel: trimmed)
            )
            if let index = templates.firstIndex(where: { $0.id == selectedTemplate.id }) {
                templates[index] = response
            }
            selectedTemplateID = response.id
            templates.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelectedTemplate() async {
        guard let client, let selectedTemplate else {
            return
        }
        guard !selectedTemplate.builtin else {
            errorMessage = "Built-in parse templates cannot be deleted."
            return
        }
        errorMessage = nil
        do {
            try await client.deleteDataStudioTemplate(templateID: selectedTemplate.id)
            templates.removeAll { $0.id == selectedTemplate.id }
            if selectedTemplateID == selectedTemplate.id {
                selectedTemplateID = templates.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var selectedTemplate: DataStudioTemplateResponse? {
        guard let selectedTemplateID else {
            return nil
        }
        return templates.first(where: { $0.id == selectedTemplateID })
    }

    private var requestGroupStates: [DataStudioGroupStatePayload] {
        orderedWorkbooks.enumerated().map { index, workbook in
            let existing = groupState(for: workbook.response.workbookPath)
            return DataStudioGroupStatePayload(
                workbookPath: workbook.response.workbookPath,
                displayName: normalizedDisplayName(for: workbook, override: existing?.displayName),
                includeInCompare: existing?.includeInCompare ?? true,
                sortOrder: index
            )
        }
    }

    private var requestSpecimenStates: [DataStudioSpecimenStatePayload] {
        specimenStatesByWorkbookPath
            .keys
            .sorted()
            .flatMap { workbookPath in
                (specimenStatesByWorkbookPath[workbookPath] ?? []).sorted { lhs, rhs in
                    lhs.specimenId.localizedCaseInsensitiveCompare(rhs.specimenId) == .orderedAscending
                }
            }
    }

    private var selectedExportRecipeIDs: [String] {
        figureFamilies.compactMap { family in
            recipe(forFamilyID: family.id)?.id
        }
    }

    private func buildWorkbookFromPendingRawFiles(templateID: String) async {
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
            isImportWizardPresented = false
            isImportResolverPresented = false
            isCreateTemplateEditorPresented = false
            resetImportPresentationState()
            discardPendingSourcePreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rebuildComparisonContext(
        refreshWorkbookPreviews: Bool = false,
        revision: Int? = nil
    ) async {
        guard let client else {
            return
        }
        let activeRevision = revision ?? asyncCoordination.comparisonRefresh.beginNow()
        cacheCurrentFigureOptions()
        guard asyncCoordination.comparisonRefresh.isLatest(activeRevision), !Task.isCancelled else {
            return
        }
        let workbookPaths = orderedWorkbooks.map { $0.response.workbookPath }
        guard !workbookPaths.isEmpty else {
            clearComparisonContext()
            return
        }
        guard requestGroupStates.contains(where: \.includeInCompare) else {
            clearComparisonContext()
            return
        }

        currentActivity = .previewingComparison
        errorMessage = nil
        previewWarning = nil
        defer { currentActivity = .idle }
        do {
            if refreshWorkbookPreviews {
                await refreshFocusedWorkbookPreviewIfNeeded()
                guard asyncCoordination.comparisonRefresh.isLatest(activeRevision), !Task.isCancelled else {
                    return
                }
            }
            let previousComparisonSet = comparisonSet
            let previousCacheKey = comparisonContextCacheKey
            let previousMaterializedAt = comparisonContextMaterializedAt
            let previousSelectedFigureFamilyID = selectedFigureFamilyID
            let previousSelectedFigureTemplateID = selectedFigureTemplateID
            let previousSelectedRecipeID = selectedRecipeID

            let response = try await client.comparisonContextDataStudio(
                .init(
                    workbookPaths: workbookPaths,
                    groupStates: requestGroupStates,
                    specimenStates: requestSpecimenStates
                )
            )
            guard asyncCoordination.comparisonRefresh.isLatest(activeRevision), !Task.isCancelled else {
                return
            }
            comparisonSet = response.comparisonSet
            comparisonContextCacheKey = response.cacheKey
            comparisonContextMaterializedAt = response.materializedAt
            syncFigureSelection(preferredRecipeID: previousSelectedRecipeID)
            do {
                try await refreshDisplayedFigure()
                guard asyncCoordination.comparisonRefresh.isLatest(activeRevision), !Task.isCancelled else {
                    return
                }
                previewWarning = nil
                isPreviewStale = false
            } catch {
                guard asyncCoordination.comparisonRefresh.isLatest(activeRevision), !Task.isCancelled else {
                    return
                }
                comparisonSet = previousComparisonSet
                comparisonContextCacheKey = previousCacheKey
                comparisonContextMaterializedAt = previousMaterializedAt
                selectedFigureFamilyID = previousSelectedFigureFamilyID
                selectedFigureTemplateID = previousSelectedFigureTemplateID
                selectedRecipeID = previousSelectedRecipeID
                syncFigureSelection(preferredRecipeID: previousSelectedRecipeID)
                if previousComparisonSet != nil {
                    await restoreCommittedComparisonFigure()
                    previewWarning = "Refresh failed, showing last successful preview."
                    isPreviewStale = true
                } else {
                    clearComparisonContext()
                    previewWarning = error.localizedDescription
                    isPreviewStale = false
                }
            }
        } catch {
            guard asyncCoordination.comparisonRefresh.isLatest(activeRevision), !Task.isCancelled else {
                return
            }
            if comparisonSet != nil {
                previewWarning = "Refresh failed, showing last successful preview."
                isPreviewStale = true
            } else {
                previewWarning = error.localizedDescription
            }
        }
    }

    private func refreshDisplayedFigure() async throws {
        guard let comparisonSet, let currentRecipe else {
            return
        }
        let preferredOptions = preferredRenderOptions(forFamilyID: currentFigureFamily?.id, templateID: currentRecipe.templateID)
        selectedRecipeID = currentRecipe.id
        selectedFigureTemplateID = currentRecipe.templateID
        plotSession.stageExternalFigure(
            inputURL: URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath),
            sheet: .name(currentRecipe.sheetName),
            preferredTemplateID: currentRecipe.templateID,
            preferredOptions: preferredOptions
        )
        await plotSession.finishLoadingStagedExternalFigure(
            preferredTemplateID: currentRecipe.templateID,
            preferredOptions: preferredOptions,
            expectedInputURL: URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath),
            expectedSheet: .name(currentRecipe.sheetName)
        )
        if let plotError = plotSession.errorMessage, !plotError.isEmpty {
            if shouldSuppressPlotError(plotError, comparisonWorkbookPath: comparisonSet.comparisonWorkbookPath) {
                plotSession.errorMessage = nil
            } else {
                throw NSError(
                    domain: "DataStudioPreview",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: plotError]
                )
            }
        }
        plotSession.errorMessage = nil
        errorMessage = nil
    }

    private func refreshDisplayedFigureHandlingFailure() async {
        do {
            try await refreshDisplayedFigure()
            previewWarning = nil
            isPreviewStale = false
        } catch {
            if comparisonSet != nil {
                previewWarning = "Refresh failed, showing last successful preview."
                isPreviewStale = true
            } else {
                previewWarning = error.localizedDescription
            }
        }
    }

    private func stageCurrentFigurePreview() {
        guard let comparisonSet, let currentRecipe else {
            plotSession.clearPreviewContext(preserveRenderOptions: true)
            return
        }
        let preferredOptions = preferredRenderOptions(forFamilyID: currentFigureFamily?.id, templateID: currentRecipe.templateID)
        selectedRecipeID = currentRecipe.id
        selectedFigureTemplateID = currentRecipe.templateID
        plotSession.stageExternalFigure(
            inputURL: URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath),
            sheet: .name(currentRecipe.sheetName),
            preferredTemplateID: currentRecipe.templateID,
            preferredOptions: preferredOptions
        )
    }

    private func restoreCommittedComparisonFigure() async {
        guard comparisonSet != nil else {
            return
        }
        stageCurrentFigurePreview()
        try? await refreshDisplayedFigure()
    }

    private func scheduleComparisonContextRebuild() {
        asyncCoordination.comparisonRefresh.schedule(delayNanoseconds: comparisonRefreshDelayNanoseconds) { [weak self] revision in
            guard let self else {
                return
            }
            await self.rebuildComparisonContext(revision: revision)
        }
    }

    private func clearComparisonContext() {
        comparisonSet = nil
        comparisonContextCacheKey = nil
        comparisonContextMaterializedAt = nil
        comparisonExportResponse = nil
        comparisonFigureItems = []
        comparisonFilteredWorkbookItems = []
        selectedComparisonFigureID = nil
        comparisonExportDestinationURL = nil
        previewWarning = nil
        isPreviewStale = false
        plotSession.clearPreviewContext(preserveRenderOptions: true)
    }

    private func upsertWorkbook(_ response: DataStudioWorkbookResponse, shouldFocus: Bool) {
        let item = DataStudioWorkbookItem(id: response.workbookID, response: response)
        if let index = workbooks.firstIndex(where: { $0.response.workbookPath == response.workbookPath }) {
            workbooks[index] = item
        } else {
            workbooks.append(item)
        }
        let existingState = groupState(for: response.workbookPath)
        if existingState == nil {
            groupStates.append(
                DataStudioGroupStatePayload(
                    workbookPath: response.workbookPath,
                    displayName: seededDisplayName(for: response),
                    includeInCompare: true,
                    sortOrder: groupStates.count
                )
            )
        }
        reindexGroupStates()
        if shouldFocus || focusedWorkbookPath == nil {
            focusedWorkbookPath = response.workbookPath
        }
        if specimenStatesByWorkbookPath[response.workbookPath] == nil {
            specimenStatesByWorkbookPath[response.workbookPath] = []
        }
        ensureSpecimenFilterDataPreloaded(for: response.workbookPath)
    }

    private func applyRestoredGroupStates(_ restoredStates: [DataStudioGroupStatePayload]) {
        let validPaths = Set(workbooks.map { $0.response.workbookPath })
        let filtered = restoredStates.filter { validPaths.contains($0.workbookPath) }
        let existingPaths = Set(filtered.map(\.workbookPath))
        var merged = filtered
        for workbook in orderedWorkbooks where !existingPaths.contains(workbook.response.workbookPath) {
            merged.append(
                DataStudioGroupStatePayload(
                    workbookPath: workbook.response.workbookPath,
                    displayName: seededDisplayName(for: workbook),
                    includeInCompare: true,
                    sortOrder: merged.count
                )
            )
        }
        groupStates = merged
        reindexGroupStates()
    }

    private func applyRestoredSpecimenStates(_ restoredStates: [DataStudioSpecimenStatePayload]) {
        let validPaths = Set(workbooks.map { $0.response.workbookPath })
        let filtered = restoredStates.filter { validPaths.contains($0.workbookPath) }
        specimenStatesByWorkbookPath = Dictionary(grouping: filtered, by: \.workbookPath)
            .mapValues(normalizedSpecimenStates)
    }

    private func refreshFocusedWorkbookPreviewIfNeeded() async {
        if let workbookPath = specimenFilterWorkbookPath ?? focusedWorkbook?.response.workbookPath {
            await refreshWorkbookPreview(for: workbookPath)
            if baselineWorkbookPreview(for: workbookPath) == nil {
                await refreshBaselineWorkbookPreview(for: workbookPath)
            }
        }
    }

    private func scheduleWorkbookPreviewRefresh(for workbookPath: String, rebuildComparisonContext: Bool) {
        asyncCoordination.workbookPreview.schedule(for: workbookPath) { [weak self] workbookPath, revision in
            guard let self else {
                return
            }
            await self.refreshWorkbookPreview(for: workbookPath, revision: revision)
            guard self.asyncCoordination.workbookPreview.isLatest(for: workbookPath, revision: revision), !Task.isCancelled else {
                return
            }
            if rebuildComparisonContext {
                self.scheduleComparisonContextRebuild()
            }
        }
    }

    private func scheduleBaselineWorkbookPreviewRefresh(for workbookPath: String) {
        asyncCoordination.baselineWorkbookPreview.schedule(for: workbookPath) { [weak self] workbookPath, revision in
            guard let self else {
                return
            }
            await self.refreshBaselineWorkbookPreview(for: workbookPath, revision: revision)
        }
    }

    private func ensureSpecimenFilterDataPreloaded(for workbookPath: String) {
        if workbookPreview(for: workbookPath) == nil {
            scheduleWorkbookPreviewRefresh(for: workbookPath, rebuildComparisonContext: false)
        }
        if baselineWorkbookPreview(for: workbookPath) == nil {
            scheduleBaselineWorkbookPreviewRefresh(for: workbookPath)
        }
    }

    private func tracksAppliedWorkbookPreviewRefreshState(for workbookPath: String) -> Bool {
        let trackedPath = specimenFilterWorkbookPath ?? focusedWorkbook?.response.workbookPath
        return trackedPath == workbookPath
    }

    private func refreshWorkbookPreview(for workbookPath: String, revision: Int? = nil) async {
        guard let client else {
            return
        }
        let activeRevision = revision ?? asyncCoordination.workbookPreview.beginNow(for: workbookPath)
        if tracksAppliedWorkbookPreviewRefreshState(for: workbookPath) {
            focusedWorkbookPreviewRefreshState = .refreshing(workbookPath: workbookPath)
        }
        do {
            let response = try await client.previewDataStudioWorkbook(
                .init(
                    workbookPath: workbookPath,
                    specimenStates: specimenStates(for: workbookPath)
                )
            )
            guard asyncCoordination.workbookPreview.isLatest(for: workbookPath, revision: activeRevision), !Task.isCancelled else {
                return
            }
            workbookPreviewByPath[workbookPath] = response
            synchronizeSpecimenStates(with: response)
            if tracksAppliedWorkbookPreviewRefreshState(for: workbookPath) {
                focusedWorkbookPreviewRefreshState = .idle
            }
        } catch {
            guard asyncCoordination.workbookPreview.isLatest(for: workbookPath, revision: activeRevision), !Task.isCancelled else {
                return
            }
            if tracksAppliedWorkbookPreviewRefreshState(for: workbookPath) {
                focusedWorkbookPreviewRefreshState = .failed(
                    workbookPath: workbookPath,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func refreshBaselineWorkbookPreview(for workbookPath: String, revision: Int? = nil) async {
        guard let client else {
            return
        }
        let activeRevision = revision ?? asyncCoordination.baselineWorkbookPreview.beginNow(for: workbookPath)
        if tracksAppliedWorkbookPreviewRefreshState(for: workbookPath) {
            baselineWorkbookPreviewRefreshState = .refreshing(workbookPath: workbookPath)
        }
        do {
            let response = try await client.previewDataStudioWorkbook(.init(workbookPath: workbookPath))
            guard asyncCoordination.baselineWorkbookPreview.isLatest(for: workbookPath, revision: activeRevision), !Task.isCancelled else {
                return
            }
            baselineWorkbookPreviewByPath[workbookPath] = response
            if specimenStatesByWorkbookPath[workbookPath] == nil, response.supported {
                specimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(
                    response.specimens.map {
                        DataStudioSpecimenStatePayload(
                            workbookPath: workbookPath,
                            specimenId: $0.specimenId,
                            included: $0.included,
                            selectedAsRepresentative: false
                        )
                    }
                )
            }
            if draftSpecimenStatesByWorkbookPath[workbookPath] == nil {
                draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(specimenStates(for: workbookPath))
            }
            if tracksAppliedWorkbookPreviewRefreshState(for: workbookPath) {
                baselineWorkbookPreviewRefreshState = .idle
            }
        } catch {
            guard asyncCoordination.baselineWorkbookPreview.isLatest(for: workbookPath, revision: activeRevision), !Task.isCancelled else {
                return
            }
            if tracksAppliedWorkbookPreviewRefreshState(for: workbookPath) {
                baselineWorkbookPreviewRefreshState = .failed(
                    workbookPath: workbookPath,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func synchronizeSpecimenStates(with preview: DataStudioWorkbookPreviewResponse) {
        guard preview.supported else {
            return
        }
        let preservedRepresentativeSpecimenID = selectedRepresentativeSpecimenID(
            in: specimenStates(for: preview.workbookPath)
        )
        specimenStatesByWorkbookPath[preview.workbookPath] = normalizedSpecimenStates(preview.specimens.map {
            DataStudioSpecimenStatePayload(
                workbookPath: preview.workbookPath,
                specimenId: $0.specimenId,
                included: $0.included,
                selectedAsRepresentative: $0.included && $0.specimenId == preservedRepresentativeSpecimenID
            )
        })
        if !hasPendingFilterChanges(for: preview.workbookPath) {
            draftSpecimenStatesByWorkbookPath[preview.workbookPath] = normalizedSpecimenStates(specimenStates(for: preview.workbookPath))
        }
    }

    private func setSpecimenInclusion(
        for workbookPath: String,
        includedIDs: Set<String>,
        explicitlyExcludedIDs: Set<String>
    ) {
        let specimenIDs = allKnownSpecimenIDs(for: workbookPath)
        guard !specimenIDs.isEmpty else {
            return
        }
        let preservedRepresentativeSpecimenID = selectedRepresentativeSpecimenID(
            in: specimenStates(for: workbookPath)
        )
        specimenStatesByWorkbookPath[workbookPath] = specimenIDs.map { specimenId in
            let included = explicitlyExcludedIDs.contains(specimenId) ? false : includedIDs.contains(specimenId)
            return DataStudioSpecimenStatePayload(
                workbookPath: workbookPath,
                specimenId: specimenId,
                included: included,
                selectedAsRepresentative: included && specimenId == preservedRepresentativeSpecimenID
            )
        }
        draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(specimenStates(for: workbookPath))
    }

    private func allKnownSpecimenIDs(for workbookPath: String) -> [String] {
        let baselineIDs = baselineWorkbookPreview(for: workbookPath)?.specimens.map(\.specimenId) ?? []
        if !baselineIDs.isEmpty {
            return baselineIDs
        }
        let previewIDs = workbookPreview(for: workbookPath)?.specimens.map(\.specimenId) ?? []
        if !previewIDs.isEmpty {
            return previewIDs
        }
        let committedIDs = specimenStates(for: workbookPath).map(\.specimenId)
        if !committedIDs.isEmpty {
            return committedIDs
        }
        return draftSpecimenStates(for: workbookPath).map(\.specimenId)
    }

    private func primeDraftSpecimenStates(for workbookPath: String) {
        if draftSpecimenStatesByWorkbookPath[workbookPath] != nil {
            return
        }
        draftSpecimenStatesByWorkbookPath[workbookPath] = normalizedSpecimenStates(specimenStates(for: workbookPath))
    }

    private func applyCommittedSpecimenStates(
        for workbookPath: String,
        includedIDs: Set<String>,
        explicitlyExcludedIDs: Set<String>,
        actionName: String
    ) {
        let previousSnapshot = undoSnapshot()
        setSpecimenInclusion(
            for: workbookPath,
            includedIDs: includedIDs,
            explicitlyExcludedIDs: explicitlyExcludedIDs
        )
        scheduleWorkbookPreviewRefresh(for: workbookPath, rebuildComparisonContext: true)
        registerUndo(previousSnapshot: previousSnapshot, actionName: actionName)
    }

    private func normalizedSpecimenStates(_ states: [DataStudioSpecimenStatePayload]) -> [DataStudioSpecimenStatePayload] {
        var latestStatesBySpecimenID: [String: DataStudioSpecimenStatePayload] = [:]
        for state in states {
            latestStatesBySpecimenID[state.specimenId] = state
        }
        let normalizedRepresentativeSpecimenID = selectedRepresentativeSpecimenID(
            in: Array(latestStatesBySpecimenID.values)
        )
        return latestStatesBySpecimenID.values
            .map { state in
                DataStudioSpecimenStatePayload(
                    workbookPath: state.workbookPath,
                    specimenId: state.specimenId,
                    included: state.included,
                    selectedAsRepresentative: state.included && state.specimenId == normalizedRepresentativeSpecimenID
                )
            }
            .sorted { lhs, rhs in
                lhs.specimenId.localizedCaseInsensitiveCompare(rhs.specimenId) == .orderedAscending
            }
    }

    private func upsertSpecimenState(
        in states: [DataStudioSpecimenStatePayload],
        workbookPath: String,
        specimenId: String,
        included: Bool
    ) -> [DataStudioSpecimenStatePayload] {
        var updatedStates = states
        let selectedRepresentativeSpecimenID = selectedRepresentativeSpecimenID(in: states)
        let payload = DataStudioSpecimenStatePayload(
            workbookPath: workbookPath,
            specimenId: specimenId,
            included: included,
            selectedAsRepresentative: included && selectedRepresentativeSpecimenID == specimenId
        )
        if let index = updatedStates.firstIndex(where: { $0.specimenId == specimenId }) {
            updatedStates[index] = payload
        } else {
            updatedStates.append(payload)
        }
        return updatedStates
    }

    private func setRepresentativeSelection(
        in states: [DataStudioSpecimenStatePayload],
        workbookPath: String,
        specimenId: String?
    ) -> [DataStudioSpecimenStatePayload] {
        let selectedSpecimenID = specimenId.flatMap { candidate in
            states.contains(where: { $0.specimenId == candidate && $0.included }) ? candidate : nil
        }
        return states.map { state in
            DataStudioSpecimenStatePayload(
                workbookPath: workbookPath,
                specimenId: state.specimenId,
                included: state.included,
                selectedAsRepresentative: state.included && state.specimenId == selectedSpecimenID
            )
        }
    }

    private func selectedRepresentativeSpecimenID(
        in states: [DataStudioSpecimenStatePayload]
    ) -> String? {
        states.reversed().first(where: { $0.included && $0.selectedAsRepresentative })?.specimenId
    }

    private func specimenFilename(for workbookPath: String, specimenId: String?) -> String? {
        guard let specimenId else {
            return nil
        }
        if let filename = baselineWorkbookPreview(for: workbookPath)?
            .specimens
            .first(where: { $0.specimenId == specimenId })?
            .filename
        {
            return filename
        }
        if let filename = workbookPreview(for: workbookPath)?
            .specimens
            .first(where: { $0.specimenId == specimenId })?
            .filename
        {
            return filename
        }
        return specimenId
    }

    private func dismissSpecimenFilter() {
        specimenFilterAnchor = nil
        focusedWorkbookPreviewRefreshState = .idle
        baselineWorkbookPreviewRefreshState = .idle
    }

    private func resolveRestoredWorkbookPath(selectedWorkbookID: String?, primaryWorkbookID: String?) -> String? {
        let identifiers = [selectedWorkbookID, primaryWorkbookID].compactMap { $0 }
        for identifier in identifiers {
            if let workbook = workbooks.first(where: {
                $0.response.workbookID == identifier || $0.response.workbookPath == identifier
            }) {
                return workbook.response.workbookPath
            }
        }
        return orderedWorkbooks.first?.response.workbookPath
    }

    private func setGroupState(workbookPath: String, displayName: String, includeInCompare: Bool) {
        let existing = groupState(for: workbookPath)
        let sortOrder = existing?.sortOrder ?? groupStates.count
        let newState = DataStudioGroupStatePayload(
            workbookPath: workbookPath,
            displayName: displayName,
            includeInCompare: includeInCompare,
            sortOrder: sortOrder
        )
        if let index = groupStates.firstIndex(where: { $0.workbookPath == workbookPath }) {
            groupStates[index] = newState
        } else {
            groupStates.append(newState)
        }
        reindexGroupStates()
    }

    private func groupState(for workbookPath: String) -> DataStudioGroupStatePayload? {
        groupStates.first(where: { $0.workbookPath == workbookPath })
    }

    private func displayName(for workbook: DataStudioWorkbookItem) -> String {
        normalizedDisplayName(for: workbook, override: groupState(for: workbook.response.workbookPath)?.displayName)
    }

    private func normalizedDisplayName(for workbook: DataStudioWorkbookItem, override: String?) -> String {
        let trimmed = (override ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return seededDisplayName(for: workbook)
    }

    private func reindexGroupStates() {
        let orderedPaths = orderedWorkbooks.map { $0.response.workbookPath }
        let stateByPath = Dictionary(uniqueKeysWithValues: groupStates.map { ($0.workbookPath, $0) })
        groupStates = orderedPaths.enumerated().map { index, path in
            let state = stateByPath[path]
            let workbook = workbooks.first(where: { $0.response.workbookPath == path })
            return DataStudioGroupStatePayload(
                workbookPath: path,
                displayName: workbook.map { normalizedDisplayName(for: $0, override: state?.displayName) }
                    ?? seededDisplayName(workbookPath: path, responseLabel: state?.displayName ?? ""),
                includeInCompare: state?.includeInCompare ?? true,
                sortOrder: index
            )
        }
    }

    private func seededDisplayName(for workbook: DataStudioWorkbookItem) -> String {
        seededDisplayName(workbookPath: workbook.response.workbookPath, responseLabel: workbook.response.label)
    }

    private func seededDisplayName(for response: DataStudioWorkbookResponse) -> String {
        seededDisplayName(workbookPath: response.workbookPath, responseLabel: response.label)
    }

    private func seededDisplayName(workbookPath: String, responseLabel: String) -> String {
        let workbookStem = URL(fileURLWithPath: workbookPath)
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !workbookStem.isEmpty {
            return workbookStem
        }
        let trimmedLabel = responseLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty {
            return trimmedLabel
        }
        return "Workbook"
    }

    private func syncFigureSelection(preferredRecipeID: String? = nil) {
        guard !figureFamilies.isEmpty else {
            selectedFigureFamilyID = nil
            selectedFigureTemplateID = nil
            selectedRecipeID = nil
            return
        }

        let restoredFamily = figureFamilies.first(where: { $0.id == selectedFigureFamilyID })
        let recipeFromPreference = preferredRecipeID.flatMap { recipeID in
            comparisonSet?.recipes.first(where: { $0.id == recipeID })
        }
        let family = restoredFamily
            ?? recipeFromPreference.flatMap { recipe in
                familyFor(recipe: recipe)
            }
            ?? figureFamilies.first

        selectedFigureFamilyID = family?.id

        if let family {
            let selectedTemplate = selectedTemplateID(forFamilyID: family.id)
            let supportedTemplates = Set(family.recipes.filter(\.supported).map(\.templateID))
            if let selectedTemplate, supportedTemplates.contains(selectedTemplate) {
                selectedFigureTemplateID = selectedTemplate
            } else {
                let fallbackRecipe = preferredRecipe(in: family)
                selectedFigureTemplateID = fallbackRecipe?.templateID
                setFigurePreference(familyID: family.id, selectedTemplateID: fallbackRecipe?.templateID)
            }
        } else {
            selectedFigureTemplateID = nil
        }
        selectedRecipeID = currentRecipe?.id
        plotSession.selectedTemplateID = currentRecipe?.templateID ?? selectedFigureTemplateID
    }

    private func familyFor(recipe: DataStudioComparisonRecipeResponse) -> DataStudioFigureFamilyItem? {
        if let metricID = recipe.metricID, !metricID.isEmpty {
            return figureFamilies.first(where: { $0.id == normalizeFigureFamilyID(metricID) })
        }
        return figureFamilies.first(where: { $0.id == "representative_curve" })
    }

    private func recipe(forFamilyID familyID: String) -> DataStudioComparisonRecipeResponse? {
        guard let family = figureFamilies.first(where: { $0.id == familyID }) else {
            return nil
        }
        let selectedTemplateID = selectedTemplateID(forFamilyID: family.id)
        if let selectedTemplateID,
           let recipe = family.recipes.first(where: { $0.templateID == selectedTemplateID && $0.supported })
        {
            return recipe
        }
        return preferredRecipe(in: family)
    }

    private func preferredRecipe(in family: DataStudioFigureFamilyItem) -> DataStudioComparisonRecipeResponse? {
        let preferredTemplateOrder = [
            "curve",
            "box_strip",
            "grouped_bar_error",
            "point_error",
            "box",
            "bar",
            "violin",
        ]
        let supported = family.recipes.filter(\.supported)
        if let matched = preferredTemplateOrder.lazy.compactMap({ templateID in
            supported.first(where: { $0.templateID == templateID })
        }).first {
            return matched
        }
        return supported.first
    }

    private func selectedTemplateID(forFamilyID familyID: String) -> String? {
        if let preference = figurePreferences.first(where: { $0.familyID == familyID }),
           let selected = preference.selectedTemplateID
        {
            return selected
        }
        if selectedFigureFamilyID == familyID {
            return selectedFigureTemplateID
        }
        return nil
    }

    private func setFigurePreference(familyID: String, selectedTemplateID: String?) {
        if let index = figurePreferences.firstIndex(where: { $0.familyID == familyID }) {
            let existing = figurePreferences[index]
            figurePreferences[index] = DataStudioFigurePreferencePayload(
                familyID: familyID,
                selectedTemplateID: selectedTemplateID,
                optionsByTemplate: existing.optionsByTemplate
            )
        } else {
            figurePreferences.append(
                DataStudioFigurePreferencePayload(
                    familyID: familyID,
                    selectedTemplateID: selectedTemplateID,
                    optionsByTemplate: [:]
                )
            )
        }
    }

    private func storeCurrentFigureOptions(_ options: RenderOptionsPayload) {
        guard let familyID = currentFigureFamily?.id else {
            return
        }
        let templateID = plotSession.selectedTemplateID ?? selectedFigureTemplateID
        guard let templateID else {
            return
        }
        let existing = figurePreferences.first(where: { $0.familyID == familyID })
        var optionsByTemplate = existing?.optionsByTemplate ?? [:]
        optionsByTemplate[templateID] = options
        if let index = figurePreferences.firstIndex(where: { $0.familyID == familyID }) {
            figurePreferences[index] = DataStudioFigurePreferencePayload(
                familyID: familyID,
                selectedTemplateID: templateID,
                optionsByTemplate: optionsByTemplate
            )
        } else {
            figurePreferences.append(
                DataStudioFigurePreferencePayload(
                    familyID: familyID,
                    selectedTemplateID: templateID,
                    optionsByTemplate: optionsByTemplate
                )
            )
        }
        selectedFigureTemplateID = templateID
    }

    private func cacheCurrentFigureOptions() {
        storeCurrentFigureOptions(plotSession.renderOptions)
    }

    private func preferredRenderOptions(
        forFamilyID familyID: String?,
        templateID: String
    ) -> RenderOptionsPayload? {
        guard let familyID else {
            return nil
        }
        return figurePreferences
            .first(where: { $0.familyID == familyID })?
            .optionsByTemplate[templateID]
    }

    private func exportFigureOptionsByRecipeID() -> [String: RenderOptionsPayload] {
        var result: [String: RenderOptionsPayload] = [:]
        for family in figureFamilies {
            guard let recipe = recipe(forFamilyID: family.id) else {
                continue
            }
            if let options = preferredRenderOptions(forFamilyID: family.id, templateID: recipe.templateID) {
                result[recipe.id] = options
            } else if family.id == currentFigureFamily?.id {
                result[recipe.id] = plotSession.renderOptions
            }
        }
        return result
    }

    private var bulkAutoKeepPresentation: BulkAutoKeepPresentation {
        guard !orderedWorkbooks.isEmpty else {
            return BulkAutoKeepPresentation(
                eligibleWorkbookPaths: [],
                availability: .disabled("Import workbook groups before applying Auto Keep 5."),
                help: "Import workbook groups before applying Auto Keep 5."
            )
        }
        guard currentActivity == .idle else {
            return BulkAutoKeepPresentation(
                eligibleWorkbookPaths: [],
                availability: .disabled("Wait for the current refresh to finish before applying Auto Keep 5 to all groups."),
                help: "Wait for previews to finish before applying Auto Keep 5 to all groups."
            )
        }

        var eligibleWorkbookPaths: [String] = []
        var skippedCount = 0
        var loadingCount = 0

        for workbook in orderedWorkbooks {
            let workbookPath = workbook.response.workbookPath
            guard baselineWorkbookPreview(for: workbookPath) != nil else {
                loadingCount += 1
                continue
            }
            if specimenFilterPresentation(for: workbookPath).canApplyAuto {
                eligibleWorkbookPaths.append(workbookPath)
            } else {
                skippedCount += 1
            }
        }

        if loadingCount > 0 {
            let label = loadingCount == 1 ? "1 group" : "\(loadingCount) groups"
            return BulkAutoKeepPresentation(
                eligibleWorkbookPaths: [],
                availability: .disabled("Auto Keep 5 suggestions are still loading for \(label)."),
                help: "Auto Keep 5 suggestions are still loading for \(label)."
            )
        }

        guard !eligibleWorkbookPaths.isEmpty else {
            return BulkAutoKeepPresentation(
                eligibleWorkbookPaths: [],
                availability: .disabled("Auto Keep 5 is already current or unsupported for all workbook groups."),
                help: "Auto Keep 5 is already current or unsupported for all workbook groups."
            )
        }

        let applyLabel = eligibleWorkbookPaths.count == 1 ? "1 group" : "\(eligibleWorkbookPaths.count) groups"
        let help: String
        if skippedCount == 0 {
            help = "Apply Auto Keep 5 to \(applyLabel)."
        } else {
            let skippedLabel = skippedCount == 1 ? "1 group" : "\(skippedCount) groups"
            help = "Apply Auto Keep 5 to \(applyLabel) and skip \(skippedLabel) that are already current or unsupported."
        }
        return BulkAutoKeepPresentation(
            eligibleWorkbookPaths: eligibleWorkbookPaths,
            availability: .enabled(),
            help: help
        )
    }

    private func undoSnapshot() -> UndoSnapshot {
        UndoSnapshot(
            groupStates: groupStates,
            specimenStatesByWorkbookPath: specimenStatesByWorkbookPath,
            selectedFigureFamilyID: selectedFigureFamilyID,
            selectedFigureTemplateID: selectedFigureTemplateID,
            selectedRecipeID: selectedRecipeID,
            figurePreferences: figurePreferences
        )
    }

    private func registerUndo(previousSnapshot: UndoSnapshot, actionName: String) {
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

    private func restore(from snapshot: UndoSnapshot) {
        groupStates = snapshot.groupStates
        specimenStatesByWorkbookPath = snapshot.specimenStatesByWorkbookPath
        draftSpecimenStatesByWorkbookPath = snapshot.specimenStatesByWorkbookPath
        selectedFigureFamilyID = snapshot.selectedFigureFamilyID
        selectedFigureTemplateID = snapshot.selectedFigureTemplateID
        selectedRecipeID = snapshot.selectedRecipeID
        figurePreferences = snapshot.figurePreferences
        previewWarning = nil
        isPreviewStale = false
        scheduleComparisonContextRebuild()
    }

    private func resetContentState() {
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
        isImportWizardPresented = false
        importWizardStep = .kind
        isImportScopePresented = false
        isImportChooserPresented = false
        isImportResolverPresented = false
        isCreateTemplateEditorPresented = false
        plotSession.clearPreviewContext(preserveRenderOptions: true)
        previewWarning = nil
        isPreviewStale = false
        errorMessage = nil
        currentActivity = .idle
    }

    private func shouldSuppressPlotError(_ message: String, comparisonWorkbookPath: String) -> Bool {
        let lowered = message.lowercased()
        let comparisonName = URL(fileURLWithPath: comparisonWorkbookPath).lastPathComponent.lowercased()
        return lowered.contains(comparisonName)
            && lowered.contains("representative curve group")
            && lowered.contains("representative_curve")
    }

    private func scheduleImportPanelPresentation() {
        importPanelPresentationRevision += 1
        let revision = importPanelPresentationRevision
        isImportPresented = false
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.importPanelPresentationRevision == revision else {
                return
            }
            self.isImportPresented = true
        }
    }

    private func clearImportFlowError() {
        errorMessage = nil
    }

    private func resetImportPresentationState() {
        isImportPresented = false
        isImportWizardPresented = false
        importWizardStep = .kind
        isImportScopePresented = false
        isImportChooserPresented = false
        isImportResolverPresented = false
        isCreateTemplateEditorPresented = false
        pendingImportDisposition = .addToCurrentSession
        pendingImportKind = .rawFiles
    }

    private func discardPendingSourcePreview() {
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
        isCreateTemplateEditorPresented = false
    }

    private func isUserCancelled(_ error: Error) -> Bool {
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

    private func selectInitialPreviewContext(from preview: DataStudioRawFilePreviewResponse) {
        if let suggestion = preview.bindingSuggestions.first(where: \.defaultSelected) ?? preview.bindingSuggestions.first {
            selectedPreviewSheetName = suggestion.sheetName
            selectedPreviewBlockID = suggestion.blockID
            return
        }
        selectedPreviewSheetName = preview.sheets.first?.sheetName
        selectedPreviewBlockID = preview.sheets.first?.blocks.first?.id
    }

    private func defaultSuggestionSelection(from preview: DataStudioRawFilePreviewResponse) -> [String] {
        let primaryCurve = preferredCreateTemplateSuggestion(in: preview.bindingSuggestions, kind: "curve_pair")
        let preferredBlockID = primaryCurve?.blockID
        var selection: [String] = []
        if let primaryCurve {
            selection.append(primaryCurve.id)
        }

        for kind in ["metric_group", "metadata_group", "structure_rows"] {
            let suggestion = preferredCreateTemplateSuggestion(
                in: preview.bindingSuggestions,
                kind: kind,
                preferredBlockID: preferredBlockID
            )
            if let suggestion, !selection.contains(suggestion.id) {
                selection.append(suggestion.id)
            }
        }

        if selection.isEmpty {
            selection = preview.bindingSuggestions
                .filter(\.defaultSelected)
                .map(\.id)
        }
        return selection
    }

    private func flattenedCandidateSelection(
        fromSuggestionIDs suggestionIDs: [String],
        preview: DataStudioRawFilePreviewResponse?
    ) -> [String] {
        guard let preview else {
            return []
        }
        let selectedSet = Set(suggestionIDs)
        var flattened: [String] = []
        for suggestion in preview.bindingSuggestions where selectedSet.contains(suggestion.id) {
            for candidateID in suggestion.candidateIDs where !flattened.contains(candidateID) {
                flattened.append(candidateID)
            }
        }
        return flattened
    }

    private func reconcileSuggestionSelection() {
        guard let preview = sourcePreview else {
            selectedSuggestionIDs = []
            return
        }
        let selectedSet = Set(selectedCandidateIDs)
        selectedSuggestionIDs = preview.bindingSuggestions
            .filter { !$0.candidateIDs.isEmpty && Set($0.candidateIDs).isSubset(of: selectedSet) }
            .map(\.id)
    }

    private func syncPinnedPreviewRanges() {
        guard let preview = sourcePreview else {
            pinnedPreviewRanges = []
            return
        }
        let selectedSet = Set(selectedSuggestionIDs)
        pinnedPreviewRanges = preview.bindingSuggestions
            .filter { selectedSet.contains($0.id) }
            .flatMap(\.previewRanges)
    }

    private func suggestion(for id: String) -> DataStudioBindingSuggestionResponse? {
        sourcePreview?.bindingSuggestions.first(where: { $0.id == id })
    }

    private func preferredCreateTemplateSuggestion(
        kind: String,
        preferredBlockID: String? = nil
    ) -> DataStudioBindingSuggestionResponse? {
        preferredCreateTemplateSuggestion(
            in: createTemplateSuggestions,
            kind: kind,
            preferredBlockID: preferredBlockID
        )
    }

    private func preferredCreateTemplateSuggestion(
        in suggestions: [DataStudioBindingSuggestionResponse],
        kind: String,
        preferredBlockID: String? = nil
    ) -> DataStudioBindingSuggestionResponse? {
        let matching = suggestions.filter { $0.kind == kind }
        if let preferredBlockID,
           let preferred = matching.first(where: { $0.blockID == preferredBlockID })
        {
            return preferred
        }
        return matching.first
    }

    private func selectedSuggestion(for kind: String) -> DataStudioBindingSuggestionResponse? {
        let selected = createTemplateSuggestions.filter { suggestion in
            suggestion.kind == kind && selectedSuggestionIDs.contains(suggestion.id)
        }
        if let preferredBlockID = createTemplatePrimaryCurveSuggestion?.blockID,
           let preferred = selected.first(where: { $0.blockID == preferredBlockID })
        {
            return preferred
        }
        return selected.first
    }

    private func candidate(for id: String) -> DataStudioFieldCandidateResponse? {
        sourcePreview?.fieldCandidates.first(where: { $0.id == id })
    }

    private func displayLabel(
        forCandidateID id: String,
        includeUnit: Bool = false
    ) -> String? {
        guard let candidate = candidate(for: id) else {
            return nil
        }
        if includeUnit,
           let unitHint = candidate.unitHint,
           !unitHint.isEmpty,
           !candidate.label.localizedCaseInsensitiveContains(unitHint)
        {
            return "\(candidate.label) (\(unitHint))"
        }
        return candidate.label
    }

    private func selectedLabels(for kind: String, includeUnit: Bool = false) -> [String] {
        let selectedIDs = Set(selectedCandidateIDs)
        var labels: [String] = []
        for candidate in sourcePreview?.fieldCandidates ?? [] where candidate.kind == kind && selectedIDs.contains(candidate.id) {
            let label = displayLabel(forCandidateID: candidate.id, includeUnit: includeUnit) ?? candidate.label
            if !labels.contains(label) {
                labels.append(label)
            }
        }
        return labels
    }

    private var selectedCurveSummary: String? {
        if let suggestion = selectedSuggestion(for: "curve_pair") {
            let xLabel = suggestion.candidateIDs
                .compactMap { id -> String? in
                    guard candidate(for: id)?.kind == "curve_x" else { return nil }
                    return displayLabel(forCandidateID: id, includeUnit: true)
                }
                .first
            let yLabel = suggestion.candidateIDs
                .compactMap { id -> String? in
                    guard candidate(for: id)?.kind == "curve_y" else { return nil }
                    return displayLabel(forCandidateID: id, includeUnit: true)
                }
                .first
            if let xLabel, let yLabel {
                return "X = \(xLabel), Y = \(yLabel)"
            }
        }

        let xLabels = selectedLabels(for: "curve_x", includeUnit: true)
        let yLabels = selectedLabels(for: "curve_y", includeUnit: true)
        guard let xLabel = xLabels.first, let yLabel = yLabels.first else {
            return nil
        }
        return "X = \(xLabel), Y = \(yLabel)"
    }

    private var selectedMetricSummary: String? {
        let labels = selectedLabels(for: "metric")
        guard !labels.isEmpty else {
            return nil
        }
        return labels.joined(separator: ", ")
    }

    private var selectedMetadataSummary: String? {
        let labels = selectedLabels(for: "metadata")
        guard !labels.isEmpty else {
            return nil
        }
        return labels.joined(separator: ", ")
    }

    private var selectedStructureSummary: String? {
        if let suggestion = selectedSuggestion(for: "structure_rows"), !suggestion.summary.isEmpty {
            return suggestion.summary
        }
        let selectedIDs = Set(selectedCandidateIDs)
        var parts: [String] = []
        for candidate in sourcePreview?.fieldCandidates ?? [] where selectedIDs.contains(candidate.id) {
            guard let range = candidate.range else {
                continue
            }
            switch candidate.kind {
            case "header_row":
                parts.append("Header Row \(range.startRow + 1)")
            case "unit_row":
                parts.append("Unit Row \(range.startRow + 1)")
            default:
                break
            }
        }
        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: ", ")
    }

    private func previewLocation(for suggestion: DataStudioBindingSuggestionResponse) -> String {
        guard let preview = sourcePreview else {
            return suggestion.sheetName
        }
        if let blockID = suggestion.blockID {
            for sheet in preview.sheets where sheet.sheetName == suggestion.sheetName {
                if let block = sheet.blocks.first(where: { $0.id == blockID }) {
                    return "\(sheet.sheetName) / \(block.label)"
                }
            }
        }
        return suggestion.sheetName
    }

    private func inferGroupName(from urls: [URL]) -> String {
        guard let first = urls.first else {
            return "DataStudio_Group"
        }
        return first.deletingPathExtension().lastPathComponent
    }

    private func normalizeFigureFamilyID(_ metricID: String) -> String {
        metricID
            .lowercased()
            .replacingOccurrences(of: " at ", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    private func figureFamilyComparator(_ lhs: String, _ rhs: String) -> Bool {
        let lhsPriority = figureFamilyPriority(lhs)
        let rhsPriority = figureFamilyPriority(rhs)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    private func figureFamilyPriority(_ familyID: String) -> Int {
        if familyID == "representative_curve" {
            return 0
        }
        if familyID.contains("strength") {
            return 1
        }
        if familyID.contains("modulus") {
            return 2
        }
        if familyID.contains("elongation") {
            return 3
        }
        return 9
    }

    private func specimenFilterSortDescriptor(
        for preview: DataStudioWorkbookPreviewResponse?
    ) -> DataStudioSpecimenFilterSortDescriptor {
        guard let preview else {
            return DataStudioSpecimenFilterSortDescriptor(
                key: .distanceFromMean,
                label: "Distance from Mean",
                unit: nil
            )
        }
        var candidateMetricIDs: [String] = []
        if let currentMetricID = currentFigureFamily?.metricID, !currentMetricID.isEmpty {
            candidateMetricIDs.append(currentMetricID)
        }
        candidateMetricIDs.append("Elongation")
        candidateMetricIDs.append(contentsOf: preview.metrics.map(\.label))

        var seenMetricIDs: Set<String> = []
        for metricID in candidateMetricIDs {
            let normalizedMetricID = normalizeFigureFamilyID(metricID)
            guard seenMetricIDs.insert(normalizedMetricID).inserted else {
                continue
            }
            guard preview.specimens.contains(where: { specimenMetricValue(for: $0, metricID: metricID) != nil }) else {
                continue
            }
            let summary = preview.metrics.first(where: {
                metricIdentifierMatches($0.label, metricID) || metricIdentifierMatches($0.id, metricID)
            })
            return DataStudioSpecimenFilterSortDescriptor(
                key: .metric(metricID: summary?.label ?? metricID),
                label: summary?.label ?? metricID,
                unit: summary?.unit
            )
        }

        return DataStudioSpecimenFilterSortDescriptor(
            key: .distanceFromMean,
            label: "Distance from Mean",
            unit: nil
        )
    }

    private func specimenFilterSortValue(
        for specimen: DataStudioSpecimenPreviewResponse,
        descriptor: DataStudioSpecimenFilterSortDescriptor
    ) -> Double? {
        switch descriptor.key {
        case let .metric(metricID):
            return specimenMetricValue(for: specimen, metricID: metricID)
        case .distanceFromMean:
            return specimen.distanceFromMeanScore
        }
    }

    private func sortedSpecimenRows(
        _ specimens: [DataStudioSpecimenPreviewResponse],
        descriptor: DataStudioSpecimenFilterSortDescriptor,
        groupByDisposition: Bool
    ) -> [DataStudioSpecimenPreviewResponse] {
        specimens.sorted { lhs, rhs in
            if groupByDisposition {
                let leftDisposition = specimenFilterDisposition(for: lhs)
                let rightDisposition = specimenFilterDisposition(for: rhs)
                let leftPriority = specimenFilterDispositionPriority(leftDisposition)
                let rightPriority = specimenFilterDispositionPriority(rightDisposition)
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }
            }
            let leftValue = specimenFilterSortValue(for: lhs, descriptor: descriptor)
            let rightValue = specimenFilterSortValue(for: rhs, descriptor: descriptor)
            switch (leftValue, rightValue) {
            case let (left?, right?) where left != right:
                return descriptor.sortsHighToLow ? (left > right) : (left < right)
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                break
            }
            let leftDistance = lhs.distanceFromMeanScore ?? .infinity
            let rightDistance = rhs.distanceFromMeanScore ?? .infinity
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }
            let filenameComparison = lhs.filename.localizedCaseInsensitiveCompare(rhs.filename)
            if filenameComparison != .orderedSame {
                return filenameComparison == .orderedAscending
            }
            return lhs.specimenId.localizedCaseInsensitiveCompare(rhs.specimenId) == .orderedAscending
        }
    }

    private func specimenMetricValue(
        for specimen: DataStudioSpecimenPreviewResponse,
        metricID: String
    ) -> Double? {
        specimen.metrics.first { metricIdentifierMatches($0.key, metricID) }?.value ?? nil
    }

    private func metricIdentifierMatches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private func specimenFilterDisposition(
        for specimen: DataStudioSpecimenPreviewResponse
    ) -> DataStudioSpecimenFilterRankDisposition {
        switch specimen.autoRuleRole {
        case "keep":
            return .keep
        case "exclude":
            return .out
        default:
            return .ineligible
        }
    }

    private func specimenFilterDispositionPriority(
        _ disposition: DataStudioSpecimenFilterRankDisposition
    ) -> Int {
        switch disposition {
        case .keep:
            return 0
        case .out:
            return 1
        case .ineligible:
            return 2
        }
    }

    private func displayLabel(forTemplateID templateID: String) -> String {
        switch templateID {
        case "curve":
            return "Curve"
        case "bar":
            return "Bar"
        case "box":
            return "Box"
        case "box_strip":
            return "Box + Strip"
        case "violin":
            return "Violin"
        case "point_error":
            return "Point + Error"
        case "grouped_bar_error":
            return "Bar + Error"
        default:
            return templateID.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func jsonValue(for state: DataStudioGroupStatePayload) -> JSONValue {
        .object(
            [
                "workbook_path": .string(state.workbookPath),
                "display_name": .string(state.displayName),
                "include_in_compare": .bool(state.includeInCompare),
                "sort_order": .number(Double(state.sortOrder)),
            ]
        )
    }

    private func jsonValue(for state: DataStudioSpecimenStatePayload) -> JSONValue {
        .object(
            [
                "workbook_path": .string(state.workbookPath),
                "specimen_id": .string(state.specimenId),
                "included": .bool(state.included),
                "selected_as_representative": .bool(state.selectedAsRepresentative),
            ]
        )
    }

    private func jsonValue(for preference: DataStudioFigurePreferencePayload) -> JSONValue {
        .object(
            [
                "family_id": .string(preference.familyID),
                "selected_template_id": preference.selectedTemplateID.map(JSONValue.string) ?? .null,
                "options_by_template": .object(
                    preference.optionsByTemplate.mapValues { options in
                        jsonValue(for: options)
                    }
                ),
            ]
        )
    }

    private func jsonValue(for options: RenderOptionsPayload) -> JSONValue {
        .object(
            [
                "size": options.size.map(JSONValue.string) ?? .null,
                "xscale": options.xscale.map(JSONValue.string) ?? .null,
                "yscale": options.yscale.map(JSONValue.string) ?? .null,
                "reverse_x": .bool(options.reverseX),
                "x_min": options.xMin.map(JSONValue.number) ?? .null,
                "x_max": options.xMax.map(JSONValue.number) ?? .null,
                "y_min": options.yMin.map(JSONValue.number) ?? .null,
                "y_max": options.yMax.map(JSONValue.number) ?? .null,
                "x_tick_density": options.xTickDensity.map(JSONValue.string) ?? .null,
                "y_tick_density": options.yTickDensity.map(JSONValue.string) ?? .null,
                "x_tick_edge_labels": options.xTickEdgeLabels.map(JSONValue.string) ?? .null,
                "y_tick_edge_labels": options.yTickEdgeLabels.map(JSONValue.string) ?? .null,
                "series_order": .array((options.seriesOrder ?? []).map(JSONValue.string)),
                "x_label_override": options.xLabelOverride.map(JSONValue.string) ?? .null,
                "y_label_override": options.yLabelOverride.map(JSONValue.string) ?? .null,
                "baseline": options.baseline.map(JSONValue.string) ?? .null,
                "show_colorbar": options.showColorbar.map(JSONValue.bool) ?? .null,
                "style_preset": .string(options.stylePreset),
                "palette_preset": .string(options.palettePreset),
                "use_sidecar": options.useSidecar.map(JSONValue.bool) ?? .null,
                "visual_theme_id": options.visualThemeID.map(JSONValue.string) ?? .null,
            ]
        )
    }
}

private extension DataStudioSession {
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
