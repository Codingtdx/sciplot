import SwiftUI

struct CodeConsoleContextView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        Form {
            actionsSection
            bindingSection
            runnerSection
            outputHandoffSection
        }
        .formStyle(.grouped)
        .inspectorSurface()
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section("Actions") {
            InspectorActionStack {
                Button("Export") {
                    session.exportCurrentOutputs()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.exportAvailability.isEnabled)
                .help(
                    session.exportAvailability.reason
                        ?? "Export the latest run's generated PDF figures as PDF or 300 dpi TIFF."
                )
                .inspectorActionButton()
            }

            DisclosureGroup("Advanced") {
                InspectorActionStack {
                    Button("Reveal Output") {
                        session.revealLatestOutput()
                    }
                    .buttonStyle(.bordered)
                    .disabled(session.latestRunResponse == nil && session.latestExportItems.isEmpty)
                    .help(
                        session.latestRunResponse == nil && session.latestExportItems.isEmpty
                            ? "Run code to generate managed outputs first."
                            : "Reveal the latest export or managed output folder in Finder."
                    )
                    .inspectorActionButton()
                }

                LatestExportList(
                    items: session.latestExportItems,
                    openButtonTitle: { "Open \($0.label)" },
                    openButtonHelp: { "Open the exported Code Console figure \($0.label)." },
                    openAction: { session.openLatestExport(id: $0.id) }
                )
            }
        }
    }

    @ViewBuilder
    private var bindingSection: some View {
        Section("Binding") {
            Label(session.liveStatusLabel, systemImage: session.liveStatusSymbol)
                .foregroundStyle(session.errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))

            if let binding = session.selectedBinding {
                AdaptiveInspectorTextRow(
                    title: "Source",
                    value: binding.sourceURL.lastPathComponent,
                    selectable: true
                )
                AdaptiveInspectorTextRow(title: "Origin", value: binding.sourceKind.title)
                AdaptiveInspectorTextRow(title: "Sheet", value: session.selectedSheet.displayName)

                if !session.boundContext.isEmpty {
                    Divider()
                    ForEach(session.boundContext) { item in
                        AdaptiveInspectorTextRow(title: item.label, value: item.value, selectable: true)
                        if !item.detail.isEmpty, item.detail != item.value {
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                InspectorEmptyState(message: "Bind a dataset to enable context.")
            }

            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var runnerSection: some View {
        Section("Runner") {
            AdaptiveInspectorTextRow(title: "Prompt", value: session.promptText.isEmpty ? "Not ready" : "Ready")
            AdaptiveInspectorTextRow(title: "Editor", value: session.editorText.isEmpty ? "Empty" : "Loaded")
            AdaptiveInspectorTextRow(title: "Runner", value: session.isRunning ? "Running" : "Idle")
            Text(session.promptStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var outputHandoffSection: some View {
        Section("Outputs & Handoff") {
            if let run = session.latestRunResponse {
                AdaptiveInspectorTextRow(title: "Run status", value: run.status.capitalized)
                AdaptiveInspectorTextRow(title: "Generated files", value: "\(run.generatedFiles.count)")
                AdaptiveInspectorTextRow(
                    title: "Output folder",
                    value: run.outputDir,
                    selectable: true
                )

                if !session.outputsSummary.isEmpty {
                    Text(session.outputsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                InspectorEmptyState(message: "Run code to generate managed outputs.")
            }
        }
    }
}
