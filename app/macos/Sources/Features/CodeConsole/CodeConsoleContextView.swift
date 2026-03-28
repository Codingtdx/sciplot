import SwiftUI

struct CodeConsoleContextView: View {
    let session: CodeConsoleSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InspectorSection(title: "Status") {
                    Text(session.unavailableReason)
                        .foregroundStyle(.secondary)
                }

                InspectorSection(title: "Bound Context") {
                    if session.boundContext.isEmpty {
                        Text("No Plot or Data Cleanup context is currently bound.")
                            .foregroundStyle(.secondary)
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
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
