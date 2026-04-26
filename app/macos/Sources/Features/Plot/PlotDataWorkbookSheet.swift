import SwiftUI

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

            HStack(spacing: 16) {
                Text("Pipeline: \(session.dataPipelineSummary.title)")
                    .foregroundStyle(.secondary)
                Text(session.dataPipelineSummary.detail)
                    .foregroundStyle(.secondary)
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
            workbookTabButton(.transformed, availability: session.dataTransformAvailability)
            workbookTabButton(.variables, availability: session.dataTransformAvailability)
            workbookTabButton(.fit, availability: session.fitAnalysisAvailability)
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        switch session.dataWorkbookTab {
        case .sourceData, .transformed:
            sourceDataContent
        case .variables:
            variablesContent
        case .fit:
            fitContent
        }
    }

    private var variablesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.dataVariables.isEmpty {
                EmptyStateCard(title: "No variables")
            } else {
                Table(session.dataVariables) {
                    TableColumn("Name") { variable in
                        Text(variable.id)
                    }
                    TableColumn("Kind") { variable in
                        Text(variable.kind)
                    }
                    TableColumn("Value") { variable in
                        if variable.kind == "expression" {
                            Text(variable.expression ?? "")
                        } else if let value = variable.value {
                            Text(value.formatted(.number.precision(.fractionLength(4))))
                        } else {
                            Text("")
                        }
                    }
                }
                .frame(minHeight: 320)
            }
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
                            sourceTableCell(row, at: 0)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(1) {
                        TableColumn(sourceTableResponse.columnHeaders[1]) { row in
                            sourceTableCell(row, at: 1)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(2) {
                        TableColumn(sourceTableResponse.columnHeaders[2]) { row in
                            sourceTableCell(row, at: 2)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(3) {
                        TableColumn(sourceTableResponse.columnHeaders[3]) { row in
                            sourceTableCell(row, at: 3)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(4) {
                        TableColumn(sourceTableResponse.columnHeaders[4]) { row in
                            sourceTableCell(row, at: 4)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(5) {
                        TableColumn(sourceTableResponse.columnHeaders[5]) { row in
                            sourceTableCell(row, at: 5)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(6) {
                        TableColumn(sourceTableResponse.columnHeaders[6]) { row in
                            sourceTableCell(row, at: 6)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(7) {
                        TableColumn(sourceTableResponse.columnHeaders[7]) { row in
                            sourceTableCell(row, at: 7)
                        }
                    }
                    if sourceTableResponse.columnHeaders.indices.contains(8) {
                        TableColumn(sourceTableResponse.columnHeaders[8]) { row in
                            sourceTableCell(row, at: 8)
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

    private func sourceTableCell(_ row: PlotWorkbookTableRow, at index: Int) -> some View {
        Text(row.value(at: index).displayString)
            .lineLimit(1)
            .truncationMode(.middle)
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
                        Text("Exponential").tag("exponential")
                        Text("Logarithmic").tag("logarithmic")
                        Text("Power Law").tag("power_law")
                        Text("Gaussian").tag("gaussian")
                        Text("Logistic").tag("logistic")
                        Text("Custom").tag("custom_function")
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
