import SwiftUI

struct ComposerInspectorView: View {
    @Bindable var session: ComposerSession

    var body: some View {
        Form {
            selectionSection
            editSection
            exportActionsSection
            previewSection
        }
        .formStyle(.grouped)
        .inspectorSurface()
    }

    @ViewBuilder
    private var selectionSection: some View {
        Section("Selection") {
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
            }

        }
    }

    @ViewBuilder
    private var editSection: some View {
        Section("Edit") {
            let presentation = session.editPresentation

            if let selection = session.selectedCellSelection, selection.cellCount > 1 {
                AdaptiveInspectorTextRow(title: "Merge", value: "\(selection.colSpan)x\(selection.rowSpan)")

                InspectorActionStack {
                    Button("Merge Selected Cells") {
                        session.mergeSelectedCells()
                    }
                    .buttonStyle(.borderedProminent)
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
                    .buttonStyle(.borderedProminent)
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

            if session.shouldShowPlacementAction {
                InspectorActionStack {
                    Button(session.placementActionTitle) {
                        session.placeFocusedPanelInSelectedTarget()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!presentation.placementAvailability.isEnabled)
                    .help(
                        presentation.placementAvailability.reason
                            ?? "Place the focused panel into the selected target."
                    )
                    .inspectorActionButton()
                }
            }

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

                if !panel.hidden {
                    InspectorActionStack {
                        Button("Remove From Board") {
                            session.removeSelectedPanelFromBoard()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!presentation.removeSelectedPanelAvailability.isEnabled)
                        .help(
                            presentation.removeSelectedPanelAvailability.reason
                                ?? "Remove the selected panel from the board while keeping it in the asset rail."
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
            }

            if session.selectedCellSelection != nil || session.selectedFreeRegion != nil || session.selectedPanel != nil {
                InspectorActionStack {
                    Button("Clear Selection") {
                        session.clearTransientEditingState()
                    }
                    .buttonStyle(.bordered)
                    .inspectorActionButton()
                }
            } else {
                InspectorEmptyState(message: "No edit target")
            }
        }
    }

    @ViewBuilder
    private var exportActionsSection: some View {
        Section("Actions") {
            InspectorActionStack {
                Button("Export") {
                    Task { await session.exportComposition() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.exportAvailability.isEnabled)
                .help(
                    session.exportAvailability.reason
                        ?? "Export the current composition as PDF or 300 dpi TIFF."
                )
                .inspectorActionButton()
            }

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
        Section("Preview") {
            if session.isPreviewing {
                BusyStateCard(title: "Rendering preview")
                .frame(height: 180)
            } else if let preview = session.previewResponse {
                Base64PreviewImageView(base64PNG: preview.pngBase64)
                    .frame(height: 200)
            } else {
                InspectorEmptyState(message: "No preview")
            }

            if session.isExporting {
                ProgressView()
                    .controlSize(.small)
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
