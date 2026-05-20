import SwiftUI

struct ComposerInspectorView: View {
    @Bindable var session: ComposerSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                selectionSection
                placementSection
                panelSection
                actionsSection
                previewSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .inspectorSurface()
    }

    @ViewBuilder
    private var selectionSection: some View {
        InspectorSection(title: "Selection") {
            if let region = session.selectedFreeRegion {
                AdaptiveInspectorTextRow(title: "Target", value: session.regionSummary(region))
                AdaptiveInspectorTextRow(title: "Span", value: "\(region.colSpan)x\(region.rowSpan)")
            } else if let selection = session.selectedCellSelection {
                AdaptiveInspectorTextRow(
                    title: "Target",
                    value: selection.cellCount > 1 ? "Cell selection" : "Single cell"
                )
                AdaptiveInspectorTextRow(title: "Cells", value: "\(selection.cellCount)")
                AdaptiveInspectorTextRow(title: "Span", value: "\(selection.colSpan)x\(selection.rowSpan)")
                AdaptiveInspectorTextRow(title: "Range", value: cellSelectionSummary(selection))
            } else if session.selectedPanel == nil {
                InspectorEmptyState(message: "No selection")
            }

            if let panel = session.selectedPanel {
                if session.selectedCellSelection != nil || session.selectedFreeRegion != nil {
                    Divider()
                }
                AdaptiveInspectorTextRow(title: "Panel", value: panel.kind == "graph" ? "Graph" : "Asset")
                AdaptiveInspectorTextRow(title: "Placement", value: session.placementSummary(for: panel))
                AdaptiveInspectorTextRow(
                    title: "File",
                    value: URL(fileURLWithPath: panel.filePath).lastPathComponent,
                    selectable: true
                )

                if panel.kind == "graph", !session.resolvedLabel(for: panel).isEmpty {
                    AdaptiveInspectorTextRow(title: "Label", value: session.resolvedLabel(for: panel))
                }

                if let assetRef = panel.assetRef {
                    Divider()
                    AdaptiveInspectorTextRow(title: "Linked Source", value: assetRef.label, selectable: true)
                    AdaptiveInspectorTextRow(title: "Artifact", value: assetRef.kind.capitalized)
                    AdaptiveInspectorTextRow(
                        title: "Status",
                        value: assetRef.preflightStatus.replacingOccurrences(of: "_", with: " ").capitalized
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var placementSection: some View {
        InspectorSection(title: "Placement") {
            let presentation = session.editPresentation
            let hasPlacementTarget = session.selectedCellSelection != nil || session.selectedFreeRegion != nil || session.shouldShowPlacementAction

            if let selection = session.selectedCellSelection, selection.cellCount > 1 {
                AdaptiveInspectorTextRow(title: "Merge", value: "\(selection.colSpan)x\(selection.rowSpan)")

                InspectorActionStack {
                    Button("Merge Selected Cells") {
                        session.mergeSelectedCells()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.mergeSelectedCellsAvailability.isEnabled)
                    .help(
                        presentation.mergeSelectedCellsAvailability.reason
                            ?? "Merge the selected empty cells into one free region."
                    )
                    .inspectorActionButton()
                }
            } else if session.selectedFreeRegion != nil {
                InspectorActionStack {
                    Button("Unmerge Region") {
                        session.unmergeSelectedRegion()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.unmergeSelectedRegionAvailability.isEnabled)
                    .help(
                        presentation.unmergeSelectedRegionAvailability.reason
                            ?? "Return the selected free region back to its underlying grid cells."
                    )
                    .inspectorActionButton()

                    if session.shouldShowPlacementAction {
                        Button(session.placementActionTitle) {
                            session.placeFocusedPanelInSelectedTarget()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!presentation.placementAvailability.isEnabled)
                        .help(
                            presentation.placementAvailability.reason
                                ?? "Place the focused panel into the selected target."
                        )
                        .inspectorActionButton()
                    }
                }
            }

            if session.shouldShowPlacementAction && session.selectedFreeRegion == nil {
                InspectorActionStack {
                    Button(session.placementActionTitle) {
                        session.placeFocusedPanelInSelectedTarget()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.placementAvailability.isEnabled)
                    .help(
                        presentation.placementAvailability.reason
                            ?? "Place the focused panel into the selected target."
                    )
                    .inspectorActionButton()
                }
            }

            if session.selectedCellSelection != nil || session.selectedFreeRegion != nil || session.selectedPanel != nil {
                InspectorActionStack {
                    Button("Clear Selection") {
                        session.clearTransientEditingState()
                    }
                    .buttonStyle(.bordered)
                    .inspectorActionButton()
                }
            }

            if !hasPlacementTarget {
                InspectorEmptyState(message: "No placement target")
            }
        }
    }

    @ViewBuilder
    private var panelSection: some View {
        InspectorSection(title: "Panel") {
            let presentation = session.editPresentation

            if let panel = session.selectedPanel {
                AdaptiveInspectorControlRow(title: "Locked") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { panel.locked },
                            set: { session.updateSelectedPanel(locked: $0) }
                        )
                    )
                    .labelsHidden()
                }

                AdaptiveInspectorControlRow(title: "Visible") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { !panel.hidden },
                            set: { session.updateSelectedPanel(hidden: !$0) }
                        )
                    )
                    .labelsHidden()
                }

                if !panel.hidden {
                    InspectorActionStack {
                        Button("Remove From Board") {
                            session.removeSelectedPanelFromBoard()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!presentation.removeSelectedPanelAvailability.isEnabled)
                        .help(
                            presentation.removeSelectedPanelAvailability.reason
                                ?? "Remove the selected panel from the board while keeping it in the library."
                        )
                        .inspectorActionButton()
                    }
                }

                if panel.kind == "graph" {
                    AdaptiveInspectorControlRow(title: "Auto Labels") {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { session.project.autoLabels },
                                set: { session.setAutoLabels($0) }
                            )
                        )
                        .labelsHidden()
                    }

                    AdaptiveInspectorControlRow(title: "Label") {
                        TextField(
                            "Manual Label",
                            text: Binding(
                                get: { panel.label ?? "" },
                                set: { session.updateSelectedPanel(label: $0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .disabled(!presentation.manualLabelAvailability.isEnabled)
                        .help(
                            presentation.manualLabelAvailability.reason
                                ?? "Enter a manual label for the selected graph panel."
                        )
                    }
                }
            } else {
                InspectorEmptyState(message: "No panel selected")
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        InspectorSection(title: "Actions") {
            DisclosureGroup("Advanced") {
                InspectorActionStack {
                    Button("Reveal Output") {
                        session.revealLatestExport()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!session.revealOutputAvailability.isEnabled)
                    .help(
                        session.revealOutputAvailability.reason
                            ?? "Reveal the latest exported composition in Finder."
                    )
                    .inspectorActionButton()
                }

                LatestExportList(
                    items: session.latestExportItems,
                    openButtonTitle: { "Open \($0.label)" },
                    openButtonHelp: { "Open the exported composition file \($0.label)." },
                    openAction: { session.openLatestExport(id: $0.id) }
                )
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        InspectorSection(title: "Preview") {
            ComposerInspectorPreviewContent(session: session)

            if session.isExporting {
                ProgressView()
                    .controlSize(.small)
            }
            if let preflight = session.previewResponse?.exportPreflight, preflight.status != "ready" {
                Divider()
                AdaptiveInspectorTextRow(
                    title: "Preflight",
                    value: preflight.status.replacingOccurrences(of: "_", with: " ").capitalized
                )
                ForEach(preflight.diagnostics.prefix(3)) { diagnostic in
                    Text(diagnostic.message)
                        .font(.caption)
                        .foregroundStyle(diagnostic.severity == "critical" ? .red : .secondary)
                }
            }
        }
    }

    private func cellSelectionSummary(_ selection: ComposerCellSelection) -> String {
        if selection.cellCount == 1 {
            return session.cellDisplayLabel(selection.origin)
        }

        let trailingCell = ComposerGridCell(
            col: selection.origin.col + selection.colSpan - 1,
            row: selection.origin.row + selection.rowSpan - 1
        )
        return "\(session.cellDisplayLabel(selection.origin))-\(session.cellDisplayLabel(trailingCell))"
    }
}

private struct ComposerInspectorPreviewContent: View {
    @Bindable var session: ComposerSession

    var body: some View {
        Group {
            if session.isPreviewing {
                BusyStateCard(title: "Rendering preview")
                    .frame(height: 180)
            } else if let preview = session.previewResponse {
                Base64PreviewImageView(base64PNG: preview.pngBase64)
                    .frame(height: 200)
            } else {
                SubtleStageHint(title: "Select or place a panel to preview", alignment: .leading)
                    .frame(height: 96)
            }
        }
    }
}
