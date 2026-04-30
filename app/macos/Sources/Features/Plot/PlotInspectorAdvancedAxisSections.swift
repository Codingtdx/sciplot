import SwiftUI

extension PlotInspectorView {
    func referenceGuide(_ id: String) -> ReferenceGuidePayload {
        session.referenceGuides.first(where: { $0.id == id }) ?? ReferenceGuidePayload(id: id)
    }

    func isReferenceGuideSelected(_ id: String) -> Bool {
        session.selectedReferenceGuideID == id
    }

    func isTextAnnotationSelected(_ id: String) -> Bool {
        session.selectedTextAnnotationID == id
    }

    func referenceGuideTitle(_ guide: ReferenceGuidePayload) -> String {
        let label = guide.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !label.isEmpty {
            return label
        }
        return guide.kind == "band" ? "Region" : "Line"
    }

    @ViewBuilder
    func referenceGuideAxisOptions(currentValue: String) -> some View {
        Text("X").tag("x")
        Text("Primary Y").tag("y_primary")
        if session.hasActiveSecondaryYAxis || currentValue == "y_secondary" {
            Text("Secondary Y").tag("y_secondary")
        }
    }

    func referenceGuideEnabledBinding(id: String) -> Binding<Bool> {
        boolBinding(
            get: { referenceGuide(id).enabled },
            set: { enabled in
                session.updateReferenceGuide(id: id) { $0.enabled = enabled }
            }
        )
    }

    func referenceGuideKindBinding(id: String) -> Binding<String> {
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

    func referenceGuideAxisTargetBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { referenceGuide(id).axisTarget },
            set: { axisTarget in
                session.updateReferenceGuide(id: id) { $0.axisTarget = axisTarget }
            }
        )
    }

    func referenceGuideValueBinding(id: String) -> Binding<String> {
        numericTextBinding(
            get: { referenceGuide(id).value },
            set: { value in
                session.updateReferenceGuide(id: id, policy: .debounced) { $0.value = value ?? 0.0 }
            }
        )
    }

    func referenceGuideStartBinding(id: String) -> Binding<String> {
        numericTextBinding(
            get: { referenceGuide(id).start },
            set: { value in
                session.updateReferenceGuide(id: id, policy: .debounced) { $0.start = value ?? 0.0 }
            }
        )
    }

    func referenceGuideEndBinding(id: String) -> Binding<String> {
        numericTextBinding(
            get: { referenceGuide(id).end },
            set: { value in
                session.updateReferenceGuide(id: id, policy: .debounced) { $0.end = value ?? 1.0 }
            }
        )
    }

    func referenceGuideLabelBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { referenceGuide(id).label ?? "" },
            set: { label in
                session.updateReferenceGuide(id: id, policy: .debounced) { $0.label = label.isEmpty ? nil : label }
            }
        )
    }

    func extraAxis(_ axis: PlotAxisSelection) -> ExtraAxisPayload {
        switch axis {
        case .x:
            return session.renderOptions.extraXAxis ?? ExtraAxisPayload(position: "top")
        case .y:
            return session.renderOptions.extraYAxis ?? ExtraAxisPayload(position: "right")
        }
    }

    func updateExtraAxis(
        _ axis: PlotAxisSelection,
        policy: PlotPreviewRefreshPolicy = .immediate,
        mutate: @escaping (inout ExtraAxisPayload) -> Void
    ) {
        switch axis {
        case .x:
            session.updateExtraXAxis(policy: policy, mutate: mutate)
        case .y:
            session.updateExtraYAxis(policy: policy, mutate: mutate)
        }
    }

    func extraAxisControls(title: String, axis: PlotAxisSelection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            AdaptiveInspectorControlRow(title: "Visible") {
                Toggle("", isOn: extraAxisEnabledBinding(for: axis))
                    .labelsHidden()
                    .disabled(!extraAxisAvailability(for: axis).isEnabled)
                    .help(extraAxisAvailability(for: axis).reason ?? "Add a converted secondary axis to the current figure.")
            }

            if extraAxis(axis).enabled {
                if axis == .y {
                    AdaptiveInspectorControlRow(title: "Mode") {
                        Picker("", selection: extraAxisBindingModeBinding(for: axis)) {
                            Text("Conversion").tag("conversion")
                            Text("Double Y").tag("series_assignment")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .help(
                            session.extraYAxisSeriesBindingAvailability.reason
                                ?? "Route selected series to an independent secondary Y axis."
                        )
                    }
                }

                AdaptiveInspectorControlRow(title: "Position") {
                    Picker("", selection: extraAxisPositionBinding(for: axis)) {
                        switch axis {
                        case .x:
                            Text("Top").tag("top")
                            Text("Bottom").tag("bottom")
                        case .y:
                            Text("Right").tag("right")
                            Text("Left").tag("left")
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                AdaptiveInspectorControlRow(title: "Title") {
                    TextField("Optional", text: extraAxisTitleBinding(for: axis))
                        .textFieldStyle(.roundedBorder)
                }

                AdaptiveInspectorControlRow(title: "Unit") {
                    TextField("Optional", text: extraAxisDisplayUnitBinding(for: axis))
                        .textFieldStyle(.roundedBorder)
                }

                if axis == .y && extraAxis(axis).bindingMode == "series_assignment" {
                    AdaptiveInspectorControlRow(title: "Series") {
                        VStack(alignment: .leading, spacing: 6) {
                            if session.seriesAssignmentCandidateIDs.isEmpty {
                                Text("No series")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(session.seriesAssignmentCandidateIDs, id: \.self) { seriesID in
                                    Toggle(seriesID, isOn: extraYAxisSeriesSelectedBinding(seriesID: seriesID))
                                        .toggleStyle(.checkbox)
                                }
                                if !extraAxis(axis).seriesIDs.isEmpty {
                                    Button("Clear") {
                                        updateExtraAxis(.y) { $0.seriesIDs = [] }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                } else {
                    axisRangeRow(
                        title: "Conversion",
                        lowerTitle: "Data",
                        upperTitle: "Display",
                        lowerBinding: extraAxisDataValueBinding(for: axis),
                        upperBinding: extraAxisDisplayValueBinding(for: axis)
                    )
                }
            }
        }
    }

    func extraAxisAvailability(for axis: PlotAxisSelection) -> ActionAvailability {
        switch axis {
        case .x:
            return session.extraXAxisAvailability
        case .y:
            return session.extraYAxisAvailability
        }
    }

    func extraAxisEnabledBinding(for axis: PlotAxisSelection) -> Binding<Bool> {
        boolBinding(
            get: { extraAxis(axis).enabled },
            set: { enabled in
                updateExtraAxis(axis) { $0.enabled = enabled }
            }
        )
    }

    func extraAxisPositionBinding(for axis: PlotAxisSelection) -> Binding<String> {
        stringBinding(
            get: { extraAxis(axis).position },
            set: { value in
                updateExtraAxis(axis) { $0.position = value }
            }
        )
    }

    func extraAxisBindingModeBinding(for axis: PlotAxisSelection) -> Binding<String> {
        stringBinding(
            get: { extraAxis(axis).bindingMode },
            set: { value in
                guard axis == .y else {
                    return
                }
                if value == "series_assignment" && !session.extraYAxisSeriesBindingAvailability.isEnabled {
                    return
                }
                updateExtraAxis(axis) { $0.bindingMode = value }
            }
        )
    }

    func extraAxisTitleBinding(for axis: PlotAxisSelection) -> Binding<String> {
        stringBinding(
            get: { extraAxis(axis).title ?? "" },
            set: { value in
                updateExtraAxis(axis, policy: .debounced) { $0.title = value.isEmpty ? nil : value }
            }
        )
    }

    func extraAxisDisplayUnitBinding(for axis: PlotAxisSelection) -> Binding<String> {
        stringBinding(
            get: { extraAxis(axis).displayUnit ?? "" },
            set: { value in
                updateExtraAxis(axis, policy: .debounced) { $0.displayUnit = value.isEmpty ? nil : value }
            }
        )
    }

    func extraAxisDataValueBinding(for axis: PlotAxisSelection) -> Binding<String> {
        numericValueBinding(
            get: { extraAxis(axis).dataValue },
            set: { value in
                updateExtraAxis(axis, policy: .debounced) { $0.dataValue = value }
            }
        )
    }

    func extraAxisDisplayValueBinding(for axis: PlotAxisSelection) -> Binding<String> {
        numericValueBinding(
            get: { extraAxis(axis).displayValue },
            set: { value in
                updateExtraAxis(axis, policy: .debounced) { $0.displayValue = value }
            }
        )
    }

    func axisBreaks(for axis: PlotAxisSelection) -> [AxisBreakPayload] {
        switch axis {
        case .x:
            return session.xAxisBreaks
        case .y:
            return session.yAxisBreaks
        }
    }

    func axisBreakAvailability(for axis: PlotAxisSelection) -> ActionAvailability {
        switch axis {
        case .x:
            return session.xAxisBreakAvailability
        case .y:
            return session.yAxisBreakAvailability
        }
    }

    func axisBreak(_ axis: PlotAxisSelection, id: String) -> AxisBreakPayload {
        axisBreaks(for: axis).first(where: { $0.id == id }) ?? AxisBreakPayload(id: id)
    }

    func axisBreakControls(title: String, axis: PlotAxisSelection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Add Break") {
                    session.addAxisBreak(axis: axis)
                }
                .buttonStyle(.bordered)
                .disabled(!axisBreakAvailability(for: axis).isEnabled)
                .help(axisBreakAvailability(for: axis).reason ?? "Compress or split a removed interval on the current axis.")
            }

            AdaptiveInspectorControlRow(title: "Mode") {
                Picker("", selection: axisBreakDisplayModeBinding(axis: axis)) {
                    Text("Compressed").tag("compress")
                    Text("Split").tag("split")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(axisBreaks(for: axis).isEmpty || !axisBreakAvailability(for: axis).isEnabled)
                .help("Compressed keeps one axis with gap markers. Split uses joined panels.")
            }

            ForEach(axisBreaks(for: axis)) { axisBreak in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("Break")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Button("Remove") {
                            session.removeAxisBreak(axis: axis, id: axisBreak.id)
                        }
                        .buttonStyle(.bordered)
                    }

                    AdaptiveInspectorControlRow(title: "Visible") {
                        Toggle("", isOn: axisBreakEnabledBinding(axis: axis, id: axisBreak.id))
                            .labelsHidden()
                    }

                    axisRangeRow(
                        title: "Range",
                        lowerTitle: "Start",
                        upperTitle: "End",
                        lowerBinding: axisBreakStartBinding(axis: axis, id: axisBreak.id),
                        upperBinding: axisBreakEndBinding(axis: axis, id: axisBreak.id)
                    )
                }
                .padding(.top, 6)
            }
        }
    }

    func axisBreakEnabledBinding(axis: PlotAxisSelection, id: String) -> Binding<Bool> {
        boolBinding(
            get: { axisBreak(axis, id: id).enabled },
            set: { enabled in
                session.updateAxisBreak(axis: axis, id: id) { $0.enabled = enabled }
            }
        )
    }

    func axisBreakDisplayMode(for axis: PlotAxisSelection) -> String {
        switch axis {
        case .x:
            return session.xAxisBreakDisplayMode
        case .y:
            return session.yAxisBreakDisplayMode
        }
    }

    func axisBreakDisplayModeBinding(axis: PlotAxisSelection) -> Binding<String> {
        stringBinding(
            get: { axisBreakDisplayMode(for: axis) },
            set: { mode in
                session.updateAxisBreakDisplayMode(axis: axis, mode: mode)
            }
        )
    }

    func axisBreakStartBinding(axis: PlotAxisSelection, id: String) -> Binding<String> {
        numericTextBinding(
            get: { axisBreak(axis, id: id).start },
            set: { value in
                session.updateAxisBreak(axis: axis, id: id, policy: .debounced) { $0.start = value ?? 0.0 }
            }
        )
    }

    func axisBreakEndBinding(axis: PlotAxisSelection, id: String) -> Binding<String> {
        numericTextBinding(
            get: { axisBreak(axis, id: id).end },
            set: { value in
                session.updateAxisBreak(axis: axis, id: id, policy: .debounced) { $0.end = value ?? 1.0 }
            }
        )
    }

    func extraYAxisSeriesSelectedBinding(seriesID: String) -> Binding<Bool> {
        boolBinding(
            get: { extraAxis(.y).seriesIDs.contains(seriesID) },
            set: { isSelected in
                updateExtraAxis(.y) { axis in
                    var seriesIDs = axis.seriesIDs
                    if isSelected {
                        if !seriesIDs.contains(seriesID) {
                            seriesIDs.append(seriesID)
                        }
                    } else {
                        seriesIDs.removeAll { $0 == seriesID }
                    }
                    axis.seriesIDs = seriesIDs
                    axis.bindingMode = "series_assignment"
                }
            }
        )
    }
}
