import SwiftUI

struct DataStudioInspectorView: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        if session.showsCompactEmptyInspector {
            compactEmptyInspector
        } else {
            PlotInspectorView(session: session.plotSession, styleSectionTitle: "Style") {
                figureSection
            } trailingSections: {
                if session.showsInspectorActions {
                    actionsSection
                }
            }
        }
    }

    private var compactEmptyInspector: some View {
        Form {
            Section("Actions") {
                InspectorEmptyState(message: "Use Import to add workbook groups.")
            }
        }
        .formStyle(.grouped)
        .inspectorSurface()
    }

    private var figureSection: some View {
        Section("Figure") {
            if session.figureFamilies.isEmpty {
                InspectorEmptyState(message: "Import a workbook group to activate figure controls.")
            } else {
                if !session.availableFigureTemplates.isEmpty {
                    AdaptiveInspectorControlRow(title: "Template") {
                        Picker("", selection: figureTemplateBinding) {
                            ForEach(session.availableFigureTemplates) { template in
                                Text(template.label).tag(Optional(template.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                AdaptiveInspectorTextRow(
                    title: "Metric",
                    value: session.currentFigureFamily?.title ?? "Representative Curve"
                )
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            InspectorActionStack {
                Button("Open in Plot") {
                    session.openCurrentFigureInPlot()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.canOpenCurrentFigureInPlot)
                .help(
                    session.canOpenCurrentFigureInPlot
                        ? "Open the current comparison figure in Plot."
                        : "Choose a supported figure context before opening in Plot."
                )
                .inspectorActionButton()

                Button("Export Bundle") {
                    Task { await session.exportComparisonBundle() }
                }
                .buttonStyle(.bordered)
                .disabled(!session.exportAvailability.isEnabled)
                .help(session.exportAvailability.reason ?? "Export the comparison workbook and figure outputs.")
                .inspectorActionButton()
            }

            DisclosureGroup("Advanced") {
                InspectorActionStack {
                    Button("Reveal Workbook") {
                        session.revealFocusedWorkbook()
                    }
                    .buttonStyle(.bordered)
                    .disabled(session.focusedWorkbook == nil)
                    .help(
                        session.focusedWorkbook == nil
                            ? "Select a workbook group first."
                            : "Reveal the focused workbook in Finder."
                    )
                    .inspectorActionButton()

                    Button("Reveal Output") {
                        session.revealLatestExport()
                    }
                    .buttonStyle(.bordered)
                    .disabled(session.focusedWorkbook == nil && session.comparisonExportDestinationURL == nil)
                    .help(
                        session.focusedWorkbook == nil && session.comparisonExportDestinationURL == nil
                            ? "Export or focus a workbook first."
                            : "Reveal the latest output location in Finder."
                    )
                    .inspectorActionButton()
                }
            }
        }
    }

    private var figureTemplateBinding: Binding<String?> {
        Binding(
            get: { session.currentFigureTemplateID },
            set: { newValue in
                if let newValue {
                    session.selectFigureTemplate(id: newValue)
                }
            }
        )
    }
}
