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
    let runningHealthProbeCacheNanoseconds: UInt64

    var status: Status = .idle
    var logs: [String] = []
    var repoRootURL: URL?

    @ObservationIgnored private var childProcess: Process?
    @ObservationIgnored private var lastCompatibilityFailure: String?
    @ObservationIgnored private var lastHealthProbeAt: ContinuousClock.Instant?
    @ObservationIgnored private let requiredRoutes: Set<SidecarRouteSignature> = [
        .init(method: "GET", path: "/meta"),
        .init(method: "GET", path: "/plot-contract"),
        .init(method: "POST", path: "/inspect-file"),
        .init(method: "POST", path: "/code-console/context"),
        .init(method: "POST", path: "/code-console/run"),
        .init(method: "POST", path: "/compose-preview"),
        .init(method: "GET", path: "/data-studio/templates"),
        .init(method: "POST", path: "/source-table-preview"),
        .init(method: "POST", path: "/data-studio/template-preview"),
        .init(method: "POST", path: "/data-studio/build-workbook"),
    ]

    init(
        locator: RepoLocator = RepoLocator(),
        session: URLSession = .shared,
        baseURL: URL = URL(string: "http://127.0.0.1:8765")!,
        startupTimeoutNanoseconds: UInt64 = 15_000_000_000,
        probeIntervalNanoseconds: UInt64 = 250_000_000,
        runningHealthProbeCacheNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.locator = locator
        self.session = session
        self.baseURL = baseURL
        self.startupTimeoutNanoseconds = startupTimeoutNanoseconds
        self.probeIntervalNanoseconds = probeIntervalNanoseconds
        self.runningHealthProbeCacheNanoseconds = runningHealthProbeCacheNanoseconds
    }

    func ensureRunning() async throws {
        if case .running = status {
            if hasFreshHealthProbeCache {
                return
            }
            if await probeHealthOnly() {
                return
            }
            if try await probeCompatibility() {
                return
            }
            appendLog("[runtime] Active sidecar failed compatibility checks; restarting managed sidecar.")
        }

        status = .starting
        let repoRoot = try locator.locateRepositoryRoot()
        repoRootURL = repoRoot

        try await terminateIncompatibleListeners()
        try startSidecarProcess(repoRoot: repoRoot)
        try await waitForCompatibility(timeoutNanoseconds: startupTimeoutNanoseconds)
        status = .running
        markCompatibilitySuccess()
    }

    private func probeCompatibility() async throws -> Bool {
        do {
            _ = try await fetchHealth()
            let routes = try await fetchOpenAPIRoutes()
            let missing = requiredRoutes.subtracting(routes)
            guard missing.isEmpty else {
                let missingText = missing
                    .map { "\($0.method) \($0.path)" }
                    .sorted()
                    .joined(separator: ", ")
                reportCompatibilityFailure("Missing required routes: \(missingText).")
                return false
            }

            let payloadCompatible = try await probePayloadCompatibility()
            if payloadCompatible {
                markCompatibilitySuccess()
            }
            return payloadCompatible
        } catch {
            reportCompatibilityFailure(error.localizedDescription)
            return false
        }
    }

    private func probeHealthOnly() async -> Bool {
        do {
            _ = try await fetchHealth()
            lastHealthProbeAt = .now
            lastCompatibilityFailure = nil
            return true
        } catch {
            reportCompatibilityFailure(error.localizedDescription)
            return false
        }
    }

    private var hasFreshHealthProbeCache: Bool {
        guard let lastHealthProbeAt else {
            return false
        }
        let ttl = Duration.nanoseconds(Int(runningHealthProbeCacheNanoseconds))
        return ContinuousClock.now < (lastHealthProbeAt + ttl)
    }

    private func markCompatibilitySuccess() {
        let now = ContinuousClock.now
        lastHealthProbeAt = now
        lastCompatibilityFailure = nil
    }

    private func probePayloadCompatibility() async throws -> Bool {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let (metaData, metaResponse) = try await session.data(from: baseURL.appendingPathComponent("meta"))
            guard let metaHTTP = metaResponse as? HTTPURLResponse, 200 ..< 300 ~= metaHTTP.statusCode else {
                reportCompatibilityFailure("/meta returned a non-2xx status.")
                return false
            }
            let meta: SidecarMetaResponse
            do {
                meta = try decoder.decode(SidecarMetaResponse.self, from: metaData)
            } catch {
                reportCompatibilityFailure("/meta decode failed: \(error.localizedDescription)")
                return false
            }
            guard !meta.templates.isEmpty else {
                reportCompatibilityFailure("/meta contains no templates.")
                return false
            }

            let (contractData, contractResponse) = try await session.data(from: baseURL.appendingPathComponent("plot-contract"))
            guard let contractHTTP = contractResponse as? HTTPURLResponse, 200 ..< 300 ~= contractHTTP.statusCode else {
                reportCompatibilityFailure("/plot-contract returned a non-2xx status.")
                return false
            }
            let contract: PlotContractResponse
            do {
                contract = try decoder.decode(PlotContractResponse.self, from: contractData)
            } catch {
                reportCompatibilityFailure("/plot-contract decode failed: \(error.localizedDescription)")
                return false
            }
            guard !contract.templates.isEmpty else {
                reportCompatibilityFailure("/plot-contract contains no templates.")
                return false
            }

            return true
        } catch {
            reportCompatibilityFailure(error.localizedDescription)
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

        let detail = lastCompatibilityFailure ?? "No additional probe detail captured."
        throw SidecarError.startupFailed("Timed out waiting for compatible sidecar payloads. Last probe failure: \(detail)")
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

    private func reportCompatibilityFailure(_ reason: String) {
        guard lastCompatibilityFailure != reason else {
            return
        }
        lastCompatibilityFailure = reason
        appendLog("[runtime] Compatibility probe failed: \(reason)")
    }
}
