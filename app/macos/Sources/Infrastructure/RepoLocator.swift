import Foundation

struct RepoLocator {
    let fileManager: FileManager
    let bundle: Bundle

    init(fileManager: FileManager = .default, bundle: Bundle = .main) {
        self.fileManager = fileManager
        self.bundle = bundle
    }

    func locateRepositoryRoot() throws -> URL {
        let candidates = [
            infoPlistHint(),
            bundleLocation(),
            currentWorkingDirectory(),
        ].compactMap { $0 }

        for candidate in candidates {
            if let verified = verifyRepository(startingAt: candidate) {
                return verified
            }
        }

        throw SidecarError.repoNotFound
    }

    func infoPlistHint() -> URL? {
        guard let hint = bundle.object(forInfoDictionaryKey: "RepoRootHint") as? String else {
            return nil
        }
        return URL(fileURLWithPath: hint, isDirectory: true)
    }

    func bundleLocation() -> URL? {
        bundle.bundleURL
    }

    func currentWorkingDirectory() -> URL? {
        URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    }

    func verifyRepository(startingAt url: URL) -> URL? {
        var candidate = url
        var visitedPaths: Set<String> = []

        if !candidate.hasDirectoryPath {
            candidate.deleteLastPathComponent()
        }

        while true {
            let candidatePath = candidate.standardizedFileURL.path
            guard visitedPaths.insert(candidatePath).inserted else {
                return nil
            }

            let agentsURL = candidate.appendingPathComponent("AGENTS.md", isDirectory: false)
            let pyprojectURL = candidate.appendingPathComponent("pyproject.toml", isDirectory: false)

            if fileManager.fileExists(atPath: agentsURL.path) && fileManager.fileExists(atPath: pyprojectURL.path) {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            if parent.path == candidatePath {
                return nil
            }
            candidate = parent
        }
    }
}
