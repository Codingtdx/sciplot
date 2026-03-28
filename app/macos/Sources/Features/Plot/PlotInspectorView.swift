import SwiftUI

struct PlotInspectorView: View {
    @Bindable var session: PlotSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let template = session.selectedTemplateSummary {
                    InspectorSection(title: "Template") {
                        KeyValueGrid(values: [
                            ("Label", template.label),
                            ("ID", template.id),
                            ("Category", template.category),
                        ])
                    }

                    if session.editableOptionIDs.contains("size") {
                        InspectorSection(title: "Size") {
                            Picker("Canvas size", selection: $session.renderOptions.size.replacingNil(with: template.defaultSize)) {
                                ForEach(session.allowedSizes) { size in
                                    Text(size.label).tag(Optional(size.id))
                                }
                            }
                        }
                    }

                    InspectorSection(title: "Scales") {
                        if session.editableOptionIDs.contains("xscale") {
                            Picker("X scale", selection: $session.renderOptions.xscale.replacingNil(with: "linear")) {
                                Text("Linear").tag(Optional("linear"))
                                Text("Log").tag(Optional("log"))
                            }
                        }

                        if session.editableOptionIDs.contains("yscale") {
                            Picker("Y scale", selection: $session.renderOptions.yscale.replacingNil(with: "linear")) {
                                Text("Linear").tag(Optional("linear"))
                                Text("Log").tag(Optional("log"))
                            }
                        }

                        if session.editableOptionIDs.contains("reverse_x") {
                            Toggle("Reverse X", isOn: $session.renderOptions.reverseX)
                        }

                        if session.editableOptionIDs.contains("baseline") {
                            TextField(
                                "Baseline",
                                text: Binding(
                                    get: { session.renderOptions.baseline ?? "" },
                                    set: { session.renderOptions.baseline = $0.isEmpty ? nil : $0 }
                                )
                            )
                        }

                        if session.editableOptionIDs.contains("show_colorbar") {
                            Toggle(
                                "Show colorbar",
                                isOn: Binding(
                                    get: { session.renderOptions.showColorbar ?? false },
                                    set: { session.renderOptions.showColorbar = $0 }
                                )
                            )
                        }
                    }

                    InspectorSection(title: "Styling") {
                        Picker("Style", selection: $session.renderOptions.stylePreset) {
                            ForEach(session.availableStyles) { style in
                                Text(style.label).tag(style.id)
                            }
                        }

                        Picker("Palette", selection: $session.renderOptions.palettePreset) {
                            ForEach(session.availablePalettes) { palette in
                                Text(palette.label).tag(palette.id)
                            }
                        }

                        if let themes = session.metadata?.visualThemes, !themes.isEmpty {
                            Picker(
                                "Visual theme",
                                selection: Binding(
                                    get: { session.renderOptions.visualThemeID ?? themes.first?.id ?? "" },
                                    set: { session.renderOptions.visualThemeID = $0.isEmpty ? nil : $0 }
                                )
                            ) {
                                ForEach(themes) { theme in
                                    Text(theme.label).tag(theme.id)
                                }
                            }
                        }
                    }
                } else {
                    EmptyStateCard(
                        title: "No active template",
                        message: "Inspect a file and choose a compatible template to edit Plot options."
                    )
                }
            }
            .padding(16)
        }
    }
}

private extension Binding where Value == String? {
    func replacingNil(with defaultValue: String) -> Binding<String?> {
        Binding<String?>(
            get: { wrappedValue ?? defaultValue },
            set: { wrappedValue = $0 }
        )
    }
}
