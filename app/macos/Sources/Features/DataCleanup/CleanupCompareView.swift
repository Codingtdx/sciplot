import SwiftUI

struct CleanupCompareView: View {
    let session: DataCleanupSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Compare Queue") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Drag to reorder the compare/export sequence. The primary workbook always stays bound for Plot handoff.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if session.orderedPreparedWorkbooks.isEmpty {
                        EmptyStateCard(
                            title: "No compare queue yet",
                            message: "Load or preprocess prepared workbooks to build the runtime compare queue."
                        )
                    } else {
                        List {
                            ForEach(session.orderedPreparedWorkbooks) { workbook in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Text(workbook.label)
                                            .font(.subheadline.weight(.semibold))
                                        if workbook.id == session.primaryWorkbook?.id {
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
                                    HStack(spacing: 10) {
                                        Button("Use as Primary") {
                                            session.setPrimaryWorkbook(id: workbook.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(workbook.id == session.primaryWorkbook?.id)

                                        Button("Focus") {
                                            session.setFocusedWorkbook(id: workbook.id)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .onMove(perform: session.moveComparisonWorkbooks)
                        }
                        .listStyle(.inset)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 180, maxHeight: 280)
                    }
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
