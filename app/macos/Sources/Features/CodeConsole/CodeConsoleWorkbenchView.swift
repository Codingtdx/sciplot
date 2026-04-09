import SwiftUI

struct CodeConsoleWorkbenchView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar

            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
            }

            if session.availableBindings.isEmpty {
                EmptyStateCard(
                    title: "No bound dataset",
                    message: "Import a file directly in Code Console, or bring a Plot / Data Studio dataset here to generate the external-AI prompt and controlled runner context."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    sourceRail
                        .frame(minWidth: 250, idealWidth: 280, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 18) {
                        CodeConsoleEditorView(session: session)
                        CodeConsoleOutputsView(session: session)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(18)
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
                    session.importFile(first)
                }
            case let .failure(error):
                session.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: bindingForGuide) {
            CodeConsoleGuideSheet(session: session)
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.selectedSourceFilename ?? "No source selected")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(session.documentStatusSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            if session.selectedFileURL != nil {
                Picker("Sheet", selection: selectedSheetBinding) {
                    ForEach(session.availableSheets, id: \.self) { sheet in
                        Text(sheet.displayName).tag(sheet)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220, alignment: .leading)
            }

            HStack(spacing: 6) {
                Image(systemName: session.liveStatusSymbol)
                    .symbolEffect(
                        .pulse.byLayer,
                        options: .repeating,
                        value: session.isRefreshingContext || session.isRunning
                    )
                Text(session.liveStatusLabel)
                    .contentTransition(.opacity)
            }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .animation(MotionTokens.status, value: session.liveStatusLabel)
        }
    }

    private var sourceRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bound Context")
                    .font(.headline)

                ForEach(session.availableBindings) { binding in
                    Button {
                        session.setSelectedBinding(id: binding.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(binding.title)
                                    .font(.headline)
                                Spacer()
                                Text(binding.sourceKind.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(binding.sourceURL.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(binding.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(cardBackground(isSelected: session.selectedBindingID == binding.id))
                    }
                    .buttonStyle(.plain)
                }

                if !session.boundContext.isEmpty {
                    ForEach(session.boundContext) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.value)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.quinary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                HStack(spacing: 10) {
                    Button("Open Source") {
                        session.openCurrentSource()
                    }
                    .buttonStyle(.bordered)

                    Button("Reveal") {
                        session.revealCurrentSource()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func cardBackground(isSelected: Bool) -> some ShapeStyle {
        isSelected ? AnyShapeStyle(.quinary.opacity(0.32)) : AnyShapeStyle(.quinary.opacity(0.15))
    }

    private var bindingForImporter: Binding<Bool> {
        Binding(
            get: { session.isImporterPresented },
            set: { session.isImporterPresented = $0 }
        )
    }

    private var bindingForGuide: Binding<Bool> {
        Binding(
            get: { session.isGuidePresented },
            set: { session.isGuidePresented = $0 }
        )
    }

    private var selectedSheetBinding: Binding<SheetValue> {
        Binding(
            get: { session.selectedSheet },
            set: { session.setSelectedSheet($0) }
        )
    }
}

private struct CodeConsoleGuideSheet: View {
    @Bindable var session: CodeConsoleSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    guideSection(
                        title: "Bind Context",
                        text: "Use Import or existing Plot/Data Studio context to bind a dataset before generating prompts."
                    )
                    guideSection(
                        title: "Prompt And Code",
                        text: "Copy the controlled prompt for external AI, then paste returned Python into the editor."
                    )
                    guideSection(
                        title: "Run",
                        text: "Run executes repo-native Python and captures logs, generated files, and previews."
                    )
                    guideSection(
                        title: "Outputs",
                        text: "Use the Outputs panel and inspector to open generated artifacts and hand off results."
                    )
                }
                .padding(24)
            }
            .navigationTitle("Code Console Help")
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
