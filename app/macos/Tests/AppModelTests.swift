import Foundation
import SwiftUI
import XCTest
@testable import SciPlotGodMac

@MainActor
final class AppModelTests: XCTestCase {
    private let originalWorkingDirectory: String = FileManager.default.currentDirectoryPath

    override func tearDown() {
        FileManager.default.changeCurrentDirectoryPath(originalWorkingDirectory)
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testWorkbenchCommandsRouteToCurrentSession() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

        model.switchWorkbench(.dataStudio)
        model.beginImport(for: .dataStudio)
        XCTAssertEqual(model.selectedWorkbench, .dataStudio)
        XCTAssertEqual(model.dataStudioSession.importFlow, .wizard(step: .kind))

        model.switchWorkbench(.composer)
        model.beginImport(for: .composer)
        XCTAssertTrue(model.composerSession.isImportMenuPresented)
        XCTAssertFalse(model.composerSession.isImportPresented)
    }

    func testWorkbenchWindowIDsAreStableSingletonSceneIDs() {
        XCTAssertEqual(Workbench.plot.windowSceneID, "plot")
        XCTAssertEqual(Workbench.dataStudio.windowSceneID, "data-studio")
        XCTAssertEqual(Workbench.composer.windowSceneID, "composer")
        XCTAssertEqual(Workbench.codeConsole.windowSceneID, "code-console")
    }

    func testLauncherWindowReuseOnlyAcceptsControlledBorderlessWindow() {
        let manager = AppWindowManager()
        let window = NonKeyableLauncherWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 760, height: 460)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "SciPlot God"

        XCTAssertFalse(manager.canReuseLauncherWindow(window))

        let genericKeyableWindow = KeyableLauncherWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 760, height: 460)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        genericKeyableWindow.identifier = NSUserInterfaceItemIdentifier("launcher")

        XCTAssertFalse(manager.canReuseLauncherWindow(genericKeyableWindow))

        let controlledWindow = BorderlessLauncherWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 760, height: 460)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        controlledWindow.identifier = NSUserInterfaceItemIdentifier("launcher")

        XCTAssertTrue(manager.canReuseLauncherWindow(controlledWindow))
    }

    func testLauncherSceneFallbackDoesNotStealFocusFromVisibleWorkbenchWindow() async throws {
        let manager = AppWindowManager()
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())
        closeLauncherWindows()
        let workbenchWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 640, height: 420)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        workbenchWindow.identifier = NSUserInterfaceItemIdentifier(Workbench.plot.windowSceneID)
        workbenchWindow.title = Workbench.plot.title
        workbenchWindow.isReleasedWhenClosed = false
        workbenchWindow.orderFrontRegardless()
        defer {
            workbenchWindow.close()
            closeLauncherWindows()
        }

        manager.openLauncherAfterSceneAttempt(model: model)
        try await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertFalse(
            NSApp.windows.contains { window in
                window.isVisible && (window.identifier?.rawValue == "launcher" || window.title == "SciPlot God")
            },
            "Automatic Launcher fallback should not present over an already visible workbench window."
        )
        XCTAssertTrue(workbenchWindow.isVisible)
    }

    func testLauncherSceneFallbackDoesNotStealFocusWhenWorkbenchAppearsBeforeRetry() async throws {
        let manager = AppWindowManager()
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())
        closeLauncherWindows()

        manager.openLauncherAfterSceneAttempt(model: model, delays: [0.2])

        try await Task.sleep(nanoseconds: 50_000_000)
        let workbenchWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 640, height: 420)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        workbenchWindow.identifier = NSUserInterfaceItemIdentifier(Workbench.plot.windowSceneID)
        workbenchWindow.title = Workbench.plot.title
        workbenchWindow.isReleasedWhenClosed = false
        workbenchWindow.orderFrontRegardless()
        defer {
            workbenchWindow.close()
            closeLauncherWindows()
        }

        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertFalse(
            NSApp.windows.contains { window in
                window.isVisible && (window.identifier?.rawValue == "launcher" || window.title == "SciPlot God")
            },
            "Delayed Launcher fallback should not present after a workbench window becomes visible."
        )
        XCTAssertTrue(workbenchWindow.isVisible)
    }

    func testLauncherSceneFallbackDoesNotReconfigureAlreadyVisibleLauncherWindow() async throws {
        let manager = AppWindowManager()
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())
        closeLauncherWindows()

        let launcherWindow = BorderlessLauncherWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 720, height: 420)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        launcherWindow.identifier = NSUserInterfaceItemIdentifier("launcher")
        launcherWindow.title = "SciPlot God"
        launcherWindow.isReleasedWhenClosed = false
        launcherWindow.orderFrontRegardless()
        defer {
            launcherWindow.close()
            closeLauncherWindows()
        }

        manager.openLauncherAfterSceneAttempt(model: model, delays: [0.05])
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(
            launcherWindow.contentView?.bounds.size ?? .zero,
            CGSize(width: 720, height: 420),
            "Visible reusable Launcher windows should be treated as already managed by the fallback path."
        )
    }

    private func closeLauncherWindows() {
        NSApp.windows
            .filter { $0.identifier?.rawValue == "launcher" || $0.title == "SciPlot God" }
            .forEach { $0.close() }
    }

    func testAppearanceModeStorageAndPreferredColorSchemeMapping() {
        XCTAssertEqual(AppAppearanceMode.storageKey, "appAppearanceMode")
        XCTAssertEqual(AppAppearanceMode.allCases.map(\.rawValue), ["system", "light", "dark"])
        XCTAssertNil(AppAppearanceMode.system.preferredColorScheme)
        XCTAssertEqual(AppAppearanceMode.light.preferredColorScheme, .light)
        XCTAssertEqual(AppAppearanceMode.dark.preferredColorScheme, .dark)
        XCTAssertEqual(AppAppearanceMode.system.effectiveColorScheme(system: .dark), .dark)
        XCTAssertEqual(AppAppearanceMode.light.effectiveColorScheme(system: .dark), .light)
        XCTAssertEqual(AppAppearanceMode.dark.effectiveColorScheme(system: .light), .dark)
        XCTAssertEqual(AppAppearanceMode.storedValue(from: "unexpected"), .system)
    }

    func testExplicitWorkbenchActionsDoNotNeedVisibleWorkbenchSwitching() async {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

        model.switchWorkbench(.plot)
        model.beginImport(for: .dataStudio)
        XCTAssertEqual(model.selectedWorkbench, .plot)
        XCTAssertEqual(model.dataStudioSession.importFlow, .wizard(step: .kind))

        model.beginImport(for: .codeConsole)
        XCTAssertEqual(model.selectedWorkbench, .plot)
        XCTAssertTrue(model.codeConsoleSession.isImporterPresented)

        await model.saveProject(for: .composer)
        XCTAssertEqual(model.selectedWorkbench, .plot)
    }

    func testLauncherRowsOnlyRequestModuleWindows() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

        XCTAssertNil(model.requestedWorkbenchWindow)

        model.enterWorkbench(.composer)
        XCTAssertEqual(model.requestedWorkbenchWindow, .composer)

        model.showLauncher()
        model.enterWorkbench(.plot)
        XCTAssertEqual(model.requestedWorkbenchWindow, .plot)
        XCTAssertFalse(model.plotSession.isImporterPresented)

        model.showLauncher()
        model.enterWorkbench(.dataStudio)
        XCTAssertEqual(model.requestedWorkbenchWindow, .dataStudio)
        XCTAssertEqual(model.dataStudioSession.importFlow, .idle)

        model.showLauncher()
        model.enterWorkbench(.composer)
        XCTAssertEqual(model.requestedWorkbenchWindow, .composer)
        XCTAssertFalse(model.composerSession.isImportMenuPresented)

        model.showLauncher()
        model.enterWorkbench(.codeConsole)
        XCTAssertEqual(model.requestedWorkbenchWindow, .codeConsole)
        XCTAssertFalse(model.codeConsoleSession.isImporterPresented)
    }

    func testNewProjectClearsPlotStateAndRequestsLauncher() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())
        model.plotSession.importFile(URL(fileURLWithPath: "/tmp/existing.csv"))
        model.plotSession.chooseTemplate("curve")
        model.plotSession.isDataWorkbookPresented = true
        model.plotSession.errorMessage = "Old error"
        model.plotSession.selectedPlotAdjustmentCategory = .legend
        model.dataStudioSession.workbooks = [
            DataStudioWorkbookItem(
                id: "workbook-1",
                response: TestPayloads.dataStudioWorkbook(path: "/tmp/prepared.xlsx", label: "Prepared")
            ),
        ]
        model.composerSession.project = TestPayloads.composerProject()
        model.codeConsoleSession.editorText = "print('keep me until reset')"
        model.codeConsoleSession.latestRunResponse = TestPayloads.codeConsoleRun()

        model.openInPlot(
            inputURL: URL(fileURLWithPath: "/tmp/prepared.xlsx"),
            sheet: .name("Representative_Curve"),
            templateID: "curve",
            options: RenderOptionsPayload()
        )
        XCTAssertTrue(model.isPlotReplacementConfirmationPresented)

        model.newProject()

        XCTAssertFalse(model.isPlotReplacementConfirmationPresented)
        XCTAssertNil(model.plotSession.selectedFileURL)
        XCTAssertNil(model.plotSession.selectedTemplateID)
        XCTAssertFalse(model.plotSession.isDataWorkbookPresented)
        XCTAssertNil(model.plotSession.errorMessage)
        XCTAssertEqual(model.plotSession.selectedPlotAdjustmentCategory, .figure)
        XCTAssertTrue(model.dataStudioSession.workbooks.isEmpty)
        XCTAssertTrue(model.composerSession.project.panels.isEmpty)
        XCTAssertTrue(model.codeConsoleSession.editorText.isEmpty)
        XCTAssertNil(model.codeConsoleSession.latestRunResponse)
        XCTAssertNil(model.requestedWorkbenchWindow)
    }

    func testProjectSaveAvailabilityUsesAnyDurableModuleContent() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

        XCTAssertFalse(model.saveProjectAvailability(for: .codeConsole).isEnabled)

        model.composerSession.project = TestPayloads.composerProject()

        XCTAssertTrue(model.saveProjectAvailability(for: .plot).isEnabled)
        XCTAssertTrue(model.saveProjectAvailability(for: .codeConsole).isEnabled)
    }

    func testAppModelSavesAggregateComposerAndCodeConsoleProjectPayload() async {
        let client = MockSidecarClient()
        let destinationURL = URL(fileURLWithPath: "/tmp/four-module.sciplotgod")
        let model = AppModel(
            runtime: SidecarRuntime(),
            client: client,
            chooseProjectSaveLocation: { _ in destinationURL }
        )
        model.composerSession.project = TestPayloads.composerProject()
        model.codeConsoleSession.importFile(URL(fileURLWithPath: "/tmp/manual.csv"))
        model.codeConsoleSession.editorText = "print('saved editor')"
        model.codeConsoleSession.latestRunResponse = TestPayloads.codeConsoleRun()
        client.saveProjectHandler = { request in
            SaveProjectResponse(projectPath: request.projectPath, payload: request.payload)
        }

        await model.saveProjectAs(for: .codeConsole)

        XCTAssertEqual(client.saveProjectRequests.count, 1)
        let request = client.saveProjectRequests[0]
        XCTAssertEqual(request.projectPath, destinationURL.path)
        XCTAssertNil(request.sourcePath)
        XCTAssertEqual(request.payload.version, 2)
        XCTAssertEqual(request.payload.selectedWorkbench, "code_console")
        XCTAssertEqual(request.payload.composer?.project.panels.first?.filePath, "/tmp/panel.pdf")
        XCTAssertEqual(request.payload.codeConsole?.manualBinding?.originalSourcePath, "/tmp/manual.csv")
        XCTAssertEqual(request.payload.codeConsole?.editorText, "print('saved editor')")
        XCTAssertEqual(request.payload.codeConsole?.latestRun?.generatedFiles.first?.path, "/tmp/code_console/run-1/outputs/sample.pdf")
        XCTAssertEqual(model.projectURL, destinationURL)
        XCTAssertFalse(model.isProjectDirty)
    }

    func testOpenProjectRestoresComposerAndCodeConsoleAndFocusesSavedWorkbench() async throws {
        let client = MockSidecarClient()
        let model = AppModel(runtime: SidecarRuntime(), client: client)
        var composerProject = TestPayloads.composerProject()
        composerProject.panels[0].filePath = "/tmp/restored/panel.pdf"
        let manualBinding = CodeConsoleProjectManualBindingPayload(
            sourceFilename: "manual.csv",
            embeddedSourceRelpath: "sources/code_console/manual/manual.csv",
            sourceSHA256: "abc123",
            originalSourcePath: "/tmp/restored/manual.csv",
            savedSourceMtimeNs: 123,
            sheet: .name("Manual"),
            templateID: "curve",
            renderOptions: RenderOptionsPayload(size: "60x55"),
            title: "Restored manual"
        )
        let runSnapshot = CodeConsoleRunSnapshotPayload(
            status: "succeeded",
            exitCode: 0,
            durationSeconds: 0.5,
            stdout: "ok",
            stderr: "",
            runDir: "/tmp/restored/run",
            outputDir: "/tmp/restored/run/outputs",
            scriptPath: "/tmp/restored/run/user_code.py",
            promptPath: "/tmp/restored/run/prompt.txt",
            contextPath: "/tmp/restored/run/context.json",
            stdoutPath: "/tmp/restored/run/stdout.txt",
            stderrPath: "/tmp/restored/run/stderr.txt",
            generatedFiles: [
                .init(path: "/tmp/restored/run/outputs/figure.pdf", name: "figure.pdf", fileType: "pdf", sizeBytes: 2048),
            ]
        )
        client.openProjectResponse = OpenProjectResponse(
            projectPath: "/tmp/restored.sciplotgod",
            restoredSourcePath: nil,
            restoredWorkbookPaths: [],
            payload: ProjectBundlePayload(
                version: 2,
                selectedWorkbench: "code_console",
                plot: nil,
                dataStudio: nil,
                composer: ComposerProjectPayload(
                    sessionKind: "composer",
                    version: 2,
                    project: composerProject,
                    embeddedPanels: [],
                    projectDisplayName: "restored"
                ),
                codeConsole: CodeConsoleProjectPayload(
                    sessionKind: "code_console",
                    version: 2,
                    selectedSourceKind: "imported_file",
                    selectedSheet: .name("Manual"),
                    editorText: "print('restored editor')",
                    promptText: "saved prompt",
                    starterCode: "saved starter",
                    manualBinding: manualBinding,
                    latestRun: runSnapshot,
                    embeddedGeneratedFiles: [],
                    selectedGeneratedFilePath: "/tmp/restored/run/outputs/figure.pdf",
                    projectDisplayName: "restored"
                ),
                artifacts: ["manifest_relpath": .string("artifacts/manifest.json")]
            )
        )
        client.codeConsoleContextHandler = { request in
            let base = TestPayloads.codeConsoleContext(path: request.inputPath)
            return CodeConsoleContextResponse(
                contextID: "ctx_restored",
                inputPath: request.inputPath,
                sheet: request.sheet,
                sheetNames: base.sheetNames,
                inspection: base.inspection,
                dataset: base.dataset,
                template: request.template ?? base.template,
                options: request.options,
                promptText: "refreshed prompt",
                starterCode: "refreshed starter",
                sourceKind: request.sourceKind,
                sourceLabel: request.sourceLabel
            )
        }

        await model.openProjectDocument(URL(fileURLWithPath: "/tmp/restored.sciplotgod"))
        try? await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertEqual(model.selectedWorkbench, .codeConsole)
        XCTAssertEqual(model.requestedWorkbenchWindow, .codeConsole)
        XCTAssertEqual(model.composerSession.project.panels.first?.filePath, "/tmp/restored/panel.pdf")
        XCTAssertEqual(model.codeConsoleSession.selectedFileURL?.path, "/tmp/restored/manual.csv")
        XCTAssertEqual(model.codeConsoleSession.selectedSheet, .name("Manual"))
        XCTAssertEqual(model.codeConsoleSession.editorText, "print('restored editor')")
        XCTAssertEqual(model.codeConsoleSession.latestRunResponse?.generatedFiles.first?.path, "/tmp/restored/run/outputs/figure.pdf")
        XCTAssertFalse(model.isProjectDirty)
    }

    func testPlotDataWorkbookToolbarActionOpensSourceDataTab() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

        model.plotSession.dataWorkbookTab = .fit
        model.showPlotDataWorkbook()

        XCTAssertTrue(model.plotSession.isDataWorkbookPresented)
        XCTAssertEqual(model.plotSession.dataWorkbookTab, .sourceData)
    }

    func testShowHelpForActiveWorkbenchPresentsQuickHelp() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

        model.switchWorkbench(.composer)
        model.showHelpForActiveWorkbench()

        XCTAssertTrue(model.isQuickHelpPresented)
        XCTAssertEqual(model.quickHelpWorkbench, .composer)

        model.dismissQuickHelp()

        XCTAssertFalse(model.isQuickHelpPresented)
        XCTAssertNil(model.quickHelpWorkbench)
    }

    func testDataStudioImportTransitionsFromWizardToFileImporter() async {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

        model.switchWorkbench(.dataStudio)
        model.beginImport(for: .dataStudio)
        XCTAssertEqual(model.dataStudioSession.importFlow, .wizard(step: .kind))

        model.dataStudioSession.chooseImportKind(.rawFiles)
        XCTAssertEqual(model.dataStudioSession.importFlow, .idle)

        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(model.dataStudioSession.importFlow, .importer(kind: .rawFiles))
    }

    func testOpenInPlotSeedsPlotSessionAndContext() async {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())
        let workbookURL = URL(fileURLWithPath: "/tmp/prepared.xlsx")

        model.openInPlot(
            inputURL: workbookURL,
            sheet: .name("Representative_Curve"),
            templateID: "curve",
            options: RenderOptionsPayload(size: "60x55")
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(model.selectedWorkbench, .plot)
        XCTAssertEqual(model.requestedWorkbenchWindow, .plot)
        XCTAssertEqual(model.plotSession.selectedFileURL, workbookURL)
        XCTAssertEqual(model.plotSession.selectedSheet, .name("Representative_Curve"))
        XCTAssertEqual(model.codeConsoleSession.boundContext.first?.value, "prepared.xlsx")
    }

    func testOpenInPlotRequestsReplacementWhenPlotAlreadyHasContent() async {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())
        model.plotSession.importFile(URL(fileURLWithPath: "/tmp/existing.csv"))

        model.openInPlot(
            inputURL: URL(fileURLWithPath: "/tmp/prepared.xlsx"),
            sheet: .name("Representative_Curve"),
            templateID: "curve",
            options: RenderOptionsPayload()
        )

        XCTAssertTrue(model.isPlotReplacementConfirmationPresented)
        XCTAssertEqual(model.plotSession.selectedFileURL?.path, "/tmp/existing.csv")

        model.confirmPendingPlotReplacement()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertFalse(model.isPlotReplacementConfirmationPresented)
        XCTAssertEqual(model.plotSession.selectedFileURL?.path, "/tmp/prepared.xlsx")
    }

    func testOpenPlotDocumentRequestsPlotScopedReplacementForProjectFiles() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())
        model.plotSession.importFile(URL(fileURLWithPath: "/tmp/existing.csv"))

        model.openPlotDocument(URL(fileURLWithPath: "/tmp/next.sciplotgod"))

        XCTAssertEqual(model.selectedWorkbench, .plot)
        XCTAssertEqual(model.requestedWorkbenchWindow, .plot)
        XCTAssertTrue(model.isPlotReplacementConfirmationPresented)
        XCTAssertEqual(model.plotSession.selectedFileURL?.path, "/tmp/existing.csv")
    }

    func testActiveExportAvailabilityTracksSelectedWorkbench() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

        model.switchWorkbench(.plot)
        XCTAssertFalse(model.activeExportAvailability.isEnabled)
        XCTAssertTrue(model.activeExportAvailability.reason?.contains("Import a source file") ?? false)

        model.switchWorkbench(.dataStudio)
        XCTAssertFalse(model.activeExportAvailability.isEnabled)
        XCTAssertTrue(model.activeExportAvailability.reason?.contains("Import workbook groups") ?? false)

        model.switchWorkbench(.composer)
        XCTAssertFalse(model.activeExportAvailability.isEnabled)
        XCTAssertTrue(model.activeExportAvailability.reason?.contains("Import at least one panel") ?? false)

        model.switchWorkbench(.codeConsole)
        XCTAssertFalse(model.activeExportAvailability.isEnabled)
        XCTAssertTrue(model.activeExportAvailability.reason?.contains("Run code to generate PDF figures") ?? false)
    }

    func testActiveExportCopyTracksSelectedWorkbench() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

        model.switchWorkbench(.plot)
        XCTAssertEqual(model.activeExportCommandTitle, "Export Plot")
        XCTAssertTrue(model.activeExportHelpText.contains("Import a source file"))

        model.switchWorkbench(.dataStudio)
        XCTAssertEqual(model.activeExportCommandTitle, "Export Bundle")
        XCTAssertTrue(model.activeExportHelpText.contains("Import workbook groups"))

        model.switchWorkbench(.composer)
        XCTAssertEqual(model.activeExportCommandTitle, "Export Composition")
        XCTAssertTrue(model.activeExportHelpText.contains("Import at least one panel"))

        model.switchWorkbench(.codeConsole)
        XCTAssertEqual(model.activeExportCommandTitle, "Export Figures")
        XCTAssertTrue(model.activeExportHelpText.contains("Run code to generate PDF figures"))
    }

    func testActiveRevealAvailabilityTracksSelectedWorkbench() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

        model.switchWorkbench(.plot)
        XCTAssertFalse(model.activeRevealAvailability.isEnabled)
        XCTAssertTrue(model.activeRevealAvailability.reason?.contains("Export a plot first") ?? false)

        let workbook = DataStudioWorkbookItem(
            id: "workbook-1",
            response: TestPayloads.dataStudioWorkbook(path: "/tmp/prepared.xlsx", label: "Prepared")
        )
        model.dataStudioSession.workbooks = [workbook]
        model.dataStudioSession.groupStates = [
            .init(workbookPath: workbook.response.workbookPath, displayName: "Prepared", includeInCompare: true, sortOrder: 0),
        ]
        model.dataStudioSession.focusedWorkbookPath = workbook.response.workbookPath
        model.switchWorkbench(.dataStudio)
        XCTAssertTrue(model.activeRevealAvailability.isEnabled)

        model.composerSession.exportURL = URL(fileURLWithPath: "/tmp/composer-final.pdf")
        model.switchWorkbench(.composer)
        XCTAssertTrue(model.activeRevealAvailability.isEnabled)

        model.codeConsoleSession.latestRunResponse = TestPayloads.codeConsoleRun()
        model.switchWorkbench(.codeConsole)
        XCTAssertTrue(model.activeRevealAvailability.isEnabled)
    }

    func testRuntimeIssueMessageUsesBootstrapError() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

        XCTAssertNil(model.runtimeIssueMessage)

        model.bootstrapErrorMessage = "Sidecar failed to start."
        XCTAssertEqual(model.runtimeIssueMessage?.summary, "Runtime unavailable")
        XCTAssertEqual(model.runtimeIssueMessage?.detail, "Sidecar failed to start.")
    }

    func testRuntimeIssueMessageIncludesRecentRuntimeLogsWhenAvailable() {
        let runtime = SidecarRuntime()
        runtime.logs = [
            "[runtime] Started sidecar process",
            "[runtime] Compatibility probe failed [payload.meta.decode]: bad payload",
        ]
        let model = AppModel(runtime: runtime, client: MockSidecarClient())

        model.bootstrapErrorMessage = "The sidecar failed to start."

        let detail = model.runtimeIssueMessage?.detail ?? ""
        XCTAssertTrue(detail.contains("The sidecar failed to start."))
        XCTAssertTrue(detail.contains("Recent runtime logs:"))
        XCTAssertTrue(detail.contains("payload.meta.decode"))
    }

    func testBootstrapCancellationDoesNotSurfaceRuntimeIssue() async throws {
        let fixture = try makeRuntimeFixture()
        let client = MockSidecarClient()
        client.metaHandler = {
            throw CancellationError()
        }
        client.plotContractHandler = {
            TestPayloads.contract()
        }
        let model = AppModel(runtime: fixture.runtime, client: client)

        await model.bootstrapIfNeeded()

        XCTAssertNil(model.bootstrapErrorMessage)
        XCTAssertFalse(model.hasBootstrapped)
    }

    func testBootstrapAndPlotImportInspectTemplateFlowWithSidecarClient() async throws {
        let fixture = try makeRuntimeFixture()
        let model = AppModel(runtime: fixture.runtime, client: fixture.client)

        await model.bootstrapIfNeeded()

        XCTAssertTrue(model.hasBootstrapped)
        XCTAssertNil(model.bootstrapErrorMessage)
        XCTAssertNotNil(model.plotSession.metadata)
        XCTAssertNotNil(model.plotSession.contract)
        XCTAssertEqual(model.plotSession.renderOptions.stylePreset, model.plotSession.metadata?.defaults.stylePreset)
        XCTAssertEqual(model.plotSession.renderOptions.palettePreset, model.plotSession.metadata?.defaults.palettePreset)
        XCTAssertFalse(model.plotSession.templateGalleryItems.isEmpty)
        XCTAssertTrue(model.plotSession.templateGalleryItems.allSatisfy { !$0.selectable })
        XCTAssertGreaterThanOrEqual(fixture.requestCounter.count(for: "/meta"), 1)
        XCTAssertGreaterThanOrEqual(fixture.requestCounter.count(for: "/plot-contract"), 1)

        await model.plotSession.importFileAndInspect(URL(fileURLWithPath: "/tmp/runtime-chain.csv"))

        XCTAssertEqual(model.plotSession.selectedSourcePath, "/tmp/runtime-chain.csv")
        XCTAssertNotNil(model.plotSession.inspectionResponse)
        XCTAssertEqual(fixture.requestCounter.count(for: "/inspect-file"), 1)
        XCTAssertFalse(model.plotSession.compatibleRecommendations.isEmpty)
        XCTAssertFalse(model.plotSession.templateGalleryItems.isEmpty)
        XCTAssertTrue(model.plotSession.templateGalleryItems.allSatisfy(\.selectable))
    }

    private func makeRuntimeFixture() throws -> (
        runtime: SidecarRuntime,
        client: SidecarClient,
        requestCounter: RequestCounter
    ) {
        let repoRoot = try makeRepositoryFixture(includePythonStub: true)
        let bundleURL = try makeAppBundleFixture(
            at: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("SciPlot God.app", isDirectory: true),
            infoValues: ["RepoRootHint": repoRoot.path]
        )
        guard let bundle = Bundle(url: bundleURL) else {
            throw XCTestError(.failureWhileWaiting)
        }
        FileManager.default.changeCurrentDirectoryPath(repoRoot.path)

        let requestCounter = RequestCounter()
        let healthData = Data(#"{"status":"ok","version":"5.0.0"}"#.utf8)
        let openAPIData = TestPayloads.compatibleOpenAPIData()
        let metaData = try encodeJSON(TestPayloads.meta())
        let contractData = try encodeJSON(TestPayloads.contract())
        let inspectData = try encodeJSON(TestPayloads.inspectFile(path: "/tmp/runtime-chain.csv"))

        let session = makeStubbedSession { request in
            let path = request.url?.path ?? ""
            requestCounter.record(path: path)

            switch path {
            case "/health":
                return Self.jsonResponse(request: request, statusCode: 200, body: healthData)
            case "/openapi.json":
                return Self.jsonResponse(request: request, statusCode: 200, body: openAPIData)
            case "/meta":
                return Self.jsonResponse(request: request, statusCode: 200, body: metaData)
            case "/plot-contract":
                return Self.jsonResponse(request: request, statusCode: 200, body: contractData)
            case "/inspect-file":
                return Self.jsonResponse(request: request, statusCode: 200, body: inspectData)
            default:
                return Self.jsonResponse(
                    request: request,
                    statusCode: 404,
                    body: Data(#"{"detail":"not found"}"#.utf8)
                )
            }
        }

        let runtime = SidecarRuntime(
            locator: RepoLocator(fileManager: .default, bundle: bundle),
            session: session,
            startupTimeoutNanoseconds: 200_000_000,
            probeIntervalNanoseconds: 20_000_000
        )
        let client = SidecarClient(runtime: runtime, session: session)
        return (runtime, client, requestCounter)
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(value)
    }

    private func makeRepositoryFixture(includePythonStub: Bool = false) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("AGENTS.md"))
        try Data().write(to: root.appendingPathComponent("pyproject.toml"))

        if includePythonStub {
            let binDir = root.appendingPathComponent(".venv/bin", isDirectory: true)
            try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
            let pythonURL = binDir.appendingPathComponent("python", isDirectory: false)
            try "#!/bin/sh\nexit 0\n".write(to: pythonURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonURL.path
            )
        }

        return root
    }

    private func makeAppBundleFixture(
        at bundleURL: URL,
        infoValues: [String: String]
    ) throws -> URL {
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)

        let executableURL = macOS.appendingPathComponent("SciPlot God", isDirectory: false)
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        var info: [String: String] = [
            "CFBundleExecutable": "SciPlot God",
            "CFBundleIdentifier": "com.codegod.desktop.tests.fixture",
            "CFBundleName": "SciPlot God",
            "CFBundlePackageType": "APPL",
        ]
        info.merge(infoValues) { _, new in new }

        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contents.appendingPathComponent("Info.plist", isDirectory: false))

        return bundleURL
    }

    private func makeStubbedSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func jsonResponse(
        request: URLRequest,
        statusCode: Int,
        body: Data
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1:8765")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, body)
    }
}

private final class NonKeyableLauncherWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class KeyableLauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class RequestCounter {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func record(path: String) {
        lock.lock()
        counts[path, default: 0] += 1
        lock.unlock()
    }

    func count(for path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[path, default: 0]
    }
}
