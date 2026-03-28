import Foundation

struct RepoLocator {
    let fileManager: FileManager = .default
    let bundle: Bundle = .main

    func locateRepositoryRoot() throws -> URL {
        let candidates = [
            infoPlistHint(),
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

    func currentWorkingDirectory() -> URL? {
        URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    }

    func verifyRepository(startingAt url: URL) -> URL? {
        var candidate = url

        if !candidate.hasDirectoryPath {
            candidate.deleteLastPathComponent()
        }

        while true {
            let agentsURL = candidate.appendingPathComponent("AGENTS.md", isDirectory: false)
            let pyprojectURL = candidate.appendingPathComponent("pyproject.toml", isDirectory: false)

            if fileManager.fileExists(atPath: agentsURL.path) && fileManager.fileExists(atPath: pyprojectURL.path) {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }
    }
}
