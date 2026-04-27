import SwiftUI

struct PlotDataPipelineInspectorView: View {
    @Bindable var session: PlotSession
    @Binding var selection: PlotDataPipelineSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pipelineHeader
            pipelineActions
            pipelineList
            selectedEditor
        }
    }

    private var pipelineHeader: some View {
        InspectorSection(title: "Pipeline") {
            AdaptiveInspectorTextRow(title: "State", value: session.dataPipelineSummary.title)
            AdaptiveInspectorTextRow(title: "Active", value: session.dataPipelineSummary.detail)
        }
    }

    private var pipelineActions: some View {
        InspectorSection(title: "Add") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    addButton("Variable") {
                        session.addDataVariable(kind: "scalar")
                        selection = session.dataVariables.last.map { .variable($0.id) }
                    }
                    addButton("Derived") {
                        session.addDataTransform(kind: "derived_column")
                        selection = session.dataTransforms.last.map { .transform($0.id) }
                    }
                    addButton("Filter") {
                        session.addDataTransform(kind: "row_filter")
                        selection = session.dataTransforms.last.map { .transform($0.id) }
                    }
                }
                HStack(spacing: 8) {
                    addButton("Bin") {
                        session.addDataTransform(kind: "bin_column")
                        selection = session.dataTransforms.last.map { .transform($0.id) }
                    }
                    addButton("Smooth") {
                        session.addDataTransform(kind: "rolling_window")
                        selection = session.dataTransforms.last.map { .transform($0.id) }
                    }
                    addButton("Aggregate") {
                        session.addDataTransform(kind: "aggregate_summary")
                        selection = session.dataTransforms.last.map { .transform($0.id) }
                    }
                }
            }
            .disabled(!session.dataTransformAvailability.isEnabled)
            .help(session.dataTransformAvailability.reason ?? "Add typed data pipeline steps.")
        }
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private var pipelineList: some View {
        InspectorSection(title: "Items") {
            if session.dataVariables.isEmpty && session.dataTransforms.isEmpty {
                InspectorEmptyState(message: "Source data")
            } else {
                VStack(spacing: 2) {
                    ForEach(session.dataVariables) { variable in
                        pipelineRow(
                            title: dataVariableTitle(variable),
                            subtitle: variable.kind == "expression" ? "Expression variable" : "Scalar variable",
                            systemImage: "number",
                            isEnabled: variableEnabledBinding(id: variable.id),
                            isSelected: selection == .variable(variable.id),
                            onSelect: { selection = .variable(variable.id) },
                            onDelete: {
                                session.removeDataVariable(id: variable.id)
                                if selection == .variable(variable.id) {
                                    selection = nil
                                }
                            }
                        )
                    }
                    ForEach(session.dataTransforms) { transform in
                        pipelineRow(
                            title: dataTransformTitle(transform),
                            subtitle: dataTransformKindLabel(transform.kind),
                            systemImage: dataTransformSymbol(transform.kind),
                            isEnabled: transformEnabledBinding(id: transform.id),
                            isSelected: selection == .transform(transform.id),
                            onSelect: { selection = .transform(transform.id) },
                            onDelete: {
                                session.removeDataTransform(id: transform.id)
                                if selection == .transform(transform.id) {
                                    selection = nil
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private func pipelineRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isEnabled: Binding<Bool>,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                }
            }
            .buttonStyle(.plain)

            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private var selectedEditor: some View {
        switch selection {
        case .variable(let id):
            if session.dataVariables.contains(where: { $0.id == id }) {
                InspectorSection(title: "Variable") {
                    dataVariableEditor(id: id)
                }
            } else {
                InspectorSection(title: "Edit") {
                    InspectorEmptyState(message: "Select an item")
                }
            }
        case .transform(let id):
            if session.dataTransforms.contains(where: { $0.id == id }) {
                InspectorSection(title: "Transform") {
                    dataTransformEditor(id: id)
                }
            } else {
                InspectorSection(title: "Edit") {
                    InspectorEmptyState(message: "Select an item")
                }
            }
        case nil:
            InspectorSection(title: "Edit") {
                InspectorEmptyState(message: "Select an item")
            }
        }
    }

    private func dataVariableEditor(id: String) -> some View {
        Group {
            AdaptiveInspectorControlRow(title: "Name") {
                TextField("baseline", text: variableTextBinding(id: id, keyPath: \.id))
                    .textFieldStyle(.roundedBorder)
            }
            AdaptiveInspectorControlRow(title: "Kind") {
                Picker("", selection: variableTextBinding(id: id, keyPath: \.kind)) {
                    Text("Scalar").tag("scalar")
                    Text("Expression").tag("expression")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            if dataVariable(id).kind == "expression" {
                AdaptiveInspectorControlRow(title: "Expression") {
                    TextField("1 + 1", text: variableTextBinding(id: id, keyPath: \.expression))
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                AdaptiveInspectorControlRow(title: "Value") {
                    TextField("1", text: variableNumberBinding(id: id))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    @ViewBuilder
    private func dataTransformEditor(id: String) -> some View {
        AdaptiveInspectorControlRow(title: "Label") {
            TextField("Optional", text: transformTextBinding(id: id, keyPath: \.label))
                .textFieldStyle(.roundedBorder)
        }

        switch dataTransform(id).kind {
        case "mask_filter":
            expressionOnlyControls(id: id, placeholder: "col('x') > 0")
        case "row_filter":
            rowFilterControls(id: id)
        case "pivot_matrix":
            pivotControls(id: id)
        case "bin_column":
            binControls(id: id)
        case "rolling_window":
            rollingControls(id: id)
        case "aggregate_summary":
            aggregateControls(id: id)
        case "sort_rows", "select_columns", "type_cast":
            columnListControls(id: id)
        default:
            derivedColumnControls(id: id)
        }
    }

    private func dataTransform(_ id: String) -> DataTransformPayload {
        session.dataTransforms.first(where: { $0.id == id }) ?? DataTransformPayload(id: id)
    }

    private func dataVariable(_ id: String) -> DataVariablePayload {
        session.dataVariables.first(where: { $0.id == id }) ?? DataVariablePayload(id: id)
    }

    private func dataVariableTitle(_ variable: DataVariablePayload) -> String {
        let label = variable.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? variable.id : label
    }

    private func dataTransformTitle(_ transform: DataTransformPayload) -> String {
        let label = transform.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? dataTransformKindLabel(transform.kind) : label
    }

    private func dataTransformKindLabel(_ kind: String) -> String {
        switch kind {
        case "mask_filter":
            return "Mask"
        case "row_filter":
            return "Filter"
        case "pivot_matrix":
            return "Pivot"
        case "bin_column":
            return "Bin"
        case "rolling_window":
            return "Smooth"
        case "aggregate_summary":
            return "Aggregate"
        case "sort_rows":
            return "Sort"
        case "select_columns":
            return "Select"
        case "type_cast":
            return "Cast"
        default:
            return "Derived"
        }
    }

    private func dataTransformSymbol(_ kind: String) -> String {
        switch kind {
        case "mask_filter", "row_filter":
            return "line.3.horizontal.decrease.circle"
        case "pivot_matrix":
            return "tablecells"
        case "bin_column":
            return "chart.bar.xaxis"
        case "rolling_window":
            return "waveform.path"
        case "aggregate_summary":
            return "sum"
        default:
            return "function"
        }
    }

    private func derivedColumnControls(id: String) -> some View {
        Group {
            AdaptiveInspectorControlRow(title: "Target") {
                TextField("Column", text: transformTextBinding(id: id, keyPath: \.targetColumn))
                    .textFieldStyle(.roundedBorder)
            }
            AdaptiveInspectorControlRow(title: "Expression") {
                TextField("x + 1", text: transformTextBinding(id: id, keyPath: \.expression))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func rowFilterControls(id: String) -> some View {
        Group {
            AdaptiveInspectorControlRow(title: "Column") {
                TextField("Column", text: transformTextBinding(id: id, keyPath: \.column))
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
            TextField(placeholder, text: transformTextBinding(id: id, keyPath: \.expression))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func pivotControls(id: String) -> some View {
        Group {
            AdaptiveInspectorControlRow(title: "X/Y/Z") {
                HStack(spacing: 8) {
                    TextField("X", text: transformTextBinding(id: id, keyPath: \.xColumn))
                        .textFieldStyle(.roundedBorder)
                    TextField("Y", text: transformTextBinding(id: id, keyPath: \.yColumn))
                        .textFieldStyle(.roundedBorder)
                    TextField("Z", text: transformTextBinding(id: id, keyPath: \.zColumn))
                        .textFieldStyle(.roundedBorder)
                }
            }
            AdaptiveInspectorControlRow(title: "Mode") {
                Picker("", selection: transformTextBinding(id: id, keyPath: \.outputMode)) {
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
                TextField("Column", text: transformTextBinding(id: id, keyPath: \.column))
                    .textFieldStyle(.roundedBorder)
            }
            AdaptiveInspectorControlRow(title: "Target/Bins") {
                HStack(spacing: 8) {
                    TextField("bin", text: transformTextBinding(id: id, keyPath: \.targetColumn))
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
                TextField("Column", text: transformTextBinding(id: id, keyPath: \.column))
                    .textFieldStyle(.roundedBorder)
            }
            AdaptiveInspectorControlRow(title: "Target/Window") {
                HStack(spacing: 8) {
                    TextField("smoothed", text: transformTextBinding(id: id, keyPath: \.targetColumn))
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

    private func transformEnabledBinding(id: String) -> Binding<Bool> {
        Binding {
            dataTransform(id).enabled
        } set: { newValue in
            session.updateDataTransform(id: id, policy: .immediate) { $0.enabled = newValue }
        }
    }

    private func variableEnabledBinding(id: String) -> Binding<Bool> {
        Binding {
            dataVariable(id).enabled
        } set: { newValue in
            session.updateDataVariable(id: id, policy: .immediate) { $0.enabled = newValue }
        }
    }

    private func operatorBinding(id: String) -> Binding<String> {
        Binding {
            dataTransform(id).filterOperator
        } set: { newValue in
            session.updateDataTransform(id: id, policy: .immediate) { $0.filterOperator = newValue }
        }
    }

    private func transformTextBinding(id: String, keyPath: WritableKeyPath<DataTransformPayload, String?>) -> Binding<String> {
        Binding {
            dataTransform(id)[keyPath: keyPath] ?? ""
        } set: { newValue in
            session.updateDataTransform(id: id) { transform in
                transform[keyPath: keyPath] = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newValue
            }
        }
    }

    private func transformTextBinding(id: String, keyPath: WritableKeyPath<DataTransformPayload, String>) -> Binding<String> {
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
