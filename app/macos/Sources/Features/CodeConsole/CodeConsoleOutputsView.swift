import Foundation
import SwiftUI

struct CodeConsoleOutputsView: View {
    @Bindable var session: CodeConsoleSession
    var quickLookThumbnailModel: QuickLookThumbnailModel? = nil
    var quickLookLoadsOnAppear = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Outputs")
                .font(.headline)

            if session.isRunning {
                BusyStateCard(title: "Running Code Console")
            } else if let run = session.latestRunResponse {
                summaryGrid(run: run)

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
                EmptyStateCard(title: "No run output")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quinary.opacity(0.25), in: RoundedRectangle(cornerRadius: 18))
    }

    private func summaryGrid(run: CodeConsoleRunResponse) -> some View {
        KeyValueGrid(
            values: [
                ("Status", run.status.capitalized),
                ("Exit code", run.exitCode.map(String.init) ?? "n/a"),
                ("Duration", String(format: "%.2fs", run.durationSeconds)),
                ("Generated files", "\(run.generatedFiles.count)"),
            ]
        )
    }

    private func generatedFilesSection(run: CodeConsoleRunResponse) -> some View {
        let presentation = session.outputsPresentation

        return VStack(alignment: .leading, spacing: 10) {
            Text("Generated Files")
                .font(.headline)

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
                        .padding(10)
                        .background(
                            (session.selectedGeneratedFile?.path == item.path
                                ? AnyShapeStyle(.quinary.opacity(0.32))
                                : AnyShapeStyle(.quinary.opacity(0.15))),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
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
                .font(.headline)

            if let selectedGeneratedFile = session.selectedGeneratedFile,
               let selectedGeneratedFileURL = session.selectedGeneratedFileURL
            {
                previewContent(for: selectedGeneratedFile, url: selectedGeneratedFileURL)
            } else {
                EmptyStateCard(title: "No preview selected")
            }
        }
    }

    @ViewBuilder
    private func previewContent(
        for file: CodeConsoleGeneratedFileResponse,
        url: URL
    ) -> some View {
        if !FileManager.default.fileExists(atPath: url.path) {
            EmptyStateCard(
                title: "Preview unavailable",
                message: "The selected generated file could not be found on disk."
            )
        } else if file.fileType.caseInsensitiveCompare("pdf") == .orderedSame {
            let previewShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            PDFPreviewView(url: url)
                .clipShape(previewShape)
                .background(.quinary.opacity(0.2), in: previewShape)
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
                .font(.headline)

            ScrollView {
                Text(text.isEmpty ? "No output." : text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(minHeight: 90, maxHeight: 140)
            .padding(10)
            .background(.quinary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
