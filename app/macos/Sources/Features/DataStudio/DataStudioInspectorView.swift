import SwiftUI

struct DataStudioInspectorView: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        if session.showsCompactEmptyInspector {
            compactEmptyInspector
        } else {
            PlotInspectorView(session: session.plotSession, styleSectionTitle: "Style") {
                figureSection
                dataSection
            } trailingSections: {
                studioSection
                if session.showsInspectorActions {
                    actionsSection
                }
            }
        }
    }

    private var compactEmptyInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                compactSection(
                    title: "Figure",
                    message: "Import at least one group to activate the Data Studio figure selector."
                )

                compactSection(
                    title: "Data",
                    message: "No workbook groups are loaded."
                )

                compactSection(
                    title: "Studio",
                    message: "Representative, exclusion, and aggregation rules appear once workbook data is loaded."
                )

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .inspectorSurface()
    }

    private var figureSection: some View {
        Section("Figure") {
            if session.figureFamilies.isEmpty {
                Text("Import at least one group to activate the Data Studio figure selector.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Type") {
                    Picker("", selection: figureFamilyBinding) {
                        ForEach(session.figureFamilies) { family in
                            Text(family.title).tag(Optional(family.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                if !session.availableFigureTemplates.isEmpty {
                    LabeledContent("Template") {
                        Picker("", selection: figureTemplateBinding) {
                            ForEach(session.availableFigureTemplates) { template in
                                Text(template.label).tag(Optional(template.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                LabeledContent("Metric", value: session.currentFigureFamily?.title ?? "Representative Curve")
            }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            if session.orderedGroups.isEmpty {
                Text("No workbook groups are loaded.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Included", value: "\(session.includedGroups.count)")

                ForEach(session.includedGroups) { group in
                    LabeledContent(group.state.displayName.isEmpty ? group.workbook.response.label : group.state.displayName) {
                        Text("\(group.workbook.response.parsedSampleCount) reps")
                            .foregroundStyle(.secondary)
                    }
                }

                if let comparisonSet = session.comparisonSet {
                    LabeledContent("Workbook", value: URL(fileURLWithPath: comparisonSet.comparisonWorkbookPath).lastPathComponent)
                }
            }
        }
    }

    private var studioSection: some View {
        Section("Studio") {
            LabeledContent("Representative", value: "Closest to the median replicate profile")
            LabeledContent("Outlier / Exclusion", value: "Uses workbook warnings and exclusions")
            LabeledContent("Metric Aggregation", value: "Workbook mean and std")

            if let focusedWorkbook = session.focusedWorkbook, !focusedWorkbook.response.warnings.isEmpty {
                Divider()
                ForEach(Array(focusedWorkbook.response.warnings.prefix(4)), id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            Button("Open Current Figure in Plot") {
                session.openCurrentFigureInPlot()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.canOpenCurrentFigureInPlot)

            Button("Export Figure Bundle") {
                Task { await session.exportComparisonBundle() }
            }
            .buttonStyle(.bordered)
            .disabled(!session.canExportComparison)

            Button("Reveal Workbook") {
                session.revealFocusedWorkbook()
            }
            .buttonStyle(.bordered)
            .disabled(session.focusedWorkbook == nil)

            Button("Reveal Latest Output") {
                session.revealLatestExport()
            }
            .buttonStyle(.bordered)
            .disabled(session.focusedWorkbook == nil && session.comparisonExportDestinationURL == nil)

            if session.hasSessionContent {
                Button("Validate Session Payload") {
                    Task {
                        _ = await session.normalizeSessionPayload()
                    }
                }
                .buttonStyle(.bordered)
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

    private func compactSection(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
