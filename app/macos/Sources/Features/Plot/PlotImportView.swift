import SwiftUI

struct PlotImportView: View {
    @Bindable var session: PlotSession
    @State private var isDataPreviewExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if session.selectedFileURL == nil {
                ContentUnavailableView(
                    "Import a Plot source",
                    systemImage: "tray.and.arrow.down",
                    description: Text("Choose a `.csv`, `.xlsx`, or `.xlsm` file to inspect and continue.")
                )
            } else if session.isInspecting, session.inspectionResponse == nil {
                BusyStateCard(
                    title: "Inspecting source",
                    message: "Loading compatible templates and source summary."
                )
            }

            PlotTemplateView(session: session)

            if let inspection = session.inspectionResponse {
                HStack(spacing: 14) {
                    Label(inspection.inspection.modelLabel, systemImage: "doc.text.magnifyingglass")
                    Label("\(session.compatibleRecommendations.count) compatible", systemImage: "checkmark.circle")
                    if let selectedTemplate = session.selectedTemplateSummary?.label {
                        Label(selectedTemplate, systemImage: "square.grid.2x2")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                DisclosureGroup("Data Preview", isExpanded: $isDataPreviewExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        KeyValueGrid(values: [
                            ("Rows", "\(inspection.dataset?.rawRows ?? 0)"),
                            ("Columns", "\(inspection.dataset?.rawCols ?? 0)"),
                            ("Shapes", (inspection.dataset?.dataShapes ?? []).prefix(2).joined(separator: ", ")),
                            ("Quality flags", "\(inspection.dataset?.qualityFlags.count ?? 0)"),
                        ])

                        if session.sampleRows.isEmpty {
                            Text("No sample rows available.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            PlotSampleTable(session: session)
                                .frame(minHeight: 170, maxHeight: 210)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.subheadline.weight(.medium))
            } else if session.selectedFileURL != nil {
                ContentUnavailableView(
                    "Inspect this source",
                    systemImage: "magnifyingglass",
                    description: Text("Use Inspect to load compatibility and continue with a template.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlotSampleTable: View {
    let session: PlotSession

    var body: some View {
        Table(session.sampleRows) {
            TableColumn("Row") { row in
                Text("\(row.id + 1)")
                    .foregroundStyle(.secondary)
            }

            TableColumnForEach(session.sampleColumns) { column in
                TableColumn(column.title) { row in
                    Text(row.value(at: column.id).displayString)
                        .lineLimit(1)
                }
            }
        }
    }
}
