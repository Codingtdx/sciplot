import SwiftUI

struct CodeConsoleWorkbenchView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
            }

            HSplitView {
                sourceRail
                    .frame(minWidth: 250, idealWidth: 280, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 16)
                    .padding(.vertical, 12)

                codeConsoleContent
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

    @ViewBuilder
    private var codeConsoleContent: some View {
        if session.availableBindings.isEmpty {
            SubtleStageHint(
                title: "Import a file or bind a Plot or Data Studio dataset",
                systemImage: "tray.and.arrow.down",
                alignment: .center
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                CodeConsoleOutputsView(session: session)
                CodeConsoleEditorView(session: session)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var sourceRail: some View {
        let presentation = session.sourceActionsPresentation

        return VStack(alignment: .leading, spacing: 12) {
            WorkbenchRailTitle(title: "Bound Context", trailing: "\(session.availableBindings.count)")

            List(selection: selectedBindingSelection) {
                ForEach(session.availableBindings) { binding in
                    CodeConsoleBindingRow(binding: binding)
                        .tag(Optional(binding.id))
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)

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

    private var bindingForImporter: Binding<Bool> {
        Binding(
            get: { session.isImporterPresented },
            set: { session.isImporterPresented = $0 }
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
