import Foundation

extension DataStudioSession {
    func showAnalysis() {
        isAnalysisPresented = true
        refreshAnalysisIfNeeded()
    }

    func dismissAnalysis() {
        isAnalysisPresented = false
    }

    func selectAnalysisTarget(_ target: DataStudioAnalysisTarget) {
        guard analysisTarget != target else {
            return
        }
        analysisTarget = target
        analysisSelectedSeriesID = nil
        analysisFitOffset = 0
        analysisSourceTableOffset = 0
        refreshAnalysisIfNeeded()
    }

    func selectAnalysisTab(_ tab: DataStudioAnalysisTab) {
        guard analysisTab != tab else {
            return
        }
        analysisTab = tab
        refreshAnalysisIfNeeded()
    }

    var analysisSourceContext: (inputURL: URL, sheet: SheetValue)? {
        switch analysisTarget {
        case .focusedWorkbook:
            guard let focusedWorkbook else {
                return nil
            }
            return (focusedWorkbook.workbookURL, .name(focusedWorkbook.response.preferredSheet))
        case .currentFigure:
            guard let inputURL = currentFigureSourceURL else {
                return nil
            }
            return (inputURL, currentFigureSheet)
        }
    }

    var analysisFitAvailability: ActionAvailability {
        guard analysisSourceContext != nil else {
            return .disabled("Select a workbook or figure before running fit analysis.")
        }
        switch analysisTarget {
        case .focusedWorkbook:
            return .enabled()
        case .currentFigure:
            guard let recipe = currentRecipe else {
                return .disabled("Choose a figure before running fit analysis.")
            }
            let supportedTemplates = Set(["curve", "point_line", "scatter"])
            guard supportedTemplates.contains(recipe.templateID) else {
                return .disabled("Fit is only available for curve-like figures in this release.")
            }
            return .enabled()
        }
    }

    var analysisFitOptions: FitOptionsPayload {
        switch analysisTarget {
        case .focusedWorkbook:
            return focusedWorkbookFitOptions
        case .currentFigure:
            return currentFigureFitOptions
        }
    }

    func updateAnalysisFitModel(_ modelID: String) {
        switch analysisTarget {
        case .focusedWorkbook:
            focusedWorkbookFitOptions = FitOptionsPayload(enabled: true, modelID: modelID)
        case .currentFigure:
            plotSession.fitOptions = FitOptionsPayload(enabled: true, modelID: modelID)
            plotSession.notifyFitOptionsDidChange()
            Task { await refreshDisplayedFigureHandlingFailure() }
        }
        analysisSelectedSeriesID = nil
        loadAnalysisFit(offset: 0)
    }

    func selectAnalysisSeries(id: String?) {
        analysisSelectedSeriesID = id
        loadAnalysisFit(offset: 0)
    }

    func refreshAnalysisIfNeeded() {
        guard isAnalysisPresented else {
            return
        }
        switch analysisTab {
        case .sourceData:
            loadAnalysisSourceTable(offset: analysisSourceTableOffset)
        case .fit:
            if analysisFitAvailability.isEnabled {
                loadAnalysisFit(offset: analysisFitOffset)
            } else {
                analysisFitResponse = nil
                analysisFitErrorMessage = analysisFitAvailability.reason
            }
        }
    }

    func loadAnalysisSourceTable(offset: Int = 0) {
        guard let client, let context = analysisSourceContext else {
            analysisSourceTableResponse = nil
            return
        }
        let resolvedOffset = max(0, offset)
        analysisSourceTableOffset = resolvedOffset
        isLoadingAnalysisSourceTable = true
        analysisSourceTableErrorMessage = nil
        Task {
            do {
                let response = try await client.sourceTablePreview(
                    .init(
                        inputPath: context.inputURL.path,
                        sheet: context.sheet,
                        offset: resolvedOffset,
                        limit: 50
                    )
                )
                analysisSourceTableResponse = response
                isLoadingAnalysisSourceTable = false
            } catch {
                analysisSourceTableErrorMessage = error.localizedDescription
                isLoadingAnalysisSourceTable = false
            }
        }
    }

    func loadAnalysisFit(offset: Int = 0) {
        guard let client, let context = analysisSourceContext else {
            analysisFitResponse = nil
            return
        }
        guard analysisFitAvailability.isEnabled else {
            analysisFitResponse = nil
            analysisFitErrorMessage = analysisFitAvailability.reason
            return
        }
        let resolvedOffset = max(0, offset)
        analysisFitOffset = resolvedOffset
        isLoadingAnalysisFit = true
        analysisFitErrorMessage = nil
        Task {
            do {
                let response = try await client.fitAnalysis(
                    .init(
                        inputPath: context.inputURL.path,
                        sheet: context.sheet,
                        modelID: analysisFitOptions.modelID,
                        seriesID: analysisSelectedSeriesID,
                        offset: resolvedOffset,
                        limit: 50
                    )
                )
                analysisFitResponse = response
                analysisSelectedSeriesID = response.selectedSeriesID
                isLoadingAnalysisFit = false
            } catch {
                analysisFitErrorMessage = error.localizedDescription
                isLoadingAnalysisFit = false
            }
        }
    }

    func pageAnalysisSourceTable(by delta: Int) {
        let nextOffset = max(0, (analysisSourceTableResponse?.offset ?? analysisSourceTableOffset) + delta * 50)
        loadAnalysisSourceTable(offset: nextOffset)
    }

    func pageAnalysisFit(by delta: Int) {
        let nextOffset = max(0, (analysisFitResponse?.offset ?? analysisFitOffset) + delta * 50)
        loadAnalysisFit(offset: nextOffset)
    }

    var analysisSourceTableRows: [PlotWorkbookTableRow] {
        guard let response = analysisSourceTableResponse else {
            return []
        }
        return response.rows.enumerated().map { index, values in
            PlotWorkbookTableRow(id: response.offset + index, values: values)
        }
    }

    var analysisSourceTablePageSummary: String {
        guard let response = analysisSourceTableResponse else {
            return "0 / 0"
        }
        if response.totalRows == 0 || response.rows.isEmpty {
            return "0 / \(response.totalRows)"
        }
        let start = response.offset + 1
        let end = min(response.totalRows, response.offset + response.rows.count)
        return "\(start)-\(end) / \(response.totalRows)"
    }

    var canPageAnalysisSourceBackward: Bool {
        (analysisSourceTableResponse?.offset ?? analysisSourceTableOffset) > 0
    }

    var canPageAnalysisSourceForward: Bool {
        guard let response = analysisSourceTableResponse else {
            return false
        }
        return response.offset + response.rows.count < response.totalRows
    }

    var analysisFitPageSummary: String {
        guard let response = analysisFitResponse else {
            return "0 / 0"
        }
        if response.totalRows == 0 || response.rows.isEmpty {
            return "0 / \(response.totalRows)"
        }
        let start = response.offset + 1
        let end = min(response.totalRows, response.offset + response.rows.count)
        return "\(start)-\(end) / \(response.totalRows)"
    }

    var canPageAnalysisFitBackward: Bool {
        (analysisFitResponse?.offset ?? analysisFitOffset) > 0
    }

    var canPageAnalysisFitForward: Bool {
        guard let response = analysisFitResponse else {
            return false
        }
        return response.offset + response.rows.count < response.totalRows
    }

    var analysisFitSummaryRows: [(String, String)] {
        guard let response = analysisFitResponse else {
            return []
        }
        var rows: [(String, String)] = [
            ("Equation", response.equationDisplay),
            ("R²", response.rSquared.formatted(.number.precision(.fractionLength(4)))),
            ("RMSE", response.rmse.formatted(.number.precision(.fractionLength(4)))),
            ("Points", "\(response.pointCount)"),
        ]
        if let slope = response.slope {
            rows.insert(("Slope", slope.formatted(.number.precision(.fractionLength(4)))), at: 1)
        }
        if let intercept = response.intercept {
            rows.insert(("Intercept", intercept.formatted(.number.precision(.fractionLength(4)))), at: min(rows.count, 2))
        }
        return rows
    }
}
