import SwiftUI

struct PlotDataTransformInspectorView: View {
    @Bindable var session: PlotSession

    var body: some View {
        DisclosureGroup("Data") {
            let summary = session.dataPipelineSummary
            AdaptiveInspectorTextRow(title: "Pipeline", value: summary.title)
            AdaptiveInspectorTextRow(title: "Status", value: summary.detail)

            HStack(spacing: 8) {
                Button("Variable") {
                    session.addDataVariable(kind: "scalar")
                }
                Button("Expression Var") {
                    session.addDataVariable(kind: "expression")
                }
            }
            .buttonStyle(.bordered)
            .disabled(!session.dataTransformAvailability.isEnabled)

            ForEach(session.dataVariables) { variable in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(variable.label?.isEmpty == false ? variable.label ?? variable.id : variable.id)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Toggle("", isOn: variableEnabledBinding(id: variable.id))
                            .labelsHidden()
                        Button("Remove") {
                            session.removeDataVariable(id: variable.id)
                        }
                        .buttonStyle(.bordered)
                    }
                    AdaptiveInspectorControlRow(title: "Name") {
                        TextField("baseline", text: variableTextBinding(id: variable.id, keyPath: \.id))
                            .textFieldStyle(.roundedBorder)
                    }
                    AdaptiveInspectorControlRow(title: "Kind") {
                        Picker("", selection: variableTextBinding(id: variable.id, keyPath: \.kind)) {
                            Text("Scalar").tag("scalar")
                            Text("Expression").tag("expression")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    if variable.kind == "expression" {
                        AdaptiveInspectorControlRow(title: "Expression") {
                            TextField("1 + 1", text: variableTextBinding(id: variable.id, keyPath: \.expression))
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        AdaptiveInspectorControlRow(title: "Value") {
                            TextField("1", text: variableNumberBinding(id: variable.id))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(.top, 6)
            }

            HStack(spacing: 8) {
                Button("Derived") {
                    session.addDataTransform(kind: "derived_column")
                }
                Button("Mask") {
                    session.addDataTransform(kind: "mask_filter")
                }
                Button("Filter") {
                    session.addDataTransform(kind: "row_filter")
                }
                Button("Pivot") {
                    session.addDataTransform(kind: "pivot_matrix")
                }
                Button("Bin") {
                    session.addDataTransform(kind: "bin_column")
                }
                Button("Smooth") {
                    session.addDataTransform(kind: "rolling_window")
                }
                Button("Aggregate") {
                    session.addDataTransform(kind: "aggregate_summary")
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
                    case "mask_filter":
                        expressionOnlyControls(id: transform.id, placeholder: "col('x') > 0")
                    case "row_filter":
                        rowFilterControls(id: transform.id)
                    case "pivot_matrix":
                        pivotControls(id: transform.id)
                    case "bin_column":
                        binControls(id: transform.id)
                    case "rolling_window":
                        rollingControls(id: transform.id)
                    case "aggregate_summary":
                        aggregateControls(id: transform.id)
                    case "sort_rows", "select_columns", "type_cast":
                        columnListControls(id: transform.id)
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

    private func dataVariable(_ id: String) -> DataVariablePayload {
        session.dataVariables.first(where: { $0.id == id }) ?? DataVariablePayload(id: id)
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

    private func expressionOnlyControls(id: String, placeholder: String) -> some View {
        AdaptiveInspectorControlRow(title: "Expression") {
            TextField(placeholder, text: textBinding(id: id, keyPath: \.expression))
                .textFieldStyle(.roundedBorder)
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
            AdaptiveInspectorControlRow(title: "Mode") {
                Picker("", selection: textBinding(id: id, keyPath: \.outputMode)) {
                    Text("XYZ Long").tag("xyz_long")
                    Text("Matrix").tag("matrix")
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private func binControls(id: String) -> some View {
        Group {
            AdaptiveInspectorControlRow(title: "Column") {
                TextField("Column", text: textBinding(id: id, keyPath: \.column))
                    .textFieldStyle(.roundedBorder)
            }
            AdaptiveInspectorControlRow(title: "Target/Bins") {
                HStack(spacing: 8) {
                    TextField("bin", text: textBinding(id: id, keyPath: \.targetColumn))
                        .textFieldStyle(.roundedBorder)
                    TextField("10", text: intBinding(id: id, keyPath: \.bins))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func rollingControls(id: String) -> some View {
        Group {
            AdaptiveInspectorControlRow(title: "Column") {
                TextField("Column", text: textBinding(id: id, keyPath: \.column))
                    .textFieldStyle(.roundedBorder)
            }
            AdaptiveInspectorControlRow(title: "Target/Window") {
                HStack(spacing: 8) {
                    TextField("smoothed", text: textBinding(id: id, keyPath: \.targetColumn))
                        .textFieldStyle(.roundedBorder)
                    TextField("3", text: intBinding(id: id, keyPath: \.window))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func aggregateControls(id: String) -> some View {
        Group {
            AdaptiveInspectorControlRow(title: "Group By") {
                TextField("group", text: stringListBinding(id: id, keyPath: \.groupBy))
                    .textFieldStyle(.roundedBorder)
            }
            AdaptiveInspectorControlRow(title: "Values") {
                TextField("signal", text: stringListBinding(id: id, keyPath: \.valueColumns))
                    .textFieldStyle(.roundedBorder)
            }
            AdaptiveInspectorControlRow(title: "Stats") {
                TextField("mean,sd,sem,count", text: stringListBinding(id: id, keyPath: \.statistics))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func columnListControls(id: String) -> some View {
        AdaptiveInspectorControlRow(title: "Columns") {
            TextField("x, y", text: stringListBinding(id: id, keyPath: \.columns))
                .textFieldStyle(.roundedBorder)
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

    private func textBinding(id: String, keyPath: WritableKeyPath<DataTransformPayload, String>) -> Binding<String> {
        Binding {
            dataTransform(id)[keyPath: keyPath]
        } set: { newValue in
            session.updateDataTransform(id: id) { transform in
                transform[keyPath: keyPath] = newValue
            }
        }
    }

    private func intBinding(id: String, keyPath: WritableKeyPath<DataTransformPayload, Int?>) -> Binding<String> {
        Binding {
            dataTransform(id)[keyPath: keyPath]?.formatted() ?? ""
        } set: { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            session.updateDataTransform(id: id) { transform in
                transform[keyPath: keyPath] = trimmed.isEmpty ? nil : Int(trimmed)
            }
        }
    }

    private func stringListBinding(
        id: String,
        keyPath: WritableKeyPath<DataTransformPayload, [String]?>
    ) -> Binding<String> {
        Binding {
            dataTransform(id)[keyPath: keyPath]?.joined(separator: ", ") ?? ""
        } set: { newValue in
            let items = newValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            session.updateDataTransform(id: id) { transform in
                transform[keyPath: keyPath] = items.isEmpty ? nil : items
            }
        }
    }

    private func variableEnabledBinding(id: String) -> Binding<Bool> {
        Binding {
            dataVariable(id).enabled
        } set: { newValue in
            session.updateDataVariable(id: id, policy: .immediate) { $0.enabled = newValue }
        }
    }

    private func variableTextBinding(id: String, keyPath: WritableKeyPath<DataVariablePayload, String>) -> Binding<String> {
        Binding {
            dataVariable(id)[keyPath: keyPath]
        } set: { newValue in
            session.updateDataVariable(id: id) { variable in
                variable[keyPath: keyPath] = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func variableTextBinding(id: String, keyPath: WritableKeyPath<DataVariablePayload, String?>) -> Binding<String> {
        Binding {
            dataVariable(id)[keyPath: keyPath] ?? ""
        } set: { newValue in
            session.updateDataVariable(id: id) { variable in
                variable[keyPath: keyPath] = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newValue
            }
        }
    }

    private func variableNumberBinding(id: String) -> Binding<String> {
        Binding {
            dataVariable(id).value?.formatted(.number.precision(.fractionLength(4))) ?? ""
        } set: { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            session.updateDataVariable(id: id) { variable in
                variable.value = trimmed.isEmpty ? nil : Double(trimmed)
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
