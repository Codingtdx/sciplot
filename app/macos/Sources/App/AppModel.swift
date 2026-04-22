import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private struct ConcurrentClientBox: @unchecked Sendable {
        let base: any SidecarClienting
    }

    enum PendingPlotReplacementAction {
        case importFromFilesystem
        case openPlotDocument(URL)
        case openExternalFigure(URL, SheetValue, String?, RenderOptionsPayload?, FitOptionsPayload?)
    }

    let runtime: SidecarRuntime
    let client: any SidecarClienting
    let plotSession: PlotSession
    let dataStudioSession: DataStudioSession
    let composerSession: ComposerSession
    let codeConsoleSession: CodeConsoleSession

    var selectedWorkbench: Workbench = .plot
    var inspectorPresented = true
    var bootstrapErrorMessage: String?
    var hasBootstrapped = false
    var isPlotReplacementConfirmationPresented = false

    var activeExportAvailability: ActionAvailability {
        switch selectedWorkbench {
        case .plot:
            return plotSession.exportAvailability
        case .dataStudio:
            return dataStudioSession.exportAvailability
        case .composer:
            return composerSession.exportAvailability
        case .codeConsole:
            return codeConsoleSession.exportAvailability
        }
    }

    var activeRevealAvailability: ActionAvailability {
        switch selectedWorkbench {
        case .plot:
            return plotSession.revealOutputAvailability
        case .dataStudio:
            return dataStudioSession.revealOutputAvailability
        case .composer:
            return composerSession.revealOutputAvailability
        case .codeConsole:
            return codeConsoleSession.revealOutputAvailability
        }
    }

    var activeSaveProjectAvailability: ActionAvailability {
        switch selectedWorkbench {
        case .plot:
            return plotSession.saveProjectAvailability
        case .dataStudio:
            return dataStudioSession.saveProjectAvailability
        case .composer, .codeConsole:
            return .disabled("Project files are not available for this workbench.")
        }
    }

    var activeExportCommandTitle: String {
        switch selectedWorkbench {
        case .plot:
            return "Export Plot"
        case .dataStudio:
            return "Export Bundle"
        case .composer:
            return "Export Composition"
        case .codeConsole:
            return "Export Figures"
        }
    }

    var activeExportHelpText: String {
        if let reason = activeExportAvailability.reason {
            return reason
        }

        switch selectedWorkbench {
        case .plot:
            return "Export the current plot as PDF or 300 dpi TIFF."
        case .dataStudio:
            return "Export the comparison workbook bundle, filtered workbooks, and figure outputs."
        case .composer:
            return "Export the current composition as PDF or 300 dpi TIFF."
        case .codeConsole:
            return "Export the latest run's generated PDF figures as PDF or 300 dpi TIFF."
        }
    }

    var runtimeIssueMessage: DiagnosticMessage? {
        guard let bootstrapErrorMessage else {
            return nil
        }
        return DiagnosticMessage(summary: "Runtime unavailable", detail: bootstrapErrorMessage)
    }

    @ObservationIgnored private var pendingPlotReplacementAction: PendingPlotReplacementAction?

    init(runtime: SidecarRuntime, client: (any SidecarClienting)? = nil) {
        self.runtime = runtime
        let resolvedClient = client ?? SidecarClient(runtime: runtime)
        self.client = resolvedClient
        self.plotSession = PlotSession()
        self.dataStudioSession = DataStudioSession()
        self.composerSession = ComposerSession()
        self.codeConsoleSession = CodeConsoleSession()

        plotSession.configure(client: resolvedClient)
        dataStudioSession.configure(client: resolvedClient)
        composerSession.configure(client: resolvedClient)
        codeConsoleSession.configure(client: resolvedClient)

        dataStudioSession.openInPlotHandler = { [weak self] url, sheet, templateID, options, fitOptions in
            self?.openInPlot(inputURL: url, sheet: sheet, templateID: templateID, options: options, fitOptions: fitOptions)
        }
    }

    convenience init() {
        self.init(runtime: SidecarRuntime(), client: nil)
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else {
            return
        }

        do {
            try await runtime.ensureRunning()
            let clientBox = ConcurrentClientBox(base: client)
            async let metaTask = clientBox.base.fetchMeta()
            async let contractTask = clientBox.base.fetchPlotContract()
            let (meta, contract) = try await (metaTask, contractTask)
            plotSession.apply(meta: meta, contract: contract)
            dataStudioSession.apply(meta: meta, contract: contract)
            codeConsoleSession.apply(meta: meta)
            refreshCodeConsoleContext()
            hasBootstrapped = true
            bootstrapErrorMessage = nil
        } catch {
            if isUserCancellationError(error) {
                bootstrapErrorMessage = nil
            } else {
                bootstrapErrorMessage = error.localizedDescription
            }
        }
    }

    func switchWorkbench(_ workbench: Workbench) {
        selectedWorkbench = workbench
        refreshCodeConsoleContext()
    }

    func beginImportForActiveWorkbench() {
        switch selectedWorkbench {
        case .plot:
            requestPlotImport()
        case .dataStudio:
            dataStudioSession.beginImportFlow()
        case .composer:
            composerSession.showImportMenu()
        case .codeConsole:
            codeConsoleSession.isImporterPresented = true
        }
    }

    func exportActiveWorkbench() async {
        switch selectedWorkbench {
        case .plot:
            await plotSession.exportCurrentSelection()
        case .dataStudio:
            await dataStudioSession.exportComparisonBundle()
        case .composer:
            await composerSession.exportComposition()
        case .codeConsole:
            codeConsoleSession.exportCurrentOutputs()
        }
    }

    func saveProject() async {
        switch selectedWorkbench {
        case .plot:
            await plotSession.saveProject()
        case .dataStudio:
            await dataStudioSession.saveProject()
        case .composer, .codeConsole:
            return
        }
        refreshCodeConsoleContext()
    }

    func saveProjectAs() async {
        switch selectedWorkbench {
        case .plot:
            await plotSession.saveProjectAs()
        case .dataStudio:
            await dataStudioSession.saveProjectAs()
        case .composer, .codeConsole:
            return
        }
        refreshCodeConsoleContext()
    }

    func showHelpForActiveWorkbench() {
        switch selectedWorkbench {
        case .plot:
            plotSession.showGuide()
        case .dataStudio:
            dataStudioSession.showGuide()
        case .composer:
            composerSession.showGuide()
        case .codeConsole:
            codeConsoleSession.showGuide()
        }
    }

    func revealActiveOutput() {
        switch selectedWorkbench {
        case .plot:
            plotSession.revealLatestExport()
        case .dataStudio:
            dataStudioSession.revealLatestExport()
        case .composer:
            composerSession.revealLatestExport()
        case .codeConsole:
            codeConsoleSession.revealLatestOutput()
        }
    }

    func toggleInspector() {
        inspectorPresented.toggle()
    }

    func newDataStudioSession() {
        dataStudioSession.newSession()
        refreshCodeConsoleContext()
    }

    func clearCurrentDataStudioSession() {
        dataStudioSession.clearCurrentSession()
        refreshCodeConsoleContext()
    }

    func openInPlot(
        inputURL: URL,
        sheet: SheetValue,
        templateID: String?,
        options: RenderOptionsPayload?,
        fitOptions: FitOptionsPayload? = nil
    ) {
        selectedWorkbench = .plot
        if plotSession.hasSessionContent {
            pendingPlotReplacementAction = .openExternalFigure(inputURL, sheet, templateID, options, fitOptions)
            isPlotReplacementConfirmationPresented = true
        } else {
            plotSession.stageExternalFigure(
                inputURL: inputURL,
                sheet: sheet,
                preferredTemplateID: templateID,
                preferredOptions: options,
                preferredFitOptions: fitOptions
            )
            refreshCodeConsoleContext()
            Task {
                await plotSession.finishLoadingStagedExternalFigure(
                    preferredTemplateID: templateID,
                    preferredOptions: options,
                    expectedInputURL: inputURL,
                    expectedSheet: sheet
                )
                refreshCodeConsoleContext()
            }
        }
    }

    func refreshCodeConsoleContext() {
        codeConsoleSession.refreshContext(plot: plotSession, dataStudio: dataStudioSession)
    }

    func confirmPendingPlotReplacement() {
        guard let pendingPlotReplacementAction else {
            return
        }

        isPlotReplacementConfirmationPresented = false
        self.pendingPlotReplacementAction = nil

        switch pendingPlotReplacementAction {
        case .importFromFilesystem:
            plotSession.isImporterPresented = true
        case let .openPlotDocument(url):
            Task {
                if url.pathExtension.lowercased() == "sciplotgod" {
                    await openProjectDocument(url)
                } else {
                    selectedWorkbench = .plot
                    plotSession.importFile(url)
                }
                refreshCodeConsoleContext()
            }
        case let .openExternalFigure(url, sheet, templateID, options, fitOptions):
            plotSession.stageExternalFigure(
                inputURL: url,
                sheet: sheet,
                preferredTemplateID: templateID,
                preferredOptions: options,
                preferredFitOptions: fitOptions
            )
            refreshCodeConsoleContext()
            Task {
                await plotSession.finishLoadingStagedExternalFigure(
                    preferredTemplateID: templateID,
                    preferredOptions: options,
                    expectedInputURL: url,
                    expectedSheet: sheet
                )
                refreshCodeConsoleContext()
            }
        }
    }

    func cancelPendingPlotReplacement() {
        pendingPlotReplacementAction = nil
        isPlotReplacementConfirmationPresented = false
    }

    private func requestPlotImport() {
        if plotSession.hasSessionContent {
            pendingPlotReplacementAction = .importFromFilesystem
            isPlotReplacementConfirmationPresented = true
        } else {
            plotSession.isImporterPresented = true
        }
    }

    func openPlotDocument(_ url: URL) {
        if url.pathExtension.lowercased() == "sciplotgod" {
            Task {
                await openProjectDocument(url)
                refreshCodeConsoleContext()
            }
            return
        }
        selectedWorkbench = .plot
        if plotSession.hasSessionContent {
            pendingPlotReplacementAction = .openPlotDocument(url)
            isPlotReplacementConfirmationPresented = true
            return
        }
        Task {
            if url.pathExtension.lowercased() == "sciplotgod" {
                await plotSession.openProject(url)
            } else {
                plotSession.importFile(url)
            }
            refreshCodeConsoleContext()
        }
    }

    func openProjectDocument(_ url: URL) async {
        do {
            let response = try await client.openProject(.init(projectPath: url.path))
            switch response.payload.selectedWorkbench {
            case "data_studio":
                selectedWorkbench = .dataStudio
                await dataStudioSession.restoreProject(from: response)
            default:
                selectedWorkbench = .plot
                await plotSession.restoreProject(from: response)
            }
        } catch {
            if isUserCancellationError(error) {
                return
            }
            if url.pathExtension.lowercased() == "sciplotgod" {
                switch selectedWorkbench {
                case .dataStudio:
                    dataStudioSession.errorMessage = error.localizedDescription
                default:
                    plotSession.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
