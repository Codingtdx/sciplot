import SwiftUI

struct DataCleanupWorkbenchView: View {
    let session: DataCleanupSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topSourceBar

            if let errorMessage = session.errorMessage {
                compactIssueLabel(message: errorMessage)
            }

            HSplitView {
                CleanupImportView(session: session)
                    .frame(minWidth: 230, idealWidth: 260, maxWidth: 300, maxHeight: .infinity, alignment: .topLeading)

                CleanupPreviewSurface(session: session)
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
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
            Text("Choose raw tensile CSV files or prepared workbooks for the current cleanup session.")
        }
        .sheet(isPresented: bindingForGuide) {
            DataCleanupGuideSheet(session: session)
        }
    }

    private var topSourceBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.selectedSourceFilename ?? "No workbook selected")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)

            if let focusedWorkbook = session.focusedWorkbook {
                HStack(spacing: 8) {
                    Text("Sheet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(focusedWorkbook.preferredSheet.displayName)
                        .font(.footnote.weight(.medium))
                }
            }

            Label(session.liveStatusLabel, systemImage: session.liveStatusSymbol)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func compactIssueLabel(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(2)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.quinary.opacity(0.32), in: RoundedRectangle(cornerRadius: 10))
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

private struct CleanupPreviewSurface: View {
    let session: DataCleanupSession

    var body: some View {
        ZStack(alignment: .topTrailing) {
            previewContent

            if session.currentActivity == .refreshingReview || session.focusedWorkbook?.isReviewLoading == true {
                Label("Updating preview", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote.weight(.semibold))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(.thinMaterial, in: Capsule())
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var previewContent: some View {
        if let workbook = session.focusedWorkbook {
            if workbook.isReviewLoading {
                BusyStateCard(
                    title: "Refreshing preview",
                    message: "Data Cleanup is rendering the representative curve for the focused workbook."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = workbook.reviewErrorMessage {
                ErrorStateCard(
                    title: "Preview issue",
                    message: errorMessage,
                    retryTitle: "Retry Preview",
                    retryAction: {
                        Task { await session.refreshFocusedReview() }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let preview = workbook.reviewPreview {
                Base64PDFPreviewView(base64PDF: preview.pdfBase64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
                    )
            } else {
                emptySurface(
                    title: "No preview yet",
                    systemImage: "waveform.path.ecg.rectangle",
                    description: "Focus a prepared workbook to review its representative curve."
                )
            }
        } else if session.currentActivity == .preprocessing || session.currentActivity == .importingWorkbooks {
            BusyStateCard(
                title: "Preparing workbook",
                message: "Data Cleanup is building the first focused workbook preview."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            emptySurface(
                title: "No prepared workbook yet",
                systemImage: "tablecells.badge.ellipsis",
                description: "Import raw CSV or open a prepared workbook from the toolbar to start review."
            )
        }
    }

    private func emptySurface(title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct DataCleanupGuideSheet: View {
    let session: DataCleanupSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    guideSection(
                        title: "Import",
                        text: "Use the toolbar to preprocess raw tensile CSV files or open prepared workbooks into the current cleanup session."
                    )
                    guideSection(
                        title: "Focus",
                        text: "The main canvas always previews the focused workbook. The left rail controls focus and queue order."
                    )
                    guideSection(
                        title: "Primary",
                        text: "Primary controls Plot handoff. It does not replace the focused workbook preview."
                    )
                    guideSection(
                        title: "Compare / Output",
                        text: "Export writes the comparison workbook plus figure bundle together. Output browsing stays in the inspector."
                    )
                }
                .padding(24)
            }
            .navigationTitle("Data Cleanup Help")
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
