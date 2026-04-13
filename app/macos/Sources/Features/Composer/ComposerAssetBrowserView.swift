import SwiftUI

struct ComposerAssetBrowserView: View {
    @Bindable var session: ComposerSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Library")
                .font(.title3.weight(.semibold))

            if session.orderedPanels.isEmpty {
                EmptyStateCard(title: "No imported panels")
            } else {
                List(selection: panelSelectionBinding) {
                    ForEach(session.orderedPanels) { panel in
                        ComposerLibraryRow(
                            panel: panel,
                            resolvedLabel: session.resolvedLabel(for: panel)
                        ) {
                            session.beginPanelDrag(panel.id)
                        } onDragEnded: {
                            session.endPanelDrag(panel.id)
                        }
                        .tag(panel.id)
                        .contextMenu {
                            Button("Select") {
                                session.focusPanel(panel.id)
                            }

                            if let target = session.selectedPlacementTarget,
                               session.canPlace(panelID: panel.id, in: target) {
                                Button(panel.hidden ? "Place Here" : "Move Here") {
                                    session.focusPanel(panel.id)
                                    session.place(panelID: panel.id, in: target)
                                }
                            }

                            if !panel.hidden && !panel.locked {
                                Button("Remove From Board") {
                                    session.focusPanel(panel.id)
                                    session.removeSelectedPanelFromBoard()
                                }
                            }

                            if session.selectedPanelID == panel.id {
                                Button("Clear Selection") {
                                    session.clearTransientEditingState()
                                }
                            }
                        }
                    }
                    .onMove(perform: session.movePanels)
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
                .scrollContentBackground(.hidden)
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.quinary.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
    }

    private var panelSelectionBinding: Binding<Set<String>> {
        Binding(
            get: {
                if let selectedPanelID = session.selectedPanelID {
                    return [selectedPanelID]
                }
                return []
            },
            set: { newSelection in
                session.focusPanel(newSelection.first)
            }
        )
    }
}

private struct ComposerLibraryRow: View {
    let panel: ComposerPanelPayload
    let resolvedLabel: String
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ComposerPanelThumbnailView(
                url: URL(fileURLWithPath: panel.filePath),
                size: CGSize(width: 76, height: 58),
                cornerRadius: 12
            )
            .frame(width: 76, height: 58)
            .opacity(panel.hidden ? 0.45 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        onDragStarted()
                    }
                    .onEnded { _ in
                        onDragEnded()
                    }
            )
            .draggable(
                ComposerPanelDragPayload(panelID: panel.id, sourceSurface: .library)
            ) {
                ComposerPanelThumbnailView(
                    url: URL(fileURLWithPath: panel.filePath),
                    size: CGSize(width: 132, height: 96),
                    cornerRadius: 14
                )
                .frame(width: 132, height: 96)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Text(fileName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    if !resolvedLabel.isEmpty {
                        Text(resolvedLabel)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.background, in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: kindSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if panel.locked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if panel.hidden {
                        Image(systemName: "eye.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fileName: String {
        URL(fileURLWithPath: panel.filePath).lastPathComponent
    }
    private var kindSymbol: String {
        panel.kind == "graph" ? "chart.xyaxis.line" : "photo"
    }
}
