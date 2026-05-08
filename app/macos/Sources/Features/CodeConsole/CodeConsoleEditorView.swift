import SwiftUI

struct CodeConsoleEditorView: View {
    @Bindable var session: CodeConsoleSession
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkspaceMetrics.panelSpacing) {
            promptCard
            editorCard
        }
    }

    private var promptCard: some View {
        let presentation = session.editorPresentation

        return VStack(alignment: .leading, spacing: 12) {
            promptHeader(presentation: presentation)

            ScrollView {
                Text(session.promptText.isEmpty ? "Bind a dataset to generate the prompt." : session.promptText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(minHeight: 96, idealHeight: 126, maxHeight: 150)
            .padding(ProWorkspaceMetrics.editorCardPadding)
            .proEditorSurface(theme: theme)
        }
    }

    private func promptHeader(presentation: CodeConsoleEditorPresentation) -> some View {
        HStack {
            Text("Prompt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            HStack(spacing: ProWorkspaceMetrics.commandStripSpacing) {
                Button("Refresh") {
                    session.refreshPrompt()
                }
                .buttonStyle(.bordered)
                .disabled(!presentation.refreshPromptAvailability.isEnabled)
                .help(
                    presentation.refreshPromptAvailability.reason
                        ?? "Refresh the bound context and regenerate the external AI prompt."
                )

                Button("Copy Prompt") {
                    session.copyPromptToPasteboard()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!presentation.copyPromptAvailability.isEnabled)
                .help(
                    presentation.copyPromptAvailability.reason
                        ?? "Copy the current external AI prompt to the clipboard."
                )
            }
            .controlSize(.small)
        }
        .layoutPriority(1)
    }

    private var editorCard: some View {
        let presentation = session.editorPresentation

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Python")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                HStack(spacing: ProWorkspaceMetrics.commandStripSpacing) {
                    Button("Restore Starter") {
                        session.restoreStarterCode()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.restoreStarterAvailability.isEnabled)
                    .help(
                        presentation.restoreStarterAvailability.reason
                            ?? "Restore the starter code that matches the current bound context."
                    )

                    Button("Run Script") {
                        Task { await session.runCurrentCode() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!presentation.runAvailability.isEnabled)
                    .help(
                        presentation.runAvailability.reason
                            ?? "Run the current Python code against the bound Code Console context."
                    )
                }
                .controlSize(.small)
            }

            TextEditor(text: $session.editorText)
                .font(.callout.monospaced())
                .padding(ProWorkspaceMetrics.editorCardPadding)
                .frame(minHeight: 210, idealHeight: 260, maxHeight: .infinity)
                .proEditorSurface(theme: theme)
        }
    }
}
