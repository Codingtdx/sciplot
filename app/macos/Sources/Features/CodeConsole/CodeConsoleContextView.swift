import SwiftUI

struct CodeConsoleContextView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                bindingSection
                runnerSection
                outputHandoffSection
                advancedSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .inspectorSurface()
    }

    @ViewBuilder
    private var advancedSection: some View {
        let presentation = session.outputsPresentation
        let sourcePresentation = session.sourceActionsPresentation

        InspectorSection(title: "Advanced") {
            InspectorActionStack {
                Button("Open Source") {
                    session.openCurrentSource()
                }
                .buttonStyle(.bordered)
                .disabled(!sourcePresentation.openSourceAvailability.isEnabled)
                .help(sourcePresentation.openSourceAvailability.reason ?? "Open the bound source file.")
                .inspectorActionButton()

                Button("Reveal Source") {
                    session.revealCurrentSource()
                }
                .buttonStyle(.bordered)
                .disabled(!sourcePresentation.revealSourceAvailability.isEnabled)
                .help(sourcePresentation.revealSourceAvailability.reason ?? "Reveal the bound source file in Finder.")
                .inspectorActionButton()

                Button("Reveal Output") {
                    session.revealLatestOutput()
                }
                .buttonStyle(.bordered)
                .disabled(!presentation.revealLatestOutputAvailability.isEnabled)
                .help(
                    presentation.revealLatestOutputAvailability.reason
                        ?? "Reveal the latest export or managed output folder in Finder."
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

    @ViewBuilder
    private var bindingSection: some View {
        InspectorSection(title: "Binding") {
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
                    }
                }
            } else {
                InspectorEmptyState(message: "No bound dataset")
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
        InspectorSection(title: "Runner") {
            AdaptiveInspectorTextRow(title: "Prompt", value: session.promptText.isEmpty ? "Not ready" : "Ready")
            AdaptiveInspectorTextRow(title: "Editor", value: session.editorText.isEmpty ? "Empty" : "Loaded")
            AdaptiveInspectorTextRow(title: "Runner", value: session.isRunning ? "Running" : "Idle")
        }
    }

    @ViewBuilder
    private var outputHandoffSection: some View {
        InspectorSection(title: "Outputs & Handoff") {
            if let run = session.latestRunResponse {
                AdaptiveInspectorTextRow(title: "Run status", value: run.status.capitalized)
                AdaptiveInspectorTextRow(title: "Generated files", value: "\(run.generatedFiles.count)")
                AdaptiveInspectorTextRow(
                    title: "Output folder",
                    value: run.outputDir,
                    selectable: true
                )
            } else {
                InspectorEmptyState(message: "No outputs")
            }
        }
    }
}
