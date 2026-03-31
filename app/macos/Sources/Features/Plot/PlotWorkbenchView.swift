import SwiftUI

struct PlotWorkbenchView: View {
    @Bindable var session: PlotSession
    let bootstrapErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            workspaceHeader

            if let bootstrapErrorMessage {
                compactIssueLabel(message: bootstrapErrorMessage)
            }

            if let errorMessage = session.errorMessage {
                compactIssueLabel(message: errorMessage)
            }

            switch session.workspaceMode {
            case .review:
                PlotImportView(session: session)
            case .refine:
                PlotRefineView(session: session)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: bindingForImporter,
            allowedContentTypes: FileTypeCatalog.plotInputs,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let first = urls.first {
                    Task { await session.importFileAndInspect(first) }
                }
            case let .failure(error):
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.selectedSourceFilename ?? "No source selected")
                .font(.title2.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 12) {
                if session.selectedFileURL != nil {
                    Picker("Sheet", selection: selectedSheetBinding) {
                        ForEach(session.availableSheets, id: \.self) { sheet in
                            Text(sheet.displayName).tag(sheet)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 230, alignment: .leading)
                }

                if session.isInspecting {
                    Label("Inspecting…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if session.needsInspection {
                    Label("Inspect required", systemImage: "magnifyingglass")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if session.workspaceMode == .refine {
                    Button("Review") {
                        session.returnToReview()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Continue") {
                    Task { await session.continueToRefine() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.canContinueToRefine)
            }
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

    private var bindingForImporter: Binding<Bool> {
        Binding(
            get: { session.isImporterPresented },
            set: { session.isImporterPresented = $0 }
        )
    }

    private var selectedSheetBinding: Binding<SheetValue> {
        Binding(
            get: { session.selectedSheet },
            set: { newSheet in
                Task { await session.selectSheetAndReinspect(newSheet) }
            }
        )
    }
}
