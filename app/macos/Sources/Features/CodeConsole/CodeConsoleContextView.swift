import SwiftUI

struct CodeConsoleContextView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        Form {
            contextSummarySection
            boundContextSection
            runnerSection
            outputHandoffSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var contextSummarySection: some View {
        Section("Context Summary") {
            Label(session.liveStatusLabel, systemImage: session.liveStatusSymbol)
                .foregroundStyle(session.errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))

            if let binding = session.selectedBinding {
                LabeledContent("Source", value: binding.sourceURL.lastPathComponent)
                LabeledContent("Origin", value: binding.sourceKind.title)
                LabeledContent("Sheet", value: session.selectedSheet.displayName)
            } else {
                Text("No Plot, Data Studio, or direct import source is currently bound.")
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var boundContextSection: some View {
        Section("Bound Context") {
            if session.boundContext.isEmpty {
                Text("Context metadata appears here after the current dataset has been inspected.")
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
    private var runnerSection: some View {
        Section("Prompt & Runner") {
            LabeledContent("Prompt", value: session.promptText.isEmpty ? "Not ready" : "Ready")
            LabeledContent("Editor", value: session.editorText.isEmpty ? "Empty" : "Loaded")
            LabeledContent("Runner", value: session.isRunning ? "Running" : "Idle")
            Text(session.promptStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var outputHandoffSection: some View {
        Section("Output & Handoff") {
            Text(session.outputsSummary)
                .foregroundStyle(.secondary)

            if let run = session.latestRunResponse {
                LabeledContent("Run status", value: run.status.capitalized)
                LabeledContent("Generated files", value: "\(run.generatedFiles.count)")
                LabeledContent("Output folder", value: run.outputDir)
                    .textSelection(.enabled)
            } else {
                Text("No managed Code Console run has completed yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
