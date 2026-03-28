import SwiftUI

struct CleanupImportView: View {
    let session: DataCleanupSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Button("Import Raw CSV") {
                    session.isRawImporterPresented = true
                }
                .buttonStyle(.borderedProminent)

                Button("Open Prepared Workbook") {
                    session.isWorkbookImporterPresented = true
                }
                .buttonStyle(.bordered)
            }

            GroupBox("Current Intake") {
                VStack(alignment: .leading, spacing: 12) {
                    if session.rawInputURLs.isEmpty && session.preparedWorkbooks.isEmpty {
                        Text("No cleanup sources are loaded yet.")
                            .foregroundStyle(.secondary)
                    }

                    if !session.rawInputURLs.isEmpty {
                        Text("Raw CSV Intake")
                            .font(.headline)
                        ForEach(session.rawInputURLs, id: \.path) { url in
                            Label(url.lastPathComponent, systemImage: "doc.text")
                        }
                    }

                    if !session.preparedWorkbooks.isEmpty {
                        Text("Prepared Workbooks")
                            .font(.headline)
                        ForEach(session.preparedWorkbooks) { workbook in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workbook.url.lastPathComponent)
                                Text("\(workbook.sampleCount) specimens · \(workbook.preferredSheet.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}
