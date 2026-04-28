import SwiftUI

struct PlotRefineView: View {
    @Bindable var session: PlotSession

    var body: some View {
        ZStack(alignment: .topLeading) {
            previewSurface

            if session.selectedFileURL != nil {
                VStack(alignment: .leading, spacing: 8) {
                    PlotToolStripView(session: session)

                    if session.selectedPlotTool.showsCanvasOptions {
                        PlotToolOptionsBar(session: session)
                            .transition(MotionTokens.stateTransition)
                    }
                }
                .padding(16)
                .transition(MotionTokens.stateTransition)
            }

            if session.isPreviewing, session.previewResponse?.previews.first != nil {
                updatingBadge
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
            }

            if let selectedMovableLayer {
                PlotCanvasOverlayControlsView(
                    session: session,
                    selection: selectedMovableLayer
                )
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .transition(MotionTokens.stateTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var selectedMovableLayer: PlotLayerSelection? {
        guard case .layer(let layer) = session.canvasSelection, layer.isMovableOverlay else {
            return nil
        }
        return layer
    }

    @ViewBuilder
    private var previewSurface: some View {
        if let preview = session.previewResponse?.previews.first {
            Base64PDFPreviewView(base64PDF: preview.pdfBase64)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
                .overlay(alignment: .center) {
                    if session.isInspecting || session.isPreviewing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(10)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    SubtleStageHint(
                        title: "Preview",
                        systemImage: "doc.richtext"
                    )
                    .padding(.horizontal, 2)
                }
        }
    }

    private var updatingBadge: some View {
        ProgressView()
            .controlSize(.small)
            .padding(10)
            .background(.thinMaterial, in: Capsule())
            .foregroundStyle(.secondary)
            .transition(MotionTokens.stateTransition)
    }
}

private struct PlotToolOptionsBar: View {
    @Bindable var session: PlotSession

    var body: some View {
        HStack(spacing: 8) {
            Label(session.selectedPlotTool.title, systemImage: session.selectedPlotTool.systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)

            Divider()
                .frame(height: 18)

            optionsContent

            Divider()
                .frame(height: 18)

            Button {
                session.selectedPlotTool = .select
            } label: {
                Image(systemName: "checkmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Finish tool")
        }
        .controlSize(.small)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 5)
    }

    @ViewBuilder
    private var optionsContent: some View {
        switch session.selectedPlotTool {
        case .fit:
            fitOptions
        case .guide:
            guideOptions
        case .text:
            textOptions
        case .shape:
            shapeOptions
        case .function:
            functionOptions
        case .axisBreak:
            axisBreakOptions
        case .secondaryAxis:
            secondaryAxisOptions
        case .select, .panZoom, .dataCursor:
            EmptyView()
        }
    }

    private var fitOptions: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { session.fitOptions.enabled },
                set: { session.updateFitEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!session.fitOverlayAvailability.isEnabled)
            .help(session.fitOverlayAvailability.reason ?? "Show fit overlay.")

            Picker("", selection: Binding(
                get: { session.fitOptions.modelID },
                set: { session.updateFitModel($0) }
            )) {
                Text("Linear").tag("linear")
                Text("Poly 2").tag("polynomial_2")
                Text("Poly 3").tag("polynomial_3")
                Text("Exp").tag("exponential")
                Text("Log").tag("logarithmic")
                Text("Power").tag("power_law")
                Text("Gaussian").tag("gaussian")
                Text("Logistic").tag("logistic")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 118)
            .disabled(!session.fitAnalysisAvailability.isEnabled)
            .help(session.fitAnalysisAvailability.reason ?? "Choose the fit model.")
        }
    }

    @ViewBuilder
    private var guideOptions: some View {
        if let id = selectedReferenceGuideID {
            HStack(spacing: 8) {
                Picker("", selection: Binding(
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
                )) {
                    Text("Line").tag("line")
                    Text("Region").tag("band")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 118)

                Picker("", selection: Binding(
                    get: { referenceGuide(id).axisTarget },
                    set: { axisTarget in
                        session.updateReferenceGuide(id: id) { $0.axisTarget = axisTarget }
                    }
                )) {
                    referenceGuideAxisOptions(currentValue: referenceGuide(id).axisTarget)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 92)
            }
        } else {
            addGuideButton
        }
    }

    @ViewBuilder
    private var textOptions: some View {
        if let id = selectedTextAnnotationID {
            HStack(spacing: 8) {
                TextField("Text", text: Binding(
                    get: { textAnnotation(id).text },
                    set: { value in
                        session.updateTextAnnotation(id: id, policy: .debounced) { $0.text = value }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)

                Picker("", selection: Binding(
                    get: { textAnnotation(id).displayStyle },
                    set: { value in
                        session.updateTextAnnotation(id: id) { annotation in
                            annotation.displayStyle = value
                            annotation.connectorEnabled = value == "callout"
                        }
                    }
                )) {
                    Text("Text").tag("plain")
                    Text("Callout").tag("callout")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 128)
            }
        } else {
            addTextButton
        }
    }

    @ViewBuilder
    private var shapeOptions: some View {
        if let id = selectedShapeAnnotationID {
            Picker("", selection: Binding(
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
            )) {
                Text("Rect").tag("rectangle")
                Text("Ellipse").tag("ellipse")
                Text("Bracket").tag("bracket")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 188)
        } else {
            addShapeButton
        }
    }

    @ViewBuilder
    private var functionOptions: some View {
        if let id = selectedFunctionLayerID {
            HStack(spacing: 8) {
                TextField("f(x)", text: Binding(
                    get: { functionLayer(id).expression },
                    set: { value in
                        session.updateAnalyticalLayer(id: id) { $0.expression = value }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)

                Picker("", selection: Binding(
                    get: { functionLayer(id).yAxisTarget },
                    set: { value in
                        session.updateAnalyticalLayer(id: id, policy: .immediate) { $0.yAxisTarget = value }
                    }
                )) {
                    Text("Primary Y").tag("y_primary")
                    if session.hasActiveSecondaryYAxis || functionLayer(id).yAxisTarget == "y_secondary" {
                        Text("Secondary Y").tag("y_secondary")
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 116)
            }
        } else {
            addFunctionButton
        }
    }

    private var axisBreakOptions: some View {
        HStack(spacing: 6) {
            Button {
                session.addAxisBreak(axis: .x)
                session.selectCanvasSelection(.axis(.x))
            } label: {
                Label("X", systemImage: "arrow.left.and.right")
            }
            .disabled(!session.xAxisBreakAvailability.isEnabled)
            .help(session.xAxisBreakAvailability.reason ?? "Add an X axis break.")

            Button {
                session.addAxisBreak(axis: .y)
                session.selectCanvasSelection(.axis(.y))
            } label: {
                Label("Y", systemImage: "arrow.up.and.down")
            }
            .disabled(!session.yAxisBreakAvailability.isEnabled)
            .help(session.yAxisBreakAvailability.reason ?? "Add a Y axis break.")
        }
        .buttonStyle(.bordered)
    }

    private var secondaryAxisOptions: some View {
        Toggle("Secondary Y", isOn: Binding(
            get: { session.renderOptions.extraYAxis?.enabled ?? false },
            set: { enabled in
                session.updateExtraYAxis { axis in
                    axis.enabled = enabled
                }
                session.selectCanvasSelection(.axis(.y))
            }
        ))
        .toggleStyle(.switch)
        .disabled(!session.extraYAxisAvailability.isEnabled)
        .help(session.extraYAxisAvailability.reason ?? "Show secondary Y axis.")
    }

    private var addGuideButton: some View {
        Button {
            session.addReferenceGuide(kind: "line")
            if let id = session.selectedReferenceGuideID {
                session.selectPlotLayer(.referenceGuide(id))
            }
        } label: {
            Label("Add Guide", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .disabled(!session.referenceGuideAvailability.isEnabled)
        .help(session.referenceGuideAvailability.reason ?? "Add a reference guide.")
    }

    private var addTextButton: some View {
        Button {
            session.addTextAnnotation()
            if let id = session.selectedTextAnnotationID {
                session.selectPlotLayer(.textAnnotation(id))
            }
        } label: {
            Label("Add Text", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .disabled(!session.textAnnotationAvailability.isEnabled)
        .help(session.textAnnotationAvailability.reason ?? "Add a text note.")
    }

    private var addShapeButton: some View {
        Button {
            session.addShapeAnnotation(kind: "rectangle")
            if let id = session.selectedShapeAnnotationID {
                session.selectPlotLayer(.shapeAnnotation(id))
            }
        } label: {
            Label("Add Shape", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .disabled(!session.shapeAnnotationAvailability.isEnabled)
        .help(session.shapeAnnotationAvailability.reason ?? "Add a shape annotation.")
    }

    private var addFunctionButton: some View {
        Button {
            session.addAnalyticalFunctionLayer()
            if let layer = session.analyticalLayers.last {
                session.selectPlotLayer(.function(layer.id))
            }
        } label: {
            Label("Add Function", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .disabled(!session.analyticalLayerAvailability.isEnabled)
        .help(session.analyticalLayerAvailability.reason ?? "Add a function layer.")
    }

    private var selectedReferenceGuideID: String? {
        if case .layer(.referenceGuide(let id)) = session.canvasSelection {
            return id
        }
        return session.selectedReferenceGuideID
    }

    private var selectedTextAnnotationID: String? {
        if case .layer(.textAnnotation(let id)) = session.canvasSelection {
            return id
        }
        return session.selectedTextAnnotationID
    }

    private var selectedShapeAnnotationID: String? {
        if case .layer(.shapeAnnotation(let id)) = session.canvasSelection {
            return id
        }
        return session.selectedShapeAnnotationID
    }

    private var selectedFunctionLayerID: String? {
        if case .layer(.function(let id)) = session.canvasSelection {
            return id
        }
        return session.analyticalLayers.last?.id
    }

    private func referenceGuide(_ id: String) -> ReferenceGuidePayload {
        session.referenceGuides.first(where: { $0.id == id }) ?? ReferenceGuidePayload(id: id)
    }

    private func textAnnotation(_ id: String) -> TextAnnotationPayload {
        session.textAnnotations.first(where: { $0.id == id }) ?? TextAnnotationPayload(id: id)
    }

    private func shapeAnnotation(_ id: String) -> ShapeAnnotationPayload {
        session.shapeAnnotations.first(where: { $0.id == id }) ?? ShapeAnnotationPayload(id: id)
    }

    private func functionLayer(_ id: String) -> AnalyticalLayerPayload {
        session.analyticalLayers.first(where: { $0.id == id }) ?? AnalyticalLayerPayload(id: id)
    }

    @ViewBuilder
    private func referenceGuideAxisOptions(currentValue: String) -> some View {
        Text("X").tag("x")
        Text("Primary Y").tag("y_primary")
        if session.hasActiveSecondaryYAxis || currentValue == "y_secondary" {
            Text("Secondary Y").tag("y_secondary")
        }
    }

    private func compactText(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct PlotCanvasOverlayControlsView: View {
    @Bindable var session: PlotSession
    let selection: PlotLayerSelection

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .labelStyle(.titleAndIcon)

                Text(positionLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()
                .frame(height: 18)

            nudgeButton(
                "arrow.left",
                deltaX: -stepX,
                deltaY: 0,
                shortcut: .leftArrow,
                help: "Nudge left"
            )
            VStack(spacing: 3) {
                nudgeButton(
                    "arrow.up",
                    deltaX: 0,
                    deltaY: stepY,
                    shortcut: .upArrow,
                    help: "Nudge up"
                )
                nudgeButton(
                    "arrow.down",
                    deltaX: 0,
                    deltaY: -stepY,
                    shortcut: .downArrow,
                    help: "Nudge down"
                )
            }
            nudgeButton(
                "arrow.right",
                deltaX: stepX,
                deltaY: 0,
                shortcut: .rightArrow,
                help: "Nudge right"
            )

            Divider()
                .frame(height: 18)

            Button {
                deleteSelection()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete selected overlay")

            Button {
                session.selectedPlotTool = .select
                session.selectCanvasSelection(.figure)
            } label: {
                Image(systemName: "checkmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Finish editing")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 6)
        .help("Use Option + Arrow keys to nudge the selected overlay.")
    }

    private var title: String {
        switch selection {
        case .referenceGuide(let id):
            if let guide = session.referenceGuides.first(where: { $0.id == id }) {
                return guide.kind == "band" ? "Region" : "Guide"
            }
            return "Guide"
        case .textAnnotation:
            return "Text"
        case .shapeAnnotation(let id):
            if let shape = session.shapeAnnotations.first(where: { $0.id == id }) {
                switch shape.kind {
                case "ellipse":
                    return "Ellipse"
                case "bracket":
                    return "Bracket"
                default:
                    return "Shape"
                }
            }
            return "Shape"
        case .fitOverlay, .function, .series:
            return "Object"
        }
    }

    private var systemImage: String {
        switch selection {
        case .referenceGuide:
            return "ruler"
        case .textAnnotation:
            return "textformat"
        case .shapeAnnotation:
            return "rectangle.dashed"
        case .fitOverlay:
            return "chart.xyaxis.line"
        case .function:
            return "function"
        case .series:
            return "list.bullet.rectangle"
        }
    }

    private var positionLabel: String {
        switch selection {
        case .referenceGuide(let id):
            guard let guide = session.referenceGuides.first(where: { $0.id == id }) else {
                return "x --  y --"
            }
            if guide.kind == "line" {
                let value = guide.value ?? 0.0
                return guide.axisTarget == "x" ? "x \(formatted(value))" : "y \(formatted(value))"
            }
            let start = guide.start ?? 0.0
            let end = guide.end ?? 1.0
            return "\(formatted(start))...\(formatted(end))"
        case .textAnnotation(let id):
            guard let annotation = session.textAnnotations.first(where: { $0.id == id }) else {
                return "x --  y --"
            }
            return "x \(formatted(annotation.x))  y \(formatted(annotation.y))"
        case .shapeAnnotation(let id):
            guard let shape = session.shapeAnnotations.first(where: { $0.id == id }) else {
                return "x --  y --"
            }
            let centerX = (shape.xStart + shape.xEnd) / 2.0
            let centerY = (shape.yStart + shape.yEnd) / 2.0
            return "x \(formatted(centerX))  y \(formatted(centerY))"
        case .fitOverlay, .function, .series:
            return "x --  y --"
        }
    }

    private var stepX: Double {
        switch selection {
        case .textAnnotation(let id):
            let annotation = session.textAnnotations.first(where: { $0.id == id })
            return annotation?.coordinateSpace == "axes_fraction" ? 0.02 : 0.1
        case .shapeAnnotation:
            return 0.05
        default:
            return 0.1
        }
    }

    private var stepY: Double {
        stepX
    }

    private func nudgeButton(
        _ systemImage: String,
        deltaX: Double,
        deltaY: Double,
        shortcut: KeyEquivalent,
        help: String
    ) -> some View {
        Button {
            nudge(deltaX: deltaX, deltaY: deltaY)
        } label: {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .keyboardShortcut(shortcut, modifiers: [.option])
        .help("\(help) with Option-\(shortcutLabel(shortcut))")
    }

    private func nudge(deltaX: Double, deltaY: Double) {
        switch selection {
        case .referenceGuide(let id):
            session.nudgeReferenceGuide(id: id, deltaX: deltaX, deltaY: deltaY)
        case .textAnnotation(let id):
            session.nudgeTextAnnotationPosition(id: id, deltaX: deltaX, deltaY: deltaY)
        case .shapeAnnotation(let id):
            session.nudgeShapeAnnotation(id: id, deltaX: deltaX, deltaY: deltaY)
        case .fitOverlay, .function, .series:
            break
        }
    }

    private func deleteSelection() {
        switch selection {
        case .referenceGuide(let id):
            session.removeReferenceGuide(id: id)
        case .textAnnotation(let id):
            session.removeTextAnnotation(id: id)
        case .shapeAnnotation(let id):
            session.removeShapeAnnotation(id: id)
        case .fitOverlay, .function, .series:
            break
        }
        session.selectedPlotTool = .select
        session.selectCanvasSelection(.figure)
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }

    private func shortcutLabel(_ shortcut: KeyEquivalent) -> String {
        switch shortcut {
        case .leftArrow:
            return "Left"
        case .rightArrow:
            return "Right"
        case .upArrow:
            return "Up"
        case .downArrow:
            return "Down"
        default:
            return "Arrow"
        }
    }
}
