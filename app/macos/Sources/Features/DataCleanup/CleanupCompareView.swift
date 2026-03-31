import SwiftUI

struct CleanupCompareView: View {
    let session: DataCleanupSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Comparison Order") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Drag to reorder the compare/export sequence. The primary workbook stays fixed for Plot handoff.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    List {
                        ForEach(session.orderedPreparedWorkbooks) { workbook in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(workbook.label)
                                        .font(.subheadline.weight(.semibold))
                                    if workbook.id == session.primaryWorkbookID {
                                        Text("Primary")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    }
                                }
                                Text(workbook.url.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(workbook.sampleCount) specimens · \(workbook.metrics.count) metrics")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .onMove(perform: session.moveComparisonWorkbooks)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180, maxHeight: 260)
                }
                .padding(.top, 8)
            }

            GroupBox("Compare") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export the comparison workbook plus QC figures, then choose whether the figures stay as editable PDF or convert to 300 dpi TIFF.")
                        .foregroundStyle(.secondary)

                    Button("Export Comparison Bundle") {
                        Task { await session.exportComparisonBundle() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.orderedPreparedWorkbooks.count < 2 || session.isBusy)
                }
                .padding(.top, 8)
            }
        }
    }
}
