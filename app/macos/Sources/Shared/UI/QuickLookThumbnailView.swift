import AppKit
import Observation
import QuickLookThumbnailing
import SwiftUI

struct QuickLookThumbnailLoadResult {
    let image: NSImage?
    let errorMessage: String?
}

@MainActor
@Observable
final class QuickLookThumbnailModel {
    typealias Loader = @Sendable (_ url: URL, _ size: CGSize) async -> QuickLookThumbnailLoadResult

    var image: NSImage?
    var errorMessage: String?
    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private var activeRequestID = UUID()

    init(loader: @escaping Loader = QuickLookThumbnailModel.defaultLoader) {
        self.loader = loader
    }

    func load(url: URL, size: CGSize) async {
        let requestID = UUID()
        activeRequestID = requestID
        image = nil
        errorMessage = nil

        let result = await loader(url, size)
        guard activeRequestID == requestID else {
            return
        }
        image = result.image
        errorMessage = result.image == nil
            ? (result.errorMessage ?? "Could not load a thumbnail for this asset.")
            : nil
    }

    private static func defaultLoader(url: URL, size: CGSize) async -> QuickLookThumbnailLoadResult {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.saveBestRepresentation(for: request, to: temporaryURL, as: .png) { error in
                let loadedImage = NSImage(contentsOf: temporaryURL)
                let message = error?.localizedDescription ?? "Could not load a thumbnail for this asset."
                try? FileManager.default.removeItem(at: temporaryURL)
                continuation.resume(
                    returning: QuickLookThumbnailLoadResult(
                        image: loadedImage,
                        errorMessage: loadedImage == nil ? message : nil
                    )
                )
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
