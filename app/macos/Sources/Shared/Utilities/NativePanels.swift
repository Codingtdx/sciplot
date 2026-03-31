import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

@MainActor
enum NativePanels {
    static func chooseSaveLocation(
        title: String,
        message: String,
        suggestedName: String,
        allowedContentTypes: [UTType],
        prompt: String = "Export"
    ) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.message = message
        panel.prompt = prompt
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = allowedContentTypes
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel.runModal() == .OK ? panel.url : nil
    }

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
        chooseSaveLocation(
            title: "Save Prepared Workbook",
            message: "Choose where the prepared workbook should be written.",
            suggestedName: suggestedName,
            allowedContentTypes: FileTypeCatalog.workbookExport,
            prompt: "Save"
        )
    }
}

@MainActor
enum NativeExportCoordinator {
    static func chooseComposerExportLocation(suggestedName: String) -> URL? {
        NativePanels.chooseSaveLocation(
            title: "Export Composition",
            message: "Choose a destination, file name, and output format for this composition export.",
            suggestedName: suggestedName,
            allowedContentTypes: FileTypeCatalog.composerExport,
            prompt: "Export"
        )
    }

    static func choosePlotExportLocation(suggestedName: String, isMultiOutput: Bool) -> URL? {
        let message: String
        if isMultiOutput {
            message = "This template exports a file group. The name you choose is used as the base stem, and each output appends a deterministic suffix."
        } else {
            message = "Choose where the exported PDF should be written."
        }

        return NativePanels.chooseSaveLocation(
            title: "Export Plot",
            message: message,
            suggestedName: suggestedName,
            allowedContentTypes: [FileTypeCatalog.pdf],
            prompt: "Export"
        )
    }

    static func chooseDirectory(title: String, message: String) -> URL? {
        NativePanels.chooseDirectory(title: title, message: message)
    }

    static func chooseWorkbookSaveLocation(suggestedName: String) -> URL? {
        NativePanels.chooseWorkbookSaveLocation(suggestedName: suggestedName)
    }

    static func materializeComposerExport(intermediatePDFURL: URL, destinationURL: URL) throws {
        guard FileManager.default.fileExists(atPath: intermediatePDFURL.path) else {
            throw NativeExportError.missingIntermediateFile(intermediatePDFURL.path)
        }

        switch composerExportFormat(for: destinationURL) {
        case .pdf:
            try replaceItem(at: destinationURL, withItemAt: intermediatePDFURL)
        case .tiff:
            try writeSinglePageTIFF(
                fromPDFAt: intermediatePDFURL,
                to: destinationURL,
                dpi: 300
            )
        }
    }

    static func materializePlotOutputs(sourceURLs: [URL], destinationURL: URL) throws -> [URL] {
        guard !sourceURLs.isEmpty else {
            throw NativeExportError.noSourceOutputs
        }

        for source in sourceURLs where !FileManager.default.fileExists(atPath: source.path) {
            throw NativeExportError.missingIntermediateFile(source.path)
        }

        if sourceURLs.count == 1 {
            try replaceItem(at: destinationURL, withItemAt: sourceURLs[0])
            return [destinationURL]
        }

        let destinationDirectory = destinationURL.deletingLastPathComponent()
        let baseStem = destinationURL.deletingPathExtension().lastPathComponent
        let normalizedStem = baseStem.isEmpty ? "export" : baseStem
        let suffixes = deterministicSuffixes(from: sourceURLs)
        var finalURLs: [URL] = []

        for (index, source) in sourceURLs.enumerated() {
            let suffix = suffixes[index]
            let sourceExtension = source.pathExtension.isEmpty ? "pdf" : source.pathExtension
            let finalFilename = suffix.isEmpty
                ? "\(normalizedStem).\(sourceExtension)"
                : "\(normalizedStem)_\(suffix).\(sourceExtension)"
            let finalURL = destinationDirectory.appendingPathComponent(finalFilename)
            try replaceItem(at: finalURL, withItemAt: source)
            finalURLs.append(finalURL)
        }

        return finalURLs
    }

    private static func composerExportFormat(for destinationURL: URL) -> ComposerExportFormat {
        let ext = destinationURL.pathExtension.lowercased()
        if ext == "tif" || ext == "tiff" {
            return .tiff
        }
        return .pdf
    }

    private static func replaceItem(at destinationURL: URL, withItemAt sourceURL: URL) throws {
        if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
            return
        }

        let fileManager = FileManager.default
        let directoryURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func writeSinglePageTIFF(fromPDFAt pdfURL: URL, to outputURL: URL, dpi: CGFloat) throws {
        guard let document = PDFDocument(url: pdfURL),
              let page = document.page(at: 0)
        else {
            throw NativeExportError.invalidPDF(pdfURL.path)
        }

        let pageBounds = page.bounds(for: .mediaBox)
        let pixelsWide = max(Int(round(pageBounds.width * dpi / 72.0)), 1)
        let pixelsHigh = max(Int(round(pageBounds.height * dpi / 72.0)), 1)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw NativeExportError.tiffRenderingFailed("Could not create sRGB color space.")
        }

        guard let context = CGContext(
            data: nil,
            width: pixelsWide,
            height: pixelsHigh,
            bitsPerComponent: 8,
            bytesPerRow: pixelsWide * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NativeExportError.tiffRenderingFailed("Could not create TIFF rendering context.")
        }

        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))

        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(pixelsHigh))
        let scale = dpi / 72.0
        context.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        guard let image = context.makeImage() else {
            throw NativeExportError.tiffRenderingFailed("Could not finalize TIFF image buffer.")
        }

        let fileManager = FileManager.default
        let directoryURL = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.tiff.identifier as CFString,
            1,
            nil
        ) else {
            throw NativeExportError.tiffRenderingFailed("Could not create TIFF destination.")
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
            kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFCompression: 1,
            ],
        ]

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw NativeExportError.tiffRenderingFailed("Could not write TIFF file.")
        }
    }

    private static func deterministicSuffixes(from sourceURLs: [URL]) -> [String] {
        let stems = sourceURLs.map { $0.deletingPathExtension().lastPathComponent }
        let commonPrefix = normalizedCommonPrefix(for: stems)
        let separatorCharacters = CharacterSet(charactersIn: "_- ")

        var suffixes = stems.map { stem -> String in
            guard !commonPrefix.isEmpty, stem.hasPrefix(commonPrefix) else {
                return stem
            }
            let rawSuffix = String(stem.dropFirst(commonPrefix.count))
            let trimmed = rawSuffix.trimmingCharacters(in: separatorCharacters)
            return trimmed.isEmpty ? stem : trimmed
        }

        var seen: [String: Int] = [:]
        for index in suffixes.indices {
            let key = suffixes[index]
            if let count = seen[key] {
                let next = count + 1
                seen[key] = next
                suffixes[index] = "\(key)_\(next)"
            } else {
                seen[key] = 1
            }
        }

        return suffixes
    }

    private static func normalizedCommonPrefix(for values: [String]) -> String {
        guard var prefix = values.first, !prefix.isEmpty else {
            return ""
        }

        for value in values.dropFirst() where !prefix.isEmpty {
            while !value.hasPrefix(prefix) && !prefix.isEmpty {
                prefix.removeLast()
            }
        }

        return prefix.trimmingCharacters(in: CharacterSet(charactersIn: "_- "))
    }
}

private enum ComposerExportFormat {
    case pdf
    case tiff
}

private enum NativeExportError: LocalizedError {
    case noSourceOutputs
    case missingIntermediateFile(String)
    case invalidPDF(String)
    case tiffRenderingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSourceOutputs:
            return "No exported files were available to save."
        case let .missingIntermediateFile(path):
            return "Expected export artifact was not found at \(path)."
        case let .invalidPDF(path):
            return "Could not read the exported PDF at \(path)."
        case let .tiffRenderingFailed(message):
            return message
        }
    }
}
