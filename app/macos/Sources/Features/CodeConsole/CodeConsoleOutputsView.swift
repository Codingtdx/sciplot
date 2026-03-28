import SwiftUI

struct CodeConsoleOutputsView: View {
    let session: CodeConsoleSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Outputs")
                .font(.headline)
            Text(session.outputsSummary)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quinary.opacity(0.25), in: RoundedRectangle(cornerRadius: 18))
    }
}
