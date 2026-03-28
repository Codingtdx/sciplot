import SwiftUI

struct CleanupExportView: View {
    let session: DataCleanupSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let comparisonExport = session.comparisonExportResponse {
                GroupBox("Comparison Export") {
                    VStack(alignment: .leading, spacing: 12) {
                        KeyValueGrid(values: [
                            ("Bundle directory", comparisonExport.bundleDir),
                            ("Workbook", comparisonExport.comparisonWorkbookPath),
                            ("Outputs", "\(comparisonExport.outputs.count)"),
                        ])

                        HStack {
                            Button("Reveal in Finder") {
                                session.revealLatestExport()
                            }

                            Button("Open in Plot") {
                                session.openPrimaryWorkbookInPlot()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 8)
                }
            } else {
                EmptyStateCard(
                    title: "No comparison bundle exported yet",
                    message: "Export the comparison bundle first, or hand the current prepared workbook into Plot."
                )
            }

            if !session.preparedWorkbooks.isEmpty {
                Button("Open in Plot") {
                    session.openPrimaryWorkbookInPlot()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
