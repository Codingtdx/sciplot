import SwiftUI
import UniformTypeIdentifiers

struct ComposerWorkbenchView: View {
    let session: ComposerSession
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
            }

            HStack(alignment: .top, spacing: 20) {
                ComposerAssetBrowserView(session: session)
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)

                ComposerCanvasView(session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
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
