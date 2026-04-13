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
            let previewShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            Base64PDFPreviewView(base64PDF: preview.pdfBase64)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(previewShape)
                .compositingGroup()
                .overlay(
                    previewShape
                        .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1, antialiased: true)
                )
        } else if session.isInspecting || session.isPreviewing {
            BusyStateCard(
                title: session.isInspecting ? "Inspecting Source" : "Rendering Preview"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No Preview", systemImage: "photo.on.rectangle")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var updatingBadge: some View {
        ProgressView()
            .controlSize(.small)
            .padding(10)
            .background(.thinMaterial, in: Capsule())
            .foregroundStyle(.secondary)
            .transition(MotionTokens.stateTransition)
    }
}
