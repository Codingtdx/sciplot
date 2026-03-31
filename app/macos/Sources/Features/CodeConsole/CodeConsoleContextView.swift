import SwiftUI

struct CodeConsoleContextView: View {
    let session: CodeConsoleSession

    var body: some View {
        Form {
            contextSummarySection
            boundContextSection
            outputHandoffSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var contextSummarySection: some View {
        Section("Context Summary") {
            Label("Runner unavailable", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(session.unavailableReason)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var boundContextSection: some View {
        Section("Bound Context") {
            if session.boundContext.isEmpty {
                Text("No Plot or Data Cleanup context is currently bound.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.boundContext) { item in
                    LabeledContent(item.label, value: item.value)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var outputHandoffSection: some View {
        Section("Output & Handoff") {
            Text(session.outputsSummary)
                .foregroundStyle(.secondary)
        }
    }
}
