import SwiftUI

struct PlotRefineView: View {
    @Bindable var session: PlotSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.isPreviewing {
                BusyStateCard(
                    title: "Rendering preview",
                    message: "Generating the current Plot preview."
                )
            } else if let preview = session.previewResponse?.previews.first {
                Base64PreviewImageView(base64PNG: preview.pngBase64)
                    .frame(minHeight: 520)
            } else {
                ContentUnavailableView(
                    "No preview yet",
                    systemImage: "photo.on.rectangle",
                    description: Text("Choose a compatible template and continue to render a preview.")
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
