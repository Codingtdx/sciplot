import Foundation
import Observation

enum DataCleanupStage: String, CaseIterable, Identifiable {
    case intake
    case review
    case compare
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intake:
            return "Import"
        case .review:
            return "Review & Clean"
        case .compare:
            return "Compare"
        case .export:
            return "Export / Open in Plot"
        }
    }
}

enum DataCleanupImportKind: String, Identifiable {
    case rawCSV
    case preparedWorkbook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rawCSV:
            return "Import Raw CSV"
        case .preparedWorkbook:
            return "Open Prepared Workbook"
        }
    }
}

struct PreparedWorkbookItem: Identifiable, Equatable {
    let id: String
    var url: URL
    var label: String
    var preferredSheet: SheetValue
    var sampleCount: Int
    var representativeFilename: String
    var metrics: [TensileMetricSummaryResponse]
    var sheetNames: [String]
    var warnings: [String]
    var reviewTemplateID: String?
    var reviewInspection: InputInspectionResponse?
    var reviewDataset: PlotDatasetPreviewResponse?
    var reviewPreview: PreviewItemResponse?
    var reviewSubmissionReport: SubmissionReportResponse?
    var reviewErrorMessage: String?
    var isReviewLoading = false
}

struct CleanupExportFigureItem: Identifiable, Equatable {
    let id: String
    let sourcePath: String
    let label: String
    let category: String
    let kind: String
    let metric: String?
    let url: URL
}

@MainActor
@Observable
final class DataCleanupSession {
    typealias DirectoryChooser = @MainActor (_ title: String, _ message: String) -> URL?
    typealias WorkbookSaveChooser = @MainActor (_ suggestedName: String) -> URL?
    typealias ComparisonFigureFormatChooser = @MainActor (_ title: String, _ message: String) -> ExportGraphicFormat?
    typealias ComparisonOutputMaterializer = @MainActor (_ sourceURLs: [URL], _ format: ExportGraphicFormat) throws -> [URL]

    @ObservationIgnored private var client: (any SidecarClienting)?
    @ObservationIgnored private let chooseDirectory: DirectoryChooser
    @ObservationIgnored private let chooseWorkbookSaveLocation: WorkbookSaveChooser
    @ObservationIgnored private let chooseComparisonFigureFormat: ComparisonFigureFormatChooser
    @ObservationIgnored private let materializeComparisonOutputs: ComparisonOutputMaterializer

    var isImportMenuPresented = false
    var isGuidePresented = false
    var isRawImporterPresented = false
    var isWorkbookImporterPresented = false
    var rawInputURLs: [URL] = []
    var preparedWorkbooks: [PreparedWorkbookItem] = []
    var latestPreprocessResponse: TensileReplicateResponseModel?
    var comparisonExportResponse: TensileComparisonExportResponse?
    var comparisonExportDestinationURL: URL?
    var comparisonExportFigureURLs: [URL] = []
    var comparisonFigureItems: [CleanupExportFigureItem] = []
    var selectedComparisonFigureID: String?
    var comparisonWorkbookOrder: [String] = []
    var primaryWorkbookID: String?
    var focusedWorkbookID: String?
    var groupName = ""
    var errorMessage: String?
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

    var stage: DataCleanupStage {
        if comparisonExportResponse != nil {
            return .export
        }
        if preparedWorkbooks.count >= 2 {
            return .compare
        }
        if !preparedWorkbooks.isEmpty {
            return .review
        }
        return .intake
    }

    var primaryWorkbook: PreparedWorkbookItem? {
        guard let primaryWorkbookID else {
            return preparedWorkbooks.first
        }
        return preparedWorkbooks.first(where: { $0.id == primaryWorkbookID }) ?? preparedWorkbooks.first
    }

    var focusedWorkbook: PreparedWorkbookItem? {
        guard let focusedWorkbookID else {
            return primaryWorkbook
        }
        return preparedWorkbooks.first(where: { $0.id == focusedWorkbookID }) ?? primaryWorkbook
    }

    var primaryWorkbookURL: URL? {
        primaryWorkbook?.url
    }

    var primaryPreferredSheet: SheetValue? {
        primaryWorkbook?.preferredSheet
    }

    var selectedComparisonFigureItem: CleanupExportFigureItem? {
        guard let selectedComparisonFigureID else {
            return comparisonFigureItems.first
        }
        return comparisonFigureItems.first(where: { $0.id == selectedComparisonFigureID }) ?? comparisonFigureItems.first
    }

    var orderedPreparedWorkbooks: [PreparedWorkbookItem] {
        guard !comparisonWorkbookOrder.isEmpty else {
            return preparedWorkbooks
        }

        let byID = Dictionary(uniqueKeysWithValues: preparedWorkbooks.map { ($0.id, $0) })
        var ordered: [PreparedWorkbookItem] = []
        var seen: Set<String> = []
        for workbookID in comparisonWorkbookOrder {
            guard let workbook = byID[workbookID], seen.insert(workbookID).inserted else {
                continue
            }
            ordered.append(workbook)
        }
        for workbook in preparedWorkbooks where !seen.contains(workbook.id) {
            ordered.append(workbook)
        }
        return ordered
    }

    func showGuide() {
        isGuidePresented = true
    }

    func dismissGuide() {
        isGuidePresented = false
    }

    func showImportMenu() {
        isImportMenuPresented = true
    }

    func beginImport(kind: DataCleanupImportKind) {
        isImportMenuPresented = false
        switch kind {
        case .rawCSV:
            isRawImporterPresented = true
        case .preparedWorkbook:
            isWorkbookImporterPresented = true
        }
    }

    func setFocusedWorkbook(id: String?) {
        focusedWorkbookID = id
        guard let id else {
            return
        }
        if workbook(for: id)?.reviewPreview == nil, workbook(for: id)?.isReviewLoading == false {
            Task { await self.refreshReview(for: id) }
        }
    }

    func setPrimaryWorkbook(id: String) {
        primaryWorkbookID = id
        if focusedWorkbookID == nil {
            focusedWorkbookID = id
        }
    }

    func removeWorkbook(id: String) {
        preparedWorkbooks.removeAll { $0.id == id }
        comparisonWorkbookOrder.removeAll { $0 == id }
        clearExportSelection()
        if primaryWorkbookID == id {
            primaryWorkbookID = orderedPreparedWorkbooks.first?.id
        }
        if focusedWorkbookID == id {
            focusedWorkbookID = primaryWorkbookID ?? orderedPreparedWorkbooks.first?.id
        }
    }

    func selectComparisonFigure(id: String) {
        selectedComparisonFigureID = id
    }

    func handleImportedRawFiles(_ urls: [URL]) async {
        rawInputURLs = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        clearExportSelection()
        errorMessage = nil

        guard !rawInputURLs.isEmpty else {
            return
        }

        if groupName.isEmpty {
            groupName = rawInputURLs.first?.deletingPathExtension().lastPathComponent ?? "prepared-workbook"
        }

        guard let outputURL = chooseWorkbookSaveLocation("\(groupName).xlsx") else {
            return
        }

        await preprocessRawFiles(to: outputURL)
    }

    func preprocessRawFiles(to outputURL: URL) async {
        guard let client, !rawInputURLs.isEmpty else {
            return
        }

        isBusy = true
        clearExportSelection()
        errorMessage = nil
        defer { isBusy = false }

        do {
            let response = try await client.preprocessTensileReplicates(
                .init(
                    filePaths: rawInputURLs.map(\.path),
                    outputPath: outputURL.path,
                    groupName: groupName.isEmpty ? nil : groupName
                )
            )
            latestPreprocessResponse = response

            let item = PreparedWorkbookItem(
                id: response.outputPath,
                url: URL(fileURLWithPath: response.outputPath),
                label: response.groupName,
                preferredSheet: .name(response.preferredSheet),
                sampleCount: response.sampleCount,
                representativeFilename: response.representativeFilename,
                metrics: response.metrics,
                sheetNames: response.sheetNames,
                warnings: response.warnings,
                reviewTemplateID: nil,
                reviewInspection: nil,
                reviewDataset: nil,
                reviewPreview: nil,
                reviewSubmissionReport: nil,
                reviewErrorMessage: nil
            )
            upsertPreparedWorkbook(item)
            focusImportedWorkbook(id: item.id)
            await refreshReview(for: item.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleImportedWorkbooks(_ urls: [URL]) async {
        guard let client else {
            return
        }

        isBusy = true
        clearExportSelection()
        errorMessage = nil
        defer { isBusy = false }

        do {
            var lastImportedID: String?
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let summary = try await client.inspectTensileWorkbook(.init(workbookPath: url.path))
                let item = PreparedWorkbookItem(
                    id: summary.workbookPath,
                    url: URL(fileURLWithPath: summary.workbookPath),
                    label: summary.label,
                    preferredSheet: .name(summary.preferredSheet),
                    sampleCount: summary.sampleCount,
                    representativeFilename: summary.representativeFilename,
                    metrics: summary.metrics,
                    sheetNames: summary.sheetNames,
                    warnings: summary.warnings,
                    reviewTemplateID: nil,
                    reviewInspection: nil,
                    reviewDataset: nil,
                    reviewPreview: nil,
                    reviewSubmissionReport: nil,
                    reviewErrorMessage: nil
                )
                upsertPreparedWorkbook(item)
                lastImportedID = item.id
            }
            if let lastImportedID {
                focusImportedWorkbook(id: lastImportedID)
                await refreshReview(for: lastImportedID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshFocusedReview() async {
        guard let workbookID = focusedWorkbook?.id else {
            return
        }
        await refreshReview(for: workbookID)
    }

    func exportComparisonBundle() async {
        guard let client else {
            return
        }

        guard preparedWorkbooks.count >= 2 else {
            errorMessage = "Comparison export requires at least two prepared workbooks."
            return
        }

        guard let directoryURL = chooseDirectory(
            "Export Comparison Bundle",
            "Choose a destination folder for the comparison workbook and figure bundle."
        ) else {
            return
        }

        guard let figureFormat = chooseComparisonFigureFormat(
            "Comparison Figure Format",
            "Choose whether the exported comparison figures should stay as editable PDF or be converted to 300 dpi TIFF."
        ) else {
            return
        }

        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let response = try await client.exportTensileComparison(
                .init(
                    workbookPaths: orderedPreparedWorkbooks.map { $0.url.path },
                    outputDir: directoryURL.path
                )
            )
            comparisonExportResponse = response

            let sourceFigureURLs = response.figureOutputs.map { URL(fileURLWithPath: $0.path) }
            let materializedFigureURLs = try materializeComparisonOutputs(sourceFigureURLs, figureFormat)
            comparisonExportFigureURLs = materializedFigureURLs
            comparisonFigureItems = zip(response.figureOutputs, materializedFigureURLs).map { figure, url in
                CleanupExportFigureItem(
                    id: figure.path,
                    sourcePath: figure.path,
                    label: figure.label,
                    category: figure.category,
                    kind: figure.kind,
                    metric: figure.metric,
                    url: url
                )
            }
            selectedComparisonFigureID = comparisonFigureItems.first?.id
            comparisonExportDestinationURL = directoryURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openPrimaryWorkbookInPlot() {
        guard let primary = primaryWorkbookURL,
              let preferredSheet = primaryPreferredSheet
        else {
            return
        }
        openInPlotHandler?(primary, preferredSheet)
    }

    func moveComparisonWorkbooks(from source: IndexSet, to destination: Int) {
        comparisonWorkbookOrder = orderedPreparedWorkbooks.map(\.id)
        comparisonWorkbookOrder.move(fromOffsets: source, toOffset: destination)
        clearExportSelection()
    }

    func revealLatestExport() {
        if let comparisonExportDestinationURL {
            WorkspaceBridge.reveal([comparisonExportDestinationURL])
        } else if let primaryWorkbookURL {
            WorkspaceBridge.reveal([primaryWorkbookURL])
        }
    }

    private func refreshReview(for workbookID: String) async {
        guard let client,
              let workbook = workbook(for: workbookID)
        else {
            return
        }

        mutateWorkbook(id: workbookID) {
            $0.isReviewLoading = true
            $0.reviewErrorMessage = nil
        }

        do {
            let inspectResponse = try await client.inspectFile(
                .init(inputPath: workbook.url.path, sheet: workbook.preferredSheet)
            )
            let templateID = inspectResponse.inspection.recommendations.first?.templateID
                ?? inspectResponse.inspection.primaryRecommendation.first?.templateID
                ?? inspectResponse.inspection.recommendation.template

            let previewResponse = try await client.renderPreview(
                .init(
                    inputPath: workbook.url.path,
                    sheet: workbook.preferredSheet,
                    template: templateID,
                    options: previewOptions(from: inspectResponse.inspection)
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

    private func previewOptions(from inspection: InputInspectionResponse) -> RenderOptionsPayload {
        var options = RenderOptionsPayload()
        options.size = inspection.recommendation.size
        options.xscale = inspection.recommendation.xscale
        options.yscale = inspection.recommendation.yscale
        options.reverseX = inspection.recommendation.reverseX ?? false
        options.baseline = inspection.recommendation.baseline
        options.showColorbar = inspection.recommendation.showColorbar
        if let stylePreset = inspection.recommendation.stylePreset {
            options.stylePreset = stylePreset
        }
        if let palettePreset = inspection.recommendation.palettePreset {
            options.palettePreset = palettePreset
        }
        options.useSidecar = inspection.recommendation.useSidecar
        return options
    }

    private func focusImportedWorkbook(id: String) {
        focusedWorkbookID = id
        if primaryWorkbookID == nil {
            primaryWorkbookID = id
        }
    }

    private func clearExportSelection() {
        comparisonExportResponse = nil
        comparisonExportDestinationURL = nil
        comparisonExportFigureURLs = []
        comparisonFigureItems = []
        selectedComparisonFigureID = nil
    }

    private func workbook(for id: String) -> PreparedWorkbookItem? {
        preparedWorkbooks.first(where: { $0.id == id })
    }

    private func mutateWorkbook(id: String, _ mutate: (inout PreparedWorkbookItem) -> Void) {
        guard let existingIndex = preparedWorkbooks.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&preparedWorkbooks[existingIndex])
    }

    private func upsertPreparedWorkbook(_ item: PreparedWorkbookItem) {
        if let existingIndex = preparedWorkbooks.firstIndex(where: { $0.id == item.id }) {
            preparedWorkbooks[existingIndex] = item
        } else {
            preparedWorkbooks.append(item)
        }
        if !comparisonWorkbookOrder.contains(item.id) {
            comparisonWorkbookOrder.append(item.id)
        }
    }
}
