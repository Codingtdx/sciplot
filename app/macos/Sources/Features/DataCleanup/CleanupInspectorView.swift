import SwiftUI

struct CleanupInspectorView: View {
    let session: DataCleanupSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InspectorSection(title: "Session") {
                    KeyValueGrid(values: [
                        ("Raw inputs", "\(session.rawInputURLs.count)"),
                        ("Prepared workbooks", "\(session.preparedWorkbooks.count)"),
                    ])
                }

                InspectorSection(title: "Group") {
                    if session.groupName.isEmpty {
                        Text("A group name will be suggested from the imported raw files.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(session.groupName)
                    }
                }
            }
            .padding(16)
        }
    }
}
