import Foundation
import XCTest
@testable import SciPlotGodMac

final class SidecarRuntimeTests: XCTestCase {
    private var originalWorkingDirectory: String = FileManager.default.currentDirectoryPath

    override func tearDown() {
        FileManager.default.changeCurrentDirectoryPath(originalWorkingDirectory)
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testRepoLocatorFindsRepositoryRootByWalkingUpward() throws {
        let tempRoot = try makeRepositoryFixture()
        let nested = tempRoot.appendingPathComponent("nested/workbench", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        FileManager.default.changeCurrentDirectoryPath(nested.path)

        let located = try RepoLocator().locateRepositoryRoot()
        XCTAssertEqual(canonicalPath(located), canonicalPath(tempRoot))
    }

    @MainActor
    func testEnsureRunningReusesCompatibleSidecar() async throws {
        let repoRoot = try makeRepositoryFixture()
        FileManager.default.changeCurrentDirectoryPath(repoRoot.path)

        let session = makeStubbedSession { request in
            switch request.url?.lastPathComponent {
            case "health":
                return Self.jsonResponse(
                    request: request,
                    statusCode: 200,
                    body: #"{"status":"ok","version":"5.0.0"}"#
                )
            case "openapi.json":
                return Self.jsonResponse(
                    request: request,
                    statusCode: 200,
                    body: """
                    {
                      "paths": {
                        "/meta": { "get": {} },
                        "/plot-contract": { "get": {} },
                        "/inspect-file": { "post": {} },
                        "/compose-preview": { "post": {} },
                        "/preprocess-tensile-replicates": { "post": {} }
                      }
                    }
                    """
                )
            default:
                throw URLError(.badURL)
            }
        }

        let runtime = SidecarRuntime(
            session: session,
            startupTimeoutNanoseconds: 100_000_000,
            probeIntervalNanoseconds: 10_000_000
        )

        try await runtime.ensureRunning()

        XCTAssertEqual(runtime.status, .running)
        XCTAssertEqual(runtime.repoRootURL.map(canonicalPath), canonicalPath(repoRoot))
        XCTAssertTrue(runtime.logs.contains(where: { $0.contains("Reusing a compatible sidecar") }))
    }

    @MainActor
    func testEnsureRunningFailsWhenSpawnedSidecarNeverBecomesCompatible() async throws {
        let repoRoot = try makeRepositoryFixture(includePythonStub: true)
        FileManager.default.changeCurrentDirectoryPath(repoRoot.path)

        let session = makeStubbedSession { request in
            Self.jsonResponse(request: request, statusCode: 503, body: #"{"detail":"offline"}"#)
        }

        let runtime = SidecarRuntime(
            session: session,
            startupTimeoutNanoseconds: 200_000_000,
            probeIntervalNanoseconds: 20_000_000
        )

        do {
            try await runtime.ensureRunning()
            XCTFail("Expected startup failure")
        } catch {
            guard case SidecarError.startupFailed(_) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
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
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1:8765")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
