import SwiftUI
import UniformTypeIdentifiers

struct ComposerWorkbenchView: View {
    let session: ComposerSession
    var isInspectorPresented = true
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ComposerProWorkspace(session: session, isInspectorPresented: isInspectorPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.96))
        .preferredColorScheme(.dark)
        .onAppear {
            session.attachUndoManager(undoManager)
        }
        .fileImporter(
            isPresented: bindingForImporter,
            allowedContentTypes: allowedImportTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task { await session.handleImportedAssets(urls) }
            case let .failure(error):
                session.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Import Composer Source",
            isPresented: bindingForImportMenu,
            titleVisibility: .visible
        ) {
            Button("Graph PDF") {
                session.beginImport(kind: .graph)
            }
            Button("Asset File") {
                session.beginImport(kind: .asset)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose Graph PDF or Asset File for this Composer session.")
        }
    }

    private var allowedImportTypes: [UTType] {
        switch session.pendingImportKind {
        case .graph:
            return [FileTypeCatalog.pdf]
        case .asset:
            return FileTypeCatalog.composerImports
        }
    }

    private var bindingForImporter: Binding<Bool> {
        Binding(
            get: { session.isImportPresented },
            set: { session.isImportPresented = $0 }
        )
    }

    private var bindingForImportMenu: Binding<Bool> {
        Binding(
            get: { session.isImportMenuPresented },
            set: { session.isImportMenuPresented = $0 }
        )
    }

}

private struct ComposerProWorkspace: View {
    let session: ComposerSession
    let isInspectorPresented: Bool

    var body: some View {
        HStack(spacing: ProWorkspaceMetrics.panelSpacing) {
            ComposerAssetBrowserView(session: session)
                .padding(12)
                .frame(width: ProWorkspaceMetrics.leftRailIdealWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous)
                )
                .padding(.leading, 12)
                .padding(.vertical, 12)

            ComposerCanvasStageView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 12)

            if isInspectorPresented {
                ComposerInspectorView(session: session)
                    .frame(width: 340)
                    .frame(maxHeight: .infinity)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous))
                    .glassEffect(
                        .regular.interactive(),
                        in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous)
                    )
                    .padding(.trailing, 10)
                    .padding(.vertical, 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(MotionTokens.selection, value: isInspectorPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ComposerCanvasStageView: View {
    let session: ComposerSession

    var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .underPageBackgroundColor)
                .opacity(0.72)

            ComposerCanvasView(session: session)
                .padding(28)

            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous))
    }
}
