import SwiftUI

struct CleanupCompareView: View {
    let session: DataCleanupSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Comparison Inputs") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Prepared workbooks loaded: \(session.preparedWorkbooks.count)")
                        .font(.headline)

                    ForEach(session.preparedWorkbooks) { workbook in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workbook.url.lastPathComponent)
                            Text("\(workbook.sampleCount) specimens · \(workbook.metrics.count) metrics")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            }

            GroupBox("Compare") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use the sidecar comparison export to generate the representative curve comparison workbook and the QC figures.")
                        .foregroundStyle(.secondary)

                    Button("Export Comparison Bundle") {
                        Task { await session.exportComparisonBundle() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.preparedWorkbooks.count < 2 || session.isBusy)
                }
                .padding(.top, 8)
            }
        }
    }
}
