import Foundation
import SwiftUI

struct CodeConsoleOutputsView: View {
    @Bindable var session: CodeConsoleSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Outputs")
                    .font(.headline)
                Spacer()
                if session.latestRunResponse != nil {
                    Button("Reveal Output Folder") {
                        session.revealManagedOutputFolder()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text(session.outputsSummary)
                .foregroundStyle(.secondary)

            if session.isRunning {
                BusyStateCard(
                    title: "Running Code Console",
                    message: "SciPlot God is executing the pasted Python in the repo-native runner."
                )
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
                EmptyStateCard(
                    title: "No run output yet",
                    message: "Copy the prompt, paste the returned Python, then run the script to review logs and generated files here."
                )
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Generated Files")
                .font(.headline)

            if run.generatedFiles.isEmpty {
                Text("The script finished without writing anything to `OUTPUT_DIR`.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(run.generatedFiles) { item in
                    Button {
                        session.selectGeneratedFile(path: item.path)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(item.fileType.uppercased()) · \(ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

                    Button("Reveal") {
                        session.revealSelectedGeneratedFile()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var generatedPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.headline)

            if let selectedGeneratedFileURL = session.selectedGeneratedFileURL {
                QuickLookThumbnailView(url: selectedGeneratedFileURL, size: 360)
            } else {
                EmptyStateCard(
                    title: "No preview selected",
                    message: "Choose a generated file to inspect its preview."
                )
            }
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
