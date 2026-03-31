import SwiftUI

struct PlotInspectorView: View {
    @Bindable var session: PlotSession

    var body: some View {
        Form {
            plotOptionsSection
            if shouldShowAxesSection {
                axesSection
            }

            if session.shouldShowSeriesLegendControls {
                seriesSection
            }
        }
        .formStyle(.grouped)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var plotOptionsSection: some View {
        Section("Plot Options") {
            if let template = session.selectedTemplateSummary {
                if session.editableOptionIDs.contains("size") && session.allowedSizes.count > 1 {
                    LabeledContent("Canvas") {
                        Picker("", selection: sizeBinding(defaultSize: template.defaultSize)) {
                            ForEach(session.allowedSizes) { size in
                                Text(size.label).tag(size.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                } else {
                    LabeledContent("Canvas", value: sizeLabel(for: template.defaultSize))
                }

                if !session.availableStyles.isEmpty {
                    if session.availableStyles.count > 1 {
                        LabeledContent("Style") {
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
                        LabeledContent("Style", value: style.label)
                    }
                }

                if !session.availablePalettes.isEmpty {
                    if session.availablePalettes.count > 1 {
                        LabeledContent("Palette") {
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
                        LabeledContent("Palette", value: palette.label)
                    }
                }

                if let themes = session.metadata?.visualThemes, !themes.isEmpty {
                    if themes.count > 1 {
                        LabeledContent("Theme") {
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
                        LabeledContent("Theme", value: theme.label)
                    }
                }

                if session.editableOptionIDs.contains("show_colorbar") {
                    LabeledContent("Colorbar") {
                        Toggle("", isOn: boolBinding(
                            get: { session.renderOptions.showColorbar ?? false },
                            set: { newValue in
                                session.updateRenderOptions(policy: .immediate) { $0.showColorbar = newValue }
                            }
                        ))
                        .labelsHidden()
                    }
                }
            } else {
                Text("Choose a compatible template to edit plot options.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var axesSection: some View {
        Section("Axes") {
            if session.editableOptionIDs.contains("xscale") {
                LabeledContent("X scale") {
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
                LabeledContent("Y scale") {
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

            if session.editableOptionIDs.contains("reverse_x") {
                LabeledContent("Reverse X") {
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
                LabeledContent("Baseline") {
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
    }

    private var seriesSection: some View {
        Section("Series / Legend") {
            if session.seriesOrderLabels.isEmpty {
                Text("No series labels are available for the current selection.")
                    .foregroundStyle(.secondary)
            } else {
                SortableSeriesListView(
                    title: "Legend order",
                    detail: "Drag or tap to reorder legend entries. Session-only.",
                    items: Binding(
                        get: { session.seriesOrderLabels },
                        set: { session.setSeriesOrder($0) }
                    ),
                    canEdit: session.canEditSeriesOrder
                )

                Button("Reset Series Order") {
                    session.resetSeriesOrder()
                }
                .disabled(!session.canEditSeriesOrder || session.renderOptions.seriesOrder == nil)
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

    private func sizeLabel(for sizeID: String) -> String {
        session.allowedSizes.first(where: { $0.id == sizeID })?.label ?? sizeID
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
            "baseline",
        ]
        return !session.editableOptionIDs.isDisjoint(with: axisOptionIDs)
    }
}
