import SwiftUI

struct CleanupExportView: View {
    let session: DataCleanupSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let comparisonExport = session.comparisonExportResponse {
                GroupBox("Comparison Export") {
                    VStack(alignment: .leading, spacing: 12) {
                        KeyValueGrid(values: [
                            ("Bundle directory", comparisonExport.bundleDir),
                            ("Workbook", comparisonExport.comparisonWorkbookPath),
                            ("Outputs", "\(comparisonExport.figureOutputs.count)"),
                            (
                                "Figure format",
                                session.selectedComparisonFigureItem?.url.pathExtension.uppercased() ?? "PDF"
                            ),
                        ])

                        HStack(spacing: 10) {
                            Button("Reveal in Finder") {
                                session.revealLatestExport()
                            }
                            .buttonStyle(.bordered)

                            Button("Open in Plot") {
                                session.openPrimaryWorkbookInPlot()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if !session.comparisonFigureItems.isEmpty {
                            Picker("Figure Preview", selection: previewSelectionBinding) {
                                ForEach(session.comparisonFigureItems) { item in
                                    Text(item.label).tag(item.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 320, alignment: .leading)

                            if let figure = session.selectedComparisonFigureItem {
                                exportPreview(for: figure)
                                    .frame(minHeight: 320)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            } else {
                EmptyStateCard(
                    title: "No comparison bundle exported yet",
                    message: "Export the comparison bundle first to generate the workbook plus editable PDF or 300 dpi TIFF figures, or hand the current prepared workbook into Plot."
                )
            }

            if !session.preparedWorkbooks.isEmpty {
                Button("Open in Plot") {
                    session.openPrimaryWorkbookInPlot()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var previewSelectionBinding: Binding<String> {
        Binding(
            get: { session.selectedComparisonFigureItem?.id ?? "" },
            set: { session.selectComparisonFigure(id: $0) }
        )
    }

    @ViewBuilder
    private func exportPreview(for figure: CleanupExportFigureItem) -> some View {
        if figure.url.pathExtension.lowercased() == "pdf" {
            PDFPreviewView(url: figure.url)
                .background(.quinary.opacity(0.2), in: RoundedRectangle(cornerRadius: 18))
        } else {
            QuickLookThumbnailView(url: figure.url, size: 440)
        }
    }
}
