import Foundation

func isUserCancellationError(_ error: Error) -> Bool {
    if error is CancellationError {
        return true
    }
    if let urlError = error as? URLError, urlError.code == .cancelled {
        return true
    }
    if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
        return true
    }
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
        return true
    }
    if nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue {
        return true
    }
    return false
}
