import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum PendingPlotReplacementAction {
        case importFromFilesystem
        case seedFromDataStudio(URL, SheetValue)
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

        dataStudioSession.openInPlotHandler = { [weak self] url, sheet in
            self?.openInPlot(workbookURL: url, preferredSheet: sheet)
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
            let meta = try await client.fetchMeta()
            let contract = try await client.fetchPlotContract()
            plotSession.apply(meta: meta, contract: contract)
            dataStudioSession.apply(meta: meta)
            codeConsoleSession.apply(meta: meta)
            refreshCodeConsoleContext()
            hasBootstrapped = true
            bootstrapErrorMessage = nil
        } catch {
            bootstrapErrorMessage = error.localizedDescription
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
            dataStudioSession.showImportMenu()
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

    func openInPlot(workbookURL: URL, preferredSheet: SheetValue) {
        selectedWorkbench = .plot
        if plotSession.hasSessionContent {
            pendingPlotReplacementAction = .seedFromDataStudio(workbookURL, preferredSheet)
            isPlotReplacementConfirmationPresented = true
        } else {
            plotSession.seedFromDataStudio(workbookURL: workbookURL, preferredSheet: preferredSheet)
            refreshCodeConsoleContext()
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
        case let .seedFromDataStudio(url, sheet):
            plotSession.seedFromDataStudio(workbookURL: url, preferredSheet: sheet)
            refreshCodeConsoleContext()
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
}
