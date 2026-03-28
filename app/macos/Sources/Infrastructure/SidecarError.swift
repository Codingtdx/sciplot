import Foundation

enum SidecarError: Error, LocalizedError, Equatable {
    case repoNotFound
    case pythonNotFound(URL)
    case startupFailed(String)
    case incompatibleRoutes([SidecarRouteSignature])
    case httpStatus(Int, String)
    case invalidResponse(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .repoNotFound:
            return "Could not locate the SciPlot God repository root from the native app."
        case let .pythonNotFound(url):
            return "Could not find the repo virtual environment Python at \(url.path)."
        case let .startupFailed(message):
            return "The sidecar failed to start. \(message)"
        case let .incompatibleRoutes(routes):
            let routeText = routes.map(\.displayName).joined(separator: ", ")
            return "The running sidecar is missing required routes: \(routeText)"
        case let .httpStatus(code, detail):
            return "Sidecar request failed with HTTP \(code). \(detail)"
        case let .invalidResponse(message):
            return "The sidecar returned an unexpected response. \(message)"
        case let .transport(message):
            return "Could not communicate with the sidecar. \(message)"
        }
    }
}

struct SidecarRouteSignature: Hashable, Sendable {
    let method: String
    let path: String

    var displayName: String {
        "\(method) \(path)"
    }
}
