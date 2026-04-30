import SwiftUI

extension PlotInspectorView {
    func sizeBinding(defaultSize: String) -> Binding<String> {
        stringBinding(
            get: { session.renderOptions.size ?? defaultSize },
            set: { newValue in
                session.updateRenderOptions(policy: .immediate) { $0.size = newValue }
            }
        )
    }

    func stringBinding(
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

    func boolBinding(
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

    var fitEnabledBinding: Binding<Bool> {
        boolBinding(
            get: { session.fitOptions.enabled },
            set: { session.updateFitEnabled($0) }
        )
    }

    var fitModelBinding: Binding<String> {
        stringBinding(
            get: { session.fitOptions.modelID },
            set: { session.updateFitModel($0) }
        )
    }

    func annotationTitle(_ annotation: TextAnnotationPayload) -> String {
        let trimmed = annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Annotation" : trimmed
    }

    func textAnnotation(_ id: String) -> TextAnnotationPayload {
        session.textAnnotations.first(where: { $0.id == id }) ?? TextAnnotationPayload(id: id)
    }

    func textAnnotationEnabledBinding(id: String) -> Binding<Bool> {
        boolBinding(
            get: { textAnnotation(id).enabled },
            set: { enabled in
                session.updateTextAnnotation(id: id) { $0.enabled = enabled }
            }
        )
    }

    func textAnnotationTextBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).text },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.text = value }
            }
        )
    }

    func textAnnotationCoordinateSpaceBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).coordinateSpace },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.coordinateSpace = value }
            }
        )
    }

    @ViewBuilder
    func annotationYAxisOptions(currentValue: String) -> some View {
        Text("Primary Y").tag("y_primary")
        if session.hasActiveSecondaryYAxis || currentValue == "y_secondary" {
            Text("Secondary Y").tag("y_secondary")
        }
    }

    func textAnnotationDisplayStyleBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).displayStyle },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.displayStyle = value }
            }
        )
    }

    func textAnnotationYAxisTargetBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).yAxisTarget },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.yAxisTarget = value }
            }
        )
    }

    func textAnnotationHorizontalAlignmentBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).horizontalAlignment },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.horizontalAlignment = value }
            }
        )
    }

    func textAnnotationVerticalAlignmentBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).verticalAlignment },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.verticalAlignment = value }
            }
        )
    }

    func textAnnotationConnectorEnabledBinding(id: String) -> Binding<Bool> {
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

    func textAnnotationXBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { textAnnotation(id).x },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.x = value }
            }
        )
    }

    func textAnnotationTargetXBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { textAnnotation(id).targetX },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.targetX = value }
            }
        )
    }

    func textAnnotationTargetYBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { textAnnotation(id).targetY },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.targetY = value }
            }
        )
    }

    func textAnnotationTargetYAxisTargetBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).targetYAxisTarget },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.targetYAxisTarget = value }
            }
        )
    }

    func textAnnotationYBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { textAnnotation(id).y },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.y = value }
            }
        )
    }

    func numericTextBinding(
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

    func numericValueBinding(
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

    func axisRangeRow(
        title: String,
        lowerTitle: String,
        upperTitle: String,
        lowerBinding: Binding<String>,
        upperBinding: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                labeledField(label: lowerTitle, binding: lowerBinding)
                labeledField(label: upperTitle, binding: upperBinding)
            }
        }
    }

    func labeledField(label: String, binding: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, text: binding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 84)
        }
    }

    func annotationPositionRow(for annotationID: String) -> some View {
        axisRangeRow(
            title: "Position",
            lowerTitle: "X",
            upperTitle: "Y",
            lowerBinding: textAnnotationXBinding(id: annotationID),
            upperBinding: textAnnotationYBinding(id: annotationID)
        )
    }

    func axisTickLabelControls(title: String, axis: PlotAxisSelection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if supportsTickDensity(for: axis) {
                AdaptiveInspectorControlRow(title: "Density") {
                    Picker("", selection: tickDensityBinding(for: axis)) {
                        Text("Auto").tag("auto")
                        Text("Sparse").tag("sparse")
                        Text("Dense").tag("dense")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                .disabled(isLogScale(axis))
                .help(isLogScale(axis) ? "Density is available on linear axes only." : "")
            }

            if supportsTickEdgeLabels(for: axis) {
                AdaptiveInspectorControlRow(title: "Edge labels") {
                    Picker("", selection: tickEdgeLabelsBinding(for: axis)) {
                        Text("Auto").tag("auto")
                        Text("Hide Min").tag("hide_min")
                        Text("Hide Max").tag("hide_max")
                        Text("Hide Both").tag("hide_both")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
    }
}
