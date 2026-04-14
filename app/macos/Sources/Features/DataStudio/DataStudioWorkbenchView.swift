import SwiftUI
import UniformTypeIdentifiers

struct DataStudioWorkbenchView: View {
    @Bindable var session: DataStudioSession
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.focusedWorkbook != nil {
                topBar
            }

            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
            }

            HSplitView {
                DataStudioGroupRailView(session: session)
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity)

                DataStudioPreviewWorkspaceView(session: session)
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            session.attachUndoManager(undoManager)
        }
        .task {
            if session.templates.isEmpty {
                await session.refreshTemplates()
            }
        }
        .fileImporter(
            isPresented: importerBinding,
            allowedContentTypes: allowedImportTypes,
            allowsMultipleSelection: true
        ) { result in
            session.handleImportPanelResult(result)
        }
        .sheet(isPresented: importWizardBinding) {
            DataStudioImportWizardSheet(session: session)
        }
        .sheet(isPresented: guideBinding) {
            DataStudioGuideSheet(session: session)
        }
    }

    private var topBar: some View {
        let isBusyActivity = session.currentActivity != .idle
        return HStack(alignment: .center, spacing: 12) {
            Text(session.focusTitle)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 16)

            Image(systemName: activitySymbol)
                .symbolEffect(
                    .pulse.byLayer,
                    options: .repeating,
                    value: isBusyActivity
                )
                .font(.headline)
                .foregroundStyle(session.errorMessage == nil ? Color.secondary : Color.orange)
        }
    }

    private var activitySymbol: String {
        if session.errorMessage != nil {
            return "exclamationmark.triangle.fill"
        }
        switch session.currentActivity {
        case .previewingComparison, .idle:
            return session.previewStatusSymbol
        case .loadingTemplates, .previewingSource, .creatingTemplate, .buildingWorkbook, .importingWorkbooks, .exportingComparison:
            return "arrow.triangle.2.circlepath"
        }
    }

    private var allowedImportTypes: [UTType] {
        switch session.pendingImportKind {
        case .rawFiles:
            return FileTypeCatalog.dataStudioRawInputs
        case .existingWorkbook:
            return FileTypeCatalog.dataStudioWorkbookInputs
        }
    }

    private var importerBinding: Binding<Bool> {
        Binding(
            get: { session.isImportPresented },
            set: { session.isImportPresented = $0 }
        )
    }

    private var importWizardBinding: Binding<Bool> {
        Binding(
            get: { session.isImportWizardPresented },
            set: { isPresented in
                if isPresented {
                    session.isImportWizardPresented = true
                } else {
                    session.dismissImportWizard()
                }
            }
        )
    }

    private var guideBinding: Binding<Bool> {
        Binding(
            get: { session.isGuidePresented },
            set: { session.isGuidePresented = $0 }
        )
    }

}

private struct DataStudioGroupRailView: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        let autoKeepAvailability = session.autoKeepAllAvailability
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Workbook Groups")
                    .font(.headline)
                Spacer()
                Button("Auto Keep 5 All") {
                    session.applySuggestedExclusionsToAllWorkbooks()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!autoKeepAvailability.isEnabled)
                .help(autoKeepAvailability.reason ?? session.autoKeepAllHelp)
                Text("\(session.orderedGroups.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if session.orderedGroups.isEmpty {
                EmptyStateCard(title: "No groups")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List(selection: focusedWorkbookSelection) {
                    ForEach(session.orderedGroups) { group in
                        DataStudioGroupRowView(session: session, group: group)
                            .tag(group.id)
                    }
                    .onMove(perform: session.moveGroups)
                }
                .listStyle(.inset)
                .animation(MotionTokens.list, value: session.orderedGroups.map(\.id))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var focusedWorkbookSelection: Binding<String?> {
        Binding(
            get: { session.focusedWorkbook?.response.workbookPath },
            set: { session.focusWorkbook(path: $0) }
        )
    }
}

private struct DataStudioGroupRowView: View {
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

private struct DataStudioPreviewWorkspaceView: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !session.orderedGroups.isEmpty {
                figureContextBar
            }

            workspaceBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var figureContextBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(session.figureFamilies) { family in
                        Button {
                            session.selectFigureFamily(id: family.id)
                        } label: {
                            Text(family.title)
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(familyBackground(selected: session.currentFigureFamily?.id == family.id), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 12) {
                if session.availableFigureTemplates.count > 1 {
                    Picker("Figure Template", selection: selectedFigureTemplateBinding) {
                        ForEach(session.availableFigureTemplates) { item in
                            Text(item.label).tag(Optional(item.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180, alignment: .leading)
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var workspaceBody: some View {
        if session.orderedGroups.isEmpty {
            EmptyStateCard(title: "No workbook groups")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.includedGroups.isEmpty {
            EmptyStateCard(title: "No groups in compare")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            if let warning = session.previewWarning {
                DataStudioInlinePreviewBanner(message: warning, stale: session.isPreviewStale) {
                    session.retryPreviewRefresh()
                }
            }

            PlotRefineView(session: session.plotSession)

            if let focusedWorkbook = session.focusedWorkbook {
                DataStudioFocusedWorkbookStrip(session: session, workbook: focusedWorkbook)
            }
        }
    }

    private var selectedFigureTemplateBinding: Binding<String?> {
        Binding(
            get: { session.currentFigureTemplateID },
            set: { newValue in
                if let newValue {
                    session.selectFigureTemplate(id: newValue)
                }
            }
        )
    }

    private func familyBackground(selected: Bool) -> Color {
        selected ? Color.accentColor.opacity(0.18) : Color(nsColor: .quaternaryLabelColor).opacity(0.12)
    }
}

private struct DataStudioFocusedWorkbookStrip: View {
    @Bindable var session: DataStudioSession
    let workbook: DataStudioWorkbookItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Focused Group")
                    .font(.headline)
                Spacer()
                DataStudioSpecimenFilterPrimaryTrigger(session: session, workbook: workbook)
            }

            if !displayedMetrics.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    ForEach(Array(displayedMetrics.prefix(3)), id: \.id) { metric in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(metric.unit.isEmpty ? metric.label : "\(metric.label) (\(metric.unit))")
                                .font(.subheadline.weight(.semibold))
                            Text(metric.mean?.formatted(.number.precision(.fractionLength(2))) ?? "n/a")
                                .font(.title3.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.quinary.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }

            if !workbook.response.warnings.isEmpty || !workbook.response.exclusions.isEmpty || !previewWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(previewWarnings.prefix(3)), id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    ForEach(Array(workbook.response.exclusions.prefix(3)), id: \.self) { exclusion in
                        Label(exclusion, systemImage: "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
    }

    private var displayedMetrics: [DataStudioMetricSummaryResponse] {
        session.displayedMetrics(for: workbook)
    }

    private var previewWarnings: [String] {
        let preview = session.workbookPreview(for: workbook.response.workbookPath)
        return !(preview?.warnings.isEmpty ?? true) ? (preview?.warnings ?? []) : workbook.response.warnings
    }
}

private struct DataStudioInlinePreviewBanner: View {
    let message: String
    let stale: Bool
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(stale ? .orange : .yellow)

            Text(message)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 12)

            Button("Retry Preview", action: retry)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background((stale ? Color.orange : Color.yellow).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct DataStudioGuideSheet: View {
    @Bindable var session: DataStudioSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    guideSection(
                        title: "Groups First",
                        text: "Each workbook row is a sample group. Rename it, reorder it, and decide whether it participates in compare."
                    )
                    guideSection(
                        title: "Import Lives in the Toolbar",
                        text: "Raw file parsing and parse template creation are now part of the import flow, not the main workspace."
                    )
                    guideSection(
                        title: "Preview Is the Main Work Surface",
                        text: "Use the figure family switch above the canvas, then refine style and axes from the Plot-style inspector."
                    )
                }
                .padding(24)
            }
            .navigationTitle("Data Studio Help")
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
