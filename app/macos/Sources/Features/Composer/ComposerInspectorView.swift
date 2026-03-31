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
    }

    @ViewBuilder
    private var selectionSection: some View {
        Section("Selection") {
            if let region = session.selectedFreeRegion {
                LabeledContent("Target", value: "Merged free region")
                LabeledContent("Span", value: "\(region.colSpan)x\(region.rowSpan)")
                LabeledContent("Coverage", value: session.regionSummary(region))
            } else if let selection = session.selectedCellSelection {
                LabeledContent("Target", value: selection.cellCount > 1 ? "Cell selection" : "Single cell")
                LabeledContent("Cells", value: "\(selection.cellCount)")
                LabeledContent("Span", value: "\(selection.colSpan)x\(selection.rowSpan)")
                LabeledContent("Coverage", value: cellSelectionSummary(selection))
            } else if session.selectedPanel == nil {
                Text("Select cells, a merged region, or a placed panel to edit the composition.")
                    .foregroundStyle(.secondary)
            }

            if let panel = session.selectedPanel {
                if session.selectedCellSelection != nil || session.selectedFreeRegion != nil {
                    Divider()
                }
                LabeledContent("Panel", value: panel.kind == "graph" ? "Graph" : "Asset")
                LabeledContent("Placement", value: session.placementSummary(for: panel))
                LabeledContent("File", value: URL(fileURLWithPath: panel.filePath).lastPathComponent)

                if panel.kind == "graph", !session.resolvedLabel(for: panel).isEmpty {
                    LabeledContent("Label", value: session.resolvedLabel(for: panel))
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
        Section("Actions") {
            if let selection = session.selectedCellSelection, selection.cellCount > 1 {
                LabeledContent("Merge", value: "\(selection.colSpan)x\(selection.rowSpan)")

                Text(session.mergeGuidance)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Merge Selected Cells") {
                    session.mergeSelectedCells()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.canMergeSelectedCells)

                Button("Clear Selection") {
                    session.clearTransientEditingState()
                }
                .buttonStyle(.bordered)
            } else if session.selectedFreeRegion != nil {
                Button("Unmerge Region") {
                    session.unmergeSelectedRegion()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.canUnmergeSelectedRegion)

                if session.canPlaceFocusedPanelInSelectedTarget {
                    Button(session.placementActionTitle) {
                        session.placeFocusedPanelInSelectedTarget()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Clear Selection") {
                    session.clearTransientEditingState()
                }
                .buttonStyle(.bordered)
            }

            if session.canPlaceFocusedPanelInSelectedTarget {
                Button(session.placementActionTitle) {
                    session.placeFocusedPanelInSelectedTarget()
                }
                .buttonStyle(.borderedProminent)
            }

            if let panel = session.selectedPanel {
                Toggle(
                    "Locked",
                    isOn: Binding(
                        get: { panel.locked },
                        set: { session.updateSelectedPanel(locked: $0) }
                    )
                )

                if !panel.hidden {
                    Button("Remove From Board") {
                        session.removeSelectedPanelFromBoard()
                    }
                    .buttonStyle(.bordered)
                    .disabled(panel.locked)
                }

                if panel.kind == "graph" {
                    Toggle(
                        "Auto Figure Labels",
                        isOn: Binding(
                            get: { session.project.autoLabels },
                            set: { session.setAutoLabels($0) }
                        )
                    )

                    TextField(
                        "Manual Label",
                        text: Binding(
                            get: { panel.label ?? "" },
                            set: { session.updateSelectedPanel(label: $0) }
                        )
                    )
                    .disabled(session.project.autoLabels)
                }
            }

            if session.selectedCellSelection != nil || session.selectedFreeRegion != nil || session.selectedPanel != nil {
                Text(session.placementGuidance)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Clear Selection") {
                    session.clearTransientEditingState()
                }
                .buttonStyle(.bordered)
            } else {
                Text("The current selection controls what actions appear here.")
                    .foregroundStyle(.secondary)
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
                Text("Preview updates automatically as you merge, place, label, and reorder panels.")
                    .foregroundStyle(.secondary)
            }

            if session.isExporting {
                Label("Exporting composition…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            } else {
                Text("Use Export to save the composition as PDF or TIFF with an explicit destination and file name.")
                    .foregroundStyle(.secondary)
            }

            if let exportURL = session.exportURL {
                LabeledContent("Latest Export", value: exportURL.lastPathComponent)
                LabeledContent("Folder", value: exportURL.deletingLastPathComponent().lastPathComponent)

                Button("Reveal In Finder") {
                    session.revealLatestExport()
                }
                .buttonStyle(.bordered)
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
