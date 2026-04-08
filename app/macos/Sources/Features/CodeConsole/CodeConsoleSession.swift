import AppKit
import Foundation
import Observation

struct CodeConsoleContextItem: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String
    let detail: String
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
    let subtitle: String
    let templateID: String?
    let renderOptions: RenderOptionsPayload
}

@MainActor
@Observable
final class CodeConsoleSession {
    private let contextRefreshDebounceNanoseconds: UInt64 = 120_000_000

    @ObservationIgnored private var client: (any SidecarClienting)?
    @ObservationIgnored private var defaultRenderOptions = RenderOptionsPayload()
    @ObservationIgnored private var manualBinding: CodeConsoleBindingOption?
    @ObservationIgnored private var contextRevision = 0
    @ObservationIgnored private var contextRefreshTask: Task<Void, Never>?

    var editorText = ""
    var promptText = ""
    var starterCode = ""
    var promptStatusMessage = "Bind a dataset, copy the prompt for external AI, then paste the returned Python here."
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

    var outputsSummary: String {
        if let latestRunResponse {
            let outputCount = latestRunResponse.generatedFiles.count
            let duration = String(format: "%.2fs", latestRunResponse.durationSeconds)
            let exitText = latestRunResponse.exitCode.map(String.init) ?? "n/a"
            return "\(latestRunResponse.status.capitalized) · \(outputCount) files · \(duration) · exit \(exitText)"
        }
        if isRunning {
            return "Running the pasted Python in the repo-native Code Console runner."
        }
        if contextResponse != nil {
            return "Prompt ready. Paste the returned Python script here to run it."
        }
        return "Import or bind a dataset to generate the controlled prompt and runner context."
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

    var liveStatusLabel: String {
        if selectedFileURL == nil {
            return "Awaiting context"
        }
        if isRunning {
            return "Running script"
        }
        if isRefreshingContext {
            return "Refreshing prompt"
        }
        if contextResponse != nil {
            return "Prompt ready"
        }
        return "Ready"
    }

    var liveStatusSymbol: String {
        if errorMessage != nil {
            return "exclamationmark.triangle.fill"
        }
        if isRunning || isRefreshingContext {
            return "arrow.triangle.2.circlepath"
        }
        if contextResponse != nil {
            return "checkmark.circle.fill"
        }
        return "circle.dashed"
    }

    func configure(client: any SidecarClienting) {
        self.client = client
    }

    func apply(meta: SidecarMetaResponse) {
        defaultRenderOptions.stylePreset = meta.defaults.stylePreset
        defaultRenderOptions.palettePreset = meta.defaults.palettePreset
        defaultRenderOptions.visualThemeID = meta.visualThemes.first?.id
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
                    subtitle: plot.selectedTemplateID ?? plot.selectedSheet.displayName,
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
                    subtitle: dataStudio.currentRecipeLabel,
                    templateID: dataStudio.currentFigureTemplateID,
                    renderOptions: dataStudio.currentFigureRenderOptions
                )
            )
        }

        if let manualBinding {
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
            subtitle: "Direct Code Console input",
            templateID: nil,
            renderOptions: defaultRenderOptions
        )
        manualBinding = binding
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
        contextRevision += 1
        let revision = contextRevision
        contextRefreshTask?.cancel()
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
            promptStatusMessage = "Import or bind a dataset first."
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(promptText, forType: .string)
        promptStatusMessage = "Prompt copied. Paste it into the external AI, then bring the returned Python back here."
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
        if let outputDir = latestRunResponse?.outputDir {
            WorkspaceBridge.reveal([URL(fileURLWithPath: outputDir)])
        } else if let selectedFileURL {
            WorkspaceBridge.reveal([selectedFileURL])
        }
    }

    func exportCurrentOutputs() {
        revealLatestOutput()
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
        contextRevision += 1
        let revision = contextRevision
        contextRefreshTask?.cancel()
        contextRefreshTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await Task.sleep(nanoseconds: contextRefreshDebounceNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else {
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
            if revision == contextRevision {
                isRefreshingContext = false
                contextRefreshTask = nil
            }
        }

        do {
            let response = try await client.codeConsoleContext(request)
            guard revision == contextRevision else {
                return
            }
            contextResponse = response
            selectedSheet = response.sheet
            promptText = response.promptText
            promptStatusMessage = "Prompt ready for external AI."
            let previousStarterCode = starterCode
            starterCode = response.starterCode
            if editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editorText == previousStarterCode {
                editorText = response.starterCode
            }
            refreshBoundContext()
        } catch {
            guard revision == contextRevision else {
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
                value: binding.sourceURL.lastPathComponent,
                detail: binding.sourceKind.title
            ),
            .init(
                id: "sheet",
                label: "Sheet",
                value: selectedSheet.displayName,
                detail: response?.inspection.modelLabel ?? "Input sheet"
            ),
            .init(
                id: "template",
                label: "Template context",
                value: response?.template ?? binding.templateID ?? "Auto recommendation",
                detail: response?.inspection.recommendationSummary ?? binding.subtitle
            ),
            .init(
                id: "style",
                label: "Style + palette",
                value: response?.options.stylePreset ?? binding.renderOptions.stylePreset,
                detail: response?.options.palettePreset ?? binding.renderOptions.palettePreset
            ),
        ]

        if let dataset = response?.dataset {
            items.append(
                .init(
                    id: "dataset",
                    label: "Dataset summary",
                    value: "\(dataset.rawRows) rows × \(dataset.rawCols) cols",
                    detail: dataset.model
                )
            )
        }

        boundContext = items
    }

    private func clearRunState() {
        latestRunResponse = nil
        selectedGeneratedFilePath = nil
    }

    private func bindingID(kind: CodeConsoleSourceKind, url: URL) -> String {
        "\(kind.rawValue)::\(url.standardizedFileURL.path)"
    }
}
