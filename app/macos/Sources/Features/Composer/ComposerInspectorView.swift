import SwiftUI

struct ComposerInspectorView: View {
    @Bindable var session: ComposerSession

    var body: some View {
        Form {
            selectionSection
            actionsSection
            previewAndExportSection
        }
        .formStyle(.grouped)
        .inspectorSurface()
    }

    @ViewBuilder
    private var selectionSection: some View {
        Section("Selection") {
            if let region = session.selectedFreeRegion {
                AdaptiveInspectorTextRow(title: "Target", value: "Merged free region")
                AdaptiveInspectorTextRow(title: "Span", value: "\(region.colSpan)x\(region.rowSpan)")
                AdaptiveInspectorTextRow(title: "Coverage", value: session.regionSummary(region))
            } else if let selection = session.selectedCellSelection {
                AdaptiveInspectorTextRow(
                    title: "Target",
                    value: selection.cellCount > 1 ? "Cell selection" : "Single cell"
                )
                AdaptiveInspectorTextRow(title: "Cells", value: "\(selection.cellCount)")
                AdaptiveInspectorTextRow(title: "Span", value: "\(selection.colSpan)x\(selection.rowSpan)")
                AdaptiveInspectorTextRow(title: "Coverage", value: cellSelectionSummary(selection))
            } else if session.selectedPanel == nil {
                InspectorEmptyState(message: "Select cells or a panel to edit.")
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

            if let errorMessage = session.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section("Edit") {
            if let selection = session.selectedCellSelection, selection.cellCount > 1 {
                AdaptiveInspectorTextRow(title: "Merge", value: "\(selection.colSpan)x\(selection.rowSpan)")

                InspectorActionStack {
                    Button("Merge Selected Cells") {
                        session.mergeSelectedCells()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canMergeSelectedCells)
                    .inspectorActionButton()
                }
            } else if session.selectedFreeRegion != nil {
                InspectorActionStack {
                    Button("Unmerge Region") {
                        session.unmergeSelectedRegion()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canUnmergeSelectedRegion)
                    .inspectorActionButton()

                    if session.canPlaceFocusedPanelInSelectedTarget {
                        Button(session.placementActionTitle) {
                            session.placeFocusedPanelInSelectedTarget()
                        }
                        .buttonStyle(.bordered)
                        .inspectorActionButton()
                    }
                }
            }

            if session.canPlaceFocusedPanelInSelectedTarget {
                InspectorActionStack {
                    Button(session.placementActionTitle) {
                        session.placeFocusedPanelInSelectedTarget()
                    }
                    .buttonStyle(.borderedProminent)
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
                        .disabled(panel.locked)
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
                        .disabled(session.project.autoLabels)
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
                InspectorEmptyState(message: "Select cells or a panel to reveal edit actions.")
            }
        }
    }

    @ViewBuilder
    private var previewAndExportSection: some View {
        Section("Preview & Export") {
            if session.isPreviewing {
                BusyStateCard(
                    title: "Rendering preview",
                    message: "The sidecar is recomposing the current figure."
                )
                .frame(height: 180)
            } else if let preview = session.previewResponse {
                Base64PreviewImageView(base64PNG: preview.pngBase64)
                    .frame(height: 200)

                if let report = preview.submissionReport {
                    Label(
                        report.summary,
                        systemImage: report.readiness == "ready" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(report.readiness == "ready" ? .green : .orange)
                    .font(.footnote)
                }
            } else {
                InspectorEmptyState(message: "Preview updates automatically.")
            }

            if session.isExporting {
                Label("Exporting composition…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            } else {
                InspectorEmptyState(message: "Use Export to write PDF or TIFF output.")
            }

            if let exportURL = session.exportURL {
                AdaptiveInspectorTextRow(title: "Latest Export", value: exportURL.lastPathComponent)
                AdaptiveInspectorTextRow(
                    title: "Folder",
                    value: exportURL.deletingLastPathComponent().path,
                    selectable: true
                )

                InspectorActionStack {
                    Button("Reveal In Finder") {
                        session.revealLatestExport()
                    }
                    .buttonStyle(.bordered)
                    .inspectorActionButton()
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
