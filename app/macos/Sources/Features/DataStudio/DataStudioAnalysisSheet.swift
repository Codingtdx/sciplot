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
                FitModelGrid(
                    selectedModelID: session.analysisFitOptions.modelID,
                    isEnabled: session.analysisFitAvailability.isEnabled,
                    disabledReason: session.analysisFitAvailability.reason,
                    disabledOptionIDs: ["custom_function"],
                    optionHelp: { option in
                        option.isCustom ? "Custom fit setup is available in Plot." : nil
                    },
                    select: { option in
                        guard !option.isCustom else {
                            return
                        }
                        session.updateAnalysisFitModel(option.id)
                    }
                )

                FitResultSummaryPanel(
                    isLoading: session.isLoadingAnalysisFit,
                    errorMessage: session.analysisFitErrorMessage,
                    rows: session.analysisFitSummaryRows,
                    warnings: session.analysisFitResponse?.warnings ?? [],
                    seriesSummaries: session.analysisFitResponse?.seriesSummaries ?? [],
                    selectedSeriesID: session.analysisSelectedSeriesID,
                    selectSeries: { session.selectAnalysisSeries(id: $0) },
                    retry: {
                        session.loadAnalysisFit(offset: session.analysisFitOffset)
                    }
                )
            }
        }
    }

    private var targetBinding: Binding<DataStudioAnalysisTarget> {
        Binding(
            get: { session.analysisTarget },
            set: { session.selectAnalysisTarget($0) }
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
