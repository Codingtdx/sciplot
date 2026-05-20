import Foundation
import SwiftUI

struct CodeConsoleOutputsView: View {
    @Bindable var session: CodeConsoleSession
    var quickLookThumbnailModel: QuickLookThumbnailModel? = nil
    var quickLookLoadsOnAppear = true
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkspaceMetrics.panelSpacing) {
            WorkbenchRailTitle(title: "Outputs")

            if session.isRunning {
                BusyStateCard(title: "Running Code Console")
            } else if let run = session.latestRunResponse {
                summaryGrid(run: run)
                notebookOutputsSection(run: run)

                HStack(alignment: .top, spacing: 18) {
                    generatedFilesSection(run: run)
                        .frame(minWidth: 240, maxWidth: 280, alignment: .topLeading)

                    generatedPreviewSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(minHeight: 220)

                logsSection(title: "Stdout", text: run.stdout)
                logsSection(title: "Stderr", text: run.stderr)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryGrid(run: CodeConsoleRunResponse) -> some View {
        KeyValueGrid(
            values: [
                ("Status", run.status.capitalized),
                ("Exit code", run.exitCode.map(String.init) ?? "n/a"),
                ("Duration", String(format: "%.2fs", run.durationSeconds)),
                ("Generated files", "\(run.generatedFiles.count)"),
                ("Notebook outputs", "\(run.notebookOutputs.count)"),
                ("Artifacts", "\(run.notebookArtifacts.count)"),
            ]
        )
    }

    @ViewBuilder
    private func notebookOutputsSection(run: CodeConsoleRunResponse) -> some View {
        if !run.notebookOutputs.isEmpty || !run.dataContainers.isEmpty || !run.notebookArtifacts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notebook Outputs")
                    .font(.subheadline.weight(.semibold))

                ForEach(run.notebookOutputs) { output in
                    HStack(spacing: 8) {
                        Text(output.label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(output.kind.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(output.status.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if !run.dataContainers.isEmpty {
                    Text("\(run.dataContainers.count) table container\(run.dataContainers.count == 1 ? "" : "s") available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !run.notebookArtifacts.isEmpty {
                    Divider()
                    ForEach(run.notebookArtifacts) { artifact in
                        HStack(spacing: 8) {
                            Text(artifact.label)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(artifact.kind.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(artifact.status.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .proGlassPanel(theme: theme, cornerRadius: ProCornerPolicy.row)
        }
    }

    private func generatedFilesSection(run: CodeConsoleRunResponse) -> some View {
        let presentation = session.outputsPresentation

        return VStack(alignment: .leading, spacing: 10) {
            Text("Generated Files")
                .font(.subheadline.weight(.semibold))

            if run.generatedFiles.isEmpty {
                Text("No generated files")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(run.generatedFiles) { item in
                    Button {
                        session.selectGeneratedFile(path: item.path)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(item.name)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer(minLength: 8)

                            Text("\(item.fileType.uppercased()) · \(ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Button("Open") {
                        session.openSelectedGeneratedFile()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.openSelectedGeneratedFileAvailability.isEnabled)
                    .help(
                        presentation.openSelectedGeneratedFileAvailability.reason
                            ?? "Open the selected generated file."
                    )

                    Button("Reveal") {
                        session.revealSelectedGeneratedFile()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.revealSelectedGeneratedFileAvailability.isEnabled)
                    .help(
                        presentation.revealSelectedGeneratedFileAvailability.reason
                            ?? "Reveal the selected generated file in Finder."
                    )
                }
            }
        }
    }

    private var generatedPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.subheadline.weight(.semibold))

            if let selectedGeneratedFile = session.selectedGeneratedFile,
               let selectedGeneratedFileURL = session.selectedGeneratedFileURL
            {
                previewContent(for: selectedGeneratedFile, url: selectedGeneratedFileURL)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func previewContent(
        for file: CodeConsoleGeneratedFileResponse,
        url: URL
    ) -> some View {
        if !FileManager.default.fileExists(atPath: url.path) {
            SubtleStageHint(title: "Selected output is missing", systemImage: "exclamationmark.triangle")
                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
        } else if file.fileType.caseInsensitiveCompare("pdf") == .orderedSame {
            let previewShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            PDFPreviewView(url: url)
                .clipShape(previewShape)
                .overlay(
                    previewShape
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
        } else {
            QuickLookThumbnailView(
                url: url,
                size: 360,
                model: quickLookThumbnailModel,
                loadsOnAppear: quickLookLoadsOnAppear
            )
        }
    }

    private func logsSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ScrollView {
                Text(text.isEmpty ? "No output." : text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(minHeight: 90, maxHeight: 140)
            .padding(10)
            .proEditorSurface(theme: theme, cornerRadius: ProCornerPolicy.row)
        }
    }
}
