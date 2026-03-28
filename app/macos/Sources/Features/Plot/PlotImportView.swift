import SwiftUI

struct PlotImportView: View {
    let session: PlotSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select a `.csv`, `.xlsx`, or `.xlsm` data source and inspect the normalized dataset through the sidecar.")
                        .foregroundStyle(.secondary)

                    if let selectedFileURL = session.selectedFileURL {
                        KeyValueGrid(values: [
                            ("Source", selectedFileURL.lastPathComponent),
                            ("Path", selectedFileURL.path),
                            ("Sheet", session.selectedSheet.displayName),
                        ])
                    } else {
                        EmptyStateCard(
                            title: "No data source selected",
                            message: "Use the import action to choose a file for Plot."
                        )
                    }

                    HStack {
                        if session.availableSheets.count > 1 {
                            Picker("Sheet", selection: bindingForSheet) {
                                ForEach(session.availableSheets, id: \.self) { sheet in
                                    Text(sheet.displayName).tag(sheet)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 240)
                        }

                        Spacer()

                        Button("Inspect") {
                            Task { await session.inspectCurrentFile() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.selectedFileURL == nil || session.isInspecting)
                    }
                }
                .padding(12)
            }

            if session.isInspecting {
                BusyStateCard(title: "Inspecting input", message: "The sidecar is reading the dataset structure and recommendations.")
            } else if let errorMessage = session.errorMessage {
                ErrorStateCard(
                    title: "Inspect failed",
                    message: errorMessage,
                    retryTitle: "Retry Inspect"
                ) {
                    Task { await session.inspectCurrentFile() }
                }
            } else if let inspection = session.inspectionResponse {
                GroupBox("Inspection Summary") {
                    VStack(alignment: .leading, spacing: 16) {
                        KeyValueGrid(values: [
                            ("Detected model", inspection.inspection.modelLabel),
                            ("Recommendation", inspection.inspection.recommendation.template),
                            ("Confidence", inspection.inspection.recommendationConfidence.formatted(.percent)),
                        ])

                        if !inspection.inspection.warnings.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Warnings")
                                    .font(.headline)
                                ForEach(inspection.inspection.warnings, id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.triangle")
                                }
                            }
                        }
                    }
                    .padding(12)
                }

                GroupBox("Sample Rows") {
                    PlotSampleTable(session: session)
                        .frame(minHeight: 220)
                        .padding(.top, 8)
                }
            }
        }
    }

    private var bindingForSheet: Binding<SheetValue> {
        Binding(
            get: { session.selectedSheet },
            set: { session.selectedSheet = $0 }
        )
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
