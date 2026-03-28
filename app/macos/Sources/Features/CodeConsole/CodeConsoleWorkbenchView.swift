import SwiftUI

struct CodeConsoleWorkbenchView: View {
    let session: CodeConsoleSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ErrorStateCard(
                    title: "Runner unavailable",
                    message: session.unavailableReason,
                    retryTitle: nil,
                    retryAction: nil
                )

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Bound Context")
                            .font(.headline)

                        if session.boundContext.isEmpty {
                            EmptyStateCard(
                                title: "No bound context",
                                message: "Bind Plot or Data Cleanup work first to carry session context into Code Console."
                            )
                        } else {
                            ForEach(session.boundContext) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(item.value)
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.quinary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .frame(maxWidth: 280, alignment: .leading)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Editor")
                            .font(.headline)
                        CodeConsoleEditorView(session: session)
                            .frame(minHeight: 320)
                        CodeConsoleOutputsView(session: session)
                    }
                }
            }
            .padding(24)
        }
    }
}
