import SwiftUI

struct PlotInspectorView<LeadingSections: View, TrailingSections: View>: View {
    @Bindable var session: PlotSession
    private let styleSectionTitle: String
    private let leadingSections: LeadingSections
    private let trailingSections: TrailingSections
    @State private var isPlotOptionsAdvancedExpanded: Bool

    init(
        session: PlotSession,
        styleSectionTitle: String = "Plot Options",
        plotOptionsAdvancedExpanded: Bool = false,
        @ViewBuilder leadingSections: () -> LeadingSections = { EmptyView() },
        @ViewBuilder trailingSections: () -> TrailingSections = { EmptyView() }
    ) {
        self.session = session
        self.styleSectionTitle = styleSectionTitle
        self.leadingSections = leadingSections()
        self.trailingSections = trailingSections()
        _isPlotOptionsAdvancedExpanded = State(initialValue: plotOptionsAdvancedExpanded)
    }

    var body: some View {
        Form {
            leadingSections
            plotOptionsSection
            if session.showsAdvancedPlotSection {
                advancedPlotSection
            }
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

                if showsExtraAxesControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Extra Axes")
                            .font(.subheadline.weight(.semibold))

                        if supportsExtraXAxisControls {
                            extraAxisControls(title: "X axis", axis: .x)
                        }

                        if supportsExtraYAxisControls {
                            extraAxisControls(title: "Y axis", axis: .y)
                        }
                    }
                    .padding(.top, 4)
                }

                if showsAxisBreakControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Broken Axes")
                            .font(.subheadline.weight(.semibold))

                        if supportsXAxisBreakControls {
                            axisBreakControls(title: "X axis", axis: .x)
                        }

                        if supportsYAxisBreakControls {
                            axisBreakControls(title: "Y axis", axis: .y)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var advancedPlotSection: some View {
        Section("Advanced Plot") {
            if session.supportsFitOverlayControls {
                AdaptiveInspectorControlRow(title: "Fit Overlay") {
                    Toggle("", isOn: fitEnabledBinding)
                        .labelsHidden()
                        .disabled(!session.fitOverlayAvailability.isEnabled)
                        .help(session.fitOverlayAvailability.reason ?? "Overlay the current figure with the selected fit model.")
                }

                AdaptiveInspectorControlRow(title: "Model") {
                    Picker("", selection: fitModelBinding) {
                        Text("Linear").tag("linear")
                        Text("Polynomial 2").tag("polynomial_2")
                        Text("Polynomial 3").tag("polynomial_3")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(!session.fitAnalysisAvailability.isEnabled)
                    .help(session.fitAnalysisAvailability.reason ?? "Choose the shared fit model for overlay and analysis.")
                }
            }

            DisclosureGroup("Reference Guides") {
                HStack(spacing: 10) {
                    Button("Add Line") {
                        session.addReferenceGuide(kind: "line")
                    }
                    .buttonStyle(.bordered)

                    Button("Add Region") {
                        session.addReferenceGuide(kind: "band")
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(!session.referenceGuideAvailability.isEnabled)
                .help(session.referenceGuideAvailability.reason ?? "Overlay reusable guide commands on the current figure.")

                ForEach(session.referenceGuides) { guide in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(referenceGuideTitle(guide))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            Spacer(minLength: 12)

                            Button("Remove") {
                                session.removeReferenceGuide(id: guide.id)
                            }
                            .buttonStyle(.bordered)
                        }

                        AdaptiveInspectorControlRow(title: "Visible") {
                            Toggle("", isOn: referenceGuideEnabledBinding(id: guide.id))
                                .labelsHidden()
                        }

                        AdaptiveInspectorControlRow(title: "Kind") {
                            Picker("", selection: referenceGuideKindBinding(id: guide.id)) {
                                Text("Line").tag("line")
                                Text("Region").tag("band")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        AdaptiveInspectorControlRow(title: "Axis") {
                            Picker("", selection: referenceGuideAxisTargetBinding(id: guide.id)) {
                                referenceGuideAxisOptions(currentValue: guide.axisTarget)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        if guide.kind == "line" {
                            AdaptiveInspectorControlRow(title: "Value") {
                                TextField("Value", text: referenceGuideValueBinding(id: guide.id))
                                    .textFieldStyle(.roundedBorder)
                            }
                        } else {
                            axisRangeRow(
                                title: "Region",
                                lowerTitle: "Start",
                                upperTitle: "End",
                                lowerBinding: referenceGuideStartBinding(id: guide.id),
                                upperBinding: referenceGuideEndBinding(id: guide.id)
                            )
                        }

                        AdaptiveInspectorControlRow(title: "Label") {
                            TextField("Optional", text: referenceGuideLabelBinding(id: guide.id))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.top, 6)
                }
            }

            DisclosureGroup("Text Annotations") {
                HStack(spacing: 10) {
                    Button("Add Note") {
                        session.addTextAnnotation()
                    }
                    .buttonStyle(.bordered)

                    Button("Add Callout") {
                        session.addTextAnnotation(displayStyle: "callout", connectorEnabled: true)
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(!session.textAnnotationAvailability.isEnabled)
                .help(session.textAnnotationAvailability.reason ?? "Overlay labels and callouts on the current figure.")

                ForEach(session.textAnnotations) { annotation in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(annotationTitle(annotation))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            Spacer(minLength: 12)

                            Button("Remove") {
                                session.removeTextAnnotation(id: annotation.id)
                            }
                            .buttonStyle(.bordered)
                        }

                        AdaptiveInspectorControlRow(title: "Visible") {
                            Toggle("", isOn: textAnnotationEnabledBinding(id: annotation.id))
                                .labelsHidden()
                        }

                        AdaptiveInspectorControlRow(title: "Text") {
                            TextField("Annotation", text: textAnnotationTextBinding(id: annotation.id))
                                .textFieldStyle(.roundedBorder)
                        }

                        AdaptiveInspectorControlRow(title: "Style") {
                            Picker("", selection: textAnnotationDisplayStyleBinding(id: annotation.id)) {
                                Text("Plain").tag("plain")
                                Text("Callout").tag("callout")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        AdaptiveInspectorControlRow(title: "Space") {
                            Picker("", selection: textAnnotationCoordinateSpaceBinding(id: annotation.id)) {
                                Text("Frame").tag("axes_fraction")
                                Text("Data").tag("data")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        if annotation.coordinateSpace == "data" {
                            AdaptiveInspectorControlRow(title: "Y Axis") {
                                Picker("", selection: textAnnotationYAxisTargetBinding(id: annotation.id)) {
                                    annotationYAxisOptions(currentValue: annotation.yAxisTarget)
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }

                        annotationPositionRow(for: annotation.id)

                        AdaptiveInspectorControlRow(title: "Align X") {
                            Picker("", selection: textAnnotationHorizontalAlignmentBinding(id: annotation.id)) {
                                Text("Left").tag("left")
                                Text("Center").tag("center")
                                Text("Right").tag("right")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        AdaptiveInspectorControlRow(title: "Align Y") {
                            Picker("", selection: textAnnotationVerticalAlignmentBinding(id: annotation.id)) {
                                Text("Top").tag("top")
                                Text("Center").tag("center")
                                Text("Bottom").tag("bottom")
                            }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                        }

                        AdaptiveInspectorControlRow(title: "Connector") {
                            Toggle("", isOn: textAnnotationConnectorEnabledBinding(id: annotation.id))
                                .labelsHidden()
                        }

                        if annotation.connectorEnabled {
                            AdaptiveInspectorControlRow(title: "Target Y") {
                                Picker("", selection: textAnnotationTargetYAxisTargetBinding(id: annotation.id)) {
                                    annotationYAxisOptions(currentValue: annotation.targetYAxisTarget)
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }

                            axisRangeRow(
                                title: "Target",
                                lowerTitle: "X",
                                upperTitle: "Y",
                                lowerBinding: textAnnotationTargetXBinding(id: annotation.id),
                                upperBinding: textAnnotationTargetYBinding(id: annotation.id)
                            )
                        }
                    }
                    .padding(.top, 6)
                }
            }

            PlotShapeAnnotationInspectorView(session: session)
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

    private var fitEnabledBinding: Binding<Bool> {
        boolBinding(
            get: { session.fitOptions.enabled },
            set: { session.updateFitEnabled($0) }
        )
    }

    private var fitModelBinding: Binding<String> {
        stringBinding(
            get: { session.fitOptions.modelID },
            set: { session.updateFitModel($0) }
        )
    }

    private func referenceGuide(_ id: String) -> ReferenceGuidePayload {
        session.referenceGuides.first(where: { $0.id == id }) ?? ReferenceGuidePayload(id: id)
    }

    private func referenceGuideTitle(_ guide: ReferenceGuidePayload) -> String {
        let label = guide.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !label.isEmpty {
            return label
        }
        return guide.kind == "band" ? "Region" : "Line"
    }

    @ViewBuilder
    private func referenceGuideAxisOptions(currentValue: String) -> some View {
        Text("X").tag("x")
        Text("Primary Y").tag("y_primary")
        if session.hasActiveSecondaryYAxis || currentValue == "y_secondary" {
            Text("Secondary Y").tag("y_secondary")
        }
    }

    private func referenceGuideEnabledBinding(id: String) -> Binding<Bool> {
        boolBinding(
            get: { referenceGuide(id).enabled },
            set: { enabled in
                session.updateReferenceGuide(id: id) { $0.enabled = enabled }
            }
        )
    }

    private func referenceGuideKindBinding(id: String) -> Binding<String> {
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

    private func referenceGuideAxisTargetBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { referenceGuide(id).axisTarget },
            set: { axisTarget in
                session.updateReferenceGuide(id: id) { $0.axisTarget = axisTarget }
            }
        )
    }

    private func referenceGuideValueBinding(id: String) -> Binding<String> {
        numericTextBinding(
            get: { referenceGuide(id).value },
            set: { value in
                session.updateReferenceGuide(id: id, policy: .debounced) { $0.value = value ?? 0.0 }
            }
        )
    }

    private func referenceGuideStartBinding(id: String) -> Binding<String> {
        numericTextBinding(
            get: { referenceGuide(id).start },
            set: { value in
                session.updateReferenceGuide(id: id, policy: .debounced) { $0.start = value ?? 0.0 }
            }
        )
    }

    private func referenceGuideEndBinding(id: String) -> Binding<String> {
        numericTextBinding(
            get: { referenceGuide(id).end },
            set: { value in
                session.updateReferenceGuide(id: id, policy: .debounced) { $0.end = value ?? 1.0 }
            }
        )
    }

    private func referenceGuideLabelBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { referenceGuide(id).label ?? "" },
            set: { label in
                session.updateReferenceGuide(id: id, policy: .debounced) { $0.label = label.isEmpty ? nil : label }
            }
        )
    }

    private func extraAxis(_ axis: PlotAxisSelection) -> ExtraAxisPayload {
        switch axis {
        case .x:
            return session.renderOptions.extraXAxis ?? ExtraAxisPayload(position: "top")
        case .y:
            return session.renderOptions.extraYAxis ?? ExtraAxisPayload(position: "right")
        }
    }

    private func updateExtraAxis(
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

    private func extraAxisControls(title: String, axis: PlotAxisSelection) -> some View {
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

    private func extraAxisAvailability(for axis: PlotAxisSelection) -> ActionAvailability {
        switch axis {
        case .x:
            return session.extraXAxisAvailability
        case .y:
            return session.extraYAxisAvailability
        }
    }

    private func extraAxisEnabledBinding(for axis: PlotAxisSelection) -> Binding<Bool> {
        boolBinding(
            get: { extraAxis(axis).enabled },
            set: { enabled in
                updateExtraAxis(axis) { $0.enabled = enabled }
            }
        )
    }

    private func extraAxisPositionBinding(for axis: PlotAxisSelection) -> Binding<String> {
        stringBinding(
            get: { extraAxis(axis).position },
            set: { value in
                updateExtraAxis(axis) { $0.position = value }
            }
        )
    }

    private func extraAxisBindingModeBinding(for axis: PlotAxisSelection) -> Binding<String> {
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

    private func extraAxisTitleBinding(for axis: PlotAxisSelection) -> Binding<String> {
        stringBinding(
            get: { extraAxis(axis).title ?? "" },
            set: { value in
                updateExtraAxis(axis, policy: .debounced) { $0.title = value.isEmpty ? nil : value }
            }
        )
    }

    private func extraAxisDisplayUnitBinding(for axis: PlotAxisSelection) -> Binding<String> {
        stringBinding(
            get: { extraAxis(axis).displayUnit ?? "" },
            set: { value in
                updateExtraAxis(axis, policy: .debounced) { $0.displayUnit = value.isEmpty ? nil : value }
            }
        )
    }

    private func extraAxisDataValueBinding(for axis: PlotAxisSelection) -> Binding<String> {
        numericValueBinding(
            get: { extraAxis(axis).dataValue },
            set: { value in
                updateExtraAxis(axis, policy: .debounced) { $0.dataValue = value }
            }
        )
    }

    private func extraAxisDisplayValueBinding(for axis: PlotAxisSelection) -> Binding<String> {
        numericValueBinding(
            get: { extraAxis(axis).displayValue },
            set: { value in
                updateExtraAxis(axis, policy: .debounced) { $0.displayValue = value }
            }
        )
    }

    private func axisBreaks(for axis: PlotAxisSelection) -> [AxisBreakPayload] {
        switch axis {
        case .x:
            return session.xAxisBreaks
        case .y:
            return session.yAxisBreaks
        }
    }

    private func axisBreakAvailability(for axis: PlotAxisSelection) -> ActionAvailability {
        switch axis {
        case .x:
            return session.xAxisBreakAvailability
        case .y:
            return session.yAxisBreakAvailability
        }
    }

    private func axisBreak(_ axis: PlotAxisSelection, id: String) -> AxisBreakPayload {
        axisBreaks(for: axis).first(where: { $0.id == id }) ?? AxisBreakPayload(id: id)
    }

    private func axisBreakControls(title: String, axis: PlotAxisSelection) -> some View {
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
                .help("Compressed keeps one axis with a gap marker. Split separates visible ranges into joined panels.")
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

    private func axisBreakEnabledBinding(axis: PlotAxisSelection, id: String) -> Binding<Bool> {
        boolBinding(
            get: { axisBreak(axis, id: id).enabled },
            set: { enabled in
                session.updateAxisBreak(axis: axis, id: id) { $0.enabled = enabled }
            }
        )
    }

    private func axisBreakDisplayMode(for axis: PlotAxisSelection) -> String {
        switch axis {
        case .x:
            return session.xAxisBreakDisplayMode
        case .y:
            return session.yAxisBreakDisplayMode
        }
    }

    private func axisBreakDisplayModeBinding(axis: PlotAxisSelection) -> Binding<String> {
        stringBinding(
            get: { axisBreakDisplayMode(for: axis) },
            set: { mode in
                session.updateAxisBreakDisplayMode(axis: axis, mode: mode)
            }
        )
    }

    private func axisBreakStartBinding(axis: PlotAxisSelection, id: String) -> Binding<String> {
        numericTextBinding(
            get: { axisBreak(axis, id: id).start },
            set: { value in
                session.updateAxisBreak(axis: axis, id: id, policy: .debounced) { $0.start = value ?? 0.0 }
            }
        )
    }

    private func axisBreakEndBinding(axis: PlotAxisSelection, id: String) -> Binding<String> {
        numericTextBinding(
            get: { axisBreak(axis, id: id).end },
            set: { value in
                session.updateAxisBreak(axis: axis, id: id, policy: .debounced) { $0.end = value ?? 1.0 }
            }
        )
    }

    private func extraYAxisSeriesSelectedBinding(seriesID: String) -> Binding<Bool> {
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

    private func annotationTitle(_ annotation: TextAnnotationPayload) -> String {
        let trimmed = annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Annotation" : trimmed
    }

    private func textAnnotation(_ id: String) -> TextAnnotationPayload {
        session.textAnnotations.first(where: { $0.id == id }) ?? TextAnnotationPayload(id: id)
    }

    private func textAnnotationEnabledBinding(id: String) -> Binding<Bool> {
        boolBinding(
            get: { textAnnotation(id).enabled },
            set: { enabled in
                session.updateTextAnnotation(id: id) { $0.enabled = enabled }
            }
        )
    }

    private func textAnnotationTextBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).text },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.text = value }
            }
        )
    }

    private func textAnnotationCoordinateSpaceBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).coordinateSpace },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.coordinateSpace = value }
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

    private func textAnnotationDisplayStyleBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).displayStyle },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.displayStyle = value }
            }
        )
    }

    private func textAnnotationYAxisTargetBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).yAxisTarget },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.yAxisTarget = value }
            }
        )
    }

    private func textAnnotationHorizontalAlignmentBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).horizontalAlignment },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.horizontalAlignment = value }
            }
        )
    }

    private func textAnnotationVerticalAlignmentBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).verticalAlignment },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.verticalAlignment = value }
            }
        )
    }

    private func textAnnotationConnectorEnabledBinding(id: String) -> Binding<Bool> {
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

    private func textAnnotationXBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { textAnnotation(id).x },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.x = value }
            }
        )
    }

    private func textAnnotationTargetXBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { textAnnotation(id).targetX },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.targetX = value }
            }
        )
    }

    private func textAnnotationTargetYBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { textAnnotation(id).targetY },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.targetY = value }
            }
        )
    }

    private func textAnnotationTargetYAxisTargetBinding(id: String) -> Binding<String> {
        stringBinding(
            get: { textAnnotation(id).targetYAxisTarget },
            set: { value in
                session.updateTextAnnotation(id: id) { $0.targetYAxisTarget = value }
            }
        )
    }

    private func textAnnotationYBinding(id: String) -> Binding<String> {
        numericValueBinding(
            get: { textAnnotation(id).y },
            set: { value in
                session.updateTextAnnotation(id: id, policy: .debounced) { $0.y = value }
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

    private func annotationPositionRow(for annotationID: String) -> some View {
        axisRangeRow(
            title: "Position",
            lowerTitle: "X",
            upperTitle: "Y",
            lowerBinding: textAnnotationXBinding(id: annotationID),
            upperBinding: textAnnotationYBinding(id: annotationID)
        )
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

    private var showsExtraAxesControls: Bool {
        supportsExtraXAxisControls || supportsExtraYAxisControls
    }

    private var showsAxisBreakControls: Bool {
        supportsXAxisBreakControls || supportsYAxisBreakControls
    }

    private var supportsExtraXAxisControls: Bool {
        session.editableOptionIDs.contains("extra_x_axis")
    }

    private var supportsExtraYAxisControls: Bool {
        session.editableOptionIDs.contains("extra_y_axis")
    }

    private var supportsXAxisBreakControls: Bool {
        session.editableOptionIDs.contains("x_axis_breaks")
    }

    private var supportsYAxisBreakControls: Bool {
        session.editableOptionIDs.contains("y_axis_breaks")
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
            "extra_x_axis",
            "extra_y_axis",
            "x_axis_breaks",
            "y_axis_breaks",
        ]
        return !session.editableOptionIDs.isDisjoint(with: axisOptionIDs)
    }

    private var showsPlotOptionsAdvancedControls: Bool {
        session.editableOptionIDs.contains("show_colorbar")
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

enum PlotAxisSelection {
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
