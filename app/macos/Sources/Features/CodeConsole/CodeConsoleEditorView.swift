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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("External AI Prompt")
                        .font(.headline)
                    Text("Copy this controlled prompt, let the external AI return Python, then paste that code below.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    session.refreshPrompt()
                }
                .buttonStyle(.bordered)

                Button("Copy Prompt") {
                    session.copyPromptToPasteboard()
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                Text(session.promptText.isEmpty ? "Bind a dataset to generate the prompt." : session.promptText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(minHeight: 150, maxHeight: 220)
        }
        .padding(16)
        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Python Code")
                        .font(.headline)
                    Text("Use the repo-native helper imports so the figure style stays aligned with Plot.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restore Starter") {
                    session.restoreStarterCode()
                }
                .buttonStyle(.bordered)

                Button("Run Script") {
                    Task { await session.runCurrentCode() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isRunning)
            }

            TextEditor(text: $session.editorText)
                .font(.body.monospaced())
                .padding(12)
                .frame(minHeight: 320)
                .background(.quinary.opacity(0.2), in: RoundedRectangle(cornerRadius: 18))
        }
        .padding(16)
        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
    }
}
