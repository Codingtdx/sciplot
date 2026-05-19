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
    @State private var templateSearchText = ""
    @State private var isDeleteConfirmationPresented = false

    private var presentation: DataStudioResolverPresentation {
        session.resolverPresentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            resolverHeader

            Divider()

            if filteredRecommendedMatches.isEmpty && filteredOtherTemplates.isEmpty {
                ContentUnavailableView("No Parse Templates", systemImage: "questionmark.folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    importProfilePanel
                        .frame(width: 230)
                        .border(Color(nsColor: .separatorColor), width: 0.5)

                    List(selection: selectedTemplateBinding) {
                        if !filteredRecommendedMatches.isEmpty {
                            Section("Recommended Templates") {
                                ForEach(filteredRecommendedMatches) { match in
                                    DataStudioResolverTemplateRow(
                                        title: match.label,
                                        family: match.family,
                                        detail: match.roleSummaryText,
                                        warning: match.warnings.first
                                            ?? match.diagnostics.first(where: { $0.severity == "warning" })?.message
                                    )
                                    .tag(Optional(match.templateID))
                                }
                            }
                        }

                        if !filteredOtherTemplates.isEmpty {
                            Section("Other Available Templates") {
                                ForEach(filteredOtherTemplates) { template in
                                    DataStudioResolverTemplateRow(
                                        title: template.label,
                                        family: template.family,
                                        detail: nil,
                                        warning: nil
                                    )
                                    .tag(Optional(template.id))
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
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

            TextField("Search Templates", text: $templateSearchText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(20)
    }

    private var importProfilePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Profile")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let importPreview = session.importPreview {
                VStack(alignment: .leading, spacing: 4) {
                    Text(importPreview.label)
                        .font(.headline)
                        .lineLimit(1)
                    Text(session.importSelection?.selectedSheetOrSegment ?? importPreview.selectedSheetOrSegment ?? importPreview.status.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let diagnostic = importPreview.diagnostics.first {
                    Label(diagnostic.message.isEmpty ? diagnostic.statusCode : diagnostic.message, systemImage: diagnostic.severity == "warning" ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(diagnostic.severity == "warning" ? .orange : .secondary)
                        .lineLimit(3)
                }

                if !importPreview.availableOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Options")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(importPreview.availableOptions.prefix(4)) { option in
                            Text(option.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } else if let preview = session.sourcePreview {
                Text(URL(fileURLWithPath: preview.inputPath).lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text("Source preview ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No source profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var templateManagementSection: some View {
        GroupBox("Template Management") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Template Name", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!presentation.renameTemplateAvailability.isEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button("Rename") {
                            Task { await session.renameSelectedTemplate(to: renameDraft) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!presentation.renameTemplateAvailability.isEnabled)
                        .help(presentation.renameTemplateAvailability.reason ?? "Rename the selected parse template.")

                        Button("Duplicate") {
                            Task { await session.duplicateSelectedTemplate() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!session.duplicateSelectedTemplateAvailability.isEnabled)
                        .help(session.duplicateSelectedTemplateAvailability.reason ?? "Duplicate the selected parse template.")

                        Button("Delete", role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(!presentation.deleteTemplateAvailability.isEnabled)
                        .help(presentation.deleteTemplateAvailability.reason ?? "Delete the selected parse template.")

                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Button("Import JSON") {
                            Task { await session.importTemplateJSON() }
                        }
                        .buttonStyle(.bordered)

                        Button("Export JSON") {
                            session.exportSelectedTemplateJSON()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!session.exportSelectedTemplateAvailability.isEnabled)
                        .help(session.exportSelectedTemplateAvailability.reason ?? "Export the selected parse template.")

                        Spacer()
                    }
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

    private var filteredRecommendedMatches: [DataStudioTemplateMatchResponse] {
        let needle = templateSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return presentation.recommendedMatches
        }
        return presentation.recommendedMatches.filter { match in
            match.label.lowercased().contains(needle) || match.family.lowercased().contains(needle)
        }
    }

    private var filteredOtherTemplates: [DataStudioTemplateResponse] {
        let needle = templateSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return presentation.otherTemplates
        }
        return presentation.otherTemplates.filter { template in
            template.label.lowercased().contains(needle)
                || template.family.lowercased().contains(needle)
                || template.id.lowercased().contains(needle)
        }
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
    let detail: String?
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
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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

private extension DataStudioTemplateMatchResponse {
    var roleSummaryText: String? {
        if !missingRoles.isEmpty {
            return "Missing: \(missingRoles.joined(separator: ", "))"
        }
        let roles = matchedRoles.map(\.role)
        guard !roles.isEmpty else {
            return nil
        }
        return "Matched: \(roles.joined(separator: ", "))"
    }
}
