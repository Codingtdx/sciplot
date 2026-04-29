import SwiftUI

struct CodeConsoleWorkbenchView: View {
    @Bindable var session: CodeConsoleSession
    var isInspectorPresented = true

    var body: some View {
        CodeConsoleProWorkspace(session: session, isInspectorPresented: isInspectorPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.96))
        .preferredColorScheme(.dark)
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

private struct CodeConsoleProWorkspace: View {
    @Bindable var session: CodeConsoleSession
    let isInspectorPresented: Bool

    var body: some View {
        HStack(spacing: ProWorkspaceMetrics.panelSpacing) {
            CodeConsoleSourceRailView(session: session)
                .padding(12)
                .frame(width: ProWorkspaceMetrics.leftRailIdealWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous)
                )
                .padding(.leading, 12)
                .padding(.vertical, 12)

            CodeConsoleRunStageView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 12)

            if isInspectorPresented {
                CodeConsoleContextView(session: session)
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

private struct CodeConsoleRunStageView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .underPageBackgroundColor)
                .opacity(0.72)

            CodeConsoleRunWorkspaceView(session: session)
                .padding(.horizontal, 18)
                .padding(.top, 54)
                .padding(.bottom, 18)

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

struct CodeConsoleRunWorkspaceView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        VSplitView {
            CodeConsoleEditorView(session: session)
                .frame(minHeight: 390, idealHeight: 500, maxHeight: .infinity)

            CodeConsoleOutputsView(session: session)
                .frame(minHeight: 210, idealHeight: 300, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
