import AppKit
import Foundation

enum WorkspaceBridge {
    static func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
