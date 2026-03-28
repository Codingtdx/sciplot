import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum NativePanels {
    static func chooseDirectory(title: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseWorkbookSaveLocation(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Prepared Workbook"
        panel.message = "Choose where the prepared workbook should be written."
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = FileTypeCatalog.workbookExport
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
