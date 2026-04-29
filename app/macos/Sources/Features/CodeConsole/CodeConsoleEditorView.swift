import SwiftUI

struct CodeConsoleEditorView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(minHeight: 96, idealHeight: 126, maxHeight: 150)
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func promptHeader(presentation: CodeConsoleEditorPresentation) -> some View {
        HStack {
            Text("Prompt")
                .font(.subheadline.weight(.semibold))
            Spacer()
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
        .layoutPriority(1)
    }

    private var editorCard: some View {
        let presentation = session.editorPresentation

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Python")
                    .font(.subheadline.weight(.semibold))
                Spacer()
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

            TextEditor(text: $session.editorText)
                .font(.body.monospaced())
                .padding(12)
                .frame(minHeight: 210, idealHeight: 260, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
                )
        }
    }
}
