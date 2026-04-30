import SwiftUI

struct DataStudioAnalysisSheet: View {
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
