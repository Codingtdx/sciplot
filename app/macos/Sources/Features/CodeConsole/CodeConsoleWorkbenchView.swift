import SwiftUI

struct CodeConsoleWorkbenchView: View {
    @Bindable var session: CodeConsoleSession
    var isInspectorPresented = true
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        CodeConsoleProWorkspace(session: session, isInspectorPresented: isInspectorPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.rootBackground)
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
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        HStack(spacing: ProWorkspaceMetrics.panelSpacing) {
            CodeConsoleSourceRailView(session: session)
                .padding(ProWorkspaceMetrics.stagePadding)
                .frame(width: ProWorkspaceMetrics.leftRailIdealWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .proGlassPanel(theme: theme)
                .padding(.leading, ProWorkspaceMetrics.stagePadding)
                .padding(.vertical, ProWorkspaceMetrics.stagePadding)

            CodeConsoleRunStageView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, ProWorkspaceMetrics.stagePadding)

            if isInspectorPresented {
                CodeConsoleContextView(session: session)
                    .inspectorColumnWidth()
                    .frame(maxHeight: .infinity)
                    .proGlassPanel(theme: theme)
                    .padding(.trailing, 10)
                    .padding(.vertical, ProWorkspaceMetrics.stagePadding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(MotionTokens.selection, value: isInspectorPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CodeConsoleRunStageView: View {
    @Bindable var session: CodeConsoleSession
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous)
        ZStack(alignment: .top) {
            CodeConsoleRunWorkspaceView(session: session)
                .padding(.horizontal, ProWorkspaceMetrics.stageContentPadding)
                .padding(.top, 54)
                .padding(.bottom, ProWorkspaceMetrics.stageContentPadding)

            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .background(theme.previewSurround, in: shape)
        .clipShape(shape)
        .overlay {
            shape.stroke(theme.hairline, lineWidth: 0.8)
        }
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
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkspaceMetrics.panelSpacing) {
            WorkbenchRailTitle(title: "Bound Context", trailing: "\(session.availableBindings.count)")

            sheetPicker

            List(selection: selectedBindingSelection) {
                ForEach(session.availableBindings) { binding in
                    CodeConsoleBindingRow(binding: binding)
                        .tag(Optional(binding.id))
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sheetPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "tablecells")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Picker("Sheet", selection: selectedSheetSelection) {
                ForEach(session.availableSheets, id: \.self) { sheet in
                    Text(sheet.displayName).tag(sheet)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .disabled(session.availableBindings.isEmpty || session.availableSheets.count < 2)
            .help(
                session.availableBindings.isEmpty
                    ? "Bind a dataset before choosing a sheet."
                    : "Choose the sheet used to refresh the Code Console context."
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .proGlassRow(theme: theme, cornerRadius: ProCornerPolicy.row)
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
