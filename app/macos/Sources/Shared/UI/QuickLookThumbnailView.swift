import AppKit
import Observation
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class QuickLookThumbnailModel {
    var image: NSImage?
    var errorMessage: String?

    func load(url: URL, size: CGSize) async {
        errorMessage = nil

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.saveBestRepresentation(for: request, to: temporaryURL, as: .png) { [weak self] error in
                let loadedImage = NSImage(contentsOf: temporaryURL)
                let message = error?.localizedDescription ?? "Could not load a thumbnail for this asset."
                Task { @MainActor in
                    if let loadedImage {
                        self?.image = loadedImage
                        self?.errorMessage = nil
                    } else {
                        self?.image = nil
                        self?.errorMessage = message
                    }
                    try? FileManager.default.removeItem(at: temporaryURL)
                    continuation.resume()
                }
            }
        }
    }
}

struct QuickLookThumbnailView: View {
    let url: URL
    var size: CGFloat = 240

    @State private var model = QuickLookThumbnailModel()

    var body: some View {
        Group {
            if let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else if let errorMessage = model.errorMessage {
                EmptyStateCard(title: "Thumbnail unavailable", message: errorMessage)
            } else {
                BusyStateCard(title: "Loading thumbnail", message: "Quick Look is generating a preview.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quinary.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
        .task(id: url) {
            await model.load(url: url, size: CGSize(width: size, height: size))
        }
    }
}
