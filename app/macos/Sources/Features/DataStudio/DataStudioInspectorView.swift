import SwiftUI

struct DataStudioInspectorView: View {
    @Bindable var session: DataStudioSession
    @State private var templateRenameDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                templateSection
                workbookSection
                comparisonSection
                actionsSection
            }
            .padding(16)
        }
        .onAppear {
            syncTemplateRenameDraft()
        }
        .onChange(of: session.selectedTemplateID) { _, _ in
            syncTemplateRenameDraft()
        }
    }

    private var templateSection: some View {
        InspectorSection(title: "Template Status") {
            if let template = session.selectedTemplate {
                KeyValueGrid(values: [
                    ("Mode", session.templateMode.title),
                    ("Template", template.label),
                    ("Family", template.family),
                    ("Parse Strategy", template.parseStrategy),
                    ("Scope", template.builtin ? "Built-in" : "User"),
                ])

                if !template.builtin {
                    TextField("Rename Template", text: $templateRenameDraft)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 10) {
                        Button("Rename") {
                            Task { await session.renameSelectedTemplate(to: templateRenameDraft) }
                        }
                        .buttonStyle(.bordered)

                        Button("Delete", role: .destructive) {
                            Task { await session.deleteSelectedTemplate() }
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("Built-in templates stay available as defaults. Tensile remains the first built-in template family.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !session.sourceMatches.isEmpty {
                    Divider()
                    ForEach(session.sourceMatches) { match in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(match.label)
                                    .font(.footnote.weight(.medium))
                                Text(match.confidence.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let reason = match.reasons.first {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("Select or create a template to drive Data Studio import.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var workbookSection: some View {
        InspectorSection(title: "Focused Workbook") {
            if let workbook = session.focusedWorkbook {
                KeyValueGrid(values: [
                    ("Label", workbook.label),
                    ("Workbook", workbook.workbookURL.lastPathComponent),
                    ("Preferred Sheet", workbook.response.preferredSheet),
                    ("Parsed", "\(workbook.response.parsedSampleCount)"),
                    ("Failed", "\(workbook.response.failedSampleCount)"),
                    ("Representative", workbook.response.representativeFilename),
                ])

                HStack(spacing: 10) {
                    Button("Refresh Preview") {
                        Task { await session.refreshFocusedWorkbookPreview() }
                    }
                    .buttonStyle(.bordered)

                    Button("Reveal") {
                        session.revealFocusedWorkbook()
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    Button("Set as Primary") {
                        session.setPrimaryWorkbook(id: workbook.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.primaryWorkbookID == workbook.id)

                    Button("Remove", role: .destructive) {
                        session.removeWorkbook(id: workbook.id)
                    }
                    .buttonStyle(.bordered)
                }

                if let previewReport = workbook.reviewSubmissionReport {
                    Divider()
                    KeyValueGrid(values: [
                        ("Readiness", previewReport.readiness.capitalized),
                        ("Checks", "\(previewReport.checks.count)"),
                        ("Blockers", "\(previewReport.blockers.count)"),
                    ])
                }
            } else {
                Text("No workbook is currently focused.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var comparisonSection: some View {
        InspectorSection(title: "Comparison Set") {
            if let comparisonSet = session.comparisonSet {
                KeyValueGrid(values: [
                    ("Label", comparisonSet.label),
                    ("Workbooks", "\(comparisonSet.workbookLabels.count)"),
                    ("Recipes", "\(comparisonSet.recipes.count)"),
                    ("Enabled", "\(session.enabledRecipeIDs.count)"),
                    ("Preview", session.selectedRecipe?.label ?? "None"),
                ])

                if let selectedFigure = session.selectedComparisonFigure {
                    Divider()
                    KeyValueGrid(values: [
                        ("Latest Figure", selectedFigure.response.label),
                        ("Template", selectedFigure.response.templateID),
                        ("Sheet", selectedFigure.response.sheetName),
                    ])
                }

                if let exportDestination = session.comparisonExportDestinationURL {
                    Text(exportDestination.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else {
                Text("Load at least two workbooks to activate Data Studio comparison recipes.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionsSection: some View {
        InspectorSection(title: "Actions") {
            Button("Open Primary Workbook in Plot") {
                session.openPrimaryWorkbookInPlot()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.canOpenInPlot)

            Button("Export Comparison Bundle") {
                Task { await session.exportComparisonBundle() }
            }
            .buttonStyle(.bordered)
            .disabled(!session.canExportComparison)

            Button("Open Selected Figure") {
                session.openSelectedComparisonFigure()
            }
            .buttonStyle(.bordered)
            .disabled(session.selectedComparisonFigure == nil)

            Button("Reveal Latest Output") {
                session.revealLatestExport()
            }
            .buttonStyle(.bordered)
            .disabled(session.primaryWorkbook == nil && session.comparisonExportDestinationURL == nil)

            Button("Validate Session Payload") {
                Task {
                    _ = await session.normalizeSessionPayload()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func syncTemplateRenameDraft() {
        templateRenameDraft = session.selectedTemplate?.label ?? ""
    }
}
