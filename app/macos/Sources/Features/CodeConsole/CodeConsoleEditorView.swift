import SwiftUI

struct CodeConsoleEditorView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        TextEditor(text: $session.editorText)
            .font(.body.monospaced())
            .padding(12)
            .background(.quinary.opacity(0.2), in: RoundedRectangle(cornerRadius: 18))
    }
}
