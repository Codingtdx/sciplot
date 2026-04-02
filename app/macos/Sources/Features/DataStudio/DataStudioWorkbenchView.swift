import SwiftUI
import UniformTypeIdentifiers

struct DataStudioWorkbenchView: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar

            if let errorMessage = session.errorMessage {
                compactIssueLabel(message: errorMessage)
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
            switch result {
            case let .success(urls):
                Task { await session.handleImportedFiles(urls) }
            case let .failure(error):
                session.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: importFlowBinding) {
            DataStudioImportFlowSheet(session: session)
        }
        .sheet(isPresented: importResolverBinding) {
            DataStudioImportResolverSheet(session: session)
        }
        .sheet(isPresented: guideBinding) {
            DataStudioGuideSheet(session: session)
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.focusTitle)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(session.comparisonStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            if let focusedWorkbook = session.focusedWorkbook {
                Label(
                    focusedWorkbook.response.templateMatch.label,
                    systemImage: focusedWorkbook.response.templateMatch.family == "tensile" ? "waveform.path.ecg" : "tablecells"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Label(activityLabel, systemImage: activitySymbol)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var activityLabel: String {
        switch session.currentActivity {
        case .loadingTemplates:
            return "Loading templates"
        case .previewingSource:
            return "Matching parse template"
        case .creatingTemplate:
            return "Saving parse template"
        case .buildingWorkbook:
            return "Building workbook"
        case .importingWorkbooks:
            return "Importing workbook"
        case .previewingComparison:
            return "Refreshing figure"
        case .exportingComparison:
            return "Exporting bundle"
        case .idle:
            return "Ready"
        }
    }

    private var activitySymbol: String {
        if session.errorMessage != nil {
            return "exclamationmark.triangle.fill"
        }
        if session.currentActivity == .idle {
            return "checkmark.circle"
        }
        return "arrow.triangle.2.circlepath"
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

    private var importFlowBinding: Binding<Bool> {
        Binding(
            get: { session.isImportFlowPresented },
            set: { session.isImportFlowPresented = $0 }
        )
    }

    private var importResolverBinding: Binding<Bool> {
        Binding(
            get: { session.isImportResolverPresented },
            set: { session.isImportResolverPresented = $0 }
        )
    }

    private var guideBinding: Binding<Bool> {
        Binding(
            get: { session.isGuidePresented },
            set: { session.isGuidePresented = $0 }
        )
    }

    private func compactIssueLabel(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(2)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.quinary.opacity(0.32), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct DataStudioGroupRailView: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Workbook Groups")
                    .font(.headline)
                Spacer()
                Text("\(session.orderedGroups.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if session.orderedGroups.isEmpty {
                EmptyStateCard(
                    title: "No groups yet",
                    message: "Import raw files or existing workbooks from the toolbar."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                List(selection: focusedWorkbookSelection) {
                    ForEach(session.orderedGroups) { group in
                        DataStudioGroupRowView(session: session, group: group)
                            .tag(group.id)
                    }
                    .onMove(perform: session.moveGroups)
                }
                .listStyle(.inset)
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
        _displayNameDraft = State(initialValue: group.state.displayName.isEmpty ? group.workbook.response.label : group.state.displayName)
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
            }

            HStack(spacing: 8) {
                badge(title: "\(group.workbook.response.parsedSampleCount) reps", tint: .secondary)

                if group.workbook.response.failedSampleCount > 0 || !group.workbook.response.warnings.isEmpty {
                    badge(title: "Warning", tint: .orange)
                } else {
                    badge(title: "Ready", tint: .green)
                }
            }

            if !metricSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(metricSummaries, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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
            let resolved = newValue.isEmpty ? group.workbook.response.label : newValue
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

    private var metricSummaries: [String] {
        Array(group.workbook.response.metrics.prefix(3)).map { metric in
            let value = metric.mean?.formatted(.number.precision(.fractionLength(2))) ?? "n/a"
            return "\(metric.label): \(value) \(metric.unit)"
        }
    }

    private func badge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct DataStudioPreviewWorkspaceView: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            figureContextBar

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

                Text(session.currentRecipeLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var workspaceBody: some View {
        if session.orderedGroups.isEmpty {
            EmptyStateCard(
                title: "No workbook groups",
                message: "Use the toolbar Import action to add raw files or existing workbooks."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.includedGroups.isEmpty {
            EmptyStateCard(
                title: "No groups in compare",
                message: "Turn on Compare for at least one group in the left rail."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PlotRefineView(session: session.plotSession)

            if let focusedWorkbook = session.focusedWorkbook {
                DataStudioFocusedWorkbookStrip(workbook: focusedWorkbook)
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
    let workbook: DataStudioWorkbookItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Focused Group")
                    .font(.headline)
                Spacer()
                Text(workbook.response.templateMatch.label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !workbook.response.metrics.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    ForEach(Array(workbook.response.metrics.prefix(3)), id: \.id) { metric in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(metric.label)
                                .font(.subheadline.weight(.semibold))
                            Text(metric.mean?.formatted(.number.precision(.fractionLength(2))) ?? "n/a")
                                .font(.title3.weight(.semibold))
                            Text(metric.unit)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.quinary.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }

            if !workbook.response.warnings.isEmpty || !workbook.response.exclusions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(workbook.response.warnings.prefix(3)), id: \.self) { warning in
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
}

private struct DataStudioImportFlowSheet: View {
    @Bindable var session: DataStudioSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if session.importFlowStep == .scope {
                    importScopeStep
                } else {
                    importKindStep
                }
            }
            .padding(24)
            .navigationTitle("Import into Data Studio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        session.dismissImportFlow()
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 260)
    }

    private var importScopeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This session already has workbook groups. Choose whether the next import should append to the current compare set or start a new Data Studio session.")
                .foregroundStyle(.secondary)

            Button(session.pendingImportDisposition.title) {
                session.chooseImportDisposition(.addToCurrentSession)
            }
            .buttonStyle(.borderedProminent)

            Button(DataStudioImportDisposition.startNewSession.title) {
                session.chooseImportDisposition(.startNewSession)
            }
            .buttonStyle(.bordered)
        }
    }

    private var importKindStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose whether to import raw experiment files or prepared workbooks.")
                .foregroundStyle(.secondary)

            ForEach([DataStudioImportKind.rawFiles, .existingWorkbook]) { kind in
                Button {
                    dismiss()
                    session.chooseImportKind(kind)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(kind.title)
                            .font(.headline)
                        Text(kind.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct DataStudioImportResolverSheet: View {
    @Bindable var session: DataStudioSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let preview = session.sourcePreview {
                        sourceSummary(preview: preview)
                    }

                    Picker("Resolver Mode", selection: resolverModeBinding) {
                        ForEach(DataStudioImportResolverMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if session.importResolverMode == .existingTemplate {
                        existingTemplateResolver
                    } else {
                        createTemplateResolver
                    }
                }
                .padding(24)
            }
            .navigationTitle("Resolve Parse Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        session.dismissImportResolver()
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    private func sourceSummary(preview: DataStudioRawFilePreviewResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(URL(fileURLWithPath: preview.sourcePath).lastPathComponent)
                .font(.headline)
            Text("\(preview.fileType.uppercased()) · \(preview.sheetNames.count) sheet(s) · \(preview.fieldCandidates.count) recommended region(s)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !session.sourceMatches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommended Parse Templates")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(session.sourceMatches) { match in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(match.label)
                                    .font(.footnote.weight(.medium))
                                Text(match.confidence.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let reason = match.reasons.first {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
    }

    private var existingTemplateResolver: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Parse Template", selection: selectedTemplateBinding) {
                ForEach(session.templates) { template in
                    Text(template.label).tag(Optional(template.id))
                }
            }
            .pickerStyle(.menu)

            if !session.sourceMatches.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Match reasoning")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(session.sourceMatches) { match in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(match.label)
                                    .font(.body.weight(.semibold))
                                Text(match.family)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(match.reasons, id: \.self) { reason in
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Use Selected Template") {
                    Task {
                        dismiss()
                        await session.importWithSelectedTemplate()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.selectedTemplateID == nil)
            }
        }
    }

    private var createTemplateResolver: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Template Name", text: $session.templateDraftLabel)
                .textFieldStyle(.roundedBorder)

            TextField("Template Description", text: $session.templateDraftDescription, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 10) {
                Text("Recommended Regions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let preview = session.sourcePreview, !preview.fieldCandidates.isEmpty {
                    ForEach(preview.fieldCandidates) { candidate in
                        Toggle(isOn: candidateSelectionBinding(candidate.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(candidate.label)
                                        .font(.body.weight(.semibold))
                                    Text(candidate.kind.replacingOccurrences(of: "_", with: " "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(candidate.confidence.formatted(.percent.precision(.fractionLength(0))))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(candidate.rationale)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }

                    previewBlockList(preview)
                } else {
                    Text("No candidate regions were returned for this sample file.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button("Save Template and Import") {
                    Task {
                        dismiss()
                        await session.createTemplateAndImport()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.selectedCandidateIDs.isEmpty || session.templateDraftLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func previewBlockList(_ preview: DataStudioRawFilePreviewResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sample Blocks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(preview.sheets, id: \.sheetName) { sheet in
                VStack(alignment: .leading, spacing: 10) {
                    Text(sheet.sheetName)
                        .font(.subheadline.weight(.semibold))
                    ForEach(sheet.blocks, id: \.id) { block in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(block.label)
                                    .font(.footnote.weight(.semibold))
                                Spacer()
                                Text("\(block.rowCount) × \(block.colCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            sampleGrid(rows: block.sampleRows)
                        }
                        .padding(12)
                        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    private func sampleGrid(rows: [[JSONValue]]) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        Text("\(index + 1)")
                            .foregroundStyle(.secondary)
                        ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                            Text(value.displayString)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var selectedTemplateBinding: Binding<String?> {
        Binding(
            get: { session.selectedTemplateID },
            set: { session.selectedTemplateID = $0 }
        )
    }

    private var resolverModeBinding: Binding<DataStudioImportResolverMode> {
        Binding(
            get: { session.importResolverMode },
            set: { session.importResolverMode = $0 }
        )
    }

    private func candidateSelectionBinding(_ candidateID: String) -> Binding<Bool> {
        Binding(
            get: { session.selectedCandidateIDs.contains(candidateID) },
            set: { newValue in
                if newValue {
                    if !session.selectedCandidateIDs.contains(candidateID) {
                        session.selectedCandidateIDs.append(candidateID)
                    }
                } else {
                    session.selectedCandidateIDs.removeAll { $0 == candidateID }
                }
            }
        )
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
