import Foundation
import Observation

enum DataStudioTemplateMode: String, CaseIterable, Identifiable {
    case existingTemplate
    case createNewTemplate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .existingTemplate:
            return "Existing Template"
        case .createNewTemplate:
            return "New Template"
        }
    }

    var summary: String {
        switch self {
        case .existingTemplate:
            return "Select a saved template, then import source files directly into workbook build and compare."
        case .createNewTemplate:
            return "Import one sample file, confirm recommended regions, save the template, then reuse it."
        }
    }
}

enum DataStudioImportKind: String, Identifiable {
    case sourceFiles
    case templateSample
    case workbook

    var id: String { rawValue }
}

enum DataStudioActivity: Equatable {
    case idle
    case loadingTemplates
    case previewingSource
    case creatingTemplate
    case buildingWorkbook
    case importingWorkbooks
    case refreshingWorkbookPreview
    case previewingComparison
    case exportingComparison
}

struct DataStudioWorkbookItem: Identifiable, Equatable {
    let id: String
    var response: DataStudioWorkbookResponse
    var reviewTemplateID: String?
    var reviewInspection: InputInspectionResponse?
    var reviewDataset: PlotDatasetPreviewResponse?
    var reviewPreview: PreviewItemResponse?
    var reviewSubmissionReport: SubmissionReportResponse?
    var reviewErrorMessage: String?
    var isReviewLoading = false

    var workbookURL: URL {
        URL(fileURLWithPath: response.workbookPath)
    }

    var label: String {
        response.label
    }
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

    @ObservationIgnored private var client: (any SidecarClienting)?
    @ObservationIgnored private var meta: SidecarMetaResponse?
    @ObservationIgnored private let chooseDirectory: DirectoryChooser
    @ObservationIgnored private let chooseWorkbookSaveLocation: WorkbookSaveChooser
    @ObservationIgnored private let chooseComparisonFigureFormat: ComparisonFigureFormatChooser
    @ObservationIgnored private let materializeComparisonOutputs: ComparisonOutputMaterializer

    var templates: [DataStudioTemplateResponse] = []
    var templateMode: DataStudioTemplateMode = .existingTemplate
    var selectedTemplateID: String?
    var sourcePreview: DataStudioRawFilePreviewResponse?
    var sourceMatches: [DataStudioTemplateMatchResponse] = []
    var selectedCandidateIDs: [String] = []
    var templateDraftLabel = ""
    var templateDraftDescription = ""

    var isImportMenuPresented = false
    var isImportPresented = false
    var isGuidePresented = false
    var pendingImportKind: DataStudioImportKind = .sourceFiles

    var importedSourceURLs: [URL] = []
    var workbooks: [DataStudioWorkbookItem] = []
    var workbookOrder: [String] = []
    var primaryWorkbookID: String?
    var focusedWorkbookID: String?

    var comparisonSet: DataStudioComparisonSetResponse?
    var selectedRecipeID: String?
    var enabledRecipeIDs: [String] = []
    var comparisonPreview: PreviewItemResponse?
    var comparisonExportResponse: DataStudioComparisonExportResponse?
    var comparisonExportDestinationURL: URL?
    var comparisonFigureItems: [DataStudioExportFigureItem] = []
    var selectedComparisonFigureID: String?

    var errorMessage: String?
    var currentActivity: DataStudioActivity = .idle
    var isBusy = false
    var openInPlotHandler: ((URL, SheetValue) -> Void)?

    init(
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
        self.chooseDirectory = chooseDirectory
        self.chooseWorkbookSaveLocation = chooseWorkbookSaveLocation
        self.chooseComparisonFigureFormat = chooseComparisonFigureFormat
        self.materializeComparisonOutputs = materializeComparisonOutputs
    }

    func configure(client: any SidecarClienting) {
        self.client = client
    }

    func apply(meta: SidecarMetaResponse) {
        self.meta = meta
    }

    func refreshTemplates() async {
        guard let client else {
            return
        }
        currentActivity = .loadingTemplates
        defer { currentActivity = .idle }
        do {
            let response = try await client.fetchDataStudioTemplates()
            templates = response.templates
            if selectedTemplateID == nil {
                selectedTemplateID = templates.first?.id
            } else if !templates.contains(where: { $0.id == selectedTemplateID }) {
                selectedTemplateID = templates.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func showImportMenu() {
        isImportMenuPresented = true
    }

    func beginImport(kind: DataStudioImportKind) {
        pendingImportKind = kind
        isImportMenuPresented = false
        isImportPresented = true
    }

    func showGuide() {
        isGuidePresented = true
    }

    func dismissGuide() {
        isGuidePresented = false
    }

    var selectedTemplate: DataStudioTemplateResponse? {
        guard let selectedTemplateID else {
            return nil
        }
        return templates.first(where: { $0.id == selectedTemplateID })
    }

    var selectedSourceFilename: String? {
        if let focusedWorkbook {
            return focusedWorkbook.workbookURL.lastPathComponent
        }
        return importedSourceURLs.first?.lastPathComponent
    }

    func selectTemplate(id: String?) {
        selectedTemplateID = id
        if templateMode == .existingTemplate {
            clearSourcePreview()
        }
    }

    func selectTemplateMode(_ mode: DataStudioTemplateMode) {
        templateMode = mode
        clearSourcePreview()
    }

    func handleImportedSourceFiles(_ urls: [URL]) async {
        guard let selectedTemplateID else {
            errorMessage = "Select a template before importing source files into Data Studio."
            return
        }
        importedSourceURLs = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !importedSourceURLs.isEmpty else {
            return
        }
        let suggestedName = "\(inferGroupName(from: importedSourceURLs)).xlsx"
        guard let outputURL = chooseWorkbookSaveLocation(suggestedName) else {
            return
        }
        guard let client else {
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
                    filePaths: importedSourceURLs.map(\.path),
                    outputPath: outputURL.path,
                    templateID: selectedTemplateID,
                    groupName: inferGroupName(from: importedSourceURLs)
                )
            )
            upsertWorkbook(workbook)
            focusedWorkbookID = workbook.workbookID
            if primaryWorkbookID == nil {
                primaryWorkbookID = workbook.workbookID
            }
            await refreshWorkbookPreview(for: workbook.workbookID)
            await refreshComparisonPreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleImportedTemplateSample(_ urls: [URL]) async {
        guard let sampleURL = urls.first, let client else {
            return
        }
        importedSourceURLs = [sampleURL]
        currentActivity = .previewingSource
        errorMessage = nil
        defer { currentActivity = .idle }
        do {
            let response = try await client.previewDataStudioSource(.init(inputPath: sampleURL.path))
            sourcePreview = response.preview
            sourceMatches = response.matches
            selectedCandidateIDs = defaultCandidateSelection(from: response.preview)
            templateDraftLabel = templateDraftLabel.isEmpty
                ? sampleURL.deletingPathExtension().lastPathComponent
                : templateDraftLabel
            templateDraftDescription = templateDraftDescription.isEmpty
                ? "Template created from \(sampleURL.lastPathComponent)."
                : templateDraftDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTemplateFromDraft() async {
        guard let sourceURL = importedSourceURLs.first, let client else {
            errorMessage = "Import a sample file before creating a new template."
            return
        }
        let label = templateDraftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            errorMessage = "Provide a template name before saving it."
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
            templateMode = .existingTemplate
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleImportedWorkbooks(_ urls: [URL]) async {
        guard let client else {
            return
        }
        isBusy = true
        currentActivity = .importingWorkbooks
        errorMessage = nil
        defer {
            isBusy = false
            currentActivity = .idle
        }
        do {
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let workbook = try await client.importDataStudioWorkbook(.init(workbookPath: url.path))
                upsertWorkbook(workbook)
                focusedWorkbookID = workbook.workbookID
                if primaryWorkbookID == nil {
                    primaryWorkbookID = workbook.workbookID
                }
            }
            if let focusedWorkbookID {
                await refreshWorkbookPreview(for: focusedWorkbookID)
            }
            await refreshComparisonPreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveWorkbooks(from source: IndexSet, to destination: Int) {
        let moving = source.map { workbookOrder[$0] }
        workbookOrder = workbookOrder.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        workbookOrder.insert(contentsOf: moving, at: min(destination, workbookOrder.count))
        comparisonExportResponse = nil
        comparisonFigureItems = []
        selectedComparisonFigureID = nil
        Task { await refreshComparisonPreview() }
    }

    var primaryWorkbook: DataStudioWorkbookItem? {
        guard let primaryWorkbookID else {
            return orderedWorkbooks.first
        }
        return orderedWorkbooks.first(where: { $0.id == primaryWorkbookID }) ?? orderedWorkbooks.first
    }

    var focusedWorkbook: DataStudioWorkbookItem? {
        guard let focusedWorkbookID else {
            return primaryWorkbook
        }
        return orderedWorkbooks.first(where: { $0.id == focusedWorkbookID }) ?? primaryWorkbook
    }

    var orderedWorkbooks: [DataStudioWorkbookItem] {
        guard !workbookOrder.isEmpty else {
            return workbooks
        }
        let byID = Dictionary(uniqueKeysWithValues: workbooks.map { ($0.id, $0) })
        var ordered: [DataStudioWorkbookItem] = []
        var seen: Set<String> = []
        for id in workbookOrder {
            guard let item = byID[id], seen.insert(id).inserted else {
                continue
            }
            ordered.append(item)
        }
        for item in workbooks where !seen.contains(item.id) {
            ordered.append(item)
        }
        return ordered
    }

    var primaryWorkbookURL: URL? {
        primaryWorkbook?.workbookURL
    }

    var primaryPreferredSheet: SheetValue? {
        primaryWorkbook.map { .name($0.response.preferredSheet) }
    }

    var canExportComparison: Bool {
        orderedWorkbooks.count >= 2
    }

    var canRemoveFocusedWorkbook: Bool {
        focusedWorkbookID != nil
    }

    var selectedRecipe: DataStudioComparisonRecipeResponse? {
        guard let selectedRecipeID else {
            return comparisonSet?.recipes.first
        }
        return comparisonSet?.recipes.first(where: { $0.id == selectedRecipeID }) ?? comparisonSet?.recipes.first
    }

    var templateDraftSourceURL: URL? {
        importedSourceURLs.first
    }

    func setFocusedWorkbook(id: String?) {
        focusedWorkbookID = id
        guard let id, workbook(for: id)?.reviewPreview == nil else {
            return
        }
        Task { await refreshWorkbookPreview(for: id) }
    }

    func setPrimaryWorkbook(id: String) {
        primaryWorkbookID = id
        if focusedWorkbookID == nil {
            focusedWorkbookID = id
        }
    }

    func removeFocusedWorkbook() {
        guard let focusedWorkbookID else {
            return
        }
        removeWorkbook(id: focusedWorkbookID)
    }

    func removeWorkbook(id: String) {
        workbooks.removeAll { $0.id == id }
        workbookOrder.removeAll { $0 == id }
        if primaryWorkbookID == id {
            primaryWorkbookID = orderedWorkbooks.first?.id
        }
        if focusedWorkbookID == id {
            focusedWorkbookID = primaryWorkbookID ?? orderedWorkbooks.first?.id
        }
        comparisonExportResponse = nil
        comparisonFigureItems = []
        selectedComparisonFigureID = nil
        Task { await refreshComparisonPreview() }
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

    func renameSelectedTemplate(to newLabel: String) async {
        guard let client, let selectedTemplate else {
            return
        }
        guard !selectedTemplate.builtin else {
            errorMessage = "Built-in templates cannot be renamed."
            return
        }
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Template name cannot be empty."
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
            errorMessage = "Built-in templates cannot be deleted."
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

    func normalizeSessionPayload() async -> DataStudioSessionResponse? {
        guard let client else {
            return nil
        }
        let payload: [String: JSONValue] = [
            "version": .number(1),
            "selected_template_id": selectedTemplateID.map(JSONValue.string) ?? .null,
            "selected_workbook_id": focusedWorkbookID.map(JSONValue.string) ?? .null,
            "primary_workbook_id": primaryWorkbookID.map(JSONValue.string) ?? .null,
            "selected_recipe_id": selectedRecipeID.map(JSONValue.string) ?? .null,
            "workbook_paths": .array(orderedWorkbooks.map { .string($0.response.workbookPath) }),
            "comparison_recipe_ids": .array(enabledRecipeIDs.map(JSONValue.string)),
            "imported_paths": .array(importedSourceURLs.map { .string($0.path) }),
            "template_draft_path": templateDraftSourceURL.map { .string($0.path) } ?? .null,
        ]
        do {
            return try await client.normalizeDataStudioSession(.init(payload: payload))
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func restoreSession(from payload: DataStudioSessionResponse) async {
        selectedTemplateID = payload.selectedTemplateID
        enabledRecipeIDs = payload.comparisonRecipeIDs
        selectedRecipeID = payload.selectedRecipeID
        importedSourceURLs = payload.importedPaths.map(URL.init(fileURLWithPath:))
        primaryWorkbookID = payload.primaryWorkbookID
        focusedWorkbookID = payload.selectedWorkbookID
        workbooks = []
        workbookOrder = []
        comparisonSet = nil
        comparisonPreview = nil
        comparisonExportResponse = nil
        comparisonFigureItems = []
        selectedComparisonFigureID = nil
        errorMessage = nil

        if let templateDraftPath = payload.templateDraftPath {
            await handleImportedTemplateSample([URL(fileURLWithPath: templateDraftPath)])
        }
        if !payload.workbookPaths.isEmpty {
            await handleImportedWorkbooks(payload.workbookPaths.map(URL.init(fileURLWithPath:)))
        }
        if let restoredPrimaryWorkbookID = payload.primaryWorkbookID,
           workbooks.contains(where: { $0.id == restoredPrimaryWorkbookID })
        {
            primaryWorkbookID = restoredPrimaryWorkbookID
        }
        if let restoredSelectedWorkbookID = payload.selectedWorkbookID,
           workbooks.contains(where: { $0.id == restoredSelectedWorkbookID })
        {
            focusedWorkbookID = restoredSelectedWorkbookID
        }
        if let restoredSelectedRecipeID = payload.selectedRecipeID,
           comparisonSet?.recipes.contains(where: { $0.id == restoredSelectedRecipeID }) == true
        {
            selectedRecipeID = restoredSelectedRecipeID
            await refreshComparisonPreview(forceRecipeID: restoredSelectedRecipeID)
        }
    }

    func refreshFocusedWorkbookPreview() async {
        guard let focusedWorkbookID else {
            return
        }
        await refreshWorkbookPreview(for: focusedWorkbookID)
    }

    func refreshComparisonPreview(forceRecipeID: String? = nil) async {
        guard let client else {
            return
        }
        guard orderedWorkbooks.count >= 2 else {
            comparisonSet = nil
            comparisonPreview = nil
            comparisonExportResponse = nil
            comparisonFigureItems = []
            enabledRecipeIDs = []
            return
        }
        let recipeID = forceRecipeID ?? selectedRecipeID ?? "representative_curve"
        currentActivity = .previewingComparison
        defer { currentActivity = .idle }
        do {
            let response = try await client.previewDataStudioComparison(
                .init(
                    workbookPaths: orderedWorkbooks.map { $0.response.workbookPath },
                    recipeID: recipeID
                )
            )
            comparisonSet = response.comparisonSet
            selectedRecipeID = response.recipe.id
            comparisonPreview = response.preview
            if enabledRecipeIDs.isEmpty {
                enabledRecipeIDs = response.comparisonSet.recipes
                    .filter { $0.enabledByDefault && $0.supported }
                    .map(\.id)
            } else {
                enabledRecipeIDs = enabledRecipeIDs.filter { currentID in
                    response.comparisonSet.recipes.contains(where: { $0.id == currentID && $0.supported })
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectRecipe(id: String) {
        selectedRecipeID = id
        Task { await refreshComparisonPreview(forceRecipeID: id) }
    }

    func toggleRecipe(id: String) {
        if enabledRecipeIDs.contains(id) {
            enabledRecipeIDs.removeAll { $0 == id }
        } else {
            enabledRecipeIDs.append(id)
        }
    }

    func exportComparisonBundle() async {
        guard let client, orderedWorkbooks.count >= 2 else {
            errorMessage = "Data Studio comparison export requires at least two workbooks."
            return
        }
        guard let directoryURL = chooseDirectory(
            "Export Data Studio Comparison",
            "Choose a destination folder for the comparison workbook and figure bundle."
        ) else {
            return
        }
        guard let figureFormat = chooseComparisonFigureFormat(
            "Comparison Figure Format",
            "Choose whether the exported comparison figures should stay as editable PDF or convert to 300 dpi TIFF."
        ) else {
            return
        }
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
                    selectedRecipeIDs: enabledRecipeIDs
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

    func openPrimaryWorkbookInPlot() {
        guard let primaryWorkbook else {
            return
        }
        openInPlotHandler?(URL(fileURLWithPath: primaryWorkbook.response.workbookPath), .name(primaryWorkbook.response.preferredSheet))
    }

    func revealLatestExport() {
        if let comparisonExportDestinationURL {
            WorkspaceBridge.reveal([comparisonExportDestinationURL])
        } else if let primaryWorkbook {
            WorkspaceBridge.reveal([URL(fileURLWithPath: primaryWorkbook.response.workbookPath)])
        }
    }

    func openSelectedComparisonFigure() {
        guard let selectedComparisonFigure else {
            return
        }
        WorkspaceBridge.open(selectedComparisonFigure.url)
    }

    var selectedComparisonFigure: DataStudioExportFigureItem? {
        guard let selectedComparisonFigureID else {
            return comparisonFigureItems.first
        }
        return comparisonFigureItems.first(where: { $0.id == selectedComparisonFigureID }) ?? comparisonFigureItems.first
    }

    var canOpenInPlot: Bool {
        primaryWorkbook != nil
    }

    func selectComparisonFigure(id: String) {
        selectedComparisonFigureID = id
    }

    private func refreshWorkbookPreview(for workbookID: String) async {
        guard let client, let workbook = workbook(for: workbookID) else {
            return
        }
        mutateWorkbook(id: workbookID) {
            $0.isReviewLoading = true
            $0.reviewErrorMessage = nil
        }
        currentActivity = .refreshingWorkbookPreview
        defer { currentActivity = .idle }
        do {
            let inspectResponse = try await client.inspectFile(
                .init(
                    inputPath: workbook.response.workbookPath,
                    sheet: .name(workbook.response.preferredSheet)
                )
            )
            let templateID = inspectResponse.inspection.recommendations.first?.templateID
                ?? inspectResponse.inspection.primaryRecommendation.first?.templateID
                ?? inspectResponse.inspection.recommendation.template
            let previewResponse = try await client.renderPreview(
                .init(
                    inputPath: workbook.response.workbookPath,
                    sheet: .name(workbook.response.preferredSheet),
                    template: templateID,
                    options: previewOptions(from: inspectResponse.inspection, templateID: templateID)
                )
            )
            mutateWorkbook(id: workbookID) {
                $0.reviewTemplateID = templateID
                $0.reviewInspection = inspectResponse.inspection
                $0.reviewDataset = inspectResponse.dataset
                $0.reviewPreview = previewResponse.previews.first
                $0.reviewSubmissionReport = previewResponse.submissionReport
                $0.reviewErrorMessage = previewResponse.previews.isEmpty ? "The sidecar returned no review preview." : nil
                $0.isReviewLoading = false
            }
        } catch {
            mutateWorkbook(id: workbookID) {
                $0.reviewErrorMessage = error.localizedDescription
                $0.isReviewLoading = false
            }
        }
    }

    private func previewOptions(from inspection: InputInspectionResponse, templateID: String) -> RenderOptionsPayload {
        var options = RenderOptionsPayload()
        let template = meta?.templates.first(where: { $0.id == templateID })
        options.size = inspection.recommendation.size
        options.xscale = inspection.recommendation.xscale
        options.yscale = inspection.recommendation.yscale
        options.reverseX = inspection.recommendation.reverseX ?? false
        options.baseline = inspection.recommendation.baseline
        options.showColorbar = inspection.recommendation.showColorbar
        options.stylePreset = resolveCompatiblePreviewOption(
            recommendedValue: inspection.recommendation.stylePreset,
            allowedValues: template?.availableStyles,
            metaDefault: meta?.defaults.stylePreset,
            fallback: options.stylePreset
        )
        options.palettePreset = resolveCompatiblePreviewOption(
            recommendedValue: inspection.recommendation.palettePreset,
            allowedValues: template?.availablePalettes,
            metaDefault: meta?.defaults.palettePreset,
            fallback: options.palettePreset
        )
        options.useSidecar = inspection.recommendation.useSidecar
        options.visualThemeID = meta?.visualThemes.first?.id
        return options
    }

    private func resolveCompatiblePreviewOption(
        recommendedValue: String?,
        allowedValues: [String]?,
        metaDefault: String?,
        fallback: String
    ) -> String {
        let recommended = normalizedPreviewOptionValue(recommendedValue)
        let preferredDefault = normalizedPreviewOptionValue(metaDefault)
        guard let allowedValues, !allowedValues.isEmpty else {
            return recommended ?? preferredDefault ?? fallback
        }
        if let recommended, allowedValues.contains(recommended) {
            return recommended
        }
        if let preferredDefault, allowedValues.contains(preferredDefault) {
            return preferredDefault
        }
        return allowedValues.first ?? recommended ?? preferredDefault ?? fallback
    }

    private func normalizedPreviewOptionValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func upsertWorkbook(_ response: DataStudioWorkbookResponse) {
        let newItem = DataStudioWorkbookItem(
            id: response.workbookID,
            response: response,
            reviewTemplateID: nil,
            reviewInspection: nil,
            reviewDataset: nil,
            reviewPreview: nil,
            reviewSubmissionReport: nil,
            reviewErrorMessage: nil
        )
        if let index = workbooks.firstIndex(where: { $0.id == response.workbookID }) {
            workbooks[index] = newItem
        } else {
            workbooks.append(newItem)
        }
        if !workbookOrder.contains(response.workbookID) {
            workbookOrder.append(response.workbookID)
        }
    }

    private func mutateWorkbook(id: String, _ mutate: (inout DataStudioWorkbookItem) -> Void) {
        guard let index = workbooks.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&workbooks[index])
    }

    private func workbook(for id: String) -> DataStudioWorkbookItem? {
        workbooks.first(where: { $0.id == id })
    }

    private func clearSourcePreview() {
        sourcePreview = nil
        sourceMatches = []
        selectedCandidateIDs = []
        templateDraftLabel = ""
        templateDraftDescription = ""
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
}
