import SwiftUI

struct PlotSelectedLayerEditorView: View {
    @Bindable var session: PlotSession
    let selection: PlotLayerSelection?

    var body: some View {
        InspectorSection(title: editorTitle) {
            switch selection {
            case .fitOverlay:
                fitOverlayEditor
            case .function(let id):
                if session.analyticalLayers.contains(where: { $0.id == id }) {
                    functionLayerEditor(id: id)
                } else {
                    InspectorEmptyState(message: "Select a layer")
                }
            case .referenceGuide(let id):
                if session.referenceGuides.contains(where: { $0.id == id }) {
                    referenceGuideEditor(id: id)
                } else {
                    InspectorEmptyState(message: "Select a layer")
                }
            case .textAnnotation(let id):
                if session.textAnnotations.contains(where: { $0.id == id }) {
                    textAnnotationEditor(id: id)
                } else {
                    InspectorEmptyState(message: "Select a layer")
                }
            case .shapeAnnotation(let id):
                if session.shapeAnnotations.contains(where: { $0.id == id }) {
                    shapeAnnotationEditor(id: id)
                } else {
                    InspectorEmptyState(message: "Select a layer")
                }
            case .series(let id):
                seriesEditor(id: id)
            case nil:
                InspectorEmptyState(message: "Select a layer")
            }
        }
    }

    private var editorTitle: String {
        switch selection {
        case .fitOverlay:
            return "Fit Overlay"
        case .function:
            return "Function"
        case .referenceGuide:
            return "Guide"
        case .textAnnotation:
            return "Text"
        case .shapeAnnotation:
            return "Shape"
        case .series:
            return "Legend"
        case nil:
            return "Edit"
        }
    }

    private var fitOverlayEditor: some View {
        Group {
            AdaptiveInspectorControlRow(title: "Visible") {
                Toggle("", isOn: fitEnabledBinding)
                    .labelsHidden()
                    .disabled(!session.fitOverlayAvailability.isEnabled)
                    .help(session.fitOverlayAvailability.reason ?? "Show fit overlay.")
            }
            AdaptiveInspectorControlRow(title: "Model") {
                Picker("", selection: fitModelBinding) {
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
                .disabled(!session.fitAnalysisAvailability.isEnabled)
                .help(session.fitAnalysisAvailability.reason ?? "Choose the fit model.")
            }
        }
    }

    private func functionLayerEditor(id: String) -> some View {
        Group {
            AdaptiveInspectorControlRow(title: "Expression") {
                TextField("sin(x)", text: functionExpressionBinding(id: id))
                    .textFieldStyle(.roundedBorder)
            }
            axisRangeRow(
                title: "Domain",
                lowerTitle: "Start",
                upperTitle: "End",
                lowerBinding: functionXStartBinding(id: id),
                upperBinding: functionXEndBinding(id: id)
            )
            AdaptiveInspectorControlRow(title: "Samples") {
                Stepper(value: functionSampleCountBinding(id: id), in: 2...2000, step: 10) {
                    Text("\(functionLayer(id).sampleCount)")
                        .monospacedDigit()
                }
            }
            AdaptiveInspectorControlRow(title: "Y Axis") {
                Picker("", selection: functionYAxisTargetBinding(id: id)) {
                    Text("Primary").tag("y_primary")
                    Text("Secondary").tag("y_secondary")
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            AdaptiveInspectorControlRow(title: "Label") {
                TextField("Optional", text: functionLabelBinding(id: id))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func referenceGuideEditor(id: String) -> some View {
        let guide = referenceGuide(id)
        return Group {
            AdaptiveInspectorControlRow(title: "Kind") {
                Picker("", selection: referenceGuideKindBinding(id: id)) {
                    Text("Line").tag("line")
                    Text("Region").tag("band")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            AdaptiveInspectorControlRow(title: "Axis") {
                Picker("", selection: referenceGuideAxisTargetBinding(id: id)) {
                    referenceGuideAxisOptions(currentValue: guide.axisTarget)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            if guide.kind == "line" {
                exactGuideValueEditor(id: id)
            } else {
                exactGuideRangeEditor(id: id)
            }
            AdaptiveInspectorControlRow(title: "Label") {
                TextField("Optional", text: referenceGuideLabelBinding(id: id))
                    .textFieldStyle(.roundedBorder)
            }
            AdaptiveInspectorControlRow(title: "Visible") {
                Toggle("", isOn: referenceGuideEnabledBinding(id: id))
                    .labelsHidden()
            }
            Button(role: .destructive) {
                session.removeReferenceGuide(id: id)
                session.selectCanvasSelection(.figure)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    private func exactGuideValueEditor(id: String) -> some View {
        AdaptiveInspectorControlRow(title: "Value") {
            TextField("Value", text: referenceGuideValueBinding(id: id))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func exactGuideRangeEditor(id: String) -> some View {
        axisRangeRow(
            title: "Region",
            lowerTitle: "Start",
            upperTitle: "End",
            lowerBinding: referenceGuideStartBinding(id: id),
            upperBinding: referenceGuideEndBinding(id: id)
        )
    }

    private func textAnnotationEditor(id: String) -> some View {
        let annotation = textAnnotation(id)
        return Group {
            AdaptiveInspectorControlRow(title: "Text") {
                TextField("Annotation", text: textAnnotationTextBinding(id: id))
                    .textFieldStyle(.roundedBorder)
            }
            AdaptiveInspectorControlRow(title: "Style") {
                Picker("", selection: textAnnotationDisplayStyleBinding(id: id)) {
                    Text("Plain").tag("plain")
                    Text("Callout").tag("callout")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            AdaptiveInspectorControlRow(title: "Space") {
                Picker("", selection: textAnnotationCoordinateSpaceBinding(id: id)) {
                    Text("Frame").tag("axes_fraction")
                    Text("Data").tag("data")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            if annotation.coordinateSpace == "data" {
                AdaptiveInspectorControlRow(title: "Y Axis") {
                    Picker("", selection: textAnnotationYAxisTargetBinding(id: id)) {
                        annotationYAxisOptions(currentValue: annotation.yAxisTarget)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            annotationPositionRow(for: id)
            AdaptiveInspectorControlRow(title: "Align X") {
                Picker("", selection: textAnnotationHorizontalAlignmentBinding(id: id)) {
                    Text("Left").tag("left")
                    Text("Center").tag("center")
                    Text("Right").tag("right")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            AdaptiveInspectorControlRow(title: "Align Y") {
                Picker("", selection: textAnnotationVerticalAlignmentBinding(id: id)) {
                    Text("Top").tag("top")
                    Text("Center").tag("center")
                    Text("Bottom").tag("bottom")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            AdaptiveInspectorControlRow(title: "Connector") {
                Toggle("", isOn: textAnnotationConnectorEnabledBinding(id: id))
                    .labelsHidden()
            }
            if annotation.connectorEnabled {
                AdaptiveInspectorControlRow(title: "Target Y") {
                    Picker("", selection: textAnnotationTargetYAxisTargetBinding(id: id)) {
                        annotationYAxisOptions(currentValue: annotation.targetYAxisTarget)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                axisRangeRow(
                    title: "Target",
                    lowerTitle: "X",
                    upperTitle: "Y",
                    lowerBinding: textAnnotationTargetXBinding(id: id),
                    upperBinding: textAnnotationTargetYBinding(id: id)
                )
            }
        }
    }

    private func shapeAnnotationEditor(id: String) -> some View {
        let annotation = shapeAnnotation(id)
        return Group {
            AdaptiveInspectorControlRow(title: "Kind") {
                Picker("", selection: shapeAnnotationKindBinding(id: id)) {
                    Text("Rectangle").tag("rectangle")
                    Text("Ellipse").tag("ellipse")
                    Text("Bracket").tag("bracket")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            AdaptiveInspectorControlRow(title: "Label") {
                TextField("Optional", text: shapeAnnotationLabelBinding(id: id))
                    .textFieldStyle(.roundedBorder)
            }
            AdaptiveInspectorControlRow(title: "Y Axis") {
                Picker("", selection: shapeAnnotationYAxisTargetBinding(id: id)) {
                    annotationYAxisOptions(currentValue: annotation.yAxisTarget)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            if annotation.kind == "bracket" {
                AdaptiveInspectorControlRow(title: "Direction") {
                    Picker("", selection: shapeAnnotationBracketOrientationBinding(id: id)) {
                        Text("Horizontal").tag("horizontal")
                        Text("Vertical").tag("vertical")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                if annotation.bracketOrientation == "horizontal" {
                    axisRangeRow(
                        title: "Span X",
                        lowerTitle: "From",
                        upperTitle: "To",
                        lowerBinding: shapeAnnotationXStartBinding(id: id),
                        upperBinding: shapeAnnotationXEndBinding(id: id)
                    )
                    AdaptiveInspectorControlRow(title: "Anchor Y") {
                        TextField("Y", text: shapeAnnotationYStartBinding(id: id))
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    axisRangeRow(
                        title: "Span Y",
                        lowerTitle: "From",
                        upperTitle: "To",
                        lowerBinding: shapeAnnotationYStartBinding(id: id),
                        upperBinding: shapeAnnotationYEndBinding(id: id)
                    )
                    AdaptiveInspectorControlRow(title: "Anchor X") {
                        TextField("X", text: shapeAnnotationXStartBinding(id: id))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            } else {
                axisRangeRow(
                    title: "X range",
                    lowerTitle: "Start",
                    upperTitle: "End",
                    lowerBinding: shapeAnnotationXStartBinding(id: id),
                    upperBinding: shapeAnnotationXEndBinding(id: id)
                )
                axisRangeRow(
                    title: "Y range",
                    lowerTitle: "Start",
                    upperTitle: "End",
                    lowerBinding: shapeAnnotationYStartBinding(id: id),
                    upperBinding: shapeAnnotationYEndBinding(id: id)
                )
            }
        }
    }

    private func seriesEditor(id: String) -> some View {
        Group {
            AdaptiveInspectorTextRow(title: "Entry", value: id)
            SortableSeriesListView(
                title: "Order",
                rows: session.seriesOrderRows,
                moveItem: { rowID, offset in
                    session.moveSeriesOrder(id: rowID, by: offset)
                }
            )
            Button("Reset Order") {
                session.resetSeriesOrder()
            }
            .buttonStyle(.bordered)
            .disabled(!session.resetSeriesOrderAvailability.isEnabled)
            .help(session.resetSeriesOrderAvailability.reason ?? "Reset legend ordering.")
        }
    }

    private var fitEnabledBinding: Binding<Bool> {
        boolBinding(
            get: { session.fitOptions.enabled },
            set: { session.updateFitEnabled($0) }
        )
    }

    private var fitModelBinding: Binding<String> {
        stringBinding(
            get: { session.fitOptions.modelID },
            set: { session.updateFitModel($0) }
        )
    }

    private func functionLayer(_ id: String) -> AnalyticalLayerPayload {
        session.analyticalLayers.first(where: { $0.id == id }) ?? AnalyticalLayerPayload(id: id)
    }

    private func functionExpressionBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { functionLayer(id).expression },
            set: { value in
                session.updateAnalyticalLayer(id: id) { $0.expression = value }
            }
        )
    }

    private func functionXStartBinding(id: String) -> Binding<String> {
        functionNumberBinding(id: id, get: \.xStart) { $0.xStart = $1 }
    }

    private func functionXEndBinding(id: String) -> Binding<String> {
        functionNumberBinding(id: id, get: \.xEnd) { $0.xEnd = $1 }
    }

    private func functionNumberBinding(
        id: String,
        get: KeyPath<AnalyticalLayerPayload, Double>,
        set: @escaping (inout AnalyticalLayerPayload, Double) -> Void
    ) -> Binding<String> {
        numericValueBinding(
            get: { functionLayer(id)[keyPath: get] },
            set: { value in
                session.updateAnalyticalLayer(id: id) { layer in
                    set(&layer, value)
                }
            }
        )
    }

    private func functionSampleCountBinding(id: String) -> Binding<Int> {
        Binding {
            functionLayer(id).sampleCount
        } set: { newValue in
            session.updateAnalyticalLayer(id: id, policy: .immediate) { $0.sampleCount = newValue }
        }
    }

    private func functionYAxisTargetBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { functionLayer(id).yAxisTarget },
            set: { value in
                session.updateAnalyticalLayer(id: id, policy: .immediate) { $0.yAxisTarget = value }
            }
        )
    }

    private func functionLabelBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { functionLayer(id).label ?? "" },
            set: { value in
                session.updateAnalyticalLayer(id: id) { $0.label = value.isEmpty ? nil : value }
            }
        )
    }

    private func referenceGuide(_ id: String) -> ReferenceGuidePayload {
        session.referenceGuides.first(where: { $0.id == id }) ?? ReferenceGuidePayload(id: id)
    }

    private func referenceGuideKindBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { referenceGuide(id).kind },
            set: { kind in
                session.updateReferenceGuide(id: id) { guide in
                    guide.kind = kind
                    if kind == "line" {
                        guide.value = guide.value ?? guide.start ?? 0.0
                        guide.start = nil
                        guide.end = nil
                    } else {
                        guide.start = guide.start ?? 0.0
                        guide.end = guide.end ?? 1.0
                        guide.value = nil
                    }
                }
            }
        )
    }

    private func referenceGuideAxisTargetBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { referenceGuide(id).axisTarget },
            set: { axisTarget in
                session.updateReferenceGuide(id: id) { $0.axisTarget = axisTarget }
            }
        )
    }

    private func referenceGuideValueBinding(id: String) -> Binding<String> {
        numericTextBinding(
            get: { referenceGuide(id).value },
            set: { value in
                session.updateReferenceGuide(id: id, policy: .debounced) { $0.value = value ?? 0.0 }
            }
        )
    }

    private func referenceGuideStartBinding(id: String) -> Binding<String> {
        numericTextBinding(
            get: { referenceGuide(id).start },
            set: { value in
                session.updateReferenceGuide(id: id, policy: .debounced) { $0.start = value ?? 0.0 }
            }
        )
    }

    private func referenceGuideEndBinding(id: String) -> Binding<String> {
        numericTextBinding(
            get: { referenceGuide(id).end },
            set: { value in
                session.updateReferenceGuide(id: id, policy: .debounced) { $0.end = value ?? 1.0 }
            }
        )
    }

    private func referenceGuideLabelBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { referenceGuide(id).label ?? "" },
            set: { label in
                session.updateReferenceGuide(id: id, policy: .debounced) { $0.label = label.isEmpty ? nil : label }
            }
        )
    }

    private func referenceGuideEnabledBinding(id: String) -> Binding<Bool> {
        boolBinding(
            get: { referenceGuide(id).enabled },
            set: { enabled in
                session.updateReferenceGuide(id: id, policy: .immediate) { $0.enabled = enabled }
            }
        )
    }

    private func textAnnotation(_ id: String) -> TextAnnotationPayload {
        session.textAnnotations.first(where: { $0.id == id }) ?? TextAnnotationPayload(id: id)
    }

    private func textAnnotationTextBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).text },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.text = value }
            }
        )
    }

    private func textAnnotationDisplayStyleBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).displayStyle },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.displayStyle = value }
            }
        )
    }

    private func textAnnotationCoordinateSpaceBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).coordinateSpace },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.coordinateSpace = value }
            }
        )
    }

    private func textAnnotationYAxisTargetBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).yAxisTarget },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.yAxisTarget = value }
            }
        )
    }

    private func textAnnotationHorizontalAlignmentBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).horizontalAlignment },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.horizontalAlignment = value }
            }
        )
    }

    private func textAnnotationVerticalAlignmentBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).verticalAlignment },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.verticalAlignment = value }
            }
        )
    }

    private func textAnnotationConnectorEnabledBinding(id: String) -> Binding<Bool> {
        boolBinding(
            get: { textAnnotation(id).connectorEnabled },
            set: { enabled in
                session.updateTextAnnotation(id: id) { annotation in
                    annotation.connectorEnabled = enabled
                    if enabled, annotation.displayStyle == "plain" {
                        annotation.displayStyle = "callout"
                    }
                }
            }
        )
    }

    private func textAnnotationXBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { textAnnotation(id).x },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.x = value }
            }
        )
    }

    private func textAnnotationYBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { textAnnotation(id).y },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.y = value }
            }
        )
    }

    private func textAnnotationTargetXBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { textAnnotation(id).targetX },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.targetX = value }
            }
        )
    }

    private func textAnnotationTargetYBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { textAnnotation(id).targetY },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.targetY = value }
            }
        )
    }

    private func textAnnotationTargetYAxisTargetBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).targetYAxisTarget },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.targetYAxisTarget = value }
            }
        )
    }

    private func shapeAnnotation(_ id: String) -> ShapeAnnotationPayload {
        session.shapeAnnotations.first(where: { $0.id == id }) ?? ShapeAnnotationPayload(id: id)
    }

    private func shapeAnnotationKindBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { shapeAnnotation(id).kind },
            set: { kind in
                session.updateShapeAnnotation(id: id) { annotation in
                    annotation.kind = kind
                    if kind == "bracket" {
                        annotation.bracketOrientation = "horizontal"
                        annotation.yEnd = annotation.yStart
                    }
                }
            }
        )
    }

    private func shapeAnnotationBracketOrientationBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { shapeAnnotation(id).bracketOrientation },
            set: { value in
                session.updateShapeAnnotation(id: id) { $0.bracketOrientation = value }
            }
        )
    }

    private func shapeAnnotationLabelBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { shapeAnnotation(id).label ?? "" },
            set: { value in
                session.updateShapeAnnotation(id: id, policy: .debounced) { $0.label = value.isEmpty ? nil : value }
            }
        )
    }

    private func shapeAnnotationYAxisTargetBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { shapeAnnotation(id).yAxisTarget },
            set: { value in
                session.updateShapeAnnotation(id: id) { $0.yAxisTarget = value }
            }
        )
    }

    private func shapeAnnotationXStartBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { shapeAnnotation(id).xStart },
            set: { value in
                session.updateShapeAnnotation(id: id, policy: .debounced) { $0.xStart = value }
            }
        )
    }

    private func shapeAnnotationXEndBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { shapeAnnotation(id).xEnd },
            set: { value in
                session.updateShapeAnnotation(id: id, policy: .debounced) { $0.xEnd = value }
            }
        )
    }

    private func shapeAnnotationYStartBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { shapeAnnotation(id).yStart },
            set: { value in
                session.updateShapeAnnotation(id: id, policy: .debounced) { $0.yStart = value }
            }
        )
    }

    private func shapeAnnotationYEndBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { shapeAnnotation(id).yEnd },
            set: { value in
                session.updateShapeAnnotation(id: id, policy: .debounced) { $0.yEnd = value }
            }
        )
    }

    @ViewBuilder
    private func referenceGuideAxisOptions(currentValue: String) -> some View {
        Text("X").tag("x")
        Text("Primary Y").tag("y_primary")
        if session.hasActiveSecondaryYAxis || currentValue == "y_secondary" {
            Text("Secondary Y").tag("y_secondary")
        }
    }

    @ViewBuilder
    private func annotationYAxisOptions(currentValue: String) -> some View {
        Text("Primary Y").tag("y_primary")
        if session.hasActiveSecondaryYAxis || currentValue == "y_secondary" {
            Text("Secondary Y").tag("y_secondary")
        }
    }

    private func annotationPositionRow(for annotationID: String) -> some View {
        axisRangeRow(
            title: "Position",
            lowerTitle: "X",
            upperTitle: "Y",
            lowerBinding: textAnnotationXBinding(id: annotationID),
            upperBinding: textAnnotationYBinding(id: annotationID)
        )
    }

    private func stringBinding(
        get: @escaping @MainActor () -> String,
        set: @escaping @MainActor (String) -> Void
    ) -> Binding<String> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    get()
                }
            },
            set: { newValue in
                MainActor.assumeIsolated {
                    set(newValue)
                }
            }
        )
    }

    private func boolBinding(
        get: @escaping @MainActor () -> Bool,
        set: @escaping @MainActor (Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    get()
                }
            },
            set: { newValue in
                MainActor.assumeIsolated {
                    set(newValue)
                }
            }
        )
    }

    private func numericTextBinding(
        get: @escaping @MainActor () -> Double?,
        set: @escaping @MainActor (Double?) -> Void
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = MainActor.assumeIsolated({
                    get()
                }) else {
                    return ""
                }
                return value.formatted(.number.precision(.fractionLength(0...4)))
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                MainActor.assumeIsolated {
                    if trimmed.isEmpty {
                        set(nil)
                    } else if let parsed = Double(trimmed) {
                        set(parsed)
                    }
                }
            }
        )
    }

    private func numericValueBinding(
        get: @escaping @MainActor () -> Double,
        set: @escaping @MainActor (Double) -> Void
    ) -> Binding<String> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    get().formatted(.number.precision(.fractionLength(0...4)))
                }
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let parsed = Double(trimmed) else {
                    return
                }
                MainActor.assumeIsolated {
                    set(parsed)
                }
            }
        )
    }

    private func axisRangeRow(
        title: String,
        lowerTitle: String,
        upperTitle: String,
        lowerBinding: Binding<String>,
        upperBinding: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                labeledField(label: lowerTitle, binding: lowerBinding)
                labeledField(label: upperTitle, binding: upperBinding)
            }
        }
    }

    private func labeledField(label: String, binding: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, text: binding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 84)
        }
    }
}
