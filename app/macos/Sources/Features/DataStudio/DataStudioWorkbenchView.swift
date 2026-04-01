import SwiftUI
import UniformTypeIdentifiers

private func dataStudioRecipeCapsuleColor(selected: Bool) -> Color {
    selected ? Color.accentColor.opacity(0.18) : Color(nsColor: .quaternaryLabelColor).opacity(0.12)
}

struct DataStudioWorkbenchView: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topSourceBar

            if let errorMessage = session.errorMessage {
                compactIssueLabel(message: errorMessage)
            }

            HSplitView {
                DataStudioRailView(session: session)
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 340, maxHeight: .infinity, alignment: .topLeading)

                DataStudioWorkspaceView(session: session)
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            allowsMultipleSelection: session.pendingImportKind != .templateSample
        ) { result in
            switch result {
            case let .success(urls):
                Task {
                    switch session.pendingImportKind {
                    case .sourceFiles:
                        await session.handleImportedSourceFiles(urls)
                    case .templateSample:
                        await session.handleImportedTemplateSample(urls)
                    case .workbook:
                        await session.handleImportedWorkbooks(urls)
                    }
                }
            case let .failure(error):
                session.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            importDialogTitle,
            isPresented: importMenuBinding,
            titleVisibility: .visible
        ) {
            if session.templateMode == .existingTemplate {
                Button("Import Raw Source Files") {
                    session.beginImport(kind: .sourceFiles)
                }
            } else {
                Button("Import Template Sample File") {
                    session.beginImport(kind: .templateSample)
                }
            }
            Button("Import Existing Workbook") {
                session.beginImport(kind: .workbook)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(importDialogMessage)
        }
        .sheet(isPresented: guideBinding) {
            DataStudioGuideSheet(session: session)
        }
    }

    private var topSourceBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.focusedWorkbook?.label ?? session.selectedSourceFilename ?? "No workbook selected")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(session.templateMode.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            if let selectedTemplate = session.selectedTemplate {
                Label(selectedTemplate.label, systemImage: selectedTemplate.builtin ? "shippingbox.fill" : "square.stack.3d.up")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Label(activityLabel, systemImage: activitySymbol)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var activityLabel: String {
        if session.currentActivity == .previewingSource {
            return "Inspecting source"
        }
        if session.currentActivity == .buildingWorkbook || session.currentActivity == .importingWorkbooks {
            return "Building workbooks"
        }
        if session.currentActivity == .refreshingWorkbookPreview {
            return "Refreshing preview"
        }
        if session.currentActivity == .previewingComparison {
            return "Previewing compare"
        }
        if session.currentActivity == .exportingComparison {
            return "Exporting compare"
        }
        if session.currentActivity == .creatingTemplate {
            return "Saving template"
        }
        return "Ready"
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

    private var allowedImportTypes: [UTType] {
        switch session.pendingImportKind {
        case .sourceFiles, .templateSample:
            return FileTypeCatalog.dataStudioRawInputs
        case .workbook:
            return FileTypeCatalog.dataStudioWorkbookInputs
        }
    }

    private var importDialogTitle: String {
        session.templateMode == .existingTemplate ? "Import into Data Studio" : "Create Data Studio Template"
    }

    private var importDialogMessage: String {
        switch session.templateMode {
        case .existingTemplate:
            return "Select an existing template to parse raw files directly into workbooks, or import existing workbooks into the current comparison set."
        case .createNewTemplate:
            return "Import a real sample file to review recommended regions and save a reusable Data Studio template, or import workbooks for comparison."
        }
    }

    private var importerBinding: Binding<Bool> {
        Binding(
            get: { session.isImportPresented },
            set: { session.isImportPresented = $0 }
        )
    }

    private var importMenuBinding: Binding<Bool> {
        Binding(
            get: { session.isImportMenuPresented },
            set: { session.isImportMenuPresented = $0 }
        )
    }

    private var guideBinding: Binding<Bool> {
        Binding(
            get: { session.isGuidePresented },
            set: { session.isGuidePresented = $0 }
        )
    }
}

private struct DataStudioRailView: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                templateModeCard

                if session.templateMode == .existingTemplate {
                    existingTemplateCard
                } else {
                    templateDraftCard
                }

                workbookQueueCard
                compareRecipesCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }

    private var templateModeCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Template Mode", selection: selectedModeBinding) {
                    ForEach(DataStudioTemplateMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(session.templateMode.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Import", systemImage: "tray.and.arrow.down") {
                        session.showImportMenu()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Refresh Templates", systemImage: "arrow.clockwise") {
                        Task { await session.refreshTemplates() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Template Flow")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var existingTemplateCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if session.templates.isEmpty {
                    Text("No Data Studio templates are available yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.templates) { template in
                        DataStudioTemplateRow(
                            template: template,
                            isSelected: session.selectedTemplateID == template.id,
                            selectAction: { session.selectTemplate(id: template.id) },
                            badgeView: railBadge
                        )
                    }
                }

                if !session.sourceMatches.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Latest Source Matches")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(session.sourceMatches) { match in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
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
        } label: {
            Text("Template Library")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var templateDraftCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if let preview = session.sourcePreview {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(URL(fileURLWithPath: preview.sourcePath).lastPathComponent)
                            .font(.body.weight(.semibold))
                        Text("\(preview.fileType.uppercased()) · \(preview.sheetNames.count) sheet(s) · \(preview.fieldCandidates.count) candidate(s)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Import a real sample file and Data Studio will recommend candidate regions before you save the template.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                TextField("Template Name", text: $session.templateDraftLabel)
                    .textFieldStyle(.roundedBorder)
                TextField("Template Description", text: $session.templateDraftDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommended Candidate Regions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let preview = session.sourcePreview, !preview.fieldCandidates.isEmpty {
                        ForEach(preview.fieldCandidates) { candidate in
                            Toggle(isOn: candidateBinding(for: candidate.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(candidate.label)
                                            .font(.footnote.weight(.medium))
                                        railBadge(candidate.kind.replacingOccurrences(of: "_", with: " "), tint: .gray)
                                        Text(candidate.confidence.formatted(.percent.precision(.fractionLength(0))))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(candidate.rationale)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    } else {
                        Text("Candidate regions will appear after you preview a sample file.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button("Import Sample", systemImage: "doc.viewfinder") {
                        session.beginImport(kind: .templateSample)
                    }
                    .buttonStyle(.bordered)

                    Button("Save Template", systemImage: "square.and.arrow.down") {
                        Task { await session.createTemplateFromDraft() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.sourcePreview == nil || session.selectedCandidateIDs.isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Template Draft")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var workbookQueueCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if session.orderedWorkbooks.isEmpty {
                    Text("No workbooks loaded yet. Import source files with a template or add prepared workbooks to start comparison.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.orderedWorkbooks) { workbook in
                        DataStudioWorkbookRow(
                            workbook: workbook,
                            isPrimary: session.primaryWorkbookID == workbook.id,
                            isFocused: session.focusedWorkbook?.id == workbook.id
                                || (session.focusedWorkbookID == nil && session.primaryWorkbookID == workbook.id),
                            metricSummary: workbook.response.metrics.first.map { "\($0.label): \(formattedMetric($0.mean)) \($0.unit)" },
                            focusAction: { session.setFocusedWorkbook(id: workbook.id) },
                            badgeView: railBadge
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Workbook Queue")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var compareRecipesCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let comparisonSet = session.comparisonSet {
                    Text(comparisonSet.label)
                        .font(.body.weight(.semibold))
                    Text("\(comparisonSet.workbookLabels.count) workbook(s) · \(comparisonSet.recipes.count) recipe(s)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(comparisonSet.recipes) { recipe in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("", isOn: recipeEnabledBinding(recipe.id))
                                .labelsHidden()
                                .disabled(!recipe.supported)

                            Button {
                                session.selectRecipe(id: recipe.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(recipe.label)
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if session.selectedRecipeID == recipe.id {
                                            railBadge("Preview", tint: .green)
                                        }
                                    }
                                    Text(recipe.supported ? recipe.templateID : recipe.supportReason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(!recipe.supported)
                        }
                    }
                } else {
                    Text("Comparison recipes appear automatically once at least two workbooks are loaded.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Compare Recipes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func candidateBinding(for candidateID: String) -> Binding<Bool> {
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

    private func recipeEnabledBinding(_ recipeID: String) -> Binding<Bool> {
        Binding(
            get: { session.enabledRecipeIDs.contains(recipeID) },
            set: { _ in
                session.toggleRecipe(id: recipeID)
            }
        )
    }

    private var selectedModeBinding: Binding<DataStudioTemplateMode> {
        Binding(
            get: { session.templateMode },
            set: { session.selectTemplateMode($0) }
        )
    }

    private func formattedMetric(_ value: Double?) -> String {
        guard let value else {
            return "n/a"
        }
        return value.formatted(.number.precision(.fractionLength(2)))
    }

    private func railBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }

}

private struct DataStudioTemplateRow<BadgeView: View>: View {
    let template: DataStudioTemplateResponse
    let isSelected: Bool
    let selectAction: () -> Void
    let badgeView: (_ text: String, _ tint: Color) -> BadgeView

    var body: some View {
        Button(action: selectAction) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(template.label)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if template.builtin {
                            badgeView("Builtin", .blue)
                        }
                        if isSelected {
                            badgeView("Selected", .green)
                        }
                    }
                    Text(template.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(template.family)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .quaternaryLabelColor).opacity(0.12) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DataStudioWorkbookRow<BadgeView: View>: View {
    let workbook: DataStudioWorkbookItem
    let isPrimary: Bool
    let isFocused: Bool
    let metricSummary: String?
    let focusAction: () -> Void
    let badgeView: (_ text: String, _ tint: Color) -> BadgeView

    var body: some View {
        Button(action: focusAction) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(workbook.label)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if isPrimary {
                            badgeView("Primary", .yellow)
                        }
                        if isFocused {
                            badgeView("Focused", .green)
                        }
                    }
                    Text("\(workbook.response.parsedSampleCount) parsed · \(workbook.response.failedSampleCount) failed")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let metricSummary {
                        Text(metricSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isFocused ? Color(nsColor: .quaternaryLabelColor).opacity(0.12) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DataStudioWorkspaceView: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if session.templateMode == .createNewTemplate, let sourcePreview = session.sourcePreview, session.focusedWorkbook == nil {
                    DataStudioSourcePreviewWorkspace(session: session, preview: sourcePreview)
                } else if let workbook = session.focusedWorkbook {
                    DataStudioWorkbookWorkspace(session: session, workbook: workbook)
                } else {
                    EmptyStateCard(
                        title: "No workbook yet",
                        message: session.templateMode == .existingTemplate
                            ? "Choose a template, import raw files, and Data Studio will build a workbook automatically."
                            : "Import a sample file to create a new template, or import existing workbooks to compare."
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }
}

private struct DataStudioSourcePreviewWorkspace: View {
    @Bindable var session: DataStudioSession
    let preview: DataStudioRawFilePreviewResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection(title: "Sample Source") {
                KeyValueGrid(values: [
                    ("File", URL(fileURLWithPath: preview.sourcePath).lastPathComponent),
                    ("Format", preview.fileType.uppercased()),
                    ("Encoding", preview.encoding ?? "Auto"),
                    ("Delimiter", preview.delimiter ?? "Auto"),
                    ("Sheets", preview.sheetNames.joined(separator: ", ")),
                ])
                if !preview.warnings.isEmpty {
                    ForEach(preview.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }
            }

            if !session.sourceMatches.isEmpty {
                InspectorSection(title: "Recommended Templates") {
                    ForEach(session.sourceMatches) { match in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(match.label)
                                    .font(.body.weight(.semibold))
                                Text(match.confidence.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(match.reasons, id: \.self) { reason in
                                Text(reason)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            InspectorSection(title: "Detected Blocks") {
                if preview.sheets.isEmpty {
                    Text("No previewable sheets were found in this source.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(preview.sheets, id: \.sheetName) { sheet in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(sheet.sheetName)
                                .font(.headline)
                            ForEach(sheet.blocks, id: \.id) { block in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(block.label)
                                            .font(.body.weight(.semibold))
                                        Spacer()
                                        Text("\(block.rowCount) × \(block.colCount)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    sampleGrid(rows: block.sampleRows)
                                }
                                .padding(12)
                                .background(.quinary.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
                }
            }
        }
    }

    private func sampleGrid(rows: [[JSONValue]]) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        Text("\(index + 1)")
                            .foregroundStyle(.secondary)
                        ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                            Text(value.displayString)
                                .textSelection(.enabled)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct DataStudioWorkbookWorkspace: View {
    @Bindable var session: DataStudioSession
    let workbook: DataStudioWorkbookItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            previewCard

            InspectorSection(title: "Workbook Summary") {
                KeyValueGrid(values: [
                    ("Label", workbook.label),
                    ("Template", workbook.response.templateMatch.label),
                    ("Preferred Sheet", workbook.response.preferredSheet),
                    ("Parsed Samples", "\(workbook.response.parsedSampleCount)"),
                    ("Failed Samples", "\(workbook.response.failedSampleCount)"),
                    ("Representative", workbook.response.representativeFilename),
                ])
            }

            if !workbook.response.metrics.isEmpty {
                InspectorSection(title: "Group Metrics") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                        ForEach(workbook.response.metrics, id: \.id) { metric in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(metric.label)
                                    .font(.headline)
                                Text(metric.mean.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "n/a")
                                    .font(.title3.weight(.semibold))
                                Text("std \(metric.std.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "n/a") \(metric.unit)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.quinary.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }

            if !workbook.response.warnings.isEmpty || !workbook.response.exclusions.isEmpty {
                InspectorSection(title: "Warnings & Exclusions") {
                    ForEach(workbook.response.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                    ForEach(workbook.response.exclusions, id: \.self) { exclusion in
                        Label(exclusion, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }
            }

            InspectorSection(title: "Replicate Sources") {
                if workbook.response.samples.isEmpty {
                    Text("No sample breakdown was returned for this workbook.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(workbook.response.samples) { sample in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(sample.filename)
                                    .font(.body.weight(.semibold))
                                Text(sample.parsed ? "Parsed" : "Skipped")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background((sample.parsed ? Color.green : Color.gray).opacity(0.14), in: Capsule())
                                    .foregroundStyle(sample.parsed ? .green : .secondary)
                            }
                            metricSummaryText(sample.metrics)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            ForEach(sample.warnings, id: \.self) { warning in
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if session.comparisonSet != nil {
                DataStudioComparisonWorkspace(session: session)
            }
        }
    }

    @ViewBuilder
    private var previewCard: some View {
        if workbook.isReviewLoading {
            BusyStateCard(
                title: "Refreshing workbook preview",
                message: "Data Studio is rendering the representative curve for the focused workbook."
            )
        } else if let errorMessage = workbook.reviewErrorMessage {
            ErrorStateCard(
                title: "Preview issue",
                message: errorMessage,
                retryTitle: "Retry Preview",
                retryAction: { Task { await session.refreshFocusedWorkbookPreview() } }
            )
        } else if let preview = workbook.reviewPreview {
            Base64PDFPreviewView(base64PDF: preview.pdfBase64)
                .frame(minHeight: 420)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
                )
        } else {
            EmptyStateCard(
                title: "Preview unavailable",
                message: "The focused workbook has not produced a representative curve preview yet."
            )
        }
    }

    private func metricSummaryText(_ metrics: [String: Double?]) -> Text {
        let ordered = metrics.keys.sorted().map { key -> String in
            let value = metrics[key] ?? nil
            return "\(key): \(value.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "n/a")"
        }
        return Text(ordered.joined(separator: " · "))
    }
}

private struct DataStudioComparisonWorkspace: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        InspectorSection(title: "Comparison Preview") {
            if let comparisonSet = session.comparisonSet {
                Text(comparisonSet.label)
                    .font(.headline)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(comparisonSet.recipes) { recipe in
                            Button {
                                session.selectRecipe(id: recipe.id)
                            } label: {
                                Text(recipe.label)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(dataStudioRecipeCapsuleColor(selected: session.selectedRecipeID == recipe.id), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(!recipe.supported)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if session.currentActivity == .previewingComparison && session.comparisonPreview == nil {
                    BusyStateCard(
                        title: "Rendering comparison preview",
                        message: "Data Studio is preparing the selected multi-workbook figure."
                    )
                } else if let comparisonPreview = session.comparisonPreview {
                    Base64PDFPreviewView(base64PDF: comparisonPreview.pdfBase64)
                        .frame(minHeight: 320)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
                        )
                } else {
                    Text("Select a supported recipe to preview the comparison figure.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Add at least two workbooks to preview comparison figures.")
                    .foregroundStyle(.secondary)
            }
        }
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
                        title: "Choose a Template",
                        text: "Use Existing Template for repeatable daily processing, or switch to New Template to inspect a real sample file and confirm recommended regions before saving."
                    )
                    guideSection(
                        title: "Build Workbooks",
                        text: "A batch of raw experiment files becomes one workbook with representative curve, replicate metrics, warnings, exclusions, and group-level summaries."
                    )
                    guideSection(
                        title: "Compare in Place",
                        text: "Comparison recipes stay inside Data Studio. You can preview representative curves and group metrics directly without copying workbook data into another workflow."
                    )
                    guideSection(
                        title: "Open in Plot",
                        text: "When a workbook is ready, send it to Plot for render refinement. Plot still owns the rendering contract, styles, and export polish."
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
        .frame(minWidth: 560, minHeight: 420)
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
