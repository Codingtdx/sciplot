import AppKit
import SwiftUI

struct Base64PreviewImageView: View {
    let base64PNG: String

    var body: some View {
        if let image = PreviewImageDecoder.decodeBase64PNG(base64PNG) {
            GeometryReader { geometry in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .center
                    )
            }
            .background(.black.opacity(0.02), in: RoundedRectangle(cornerRadius: 18))
        } else {
            EmptyStateCard(
                title: "Preview unavailable",
                message: "The sidecar returned preview data that could not be decoded as a PNG."
            )
        }
    }
}
