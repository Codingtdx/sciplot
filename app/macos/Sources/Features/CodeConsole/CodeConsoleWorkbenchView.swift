import SwiftUI

struct CodeConsoleWorkbenchView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkspaceMetrics.panelSpacing) {
            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
            }

            HSplitView {
                CodeConsoleSourceRailView(session: session)
                    .frame(
                        minWidth: ProWorkspaceMetrics.leftRailMinWidth,
                        idealWidth: ProWorkspaceMetrics.leftRailIdealWidth,
                        maxWidth: ProWorkspaceMetrics.leftRailMaxWidth,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .padding(.leading, 16)
                    .padding(.vertical, 12)

                CodeConsoleRunWorkspaceView(session: session)
                    .padding(.trailing, 16)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fileImporter(
            isPresented: bindingForImporter,
            allowedContentTypes: FileTypeCatalog.plotInputs,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let first = urls.first {
                    session.importFile(first)
                }
            case let .failure(error):
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private var bindingForImporter: Binding<Bool> {
        Binding(
            get: { session.isImporterPresented },
            set: { session.isImporterPresented = $0 }
        )
    }
}

struct CodeConsoleRunWorkspaceView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        if session.availableBindings.isEmpty {
            SubtleStageHint(
                title: "Import a file or bind a Plot or Data Studio dataset",
                systemImage: "tray.and.arrow.down",
                alignment: .center
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VSplitView {
                CodeConsoleEditorView(session: session)
                    .frame(minHeight: 480, idealHeight: 560, maxHeight: .infinity)

                CodeConsoleOutputsView(session: session)
                    .frame(minHeight: 260, idealHeight: 340, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct CodeConsoleSourceRailView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkspaceMetrics.panelSpacing) {
            WorkbenchRailTitle(title: "Bound Context", trailing: "\(session.availableBindings.count)")

            List(selection: selectedBindingSelection) {
                ForEach(session.availableBindings) { binding in
                    CodeConsoleBindingRow(binding: binding)
                        .tag(Optional(binding.id))
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)

            Divider()

            Picker("Sheet", selection: selectedSheetSelection) {
                ForEach(session.availableSheets, id: \.self) { sheet in
                    Text(sheet.displayName).tag(sheet)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .disabled(session.availableBindings.isEmpty || session.availableSheets.count < 2)
            .help(
                session.availableBindings.isEmpty
                    ? "Bind a dataset before choosing a sheet."
                    : "Choose the sheet used to refresh the Code Console context."
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var selectedBindingSelection: Binding<String?> {
        Binding(
            get: { session.selectedBindingID },
            set: { newValue in
                if let newValue {
                    session.setSelectedBinding(id: newValue)
                }
            }
        )
    }

    private var selectedSheetSelection: Binding<SheetValue> {
        Binding(
            get: { session.selectedSheet },
            set: { session.setSelectedSheet($0) }
        )
    }
}

private struct CodeConsoleBindingRow: View {
    let binding: CodeConsoleBindingOption

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: sourceSymbol(for: binding.sourceKind))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(binding.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(binding.sourceURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func sourceSymbol(for kind: CodeConsoleSourceKind) -> String {
        switch kind {
        case .plot:
            return "chart.xyaxis.line"
        case .dataStudio:
            return "tablecells"
        case .importedFile:
            return "doc"
        }
    }
}
