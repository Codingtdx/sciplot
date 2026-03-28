import SwiftUI

struct PlotRefineView: View {
    let session: PlotSession

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                actionRow

                if session.isPreviewing {
                    BusyStateCard(title: "Rendering preview", message: "The sidecar is generating a preview image for the selected template.")
                } else if let preview = session.previewResponse?.previews.first {
                    Base64PreviewImageView(base64PNG: preview.pngBase64)
                        .frame(minHeight: 420)
                } else {
                    EmptyStateCard(
                        title: "No preview rendered yet",
                        message: "Render the current template selection to inspect the figure inside Plot."
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Preflight") {
                    if session.isRunningPreflight {
                        BusyStateCard(title: "Running preflight", message: "The sidecar is validating the export readiness.")
                    } else if let preflight = session.preflightResponse {
                        VStack(alignment: .leading, spacing: 12) {
                            KeyValueGrid(values: [
                                ("Template", preflight.template),
                                ("Role", preflight.role),
                                ("Lifecycle", preflight.lifecyclePolicy),
                            ])

                            if !preflight.preflight.warnings.isEmpty {
                                warningList(title: "Warnings", items: preflight.preflight.warnings)
                            }
                            if !preflight.preflight.errors.isEmpty {
                                warningList(title: "Blockers", items: preflight.preflight.errors)
                            }
                        }
                        .padding(.top, 8)
                    } else {
                        Text("Run preflight to validate export blockers and warnings inline.")
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Submission Report") {
                    if let report = session.previewResponse?.submissionReport ?? session.exportResponse?.submissionReport {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(report.summary)
                                .font(.headline)
                            KeyValueGrid(values: [
                                ("Readiness", report.readiness),
                                ("Outputs", "\(report.outputCount)"),
                            ])
                        }
                        .padding(.top, 8)
                    } else {
                        Text("Preview or export to see the backend submission report.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let exportResponse = session.exportResponse {
                    GroupBox("Latest Export") {
                        VStack(alignment: .leading, spacing: 12) {
                            KeyValueGrid(values: [
                                ("Output directory", exportResponse.outputDir),
                                ("PDF count", "\(exportResponse.outputs.count)"),
                            ])

                            Button("Reveal Export in Finder") {
                                session.revealLatestExport()
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .frame(width: 320)
        }
        .task(id: session.selectedTemplateID) {
            await session.renderPreviewIfNeeded()
        }
    }

    private var actionRow: some View {
        HStack {
            if let selectedTemplateID = session.selectedTemplateID {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedTemplateID)
                        .font(.headline)
                    Text(session.selectedFileURL?.lastPathComponent ?? "")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Render Preview") {
                Task { await session.renderPreview() }
            }

            Button("Run Preflight") {
                Task { await session.runPreflight() }
            }

            Button("Export") {
                Task { await session.exportCurrentSelection() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isExporting)
        }
    }

    @ViewBuilder
    private func warningList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "exclamationmark.triangle")
            }
        }
    }
}
