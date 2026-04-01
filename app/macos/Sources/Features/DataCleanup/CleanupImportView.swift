import SwiftUI

struct CleanupImportView: View {
    let session: DataCleanupSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Intake") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Button("Raw CSV") {
                            session.beginImport(kind: .rawCSV)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Prepared Workbook") {
                            session.beginImport(kind: .preparedWorkbook)
                        }
                        .buttonStyle(.bordered)
                    }

                    if session.rawInputURLs.isEmpty {
                        Text("No raw CSV intake is currently staged.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Latest Raw Intake")
                            .font(.headline)
                        ForEach(session.rawInputURLs, id: \.path) { url in
                            Label(url.lastPathComponent, systemImage: "doc.text")
                        }
                    }
                }
                .padding(.top, 8)
            }

            GroupBox("Prepared Workbooks") {
                VStack(alignment: .leading, spacing: 12) {
                    if session.orderedPreparedWorkbooks.isEmpty {
                        Text("Load or preprocess a workbook to start review and compare.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(selection: selectionBinding) {
                            ForEach(session.orderedPreparedWorkbooks) { workbook in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(workbook.label)
                                            .font(.subheadline.weight(.semibold))
                                        if workbook.id == session.primaryWorkbook?.id {
                                            badge("Primary")
                                        }
                                        if workbook.id == session.focusedWorkbook?.id {
                                            badge("Focused")
                                        }
                                    }

                                    Text(workbook.url.lastPathComponent)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text("\(workbook.sampleCount) specimens · \(workbook.preferredSheet.displayName)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                .tag(workbook.id)
                            }
                        }
                        .listStyle(.inset)
                        .frame(minHeight: 220)

                        HStack(spacing: 10) {
                            Button("Set Primary") {
                                if let workbookID = session.focusedWorkbook?.id {
                                    session.setPrimaryWorkbook(id: workbookID)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(session.focusedWorkbook == nil || session.focusedWorkbook?.id == session.primaryWorkbook?.id)

                            Button("Refresh Preview") {
                                Task { await session.refreshFocusedReview() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(session.focusedWorkbook == nil)

                            Button("Remove", role: .destructive) {
                                if let workbookID = session.focusedWorkbook?.id {
                                    session.removeWorkbook(id: workbookID)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(session.focusedWorkbook == nil)
                        }
                    }
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { session.focusedWorkbook?.id },
            set: { session.setFocusedWorkbook(id: $0) }
        )
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}
