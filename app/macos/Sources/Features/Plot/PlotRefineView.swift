import SwiftUI

struct PlotRefineView: View {
    @Bindable var session: PlotSession

    var body: some View {
        ZStack(alignment: .topTrailing) {
            previewSurface

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
            Base64PDFPreviewView(base64PDF: preview.pdfBase64)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
                .overlay(alignment: .center) {
                    if session.isInspecting || session.isPreviewing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(10)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    SubtleStageHint(
                        title: "Preview",
                        systemImage: "doc.richtext"
                    )
                    .padding(.horizontal, 2)
                }
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
