import SwiftUI

struct ComposerAssetBrowserView: View {
    let session: ComposerSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let panels = session.project.panels
            let panelPairs: [(Int, ComposerPanelPayload)] = panels.enumerated().map { ($0.offset, $0.element) }

            Text("Assets")
                .font(.headline)

            HStack {
                Button("Add Graph") {
                    session.beginImport(kind: .graph)
                }
                .buttonStyle(.borderedProminent)

                Button("Add Asset") {
                    session.beginImport(kind: .asset)
                }
            }

            Divider()

            if panelPairs.isEmpty {
                Text("No panels imported yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(panelPairs, id: \.0) { _, panel in
                    let panelName = panel.filePath.components(separatedBy: "/").last ?? panel.id
                    let systemImage = panel.kind == "graph" ? "chart.xyaxis.line" : "photo"
                    let isSelected = panel.id == session.selectedPanelID

                    Button {
                        session.selectPanel(panel.id)
                    } label: {
                        HStack {
                            Label(panelName, systemImage: systemImage)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quinary.opacity(isSelected ? 0.35 : 0.15), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
    }
}
