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
        XCTAssertNil(model.requestedWorkbenchWindow)
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
            options: RenderOptionsPayload(size: "single_panel")
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
        let openAPIData = Data(
            """
            {
              "paths": {
                "/meta": { "get": {} },
                "/plot-contract": { "get": {} },
                "/data-studio/templates": { "get": {} },
                "/source-table-preview": { "post": {} },
                "/data-studio/template-preview": { "post": {} },
                "/data-studio/template-recommendations": { "post": {} },
                "/data-studio/build-workbook": { "post": {} },
                "/inspect-file": { "post": {} },
                "/code-console/context": { "post": {} },
                "/code-console/run": { "post": {} },
                "/compose-preview": { "post": {} }
              }
            }
            """.utf8
        )
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
