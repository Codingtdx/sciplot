import SwiftUI

struct PlotImportView: View {
    @Bindable var session: PlotSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if session.selectedFileURL == nil {
                    ContentUnavailableView("Import Plot Source", systemImage: "tray.and.arrow.down")
                } else if session.isInspecting, session.inspectionResponse == nil {
                    BusyStateCard(title: "Inspecting Source")
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
                    Text(session.selectedSourceFilename ?? "No source selected")
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    if let selectedSheet = session.inspectionResponse?.sheet ?? (session.selectedFileURL == nil ? nil : session.selectedSheet) {
                        Text(selectedSheet.displayName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quinary.opacity(0.35), in: Capsule())
                    }
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
