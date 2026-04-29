import SwiftUI
import UniformTypeIdentifiers

struct ComposerWorkbenchView: View {
    let session: ComposerSession
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkspaceMetrics.panelSpacing) {
            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
            }

            HSplitView {
                ComposerAssetBrowserView(session: session)
                    .frame(
                        minWidth: ProWorkspaceMetrics.leftRailMinWidth,
                        idealWidth: ProWorkspaceMetrics.leftRailIdealWidth,
                        maxWidth: ProWorkspaceMetrics.leftRailMaxWidth,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .padding(.leading, 16)
                    .padding(.vertical, 12)

                ComposerCanvasView(session: session)
                    .padding(.trailing, 16)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
