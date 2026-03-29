import SwiftUI
import UniformTypeIdentifiers

struct ComposerWorkbenchView: View {
    let session: ComposerSession
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ComposerAssetBrowserView(session: session)
                .frame(width: 300)
                .frame(maxHeight: .infinity)

            ComposerCanvasView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
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
        .sheet(isPresented: bindingForGuide) {
            ComposerGuideSheet(session: session)
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

    private var bindingForGuide: Binding<Bool> {
        Binding(
            get: { session.isGuidePresented },
            set: { session.isGuidePresented = $0 }
        )
    }
}

private struct ComposerGuideSheet: View {
    let session: ComposerSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    guideSection(
                        title: "Grid",
                        text: "Composer works on one fixed 3x3 figure grid. Select single cells for direct placement, or command-click adjacent cells to build a rectangular selection."
                    )
                    guideSection(
                        title: "Merge And Unmerge",
                        text: "Merge turns an empty rectangular selection into one free region. Unmerge removes that free region and leaves any assigned assets in place."
                    )
                    guideSection(
                        title: "Placement",
                        text: "Graphs stay tied to graph regions and must move into matching cell spans such as 1x1, 2x1, or 1x2. Assets can snap into single cells or merged free regions."
                    )
                    guideSection(
                        title: "Labels",
                        text: "Auto labels resolve to figure letters such as A, B, C, and D. Turn auto labels off in the inspector when you want to enter a manual panel label."
                    )
                    guideSection(
                        title: "Export",
                        text: "Preview and export still use the authoritative sidecar flow. Export creates the final single-page PDF while preserving the existing repo-backed composition rules."
                    )
                }
                .padding(24)
            }
            .navigationTitle("Composer Guide")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                        session.dismissGuide()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func guideSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
    }
}
