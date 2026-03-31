import SwiftUI

struct PlotRefineView: View {
    @Bindable var session: PlotSession

    var body: some View {
        ZStack(alignment: .topTrailing) {
            previewSurface

            if session.isPreviewing {
                updatingBadge
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var previewSurface: some View {
        if let preview = session.previewResponse?.previews.first {
            Base64PDFPreviewView(base64PDF: preview.pdfBase64)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
                )
        } else if session.isInspecting || session.isPreviewing {
            BusyStateCard(
                title: session.isInspecting ? "Inspecting source" : "Rendering preview",
                message: "Plot keeps the last successful preview visible until the next render succeeds."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "No preview yet",
                systemImage: "photo.on.rectangle",
                description: Text("Import a source from the toolbar to inspect and render a live preview.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var updatingBadge: some View {
        Label("Updating preview", systemImage: "arrow.triangle.2.circlepath")
            .font(.footnote.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.thinMaterial, in: Capsule())
            .foregroundStyle(.secondary)
    }
}
