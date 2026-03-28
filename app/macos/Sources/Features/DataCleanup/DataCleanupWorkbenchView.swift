import SwiftUI

struct DataCleanupWorkbenchView: View {
    let session: DataCleanupSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Cleanup stage", selection: bindingForStage) {
                    ForEach(DataCleanupStage.allCases) { stage in
                        Text(stage.title).tag(stage)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)

                if let errorMessage = session.errorMessage {
                    ErrorStateCard(
                        title: "Data Cleanup issue",
                        message: errorMessage,
                        retryTitle: nil,
                        retryAction: nil
                    )
                }

                switch session.stage {
                case .intake:
                    CleanupImportView(session: session)
                case .review:
                    CleanupReviewView(session: session)
                case .compare:
                    CleanupCompareView(session: session)
                case .export:
                    CleanupExportView(session: session)
                }
            }
            .padding(24)
        }
        .fileImporter(
            isPresented: bindingForRawImporter,
            allowedContentTypes: FileTypeCatalog.cleanupRawInputs,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task { await session.handleImportedRawFiles(urls) }
            case let .failure(error):
                session.errorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: bindingForWorkbookImporter,
            allowedContentTypes: FileTypeCatalog.cleanupWorkbookInputs,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task { await session.handleImportedWorkbooks(urls) }
            case let .failure(error):
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private var bindingForStage: Binding<DataCleanupStage> {
        Binding(
            get: { session.stage },
            set: { session.stage = $0 }
        )
    }

    private var bindingForRawImporter: Binding<Bool> {
        Binding(
            get: { session.isRawImporterPresented },
            set: { session.isRawImporterPresented = $0 }
        )
    }

    private var bindingForWorkbookImporter: Binding<Bool> {
        Binding(
            get: { session.isWorkbookImporterPresented },
            set: { session.isWorkbookImporterPresented = $0 }
        )
    }
}
