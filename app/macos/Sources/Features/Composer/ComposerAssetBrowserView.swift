import SwiftUI

struct ComposerAssetBrowserView: View {
    @Bindable var session: ComposerSession
    @State private var libraryFilter: ComposerLibraryFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkspaceMetrics.panelSpacing) {
            WorkbenchRailTitle(title: "Library", trailing: "\(filteredPanels.count)/\(session.orderedPanels.count)")

            Picker("Library Filter", selection: $libraryFilter) {
                ForEach(ComposerLibraryFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(session.orderedPanels.isEmpty)

            if session.orderedPanels.isEmpty {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredPanels.isEmpty {
                SubtleStageHint(
                    title: "No panels match this filter",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            } else {
                List(selection: panelSelectionBinding) {
                    ForEach(filteredPanels) { panel in
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
                .listRowSeparator(.hidden)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var filteredPanels: [ComposerPanelPayload] {
        libraryFilter.filteredPanels(session.orderedPanels)
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
                size: CGSize(width: 70, height: 54),
                cornerRadius: 10
            )
            .frame(width: 70, height: 54)
            .opacity(panel.hidden ? 0.45 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 10))
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
                    cornerRadius: 12
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

                    Text(panel.hidden ? "Library" : "Placed")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(panel.hidden ? Color.secondary : Color.green)

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
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fileName: String {
        URL(fileURLWithPath: panel.filePath).lastPathComponent
    }
    private var kindSymbol: String {
        panel.kind == "graph" ? "chart.xyaxis.line" : "photo"
    }
}
