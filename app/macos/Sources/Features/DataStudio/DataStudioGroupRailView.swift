import SwiftUI

struct DataStudioGroupRailView: View {
    @Bindable var session: DataStudioSession
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        let autoKeepAvailability = session.autoKeepAllAvailability
        VStack(alignment: .leading, spacing: ProWorkspaceMetrics.panelSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    WorkbenchRailTitle(title: "Workbook Groups", trailing: "\(session.orderedGroups.count)")
                    Button("Auto Keep 5 All") {
                        session.applySuggestedExclusionsToAllWorkbooks()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(!autoKeepAvailability.isEnabled)
                    .help(autoKeepAvailability.reason ?? session.autoKeepAllHelp)
                }

                if session.orderedGroups.isEmpty {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
                } else {
                    List(selection: focusedWorkbookSelection) {
                        ForEach(session.orderedGroups) { group in
                            DataStudioGroupRowView(session: session, group: group)
                                .tag(group.id)
                        }
                        .onMove(perform: session.moveGroups)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .animation(MotionTokens.list, value: session.orderedGroups.map(\.id))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            DataStudioFigureRailSection(session: session)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .proGlassPanel(theme: theme)
    }

    private var focusedWorkbookSelection: Binding<String?> {
        Binding(
            get: { session.focusedWorkbook?.response.workbookPath },
            set: { session.focusWorkbook(path: $0) }
        )
    }
}

struct DataStudioFigureRailSection: View {
    @Bindable var session: DataStudioSession
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkbenchRailTitle(title: "Figures", trailing: "\(session.figureFamilies.count)")

            if session.figureFamilies.isEmpty {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(session.figureFamilies) { family in
                            DataStudioFigureRailRow(
                                family: family,
                                templates: templates(for: family),
                                selectedFamilyID: figureFamilyBinding.wrappedValue,
                                selectedTemplateID: selectedTemplateID(for: family),
                                selectFamily: { session.selectFigureFamily(id: family.id) },
                                selectTemplate: { session.selectFigureTemplate(id: $0) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(12)
        .proGlassRow(theme: theme, cornerRadius: ProCornerPolicy.row)
    }

    private var figureFamilyBinding: Binding<String?> {
        Binding(
            get: { session.currentFigureFamily?.id },
            set: { newValue in
                if let newValue {
                    session.selectFigureFamily(id: newValue)
                }
            }
        )
    }

    private func templates(for family: DataStudioFigureFamilyItem) -> [DataStudioFigureTemplateItem] {
        let currentFamilyID = session.currentFigureFamily?.id
        if currentFamilyID == family.id {
            return session.availableFigureTemplates
        }

        var seen: Set<String> = []
        return family.recipes
            .filter(\.supported)
            .compactMap { recipe in
                guard seen.insert(recipe.templateID).inserted else {
                    return nil
                }
                return DataStudioFigureTemplateItem(
                    id: recipe.templateID,
                    label: session.plotSession.templateLabel(for: recipe.templateID),
                    recipeID: recipe.id
                )
            }
    }

    private func selectedTemplateID(for family: DataStudioFigureFamilyItem) -> String? {
        guard session.currentFigureFamily?.id == family.id else {
            return nil
        }
        return session.currentFigureTemplateID
    }
}

struct DataStudioFigureRailRow: View {
    let family: DataStudioFigureFamilyItem
    let templates: [DataStudioFigureTemplateItem]
    let selectedFamilyID: String?
    let selectedTemplateID: String?
    let selectFamily: () -> Void
    let selectTemplate: (String) -> Void
    @Environment(\.proWorkspaceTheme) private var theme

    private var isSelected: Bool {
        family.id == selectedFamilyID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: selectFamily) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: family.metricID == nil ? "waveform.path.ecg" : "chart.bar.xaxis")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(family.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("\(templates.count) templates")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 6)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(RoundedRectangle(cornerRadius: ProWorkspaceMetrics.innerCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .proGlassRow(theme: theme, isSelected: isSelected, cornerRadius: ProCornerPolicy.row)

            if isSelected && !templates.isEmpty {
                HStack(spacing: 6) {
                    ForEach(templates) { template in
                        Button(template.label) {
                            selectTemplate(template.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(selectedTemplateID == template.id)
                        .help("Use \(template.label) for \(family.title).")
                    }
                }
                .padding(.leading, 28)
            }
        }
    }
}

struct DataStudioGroupRowView: View {
    @Bindable var session: DataStudioSession
    let group: DataStudioGroupRowItem
    @State private var displayNameDraft: String

    init(session: DataStudioSession, group: DataStudioGroupRowItem) {
        self.session = session
        self.group = group
        _displayNameDraft = State(initialValue: Self.resolvedDisplayName(for: group))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                TextField("Group Name", text: $displayNameDraft)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.semibold))
                    .onChange(of: displayNameDraft) { _, newValue in
                        session.updateDisplayName(for: group.workbook.response.workbookPath, to: newValue)
                    }

                Toggle("", isOn: includeBinding)
                    .labelsHidden()
                    .toggleStyle(.checkbox)

                Menu {
                    Button("Reveal Workbook") {
                        session.focusWorkbook(path: group.workbook.response.workbookPath)
                        session.revealFocusedWorkbook()
                    }
                    Button("Open Workbook") {
                        session.focusWorkbook(path: group.workbook.response.workbookPath)
                        session.openFocusedWorkbook()
                    }
                    Divider()
                    Button("Remove Group", role: .destructive) {
                        session.removeWorkbook(path: group.workbook.response.workbookPath)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
            }

            HStack(spacing: 8) {
                badge(title: session.displayedReplicateBadge(for: group.workbook), tint: .secondary)

                if let editedBadge = session.specimenFilterPresentation(for: group.workbook.response.workbookPath).rowBadge {
                    badge(title: editedBadge, tint: .orange)
                }

                if session.workbookHasWarnings(group.workbook) {
                    badge(title: "Warning", tint: .orange)
                }
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Reveal Workbook") {
                session.focusWorkbook(path: group.workbook.response.workbookPath)
                session.revealFocusedWorkbook()
            }
            Button("Open Workbook") {
                session.focusWorkbook(path: group.workbook.response.workbookPath)
                session.openFocusedWorkbook()
            }
            Divider()
            Button("Remove Group", role: .destructive) {
                session.removeWorkbook(path: group.workbook.response.workbookPath)
            }
        }
        .onChange(of: group.state.displayName) { _, newValue in
            let resolved = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Self.resolvedDisplayName(for: group)
                : newValue
            if resolved != displayNameDraft {
                displayNameDraft = resolved
            }
        }
    }

    private var includeBinding: Binding<Bool> {
        Binding(
            get: { group.state.includeInCompare },
            set: { session.updateCompareInclusion(for: group.workbook.response.workbookPath, includeInCompare: $0) }
        )
    }

    private func badge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }

    private static func resolvedDisplayName(for group: DataStudioGroupRowItem) -> String {
        let override = group.state.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            return override
        }
        let stem = group.workbook.workbookURL
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stem.isEmpty {
            return stem
        }
        return group.workbook.response.label
    }
}
