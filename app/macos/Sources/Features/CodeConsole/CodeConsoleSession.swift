import AppKit
import Foundation
import Observation

struct CodeConsoleContextItem: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String
}

enum CodeConsoleSourceKind: String, Sendable {
    case plot
    case dataStudio
    case importedFile

    var title: String {
        switch self {
        case .plot:
            return "Plot"
        case .dataStudio:
            return "Data Studio"
        case .importedFile:
            return "Imported File"
        }
    }
}

struct CodeConsoleBindingOption: Identifiable, Equatable, Sendable {
    let id: String
    let sourceKind: CodeConsoleSourceKind
    let sourceURL: URL
    let sheet: SheetValue
    let title: String
    let templateID: String?
    let renderOptions: RenderOptionsPayload
}

@MainActor
@Observable
final class CodeConsoleSession {
    typealias CodeConsoleExportFormatChooser = @MainActor (_ isMultiOutput: Bool) -> ExportGraphicFormat?
    typealias CodeConsoleExportDestinationChooser = @MainActor (_ suggestedName: String, _ isMultiOutput: Bool, _ format: ExportGraphicFormat) -> URL?
    typealias CodeConsoleExportMaterializer = @MainActor (_ sourceURLs: [URL], _ destinationURL: URL) throws -> [URL]

    private let contextRefreshDebounceNanoseconds: UInt64 = 120_000_000

    @ObservationIgnored private var client: (any SidecarClienting)?
    @ObservationIgnored private var runtimeState = RuntimeState()
    @ObservationIgnored private let asyncCoordination = AsyncCoordination()
    @ObservationIgnored private let chooseExportFormat: CodeConsoleExportFormatChooser
    @ObservationIgnored private let chooseExportDestination: CodeConsoleExportDestinationChooser
    @ObservationIgnored private let materializeExport: CodeConsoleExportMaterializer

    var editorText = ""
    var promptText = ""
    var starterCode = ""
    var boundContext: [CodeConsoleContextItem] = []
    var availableBindings: [CodeConsoleBindingOption] = []
    var selectedBindingID: String?
    var selectedSheet: SheetValue = .index(0)
    var contextResponse: CodeConsoleContextResponse?
    var latestRunResponse: CodeConsoleRunResponse?
    var selectedGeneratedFilePath: String?
    var errorMessage: String?
    var isImporterPresented = false
    var isGuidePresented = false
    var isRefreshingContext = false
    var isRunning = false
    var userExportURLs: [URL] = []

    var exportAvailability: ActionAvailability {
        if isRunning {
            return .disabled("Wait for the current run to finish.")
        }
        guard latestRunResponse != nil else {
            return .disabled("Run code to generate PDF figures before exporting.")
        }
        guard !exportableGeneratedFigureURLs.isEmpty else {
            return .disabled("The latest run did not generate any PDF figures to export.")
        }
        return .enabled()
    }

    var selectedBinding: CodeConsoleBindingOption? {
        availableBindings.first(where: { $0.id == selectedBindingID }) ?? availableBindings.first
    }

    var selectedFileURL: URL? {
        selectedBinding?.sourceURL
    }

    var selectedSourceFilename: String? {
        selectedFileURL?.lastPathComponent
    }

    var availableSheets: [SheetValue] {
        let names = contextResponse?.sheetNames ?? []
        if !names.isEmpty {
            return names.map(SheetValue.name)
        }
        return [selectedSheet]
    }

    var selectedGeneratedFile: CodeConsoleGeneratedFileResponse? {
        guard let latestRunResponse else {
            return nil
        }
        if let selectedGeneratedFilePath {
            return latestRunResponse.generatedFiles.first(where: { $0.path == selectedGeneratedFilePath }) ?? latestRunResponse.generatedFiles.first
        }
        return latestRunResponse.generatedFiles.first
    }

    var selectedGeneratedFileURL: URL? {
        guard let path = selectedGeneratedFile?.path else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    var latestExportItems: [ExportedFileItem] {
        userExportURLs.map { ExportedFileItem(url: $0) }
    }

    var liveStatusSymbol: String {
        DerivedState.liveStatusSymbol(
            hasError: errorMessage != nil,
            isRunning: isRunning,
            isRefreshingContext: isRefreshingContext,
            hasContextResponse: contextResponse != nil
        )
    }

    init(
        chooseExportFormat: @escaping CodeConsoleExportFormatChooser = {
            NativeExportCoordinator.chooseCodeConsoleExportFormat(isMultiOutput: $0)
        },
        chooseExportDestination: @escaping CodeConsoleExportDestinationChooser = {
            NativeExportCoordinator.chooseCodeConsoleExportLocation(
                suggestedName: $0,
                isMultiOutput: $1,
                format: $2
            )
        },
        materializeExport: @escaping CodeConsoleExportMaterializer = {
            try NativeExportCoordinator.materializePlotOutputs(sourceURLs: $0, destinationURL: $1)
        }
    ) {
        self.chooseExportFormat = chooseExportFormat
        self.chooseExportDestination = chooseExportDestination
        self.materializeExport = materializeExport
    }

    func configure(client: any SidecarClienting) {
        self.client = client
    }

    func apply(meta: SidecarMetaResponse) {
        runtimeState.defaultRenderOptions.stylePreset = meta.defaults.stylePreset
        runtimeState.defaultRenderOptions.palettePreset = meta.defaults.palettePreset
        runtimeState.defaultRenderOptions.visualThemeID = meta.visualThemes.first?.id
    }

    func refreshContext(plot: PlotSession, dataStudio: DataStudioSession) {
        let previousSelection = selectedBindingID
        var bindings: [CodeConsoleBindingOption] = []

        if let fileURL = plot.selectedFileURL {
            bindings.append(
                .init(
                    id: bindingID(kind: .plot, url: fileURL),
                    sourceKind: .plot,
                    sourceURL: fileURL,
                    sheet: plot.selectedSheet,
                    title: "Current Plot session",
                    templateID: plot.selectedTemplateID,
                    renderOptions: plot.renderOptions
                )
            )
        }

        if let sourceURL = dataStudio.currentFigureSourceURL {
            bindings.append(
                .init(
                    id: bindingID(kind: .dataStudio, url: sourceURL),
                    sourceKind: .dataStudio,
                    sourceURL: sourceURL,
                    sheet: dataStudio.currentFigureSheet,
                    title: "Current Data Studio figure",
                    templateID: dataStudio.currentFigureTemplateID,
                    renderOptions: dataStudio.currentFigureRenderOptions
                )
            )
        }

        if let manualBinding = runtimeState.manualBinding {
            bindings.append(manualBinding)
        }

        availableBindings = bindings

        if let previousSelection, bindings.contains(where: { $0.id == previousSelection }) {
            selectedBindingID = previousSelection
        } else {
            selectedBindingID = bindings.first?.id
        }

        if let binding = selectedBinding {
            selectedSheet = binding.sheet
            refreshBoundContext()
            scheduleContextRefresh()
        } else {
            asyncCoordination.context.cancel()
            selectedSheet = .index(0)
            contextResponse = nil
            promptText = ""
            starterCode = ""
            boundContext = []
            clearRunState()
        }
    }

    func importFile(_ url: URL) {
        let binding = CodeConsoleBindingOption(
            id: bindingID(kind: .importedFile, url: url),
            sourceKind: .importedFile,
            sourceURL: url,
            sheet: .index(0),
            title: "Imported file",
            templateID: nil,
            renderOptions: runtimeState.defaultRenderOptions
        )
        runtimeState.manualBinding = binding
        if !availableBindings.contains(where: { $0.id == binding.id }) {
            availableBindings.append(binding)
        }
        selectedBindingID = binding.id
        selectedSheet = binding.sheet
        errorMessage = nil
        refreshBoundContext()
        scheduleContextRefresh()
    }

    func setSelectedBinding(id: String) {
        guard selectedBindingID != id else {
            return
        }
        selectedBindingID = id
        if let binding = selectedBinding {
            selectedSheet = binding.sheet
        }
        errorMessage = nil
        refreshBoundContext()
        scheduleContextRefresh()
    }

    func setSelectedSheet(_ sheet: SheetValue) {
        guard selectedSheet != sheet else {
            return
        }
        selectedSheet = sheet
        errorMessage = nil
        refreshBoundContext()
        scheduleContextRefresh()
    }

    func refreshPrompt() {
        scheduleContextRefresh()
    }

    func showGuide() {
        isGuidePresented = true
    }

    func dismissGuide() {
        isGuidePresented = false
    }

    func refreshCurrentContext() async {
        let revision = asyncCoordination.context.beginNow()
        await loadContext(revision: revision)
    }

    func restoreStarterCode() {
        guard !starterCode.isEmpty else {
            return
        }
        editorText = starterCode
    }

    func copyPromptToPasteboard() {
        guard !promptText.isEmpty else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(promptText, forType: .string)
    }

    func runCurrentCode() async {
        guard !editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Paste Python code from the external AI before running Code Console."
            return
        }
        guard let client, let request = currentRunRequest() else {
            errorMessage = "Import or bind a dataset before running Code Console."
            return
        }

        isRunning = true
        errorMessage = nil
        userExportURLs = []
        defer { isRunning = false }

        do {
            let response = try await client.runCodeConsole(request)
            latestRunResponse = response
            selectedGeneratedFilePath = response.generatedFiles.first?.path
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectGeneratedFile(path: String) {
        selectedGeneratedFilePath = path
    }

    func openSelectedGeneratedFile() {
        guard let selectedGeneratedFileURL else {
            return
        }
        WorkspaceBridge.open(selectedGeneratedFileURL)
    }

    func revealSelectedGeneratedFile() {
        guard let selectedGeneratedFileURL else {
            return
        }
        WorkspaceBridge.reveal([selectedGeneratedFileURL])
    }

    func revealLatestOutput() {
        if !userExportURLs.isEmpty {
            WorkspaceBridge.reveal(userExportURLs)
            return
        }
        revealManagedOutputFolder()
    }

    func revealManagedOutputFolder() {
        if let outputDir = latestRunResponse?.outputDir {
            WorkspaceBridge.reveal([URL(fileURLWithPath: outputDir)])
        } else if let selectedFileURL {
            WorkspaceBridge.reveal([selectedFileURL])
        }
    }

    func exportCurrentOutputs() {
        let sourceURLs = exportableGeneratedFigureURLs
        guard !sourceURLs.isEmpty else {
            return
        }

        let isMultiOutput = sourceURLs.count > 1
        guard let exportFormat = chooseExportFormat(isMultiOutput) else {
            return
        }
        guard let destinationURL = chooseExportDestination(
            suggestedExportFilename(format: exportFormat, isMultiOutput: isMultiOutput),
            isMultiOutput,
            exportFormat
        ) else {
            return
        }

        do {
            userExportURLs = try materializeExport(sourceURLs, destinationURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openLatestExport(id: String) {
        guard let item = latestExportItems.first(where: { $0.id == id }) else {
            return
        }
        WorkspaceBridge.open(item.url)
    }

    func openCurrentSource() {
        guard let selectedFileURL else {
            return
        }
        WorkspaceBridge.open(selectedFileURL)
    }

    func revealCurrentSource() {
        guard let selectedFileURL else {
            return
        }
        WorkspaceBridge.reveal([selectedFileURL])
    }

    private func scheduleContextRefresh() {
        asyncCoordination.context.schedule(delayNanoseconds: contextRefreshDebounceNanoseconds) { [weak self] revision in
            guard let self else {
                return
            }
            await self.loadContext(revision: revision)
        }
    }

    private func loadContext(revision: Int) async {
        guard let client, let request = currentContextRequest() else {
            return
        }

        isRefreshingContext = true
        clearRunState()
        defer {
            if asyncCoordination.context.isLatest(revision) {
                isRefreshingContext = false
            }
        }

        do {
            let response = try await client.codeConsoleContext(request)
            guard asyncCoordination.context.isLatest(revision), !Task.isCancelled else {
                return
            }
            contextResponse = response
            selectedSheet = response.sheet
            promptText = response.promptText
            let previousStarterCode = starterCode
            starterCode = response.starterCode
            if editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editorText == previousStarterCode {
                editorText = response.starterCode
            }
            refreshBoundContext()
        } catch {
            guard asyncCoordination.context.isLatest(revision), !Task.isCancelled else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func currentContextRequest() -> CodeConsoleContextRequest? {
        guard let binding = selectedBinding else {
            return nil
        }
        return .init(
            inputPath: binding.sourceURL.path,
            sheet: selectedSheet,
            template: binding.templateID,
            options: binding.renderOptions,
            sourceKind: binding.sourceKind.rawValue,
            sourceLabel: binding.title
        )
    }

    private func currentRunRequest() -> CodeConsoleRunRequest? {
        guard let contextRequest = currentContextRequest() else {
            return nil
        }
        return .init(
            contextID: contextResponse?.contextID,
            context: contextRequest,
            code: editorText,
            timeoutSeconds: 90
        )
    }

    private func refreshBoundContext() {
        guard let binding = selectedBinding else {
            boundContext = []
            return
        }

        let response = contextResponse
        var items: [CodeConsoleContextItem] = [
            .init(
                id: "source",
                label: "Bound source",
                value: binding.sourceURL.lastPathComponent
            ),
            .init(
                id: "sheet",
                label: "Sheet",
                value: selectedSheet.displayName
            ),
            .init(
                id: "template",
                label: "Template context",
                value: response?.template ?? binding.templateID ?? "Auto recommendation"
            ),
            .init(
                id: "style",
                label: "Style + palette",
                value: [
                    response?.options.stylePreset ?? binding.renderOptions.stylePreset,
                    response?.options.palettePreset ?? binding.renderOptions.palettePreset,
                ]
                .filter { !$0.isEmpty }
                .joined(separator: " / ")
            ),
        ]

        if let dataset = response?.dataset {
            items.append(
                .init(
                    id: "dataset",
                    label: "Dataset summary",
                    value: "\(dataset.rawRows) rows × \(dataset.rawCols) cols"
                )
            )
        }

        boundContext = items
    }

    private func clearRunState() {
        latestRunResponse = nil
        selectedGeneratedFilePath = nil
        userExportURLs = []
    }

    private var exportableGeneratedFigureURLs: [URL] {
        guard let latestRunResponse else {
            return []
        }
        return latestRunResponse.generatedFiles.compactMap { item in
            guard item.fileType.lowercased() == "pdf" || URL(fileURLWithPath: item.path).pathExtension.lowercased() == "pdf" else {
                return nil
            }
            return URL(fileURLWithPath: item.path)
        }
    }

    private func suggestedExportFilename(
        format: ExportGraphicFormat,
        isMultiOutput: Bool
    ) -> String {
        if !isMultiOutput,
           let latest = userExportURLs.first
        {
            return NativeExportCoordinator.suggestedGraphicFilename(
                from: latest.lastPathComponent,
                format: format
            )
        }

        if !isMultiOutput,
           let firstPDF = exportableGeneratedFigureURLs.first
        {
            return NativeExportCoordinator.suggestedGraphicFilename(
                from: firstPDF.lastPathComponent,
                format: format
            )
        }

        let baseStem = selectedFileURL?.deletingPathExtension().lastPathComponent ?? "code_console"
        return NativeExportCoordinator.suggestedGraphicFilename(
            from: "\(baseStem)_code_console",
            format: format
        )
    }

    private func bindingID(kind: CodeConsoleSourceKind, url: URL) -> String {
        "\(kind.rawValue)::\(url.standardizedFileURL.path)"
    }
}

private extension CodeConsoleSession {
    struct RuntimeState {
        var defaultRenderOptions = RenderOptionsPayload()
        var manualBinding: CodeConsoleBindingOption?
    }

    @MainActor
    final class AsyncCoordination {
        let context = AsyncLatestTaskCoordinator()
    }

    enum DerivedState {
        static func liveStatusSymbol(
            hasError: Bool,
            isRunning: Bool,
            isRefreshingContext: Bool,
            hasContextResponse: Bool
        ) -> String {
            if hasError {
                return "exclamationmark.triangle.fill"
            }
            if isRunning || isRefreshingContext {
                return "arrow.triangle.2.circlepath"
            }
            if hasContextResponse {
                return "checkmark.circle.fill"
            }
            return "circle.dashed"
        }
    }
}
