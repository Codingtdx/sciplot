import SwiftUI

extension PlotInspectorView {
    @ViewBuilder
    var plotOptionsSection: some View {
        if let template = session.selectedTemplateSummary {
            InspectorSection(title: styleSectionTitle) {
                if session.editableOptionIDs.contains("size") && session.allowedSizes.count > 1 {
                    AdaptiveInspectorControlRow(title: "Canvas") {
                        Picker("", selection: sizeBinding(defaultSize: template.defaultSize)) {
                            ForEach(session.allowedSizes) { size in
                                Text(size.label).tag(size.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                } else {
                    AdaptiveInspectorTextRow(
                        title: "Canvas",
                        value: sizeLabel(for: template.defaultSize)
                    )
                }

                if !session.availableStyles.isEmpty {
                    if session.availableStyles.count > 1 {
                        AdaptiveInspectorControlRow(title: "Theme") {
                            Picker("", selection: stringBinding(
                                get: { session.renderOptions.stylePreset },
                                set: { newValue in
                                    session.selectStylePreset(newValue)
                                }
                            )) {
                                ForEach(session.availableStyles) { style in
                                    Text(style.label).tag(style.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    } else if let style = session.availableStyles.first {
                        AdaptiveInspectorTextRow(title: "Theme", value: style.label)
                    }
                }

                if !session.availablePalettes.isEmpty {
                    if session.availablePalettes.count > 1 {
                        AdaptiveInspectorControlRow(title: "Palette") {
                            Picker("", selection: stringBinding(
                                get: { session.renderOptions.palettePreset },
                                set: { newValue in
                                    session.updateRenderOptions(policy: .immediate) { $0.palettePreset = newValue }
                                }
                            )) {
                                ForEach(session.availablePalettes) { palette in
                                    Text(palette.label).tag(palette.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    } else if let palette = session.availablePalettes.first {
                        AdaptiveInspectorTextRow(title: "Palette", value: palette.label)
                    }
                }

                if let themes = session.metadata?.visualThemes, !themes.isEmpty {
                    if themes.count > 1 {
                        AdaptiveInspectorControlRow(title: "Background") {
                            Picker("", selection: stringBinding(
                                get: { session.renderOptions.visualThemeID ?? session.defaultThemeID(for: template, styleID: session.renderOptions.stylePreset) ?? themes.first?.id ?? "" },
                                set: { newValue in
                                    session.updateRenderOptions(policy: .immediate) { $0.visualThemeID = newValue.isEmpty ? nil : newValue }
                                }
                            )) {
                                ForEach(themes) { theme in
                                    Text(theme.label).tag(theme.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    } else if let theme = themes.first {
                        AdaptiveInspectorTextRow(title: "Background", value: theme.label)
                    }
                }

                if showsPlotOptionsAdvancedControls {
                    DisclosureGroup("Advanced", isExpanded: $isPlotOptionsAdvancedExpanded) {
                        if session.editableOptionIDs.contains("show_colorbar") {
                            AdaptiveInspectorControlRow(title: "Colorbar") {
                                Toggle("", isOn: boolBinding(
                                    get: { session.renderOptions.showColorbar ?? false },
                                    set: { newValue in
                                        session.updateRenderOptions(policy: .immediate) { $0.showColorbar = newValue }
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                    }
                }
            }
        }
    }

    var axesSection: some View {
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

    var fitOverlaySection: some View {
        InspectorSection(title: "Fit Overlay") {
            AdaptiveInspectorControlRow(title: "Visible") {
                Toggle("", isOn: fitEnabledBinding)
                    .labelsHidden()
                    .disabled(!session.fitOverlayAvailability.isEnabled)
                    .help(session.fitOverlayAvailability.reason ?? "Show the selected fit model on the figure.")
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
                .help(session.fitAnalysisAvailability.reason ?? "Choose the shared fit model.")
            }
        }
    }

    var seriesSection: some View {
        InspectorSection(title: "Legend") {
            if session.seriesOrderLabels.isEmpty {
                InspectorEmptyState(message: "No legend entries")
            } else {
                SortableSeriesListView(
                    title: "Legend order",
                    rows: session.seriesOrderRows,
                    moveItem: { id, offset in
                        session.moveSeriesOrder(id: id, by: offset)
                    }
                )

                Button("Reset Series Order") {
                    session.resetSeriesOrder()
                }
                .disabled(!session.resetSeriesOrderAvailability.isEnabled)
                .help(
                    session.resetSeriesOrderAvailability.reason
                        ?? "Reset legend ordering back to the source order."
                )
            }
        }
    }

    @ViewBuilder
    var axisScaleControls: some View {
        if session.editableOptionIDs.contains("xscale") {
            AdaptiveInspectorControlRow(title: "X scale") {
                Picker("", selection: stringBinding(
                    get: { session.renderOptions.xscale ?? "linear" },
                    set: { newValue in
                        session.updateRenderOptions(policy: .immediate) { $0.xscale = newValue }
                    }
                )) {
                    Text("Linear").tag("linear")
                    Text("Log").tag("log")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }

        if session.editableOptionIDs.contains("yscale") {
            AdaptiveInspectorControlRow(title: "Y scale") {
                Picker("", selection: stringBinding(
                    get: { session.renderOptions.yscale ?? "linear" },
                    set: { newValue in
                        session.updateRenderOptions(policy: .immediate) { $0.yscale = newValue }
                    }
                )) {
                    Text("Linear").tag("linear")
                    Text("Log").tag("log")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    var axisRangeControls: some View {
        if session.editableOptionIDs.contains("reverse_x") {
            AdaptiveInspectorControlRow(title: "Reverse X") {
                Toggle("", isOn: boolBinding(
                    get: { session.renderOptions.reverseX },
                    set: { newValue in
                        session.updateRenderOptions(policy: .immediate) { $0.reverseX = newValue }
                    }
                ))
                .labelsHidden()
            }
        }

        if session.editableOptionIDs.contains("x_min") || session.editableOptionIDs.contains("x_max") {
            axisRangeRow(
                title: "X range",
                lowerTitle: "Min",
                upperTitle: "Max",
                lowerBinding: numericTextBinding(
                    get: { session.renderOptions.xMin },
                    set: { newValue in
                        session.updateRenderOptions(policy: .debounced) { $0.xMin = newValue }
                    }
                ),
                upperBinding: numericTextBinding(
                    get: { session.renderOptions.xMax },
                    set: { newValue in
                        session.updateRenderOptions(policy: .debounced) { $0.xMax = newValue }
                    }
                )
            )
        }

        if session.editableOptionIDs.contains("y_min") || session.editableOptionIDs.contains("y_max") {
            axisRangeRow(
                title: "Y range",
                lowerTitle: "Min",
                upperTitle: "Max",
                lowerBinding: numericTextBinding(
                    get: { session.renderOptions.yMin },
                    set: { newValue in
                        session.updateRenderOptions(policy: .debounced) { $0.yMin = newValue }
                    }
                ),
                upperBinding: numericTextBinding(
                    get: { session.renderOptions.yMax },
                    set: { newValue in
                        session.updateRenderOptions(policy: .debounced) { $0.yMax = newValue }
                    }
                )
            )
        }

        if session.editableOptionIDs.contains("baseline") {
            AdaptiveInspectorControlRow(title: "Baseline") {
                TextField(
                    "Baseline",
                    text: stringBinding(
                        get: { session.renderOptions.baseline ?? "" },
                        set: { newValue in
                            session.updateRenderOptions(policy: .debounced) { $0.baseline = newValue.isEmpty ? nil : newValue }
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    func sizeLabel(for sizeID: String) -> String {
        session.allowedSizes.first(where: { $0.id == sizeID })?.label ?? sizeID
    }

    var showsTickLabelControls: Bool {
        supportsTickLabelControls(for: .x) || supportsTickLabelControls(for: .y)
    }

    var showsExtraAxesControls: Bool {
        supportsExtraXAxisControls || supportsExtraYAxisControls
    }

    var showsAxisBreakControls: Bool {
        supportsXAxisBreakControls || supportsYAxisBreakControls
    }

    var supportsExtraXAxisControls: Bool {
        session.editableOptionIDs.contains("extra_x_axis")
    }

    var supportsExtraYAxisControls: Bool {
        session.editableOptionIDs.contains("extra_y_axis")
    }

    var supportsXAxisBreakControls: Bool {
        session.editableOptionIDs.contains("x_axis_breaks")
    }

    var supportsYAxisBreakControls: Bool {
        session.editableOptionIDs.contains("y_axis_breaks")
    }

    func supportsTickLabelControls(for axis: PlotAxisSelection) -> Bool {
        supportsTickDensity(for: axis) || supportsTickEdgeLabels(for: axis)
    }

    func supportsTickDensity(for axis: PlotAxisSelection) -> Bool {
        session.editableOptionIDs.contains(axis == .x ? "x_tick_density" : "y_tick_density")
    }

    func supportsTickEdgeLabels(for axis: PlotAxisSelection) -> Bool {
        session.editableOptionIDs.contains(axis == .x ? "x_tick_edge_labels" : "y_tick_edge_labels")
    }

    func isLogScale(_ axis: PlotAxisSelection) -> Bool {
        switch axis {
        case .x:
            return (session.renderOptions.xscale ?? "linear") == "log"
        case .y:
            return (session.renderOptions.yscale ?? "linear") == "log"
        }
    }

    func tickDensityBinding(for axis: PlotAxisSelection) -> Binding<String> {
        stringBinding(
            get: {
                switch axis {
                case .x:
                    return session.renderOptions.xTickDensity ?? "auto"
                case .y:
                    return session.renderOptions.yTickDensity ?? "auto"
                }
            },
            set: { newValue in
                session.updateRenderOptions(policy: .immediate) {
                    let resolved = newValue == "auto" ? nil : newValue
                    switch axis {
                    case .x:
                        $0.xTickDensity = resolved
                    case .y:
                        $0.yTickDensity = resolved
                    }
                }
            }
        )
    }

    func tickEdgeLabelsBinding(for axis: PlotAxisSelection) -> Binding<String> {
        stringBinding(
            get: {
                switch axis {
                case .x:
                    return session.renderOptions.xTickEdgeLabels ?? "auto"
                case .y:
                    return session.renderOptions.yTickEdgeLabels ?? "auto"
                }
            },
            set: { newValue in
                session.updateRenderOptions(policy: .immediate) {
                    let resolved = newValue == "auto" ? nil : newValue
                    switch axis {
                    case .x:
                        $0.xTickEdgeLabels = resolved
                    case .y:
                        $0.yTickEdgeLabels = resolved
                    }
                }
            }
        )
    }

    var shouldShowAxesSection: Bool {
        shouldShowPrimaryAxesControls || showsExtraAxesControls || showsAxisBreakControls
    }

    var shouldShowPrimaryAxesControls: Bool {
        let axisOptionIDs: Set<String> = [
            "xscale",
            "yscale",
            "reverse_x",
            "x_min",
            "x_max",
            "y_min",
            "y_max",
            "x_tick_density",
            "x_tick_edge_labels",
            "y_tick_density",
            "y_tick_edge_labels",
            "baseline",
        ]
        return !session.editableOptionIDs.isDisjoint(with: axisOptionIDs)
    }

    var showsPlotOptionsAdvancedControls: Bool {
        session.editableOptionIDs.contains("show_colorbar")
    }
}
