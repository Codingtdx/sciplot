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
            session.handleImportPanelResult(result)
        }
        .sheet(isPresented: importScopeBinding) {
            DataStudioImportScopeSheet(session: session)
        }
        .sheet(isPresented: importChooserBinding) {
            DataStudioImportChooserSheet(session: session)
        }
        .sheet(isPresented: importResolverBinding) {
            DataStudioImportResolverSheet(session: session)
        }
        .sheet(isPresented: createTemplateEditorBinding) {
            DataStudioCreateTemplateEditorSheet(session: session)
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

    private var importScopeBinding: Binding<Bool> {
        Binding(
            get: { session.isImportScopePresented },
            set: { isPresented in
                if isPresented {
                    session.isImportScopePresented = true
                } else {
                    session.dismissImportScope()
                }
            }
        )
    }

    private var importChooserBinding: Binding<Bool> {
        Binding(
            get: { session.isImportChooserPresented },
            set: { isPresented in
                if isPresented {
                    session.isImportChooserPresented = true
                } else {
                    session.dismissImportChooser()
                }
            }
        )
    }

    private var importResolverBinding: Binding<Bool> {
        Binding(
            get: { session.isImportResolverPresented },
            set: { isPresented in
                if isPresented {
                    session.isImportResolverPresented = true
                } else {
                    session.dismissImportResolver()
                }
            }
        )
    }

    private var createTemplateEditorBinding: Binding<Bool> {
        Binding(
            get: { session.isCreateTemplateEditorPresented },
            set: { isPresented in
                if isPresented {
                    session.isCreateTemplateEditorPresented = true
                } else {
                    session.dismissCreateTemplateEditor()
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
                VStack(alignment: .leading, spacing: 8) {
                    if let hint = session.groupRailEmptyHint {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
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

private struct DataStudioImportScopeSheet: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DataStudioSheetHeader(
                title: "Start Import",
                subtitle: "Choose whether the next import should extend the current comparison session or begin a new one."
            )

            Divider()

            VStack(spacing: 10) {
                DataStudioSheetOptionRow(
                    symbol: "plus.rectangle.on.rectangle",
                    title: DataStudioImportDisposition.addToCurrentSession.title,
                    detail: "Keep the current workbook groups and append the new import to this session."
                ) {
                    session.chooseImportDisposition(.addToCurrentSession)
                }

                DataStudioSheetOptionRow(
                    symbol: "sparkles.rectangle.stack",
                    title: DataStudioImportDisposition.startNewSession.title,
                    detail: "Clear current workbook group display state and start a fresh Data Studio session."
                ) {
                    session.chooseImportDisposition(.startNewSession)
                }
            }
            .padding(18)

            Divider()

            DataStudioSheetFooter {
                Button("Cancel") {
                    session.dismissImportScope()
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
            DataStudioSheetHeader(
                title: "Import into Data Studio",
                subtitle: "Choose whether to import source files or prepared workbooks."
            )

            Divider()

            VStack(spacing: 10) {
                DataStudioSheetOptionRow(
                    symbol: "tray.and.arrow.down",
                    title: DataStudioImportKind.rawFiles.title,
                    detail: "Import source csv / txt / xls / xlsx files and let Data Studio match or create a parse template."
                ) {
                    session.chooseImportKind(.rawFiles)
                }

                DataStudioSheetOptionRow(
                    symbol: "tablecells",
                    title: DataStudioImportKind.existingWorkbook.title,
                    detail: "Import a prepared workbook directly into the current workbook group list and compare context."
                ) {
                    session.chooseImportKind(.existingWorkbook)
                }
            }
            .padding(18)

            Divider()

            DataStudioSheetFooter {
                Button("Cancel") {
                    session.dismissImportChooser()
                }
            }
        }
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DataStudioImportResolverSheet: View {
    @Bindable var session: DataStudioSession

    private var recommendedMatches: [DataStudioTemplateMatchResponse] {
        session.sourceMatches.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            return lhs.confidence > rhs.confidence
        }
    }

    private var otherTemplates: [DataStudioTemplateResponse] {
        let matchedIDs = Set(recommendedMatches.map(\.templateID))
        return session.templates
            .filter { !matchedIDs.contains($0.id) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            resolverHeader

            Divider()

            if recommendedMatches.isEmpty && otherTemplates.isEmpty {
                ContentUnavailableView(
                    "No Parse Templates Available",
                    systemImage: "questionmark.folder",
                    description: Text("Create a new parse template for this file to continue importing.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: selectedTemplateBinding) {
                    if !recommendedMatches.isEmpty {
                        Section("Recommended Templates") {
                            ForEach(recommendedMatches) { match in
                                DataStudioResolverTemplateRow(
                                    title: match.label,
                                    family: match.family,
                                    reason: match.reasons.first ?? "Matched the current file structure.",
                                    warning: match.warnings.first
                                )
                                .tag(Optional(match.templateID))
                            }
                        }
                    }

                    if !otherTemplates.isEmpty {
                        Section("Other Available Templates") {
                            ForEach(otherTemplates) { template in
                                DataStudioResolverTemplateRow(
                                    title: template.label,
                                    family: template.family,
                                    reason: template.description,
                                    warning: nil
                                )
                                .tag(Optional(template.id))
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            DataStudioSheetFooter {
                Button("Cancel") {
                    session.dismissImportResolver()
                }

                Spacer()

                Button("Create New Parse Template") {
                    session.beginCreateTemplateEditor()
                }
                .buttonStyle(.bordered)

                Button("Use Selected Template") {
                    Task { await session.importWithSelectedTemplate() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.selectedTemplateID == nil)
            }
        }
        .frame(minWidth: 620, idealWidth: 620, minHeight: 430, idealHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var resolverHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resolve Parse Template")
                .font(.headline)

            if let preview = session.sourcePreview {
                Text(URL(fileURLWithPath: preview.sourcePath).lastPathComponent)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Text(sourceSummary(for: preview))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Label("No unique parse template match", systemImage: "exclamationmark.circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var selectedTemplateBinding: Binding<String?> {
        Binding(
            get: { session.selectedTemplateID },
            set: { session.selectedTemplateID = $0 }
        )
    }

    private func sourceSummary(for preview: DataStudioRawFilePreviewResponse) -> String {
        let blockCount = preview.sheets.reduce(into: 0) { partialResult, sheet in
            partialResult += sheet.blocks.count
        }
        let hasCurveLikeBlock = preview.bindingSuggestions.contains(where: { $0.kind == "curve_pair" })
        var pieces = ["\(blockCount) data block(s)"]
        pieces.append(hasCurveLikeBlock ? "Curve-like block detected" : "No clear curve block detected")
        return pieces.joined(separator: " · ")
    }
}

private struct DataStudioCreateTemplateEditorSheet: View {
    @Bindable var session: DataStudioSession

    private var preview: DataStudioRawFilePreviewResponse? {
        session.sourcePreview
    }

    private var selectedBlock: DataStudioSheetBlockResponse? {
        guard let preview else {
            return nil
        }
        for sheet in preview.sheets {
            if let explicitID = session.selectedPreviewBlockID,
               let block = sheet.blocks.first(where: { $0.id == explicitID })
            {
                return block
            }
        }
        return preview.sheets.first?.blocks.first
    }

    private var suggestions: [DataStudioBindingSuggestionResponse] {
        session.createTemplateSuggestions
    }

    private var curveSuggestion: DataStudioBindingSuggestionResponse? {
        session.createTemplatePrimaryCurveSuggestion
    }

    private var metricSuggestion: DataStudioBindingSuggestionResponse? {
        session.createTemplatePrimaryMetricSuggestion
    }

    private var metadataSuggestion: DataStudioBindingSuggestionResponse? {
        session.createTemplatePrimaryMetadataSuggestion
    }

    private var structureSuggestion: DataStudioBindingSuggestionResponse? {
        session.createTemplatePrimaryStructureSuggestion
    }

    private var selectedSummaryItems: [DataStudioTemplateSummaryItem] {
        session.selectedTemplateSummaryItems
    }

    private var advancedCandidates: [DataStudioFieldCandidateResponse] {
        guard let preview else {
            return []
        }
        let suggestedCandidateIDs = Set(suggestions.flatMap(\.candidateIDs))
        return preview.fieldCandidates
            .filter { !suggestedCandidateIDs.contains($0.id) }
            .sorted(by: candidateComparator)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorHeader

            Divider()

            HSplitView {
                previewColumn
                    .frame(minWidth: 340, idealWidth: 380, maxWidth: 430, maxHeight: .infinity)

                editorColumn
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            DataStudioSheetFooter {
                Button("Cancel") {
                    session.dismissCreateTemplateEditor()
                }

                Spacer()

                Button("Save Template") {
                    Task { await session.saveTemplateDraft() }
                }
                .buttonStyle(.bordered)
                .disabled(saveDisabled)

                Button("Save Template and Continue Import") {
                    Task { await session.saveTemplateAndContinueImport() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveDisabled)
            }
        }
        .frame(minWidth: 1000, idealWidth: 1040, minHeight: 660, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var saveDisabled: Bool {
        session.selectedCandidateIDs.isEmpty || session.templateDraftLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create Parse Template")
                .font(.headline)

            if let preview {
                Text(URL(fileURLWithPath: preview.sourcePath).lastPathComponent)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text("Confirm the recommended table bindings, then save this structure as a reusable parse template.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Blocks") {
                if let preview {
                    List(selection: selectedBlockBinding) {
                        ForEach(preview.sheets, id: \.sheetName) { sheet in
                            Section(sheet.sheetName) {
                                ForEach(sheet.blocks, id: \.id) { block in
                                    DataStudioPreviewBlockRow(block: block)
                                        .tag(Optional(block.id))
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 180, maxHeight: 240)
                } else {
                    Text("No blocks detected for this source file.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Table Preview") {
                if let block = selectedBlock {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(block.label)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(block.rowCount) × \(block.colCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let previewCaption = session.createTemplatePreviewCaption {
                            Text(previewCaption)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        KeyValueGrid(values: [
                            ("Sheet", block.sheetName),
                            ("Header Row", block.headerRowIndex.map { String($0 + 1) } ?? "Not detected"),
                            ("Unit Row", block.unitRowIndex.map { String($0 + 1) } ?? "Not detected"),
                            ("Data Starts", block.dataStartRowIndex.map { String($0 + 1) } ?? "Not detected"),
                        ])

                        DataStudioBlockTablePreview(
                            block: block,
                            hoveredRanges: session.hoveredPreviewRanges,
                            selectedRanges: session.pinnedPreviewRanges
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Select a detected block to preview the sample table.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(18)
    }

    private var editorColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Template") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Template Name", text: $session.templateDraftLabel)
                            .textFieldStyle(.roundedBorder)
                        TextField("Template Description", text: $session.templateDraftDescription, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let curveSuggestion {
                    GroupBox("Recommended Curve") {
                        DataStudioCurveSuggestionHeroCard(
                            session: session,
                            suggestion: curveSuggestion,
                            xLabel: curveAxisLabel(for: curveSuggestion, kind: "curve_x"),
                            yLabel: curveAxisLabel(for: curveSuggestion, kind: "curve_y"),
                            location: previewLocation(for: curveSuggestion)
                        )
                    }
                }

                if let metricSuggestion {
                    GroupBox("Recommended Metrics") {
                        DataStudioSuggestionResultCard(
                            session: session,
                            suggestion: metricSuggestion,
                            accentColor: .green,
                            location: nil,
                            values: displayValues(for: metricSuggestion, kinds: ["metric"], includeUnits: false, limit: 4)
                        )
                    }
                }

                if let metadataSuggestion {
                    GroupBox("Recommended Metadata") {
                        DataStudioSuggestionResultCard(
                            session: session,
                            suggestion: metadataSuggestion,
                            accentColor: .cyan,
                            location: nil,
                            values: displayValues(for: metadataSuggestion, kinds: ["metadata"], includeUnits: false, limit: 3)
                        )
                    }
                }

                if let structureSuggestion {
                    GroupBox("Detected Structure") {
                        DataStudioSuggestionResultCard(
                            session: session,
                            suggestion: structureSuggestion,
                            accentColor: .orange,
                            location: nil,
                            values: structureValues(for: structureSuggestion)
                        )
                    }
                }

                GroupBox("Selected for Template") {
                    if selectedSummaryItems.isEmpty && session.selectedCandidateIDs.isEmpty {
                        Text("Click the recommendations you want to keep in this parse template.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            if !selectedSummaryItems.isEmpty {
                                ForEach(selectedSummaryItems) { item in
                                    LabeledContent(item.title) {
                                        Text(item.value)
                                            .font(.footnote)
                                            .multilineTextAlignment(.trailing)
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }

                            let advancedSelections = advancedCandidates.filter { session.selectedCandidateIDs.contains($0.id) }
                            if !advancedSelections.isEmpty {
                                Divider()
                                Text("Additional Advanced Fields")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                DataStudioCandidateSectionList(
                                    session: session,
                                    candidates: advancedSelections,
                                    compact: true
                                )
                            }
                        }
                    }
                }

                if !session.createTemplateSecondaryCurveSuggestions.isEmpty || !advancedCandidates.isEmpty || preview != nil {
                    GroupBox {
                        DisclosureGroup("Advanced", isExpanded: $session.showAdvancedCandidates) {
                            VStack(alignment: .leading, spacing: 14) {
                                if !session.createTemplateSecondaryCurveSuggestions.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Other Possible Curves")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        ForEach(session.createTemplateSecondaryCurveSuggestions) { suggestion in
                                            DataStudioCurveSuggestionHeroCard(
                                                session: session,
                                                suggestion: suggestion,
                                                xLabel: curveAxisLabel(for: suggestion, kind: "curve_x"),
                                                yLabel: curveAxisLabel(for: suggestion, kind: "curve_y"),
                                                location: previewLocation(for: suggestion),
                                                compact: true
                                            )
                                        }
                                    }
                                }

                                if !advancedCandidates.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Manual Candidate Overrides")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        DataStudioCandidateSectionList(
                                            session: session,
                                            candidates: advancedCandidates
                                        )
                                    }
                                }

                                if let preview {
                                    DataStudioTechnicalDetailsDisclosure(preview: preview)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private var selectedBlockBinding: Binding<String?> {
        Binding(
            get: { session.selectedPreviewBlockID ?? selectedBlock?.id },
            set: { newValue in
                guard let newValue else {
                    return
                }
                session.selectPreviewBlock(id: newValue)
            }
        )
    }

    private func candidateComparator(_ lhs: DataStudioFieldCandidateResponse, _ rhs: DataStudioFieldCandidateResponse) -> Bool {
        if lhs.confidence == rhs.confidence {
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
        return lhs.confidence > rhs.confidence
    }

    private func curveAxisLabel(
        for suggestion: DataStudioBindingSuggestionResponse,
        kind: String
    ) -> String {
        let candidateIDs = Set(suggestion.candidateIDs)
        for candidate in preview?.fieldCandidates ?? [] where candidateIDs.contains(candidate.id) && candidate.kind == kind {
            if let unitHint = candidate.unitHint,
               !unitHint.isEmpty,
               !candidate.label.localizedCaseInsensitiveContains(unitHint)
            {
                return "\(candidate.label) (\(unitHint))"
            }
            return candidate.label
        }
        return kind == "curve_x" ? "X Column" : "Y Column"
    }

    private func displayValues(
        for suggestion: DataStudioBindingSuggestionResponse,
        kinds: Set<String>,
        includeUnits: Bool,
        limit: Int
    ) -> [String] {
        let candidateIDs = Set(suggestion.candidateIDs)
        let labels = (preview?.fieldCandidates ?? [])
            .filter { candidateIDs.contains($0.id) && kinds.contains($0.kind) }
            .map { candidate in
                if includeUnits,
                   let unitHint = candidate.unitHint,
                   !unitHint.isEmpty,
                   !candidate.label.localizedCaseInsensitiveContains(unitHint)
                {
                    return "\(candidate.label) (\(unitHint))"
                }
                return candidate.label
            }
        guard labels.count > limit else {
            return labels
        }
        return Array(labels.prefix(limit)) + ["+\(labels.count - limit) more"]
    }

    private func structureValues(for suggestion: DataStudioBindingSuggestionResponse) -> [String] {
        let ranges = suggestion.previewRanges.sorted { lhs, rhs in
            if lhs.startRow == rhs.startRow {
                return lhs.role < rhs.role
            }
            return lhs.startRow < rhs.startRow
        }
        var values: [String] = []
        for range in ranges {
            switch range.role {
            case "header_row":
                values.append("Header Row \(range.startRow + 1)")
            case "unit_row":
                values.append("Unit Row \(range.startRow + 1)")
            default:
                continue
            }
        }
        return values
    }

    private func previewLocation(for suggestion: DataStudioBindingSuggestionResponse) -> String {
        if let blockID = suggestion.blockID {
            for sheet in preview?.sheets ?? [] where sheet.sheetName == suggestion.sheetName {
                if let block = sheet.blocks.first(where: { $0.id == blockID }) {
                    return "\(sheet.sheetName) / \(block.label)"
                }
            }
        }
        return suggestion.sheetName
    }
}

private struct DataStudioSheetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

private struct DataStudioSheetFooter<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DataStudioSheetOptionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DataStudioResolverTemplateRow: View {
    let title: String
    let family: String
    let reason: String
    let warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(family.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(warning == nil ? "Use Template" : "Review")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let warning, !warning.isEmpty {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DataStudioPreviewBlockRow: View {
    let block: DataStudioSheetBlockResponse

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.label)
                    .font(.body)
                Text("\(block.rowCount) × \(block.colCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if block.headerRowIndex != nil {
                Image(systemName: "tablecells.badge.ellipsis")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DataStudioCurveSuggestionHeroCard: View {
    @Bindable var session: DataStudioSession
    let suggestion: DataStudioBindingSuggestionResponse
    let xLabel: String
    let yLabel: String
    let location: String
    var compact = false

    private var isSelected: Bool {
        session.selectedSuggestionIDs.contains(suggestion.id)
    }

    private var isPreviewing: Bool {
        session.hoveredSuggestionID == suggestion.id
    }

    var body: some View {
        Button {
            session.toggleSuggestion(id: suggestion.id)
        } label: {
            VStack(alignment: .leading, spacing: compact ? 10 : 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label("Recommended Curve", systemImage: "waveform.path")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if isPreviewing {
                        statusCapsule(text: "Previewing", tint: .blue)
                    }
                    if isSelected {
                        statusCapsule(text: "Selected", tint: .accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                    axisRow(axis: "X", label: xLabel, tint: .blue)
                    axisRow(axis: "Y", label: yLabel, tint: .orange)
                }

                Text(location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(compact ? 12 : 14)
            .background(backgroundFill, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            session.setHoveredSuggestion(id: isHovering ? suggestion.id : nil)
        }
    }

    private var backgroundFill: Color {
        if isPreviewing {
            return Color.blue.opacity(0.14)
        }
        return isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isPreviewing {
            return .blue.opacity(0.9)
        }
        if isSelected {
            return Color.accentColor.opacity(0.75)
        }
        return Color(nsColor: .separatorColor).opacity(0.45)
    }

    private var borderWidth: CGFloat {
        if isPreviewing {
            return 2
        }
        return isSelected ? 1.4 : 1
    }

    private func axisRow(axis: String, label: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(axis)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(tint, in: Capsule())
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }

    private func statusCapsule(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct DataStudioSuggestionResultCard: View {
    @Bindable var session: DataStudioSession
    let suggestion: DataStudioBindingSuggestionResponse
    let accentColor: Color
    let location: String?
    let values: [String]

    private var isSelected: Bool {
        session.selectedSuggestionIDs.contains(suggestion.id)
    }

    private var isPreviewing: Bool {
        session.hoveredSuggestionID == suggestion.id
    }

    var body: some View {
        Button {
            session.toggleSuggestion(id: suggestion.id)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: iconName)
                        .foregroundStyle(accentColor)
                    Spacer()
                    if isPreviewing {
                        statusCapsule(text: "Previewing", tint: accentColor)
                    }
                    if isSelected {
                        statusCapsule(text: "Selected", tint: .accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(accentColor.opacity(0.85))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(value)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }

                if let location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(backgroundFill, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            session.setHoveredSuggestion(id: isHovering ? suggestion.id : nil)
        }
    }

    private var iconName: String {
        switch suggestion.kind {
        case "metric_group":
            return "chart.bar.xaxis"
        case "metadata_group":
            return "tag"
        case "structure_rows":
            return "tablecells"
        default:
            return "sparkles.rectangle.stack"
        }
    }

    private var backgroundFill: Color {
        if isPreviewing {
            return accentColor.opacity(0.14)
        }
        return isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isPreviewing {
            return accentColor.opacity(0.9)
        }
        if isSelected {
            return Color.accentColor.opacity(0.75)
        }
        return Color(nsColor: .separatorColor).opacity(0.45)
    }

    private var borderWidth: CGFloat {
        if isPreviewing {
            return 2
        }
        return isSelected ? 1.4 : 1
    }

    private func statusCapsule(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct DataStudioTechnicalDetailsDisclosure: View {
    let preview: DataStudioRawFilePreviewResponse

    var body: some View {
        DisclosureGroup("Technical Details") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("File Type", value: preview.fileType.uppercased())
                LabeledContent("Sheets", value: "\(preview.sheets.count)")
                if let encoding = preview.encoding, !encoding.isEmpty {
                    LabeledContent("Encoding", value: encoding)
                }
                if let delimiter = preview.delimiter, !delimiter.isEmpty {
                    LabeledContent("Delimiter", value: delimiter)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        }
    }
}

private struct DataStudioCandidateSectionList: View {
    @Bindable var session: DataStudioSession
    let candidates: [DataStudioFieldCandidateResponse]
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                if index > 0 {
                    Divider()
                }
                DataStudioCandidateRow(
                    session: session,
                    candidate: candidate,
                    compact: compact
                )
                .padding(.vertical, compact ? 6 : 8)
            }
        }
    }
}

private struct DataStudioCandidateRow: View {
    @Bindable var session: DataStudioSession
    let candidate: DataStudioFieldCandidateResponse
    var compact: Bool

    var body: some View {
        Toggle(isOn: candidateSelectionBinding) {
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(candidate.label)
                        .font(.body.weight(.semibold))
                    Text(candidate.kindLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(candidate.confidence.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(candidate.sheetName)
                    if let blockID = candidate.blockID {
                        Text(blockID)
                    }
                    if let unitHint = candidate.unitHint, !unitHint.isEmpty {
                        Text(unitHint)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !compact {
                    Text(candidate.rationale)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !candidate.sampleValues.isEmpty {
                        Text(candidate.sampleValues.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
    }

    private var candidateSelectionBinding: Binding<Bool> {
        Binding(
            get: { session.selectedCandidateIDs.contains(candidate.id) },
            set: { newValue in
                session.setCandidateSelection(id: candidate.id, isSelected: newValue)
            }
        )
    }
}

private struct DataStudioBlockTablePreview: View {
    let block: DataStudioSheetBlockResponse
    let hoveredRanges: [DataStudioPreviewRangeResponse]
    let selectedRanges: [DataStudioPreviewRangeResponse]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    tableHeaderCell("", hoveredRoles: [], selectedRoles: [])
                        .frame(width: 44)
                    ForEach(0 ..< columnCount, id: \.self) { column in
                        tableHeaderCell(
                            columnLabel(for: column),
                            hoveredRoles: columnRoles(for: column, in: hoveredRanges),
                            selectedRoles: columnRoles(for: column, in: selectedRanges)
                        )
                            .frame(minWidth: 110, maxWidth: 140)
                    }
                }

                ForEach(Array(block.sampleRows.enumerated()), id: \.offset) { rowOffset, row in
                    HStack(spacing: 0) {
                        tableRowIndexCell(
                            rowNumber(for: rowOffset),
                            hoveredRoles: rowRoles(for: rowOffset, in: hoveredRanges),
                            selectedRoles: rowRoles(for: rowOffset, in: selectedRanges)
                        )
                            .frame(width: 44)
                        ForEach(0 ..< columnCount, id: \.self) { column in
                            tableDataCell(
                                value: column < row.count ? row[column].displayString : "",
                                rowOffset: rowOffset,
                                columnOffset: column
                            )
                            .frame(minWidth: 110, maxWidth: 140, minHeight: 30, alignment: .leading)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.22))
            )
        }
        .frame(minHeight: 320)
    }

    private var columnCount: Int {
        max(block.colCount, block.sampleRows.map(\.count).max() ?? 0)
    }

    private func tableHeaderCell(
        _ text: String,
        hoveredRoles: [String],
        selectedRoles: [String]
    ) -> some View {
        let highlight = highlightState(hoveredRoles: hoveredRoles, selectedRoles: selectedRoles)
        return VStack(spacing: 4) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let badgeRole = preferredBadgeRole(from: highlight.roles) {
                roleBadge(for: badgeRole, compact: true)
            } else {
                Spacer()
                    .frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(highlight.fill)
        .overlay(Rectangle().stroke(highlight.stroke, lineWidth: highlight.lineWidth))
    }

    private func tableRowIndexCell(
        _ text: String,
        hoveredRoles: [String],
        selectedRoles: [String]
    ) -> some View {
        let highlight = highlightState(hoveredRoles: hoveredRoles, selectedRoles: selectedRoles)
        return VStack(spacing: 3) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let badgeRole = preferredBadgeRole(from: highlight.roles) {
                roleBadge(for: badgeRole, compact: true)
            } else {
                Spacer()
                    .frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(highlight.fill)
        .overlay(Rectangle().stroke(highlight.stroke, lineWidth: highlight.lineWidth))
    }

    private func tableDataCell(value: String, rowOffset: Int, columnOffset: Int) -> some View {
        let hoveredRoles = matchingRoles(rowOffset: rowOffset, columnOffset: columnOffset, in: hoveredRanges)
        let selectedRoles = matchingRoles(rowOffset: rowOffset, columnOffset: columnOffset, in: selectedRanges)
        let highlight = highlightState(hoveredRoles: hoveredRoles, selectedRoles: selectedRoles)
        return Text(value)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlight.fill)
            .overlay(
                Rectangle()
                    .stroke(highlight.stroke, lineWidth: highlight.lineWidth)
            )
    }

    private func matchingRoles(
        rowOffset: Int,
        columnOffset: Int,
        in ranges: [DataStudioPreviewRangeResponse]
    ) -> [String] {
        let absoluteRow = block.range.startRow + rowOffset
        let absoluteColumn = block.range.startCol + columnOffset
        let ordered = ranges.filter { range in
            range.sheetName == block.sheetName &&
            (range.blockID == nil || range.blockID == block.id) &&
            absoluteRow >= range.startRow &&
            absoluteRow <= range.endRow &&
            absoluteColumn >= range.startCol &&
            absoluteColumn <= range.endCol
        }
        return ordered
            .map(\.role)
            .sorted { rolePriority($0) < rolePriority($1) }
    }

    private func columnRoles(for columnOffset: Int, in ranges: [DataStudioPreviewRangeResponse]) -> [String] {
        let absoluteColumn = block.range.startCol + columnOffset
        return ranges
            .filter { range in
                range.sheetName == block.sheetName &&
                (range.blockID == nil || range.blockID == block.id) &&
                !["header_row", "unit_row"].contains(range.role) &&
                absoluteColumn >= range.startCol &&
                absoluteColumn <= range.endCol
            }
            .map(\.role)
            .sorted { rolePriority($0) < rolePriority($1) }
    }

    private func rowRoles(for rowOffset: Int, in ranges: [DataStudioPreviewRangeResponse]) -> [String] {
        let absoluteRow = block.range.startRow + rowOffset
        return ranges
            .filter { range in
                range.sheetName == block.sheetName &&
                (range.blockID == nil || range.blockID == block.id) &&
                ["header_row", "unit_row"].contains(range.role) &&
                absoluteRow >= range.startRow &&
                absoluteRow <= range.endRow
            }
            .map(\.role)
            .sorted { rolePriority($0) < rolePriority($1) }
    }

    private func highlightState(
        hoveredRoles: [String],
        selectedRoles: [String]
    ) -> (roles: [String], fill: Color, stroke: Color, lineWidth: CGFloat) {
        if let role = hoveredRoles.first {
            let accent = color(forRole: role)
            return (hoveredRoles, accent.opacity(0.24), accent.opacity(0.98), 2)
        }
        if let role = selectedRoles.first {
            let accent = color(forRole: role)
            return (selectedRoles, accent.opacity(0.14), accent.opacity(0.74), 1.35)
        }
        return ([], Color(nsColor: .windowBackgroundColor), Color(nsColor: .separatorColor).opacity(0.35), 0.5)
    }

    private func preferredBadgeRole(from roles: [String]) -> String? {
        if roles.contains("x") {
            return "x"
        }
        if roles.contains("y") {
            return "y"
        }
        if roles.contains("metric") {
            return "metric"
        }
        if roles.contains("metadata") {
            return "metadata"
        }
        if roles.contains("header_row") {
            return "header_row"
        }
        if roles.contains("unit_row") {
            return "unit_row"
        }
        return nil
    }

    private func rolePriority(_ role: String) -> Int {
        switch role {
        case "x":
            return 0
        case "y":
            return 1
        case "metric":
            return 2
        case "metadata":
            return 3
        case "header_row":
            return 4
        case "unit_row":
            return 5
        default:
            return 9
        }
    }

    private func roleBadge(for role: String, compact: Bool) -> some View {
        Text(roleBadgeLabel(for: role))
            .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 2 : 4)
            .background(color(forRole: role), in: Capsule())
    }

    private func roleBadgeLabel(for role: String) -> String {
        switch role {
        case "x":
            return "X"
        case "y":
            return "Y"
        case "metric":
            return "Metric"
        case "metadata":
            return "Meta"
        case "header_row":
            return "Header"
        case "unit_row":
            return "Unit"
        default:
            return role
        }
    }

    private func color(forRole role: String) -> Color {
        switch role {
        case "x":
            return .blue
        case "y":
            return .orange
        case "metric":
            return .green
        case "metadata":
            return .cyan
        case "header_row", "unit_row":
            return .orange
        default:
            return .secondary
        }
    }

    private func rowNumber(for rowOffset: Int) -> String {
        String(block.range.startRow + rowOffset + 1)
    }

    private func columnLabel(for offset: Int) -> String {
        let absolute = block.range.startCol + offset
        return spreadsheetColumnLabel(for: absolute)
    }

    private func spreadsheetColumnLabel(for zeroBasedIndex: Int) -> String {
        var value = zeroBasedIndex + 1
        var result = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            result = String(UnicodeScalar(65 + remainder)!) + result
            value = (value - 1) / 26
        }
        return result
    }
}

private extension DataStudioFieldCandidateResponse {
    var kindLabel: String {
        kind
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
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
