import SwiftUI

struct CodeConsoleWorkbenchView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.selectedSourceFilename != nil {
                topBar
            }

            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
            }

            if session.availableBindings.isEmpty {
                EmptyStateCard(
                    title: "No bound dataset",
                    message: "Import a file or bind an existing Plot/Data Studio dataset."
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

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(session.selectedSourceFilename ?? "")
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

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

            Image(systemName: session.liveStatusSymbol)
                .symbolEffect(
                    .pulse.byLayer,
                    options: .repeating,
                    value: session.isRefreshingContext || session.isRunning
                )
                .font(.headline)
                .foregroundStyle(session.errorMessage == nil ? Color.secondary : Color.orange)
        }
    }

    private var sourceRail: some View {
        let presentation = session.sourceActionsPresentation

        return ScrollView {
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
                                Image(systemName: sourceSymbol(for: binding.sourceKind))
                                    .foregroundStyle(.secondary)
                            }
                            Text(binding.sourceURL.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(cardBackground(isSelected: session.selectedBindingID == binding.id))
                    }
                    .buttonStyle(.plain)
                }

                if !session.boundContext.isEmpty {
                    ForEach(session.boundContext) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(item.label)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 10)
                            Text(item.value)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
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
                    .disabled(!presentation.openSourceAvailability.isEnabled)
                    .help(
                        presentation.openSourceAvailability.reason
                            ?? "Open the bound source file."
                    )

                    Button("Reveal") {
                        session.revealCurrentSource()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.revealSourceAvailability.isEnabled)
                    .help(
                        presentation.revealSourceAvailability.reason
                            ?? "Reveal the bound source file in Finder."
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func cardBackground(isSelected: Bool) -> some ShapeStyle {
        isSelected ? AnyShapeStyle(.quinary.opacity(0.32)) : AnyShapeStyle(.quinary.opacity(0.15))
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

    private var bindingForImporter: Binding<Bool> {
        Binding(
            get: { session.isImporterPresented },
            set: { session.isImporterPresented = $0 }
        )
    }

    private var selectedSheetBinding: Binding<SheetValue> {
        Binding(
            get: { session.selectedSheet },
            set: { session.setSelectedSheet($0) }
        )
    }
}
