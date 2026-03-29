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
                LabeledContent("Type", value: "Merged free region")
                LabeledContent("Span", value: "\(region.colSpan)x\(region.rowSpan)")
                LabeledContent("Coverage", value: session.regionSummary(region))
            } else if let selection = session.selectedCellSelection {
                LabeledContent("Type", value: selection.cellCount > 1 ? "Cell selection" : "Single cell")
                LabeledContent("Cells", value: "\(selection.cellCount)")
                LabeledContent("Span", value: "\(selection.colSpan)x\(selection.rowSpan)")
                LabeledContent("Coverage", value: cellSelectionSummary(selection))
            } else if let panel = session.selectedPanel {
                LabeledContent("Type", value: panel.kind == "graph" ? "Graph panel" : "Asset panel")
                LabeledContent("Placement", value: session.placementSummary(for: panel))
                LabeledContent("File", value: URL(fileURLWithPath: panel.filePath).lastPathComponent)
            } else {
                Text("Select cells, a merged region, or a placed panel to edit the composition.")
                    .foregroundStyle(.secondary)
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

                Button("Clear Selection") {
                    session.clearTransientEditingState()
                }
                .buttonStyle(.bordered)
            } else if let panel = session.selectedPanel {
                ComposerPanelThumbnailView(
                    url: URL(fileURLWithPath: panel.filePath),
                    size: CGSize(width: 260, height: 160),
                    cornerRadius: 18
                )
                .frame(height: 160)

                Toggle(
                    "Hidden",
                    isOn: Binding(
                        get: { panel.hidden },
                        set: { session.updateSelectedPanel(hidden: $0) }
                    )
                )

                Toggle(
                    "Locked",
                    isOn: Binding(
                        get: { panel.locked },
                        set: { session.updateSelectedPanel(locked: $0) }
                    )
                )

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

                    if !session.resolvedLabel(for: panel).isEmpty {
                        LabeledContent("Resolved Label", value: session.resolvedLabel(for: panel))
                    }
                } else if panel.regionID != nil {
                    Button("Release From Region") {
                        session.releaseFocusedAssetFromRegion()
                    }
                    .buttonStyle(.bordered)
                }

                Text(session.placementGuidance)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Replace") {
                        session.beginReplacingSelectedPanel()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(panel.locked)

                    Button("Clear Selection") {
                        session.clearTransientEditingState()
                    }
                    .buttonStyle(.bordered)
                }

                Button(session.placementActionTitle) {
                    session.placeFocusedPanelInSelectedTarget()
                }
                .buttonStyle(.bordered)
                .disabled(!session.canPlaceFocusedPanelInSelectedTarget)
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
                .frame(height: 200)
            } else if let preview = session.previewResponse {
                Base64PreviewImageView(base64PNG: preview.pngBase64)
                    .frame(height: 220)

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
                Label("Exporting final PDF…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            } else {
                Text("Use the top-right Export action to write the final composition PDF.")
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
