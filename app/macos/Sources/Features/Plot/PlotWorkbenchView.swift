import SwiftUI

struct PlotWorkbenchView: View {
    @Bindable var session: PlotSession
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.selectedSourceFilename != nil {
                topSourceBar
            }

            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
            }

            HSplitView {
                PlotTemplateView(session: session)
                    .frame(minWidth: 230, idealWidth: 260, maxWidth: 300, maxHeight: .infinity, alignment: .topLeading)

                PlotRefineView(session: session)
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            session.attachUndoManager(undoManager)
        }
        .fileImporter(
            isPresented: bindingForImporter,
            allowedContentTypes: FileTypeCatalog.plotDocumentInputs,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let first = urls.first {
                    session.handleImportedDocument(first)
                }
            case let .failure(error):
                if isUserCancellationError(error) {
                    session.errorMessage = nil
                } else {
                    session.errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: bindingForGuide) {
            PlotGuideSheet(session: session)
        }
        .sheet(isPresented: bindingForDataWorkbook) {
            PlotDataWorkbookSheet(session: session)
        }
    }

    private var topSourceBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(session.selectedSourceFilename ?? "")
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 16)

            if session.selectedFileURL != nil {
                Picker("Sheet", selection: selectedSheetBinding) {
                    ForEach(session.availableSheets, id: \.self) { sheet in
                        Text(sheet.displayName).tag(sheet)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220, alignment: .leading)
            }

            Button("Data") {
                session.showDataWorkbook()
            }
            .buttonStyle(.bordered)
            .disabled(!session.dataWorkbookAvailability.isEnabled)
            .help(session.dataWorkbookAvailability.reason ?? "Open the Data Workbook.")

            Image(systemName: session.liveStatusSymbol)
                .symbolEffect(
                    .pulse.byLayer,
                    options: .repeating,
                    value: session.isInspecting || session.isPreviewing
                )
                .font(.headline)
                .foregroundStyle(session.errorMessage == nil ? Color.secondary : Color.orange)
        }
    }

    private var bindingForImporter: Binding<Bool> {
        Binding(
            get: { session.isImporterPresented },
            set: { session.isImporterPresented = $0 }
        )
    }

    private var bindingForGuide: Binding<Bool> {
        Binding(
            get: { session.isGuidePresented },
            set: { session.isGuidePresented = $0 }
        )
    }

    private var bindingForDataWorkbook: Binding<Bool> {
        Binding(
            get: { session.isDataWorkbookPresented },
            set: { session.isDataWorkbookPresented = $0 }
        )
    }

    private var selectedSheetBinding: Binding<SheetValue> {
        Binding(
            get: { session.selectedSheet },
            set: { session.setSelectedSheet($0) }
        )
    }
}

private struct PlotGuideSheet: View {
    let session: PlotSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    guideSection(
                        title: "Live Canvas",
                        text: "Plot is state-driven. Importing a source immediately kicks off inspect, template recommendation, and preview rendering."
                    )
                    guideSection(
                        title: "Sheets",
                        text: "Switching sheets re-runs inspect and refreshes the preview automatically. The last successful preview stays visible until the new one is ready."
                    )
                    guideSection(
                        title: "Templates",
                        text: "Use the left rail to switch between the top compatible templates. Template changes immediately refresh the preview."
                    )
                    guideSection(
                        title: "Inspector",
                        text: "Use the inspector for compact plot options, axis controls, and legend ordering. Keep the canvas dominant and move secondary helpers into lightweight surfaces."
                    )
                    axisLabelOverridesSection
                    dataTemplatesSection
                    guideSection(
                        title: "Export",
                        text: "Export is available from both the toolbar and inspector Actions section. Choose PDF or 300 dpi TIFF first, then choose the destination for the current plot state."
                    )
                }
                .padding(24)
            }
            .navigationTitle("Plot Guide")
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

    private var axisLabelOverridesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Axis Label Overrides")
                .font(.headline)

            Text("Auto normalization currently includes replacements like frequency -> ω, storage modulus -> G', shear strain -> γ, stress -> σ, and 2theta -> 2θ. Use overrides below when you want exact wording for the current Plot session.")
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("X label")
                        .foregroundStyle(.secondary)
                    TextField(
                        session.recommendedXAxisLabel ?? "Use recommended label",
                        text: axisLabelBinding(
                            get: { session.renderOptions.xLabelOverride },
                            set: { newValue in
                                session.updateRenderOptions(policy: .debounced) { $0.xLabelOverride = newValue }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Y label")
                        .foregroundStyle(.secondary)
                    TextField(
                        session.recommendedYAxisLabel ?? "Use recommended label",
                        text: axisLabelBinding(
                            get: { session.renderOptions.yLabelOverride },
                            set: { newValue in
                                session.updateRenderOptions(policy: .debounced) { $0.yLabelOverride = newValue }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }

            if session.recommendedXAxisLabel != nil || session.recommendedYAxisLabel != nil {
                Text(
                    "Recommended: X = \(session.recommendedXAxisLabel ?? "Auto"), Y = \(session.recommendedYAxisLabel ?? "Auto")"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Reset Overrides") {
                    session.updateRenderOptions(policy: .immediate) {
                        $0.xLabelOverride = nil
                        $0.yLabelOverride = nil
                    }
                }
                .buttonStyle(.bordered)

                Text("Session-only. Preview and export both use these overrides.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
    }

    private var dataTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data File Templates")
                .font(.headline)

            Text("Open the built-in example tables when you need a quick reference for supported input structure.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Open Curve Table") {
                    session.openExampleDataTemplate(named: "curve_table.csv")
                }
                .buttonStyle(.borderedProminent)

                Button("Open Replicate Table") {
                    session.openExampleDataTemplate(named: "replicate_table.csv")
                }
                .buttonStyle(.bordered)

                Button("Reveal in Finder") {
                    session.revealExampleDataTemplates()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
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

    private func axisLabelBinding(
        get: @escaping () -> String?,
        set: @escaping (String?) -> Void
    ) -> Binding<String> {
        Binding(
            get: { get() ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                set(trimmed.isEmpty ? nil : trimmed)
            }
        )
    }
}

struct PlotDataWorkbookSheet: View {
    let session: PlotSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                workbookHeader
                tabBar
                activeContent
            }
            .padding(24)
            .navigationTitle("Data Workbook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                        session.dismissDataWorkbook()
                    }
                }
            }
        }
        .onAppear {
            session.refreshDataWorkbookIfNeeded()
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var workbookHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(session.selectedSourceFilename ?? "Plot Source")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 12)

                if let template = session.selectedTemplateSummary?.label {
                    Text(template)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                Text("Sheet: \(session.selectedSheet.displayName)")
                    .foregroundStyle(.secondary)
                if let dataset = session.inspectionResponse?.dataset {
                    Text("Rows: \(dataset.rawRows)")
                        .foregroundStyle(.secondary)
                    Text("Cols: \(dataset.rawCols)")
                        .foregroundStyle(.secondary)
                }
                if let xLabel = session.sourceTableResponse?.detectedXLabel ?? session.recommendedXAxisLabel {
                    Text("X: \(xLabel)")
                        .foregroundStyle(.secondary)
                }
                if let yLabel = session.sourceTableResponse?.detectedYLabel ?? session.recommendedYAxisLabel {
                    Text("Y: \(yLabel)")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button("Open Source") {
                    session.openCurrentSource()
                }
                .buttonStyle(.bordered)

                Button("Reveal Source") {
                    session.revealCurrentSource()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 10) {
            workbookTabButton(.sourceData, availability: ActionAvailability.enabled())
            workbookTabButton(.fit, availability: session.fitAnalysisAvailability)
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        switch session.dataWorkbookTab {
        case .sourceData:
            sourceDataContent
        case .fit:
            fitContent
        }
    }

    private var sourceDataContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !session.candidateRoleRows.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(session.candidateRoleRows, id: \.0) { role, values in
                            Text("\(role): \(values)")
                                .font(.footnote)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.quinary.opacity(0.3), in: Capsule())
                        }
                    }
                }
            }

            if let sourceTableErrorMessage = session.sourceTableErrorMessage {
                ErrorStateCard(
                    title: "Could not load the source table",
                    message: sourceTableErrorMessage,
                    retryTitle: "Retry"
                ) {
                    session.loadSourceTablePreview(offset: session.sourceTableOffset)
                }
            } else if session.isLoadingSourceTable && session.sourceTableResponse == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let sourceTableResponse = session.sourceTableResponse {
                Table(session.sourceTableRows) {
                    TableColumn("#") { row in
                        Text("\(row.id + 1)")
                            .foregroundStyle(.secondary)
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(0) {
                        TableColumn(sourceTableResponse.columnHeaders[0]) { row in
                            Text(row.value(at: 0).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(1) {
                        TableColumn(sourceTableResponse.columnHeaders[1]) { row in
                            Text(row.value(at: 1).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(2) {
                        TableColumn(sourceTableResponse.columnHeaders[2]) { row in
                            Text(row.value(at: 2).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(3) {
                        TableColumn(sourceTableResponse.columnHeaders[3]) { row in
                            Text(row.value(at: 3).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(4) {
                        TableColumn(sourceTableResponse.columnHeaders[4]) { row in
                            Text(row.value(at: 4).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(5) {
                        TableColumn(sourceTableResponse.columnHeaders[5]) { row in
                            Text(row.value(at: 5).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(6) {
                        TableColumn(sourceTableResponse.columnHeaders[6]) { row in
                            Text(row.value(at: 6).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(7) {
                        TableColumn(sourceTableResponse.columnHeaders[7]) { row in
                            Text(row.value(at: 7).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(8) {
                        TableColumn(sourceTableResponse.columnHeaders[8]) { row in
                            Text(row.value(at: 8).displayString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .frame(minHeight: 320)

                HStack {
                    Button("Previous") {
                        session.pageSourceTable(by: -1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!session.canPageSourceTableBackward)

                    Button("Next") {
                        session.pageSourceTable(by: 1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!session.canPageSourceTableForward)

                    Spacer()

                    Text(session.sourceTablePageSummary)
                        .foregroundStyle(.secondary)

                    if sourceTableResponse.totalCols > 9 {
                        Text("Showing first 9 of \(sourceTableResponse.totalCols) columns")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                EmptyStateCard(title: "No source table")
            }
        }
    }

    private var fitContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.fitAnalysisAvailability.isEnabled {
                HStack(spacing: 12) {
                    Text("Model")
                        .foregroundStyle(.secondary)

                    Picker("Model", selection: fitModelBinding) {
                        Text("Linear").tag("linear")
                        Text("Polynomial 2").tag("polynomial_2")
                        Text("Polynomial 3").tag("polynomial_3")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180, alignment: .leading)

                    if session.supportsFitOverlayControls {
                        Toggle("Overlay", isOn: fitEnabledBinding)
                            .toggleStyle(.switch)
                            .disabled(!session.fitOverlayAvailability.isEnabled)
                            .help(
                                session.fitOverlayAvailability.reason
                                    ?? "Overlay the current Plot preview with the selected fit model."
                            )
                    }

                    Spacer()
                }
            }

            if !session.fitAnalysisAvailability.isEnabled {
                EmptyStateCard(
                    title: "Fit Unavailable",
                    message: session.fitAnalysisAvailability.reason
                )
            } else if let fitAnalysisErrorMessage = session.fitAnalysisErrorMessage {
                ErrorStateCard(
                    title: "Could not analyze the fit",
                    message: fitAnalysisErrorMessage,
                    retryTitle: "Retry"
                ) {
                    session.loadFitAnalysis(offset: session.fitAnalysisOffset)
                }
            } else if session.isLoadingFitAnalysis && session.fitAnalysisResponse == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let fitAnalysisResponse = session.fitAnalysisResponse {
                if fitAnalysisResponse.seriesSummaries.count > 1 {
                    HStack(spacing: 12) {
                        Text("Series")
                            .foregroundStyle(.secondary)

                        Picker("Series", selection: fitSeriesBinding(fitAnalysisResponse)) {
                            ForEach(fitAnalysisResponse.seriesSummaries) { summary in
                                Text(summary.seriesLabel).tag(summary.seriesID)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220, alignment: .leading)

                        Spacer()
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    ForEach(session.fitSummaryRows, id: \.0) { label, value in
                        GridRow {
                            Text(label)
                                .foregroundStyle(.secondary)
                            Text(value)
                                .textSelection(.enabled)
                        }
                    }
                }

                if !fitAnalysisResponse.warnings.isEmpty {
                    ForEach(fitAnalysisResponse.warnings, id: \.self) { warning in
                        Text(warning)
                            .foregroundStyle(.secondary)
                    }
                }

                Table(fitAnalysisResponse.rows) {
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
                .frame(minHeight: 320)

                HStack {
                    Button("Previous") {
                        session.pageFitAnalysis(by: -1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!session.canPageFitAnalysisBackward)

                    Button("Next") {
                        session.pageFitAnalysis(by: 1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!session.canPageFitAnalysisForward)

                    Spacer()

                    Text(session.fitAnalysisPageSummary)
                        .foregroundStyle(.secondary)
                }
            } else {
                EmptyStateCard(title: "No fit analysis")
            }
        }
    }

    @ViewBuilder
    private func workbookTabButton(
        _ tab: PlotDataWorkbookTab,
        availability: ActionAvailability
    ) -> some View {
        if tab == session.dataWorkbookTab {
            Button(tab.title) {
                session.selectDataWorkbookTab(tab)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!availability.isEnabled)
            .help(availability.reason ?? tab.title)
        } else {
            Button(tab.title) {
                session.selectDataWorkbookTab(tab)
            }
            .buttonStyle(.bordered)
            .disabled(!availability.isEnabled)
            .help(availability.reason ?? tab.title)
        }
    }

    private var fitEnabledBinding: Binding<Bool> {
        Binding(
            get: { session.fitOptions.enabled },
            set: { session.updateFitEnabled($0) }
        )
    }

    private var fitModelBinding: Binding<String> {
        Binding(
            get: { session.fitOptions.modelID },
            set: { session.updateFitModel($0) }
        )
    }

    private func fitSeriesBinding(_ response: FitAnalysisResponse) -> Binding<String> {
        Binding(
            get: {
                let selected = session.fitAnalysisSeriesSelection
                return selected.isEmpty ? (response.selectedSeriesID ?? response.seriesSummaries.first?.seriesID ?? "") : selected
            },
            set: { session.selectFitAnalysisSeries(id: $0.isEmpty ? nil : $0) }
        )
    }
}
