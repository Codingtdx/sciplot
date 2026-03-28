import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum PendingPlotReplacementAction {
        case importFromFilesystem
        case seedFromCleanup(URL, SheetValue)
    }

    let runtime: SidecarRuntime
    let client: any SidecarClienting
    let plotSession: PlotSession
    let dataCleanupSession: DataCleanupSession
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
        self.dataCleanupSession = DataCleanupSession()
        self.composerSession = ComposerSession()
        self.codeConsoleSession = CodeConsoleSession()

        plotSession.configure(client: resolvedClient)
        dataCleanupSession.configure(client: resolvedClient)
        composerSession.configure(client: resolvedClient)

        dataCleanupSession.openInPlotHandler = { [weak self] url, sheet in
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
            async let metaPayload = client.fetchMeta()
            async let contractPayload = client.fetchPlotContract()
            let (meta, contract) = try await (metaPayload, contractPayload)
            plotSession.apply(meta: meta, contract: contract)
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
        case .dataCleanup:
            dataCleanupSession.isRawImporterPresented = true
        case .composer:
            composerSession.beginImport(kind: .graph)
        case .codeConsole:
            break
        }
    }

    func exportActiveWorkbench() async {
        switch selectedWorkbench {
        case .plot:
            await plotSession.exportCurrentSelection()
        case .dataCleanup:
            await dataCleanupSession.exportComparisonBundle()
        case .composer:
            await composerSession.exportComposition()
        case .codeConsole:
            break
        }
    }

    func revealActiveOutput() {
        switch selectedWorkbench {
        case .plot:
            plotSession.revealLatestExport()
        case .dataCleanup:
            dataCleanupSession.revealLatestExport()
        case .composer:
            composerSession.revealLatestExport()
        case .codeConsole:
            break
        }
    }

    func toggleInspector() {
        inspectorPresented.toggle()
    }

    func openInPlot(workbookURL: URL, preferredSheet: SheetValue) {
        selectedWorkbench = .plot
        if plotSession.hasSessionContent {
            pendingPlotReplacementAction = .seedFromCleanup(workbookURL, preferredSheet)
            isPlotReplacementConfirmationPresented = true
        } else {
            plotSession.seedFromCleanup(workbookURL: workbookURL, preferredSheet: preferredSheet)
            refreshCodeConsoleContext()
        }
    }

    func refreshCodeConsoleContext() {
        codeConsoleSession.refreshContext(plot: plotSession, dataCleanup: dataCleanupSession)
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
        case let .seedFromCleanup(url, sheet):
            plotSession.seedFromCleanup(workbookURL: url, preferredSheet: sheet)
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
