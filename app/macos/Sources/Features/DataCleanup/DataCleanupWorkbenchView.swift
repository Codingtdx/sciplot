import SwiftUI

struct DataCleanupWorkbenchView: View {
    let session: DataCleanupSession

    var body: some View {
        HSplitView {
            CleanupImportView(session: session)
                .frame(minWidth: 290, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let errorMessage = session.errorMessage {
                        ErrorStateCard(
                            title: "Data Cleanup issue",
                            message: errorMessage,
                            retryTitle: nil,
                            retryAction: nil
                        )
                    }

                    CleanupReviewView(session: session)
                    CleanupCompareView(session: session)
                    CleanupExportView(session: session)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
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
        .confirmationDialog(
            "Import Data Cleanup Source",
            isPresented: bindingForImportMenu,
            titleVisibility: .visible
        ) {
            Button(DataCleanupImportKind.rawCSV.title) {
                session.beginImport(kind: .rawCSV)
            }
            Button(DataCleanupImportKind.preparedWorkbook.title) {
                session.beginImport(kind: .preparedWorkbook)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose whether to preprocess raw tensile CSV files or load an existing prepared workbook into the compare queue.")
        }
        .sheet(isPresented: bindingForGuide) {
            DataCleanupGuideSheet(session: session)
        }
    }

    private var bindingForImportMenu: Binding<Bool> {
        Binding(
            get: { session.isImportMenuPresented },
            set: { session.isImportMenuPresented = $0 }
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

    private var bindingForGuide: Binding<Bool> {
        Binding(
            get: { session.isGuidePresented },
            set: { session.isGuidePresented = $0 }
        )
    }
}

private struct DataCleanupGuideSheet: View {
    let session: DataCleanupSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    guideSection(
                        title: "Import",
                        text: "Bring raw tensile CSV files in for preprocessing, or open prepared workbooks directly into the review and compare queue."
                    )
                    guideSection(
                        title: "Review & Clean",
                        text: "Data Cleanup keeps the current workbook summary, warnings, and representative curve preview together so you can verify the prepared result without opening Plot first."
                    )
                    guideSection(
                        title: "Compare",
                        text: "The compare queue is runtime-only. Reorder the prepared workbooks, choose the primary handoff workbook, and export the QC bundle when at least two groups are loaded."
                    )
                    guideSection(
                        title: "Export / Open in Plot",
                        text: "Comparison export writes the workbook and figure bundle together. Open in Plot always hands off the current primary workbook with its preferred sheet."
                    )
                }
                .padding(24)
            }
            .navigationTitle("Data Cleanup Guide")
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
