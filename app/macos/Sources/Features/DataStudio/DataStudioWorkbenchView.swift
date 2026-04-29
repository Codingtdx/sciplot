import SwiftUI
import UniformTypeIdentifiers

struct DataStudioWorkbenchView: View {
    @Bindable var session: DataStudioSession
    var isInspectorPresented = true
    @Environment(\.undoManager) private var undoManager
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        HStack(spacing: ProWorkspaceMetrics.panelSpacing) {
            DataStudioGroupRailView(session: session)
                .frame(width: ProWorkspaceMetrics.leftRailIdealWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 12)
                .padding(.vertical, 12)

            DataStudioPreviewWorkspaceView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 12)

            if isInspectorPresented {
                DataStudioPreparationInspectorView(session: session)
                    .frame(width: 340)
                    .frame(maxHeight: .infinity)
                    .padding(.trailing, 10)
                    .padding(.vertical, 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(MotionTokens.selection, value: isInspectorPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.rootBackground)
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
        .sheet(isPresented: analysisBinding) {
            DataStudioAnalysisSheet(session: session)
        }
    }

    private var allowedImportTypes: [UTType] {
        switch session.pendingImportKind {
        case .rawFiles:
            return FileTypeCatalog.dataStudioRawInputs
        case .existingWorkbook:
            return FileTypeCatalog.dataStudioWorkbookInputs + [FileTypeCatalog.plotProject]
        }
    }

    private var importerBinding: Binding<Bool> {
        Binding(
            get: { session.importFlow.isImporterPresented },
            set: { _ in }
        )
    }

    private var importWizardBinding: Binding<Bool> {
        Binding(
            get: { session.importFlow.isWizardPresented },
            set: { isPresented in
                if isPresented {
                    session.beginImportFlow()
                } else {
                    session.dismissImportWizard()
                }
            }
        )
    }

    private var analysisBinding: Binding<Bool> {
        Binding(
            get: { session.isAnalysisPresented },
            set: { isPresented in
                if isPresented {
                    session.showAnalysis()
                } else {
                    session.dismissAnalysis()
                }
            }
        )
    }

}

private struct DataStudioGroupRailView: View {
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
                    .controlSize(.small)
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
        .background(theme.panelFill)
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous)
        )
    }

    private var focusedWorkbookSelection: Binding<String?> {
        Binding(
            get: { session.focusedWorkbook?.response.workbookPath },
            set: { session.focusWorkbook(path: $0) }
        )
    }
}

private struct DataStudioFigureRailSection: View {
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
        .background(
            theme.rowFill,
            in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous)
        )
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

private struct DataStudioFigureRailRow: View {
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
            .background(
                isSelected ? theme.selectedRowFill : Color.clear,
                in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.innerCornerRadius, style: .continuous)
            )

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
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        VStack(spacing: ProWorkspaceMetrics.panelSpacing) {
            previewStage

            if let focusedWorkbook = session.focusedWorkbook {
                DataStudioFocusedWorkbookStrip(session: session, workbook: focusedWorkbook)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var previewStage: some View {
        ZStack(alignment: .top) {
            theme.stageBackground

            stageContent

            if let warning = session.previewWarning {
                DataStudioInlinePreviewBanner(message: warning, stale: session.isPreviewStale) {
                    session.retryPreviewRefresh()
                }
                .frame(maxWidth: 640)
                .padding(.top, 18)
                .padding(.horizontal, 28)
            }

            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var stageContent: some View {
        if session.orderedGroups.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.includedGroups.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PlotRefineView(session: session.plotSession)
        }
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
                        .padding(.vertical, 2)
                    }
                }
            }

            if !notices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(notices.prefix(3))) { notice in
                        Label(notice.message, systemImage: notice.style.systemImage)
                            .font(.footnote)
                            .foregroundStyle(notice.style == .warning ? .orange : .secondary)
                    }
                }
            }
        }
        .padding(14)
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous)
        )
    }

    private var displayedMetrics: [DataStudioMetricSummaryResponse] {
        session.displayedMetrics(for: workbook)
    }

    private var notices: [DataStudioFocusedWorkbookNotice] {
        session.focusedWorkbookNotices(for: workbook)
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
        .padding(.vertical, 9)
        .background((stale ? Color.orange : Color.yellow).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder((stale ? Color.orange : Color.yellow).opacity(0.16), lineWidth: 1)
        )
    }
}

private struct DataStudioAnalysisSheet: View {
    @Bindable var session: DataStudioSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                header
                targetPicker
                tabBar
                activeContent
            }
            .padding(24)
            .navigationTitle("Analysis")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                        session.dismissAnalysis()
                    }
                }
            }
        }
        .onAppear {
            session.refreshAnalysisIfNeeded()
        }
        .frame(minWidth: 820, minHeight: 620)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.analysisTarget == .focusedWorkbook ? session.focusTitle : session.currentRecipeLabel)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            if let context = session.analysisSourceContext {
                HStack(spacing: 16) {
                    Text("File: \(context.inputURL.lastPathComponent)")
                        .foregroundStyle(.secondary)
                    Text("Sheet: \(context.sheet.displayName)")
                        .foregroundStyle(.secondary)
                    if let response = session.analysisSourceTableResponse {
                        Text("Rows: \(response.totalRows)")
                            .foregroundStyle(.secondary)
                        Text("Cols: \(response.totalCols)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var targetPicker: some View {
        Picker("Scope", selection: targetBinding) {
            ForEach(DataStudioAnalysisTarget.allCases) { target in
                Text(target.title).tag(target)
            }
        }
        .pickerStyle(.segmented)
    }

    private var tabBar: some View {
        HStack(spacing: 10) {
            tabButton(.sourceData, availability: .enabled())
            tabButton(.fit, availability: session.analysisFitAvailability)
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        switch session.analysisTab {
        case .sourceData:
            sourceDataContent
        case .fit:
            fitContent
        }
    }

    private var sourceDataContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage = session.analysisSourceTableErrorMessage {
                ErrorStateCard(
                    title: "Could not load the source table",
                    message: errorMessage,
                    retryTitle: "Retry"
                ) {
                    session.loadAnalysisSourceTable(offset: session.analysisSourceTableOffset)
                }
            } else if session.isLoadingAnalysisSourceTable && session.analysisSourceTableResponse == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let response = session.analysisSourceTableResponse {
                Table(session.analysisSourceTableRows) {
                    TableColumn("#") { row in
                        Text("\(row.id + 1)")
                            .foregroundStyle(.secondary)
                    }
                    if response.columnHeaders.indices.contains(0) {
                        TableColumn(response.columnHeaders[0]) { row in
                            Text(row.value(at: 0).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if response.columnHeaders.indices.contains(1) {
                        TableColumn(response.columnHeaders[1]) { row in
                            Text(row.value(at: 1).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if response.columnHeaders.indices.contains(2) {
                        TableColumn(response.columnHeaders[2]) { row in
                            Text(row.value(at: 2).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if response.columnHeaders.indices.contains(3) {
                        TableColumn(response.columnHeaders[3]) { row in
                            Text(row.value(at: 3).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if response.columnHeaders.indices.contains(4) {
                        TableColumn(response.columnHeaders[4]) { row in
                            Text(row.value(at: 4).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if response.columnHeaders.indices.contains(5) {
                        TableColumn(response.columnHeaders[5]) { row in
                            Text(row.value(at: 5).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if response.columnHeaders.indices.contains(6) {
                        TableColumn(response.columnHeaders[6]) { row in
                            Text(row.value(at: 6).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if response.columnHeaders.indices.contains(7) {
                        TableColumn(response.columnHeaders[7]) { row in
                            Text(row.value(at: 7).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if response.columnHeaders.indices.contains(8) {
                        TableColumn(response.columnHeaders[8]) { row in
                            Text(row.value(at: 8).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .frame(minHeight: 340)

                HStack {
                    Button("Previous") {
                        session.pageAnalysisSourceTable(by: -1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!session.canPageAnalysisSourceBackward)

                    Button("Next") {
                        session.pageAnalysisSourceTable(by: 1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!session.canPageAnalysisSourceForward)

                    Spacer()

                    Text(session.analysisSourceTablePageSummary)
                        .foregroundStyle(.secondary)

                    if response.totalCols > 9 {
                        Text("Showing first 9 of \(response.totalCols) columns")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                EmptyStateCard(title: "No source data")
            }
        }
    }

    private var fitContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !session.analysisFitAvailability.isEnabled {
                EmptyStateCard(
                    title: "Fit Unavailable",
                    message: session.analysisFitAvailability.reason
                )
            } else {
                HStack(spacing: 12) {
                    Picker("Model", selection: modelBinding) {
                        Text("Linear").tag("linear")
                        Text("Polynomial 2").tag("polynomial_2")
                        Text("Polynomial 3").tag("polynomial_3")
                    }
                    .pickerStyle(.menu)

                    if let response = session.analysisFitResponse, response.seriesSummaries.count > 1 {
                        Picker("Series", selection: seriesBinding) {
                            ForEach(response.seriesSummaries) { summary in
                                Text(summary.seriesLabel).tag(Optional(summary.seriesID))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                if let errorMessage = session.analysisFitErrorMessage {
                    ErrorStateCard(
                        title: "Could not analyze the fit",
                        message: errorMessage,
                        retryTitle: "Retry"
                    ) {
                        session.loadAnalysisFit(offset: session.analysisFitOffset)
                    }
                } else if session.isLoadingAnalysisFit && session.analysisFitResponse == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if let response = session.analysisFitResponse {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        ForEach(session.analysisFitSummaryRows, id: \.0) { label, value in
                            GridRow {
                                Text(label)
                                    .foregroundStyle(.secondary)
                                Text(value)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if !response.warnings.isEmpty {
                        ForEach(response.warnings, id: \.self) { warning in
                            Text(warning)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Table(response.seriesSummaries) {
                        TableColumn("Series") { row in
                            Text(row.seriesLabel)
                        }
                        TableColumn("Equation") { row in
                            Text(row.equationDisplay)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        TableColumn("R²") { row in
                            Text(row.rSquared.formatted(.number.precision(.fractionLength(4))))
                        }
                        TableColumn("RMSE") { row in
                            Text(row.rmse.formatted(.number.precision(.fractionLength(4))))
                        }
                        TableColumn("Points") { row in
                            Text("\(row.pointCount)")
                        }
                    }
                    .frame(minHeight: 180)

                    Table(response.rows) {
                        TableColumn("X") { row in
                            Text(row.x.formatted(.number.precision(.fractionLength(4))))
                        }
                        TableColumn("Y") { row in
                            Text(row.y.formatted(.number.precision(.fractionLength(4))))
                        }
                        TableColumn("Y Fit") { row in
                            Text(row.yFit.formatted(.number.precision(.fractionLength(4))))
                        }
                        TableColumn("Residual") { row in
                            Text(row.residual.formatted(.number.precision(.fractionLength(4))))
                        }
                    }
                    .frame(minHeight: 220)

                    HStack {
                        Button("Previous") {
                            session.pageAnalysisFit(by: -1)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!session.canPageAnalysisFitBackward)

                        Button("Next") {
                            session.pageAnalysisFit(by: 1)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!session.canPageAnalysisFitForward)

                        Spacer()

                        Text(session.analysisFitPageSummary)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    EmptyStateCard(title: "No fit analysis")
                }
            }
        }
    }

    private var targetBinding: Binding<DataStudioAnalysisTarget> {
        Binding(
            get: { session.analysisTarget },
            set: { session.selectAnalysisTarget($0) }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { session.analysisFitOptions.modelID },
            set: { session.updateAnalysisFitModel($0) }
        )
    }

    private var seriesBinding: Binding<String?> {
        Binding(
            get: { session.analysisSelectedSeriesID },
            set: { session.selectAnalysisSeries(id: $0) }
        )
    }

    @ViewBuilder
    private func tabButton(_ tab: DataStudioAnalysisTab, availability: ActionAvailability) -> some View {
        if tab == session.analysisTab {
            Button(tab.title) {
                session.selectAnalysisTab(tab)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!availability.isEnabled)
            .help(availability.reason ?? tab.title)
        } else {
            Button(tab.title) {
                session.selectAnalysisTab(tab)
            }
            .buttonStyle(.bordered)
            .disabled(!availability.isEnabled)
            .help(availability.reason ?? tab.title)
        }
    }
}
