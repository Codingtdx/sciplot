import SwiftUI

extension PlotInspectorView {
    var figureAdjustmentContent: some View {
        Group {
            if session.selectedTemplateSummary == nil {
                InspectorSection(title: "Figure") {
                    InspectorEmptyState(message: "Import data")
                }
            } else {
                plotOptionsSection
            }
        }
    }

    var axesAdjustmentContent: some View {
        InspectorSection(title: "Axis") {
            if !shouldShowPrimaryAxesControls {
                InspectorEmptyState(message: "No axis controls")
            } else {
                axisScaleControls
                axisRangeControls
                if showsTickLabelControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tick Labels")
                            .font(.subheadline.weight(.semibold))

                        if supportsTickLabelControls(for: .x) {
                            axisTickLabelControls(title: "X axis", axis: .x)
                        }

                        if supportsTickLabelControls(for: .y) {
                            axisTickLabelControls(title: "Y axis", axis: .y)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    var legendAdjustmentContent: some View {
        Group {
            if session.shouldShowSeriesLegendControls {
                seriesSection
            } else {
                InspectorSection(title: "Legend") {
                    InspectorEmptyState(message: "No reorderable legend entries")
                }
            }
        }
    }

    var guidesAdjustmentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection(title: "Guides") {
                PlotCanvasInteractionModeGrid(
                    modes: [
                        .guideLine(axisTarget: "x"),
                        .guideLine(axisTarget: "y_primary"),
                        .guideRegion(axisTarget: "x"),
                        .guideRegion(axisTarget: "y_primary"),
                    ],
                    selectedMode: session.canvasInteractionMode,
                    availability: session.referenceGuideAvailability
                ) { mode in
                    session.beginCanvasPlacement(mode)
                }

                objectList(
                    emptyMessage: "No guides",
                    rows: session.referenceGuides.map {
                        PlotAdjustmentObjectRow(
                            id: $0.id,
                            title: referenceGuideTitle($0),
                            detail: $0.kind == "band" ? "Region" : "Line",
                            systemImage: $0.kind == "band" ? "rectangle.dashed" : "ruler",
                            selection: .referenceGuide($0.id)
                        )
                    }
                )
            }

            selectedGuideEditor
        }
    }

    var fitAdjustmentContent: some View {
        FitModelInspectorSection(session: session)
    }

    var functionsAdjustmentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection(title: "Functions") {
                Button("Add Function") {
                    session.addAnalyticalFunctionLayer()
                    if let layer = session.analyticalLayers.last {
                        session.selectPlotLayer(.function(layer.id))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!session.analyticalLayerAvailability.isEnabled)
                .help(session.analyticalLayerAvailability.reason ?? "Add a backend-rendered function layer.")

                objectList(
                    emptyMessage: "No function layers",
                    rows: session.analyticalLayers.map {
                        PlotAdjustmentObjectRow(
                            id: $0.id,
                            title: functionTitle($0),
                            detail: "Function",
                            systemImage: "function",
                            selection: .function($0.id)
                        )
                    }
                )
            }

            selectedFunctionEditor
        }
    }

    var annotationsAdjustmentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection(title: "Annotations") {
                PlotCanvasInteractionModeGrid(
                    modes: [.text, .callout, .rectangle, .ellipse, .bracket],
                    selectedMode: session.canvasInteractionMode,
                    availability: annotationPlacementAvailability
                ) { mode in
                    session.beginCanvasPlacement(mode)
                }

                objectList(emptyMessage: "No annotations", rows: annotationRows)
            }

            selectedAnnotationEditor
        }
    }

    private var annotationPlacementAvailability: ActionAvailability {
        if session.textAnnotationAvailability.isEnabled || session.shapeAnnotationAvailability.isEnabled {
            return .enabled()
        }
        return .disabled(session.textAnnotationAvailability.reason ?? session.shapeAnnotationAvailability.reason ?? "Annotations are unavailable.")
    }

    var advancedAxesAdjustmentContent: some View {
        InspectorSection(title: "Advanced Axes") {
            if !showsExtraAxesControls && !showsAxisBreakControls {
                InspectorEmptyState(message: "No advanced axis controls")
            } else {
                if showsExtraAxesControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Extra Axes")
                            .font(.subheadline.weight(.semibold))

                        if supportsExtraXAxisControls {
                            extraAxisControls(title: "X axis", axis: .x)
                        }

                        if supportsExtraYAxisControls {
                            extraAxisControls(title: "Y axis", axis: .y)
                        }
                    }
                }

                if showsAxisBreakControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Broken Axes")
                            .font(.subheadline.weight(.semibold))

                        if supportsXAxisBreakControls {
                            axisBreakControls(title: "X axis", axis: .x)
                        }

                        if supportsYAxisBreakControls {
                            axisBreakControls(title: "Y axis", axis: .y)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

private struct PlotCanvasInteractionModeGrid: View {
    let modes: [PlotCanvasInteractionMode]
    let selectedMode: PlotCanvasInteractionMode
    let availability: ActionAvailability
    let select: (PlotCanvasInteractionMode) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 88), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(modes) { mode in
                Button {
                    select(mode)
                } label: {
                    PlotCanvasInteractionModeCard(mode: mode, isSelected: selectedMode == mode)
                }
                .buttonStyle(.plain)
                .disabled(!availability.isEnabled)
                .help(availability.reason ?? mode.title)
            }
        }
    }
}

struct PlotCanvasInteractionModeCard: View {
    let mode: PlotCanvasInteractionMode
    let isSelected: Bool
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: mode.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.74))
                .frame(height: 22)

            Text(mode.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: ProCornerPolicy.row, style: .continuous)
                .fill(isSelected ? theme.selectedRowFill : theme.rowFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ProCornerPolicy.row, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.42) : theme.hairline, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: ProCornerPolicy.row, style: .continuous))
    }
}

struct FitModelInspectorSection: View {
    @Bindable var session: PlotSession
    @Environment(\.proWorkspaceTheme) private var theme
    @State private var isCustomEditorExpanded = false
    @State private var customExpression = ""
    @State private var customParameters: [CustomFitParameterDraft] = [.defaultParameter]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection(title: "Fit") {
                AdaptiveInspectorControlRow(title: "Overlay") {
                    Toggle("", isOn: Binding(
                        get: { session.fitOptions.enabled },
                        set: { session.updateFitEnabled($0) }
                    ))
                    .labelsHidden()
                    .disabled(!session.fitOverlayAvailability.isEnabled)
                    .help(session.fitOverlayAvailability.reason ?? "Show the selected fit model on the figure.")
                }

                FitModelGrid(
                    selectedModelID: session.fitOptions.modelID,
                    isEnabled: session.fitAnalysisAvailability.isEnabled,
                    disabledReason: session.fitAnalysisAvailability.reason,
                    select: selectFitModel
                )

                if isCustomEditorExpanded {
                    customFitEditor
                }
            }

            InspectorSection(title: "Results") {
                FitResultSummaryPanel(
                    isLoading: session.isLoadingFitAnalysis,
                    errorMessage: session.fitAnalysisErrorMessage,
                    rows: session.fitSummaryRows,
                    warnings: session.fitAnalysisResponse?.warnings ?? [],
                    seriesSummaries: session.fitAnalysisResponse?.seriesSummaries ?? [],
                    selectedSeriesID: session.fitAnalysisSeriesSelection.isEmpty ? nil : session.fitAnalysisSeriesSelection,
                    selectSeries: { session.selectFitAnalysisSeries(id: $0) },
                    retry: session.fitAnalysisAvailability.isEnabled ? { session.loadFitAnalysis(offset: 0) } : nil
                )
            }
        }
        .onAppear {
            syncCustomDraftFromSession()
            if session.fitAnalysisAvailability.isEnabled {
                session.loadFitAnalysis(offset: 0)
            }
        }
    }

    private var customFitEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Expression, e.g. a * x + b", text: $customExpression)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            VStack(alignment: .leading, spacing: 8) {
                ForEach($customParameters) { $parameter in
                    HStack(spacing: 6) {
                        TextField("p", text: $parameter.name)
                            .frame(width: 44)
                        TextField("Initial", text: $parameter.initial)
                            .frame(minWidth: 58)
                        TextField("Min", text: $parameter.lower)
                            .frame(minWidth: 48)
                        TextField("Max", text: $parameter.upper)
                            .frame(minWidth: 48)
                        if customParameters.count > 1 {
                            Button {
                                customParameters.removeAll { $0.id == parameter.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                }
            }

            HStack(spacing: 8) {
                Button {
                    customParameters.append(.next(after: customParameters))
                } label: {
                    Label("Parameter", systemImage: "plus")
                }

                Spacer(minLength: 8)

                Button("Use Custom") {
                    applyCustomFit()
                }
                .buttonStyle(.bordered)
                .disabled(customPayload == nil)
                .help(customPayload == nil ? "Enter an expression and valid parameter values." : "Use the custom function fit.")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .proGlassRow(theme: theme, cornerRadius: ProCornerPolicy.row)
    }

    private func selectFitModel(_ option: FitModelOption) {
        guard session.fitAnalysisAvailability.isEnabled else {
            return
        }
        if option.isCustom {
            if let payload = existingCustomPayload ?? customPayload {
                session.updateFitOptions {
                    $0.enabled = true
                    $0.modelID = option.id
                    $0.customFunction = payload
                }
                session.loadFitAnalysis(offset: 0)
            } else {
                isCustomEditorExpanded = true
                syncCustomDraftFromSession()
            }
            return
        }

        isCustomEditorExpanded = false
        session.updateFitModel(option.id)
        session.loadFitAnalysis(offset: 0)
    }

    private func applyCustomFit() {
        guard let payload = customPayload else {
            return
        }
        session.updateFitOptions {
            $0.enabled = true
            $0.modelID = "custom_function"
            $0.customFunction = payload
        }
        isCustomEditorExpanded = false
        session.loadFitAnalysis(offset: 0)
    }

    private func syncCustomDraftFromSession() {
        guard let payload = session.fitOptions.customFunction else {
            if customParameters.isEmpty {
                customParameters = [.defaultParameter]
            }
            return
        }
        customExpression = payload.expression
        customParameters = payload.parameters.isEmpty
            ? [.defaultParameter]
            : payload.parameters.map(CustomFitParameterDraft.init(parameter:))
    }

    private var existingCustomPayload: FitCustomFunctionPayload? {
        guard let payload = session.fitOptions.customFunction else {
            return nil
        }
        let expression = payload.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty, !payload.parameters.isEmpty else {
            return nil
        }
        return payload
    }

    private var customPayload: FitCustomFunctionPayload? {
        let expression = customExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else {
            return nil
        }
        var names = Set<String>()
        let parameters = customParameters.compactMap { draft -> FitCustomParameterPayload? in
            guard let parameter = draft.payload else {
                return nil
            }
            guard names.insert(parameter.name).inserted else {
                return nil
            }
            return parameter
        }
        guard parameters.count == customParameters.count, !parameters.isEmpty else {
            return nil
        }
        return FitCustomFunctionPayload(expression: expression, parameters: parameters)
    }
}

private struct CustomFitParameterDraft: Identifiable, Equatable {
    let id: UUID
    var name: String
    var initial: String
    var lower: String
    var upper: String

    static let defaultParameter = CustomFitParameterDraft(
        id: UUID(),
        name: "a",
        initial: "1",
        lower: "",
        upper: ""
    )

    init(id: UUID = UUID(), name: String, initial: String, lower: String, upper: String) {
        self.id = id
        self.name = name
        self.initial = initial
        self.lower = lower
        self.upper = upper
    }

    init(parameter: FitCustomParameterPayload) {
        self.init(
            name: parameter.name,
            initial: parameter.initial.formatted(.number.precision(.fractionLength(0...6))),
            lower: parameter.lower?.formatted(.number.precision(.fractionLength(0...6))) ?? "",
            upper: parameter.upper?.formatted(.number.precision(.fractionLength(0...6))) ?? ""
        )
    }

    static func next(after parameters: [CustomFitParameterDraft]) -> CustomFitParameterDraft {
        let names = parameters.map(\.name)
        let candidates = ["a", "b", "c", "d", "e", "f", "g"]
        let name = candidates.first { !names.contains($0) } ?? "p\(parameters.count + 1)"
        return CustomFitParameterDraft(name: name, initial: "1", lower: "", upper: "")
    }

    var payload: FitCustomParameterPayload? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let initialValue = Double(initial.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        guard let lowerValue = optionalDouble(lower), let upperValue = optionalDouble(upper) else {
            return nil
        }
        return FitCustomParameterPayload(
            name: trimmedName,
            initial: initialValue,
            lower: lowerValue,
            upper: upperValue
        )
    }

    private func optionalDouble(_ raw: String) -> Double?? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .some(nil)
        }
        guard let value = Double(trimmed) else {
            return nil
        }
        return .some(value)
    }
}
