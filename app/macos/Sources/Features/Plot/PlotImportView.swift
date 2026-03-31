import SwiftUI

struct PlotImportView: View {
    @Bindable var session: PlotSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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

                sourceSummary

                PlotTemplateView(session: session)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension PlotImportView {
    var sourceSummary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.selectedSourceFilename ?? "No source selected")
                            .font(.headline)
                            .lineLimit(1)

                        if let modelLabel = session.inspectionResponse?.inspection.modelLabel {
                            Text(modelLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Import a file and run inspect to unlock compatible templates.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if let selectedSheet = session.inspectionResponse?.sheet ?? (session.selectedFileURL == nil ? nil : session.selectedSheet) {
                        Text(selectedSheet.displayName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quinary.opacity(0.35), in: Capsule())
                    }
                }

                if let path = session.selectedSourcePath {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                if let inspection = session.inspectionResponse {
                    HStack(spacing: 10) {
                        Label(inspection.inspection.modelLabel, systemImage: "doc.text.magnifyingglass")
                        Label("\(session.compatibleRecommendations.count) compatible", systemImage: "checkmark.circle")
                        if let selectedTemplate = session.selectedTemplateSummary?.label {
                            Label(selectedTemplate, systemImage: "square.grid.2x2")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        } label: {
            Text("Source")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
