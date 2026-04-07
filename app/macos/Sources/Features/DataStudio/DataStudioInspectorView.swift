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
                AdaptiveInspectorControlRow(title: "Type") {
                    Picker("", selection: figureFamilyBinding) {
                        ForEach(session.figureFamilies) { family in
                            Text(family.title).tag(Optional(family.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

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
                .inspectorActionButton()

                Button("Export Bundle") {
                    Task { await session.exportComparisonBundle() }
                }
                .buttonStyle(.bordered)
                .disabled(!session.canExportComparison)
                .inspectorActionButton()

                Button("Reveal Workbook") {
                    session.revealFocusedWorkbook()
                }
                .buttonStyle(.bordered)
                .disabled(session.focusedWorkbook == nil)
                .inspectorActionButton()

                Button("Reveal Output") {
                    session.revealLatestExport()
                }
                .buttonStyle(.bordered)
                .disabled(session.focusedWorkbook == nil && session.comparisonExportDestinationURL == nil)
                .inspectorActionButton()
            }
        }
    }

    private var figureFamilyBinding: Binding<String?> {
        Binding(
            get: { session.currentFigureFamily?.id },
            set: { newValue in
                if let newValue {
                    session.selectFigureFamily(id: newValue)
                }
            }
        )
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
