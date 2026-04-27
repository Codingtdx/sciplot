import AppKit
import SwiftUI

struct Base64PreviewImageView: View {
    let base64PNG: String

    var body: some View {
        if let image = PreviewImageDecoder.decodeBase64PNG(base64PNG) {
            let previewShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            .clipShape(previewShape)
            .overlay(
                previewShape
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        } else {
            SubtleStageHint(title: "Preview unavailable", systemImage: "exclamationmark.triangle")
        }
    }
}
