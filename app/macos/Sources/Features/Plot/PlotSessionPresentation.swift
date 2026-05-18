import CoreGraphics
import Foundation

struct PlotDataPipelineSummary: Equatable {
    let title: String
    let detail: String
    let hasPipeline: Bool
}

extension PlotSession {
    var currentProjectSnapshot: ProjectSnapshot? {
        guard let selectedFileURL else {
            return nil
        }
        guard let selectedTemplateID = effectiveTemplateID else {
            return nil
        }
        return ProjectSnapshot(
            sourcePath: selectedFileURL.path,
            selectedSheet: selectedSheet,
            selectedTemplateID: selectedTemplateID,
            renderOptions: renderOptions,
            fitOptions: fitOptions
        )
    }

    var isProjectDirty: Bool {
        guard let currentProjectSnapshot else {
            return false
        }
        guard let lastSavedProjectSnapshot = runtimeState.lastSavedProjectSnapshot else {
            return true
        }
        return currentProjectSnapshot != lastSavedProjectSnapshot
    }

    var suggestedProjectFilename: String {
        if let projectURL {
            return projectURL.lastPathComponent
        }
        if let selectedFileURL {
            return selectedFileURL.deletingPathExtension().lastPathComponent + ".sciplot"
        }
        return "plot-project.sciplot"
    }

    var dataWorkbookAvailability: ActionAvailability {
        if isInspecting || needsInspection {
            return .disabled("Wait for inspect to finish before opening the Data Workbook.")
        }
        guard selectedFileURL != nil else {
            return .disabled("Import a source file before opening the Data Workbook.")
        }
        return .enabled()
    }

    var showsAdvancedPlotSection: Bool {
        selectedFileURL != nil && effectiveTemplateID != nil
    }

    var referenceGuideAvailability: ActionAvailability {
        guard selectedFileURL != nil else {
            return .disabled("Import a source file before adding reference guides.")
        }
        if isInspecting || needsInspection {
            return .disabled("Wait for inspect to finish before adding reference guides.")
        }
        guard effectiveTemplateID != nil else {
            return .disabled("Reference guides become available after inspect finishes.")
        }
        return .enabled()
    }

    var textAnnotationAvailability: ActionAvailability {
        guard selectedFileURL != nil else {
            return .disabled("Import a source file before adding text annotations.")
        }
        if isInspecting || needsInspection {
            return .disabled("Wait for inspect to finish before adding text annotations.")
        }
        guard effectiveTemplateID != nil else {
            return .disabled("Text annotations become available after inspect finishes.")
        }
        return .enabled()
    }

    var shapeAnnotationAvailability: ActionAvailability {
        guard selectedFileURL != nil else {
            return .disabled("Import a source file before adding shape annotations.")
        }
        if isInspecting || needsInspection {
            return .disabled("Wait for inspect to finish before adding shape annotations.")
        }
        guard effectiveTemplateID != nil else {
            return .disabled("Shape annotations become available after inspect finishes.")
        }
        return .enabled()
    }

    var analyticalLayerAvailability: ActionAvailability {
        guard selectedFileURL != nil else {
            return .disabled("Import a source file before adding function layers.")
        }
        if isInspecting || needsInspection {
            return .disabled("Wait for inspect to finish before adding function layers.")
        }
        guard effectiveTemplateID != nil else {
            return .disabled("Function layers become available after inspect finishes.")
        }
        guard editableOptionIDs.contains("analytical_layers") else {
            return .disabled("This plot does not expose function layers.")
        }
        return .enabled()
    }

    var dataTransformAvailability: ActionAvailability {
        guard selectedFileURL != nil else {
            return .disabled("Import a source file before adding data transforms.")
        }
        if isInspecting || needsInspection {
            return .disabled("Wait for inspect to finish before adding data transforms.")
        }
        guard effectiveTemplateID != nil else {
            return .disabled("Data transforms become available after inspect finishes.")
        }
        return .enabled()
    }

    var extraXAxisAvailability: ActionAvailability {
        extraAxisAvailability(optionID: "extra_x_axis", axisLabel: "X")
    }

    var extraYAxisAvailability: ActionAvailability {
        extraAxisAvailability(optionID: "extra_y_axis", axisLabel: "Y")
    }

    var xAxisBreakAvailability: ActionAvailability {
        axisBreakAvailability(optionID: "x_axis_breaks", axis: .x)
    }

    var yAxisBreakAvailability: ActionAvailability {
        axisBreakAvailability(optionID: "y_axis_breaks", axis: .y)
    }

    var extraYAxisSeriesBindingAvailability: ActionAvailability {
        guard extraYAxisAvailability.isEnabled else {
            return .disabled(
                extraYAxisAvailability.reason
                    ?? "Double Y becomes available after inspect finishes."
            )
        }
        guard supportsExtraYAxisSeriesBinding else {
            return .disabled("Double Y is only available for curve-like templates with series ownership.")
        }
        guard seriesAssignmentCandidateIDs.count > 1 else {
            return .disabled("Double Y becomes available once inspect finds at least two series.")
        }
        return .enabled()
    }

    var fitAnalysisAvailability: ActionAvailability {
        guard selectedFileURL != nil else {
            return .disabled("Import a source file before analyzing a fit.")
        }
        if isInspecting || needsInspection {
            return .disabled("Wait for inspect to finish before analyzing a fit.")
        }
        guard let dataset = inspectionResponse?.dataset else {
            return .disabled("Fit analysis becomes available after inspect finishes.")
        }
        let supportedModels = Set(["curve_table", "tensile_curve", "frequency_sweep", "temperature_sweep", "stress_relaxation"])
        guard supportedModels.contains(dataset.model) else {
            return .disabled("Fit analysis is only available for curve-like data in this release.")
        }
        guard !dataset.candidateRoles.x.isEmpty, !dataset.candidateRoles.y.isEmpty else {
            return .disabled("This sheet does not expose X/Y fields for fitting.")
        }
        guard dataset.rawRows >= 2 else {
            return .disabled("At least two points are required to compute a fit.")
        }
        return .enabled()
    }

    var fitOverlayAvailability: ActionAvailability {
        guard selectedFileURL != nil else {
            return .disabled("Import a source file before adding a fit overlay.")
        }
        guard supportsFitOverlayControls else {
            return .disabled("Fit overlay is only available for curve, point-line, and scatter templates.")
        }
        guard fitAnalysisAvailability.isEnabled else {
            return .disabled(fitAnalysisAvailability.reason ?? "Fit overlay becomes available after inspect finishes.")
        }
        return .enabled()
    }

    var supportsFitOverlayControls: Bool {
        guard let templateID = effectiveTemplateID else {
            return false
        }
        return Set(["curve", "point_line", "scatter"]).contains(templateID)
    }

    var supportsExtraYAxisSeriesBinding: Bool {
        guard let templateID = effectiveTemplateID else {
            return false
        }
        return Set(["curve", "point_line", "scatter", "function_curve"]).contains(templateID)
    }

    var fitModelLabel: String {
        switch fitOptions.modelID {
        case "polynomial_2":
            return "Polynomial 2"
        case "polynomial_3":
            return "Polynomial 3"
        case "exponential":
            return "Exponential"
        case "logarithmic":
            return "Logarithmic"
        case "power_law":
            return "Power Law"
        case "gaussian":
            return "Gaussian"
        case "logistic":
            return "Logistic"
        case "custom_function":
            return "Custom"
        default:
            return "Linear"
        }
    }

    var sourceTableRows: [PlotWorkbookTableRow] {
        guard let sourceTableResponse else {
            return []
        }
        return sourceTableResponse.rows.enumerated().map { index, values in
            PlotWorkbookTableRow(id: sourceTableResponse.offset + index, values: values)
        }
    }

    var sourceTablePageSummary: String {
        guard let response = sourceTableResponse else {
            return "0 / 0"
        }
        if response.totalRows == 0 || response.rows.isEmpty {
            return "0 / \(response.totalRows)"
        }
        let start = response.offset + 1
        let end = min(response.totalRows, response.offset + response.rows.count)
        return "\(start)-\(end) / \(response.totalRows)"
    }

    var canPageSourceTableBackward: Bool {
        (sourceTableResponse?.offset ?? sourceTableOffset) > 0
    }

    var canPageSourceTableForward: Bool {
        guard let sourceTableResponse else {
            return false
        }
        return sourceTableResponse.offset + sourceTableResponse.rows.count < sourceTableResponse.totalRows
    }

    var fitAnalysisPageSummary: String {
        guard let fitAnalysisResponse else {
            return "0 / 0"
        }
        if fitAnalysisResponse.totalRows == 0 || fitAnalysisResponse.rows.isEmpty {
            return "0 / \(fitAnalysisResponse.totalRows)"
        }
        let start = fitAnalysisResponse.offset + 1
        let end = min(fitAnalysisResponse.totalRows, fitAnalysisResponse.offset + fitAnalysisResponse.rows.count)
        return "\(start)-\(end) / \(fitAnalysisResponse.totalRows)"
    }

    var canPageFitAnalysisBackward: Bool {
        (fitAnalysisResponse?.offset ?? fitAnalysisOffset) > 0
    }

    var canPageFitAnalysisForward: Bool {
        guard let fitAnalysisResponse else {
            return false
        }
        return fitAnalysisResponse.offset + fitAnalysisResponse.rows.count < fitAnalysisResponse.totalRows
    }

    var fitSummaryRows: [(String, String)] {
        guard let fitAnalysisResponse else {
            return []
        }
        var rows: [(String, String)] = [
            ("Model", fitModelLabel),
            ("Equation", fitAnalysisResponse.equationDisplay),
        ]
        if let slope = fitAnalysisResponse.slope {
            rows.append(("Slope", slope.formatted(.number.precision(.fractionLength(4)))))
        }
        if let intercept = fitAnalysisResponse.intercept {
            rows.append(("Intercept", intercept.formatted(.number.precision(.fractionLength(4)))))
        }
        rows.append(("R²", fitAnalysisResponse.rSquared.formatted(.number.precision(.fractionLength(4)))))
        rows.append(("RMSE", fitAnalysisResponse.rmse.formatted(.number.precision(.fractionLength(4)))))
        rows.append(("Points", "\(fitAnalysisResponse.pointCount)"))
        return rows
    }

    private func extraAxisAvailability(optionID: String, axisLabel: String) -> ActionAvailability {
        guard selectedFileURL != nil else {
            return .disabled("Import a source file before adding an extra \(axisLabel) axis.")
        }
        if isInspecting || needsInspection {
            return .disabled("Wait for inspect to finish before adding an extra \(axisLabel) axis.")
        }
        guard effectiveTemplateID != nil else {
            return .disabled("Extra \(axisLabel) axis becomes available after inspect finishes.")
        }
        guard editableOptionIDs.contains(optionID) else {
            return .disabled("This plot does not expose an extra \(axisLabel) axis.")
        }
        if hasActiveAxisBreaks {
            return .disabled("Extra \(axisLabel) axes are unavailable while broken axes are enabled.")
        }
        return .enabled()
    }

    private func axisBreakAvailability(optionID: String, axis: PlotAxisSelection) -> ActionAvailability {
        let axisLabel = axis == .x ? "X" : "Y"
        guard selectedFileURL != nil else {
            return .disabled("Import a source file before adding a broken \(axisLabel) axis.")
        }
        if isInspecting || needsInspection {
            return .disabled("Wait for inspect to finish before adding a broken \(axisLabel) axis.")
        }
        guard effectiveTemplateID != nil else {
            return .disabled("Broken \(axisLabel) axis becomes available after inspect finishes.")
        }
        guard editableOptionIDs.contains(optionID) else {
            return .disabled("This plot does not expose a broken \(axisLabel) axis.")
        }
        if hasActiveExtraXAxis || hasActiveExtraYAxis {
            return .disabled("Broken axes are unavailable while extra axes are enabled.")
        }
        if axis == .x, hasActiveSplitYAxis {
            return .disabled("Broken X axes are unavailable while split Y layout is enabled.")
        }
        if axis == .y, hasActiveSplitXAxis {
            return .disabled("Broken Y axes are unavailable while split X layout is enabled.")
        }
        if axis == .x, (renderOptions.xscale ?? "linear") != "linear" {
            return .disabled("Broken X axis is available on linear axes only.")
        }
        if axis == .y, (renderOptions.yscale ?? "linear") != "linear" {
            return .disabled("Broken Y axis is available on linear axes only.")
        }
        return .enabled()
    }

    private func deduplicatedSeriesSelectionIDs(from labels: [String]) -> [String] {
        var counts: [String: Int] = [:]
        return labels.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            let nextCount = (counts[trimmed] ?? 0) + 1
            counts[trimmed] = nextCount
            return nextCount == 1 ? trimmed : "\(trimmed) (\(nextCount))"
        }
    }

    var fitAnalysisSeriesSelection: String {
        fitAnalysisSelectedSeriesID
            ?? fitAnalysisResponse?.selectedSeriesID
            ?? fitAnalysisResponse?.seriesSummaries.first?.seriesID
            ?? ""
    }

    var availableSheets: [SheetValue] {
        if let inspectionResponse, !inspectionResponse.sheetNames.isEmpty {
            return inspectionResponse.sheetNames.map(SheetValue.name)
        }
        if selectedFileURL != nil {
            return [selectedSheet]
        }
        return [.index(0)]
    }

    var availableTemplateSummaries: [MetaTemplateSummary] {
        metadata?.templates ?? []
    }

    var templateGalleryItems: [PlotTemplateGalleryItem] {
        Array(plotTypeItems.prefix(5))
    }

    var plotTypeItems: [PlotTemplateGalleryItem] {
        let templates = availableTemplateSummaries
        guard !templates.isEmpty else {
            return []
        }

        guard inspectionResponse != nil else {
            return templates.map { template in
                PlotTemplateGalleryItem(
                    id: template.id,
                    title: template.label,
                    description: template.description,
                    thumbnailKind: thumbnailKind(for: template.id),
                    aspectRatio: templateThumbnailAspectRatio(for: template.id),
                    availability: .disabled("Import a source file to inspect compatible templates.")
                )
            }
        }

        let summariesByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
        return compatibleRecommendations.map { recommendation in
            let summary = summariesByID[recommendation.templateID]
            return PlotTemplateGalleryItem(
                id: recommendation.templateID,
                title: summary?.label ?? recommendation.templateID,
                description: summary?.description,
                thumbnailKind: thumbnailKind(for: recommendation.templateID),
                aspectRatio: templateThumbnailAspectRatio(for: recommendation.templateID),
                availability: .enabled()
            )
        }
    }

    var compatibleRecommendations: [TemplateRecommendationResponse] {
        guard let inspection = inspectionResponse?.inspection else {
            return []
        }

        let orderedCandidates = inspection.primaryRecommendation + inspection.alternativeRecommendations + inspection.advancedTemplates
        let source = orderedCandidates.isEmpty ? inspection.recommendations : orderedCandidates
        var seen: Set<String> = []
        return source.filter { candidate in
            seen.insert(candidate.templateID).inserted
        }
    }

    var compatibleTemplateIDs: Set<String> {
        Set(compatibleRecommendations.map(\.templateID))
    }

    var selectedTemplateRecommendation: TemplateRecommendationResponse? {
        guard let selectedTemplateID = effectiveTemplateID else {
            return nil
        }
        return compatibleRecommendations.first { $0.templateID == selectedTemplateID }
            ?? inspectionResponse?.inspection.recommendations.first { $0.templateID == selectedTemplateID }
    }

    var effectiveTemplateID: String? {
        if let selectedTemplateID, !selectedTemplateID.isEmpty {
            return selectedTemplateID
        }
        if let stagedTemplateID = runtimeState.stagedExternalPinnedTemplateID, !stagedTemplateID.isEmpty {
            return stagedTemplateID
        }
        if let requestedTemplateID = previewResponse?.requestedTemplateID, !requestedTemplateID.isEmpty {
            return requestedTemplateID
        }
        if let previewTemplate = previewResponse?.template, !previewTemplate.isEmpty {
            return previewTemplate
        }
        if let requestedTemplateID = preflightResponse?.requestedTemplateID, !requestedTemplateID.isEmpty {
            return requestedTemplateID
        }
        if let preflightTemplate = preflightResponse?.template, !preflightTemplate.isEmpty {
            return preflightTemplate
        }
        if let requestedTemplateID = exportResponse?.requestedTemplateID, !requestedTemplateID.isEmpty {
            return requestedTemplateID
        }
        return nil
    }

    var recommendedXAxisLabel: String? {
        if let label = selectedTemplateRecommendation?.inferredMapping["x"], !label.isEmpty {
            return label
        }
        if let label = inspectionResponse?.inspection.recommendations.first?.inferredMapping["x"], !label.isEmpty {
            return label
        }
        return nil
    }

    var recommendedYAxisLabel: String? {
        if let label = selectedTemplateRecommendation?.inferredMapping["y"], !label.isEmpty {
            return label
        }
        if let label = inspectionResponse?.inspection.recommendations.first?.inferredMapping["y"], !label.isEmpty {
            return label
        }
        return nil
    }

    func templateSummary(for templateID: String) -> MetaTemplateSummary? {
        availableTemplateSummaries.first { $0.id == templateID }
    }

    func templateLabel(for templateID: String) -> String {
        templateSummary(for: templateID)?.label ?? templateID
    }

    var selectedTemplateSummary: MetaTemplateSummary? {
        effectiveTemplateID.flatMap(templateSummary(for:))
    }

    var nativeRealtimePreviewAvailability: ActionAvailability {
        guard let templateID = effectiveTemplateID else {
            return .disabled("Choose a curve-family template before using native realtime preview.")
        }
        guard Self.nativeRealtimePreviewTemplateIDs.contains(templateID) else {
            return .disabled("This template uses backend preview until native parity is available.")
        }
        if hasActiveSplitAxisBreak {
            return .disabled("Split broken axes use backend preview until native parity is available.")
        }
        return .enabled()
    }

    var editableOptionIDs: Set<String> {
        Set(selectedTemplateSummary?.editableOptions ?? [])
    }

    var allowedSizes: [MetaSizeResponse] {
        guard let selectedTemplateSummary else {
            return metadata?.sizes ?? []
        }
        return (metadata?.sizes ?? []).filter { selectedTemplateSummary.allowedSizes.contains($0.id) }
    }

    var availableStyles: [MetaStyleResponse] {
        guard let selectedTemplateSummary else {
            return metadata?.styles ?? []
        }
        return (metadata?.styles ?? []).filter { selectedTemplateSummary.availableStyles.contains($0.id) }
    }

    var publicationStyles: [MetaStyleResponse] {
        availableStyles.filter { $0.displayGroup == "publication" }
    }

    var availablePalettes: [MetaPaletteResponse] {
        guard let selectedTemplateSummary else {
            return metadata?.palettes ?? []
        }
        return (metadata?.palettes ?? []).filter { selectedTemplateSummary.availablePalettes.contains($0.id) }
    }

    var textAnnotations: [TextAnnotationPayload] {
        renderOptions.textAnnotations ?? []
    }

    var referenceGuides: [ReferenceGuidePayload] {
        renderOptions.referenceGuides ?? []
    }

    var shapeAnnotations: [ShapeAnnotationPayload] {
        renderOptions.shapeAnnotations ?? []
    }

    var analyticalLayers: [AnalyticalLayerPayload] {
        renderOptions.analyticalLayers ?? []
    }

    var dataTransforms: [DataTransformPayload] {
        renderOptions.dataTransforms ?? []
    }

    var dataVariables: [DataVariablePayload] {
        renderOptions.dataVariables ?? []
    }

    var dataPipelineSummary: PlotDataPipelineSummary {
        let variableCount = dataVariables.count
        let transformCount = dataTransforms.count
        guard variableCount > 0 || transformCount > 0 else {
            return PlotDataPipelineSummary(
                title: "No data edits",
                detail: "Source data is used directly.",
                hasPipeline: false
            )
        }

        let titleParts = [
            countLabel(variableCount, singular: "variable", plural: "variables"),
            countLabel(transformCount, singular: "transform", plural: "transforms")
        ].compactMap { $0 }

        let activeTransformCount = dataTransforms.filter { $0.enabled }.count
        let disabledTransformCount = transformCount - activeTransformCount
        let detailParts = [
            countLabel(activeTransformCount, singular: "active transform", plural: "active transforms"),
            countLabel(disabledTransformCount, singular: "disabled", plural: "disabled")
        ].compactMap { $0 }

        return PlotDataPipelineSummary(
            title: titleParts.joined(separator: ", "),
            detail: detailParts.isEmpty ? "Variables are available to expressions." : detailParts.joined(separator: ", "),
            hasPipeline: true
        )
    }

    var xAxisBreaks: [AxisBreakPayload] {
        renderOptions.xAxisBreaks ?? []
    }

    var yAxisBreaks: [AxisBreakPayload] {
        renderOptions.yAxisBreaks ?? []
    }

    var xAxisBreakDisplayMode: String {
        axisBreakDisplayMode(for: xAxisBreaks)
    }

    var yAxisBreakDisplayMode: String {
        axisBreakDisplayMode(for: yAxisBreaks)
    }

    var hasActiveSecondaryYAxis: Bool {
        (renderOptions.extraYAxis?.enabled ?? false) && extraYAxisAvailability.isEnabled
    }

    var hasActiveExtraXAxis: Bool {
        renderOptions.extraXAxis?.enabled ?? false
    }

    var hasActiveExtraYAxis: Bool {
        renderOptions.extraYAxis?.enabled ?? false
    }

    var hasActiveAxisBreaks: Bool {
        xAxisBreaks.contains(where: \.enabled) || yAxisBreaks.contains(where: \.enabled)
    }

    var hasActiveSplitXAxis: Bool {
        xAxisBreaks.contains { $0.enabled && $0.displayMode == "split" }
    }

    var hasActiveSplitYAxis: Bool {
        yAxisBreaks.contains { $0.enabled && $0.displayMode == "split" }
    }

    var sampleColumns: [PlotSampleColumn] {
        if let dataset = inspectionResponse?.dataset, !dataset.columnProfiles.isEmpty {
            return dataset.columnProfiles.enumerated().map { index, profile in
                PlotSampleColumn(id: index, title: profile.name)
            }
        }

        let maxCount = inspectionResponse?.dataset?.sampleRows.first?.count ?? 0
        return (0..<maxCount).map { PlotSampleColumn(id: $0, title: "Column \($0 + 1)") }
    }

    var sampleRows: [PlotSampleRow] {
        inspectionResponse?.dataset?.sampleRows.enumerated().map { index, values in
            PlotSampleRow(id: index, values: values)
        } ?? []
    }

    var candidateSeriesLabels: [String] {
        inspectionResponse?.dataset?.candidateRoles.series ?? []
    }

    var seriesAssignmentCandidateIDs: [String] {
        deduplicatedSeriesSelectionIDs(from: seriesOrderLabels)
    }

    var shouldShowSeriesLegendControls: Bool {
        editableOptionIDs.contains("series_order") && candidateSeriesLabels.count > 1
    }

    private func axisBreakDisplayMode(for breaks: [AxisBreakPayload]) -> String {
        breaks.first(where: { $0.displayMode == "split" }) != nil ? "split" : "compress"
    }

    var seriesOrderLabels: [String] {
        guard shouldShowSeriesLegendControls else {
            return []
        }

        if let explicit = renderOptions.seriesOrder, !explicit.isEmpty {
            return explicit
        }

        return candidateSeriesLabels
    }

    var seriesOrderRows: [SortableSeriesListRow] {
        let labels = seriesOrderLabels
        return labels.enumerated().map { index, label in
            SortableSeriesListRow(
                id: "\(index):\(label)",
                title: label,
                positionLabel: "#\(index + 1)",
                moveUpAvailability: seriesOrderMoveAvailability(for: index, offset: -1, count: labels.count),
                moveDownAvailability: seriesOrderMoveAvailability(for: index, offset: 1, count: labels.count)
            )
        }
    }

    var canEditSeriesOrder: Bool {
        shouldShowSeriesLegendControls
    }

    var resetSeriesOrderAvailability: ActionAvailability {
        guard canEditSeriesOrder else {
            return .disabled("This plot does not expose reorderable legend entries.")
        }
        guard renderOptions.seriesOrder != nil else {
            return .disabled("Legend order already matches the source order.")
        }
        return .enabled()
    }

    func moveSeriesOrder(id: String, by offset: Int) {
        guard let index = seriesOrderRows.firstIndex(where: { $0.id == id }) else {
            return
        }
        let availability = seriesOrderMoveAvailability(for: index, offset: offset, count: seriesOrderLabels.count)
        guard availability.isEnabled else {
            return
        }

        var labels = seriesOrderLabels
        let newIndex = index + offset
        guard labels.indices.contains(index), labels.indices.contains(newIndex) else {
            return
        }
        labels.swapAt(index, newIndex)
        setSeriesOrder(labels)
    }

    func setSeriesOrder(_ labels: [String]) {
        guard shouldShowSeriesLegendControls else {
            return
        }
        let previousSnapshot = undoSnapshot()
        let beforeOrder = seriesOrderLabels
        let cleaned = labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        renderOptions.seriesOrder = cleaned.isEmpty ? nil : cleaned
        guard previousSnapshot.renderOptions != renderOptions else {
            return
        }
        notifyRenderOptionsDidChange()
        invalidateSubmissionArtifacts()
        errorMessage = nil
        schedulePreviewRefresh(policy: .immediate)
        recordPlotEditCommand(
            kind: "reorder",
            targetObjectID: "plot:legend:main",
            before: ["seriesOrder": .array(beforeOrder.map(JSONValue.string))],
            after: ["seriesOrder": .array(seriesOrderLabels.map(JSONValue.string))]
        )
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Reorder Legend")
    }

    func moveSeriesOrder(from source: IndexSet, to destination: Int) {
        var labels = seriesOrderLabels
        labels.move(fromOffsets: source, toOffset: destination)
        setSeriesOrder(labels)
    }

    func resetSeriesOrder() {
        let previousSnapshot = undoSnapshot()
        let beforeOrder = seriesOrderLabels
        renderOptions.seriesOrder = nil
        guard previousSnapshot.renderOptions != renderOptions else {
            return
        }
        notifyRenderOptionsDidChange()
        invalidateSubmissionArtifacts()
        errorMessage = nil
        schedulePreviewRefresh(policy: .immediate)
        recordPlotEditCommand(
            kind: "reorder",
            targetObjectID: "plot:legend:main",
            before: ["seriesOrder": .array(beforeOrder.map(JSONValue.string))],
            after: ["seriesOrder": .array(seriesOrderLabels.map(JSONValue.string))]
        )
        registerUndo(previousSnapshot: previousSnapshot, actionName: "Reset Legend Order")
    }

    var candidateRoleRows: [(String, String)] {
        guard let roles = inspectionResponse?.dataset?.candidateRoles else {
            return []
        }

        let pairs: [(String, [String])] = [
            ("X", roles.x),
            ("Y", roles.y),
            ("Z", roles.z),
            ("Group", roles.group),
            ("Sample", roles.sample),
            ("Value", roles.value),
            ("Metric", roles.metric),
            ("Label", roles.label),
            ("Series", roles.series),
        ]

        return pairs.compactMap { title, values in
            guard !values.isEmpty else {
                return nil
            }
            return (title, values.prefix(3).joined(separator: ", "))
        }
    }

    var inferredMappingRows: [(String, String)] {
        guard let mapping = selectedTemplateRecommendation?.inferredMapping else {
            return []
        }

        return mapping
            .filter { !$0.value.isEmpty }
            .map { (key: $0.key, value: $0.value) }
            .sorted { $0.key < $1.key }
    }

    func templateThumbnailAspectRatio(for _: String) -> CGFloat {
        return 60.0 / 55.0
    }

    func thumbnailKind(for templateID: String) -> PlotTemplateThumbnailKind {
        guard let summary = templateSummary(for: templateID) else {
            return .fallback
        }
        return PlotTemplateThumbnailKind(rawValue: summary.presentationKind) ?? .fallback
    }

    private func seriesOrderMoveAvailability(for index: Int, offset: Int, count: Int) -> ActionAvailability {
        guard canEditSeriesOrder else {
            return .disabled("This plot does not expose reorderable legend entries.")
        }

        let newIndex = index + offset
        guard (0..<count).contains(index), (0..<count).contains(newIndex) else {
            if offset < 0 {
                return .disabled("This legend entry is already first.")
            }
            return .disabled("This legend entry is already last.")
        }

        return .enabled()
    }
}

extension PlotSession {
    static let nativeRealtimePreviewTemplateIDs: Set<String> = [
        "curve",
        "point_line",
        "scatter",
        "area_curve",
        "step_line",
        "function_curve",
    ]

    private var hasActiveSplitAxisBreak: Bool {
        let xSplit = renderOptions.xAxisBreaks?.contains { $0.enabled && $0.displayMode == "split" } ?? false
        let ySplit = renderOptions.yAxisBreaks?.contains { $0.enabled && $0.displayMode == "split" } ?? false
        return xSplit || ySplit
    }
}

private func countLabel(_ count: Int, singular: String, plural: String) -> String? {
    guard count > 0 else {
        return nil
    }
    return "\(count) \(count == 1 ? singular : plural)"
}
