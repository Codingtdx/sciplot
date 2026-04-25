import SwiftUI

struct PlotFunctionLayerInspectorView: View {
    @Bindable var session: PlotSession

    var body: some View {
        DisclosureGroup("Functions") {
            Button("Add Function") {
                session.addAnalyticalFunctionLayer()
            }
            .buttonStyle(.bordered)
            .disabled(!session.analyticalLayerAvailability.isEnabled)
            .help(session.analyticalLayerAvailability.reason ?? "Overlay a sampled analytic function on this plot.")

            ForEach(session.analyticalLayers) { layer in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(layer.label?.isEmpty == false ? layer.label ?? "Function" : layer.expression)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Button("Remove") {
                            session.removeAnalyticalLayer(id: layer.id)
                        }
                        .buttonStyle(.bordered)
                    }

                    AdaptiveInspectorControlRow(title: "Visible") {
                        Toggle("", isOn: enabledBinding(id: layer.id))
                            .labelsHidden()
                    }

                    AdaptiveInspectorControlRow(title: "Expression") {
                        TextField("sin(x)", text: expressionBinding(id: layer.id))
                            .textFieldStyle(.roundedBorder)
                    }

                    AdaptiveInspectorControlRow(title: "Domain") {
                        HStack(spacing: 8) {
                            TextField("Start", text: xStartBinding(id: layer.id))
                                .textFieldStyle(.roundedBorder)
                            TextField("End", text: xEndBinding(id: layer.id))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    AdaptiveInspectorControlRow(title: "Samples") {
                        Stepper(value: sampleCountBinding(id: layer.id), in: 2...2000, step: 10) {
                            Text("\(functionLayer(layer.id).sampleCount)")
                                .monospacedDigit()
                        }
                    }

                    AdaptiveInspectorControlRow(title: "Y Axis") {
                        Picker("", selection: yAxisTargetBinding(id: layer.id)) {
                            Text("Primary").tag("y_primary")
                            Text("Secondary").tag("y_secondary")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    AdaptiveInspectorControlRow(title: "Label") {
                        TextField("Optional", text: labelBinding(id: layer.id))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func functionLayer(_ id: String) -> AnalyticalLayerPayload {
        session.analyticalLayers.first(where: { $0.id == id }) ?? AnalyticalLayerPayload(id: id)
    }

    private func enabledBinding(id: String) -> Binding<Bool> {
        Binding {
            functionLayer(id).enabled
        } set: { newValue in
            session.updateAnalyticalLayer(id: id, policy: .immediate) { $0.enabled = newValue }
        }
    }

    private func expressionBinding(id: String) -> Binding<String> {
        Binding {
            functionLayer(id).expression
        } set: { newValue in
            session.updateAnalyticalLayer(id: id) { $0.expression = newValue }
        }
    }

    private func xStartBinding(id: String) -> Binding<String> {
        numberBinding(id: id, get: \.xStart) { $0.xStart = $1 }
    }

    private func xEndBinding(id: String) -> Binding<String> {
        numberBinding(id: id, get: \.xEnd) { $0.xEnd = $1 }
    }

    private func numberBinding(
        id: String,
        get: KeyPath<AnalyticalLayerPayload, Double>,
        set: @escaping (inout AnalyticalLayerPayload, Double) -> Void
    ) -> Binding<String> {
        Binding {
            functionLayer(id)[keyPath: get].formatted(.number.precision(.fractionLength(4)))
        } set: { newValue in
            guard let value = Double(newValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return
            }
            session.updateAnalyticalLayer(id: id) { layer in
                set(&layer, value)
            }
        }
    }

    private func sampleCountBinding(id: String) -> Binding<Int> {
        Binding {
            functionLayer(id).sampleCount
        } set: { newValue in
            session.updateAnalyticalLayer(id: id, policy: .immediate) { $0.sampleCount = newValue }
        }
    }

    private func yAxisTargetBinding(id: String) -> Binding<String> {
        Binding {
            functionLayer(id).yAxisTarget
        } set: { newValue in
            session.updateAnalyticalLayer(id: id, policy: .immediate) { $0.yAxisTarget = newValue }
        }
    }

    private func labelBinding(id: String) -> Binding<String> {
        Binding {
            functionLayer(id).label ?? ""
        } set: { newValue in
            session.updateAnalyticalLayer(id: id) { $0.label = newValue.isEmpty ? nil : newValue }
        }
    }
}

struct PlotDataTransformInspectorView: View {
    @Bindable var session: PlotSession

    var body: some View {
        DisclosureGroup("Data") {
            HStack(spacing: 8) {
                Button("Derived") {
                    session.addDataTransform(kind: "derived_column")
                }
                Button("Filter") {
                    session.addDataTransform(kind: "row_filter")
                }
                Button("Pivot") {
                    session.addDataTransform(kind: "pivot_matrix")
                }
            }
            .buttonStyle(.bordered)
            .disabled(!session.dataTransformAvailability.isEnabled)
            .help(session.dataTransformAvailability.reason ?? "Apply backend-owned typed transforms before rendering.")

            ForEach(session.dataTransforms) { transform in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(transform.label?.isEmpty == false ? transform.label ?? transform.kind : transform.kind)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Toggle("", isOn: enabledBinding(id: transform.id))
                            .labelsHidden()

                        Button("Remove") {
                            session.removeDataTransform(id: transform.id)
                        }
                        .buttonStyle(.bordered)
                    }

                    AdaptiveInspectorControlRow(title: "Label") {
                        TextField("Optional", text: textBinding(id: transform.id, keyPath: \.label))
                            .textFieldStyle(.roundedBorder)
                    }

                    switch transform.kind {
                    case "row_filter":
                        rowFilterControls(id: transform.id)
                    case "pivot_matrix":
                        pivotControls(id: transform.id)
                    default:
                        derivedColumnControls(id: transform.id)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func dataTransform(_ id: String) -> DataTransformPayload {
        session.dataTransforms.first(where: { $0.id == id }) ?? DataTransformPayload(id: id)
    }

    private func derivedColumnControls(id: String) -> some View {
        Group {
            AdaptiveInspectorControlRow(title: "Target") {
                TextField("Column", text: textBinding(id: id, keyPath: \.targetColumn))
                    .textFieldStyle(.roundedBorder)
            }

            AdaptiveInspectorControlRow(title: "Expression") {
                TextField("x + 1", text: textBinding(id: id, keyPath: \.expression))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func rowFilterControls(id: String) -> some View {
        Group {
            AdaptiveInspectorControlRow(title: "Column") {
                TextField("Column", text: textBinding(id: id, keyPath: \.column))
                    .textFieldStyle(.roundedBorder)
            }

            AdaptiveInspectorControlRow(title: "Operator") {
                Picker("", selection: operatorBinding(id: id)) {
                    Text("=").tag("eq")
                    Text("!=").tag("ne")
                    Text("<").tag("lt")
                    Text("<=").tag("lte")
                    Text(">").tag("gt")
                    Text(">=").tag("gte")
                    Text("Between").tag("between")
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            AdaptiveInspectorControlRow(title: "Value") {
                HStack(spacing: 8) {
                    TextField("Value", text: jsonValueBinding(id: id))
                        .textFieldStyle(.roundedBorder)
                    TextField("Lower", text: numberBinding(id: id, keyPath: \.lower))
                        .textFieldStyle(.roundedBorder)
                    TextField("Upper", text: numberBinding(id: id, keyPath: \.upper))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func pivotControls(id: String) -> some View {
        Group {
            AdaptiveInspectorControlRow(title: "X/Y/Z") {
                HStack(spacing: 8) {
                    TextField("X", text: textBinding(id: id, keyPath: \.xColumn))
                        .textFieldStyle(.roundedBorder)
                    TextField("Y", text: textBinding(id: id, keyPath: \.yColumn))
                        .textFieldStyle(.roundedBorder)
                    TextField("Z", text: textBinding(id: id, keyPath: \.zColumn))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func enabledBinding(id: String) -> Binding<Bool> {
        Binding {
            dataTransform(id).enabled
        } set: { newValue in
            session.updateDataTransform(id: id, policy: .immediate) { $0.enabled = newValue }
        }
    }

    private func operatorBinding(id: String) -> Binding<String> {
        Binding {
            dataTransform(id).filterOperator
        } set: { newValue in
            session.updateDataTransform(id: id, policy: .immediate) { $0.filterOperator = newValue }
        }
    }

    private func textBinding(id: String, keyPath: WritableKeyPath<DataTransformPayload, String?>) -> Binding<String> {
        Binding {
            dataTransform(id)[keyPath: keyPath] ?? ""
        } set: { newValue in
            session.updateDataTransform(id: id) { transform in
                transform[keyPath: keyPath] = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newValue
            }
        }
    }

    private func numberBinding(id: String, keyPath: WritableKeyPath<DataTransformPayload, Double?>) -> Binding<String> {
        Binding {
            dataTransform(id)[keyPath: keyPath]?.formatted(.number.precision(.fractionLength(4))) ?? ""
        } set: { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            session.updateDataTransform(id: id) { transform in
                transform[keyPath: keyPath] = trimmed.isEmpty ? nil : Double(trimmed)
            }
        }
    }

    private func jsonValueBinding(id: String) -> Binding<String> {
        Binding {
            switch dataTransform(id).value {
            case .string(let value):
                return value
            case .number(let value):
                return value.formatted(.number.precision(.fractionLength(4)))
            case .bool(let value):
                return value ? "true" : "false"
            default:
                return ""
            }
        } set: { newValue in
            session.updateDataTransform(id: id) { transform in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    transform.value = nil
                } else if let number = Double(trimmed) {
                    transform.value = .number(number)
                } else {
                    transform.value = .string(trimmed)
                }
            }
        }
    }
}
