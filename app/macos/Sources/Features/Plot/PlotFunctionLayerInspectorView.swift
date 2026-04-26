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
