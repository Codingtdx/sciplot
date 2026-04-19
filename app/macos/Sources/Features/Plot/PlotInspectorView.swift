import SwiftUI

struct PlotInspectorView<LeadingSections: View, TrailingSections: View>: View {
    @Bindable var session: PlotSession
    private let styleSectionTitle: String
    private let leadingSections: LeadingSections
    private let trailingSections: TrailingSections

    init(
        session: PlotSession,
        styleSectionTitle: String = "Plot Options",
        @ViewBuilder leadingSections: () -> LeadingSections = { EmptyView() },
        @ViewBuilder trailingSections: () -> TrailingSections = { EmptyView() }
    ) {
        self.session = session
        self.styleSectionTitle = styleSectionTitle
        self.leadingSections = leadingSections()
        self.trailingSections = trailingSections()
    }

    var body: some View {
        Form {
            leadingSections
            plotOptionsSection
            if shouldShowAxesSection {
                axesSection
            }
            if session.shouldShowSeriesLegendControls {
                seriesSection
            }
            trailingSections
        }
        .formStyle(.grouped)
        .inspectorSurface()
    }

    private var plotOptionsSection: some View {
        Section(styleSectionTitle) {
            if let template = session.selectedTemplateSummary {
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
                        AdaptiveInspectorControlRow(title: "Style") {
                            Picker("", selection: stringBinding(
                                get: { session.renderOptions.stylePreset },
                                set: { newValue in
                                    session.updateRenderOptions(policy: .immediate) { $0.stylePreset = newValue }
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
                        AdaptiveInspectorTextRow(title: "Style", value: style.label)
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

                DisclosureGroup("Advanced") {
                    if let themes = session.metadata?.visualThemes, !themes.isEmpty {
                        if themes.count > 1 {
                            AdaptiveInspectorControlRow(title: "Theme") {
                                Picker("", selection: stringBinding(
                                    get: { session.renderOptions.visualThemeID ?? themes.first?.id ?? "" },
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
                            AdaptiveInspectorTextRow(title: "Theme", value: theme.label)
                        }
                    }

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
            } else {
                InspectorEmptyState(message: "No figure controls")
            }
        }
    }

    private var axesSection: some View {
        Section("Axis") {
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

            DisclosureGroup("Advanced") {
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

    private var seriesSection: some View {
        Section("Legend") {
            if session.seriesOrderLabels.isEmpty {
                InspectorEmptyState(message: "No legend entries")
            } else {
                DisclosureGroup("Advanced") {
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
    }

    private func sizeBinding(defaultSize: String) -> Binding<String> {
        stringBinding(
            get: { session.renderOptions.size ?? defaultSize },
            set: { newValue in
                session.updateRenderOptions(policy: .immediate) { $0.size = newValue }
            }
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

    private func axisTickLabelControls(title: String, axis: PlotAxisSelection) -> some View {
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

    private func sizeLabel(for sizeID: String) -> String {
        session.allowedSizes.first(where: { $0.id == sizeID })?.label ?? sizeID
    }

    private var showsTickLabelControls: Bool {
        supportsTickLabelControls(for: .x) || supportsTickLabelControls(for: .y)
    }

    private func supportsTickLabelControls(for axis: PlotAxisSelection) -> Bool {
        supportsTickDensity(for: axis) || supportsTickEdgeLabels(for: axis)
    }

    private func supportsTickDensity(for axis: PlotAxisSelection) -> Bool {
        session.editableOptionIDs.contains(axis == .x ? "x_tick_density" : "y_tick_density")
    }

    private func supportsTickEdgeLabels(for axis: PlotAxisSelection) -> Bool {
        session.editableOptionIDs.contains(axis == .x ? "x_tick_edge_labels" : "y_tick_edge_labels")
    }

    private func isLogScale(_ axis: PlotAxisSelection) -> Bool {
        switch axis {
        case .x:
            return (session.renderOptions.xscale ?? "linear") == "log"
        case .y:
            return (session.renderOptions.yscale ?? "linear") == "log"
        }
    }

    private func tickDensityBinding(for axis: PlotAxisSelection) -> Binding<String> {
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

    private func tickEdgeLabelsBinding(for axis: PlotAxisSelection) -> Binding<String> {
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

    private var shouldShowAxesSection: Bool {
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
}

struct PlotExportInspectorSection: View {
    @Bindable var session: PlotSession

    var body: some View {
        Section("Actions") {
            InspectorActionStack {
                Button("Export") {
                    Task { await session.exportCurrentSelection() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.exportAvailability.isEnabled)
                .help(
                    session.exportAvailability.reason
                        ?? "Export the current plot as PDF or 300 dpi TIFF."
                )
                .inspectorActionButton()
            }

            DisclosureGroup("Advanced") {
                InspectorActionStack {
                    Button("Reveal Output") {
                        session.revealLatestExport()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!session.revealOutputAvailability.isEnabled)
                    .help(
                        session.revealOutputAvailability.reason
                            ?? "Reveal the latest exported plot files in Finder."
                    )
                    .inspectorActionButton()
                }

                LatestExportList(
                    items: session.latestExportItems,
                    openButtonTitle: { "Open \($0.label)" },
                    openButtonHelp: { "Open the exported plot file \($0.label)." },
                    openAction: { session.openLatestExport(id: $0.id) }
                )
            }
        }
    }
}

private enum PlotAxisSelection {
    case x
    case y
}

extension PlotInspectorView where LeadingSections == EmptyView, TrailingSections == EmptyView {
    init(session: PlotSession, styleSectionTitle: String = "Plot Options") {
        self.init(
            session: session,
            styleSectionTitle: styleSectionTitle,
            leadingSections: { EmptyView() },
            trailingSections: { EmptyView() }
        )
    }
}
