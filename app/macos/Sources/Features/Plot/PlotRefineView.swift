import SwiftUI

struct PlotRefineView: View {
    @Bindable var session: PlotSession

    var body: some View {
        PlotPreviewStage(session: session)
    }
}

struct PlotPreviewStage: View {
    @Bindable var session: PlotSession
    @Environment(\.displayScale) private var displayScale
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let previewBucket = PlotPreviewPixelBucket(stageSize: geometry.size, displayScale: displayScale)
            ZStack(alignment: .topTrailing) {
                theme.stageBackground

                previewSurface
                    .padding(34)

                if session.isPreviewing, session.previewResponse?.previews.first != nil {
                    updatingBadge
                        .padding(16)
                }

                if let errorMessage = session.errorMessage {
                    PlotStageDiagnosticBanner(message: errorMessage)
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(MotionTokens.stateTransition)
                }
            }
            .task(id: previewBucket) {
                session.updatePreviewPixelBucket(stageSize: geometry.size, displayScale: displayScale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

struct PlotStageDiagnosticBanner: View {
    let message: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        DiagnosticIssueCard(message: DiagnosticMessage(detail: message))
            .background(.regularMaterial, in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct PlotEmptyPreviewPage: View {
    let isBusy: Bool
    let hasSource: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                }

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
