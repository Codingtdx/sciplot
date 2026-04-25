import SwiftUI

struct DataStudioImportWizardSheet: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        Group {
            switch session.importWizardStep {
            case .scope:
                DataStudioImportScopeSheet(session: session)
            case .kind:
                DataStudioImportChooserSheet(session: session)
            case .resolver:
                DataStudioImportResolverSheet(session: session)
            case .createTemplate:
                DataStudioCreateTemplateEditorSheet(session: session)
            }
        }
    }
}

private struct DataStudioImportScopeSheet: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DataStudioSheetHeader(title: "Start Import")

            Divider()

            VStack(spacing: 10) {
                DataStudioSheetOptionRow(
                    symbol: "plus.rectangle.on.rectangle",
                    title: DataStudioImportDisposition.addToCurrentSession.title
                ) {
                    session.chooseImportDisposition(.addToCurrentSession)
                }

                DataStudioSheetOptionRow(
                    symbol: "sparkles.rectangle.stack",
                    title: DataStudioImportDisposition.startNewSession.title
                ) {
                    session.chooseImportDisposition(.startNewSession)
                }
            }
            .padding(18)

            Divider()

            DataStudioSheetFooter {
                Button("Cancel") {
                    session.dismissImportWizard()
                }
            }
        }
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DataStudioImportChooserSheet: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DataStudioSheetHeader(title: "Import into Data Studio")

            Divider()

            VStack(spacing: 10) {
                DataStudioSheetOptionRow(
                    symbol: "tray.and.arrow.down",
                    title: DataStudioImportKind.rawFiles.title
                ) {
                    session.chooseImportKind(.rawFiles)
                }

                DataStudioSheetOptionRow(
                    symbol: "tablecells",
                    title: DataStudioImportKind.existingWorkbook.title
                ) {
                    session.chooseImportKind(.existingWorkbook)
                }
            }
            .padding(18)

            Divider()

            DataStudioSheetFooter {
                if session.canGoBackInImportWizard {
                    Button("Back") {
                        session.goBackInImportWizard()
                    }
                }

                Spacer()

                Button("Cancel") {
                    session.dismissImportWizard()
                }
            }
        }
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DataStudioImportResolverSheet: View {
    @Bindable var session: DataStudioSession
    @State private var renameDraft = ""
    @State private var isDeleteConfirmationPresented = false

    private var presentation: DataStudioResolverPresentation {
        session.resolverPresentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            resolverHeader

            Divider()

            if presentation.recommendedMatches.isEmpty && presentation.otherTemplates.isEmpty {
                ContentUnavailableView("No Parse Templates", systemImage: "questionmark.folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: selectedTemplateBinding) {
                    if !presentation.recommendedMatches.isEmpty {
                        Section("Recommended Templates") {
                            ForEach(presentation.recommendedMatches) { match in
                                DataStudioResolverTemplateRow(
                                    title: match.label,
                                    family: match.family,
                                    warning: match.warnings.first
                                )
                                .tag(Optional(match.templateID))
                            }
                        }
                    }

                    if !presentation.otherTemplates.isEmpty {
                        Section("Other Available Templates") {
                            ForEach(presentation.otherTemplates) { template in
                                DataStudioResolverTemplateRow(
                                    title: template.label,
                                    family: template.family,
                                    warning: nil
                                )
                                .tag(Optional(template.id))
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            templateManagementSection

            Divider()

            DataStudioSheetFooter {
                Button("Back") {
                    session.goBackInImportWizard()
                }

                Button("Cancel") {
                    session.dismissImportWizard()
                }

                Spacer()

                Button("Create New Parse Template") {
                    session.beginCreateTemplateEditor()
                }
                .buttonStyle(.bordered)
                .help("Open the template editor for this source preview.")

                Button("Use Selected Template") {
                    Task { await session.importWithSelectedTemplate() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!presentation.useSelectedTemplateAvailability.isEnabled)
                .help(
                    presentation.useSelectedTemplateAvailability.reason
                        ?? "Build a workbook with the selected template."
                )
            }
        }
        .frame(minWidth: 620, idealWidth: 620, minHeight: 430, idealHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            syncRenameDraft(with: presentation.selectedTemplateLabel)
        }
        .onChange(of: presentation.selectedTemplateLabel) { _, newValue in
            syncRenameDraft(with: newValue)
        }
        .confirmationDialog(
            "Delete Parse Template?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Template", role: .destructive) {
                Task { await session.deleteSelectedTemplate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes '\(presentation.selectedTemplateLabel ?? "selected template")'.")
        }
    }

    private var resolverHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resolve Parse Template")
                .font(.headline)

            if let preview = session.sourcePreview {
                Text(URL(fileURLWithPath: preview.inputPath).lastPathComponent)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(20)
    }

    private var templateManagementSection: some View {
        GroupBox("Template Management") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Template Name", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!presentation.renameTemplateAvailability.isEnabled)

                HStack(spacing: 10) {
                    Button("Rename") {
                        Task { await session.renameSelectedTemplate(to: renameDraft) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.renameTemplateAvailability.isEnabled)
                    .help(presentation.renameTemplateAvailability.reason ?? "Rename the selected parse template.")

                    Button("Delete", role: .destructive) {
                        isDeleteConfirmationPresented = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.deleteTemplateAvailability.isEnabled)
                    .help(presentation.deleteTemplateAvailability.reason ?? "Delete the selected parse template.")

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func syncRenameDraft(with selectedLabel: String?) {
        renameDraft = selectedLabel ?? ""
    }

    private var selectedTemplateBinding: Binding<String?> {
        Binding(
            get: { session.selectedTemplateID },
            set: { session.selectedTemplateID = $0 }
        )
    }
}

struct DataStudioSheetHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(20)
    }
}

struct DataStudioSheetFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct DataStudioSheetOptionRow: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 20)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(14)
            .background(.quinary.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct DataStudioResolverTemplateRow: View {
    let title: String
    let family: String?
    let warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body.weight(.semibold))
            if let family, !family.isEmpty {
                Text(family)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let warning, !warning.isEmpty {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
