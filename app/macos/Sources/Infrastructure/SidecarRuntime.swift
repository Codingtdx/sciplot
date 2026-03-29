import Foundation
import Observation

@MainActor
@Observable
final class SidecarRuntime {
    enum Status: Equatable {
        case idle
        case starting
        case running
        case failed(String)
    }

    let locator: RepoLocator
    let session: URLSession
    let baseURL: URL
    let startupTimeoutNanoseconds: UInt64
    let probeIntervalNanoseconds: UInt64

    var status: Status = .idle
    var logs: [String] = []
    var repoRootURL: URL?

    @ObservationIgnored private var childProcess: Process?
    @ObservationIgnored private let requiredRoutes: Set<SidecarRouteSignature> = [
        .init(method: "GET", path: "/meta"),
        .init(method: "GET", path: "/plot-contract"),
        .init(method: "POST", path: "/inspect-file"),
        .init(method: "POST", path: "/compose-preview"),
        .init(method: "POST", path: "/preprocess-tensile-replicates"),
    ]

    init(
        locator: RepoLocator = RepoLocator(),
        session: URLSession = .shared,
        baseURL: URL = URL(string: "http://127.0.0.1:8765")!,
        startupTimeoutNanoseconds: UInt64 = 15_000_000_000,
        probeIntervalNanoseconds: UInt64 = 250_000_000
    ) {
        self.locator = locator
        self.session = session
        self.baseURL = baseURL
        self.startupTimeoutNanoseconds = startupTimeoutNanoseconds
        self.probeIntervalNanoseconds = probeIntervalNanoseconds
    }

    func ensureRunning() async throws {
        if case .running = status, try await probeCompatibility() {
            return
        }

        status = .starting
        let repoRoot = try locator.locateRepositoryRoot()
        repoRootURL = repoRoot

        if try await probeCompatibility() {
            appendLog("[runtime] Reusing a compatible sidecar at \(baseURL.absoluteString).")
            status = .running
            return
        }

        try await terminateIncompatibleListeners()
        try startSidecarProcess(repoRoot: repoRoot)
        try await waitForCompatibility(timeoutNanoseconds: startupTimeoutNanoseconds)
        status = .running
    }

    private func probeCompatibility() async throws -> Bool {
        do {
            _ = try await fetchHealth()
            let (_, response) = try await session.data(from: baseURL.appendingPathComponent("openapi.json"))
            guard let http = response as? HTTPURLResponse, 200 ..< 300 ~= http.statusCode else {
                return false
            }

            let routes = try await fetchOpenAPIRoutes()
            let missing = requiredRoutes.subtracting(routes)
            return missing.isEmpty
        } catch {
            return false
        }
    }

    private func fetchHealth() async throws -> HealthResponse {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent("health"))
        guard let http = response as? HTTPURLResponse, 200 ..< 300 ~= http.statusCode else {
            throw SidecarError.invalidResponse("The sidecar health probe did not return HTTP 200.")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(HealthResponse.self, from: data)
    }

    private func fetchOpenAPIRoutes() async throws -> Set<SidecarRouteSignature> {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent("openapi.json"))
        guard let http = response as? HTTPURLResponse, 200 ..< 300 ~= http.statusCode else {
            throw SidecarError.invalidResponse("The sidecar openapi probe did not return HTTP 200.")
        }

        guard
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let paths = payload["paths"] as? [String: [String: Any]]
        else {
            throw SidecarError.invalidResponse("The sidecar openapi payload is missing a `paths` object.")
        }

        var routes: Set<SidecarRouteSignature> = []
        for (path, methodPayload) in paths {
            for method in methodPayload.keys {
                routes.insert(.init(method: method.uppercased(), path: path))
            }
        }
        return routes
    }

    private func waitForCompatibility(timeoutNanoseconds: UInt64) async throws {
        let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))

        while ContinuousClock.now < deadline {
            if try await probeCompatibility() {
                appendLog("[runtime] Sidecar ready at \(baseURL.absoluteString).")
                return
            }

            if let childProcess, !childProcess.isRunning {
                throw SidecarError.startupFailed(logs.suffix(20).joined(separator: "\n"))
            }

            try await Task.sleep(nanoseconds: probeIntervalNanoseconds)
        }

        throw SidecarError.startupFailed("Timed out while waiting for the sidecar to expose the required routes.")
    }

    private func startSidecarProcess(repoRoot: URL) throws {
        let pythonURL = repoRoot.appendingPathComponent(".venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            throw SidecarError.pythonNotFound(pythonURL)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = ["-m", "app.sidecar.server"]
        process.currentDirectoryURL = repoRoot
        process.environment = sidecarEnvironment(repoRoot: repoRoot)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        bind(pipe: stdoutPipe, prefix: "[sidecar/stdout]")
        bind(pipe: stderrPipe, prefix: "[sidecar/stderr]")

        do {
            try process.run()
            childProcess = process
            appendLog("[runtime] Started sidecar process with \(pythonURL.path).")
        } catch {
            status = .failed(error.localizedDescription)
            throw SidecarError.startupFailed(error.localizedDescription)
        }
    }

    private func sidecarEnvironment(repoRoot: URL) -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var environment: [String: String] = [:]

        for key in ["HOME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "PATH"] {
            if let value = inherited[key], !value.isEmpty {
                environment[key] = value
            }
        }

        if environment["PATH"] == nil {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }

        environment["PWD"] = repoRoot.path
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }

    private func bind(pipe: Pipe, prefix: String) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            let lines = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map { "\(prefix) \($0)" }

            Task { @MainActor in
                lines.forEach { self?.appendLog($0) }
            }
        }
    }

    private func terminateIncompatibleListeners() async throws {
        let pidOutput = try? await runTool(
            executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-t", "-iTCP:8765", "-sTCP:LISTEN"]
        )

        let pids = (pidOutput ?? "")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !pids.isEmpty else {
            return
        }

        appendLog("[runtime] Replacing incompatible sidecar listener(s): \(pids.joined(separator: ", ")).")

        for pid in pids {
            _ = try? await runTool(executable: URL(fileURLWithPath: "/bin/kill"), arguments: ["-TERM", pid])
        }

        try await Task.sleep(nanoseconds: max(probeIntervalNanoseconds, 500_000_000))

        if try await probeCompatibility() {
            return
        }

        for pid in pids {
            _ = try? await runTool(executable: URL(fileURLWithPath: "/bin/kill"), arguments: ["-KILL", pid])
        }

        try await Task.sleep(nanoseconds: max(probeIntervalNanoseconds, 300_000_000))
    }

    private func runTool(executable: URL, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(decoding: stdoutData, as: UTF8.self)
                let stderr = String(decoding: stderrData, as: UTF8.self)

                if process.terminationStatus == 0 || process.terminationStatus == 1 {
                    continuation.resume(returning: stdout)
                } else {
                    continuation.resume(throwing: SidecarError.transport(stderr))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func appendLog(_ line: String) {
        logs.append(line)
        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }
    }
}
