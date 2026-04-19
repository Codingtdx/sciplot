import AppKit
import Foundation

enum WorkspaceBridgeError: LocalizedError, Equatable {
    case noTargets
    case missingTarget(String)
    case openFailed(String)

    var errorDescription: String? {
        switch self {
        case .noTargets:
            return "Nothing is available to reveal in Finder yet."
        case let .missingTarget(path):
            let label = URL(fileURLWithPath: path).lastPathComponent
            return "Couldn't find “\(label)” in its last known location."
        case let .openFailed(path):
            let label = URL(fileURLWithPath: path).lastPathComponent
            return "macOS couldn't open “\(label)”."
        }
    }
}

enum WorkspaceBridge {
    static func reveal(_ urls: [URL]) throws {
        guard !urls.isEmpty else {
            throw WorkspaceBridgeError.noTargets
        }
        try ensureTargetsExist(urls)
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func open(_ url: URL) throws {
        try ensureTargetsExist([url])
        guard NSWorkspace.shared.open(url) else {
            throw WorkspaceBridgeError.openFailed(url.path)
        }
    }

    private static func ensureTargetsExist(_ urls: [URL]) throws {
        let fileManager = FileManager.default
        if let missingURL = urls.first(where: { !fileManager.fileExists(atPath: $0.path) }) {
            throw WorkspaceBridgeError.missingTarget(missingURL.path)
        }
    }
}

@MainActor
final class AsyncLatestTaskCoordinator {
    private var revision = 0
    private var task: Task<Void, Never>?

    @discardableResult
    func schedule(
        delayNanoseconds: UInt64 = 0,
        operation: @escaping @MainActor (_ revision: Int) async -> Void
    ) -> Int {
        revision += 1
        let currentRevision = revision
        task?.cancel()
        task = Task { [weak self] in
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    return
                }
            }
            guard let self, !Task.isCancelled, self.revision == currentRevision else {
                return
            }
            await operation(currentRevision)
        }
        return currentRevision
    }

    @discardableResult
    func beginNow() -> Int {
        revision += 1
        task?.cancel()
        task = nil
        return revision
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func isLatest(_ candidate: Int) -> Bool {
        revision == candidate
    }

    func wait() async {
        await task?.value
    }
}

@MainActor
final class KeyedAsyncLatestTaskCoordinator<Key: Hashable> {
    private var revisions: [Key: Int] = [:]
    private var tasks: [Key: Task<Void, Never>] = [:]

    @discardableResult
    func schedule(
        for key: Key,
        delayNanoseconds: UInt64 = 0,
        operation: @escaping @MainActor (_ key: Key, _ revision: Int) async -> Void
    ) -> Int {
        let currentRevision = beginNow(for: key)
        tasks[key] = Task { [weak self] in
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    return
                }
            }
            guard let self, !Task.isCancelled, self.isLatest(for: key, revision: currentRevision) else {
                return
            }
            await operation(key, currentRevision)
        }
        return currentRevision
    }

    @discardableResult
    func beginNow(for key: Key) -> Int {
        let currentRevision = (revisions[key] ?? 0) + 1
        revisions[key] = currentRevision
        tasks[key]?.cancel()
        tasks[key] = nil
        return currentRevision
    }

    func cancel(for key: Key) {
        tasks[key]?.cancel()
        tasks[key] = nil
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
    }

    func isLatest(for key: Key, revision: Int) -> Bool {
        revisions[key] == revision
    }
}
