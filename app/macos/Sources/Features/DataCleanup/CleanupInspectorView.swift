import SwiftUI

struct CleanupInspectorView: View {
    let session: DataCleanupSession

    var body: some View {
        Form {
            contextSummarySection
            primaryActionsSection
            outputHandoffSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var contextSummarySection: some View {
        Section("Context Summary") {
            LabeledContent("Stage", value: session.stage.title)
            LabeledContent("Raw inputs", value: "\(session.rawInputURLs.count)")
            LabeledContent("Prepared workbooks", value: "\(session.preparedWorkbooks.count)")

            if let workbook = session.preparedWorkbooks.first {
                LabeledContent("Primary workbook", value: workbook.url.lastPathComponent)
                LabeledContent("Preferred sheet", value: workbook.preferredSheet.displayName)
            } else {
                Text("Import raw CSVs or prepared workbooks to start Data Cleanup.")
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = session.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var primaryActionsSection: some View {
        Section("Primary Actions") {
            Button("Export Comparison Bundle") {
                Task { await session.exportComparisonBundle() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.preparedWorkbooks.count < 2 || session.isBusy)

            if !session.preparedWorkbooks.isEmpty {
                Button("Open in Plot") {
                    session.openPrimaryWorkbookInPlot()
                }
                .buttonStyle(.bordered)
            }

            if session.comparisonExportDestinationURL != nil {
                Button("Reveal In Finder") {
                    session.revealLatestExport()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var outputHandoffSection: some View {
        Section("Output & Handoff") {
            if let comparisonExportResponse = session.comparisonExportResponse {
                LabeledContent(
                    "Destination",
                    value: session.comparisonExportDestinationURL?.path ?? comparisonExportResponse.bundleDir
                )
                LabeledContent(
                    "Comparison workbook",
                    value: URL(fileURLWithPath: comparisonExportResponse.comparisonWorkbookPath).lastPathComponent
                )
                LabeledContent("Outputs", value: "\(comparisonExportResponse.outputs.count)")
                if !session.comparisonExportFigureURLs.isEmpty {
                    LabeledContent(
                        "Figure format",
                        value: session.comparisonExportFigureURLs[0].pathExtension.uppercased()
                    )
                }
            } else if let primaryWorkbookURL = session.primaryWorkbookURL {
                LabeledContent("Prepared workbook", value: primaryWorkbookURL.lastPathComponent)
                Text("Export the comparison bundle to generate the handoff workbook plus editable PDF or 300 dpi TIFF figures.")
                    .foregroundStyle(.secondary)
            } else {
                Text("No cleanup export output yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
