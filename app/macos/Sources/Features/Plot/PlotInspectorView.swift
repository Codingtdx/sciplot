import SwiftUI

struct PlotInspectorView<LeadingSections: View, TrailingSections: View>: View {
    @Bindable var session: PlotSession
    private let styleSectionTitle: String
    private let adjustmentCategory: PlotAdjustmentCategory?
    private let showsPlotInspectorModes: Bool
    private let leadingSections: LeadingSections
    private let trailingSections: TrailingSections
    @State private var isPlotOptionsAdvancedExpanded: Bool

    init(
        session: PlotSession,
        styleSectionTitle: String = "Figure",
        adjustmentCategory: PlotAdjustmentCategory? = nil,
        plotOptionsAdvancedExpanded: Bool = false,
        showsPlotInspectorModes: Bool = true,
        @ViewBuilder leadingSections: () -> LeadingSections = { EmptyView() },
        @ViewBuilder trailingSections: () -> TrailingSections = { EmptyView() }
    ) {
        self.session = session
        self.styleSectionTitle = styleSectionTitle
        self.adjustmentCategory = adjustmentCategory
        self.showsPlotInspectorModes = showsPlotInspectorModes
        self.leadingSections = leadingSections()
        self.trailingSections = trailingSections()
        _isPlotOptionsAdvancedExpanded = State(initialValue: plotOptionsAdvancedExpanded)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                leadingSections
                if let adjustmentCategory {
                    adjustmentCategoryContent(adjustmentCategory)
                } else if showsPlotInspectorModes {
                    PlotSelectionInspectorView(session: session) {
                        plotOptionsSection
                        if shouldShowAxesSection {
                            axesSection
                        }
                    } axisContent: {
                        if shouldShowAxesSection {
                            axesSection
                        } else {
                            InspectorSection(title: "Axis") {
                                InspectorEmptyState(message: "Select a plotted axis")
                            }
                        }
                    }
                } else {
                    plotOptionsSection
                    if session.supportsFitOverlayControls {
                        fitOverlaySection
                    }
                    if shouldShowAxesSection {
                        axesSection
                    }
                    if session.shouldShowSeriesLegendControls {
                        seriesSection
                    }
                }
                trailingSections
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .inspectorSurface()
    }

    @ViewBuilder
    private func adjustmentCategoryContent(_ category: PlotAdjustmentCategory) -> some View {
        switch category {
        case .figure:
            figureAdjustmentContent
        case .axes:
            axesAdjustmentContent
        case .legend:
            legendAdjustmentContent
        case .guides:
            guidesAdjustmentContent
        case .fit:
            fitAdjustmentContent
        case .functions:
            functionsAdjustmentContent
        case .annotations:
            annotationsAdjustmentContent
        case .advancedAxes:
            advancedAxesAdjustmentContent
        }
    }

    private var figureAdjustmentContent: some View {
        Group {
            if session.selectedTemplateSummary == nil {
                InspectorSection(title: "Figure") {
                    InspectorEmptyState(message: "Import data")
                }
            } else {
                plotOptionsSection
            }
        }
    }

    private var axesAdjustmentContent: some View {
        InspectorSection(title: "Axis") {
            if !shouldShowAxesSection {
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

    private var legendAdjustmentContent: some View {
        Group {
            if session.shouldShowSeriesLegendControls {
                seriesSection
            } else {
                InspectorSection(title: "Legend") {
                    InspectorEmptyState(message: "No reorderable legend entries")
                }
            }
        }
    }

    private var guidesAdjustmentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection(title: "Guides") {
                HStack(spacing: 8) {
                    Button("Add Line") {
                        session.addReferenceGuide(kind: "line")
                        if let id = session.selectedReferenceGuideID {
                            session.selectPlotLayer(.referenceGuide(id))
                        }
                    }
                    .disabled(!session.referenceGuideAvailability.isEnabled)
                    .help(session.referenceGuideAvailability.reason ?? "Add a reference line.")

                    Button("Add Region") {
                        session.addReferenceGuide(kind: "band")
                        if let id = session.selectedReferenceGuideID {
                            session.selectPlotLayer(.referenceGuide(id))
                        }
                    }
                    .disabled(!session.referenceGuideAvailability.isEnabled)
                    .help(session.referenceGuideAvailability.reason ?? "Add a reference region.")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                objectList(
                    emptyMessage: "No guides",
                    rows: session.referenceGuides.map {
                        PlotAdjustmentObjectRow(
                            id: $0.id,
                            title: referenceGuideTitle($0),
                            detail: $0.kind == "band" ? "Region" : "Line",
                            systemImage: $0.kind == "band" ? "rectangle.dashed" : "ruler",
                            selection: .referenceGuide($0.id)
                        )
                    }
                )
            }

            selectedGuideEditor
        }
    }

    private var fitAdjustmentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            fitOverlaySection
            InspectorSection(title: "Analysis") {
                Button {
                    session.showDataWorkbook(tab: .fit)
                } label: {
                    Label("Open Fit Table", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!session.fitAnalysisAvailability.isEnabled)
                .help(session.fitAnalysisAvailability.reason ?? "Open fit analysis results.")
            }
        }
    }

    private var functionsAdjustmentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection(title: "Functions") {
                Button("Add Function") {
                    session.addAnalyticalFunctionLayer()
                    if let layer = session.analyticalLayers.last {
                        session.selectPlotLayer(.function(layer.id))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!session.analyticalLayerAvailability.isEnabled)
                .help(session.analyticalLayerAvailability.reason ?? "Add a backend-rendered function layer.")

                objectList(
                    emptyMessage: "No function layers",
                    rows: session.analyticalLayers.map {
                        PlotAdjustmentObjectRow(
                            id: $0.id,
                            title: functionTitle($0),
                            detail: "Function",
                            systemImage: "function",
                            selection: .function($0.id)
                        )
                    }
                )
            }

            selectedFunctionEditor
        }
    }

    private var annotationsAdjustmentContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection(title: "Annotations") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Add Text") {
                            session.addTextAnnotation()
                            if let id = session.selectedTextAnnotationID {
                                session.selectPlotLayer(.textAnnotation(id))
                            }
                        }
                        .disabled(!session.textAnnotationAvailability.isEnabled)
                        .help(session.textAnnotationAvailability.reason ?? "Add text.")

                        Button("Add Callout") {
                            session.addTextAnnotation(displayStyle: "callout", connectorEnabled: true)
                            if let id = session.selectedTextAnnotationID {
                                session.selectPlotLayer(.textAnnotation(id))
                            }
                        }
                        .disabled(!session.textAnnotationAvailability.isEnabled)
                        .help(session.textAnnotationAvailability.reason ?? "Add a callout.")
                    }

                    HStack(spacing: 8) {
                        Button("Rectangle") {
                            addShape(kind: "rectangle")
                        }
                        Button("Ellipse") {
                            addShape(kind: "ellipse")
                        }
                        Button("Bracket") {
                            addShape(kind: "bracket")
                        }
                    }
                    .disabled(!session.shapeAnnotationAvailability.isEnabled)
                    .help(session.shapeAnnotationAvailability.reason ?? "Add a shape annotation.")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                objectList(emptyMessage: "No annotations", rows: annotationRows)
            }

            selectedAnnotationEditor
        }
    }

    private var advancedAxesAdjustmentContent: some View {
        InspectorSection(title: "Advanced Axes") {
            if !showsExtraAxesControls && !showsAxisBreakControls {
                InspectorEmptyState(message: "No advanced axis controls")
            } else {
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

    @ViewBuilder
    private var plotOptionsSection: some View {
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

    private var axesSection: some View {
        InspectorSection(title: "Axis") {
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

    private var fitOverlaySection: some View {
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

    private var seriesSection: some View {
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
    private var axisScaleControls: some View {
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
    private var axisRangeControls: some View {
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

    private func objectList(emptyMessage: String, rows: [PlotAdjustmentObjectRow]) -> some View {
        Group {
            if rows.isEmpty {
                InspectorEmptyState(message: emptyMessage)
            } else {
                VStack(spacing: 2) {
                    ForEach(rows) { row in
                        PlotAdjustmentObjectButton(
                            row: row,
                            isSelected: session.canvasSelection == .layer(row.selection)
                        ) {
                            session.selectPlotLayer(row.selection)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var selectedGuideEditor: some View {
        if case .layer(let selection) = session.canvasSelection,
           case .referenceGuide = selection {
            PlotSelectedLayerEditorView(session: session, selection: selection)
        }
    }

    @ViewBuilder
    private var selectedFunctionEditor: some View {
        if case .layer(let selection) = session.canvasSelection,
           case .function = selection {
            PlotSelectedLayerEditorView(session: session, selection: selection)
        }
    }

    @ViewBuilder
    private var selectedAnnotationEditor: some View {
        if case .layer(let selection) = session.canvasSelection {
            switch selection {
            case .textAnnotation, .shapeAnnotation:
                PlotSelectedLayerEditorView(session: session, selection: selection)
            case .fitOverlay, .function, .referenceGuide, .series:
                EmptyView()
            }
        }
    }

    private var annotationRows: [PlotAdjustmentObjectRow] {
        let textRows = session.textAnnotations.map {
            PlotAdjustmentObjectRow(
                id: "text:\($0.id)",
                title: annotationTitle($0),
                detail: $0.connectorEnabled ? "Callout" : "Text",
                systemImage: $0.connectorEnabled ? "text.bubble" : "character.cursor.ibeam",
                selection: .textAnnotation($0.id)
            )
        }
        let shapeRows = session.shapeAnnotations.map {
            PlotAdjustmentObjectRow(
                id: "shape:\($0.id)",
                title: shapeTitle($0),
                detail: shapeKindLabel($0.kind),
                systemImage: shapeSymbol($0.kind),
                selection: .shapeAnnotation($0.id)
            )
        }
        return textRows + shapeRows
    }

    private func addShape(kind: String) {
        session.addShapeAnnotation(kind: kind)
        if let id = session.selectedShapeAnnotationID {
            session.selectPlotLayer(.shapeAnnotation(id))
        }
    }

    private func functionTitle(_ layer: AnalyticalLayerPayload) -> String {
        let label = layer.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? layer.expression : label
    }

    private func shapeTitle(_ annotation: ShapeAnnotationPayload) -> String {
        let label = annotation.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !label.isEmpty {
            return label
        }
        return shapeKindLabel(annotation.kind)
    }

    private func shapeKindLabel(_ kind: String) -> String {
        switch kind {
        case "ellipse":
            return "Ellipse"
        case "bracket":
            return "Bracket"
        default:
            return "Rectangle"
        }
    }

    private func shapeSymbol(_ kind: String) -> String {
        switch kind {
        case "ellipse":
            return "oval"
        case "bracket":
            return "square.split.diagonal"
        default:
            return "rectangle"
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

    private func isReferenceGuideSelected(_ id: String) -> Bool {
        session.selectedReferenceGuideID == id
    }

    private func isTextAnnotationSelected(_ id: String) -> Bool {
        session.selectedTextAnnotationID == id
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

extension PlotInspectorView where LeadingSections == EmptyView, TrailingSections == EmptyView {
    init(session: PlotSession, styleSectionTitle: String = "Figure") {
        self.init(
            session: session,
            styleSectionTitle: styleSectionTitle,
            leadingSections: { EmptyView() },
            trailingSections: { EmptyView() }
        )
    }

    init(
        session: PlotSession,
        styleSectionTitle: String = "Figure",
        adjustmentCategory: PlotAdjustmentCategory
    ) {
        self.init(
            session: session,
            styleSectionTitle: styleSectionTitle,
            adjustmentCategory: adjustmentCategory,
            leadingSections: { EmptyView() },
            trailingSections: { EmptyView() }
        )
    }
}

private struct PlotAdjustmentObjectRow: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let selection: PlotLayerSelection
}

private struct PlotAdjustmentObjectButton: View {
    let row: PlotAdjustmentObjectRow
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: row.systemImage)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(row.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .proGlassRow(theme: theme, isSelected: isSelected, cornerRadius: ProCornerPolicy.smallRow)
    }
}

private struct PlotSelectionInspectorView<FigureContent: View, AxisContent: View>: View {
    @Bindable var session: PlotSession
    let figureContent: FigureContent
    let axisContent: AxisContent

    init(
        session: PlotSession,
        @ViewBuilder figureContent: () -> FigureContent,
        @ViewBuilder axisContent: () -> AxisContent
    ) {
        self.session = session
        self.figureContent = figureContent()
        self.axisContent = axisContent()
    }

    var body: some View {
        switch session.canvasSelection {
        case .figure:
            figureContent
        case .axis:
            axisContent
        case .layer(let layer):
            PlotSelectedLayerEditorView(session: session, selection: layer)
        case .dataPipeline:
            InspectorSection(title: "Data") {
                AdaptiveInspectorTextRow(title: "Pipeline", value: session.dataPipelineSummary.title)
                Button {
                    session.showDataWorkbook(tab: .transformed)
                } label: {
                    Label("Open Workbook", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!session.dataTransformAvailability.isEnabled)
                .help(session.dataTransformAvailability.reason ?? "Open the data pipeline in Data Workbook.")
            }
        }
    }
}
