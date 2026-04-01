import Foundation
import XCTest
@testable import SciPlotGodMac

@MainActor
final class AppModelTests: XCTestCase {
    private var originalWorkingDirectory: String = FileManager.default.currentDirectoryPath

    override func tearDown() {
        FileManager.default.changeCurrentDirectoryPath(originalWorkingDirectory)
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testWorkbenchCommandsRouteToCurrentSession() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

        model.switchWorkbench(.dataStudio)
        model.beginImportForActiveWorkbench()
        XCTAssertEqual(model.selectedWorkbench, .dataStudio)
        XCTAssertTrue(model.dataStudioSession.isImportMenuPresented)

        model.switchWorkbench(.composer)
        model.beginImportForActiveWorkbench()
        XCTAssertTrue(model.composerSession.isImportMenuPresented)
        XCTAssertFalse(model.composerSession.isImportPresented)
    }

    func testOpenInPlotSeedsPlotSessionAndContext() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())
        let workbookURL = URL(fileURLWithPath: "/tmp/prepared.xlsx")

        model.openInPlot(workbookURL: workbookURL, preferredSheet: .name("Representative_Curve"))

        XCTAssertEqual(model.selectedWorkbench, .plot)
        XCTAssertEqual(model.plotSession.selectedFileURL, workbookURL)
        XCTAssertEqual(model.plotSession.selectedSheet, .name("Representative_Curve"))
        XCTAssertEqual(model.codeConsoleSession.boundContext.first?.value, "prepared.xlsx")
    }

    func testOpenInPlotRequestsReplacementWhenPlotAlreadyHasContent() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())
        model.plotSession.handleImportedFile(URL(fileURLWithPath: "/tmp/existing.csv"))

        model.openInPlot(
            workbookURL: URL(fileURLWithPath: "/tmp/prepared.xlsx"),
            preferredSheet: .name("Representative_Curve")
        )

        XCTAssertTrue(model.isPlotReplacementConfirmationPresented)
        XCTAssertEqual(model.plotSession.selectedFileURL?.path, "/tmp/existing.csv")

        model.confirmPendingPlotReplacement()

        XCTAssertFalse(model.isPlotReplacementConfirmationPresented)
        XCTAssertEqual(model.plotSession.selectedFileURL?.path, "/tmp/prepared.xlsx")
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
                "/data-studio/source-preview": { "post": {} },
                "/data-studio/build-workbook": { "post": {} },
                "/inspect-file": { "post": {} },
                "/code-console/context": { "post": {} },
                "/code-console/run": { "post": {} },
                "/compose-preview": { "post": {} },
                "/preprocess-tensile-replicates": { "post": {} }
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
