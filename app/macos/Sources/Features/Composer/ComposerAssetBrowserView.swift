import SwiftUI

struct ComposerAssetBrowserView: View {
    @Bindable var session: ComposerSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if session.orderedPanels.isEmpty {
                EmptyStateCard(
                    title: "No imported panels",
                    message: "Use the Import action in the toolbar to add graph PDFs or supporting assets."
                )
            } else {
                List(selection: panelSelectionBinding) {
                    ForEach(session.orderedPanels) { panel in
                        ComposerLibraryRow(
                            panel: panel,
                            isReplacementArmed: session.isReplacementArmed(for: panel.id),
                            resolvedLabel: session.resolvedLabel(for: panel),
                            placementSummary: session.placementSummary(for: panel)
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

                            if !panel.locked {
                                Button(
                                    session.isReplacementArmed(for: panel.id) ? "Replacing…" : "Replace"
                                ) {
                                    session.beginReplacement(for: panel.id)
                                }
                                .disabled(session.isReplacementArmed(for: panel.id))
                            }

                            if session.selectedPanelID == panel.id || session.isReplacementArmed(for: panel.id) {
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Library")
                .font(.title3.weight(.semibold))
            Text("Imported panels stay here until you place them into the composition grid.")
                .foregroundStyle(.secondary)
        }
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
    let isReplacementArmed: Bool
    let resolvedLabel: String
    let placementSummary: String
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
                    Label(kindTitle, systemImage: kindSymbol)
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

                Text(placementSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if isReplacementArmed {
                    Label("Replace armed", systemImage: "arrow.triangle.swap")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fileName: String {
        URL(fileURLWithPath: panel.filePath).lastPathComponent
    }

    private var kindTitle: String {
        panel.kind == "graph" ? "Graph" : "Asset"
    }

    private var kindSymbol: String {
        panel.kind == "graph" ? "chart.xyaxis.line" : "photo"
    }
}
