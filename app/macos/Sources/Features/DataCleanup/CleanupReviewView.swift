import SwiftUI

struct CleanupReviewView: View {
    let session: DataCleanupSession

    var body: some View {
        if session.isBusy {
            BusyStateCard(title: "Preparing workbook", message: "The sidecar is generating or inspecting the cleaned workbook.")
        } else if let workbook = session.preparedWorkbooks.first {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Prepared Workbook") {
                    VStack(alignment: .leading, spacing: 12) {
                        KeyValueGrid(values: [
                            ("Label", workbook.label),
                            ("Specimens", "\(workbook.sampleCount)"),
                            ("Representative file", workbook.representativeFilename),
                            ("Preferred sheet", workbook.preferredSheet.displayName),
                        ])
                    }
                    .padding(.top, 8)
                }

                GroupBox("Metric Summary") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(workbook.metrics, id: \.label) { metric in
                            KeyValueGrid(values: [
                                ("Metric", metric.label),
                                ("Unit", metric.unit),
                                ("Mean", metric.mean?.formatted() ?? "—"),
                                ("Std", metric.std?.formatted() ?? "—"),
                            ])
                            Divider()
                        }
                    }
                    .padding(.top, 8)
                }

                if !workbook.warnings.isEmpty {
                    GroupBox("Warnings") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(workbook.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
        } else {
            EmptyStateCard(
                title: "No prepared workbook yet",
                message: "Import raw tensile CSV files or open an existing prepared workbook to review cleanup results."
            )
        }
    }
}
