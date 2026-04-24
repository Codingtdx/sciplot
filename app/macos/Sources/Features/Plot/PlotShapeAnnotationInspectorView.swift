import SwiftUI

struct PlotShapeAnnotationInspectorView: View {
    @Bindable var session: PlotSession

    var body: some View {
        DisclosureGroup("Shape Annotations") {
            HStack(spacing: 10) {
                Button("Add Rectangle") {
                    session.addShapeAnnotation(kind: "rectangle")
                }
                .buttonStyle(.bordered)

                Button("Add Ellipse") {
                    session.addShapeAnnotation(kind: "ellipse")
                }
                .buttonStyle(.bordered)

                Button("Add Bracket") {
                    session.addShapeAnnotation(kind: "bracket")
                }
                .buttonStyle(.bordered)
            }
            .disabled(!session.shapeAnnotationAvailability.isEnabled)
            .help(session.shapeAnnotationAvailability.reason ?? "Overlay regions and bracket callouts on the current figure.")

            ForEach(session.shapeAnnotations) { annotation in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(shapeAnnotationTitle(annotation))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Button(isShapeAnnotationSelected(annotation.id) ? "Selected" : "Select") {
                            session.selectShapeAnnotation(id: annotation.id)
                        }
                        .buttonStyle(.bordered)

                        Button("Remove") {
                            session.removeShapeAnnotation(id: annotation.id)
                        }
                        .buttonStyle(.bordered)
                    }

                    AdaptiveInspectorControlRow(title: "Visible") {
                        Toggle("", isOn: shapeAnnotationEnabledBinding(id: annotation.id))
                            .labelsHidden()
                    }

                    AdaptiveInspectorControlRow(title: "Kind") {
                        Picker("", selection: shapeAnnotationKindBinding(id: annotation.id)) {
                            Text("Rectangle").tag("rectangle")
                            Text("Ellipse").tag("ellipse")
                            Text("Bracket").tag("bracket")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    AdaptiveInspectorControlRow(title: "Label") {
                        TextField("Optional", text: shapeAnnotationLabelBinding(id: annotation.id))
                            .textFieldStyle(.roundedBorder)
                    }

                    AdaptiveInspectorControlRow(title: "Y Axis") {
                        Picker("", selection: shapeAnnotationYAxisTargetBinding(id: annotation.id)) {
                            annotationYAxisOptions(currentValue: shapeAnnotation(annotation.id).yAxisTarget)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    if shapeAnnotation(annotation.id).kind == "bracket" {
                        AdaptiveInspectorControlRow(title: "Direction") {
                            Picker("", selection: shapeAnnotationBracketOrientationBinding(id: annotation.id)) {
                                Text("Horizontal").tag("horizontal")
                                Text("Vertical").tag("vertical")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        if shapeAnnotation(annotation.id).bracketOrientation == "horizontal" {
                            axisRangeRow(
                                title: "Span X",
                                lowerTitle: "From",
                                upperTitle: "To",
                                lowerBinding: shapeAnnotationXStartBinding(id: annotation.id),
                                upperBinding: shapeAnnotationXEndBinding(id: annotation.id)
                            )

                            AdaptiveInspectorControlRow(title: "Anchor Y") {
                                TextField("Y", text: shapeAnnotationYStartBinding(id: annotation.id))
                                    .textFieldStyle(.roundedBorder)
                            }
                        } else {
                            axisRangeRow(
                                title: "Span Y",
                                lowerTitle: "From",
                                upperTitle: "To",
                                lowerBinding: shapeAnnotationYStartBinding(id: annotation.id),
                                upperBinding: shapeAnnotationYEndBinding(id: annotation.id)
                            )

                            AdaptiveInspectorControlRow(title: "Anchor X") {
                                TextField("X", text: shapeAnnotationXStartBinding(id: annotation.id))
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    } else {
                        axisRangeRow(
                            title: "X range",
                            lowerTitle: "Start",
                            upperTitle: "End",
                            lowerBinding: shapeAnnotationXStartBinding(id: annotation.id),
                            upperBinding: shapeAnnotationXEndBinding(id: annotation.id)
                        )

                        axisRangeRow(
                            title: "Y range",
                            lowerTitle: "Start",
                            upperTitle: "End",
                            lowerBinding: shapeAnnotationYStartBinding(id: annotation.id),
                            upperBinding: shapeAnnotationYEndBinding(id: annotation.id)
                        )
                    }

                    if isShapeAnnotationSelected(annotation.id) {
                        shapeAnnotationTransformControls(for: annotation)
                    }
                }
                .padding(10)
                .background(isShapeAnnotationSelected(annotation.id) ? Color.accentColor.opacity(0.08) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 6)
            }
        }
    }

    private func shapeAnnotation(_ id: String) -> ShapeAnnotationPayload {
        session.shapeAnnotations.first(where: { $0.id == id }) ?? ShapeAnnotationPayload(id: id)
    }

    private func shapeAnnotationTitle(_ annotation: ShapeAnnotationPayload) -> String {
        let label = annotation.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !label.isEmpty {
            return label
        }
        switch annotation.kind {
        case "ellipse":
            return "Ellipse"
        case "bracket":
            return "Bracket"
        default:
            return "Rectangle"
        }
    }

    private func isShapeAnnotationSelected(_ id: String) -> Bool {
        session.selectedShapeAnnotationID == id
    }

    private func shapeAnnotationEnabledBinding(id: String) -> Binding<Bool> {
        boolBinding(
            get: { shapeAnnotation(id).enabled },
            set: { enabled in
                session.updateShapeAnnotation(id: id) { $0.enabled = enabled }
            }
        )
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
    private func annotationYAxisOptions(currentValue: String) -> some View {
        Text("Primary Y").tag("y_primary")
        if session.hasActiveSecondaryYAxis || currentValue == "y_secondary" {
            Text("Secondary Y").tag("y_secondary")
        }
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
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                labeledField(label: lowerTitle, binding: lowerBinding)
                labeledField(label: upperTitle, binding: upperBinding)
            }
        }
    }

    private func shapeAnnotationTransformControls(for annotation: ShapeAnnotationPayload) -> some View {
        let centerX = (annotation.xStart + annotation.xEnd) / 2.0
        let centerY = (annotation.yStart + annotation.yEnd) / 2.0

        return PlotOverlayTransformControls(
            title: "Move Shape",
            xLabel: "X",
            yLabel: "Y",
            xValue: centerX,
            yValue: centerY,
            stepX: 0.05,
            stepY: 0.05
        ) { deltaX, deltaY in
            session.nudgeShapeAnnotation(
                id: annotation.id,
                deltaX: deltaX,
                deltaY: deltaY,
                policy: .debounced
            )
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
