import SwiftUI

struct ComposerWorkbenchView: View {
    let session: ComposerSession
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Composer stage", selection: bindingForStage) {
                    ForEach(ComposerStage.allCases) { stage in
                        Text(stage.title).tag(stage)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                if let errorMessage = session.errorMessage {
                    ErrorStateCard(
                        title: "Composer issue",
                        message: errorMessage,
                        retryTitle: nil,
                        retryAction: nil
                    )
                }

                HStack(alignment: .top, spacing: 20) {
                    ComposerAssetBrowserView(session: session)

                    VStack(alignment: .leading, spacing: 16) {
                        ComposerCanvasView(session: session)
                            .frame(minHeight: 480)

                        GroupBox("Authoritative Preview") {
                            if session.isPreviewing {
                                BusyStateCard(title: "Rendering preview", message: "The sidecar is composing the authoritative preview image.")
                            } else if let preview = session.previewResponse {
                                VStack(alignment: .leading, spacing: 12) {
                                    Base64PreviewImageView(base64PNG: preview.pngBase64)
                                        .frame(minHeight: 220)
                                    if let report = preview.submissionReport {
                                        Text(report.summary)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 8)
                            } else {
                                Text("Make a canvas change or import an asset to request a debounced preview.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .onAppear {
            session.attachUndoManager(undoManager)
        }
        .fileImporter(
            isPresented: bindingForImporter,
            allowedContentTypes: FileTypeCatalog.composerImports,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task { await session.handleImportedAssets(urls) }
            case let .failure(error):
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private var bindingForStage: Binding<ComposerStage> {
        Binding(
            get: { session.stage },
            set: { session.stage = $0 }
        )
    }

    private var bindingForImporter: Binding<Bool> {
        Binding(
            get: { session.isImportPresented },
            set: { session.isImportPresented = $0 }
        )
    }
}
