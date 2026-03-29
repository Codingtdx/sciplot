import SwiftUI

struct ComposerPanelThumbnailView: View {
    let url: URL
    let size: CGSize
    var cornerRadius: CGFloat = 12

    @State private var model = QuickLookThumbnailModel()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.quinary.opacity(0.35))

            if let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if model.errorMessage != nil {
                Image(systemName: "doc.richtext")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: taskKey) {
            await model.load(
                url: url,
                size: CGSize(
                    width: max(40, size.width),
                    height: max(40, size.height)
                )
            )
        }
    }

    private var taskKey: String {
        "\(url.path)#\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }
}
