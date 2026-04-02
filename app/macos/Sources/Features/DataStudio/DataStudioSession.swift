import Foundation
import Observation

enum DataStudioImportKind: String, Identifiable {
    case rawFiles
    case existingWorkbook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rawFiles:
            return "Raw Files"
        case .existingWorkbook:
            return "Existing Workbook"
        }
    }

    var summary: String {
        switch self {
        case .rawFiles:
            return "Import source csv / txt / xls / xlsx files and let Data Studio match or create a parse template."
        case .existingWorkbook:
            return "Import a prepared workbook directly into the current group list and compare context."
        }
    }
}

enum DataStudioImportDisposition: String, Identifiable {
    case addToCurrentSession
    case startNewSession

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addToCurrentSession:
            return "Add to Current Session"
        case .startNewSession:
            return "Start New Session"
        }
    }
}

enum DataStudioImportFlowStep: Equatable {
    case scope
    case kind
}

enum DataStudioImportResolverMode: String, CaseIterable, Identifiable {
    case existingTemplate
    case createTemplate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .existingTemplate:
            return "Use Existing Parse Template"
        case .createTemplate:
            return "Create Parse Template"
        }
    }
}

enum DataStudioActivity: Equatable {
    case idle
    case loadingTemplates
    case previewingSource
    case creatingTemplate
    case buildingWorkbook
    case importingWorkbooks
    case previewingComparison
    case exportingComparison
}

struct DataStudioWorkbookItem: Identifiable, Equatable {
    let id: String
    var response: DataStudioWorkbookResponse

    var workbookURL: URL {
        URL(fileURLWithPath: response.workbookPath)
    }
}

struct DataStudioGroupRowItem: Identifiable, Equatable {
    let workbook: DataStudioWorkbookItem
    let state: DataStudioGroupStatePayload

    var id: String { workbook.response.workbookPath }
}

struct DataStudioFigureFamilyItem: Identifiable, Equatable {
    let id: String
    let title: String
    let metricID: String?
    let recipes: [DataStudioComparisonRecipeResponse]
}

struct DataStudioFigureTemplateItem: Identifiable, Equatable {
    let id: String
    let label: String
    let recipeID: String
}

struct DataStudioExportFigureItem: Identifiable, Equatable {
    let id: String
    let response: DataStudioFigureOutputResponse
    let url: URL
}

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
    @ObservationIgnored private var meta: SidecarMetaResponse?
    @ObservationIgnored private var contract: PlotContractResponse?
    @ObservationIgnored private let chooseDirectory: DirectoryChooser
    @ObservationIgnored private let chooseWorkbookSaveLocation: WorkbookSaveChooser
    @ObservationIgnored private let chooseComparisonFigureFormat: ComparisonFigureFormatChooser
    @ObservationIgnored private let materializeComparisonOutputs: ComparisonOutputMaterializer
    @ObservationIgnored private var comparisonRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var comparisonRefreshRevision = 0

    let plotSession: PlotSession

    var templates: [DataStudioTemplateResponse] = []
    var selectedTemplateID: String?
    var sourcePreview: DataStudioRawFilePreviewResponse?
    var sourceMatches: [DataStudioTemplateMatchResponse] = []
    var selectedCandidateIDs: [String] = []
    var templateDraftLabel = ""
    var templateDraftDescription = ""

    var isImportFlowPresented = false
    var importFlowStep: DataStudioImportFlowStep = .kind
    var pendingImportDisposition: DataStudioImportDisposition = .addToCurrentSession
    var pendingImportKind: DataStudioImportKind = .rawFiles
    var isImportPresented = false
    var isImportResolverPresented = false
    var importResolverMode: DataStudioImportResolverMode = .existingTemplate
    var isGuidePresented = false

    var importedSourceURLs: [URL] = []
    var workbooks: [DataStudioWorkbookItem] = []
    var groupStates: [DataStudioGroupStatePayload] = []
    var focusedWorkbookPath: String?

    var comparisonSet: DataStudioComparisonSetResponse?
    var selectedRecipeID: String?
    var selectedFigureFamilyID: String?
    var selectedFigureTemplateID: String?
    var figurePreferences: [DataStudioFigurePreferencePayload] = []
    var comparisonExportResponse: DataStudioComparisonExportResponse?
    var comparisonExportDestinationURL: URL?
    var comparisonFigureItems: [DataStudioExportFigureItem] = []
    var selectedComparisonFigureID: String?

    var errorMessage: String?
    var currentActivity: DataStudioActivity = .idle
    var isBusy = false
    var openInPlotHandler: OpenInPlotHandler?

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

    func apply(meta: SidecarMetaResponse, contract: PlotContractResponse) {
        self.meta = meta
        self.contract = contract
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
        if hasSessionContent {
            importFlowStep = .scope
            pendingImportDisposition = .addToCurrentSession
        } else {
            importFlowStep = .kind
            pendingImportDisposition = .addToCurrentSession
        }
        isImportFlowPresented = true
    }

    func chooseImportDisposition(_ disposition: DataStudioImportDisposition) {
        pendingImportDisposition = disposition
        importFlowStep = .kind
    }

    func chooseImportKind(_ kind: DataStudioImportKind) {
        pendingImportKind = kind
        isImportFlowPresented = false
        isImportPresented = true
    }

    func dismissImportFlow() {
        isImportFlowPresented = false
    }

    func showGuide() {
        isGuidePresented = true
    }

    func dismissGuide() {
        isGuidePresented = false
    }

    var hasSessionContent: Bool {
        !workbooks.isEmpty
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

    var includedGroups: [DataStudioGroupRowItem] {
        orderedGroups.filter(\.state.includeInCompare)
    }

    var selectedComparisonFigure: DataStudioExportFigureItem? {
        guard let selectedComparisonFigureID else {
            return comparisonFigureItems.first
        }
        return comparisonFigureItems.first(where: { $0.id == selectedComparisonFigureID }) ?? comparisonFigureItems.first
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
            return "\(includedGroups.count) group(s) · \(currentRecipeLabel) · \(URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath).lastPathComponent)"
        }
        if !workbooks.isEmpty {
            return "\(includedGroups.count) group(s) in compare"
        }
        return "No workbook groups loaded"
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
            selectedCandidateIDs = defaultCandidateSelection(from: response.preview)
            templateDraftLabel = inferGroupName(from: importedSourceURLs)
            templateDraftDescription = "Template created from \(sampleURL.lastPathComponent)."

            let directMatches = response.matches.filter(\.autoSelected)
            if directMatches.count == 1, let match = directMatches.first {
                selectedTemplateID = match.templateID
                await buildWorkbookFromPendingRawFiles(templateID: match.templateID)
            } else {
                selectedTemplateID = response.matches.first?.templateID ?? templates.first?.id
                importResolverMode = .existingTemplate
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
        await buildWorkbookFromPendingRawFiles(templateID: selectedTemplateID)
    }

    func createTemplateAndImport() async {
        guard let sourceURL = importedSourceURLs.first, let client else {
            errorMessage = "Import a sample source file before saving a new parse template."
            return
        }
        let label = templateDraftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            errorMessage = "Provide a parse template name before saving it."
            return
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
            templates.append(template)
            templates.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            selectedTemplateID = template.id
            isImportResolverPresented = false
            await buildWorkbookFromPendingRawFiles(templateID: template.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissImportResolver() {
        isImportResolverPresented = false
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
                let workbook = try await client.importDataStudioWorkbook(.init(workbookPath: url.path))
                upsertWorkbook(workbook, shouldFocus: true)
            }
            if refreshContext {
                await rebuildComparisonContext()
            }
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
        focusedWorkbookPath = path ?? orderedWorkbooks.first?.response.workbookPath
    }

    func updateDisplayName(for workbookPath: String, to displayName: String) {
        setGroupState(
            workbookPath: workbookPath,
            displayName: displayName,
            includeInCompare: groupState(for: workbookPath)?.includeInCompare ?? true
        )
        scheduleComparisonContextRebuild()
    }

    func updateCompareInclusion(for workbookPath: String, includeInCompare: Bool) {
        setGroupState(
            workbookPath: workbookPath,
            displayName: groupState(for: workbookPath)?.displayName ?? "",
            includeInCompare: includeInCompare
        )
        scheduleComparisonContextRebuild()
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
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
    }

    func removeWorkbook(path: String) {
        workbooks.removeAll { $0.response.workbookPath == path }
        groupStates.removeAll { $0.workbookPath == path }
        selectedComparisonFigureID = nil
        reindexGroupStates()
        if focusedWorkbookPath == path {
            focusedWorkbookPath = orderedWorkbooks.first?.response.workbookPath
        }
        Task { await rebuildComparisonContext() }
    }

    func selectFigureFamily(id: String) {
        cacheCurrentFigureOptions()
        selectedFigureFamilyID = id
        syncFigureSelection()
        stageCurrentFigurePreview()
        Task { await refreshDisplayedFigure() }
    }

    func selectFigureTemplate(id: String) {
        guard let family = currentFigureFamily else {
            return
        }
        cacheCurrentFigureOptions()
        setFigurePreference(familyID: family.id, selectedTemplateID: id)
        selectedFigureTemplateID = id
        syncFigureSelection()
        stageCurrentFigurePreview()
        Task { await refreshDisplayedFigure() }
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

    func openSelectedComparisonFigure() {
        guard let selectedComparisonFigure else {
            return
        }
        WorkspaceBridge.open(selectedComparisonFigure.url)
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
            "Choose a destination folder for the comparison workbook and figure outputs."
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
                    selectedRecipeIDs: recipeIDs,
                    figureOptionsByRecipeID: exportFigureOptionsByRecipeID()
                )
            )
            comparisonExportResponse = response
            comparisonSet = response.comparisonSet
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

        focusedWorkbookPath = resolveRestoredWorkbookPath(
            selectedWorkbookID: payload.selectedWorkbookID,
            primaryWorkbookID: payload.primaryWorkbookID
        )

        await rebuildComparisonContext()
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
        let groupName = inferGroupName(from: sourceURLs)
        let suggestedName = "\(groupName).xlsx"
        guard let outputURL = chooseWorkbookSaveLocation(suggestedName) else {
            return
        }
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
            await rebuildComparisonContext()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rebuildComparisonContext() async {
        guard let client else {
            return
        }
        cacheCurrentFigureOptions()
        comparisonRefreshTask?.cancel()
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
        defer { currentActivity = .idle }
        do {
            let response = try await client.previewDataStudioComparison(
                .init(
                    workbookPaths: workbookPaths,
                    recipeID: "representative_curve",
                    groupStates: requestGroupStates
                )
            )
            comparisonSet = response.comparisonSet
            syncFigureSelection(preferredRecipeID: selectedRecipeID)
            stageCurrentFigurePreview()
            await refreshDisplayedFigure()
        } catch {
            comparisonSet = nil
            plotSession.clearPreviewContext(preserveRenderOptions: true)
            errorMessage = error.localizedDescription
        }
    }

    private func refreshDisplayedFigure() async {
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
        await plotSession.finishLoadingStagedExternalFigure(
            preferredTemplateID: currentRecipe.templateID,
            preferredOptions: preferredOptions,
            expectedInputURL: URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath),
            expectedSheet: .name(currentRecipe.sheetName)
        )
        if let plotError = plotSession.errorMessage, !plotError.isEmpty {
            errorMessage = plotError
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

    private func scheduleComparisonContextRebuild() {
        comparisonRefreshRevision += 1
        let revision = comparisonRefreshRevision
        comparisonRefreshTask?.cancel()
        comparisonRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.comparisonRefreshDelayNanoseconds ?? 0)
            } catch {
                return
            }
            guard let self, revision == self.comparisonRefreshRevision, !Task.isCancelled else {
                return
            }
            await self.rebuildComparisonContext()
        }
    }

    private func clearComparisonContext() {
        comparisonSet = nil
        comparisonExportResponse = nil
        comparisonFigureItems = []
        selectedComparisonFigureID = nil
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
                    displayName: response.label,
                    includeInCompare: true,
                    sortOrder: groupStates.count
                )
            )
        }
        reindexGroupStates()
        if shouldFocus || focusedWorkbookPath == nil {
            focusedWorkbookPath = response.workbookPath
        }
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
                    displayName: workbook.response.label,
                    includeInCompare: true,
                    sortOrder: merged.count
                )
            )
        }
        groupStates = merged
        reindexGroupStates()
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
        let responseLabel = workbook.response.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !responseLabel.isEmpty {
            return responseLabel
        }
        return workbook.workbookURL.deletingPathExtension().lastPathComponent
    }

    private func reindexGroupStates() {
        let orderedPaths = orderedWorkbooks.map { $0.response.workbookPath }
        let stateByPath = Dictionary(uniqueKeysWithValues: groupStates.map { ($0.workbookPath, $0) })
        groupStates = orderedPaths.enumerated().map { index, path in
            let state = stateByPath[path]
            return DataStudioGroupStatePayload(
                workbookPath: path,
                displayName: state?.displayName ?? workbooks.first(where: { $0.response.workbookPath == path })?.response.label ?? "",
                includeInCompare: state?.includeInCompare ?? true,
                sortOrder: index
            )
        }
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
            "distribution_compare",
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

    private func resetContentState() {
        comparisonRefreshTask?.cancel()
        workbooks = []
        groupStates = []
        focusedWorkbookPath = nil
        comparisonSet = nil
        comparisonExportResponse = nil
        comparisonExportDestinationURL = nil
        comparisonFigureItems = []
        selectedComparisonFigureID = nil
        selectedRecipeID = nil
        importedSourceURLs = []
        sourcePreview = nil
        sourceMatches = []
        selectedCandidateIDs = []
        templateDraftLabel = ""
        templateDraftDescription = ""
        isImportResolverPresented = false
        plotSession.clearPreviewContext(preserveRenderOptions: true)
        errorMessage = nil
        currentActivity = .idle
    }

    private func defaultCandidateSelection(from preview: DataStudioRawFilePreviewResponse) -> [String] {
        var chosen: [String] = []
        for kind in ["curve_x", "curve_y", "metric"] {
            if let candidate = preview.fieldCandidates
                .filter({ $0.kind == kind })
                .sorted(by: { lhs, rhs in
                    if lhs.confidence == rhs.confidence {
                        return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                    }
                    return lhs.confidence > rhs.confidence
                })
                .first
            {
                chosen.append(candidate.id)
            }
        }
        return Array(Set(chosen))
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
        case "distribution_compare":
            return "Distribution"
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
