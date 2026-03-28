import AppKit
import Observation
import QuickLookThumbnailing
import SwiftUI

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

        await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, error in
                Task { @MainActor in
                    if let thumbnail {
                        self?.image = thumbnail.nsImage
                    } else {
                        self?.image = nil
                        self?.errorMessage = error?.localizedDescription ?? "Could not load a thumbnail for this asset."
                    }
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
