import SwiftUI

struct PlotRefineView: View {
    @Bindable var session: PlotSession

    var body: some View {
        PlotPreviewStage(session: session)
    }
}

struct PlotPreviewStage: View {
    @Bindable var session: PlotSession

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(nsColor: .underPageBackgroundColor)
                .opacity(0.72)

            previewSurface
                .padding(34)

            if session.isPreviewing, session.previewResponse?.previews.first != nil {
                updatingBadge
                    .padding(16)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var previewSurface: some View {
        if let preview = session.previewResponse?.previews.first {
            if let previewPNG = preview.pngBase64,
               !previewPNG.isEmpty,
               PreviewImageDecoder.decodeBase64PNG(previewPNG) != nil
            {
                Base64PreviewImageView(base64PNG: previewPNG)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Base64PDFPreviewView(base64PDF: preview.pdfBase64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            PlotEmptyPreviewPage(
                isBusy: session.isInspecting || session.isPreviewing,
                hasSource: session.selectedFileURL != nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var updatingBadge: some View {
        ProgressView()
            .controlSize(.small)
            .padding(10)
            .glassEffect(.regular, in: Capsule())
            .foregroundStyle(.secondary)
            .transition(MotionTokens.stateTransition)
    }
}

private struct PlotEmptyPreviewPage: View {
    let isBusy: Bool
    let hasSource: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.26), radius: 24, x: 0, y: 18)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
                    .glassEffect(.regular, in: Capsule())
            }
        }
        .aspectRatio(1.12, contentMode: .fit)
        .frame(maxWidth: 760)
    }
}
