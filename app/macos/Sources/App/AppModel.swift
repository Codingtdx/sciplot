import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    private struct ConcurrentClientBox: @unchecked Sendable {
        let base: any SidecarClienting
    }

    typealias AppProjectSaveChooser = @MainActor (_ suggestedName: String) -> URL?

    struct ProjectSnapshot: Equatable {
        let plot: PlotSession.ProjectSnapshot?
        let dataStudio: DataStudioSession.ProjectSnapshot?
        let composer: ComposerSession.ProjectSnapshot?
        let codeConsole: CodeConsoleSession.ProjectSnapshot?
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
    @ObservationIgnored let chooseProjectSaveLocation: AppProjectSaveChooser

    var selectedWorkbench: Workbench = .plot
    var projectURL: URL?
    var isSavingProject = false
    var requestedWorkbenchWindow: Workbench?
    var columnVisibility: NavigationSplitViewVisibility = .all
    var inspectorPresented = true
    var inspectorPresentationByWorkbench: [Workbench: Bool] = [
        .plot: true,
        .dataStudio: true,
        .composer: true,
        .codeConsole: true,
    ]
    var isQuickHelpPresented = false
    var quickHelpWorkbench: Workbench?
    var bootstrapErrorMessage: String?
    var hasBootstrapped = false
    var isPlotReplacementConfirmationPresented = false
    @ObservationIgnored var lastSavedProjectSnapshot: ProjectSnapshot?

    var activeExportAvailability: ActionAvailability {
        exportAvailability(for: selectedWorkbench)
    }

    func exportAvailability(for workbench: Workbench) -> ActionAvailability {
        switch workbench {
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
        revealAvailability(for: selectedWorkbench)
    }

    func revealAvailability(for workbench: Workbench) -> ActionAvailability {
        switch workbench {
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
        saveProjectAvailability(for: selectedWorkbench)
    }

    func saveProjectAvailability(for _: Workbench) -> ActionAvailability {
        if isSavingProject {
            return .disabled("Project save is already in progress.")
        }
        if plotSession.hasSessionContent {
            guard plotSession.currentProjectSnapshot != nil else {
                return .disabled(plotSession.saveProjectAvailability.reason ?? "Finish Plot setup before saving the project.")
            }
            guard !plotSession.needsInspection else {
                return .disabled("Wait for inspect to finish before saving the project.")
            }
        }
        if dataStudioSession.hasSessionContent {
            guard dataStudioSession.currentProjectSnapshot != nil else {
                return .disabled(dataStudioSession.saveProjectAvailability.reason ?? "Finish Data Studio setup before saving the project.")
            }
        }
        guard hasAnyDurableProjectContent else {
            return .disabled("Add content in any module before saving a project.")
        }
        return .enabled()
    }

    var activeExportCommandTitle: String {
        exportCommandTitle(for: selectedWorkbench)
    }

    func exportCommandTitle(for workbench: Workbench) -> String {
        switch workbench {
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
        exportHelpText(for: selectedWorkbench)
    }

    func exportHelpText(for workbench: Workbench) -> String {
        let availability = exportAvailability(for: workbench)
        if let reason = availability.reason {
            return reason
        }

        switch workbench {
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
        let recentRuntimeLogs = runtime.logs.suffix(8)
        let detail: String
        if recentRuntimeLogs.isEmpty {
            detail = bootstrapErrorMessage
        } else {
            detail = """
            \(bootstrapErrorMessage)

            Recent runtime logs:
            \(recentRuntimeLogs.joined(separator: "\n"))
            """
        }
        return DiagnosticMessage(summary: "Runtime unavailable", detail: detail)
    }

    @ObservationIgnored private var pendingPlotReplacementAction: PendingPlotReplacementAction?

    init(
        runtime: SidecarRuntime,
        client: (any SidecarClienting)? = nil,
        chooseProjectSaveLocation: @escaping AppProjectSaveChooser = {
            NativePanels.chooseAppProjectSaveLocation(suggestedName: $0)
        }
    ) {
        self.runtime = runtime
        let resolvedClient = client ?? SidecarClient(runtime: runtime)
        self.client = resolvedClient
        self.plotSession = PlotSession()
        self.dataStudioSession = DataStudioSession()
        self.composerSession = ComposerSession()
        self.codeConsoleSession = CodeConsoleSession()
        self.chooseProjectSaveLocation = chooseProjectSaveLocation

        plotSession.configure(client: resolvedClient)
        dataStudioSession.configure(client: resolvedClient)
        composerSession.configure(client: resolvedClient)
        codeConsoleSession.configure(client: resolvedClient)

        dataStudioSession.openInPlotHandler = { [weak self] url, sheet, templateID, options, fitOptions in
            self?.openInPlot(inputURL: url, sheet: sheet, templateID: templateID, options: options, fitOptions: fitOptions)
        }
        dataStudioSession.openProjectDocumentHandler = { [weak self] url in
            await self?.openProjectDocument(url)
        }
        plotSession.openProjectDocumentHandler = { [weak self] url in
            await self?.openProjectDocument(url)
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
        requestOpenWindow(for: workbench)
        refreshCodeConsoleContext()
    }

    func enterWorkbench(_ workbench: Workbench) {
        requestOpenWindow(for: workbench)
    }

    func showLauncher() {
        requestedWorkbenchWindow = nil
    }

    func newProject() {
        cancelPendingPlotReplacement()
        projectURL = nil
        lastSavedProjectSnapshot = nil
        plotSession.newSession()
        dataStudioSession.newSession()
        composerSession.newSession()
        codeConsoleSession.newSession()
        selectedWorkbench = .plot
        requestedWorkbenchWindow = nil
        refreshCodeConsoleContext()
    }

    func beginLauncherPrimaryAction(for workbench: Workbench) {
        requestOpenWindow(for: workbench)
        beginImport(for: workbench)
    }

    func beginImportForActiveWorkbench() {
        beginImport(for: selectedWorkbench)
    }

    func beginImport(for workbench: Workbench) {
        switch workbench {
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

    func showPlotDataWorkbook() {
        plotSession.showDataWorkbook()
    }

    func exportActiveWorkbench() async {
        await export(for: selectedWorkbench)
    }

    func export(for workbench: Workbench) async {
        switch workbench {
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
        await saveProject(for: selectedWorkbench)
    }

    func saveProject(for workbench: Workbench) async {
        if let projectURL {
            await saveProject(to: projectURL, selectedWorkbench: workbench)
            return
        }
        await saveProjectAs(for: workbench)
    }

    func saveProjectAs() async {
        await saveProjectAs(for: selectedWorkbench)
    }

    func saveProjectAs(for workbench: Workbench) async {
        guard saveProjectAvailability(for: workbench).isEnabled else {
            return
        }
        guard let destinationURL = chooseProjectSaveLocation(suggestedProjectFilename(for: workbench)) else {
            return
        }
        await saveProject(to: destinationURL, selectedWorkbench: workbench)
    }

    func openProjectFromPanel() {
        guard let url = NativePanels.chooseProjectOpenLocation() else {
            return
        }
        Task { await openProjectDocument(url) }
    }

    func saveProject(to destinationURL: URL, selectedWorkbench workbench: Workbench) async {
        guard let payload = await buildAppProjectPayload(
            selectedWorkbench: workbench,
            projectDisplayName: destinationURL.deletingPathExtension().lastPathComponent
        ) else {
            setProjectError("Add content in any module before saving a project.", for: workbench)
            return
        }
        guard let selectedSourcePath = payload.plot.flatMap({ _ in plotSession.selectedFileURL?.path }) else {
            if payload.plot != nil {
                setProjectError("Plot projects require a source file.", for: workbench)
                return
            }
            isSavingProject = true
            await submitProjectSave(destinationURL: destinationURL, sourcePath: nil, payload: payload, workbench: workbench)
            return
        }
        isSavingProject = true
        await submitProjectSave(destinationURL: destinationURL, sourcePath: selectedSourcePath, payload: payload, workbench: workbench)
    }

    func showHelpForActiveWorkbench() {
        showHelp(for: selectedWorkbench)
    }

    func showHelp(for workbench: Workbench) {
        quickHelpWorkbench = workbench
        isQuickHelpPresented = true
    }

    func dismissQuickHelp() {
        isQuickHelpPresented = false
        quickHelpWorkbench = nil
    }

    func revealActiveOutput() {
        revealOutput(for: selectedWorkbench)
    }

    func revealOutput(for workbench: Workbench) {
        switch workbench {
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
        toggleInspector(for: selectedWorkbench)
        inspectorPresented = isInspectorPresented(for: selectedWorkbench)
    }

    func toggleInspector(for workbench: Workbench) {
        setInspectorPresented(!isInspectorPresented(for: workbench), for: workbench)
    }

    func hideInspector() {
        setInspectorPresented(false, for: selectedWorkbench)
        inspectorPresented = false
    }

    func showInspector() {
        setInspectorPresented(true, for: selectedWorkbench)
        inspectorPresented = true
    }

    func isInspectorPresented(for workbench: Workbench) -> Bool {
        inspectorPresentationByWorkbench[workbench] ?? true
    }

    func setInspectorPresented(_ isPresented: Bool, for workbench: Workbench) {
        inspectorPresentationByWorkbench[workbench] = isPresented
    }

    func toggleWorkbenchSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
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
        requestOpenWindow(for: .plot)
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
                    requestOpenWindow(for: .plot)
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
        selectedWorkbench = .plot
        requestOpenWindow(for: .plot)
        if plotSession.hasSessionContent {
            pendingPlotReplacementAction = .openPlotDocument(url)
            isPlotReplacementConfirmationPresented = true
            return
        }
        Task {
            if url.pathExtension.lowercased() == "sciplotgod" {
                await openProjectDocument(url)
            } else {
                plotSession.importFile(url)
            }
            refreshCodeConsoleContext()
        }
    }

    func openProjectDocument(_ url: URL) async {
        do {
            let response = try await client.openProject(.init(projectPath: url.path))
            await restoreProject(from: response)
        } catch {
            if isUserCancellationError(error) {
                return
            }
            if url.pathExtension.lowercased() == "sciplotgod" {
                setProjectError(error.localizedDescription, for: selectedWorkbench)
            }
        }
    }

    var hasAnyDurableProjectContent: Bool {
        plotSession.currentProjectSnapshot != nil
            || dataStudioSession.currentProjectSnapshot != nil
            || composerSession.currentProjectSnapshot != nil
            || codeConsoleSession.currentProjectSnapshot != nil
    }

    func currentProjectSnapshot(selectedWorkbench _: Workbench) -> ProjectSnapshot? {
        guard hasAnyDurableProjectContent else {
            return nil
        }
        return ProjectSnapshot(
            plot: plotSession.currentProjectSnapshot,
            dataStudio: dataStudioSession.currentProjectSnapshot,
            composer: composerSession.currentProjectSnapshot,
            codeConsole: codeConsoleSession.currentProjectSnapshot
        )
    }

    var isProjectDirty: Bool {
        guard let currentProjectSnapshot = currentProjectSnapshot(selectedWorkbench: selectedWorkbench) else {
            return false
        }
        guard let lastSavedProjectSnapshot else {
            return true
        }
        return currentProjectSnapshot != lastSavedProjectSnapshot
    }

    func buildAppProjectPayload(
        selectedWorkbench requestedWorkbench: Workbench,
        projectDisplayName: String? = nil
    ) async -> ProjectBundlePayload? {
        let projectDisplayName = projectDisplayName ?? projectURL?.deletingPathExtension().lastPathComponent
        let plotPayload = plotSession.buildProjectPayload()?.plot
        let dataStudioPayload: DataStudioProjectPayload?
        if dataStudioSession.currentProjectSnapshot != nil {
            guard let normalizedSession = await dataStudioSession.normalizeSessionPayload() else {
                return nil
            }
            dataStudioPayload = dataStudioSession.buildDataStudioProjectPayload(
                from: normalizedSession,
                projectDisplayName: projectDisplayName
            )
        } else {
            dataStudioPayload = nil
        }

        var composerPayload = composerSession.buildProjectPayload(projectDisplayName: projectDisplayName)
        var codeConsolePayload = codeConsoleSession.buildProjectPayload(projectDisplayName: projectDisplayName)
        var selectedProjectWorkbench = requestedWorkbench

        switch requestedWorkbench {
        case .plot:
            if plotPayload == nil {
                selectedProjectWorkbench = firstWorkbenchWithPayload(
                    plot: plotPayload,
                    dataStudio: dataStudioPayload,
                    composer: composerPayload,
                    codeConsole: codeConsolePayload
                ) ?? .plot
            }
        case .dataStudio:
            if dataStudioPayload == nil {
                selectedProjectWorkbench = firstWorkbenchWithPayload(
                    plot: plotPayload,
                    dataStudio: dataStudioPayload,
                    composer: composerPayload,
                    codeConsole: codeConsolePayload
                ) ?? .dataStudio
            }
        case .composer:
            if composerPayload == nil {
                composerPayload = composerSession.emptyProjectPayload(projectDisplayName: projectDisplayName)
            }
        case .codeConsole:
            if codeConsolePayload == nil {
                codeConsolePayload = codeConsoleSession.emptyProjectPayload(projectDisplayName: projectDisplayName)
            }
        }

        guard plotPayload != nil
            || dataStudioPayload != nil
            || composerPayload != nil
            || codeConsolePayload != nil
        else {
            return nil
        }

        return ProjectBundlePayload(
            version: 2,
            selectedWorkbench: sidecarWorkbenchID(for: selectedProjectWorkbench),
            plot: plotPayload,
            dataStudio: dataStudioPayload,
            composer: composerPayload,
            codeConsole: codeConsolePayload,
            artifacts: ["manifest_relpath": .string("artifacts/manifest.json")]
        )
    }

    func restoreProject(from response: OpenProjectResponse) async {
        let projectURL = URL(fileURLWithPath: response.projectPath)
        if response.payload.plot != nil {
            await plotSession.restoreProject(from: response)
        } else {
            plotSession.newSession()
        }

        if response.payload.dataStudio != nil {
            await dataStudioSession.restoreProject(from: response)
        } else {
            dataStudioSession.newSession()
        }

        if let composerPayload = response.payload.composer {
            composerSession.restoreProjectPayload(composerPayload)
        } else {
            composerSession.newSession()
        }

        refreshCodeConsoleContext()
        if let codeConsolePayload = response.payload.codeConsole {
            codeConsoleSession.restoreProjectPayload(
                codeConsolePayload,
                plot: plotSession,
                dataStudio: dataStudioSession
            )
        } else {
            codeConsoleSession.newSession()
            refreshCodeConsoleContext()
        }

        self.projectURL = projectURL
        plotSession.projectURL = projectURL
        dataStudioSession.projectURL = projectURL
        let restoredWorkbench = workbench(fromSidecarID: response.payload.selectedWorkbench)
        selectedWorkbench = restoredWorkbench
        requestOpenWindow(for: restoredWorkbench)
        lastSavedProjectSnapshot = currentProjectSnapshot(selectedWorkbench: restoredWorkbench)
    }

    private func submitProjectSave(
        destinationURL: URL,
        sourcePath: String?,
        payload: ProjectBundlePayload,
        workbench: Workbench
    ) async {
        defer { isSavingProject = false }
        do {
            let response = try await client.saveProject(
                .init(projectPath: destinationURL.path, sourcePath: sourcePath, payload: payload)
            )
            applySavedProjectResponse(response, selectedWorkbench: workbench)
        } catch {
            if isUserCancellationError(error) {
                return
            }
            setProjectError(error.localizedDescription, for: workbench)
        }
    }

    private func applySavedProjectResponse(_ response: SaveProjectResponse, selectedWorkbench workbench: Workbench) {
        let savedURL = URL(fileURLWithPath: response.projectPath)
        projectURL = savedURL
        if let plotPayload = response.payload.plot {
            plotSession.applyNormalizedProjectState(plotPayload, projectURL: savedURL, scheduleRefresh: false)
        } else {
            plotSession.projectURL = savedURL
        }
        if let dataStudioPayload = response.payload.dataStudio {
            dataStudioSession.projectURL = savedURL
            dataStudioSession.runtimeState.lastSavedProjectSnapshot = dataStudioSession.projectSnapshot(from: dataStudioPayload)
        } else {
            dataStudioSession.projectURL = savedURL
        }
        composerSession.markProjectSaved(response.payload.composer)
        codeConsoleSession.markProjectSaved(response.payload.codeConsole)
        lastSavedProjectSnapshot = currentProjectSnapshot(selectedWorkbench: workbench)
    }

    private func suggestedProjectFilename(for workbench: Workbench) -> String {
        if let projectURL {
            return projectURL.lastPathComponent
        }
        switch workbench {
        case .plot:
            return plotSession.suggestedProjectFilename
        case .dataStudio:
            return dataStudioSession.suggestedProjectFilename
        case .composer:
            return "composer-project.sciplotgod"
        case .codeConsole:
            return "code-console-project.sciplotgod"
        }
    }

    private func firstWorkbenchWithPayload(
        plot: PlotProjectPayload?,
        dataStudio: DataStudioProjectPayload?,
        composer: ComposerProjectPayload?,
        codeConsole: CodeConsoleProjectPayload?
    ) -> Workbench? {
        if plot != nil { return .plot }
        if dataStudio != nil { return .dataStudio }
        if composer != nil { return .composer }
        if codeConsole != nil { return .codeConsole }
        return nil
    }

    private func sidecarWorkbenchID(for workbench: Workbench) -> String {
        switch workbench {
        case .plot:
            return "plot"
        case .dataStudio:
            return "data_studio"
        case .composer:
            return "composer"
        case .codeConsole:
            return "code_console"
        }
    }

    private func workbench(fromSidecarID rawValue: String) -> Workbench {
        switch rawValue {
        case "data_studio", "dataStudio":
            return .dataStudio
        case "composer":
            return .composer
        case "code_console", "codeConsole":
            return .codeConsole
        default:
            return .plot
        }
    }

    private func setProjectError(_ message: String, for workbench: Workbench) {
        switch workbench {
        case .plot:
            plotSession.errorMessage = message
        case .dataStudio:
            dataStudioSession.errorMessage = message
        case .composer:
            composerSession.errorMessage = message
        case .codeConsole:
            codeConsoleSession.errorMessage = message
        }
    }

    func requestOpenWindow(for workbench: Workbench) {
        requestedWorkbenchWindow = workbench
    }

    func consumeRequestedWorkbenchWindow(_ workbench: Workbench) {
        if requestedWorkbenchWindow == workbench {
            requestedWorkbenchWindow = nil
        }
    }
}
