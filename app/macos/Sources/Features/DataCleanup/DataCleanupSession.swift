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

struct PreparedWorkbookItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let label: String
    let preferredSheet: SheetValue
    let sampleCount: Int
    let representativeFilename: String
    let metrics: [TensileMetricSummaryResponse]
    let sheetNames: [String]
    let warnings: [String]
}

@MainActor
@Observable
final class DataCleanupSession {
    typealias DirectoryChooser = @MainActor (_ title: String, _ message: String) -> URL?
    typealias WorkbookSaveChooser = @MainActor (_ suggestedName: String) -> URL?

    @ObservationIgnored private var client: (any SidecarClienting)?
    @ObservationIgnored private let chooseDirectory: DirectoryChooser
    @ObservationIgnored private let chooseWorkbookSaveLocation: WorkbookSaveChooser

    var stage: DataCleanupStage = .intake
    var isRawImporterPresented = false
    var isWorkbookImporterPresented = false
    var rawInputURLs: [URL] = []
    var preparedWorkbooks: [PreparedWorkbookItem] = []
    var latestPreprocessResponse: TensileReplicateResponseModel?
    var comparisonExportResponse: TensileComparisonExportResponse?
    var comparisonExportDestinationURL: URL?
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
        }
    ) {
        self.chooseDirectory = chooseDirectory
        self.chooseWorkbookSaveLocation = chooseWorkbookSaveLocation
    }

    func configure(client: any SidecarClienting) {
        self.client = client
    }

    var primaryWorkbookURL: URL? {
        preparedWorkbooks.first?.url
    }

    var primaryPreferredSheet: SheetValue? {
        preparedWorkbooks.first?.preferredSheet
    }

    func handleImportedRawFiles(_ urls: [URL]) async {
        rawInputURLs = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        comparisonExportDestinationURL = nil
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
        comparisonExportDestinationURL = nil
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
                warnings: response.warnings
            )
            upsertPreparedWorkbook(item)
            stage = .review
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleImportedWorkbooks(_ urls: [URL]) async {
        guard let client else {
            return
        }

        isBusy = true
        comparisonExportDestinationURL = nil
        errorMessage = nil
        defer { isBusy = false }

        do {
            for url in urls {
                let summary = try await client.inspectTensileWorkbook(.init(workbookPath: url.path))
                let item = PreparedWorkbookItem(
                    id: summary.workbookPath,
                    url: URL(fileURLWithPath: summary.workbookPath),
                    label: summary.label,
                    preferredSheet: .name(summary.sheetNames.first ?? "Representative_Curve"),
                    sampleCount: summary.sampleCount,
                    representativeFilename: summary.representativeFilename,
                    metrics: summary.metrics,
                    sheetNames: summary.sheetNames,
                    warnings: []
                )
                upsertPreparedWorkbook(item)
            }
            stage = .review
        } catch {
            errorMessage = error.localizedDescription
        }
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

        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            comparisonExportResponse = try await client.exportTensileComparison(
                .init(
                    workbookPaths: preparedWorkbooks.map { $0.url.path },
                    outputDir: directoryURL.path
                )
            )
            comparisonExportDestinationURL = directoryURL
            stage = .export
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openPrimaryWorkbookInPlot() {
        guard let primary = preparedWorkbooks.first else {
            return
        }
        openInPlotHandler?(primary.url, primary.preferredSheet)
    }

    func revealLatestExport() {
        if let comparisonExportDestinationURL {
            WorkspaceBridge.reveal([comparisonExportDestinationURL])
        } else if let primaryWorkbookURL {
            WorkspaceBridge.reveal([primaryWorkbookURL])
        }
    }

    private func upsertPreparedWorkbook(_ item: PreparedWorkbookItem) {
        if let existingIndex = preparedWorkbooks.firstIndex(where: { $0.id == item.id }) {
            preparedWorkbooks[existingIndex] = item
        } else {
            preparedWorkbooks.append(item)
        }
    }
}
