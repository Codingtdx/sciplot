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
            EmptyStateCard(
                title: "No bound dataset",
                message: "Import a file or bind an existing Plot or Data Studio dataset."
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

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WorkbenchRailTitle(title: "Bound Context", trailing: "\(session.availableBindings.count)")

                ForEach(session.availableBindings) { binding in
                    Button {
                        session.setSelectedBinding(id: binding.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(binding.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: sourceSymbol(for: binding.sourceKind))
                                    .foregroundStyle(.secondary)
                            }
                            Text(binding.sourceURL.lastPathComponent)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
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
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
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
        }
    }

    private func cardBackground(isSelected: Bool) -> some ShapeStyle {
        isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.clear)
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
}
