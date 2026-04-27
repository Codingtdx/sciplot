import SwiftUI

struct QuickHelpAction: Identifiable {
    let id: String
    let title: String
    let detail: String
}

struct QuickHelpContent {
    let title: String
    let actions: [QuickHelpAction]
}

enum QuickHelpCatalog {
    static func content(for workbench: Workbench) -> QuickHelpContent {
        switch workbench {
        case .plot:
            return QuickHelpContent(
                title: "Plot",
                actions: [
                    .init(id: "plot-import", title: "Import", detail: "Open a source file."),
                    .init(id: "plot-template", title: "Template", detail: "Pick a compatible template."),
                    .init(id: "plot-refine", title: "Refine", detail: "Use Inspector for axes, style, and overlays."),
                    .init(id: "plot-export", title: "Export", detail: "Export PDF or 300 dpi TIFF."),
                ]
            )
        case .dataStudio:
            return QuickHelpContent(
                title: "Data Studio",
                actions: [
                    .init(id: "ds-import", title: "Import", detail: "Build or open workbook groups."),
                    .init(id: "ds-groups", title: "Groups", detail: "Rename, reorder, include, or auto-filter groups."),
                    .init(id: "ds-compare", title: "Compare", detail: "Choose figure family and refine in Inspector."),
                    .init(id: "ds-export", title: "Export", detail: "Export workbook and figure outputs."),
                ]
            )
        case .composer:
            return QuickHelpContent(
                title: "Composer",
                actions: [
                    .init(id: "composer-import", title: "Import", detail: "Import graph PDFs or assets."),
                    .init(id: "composer-layout", title: "Layout", detail: "Place, move, and merge panels on canvas."),
                    .init(id: "composer-inspect", title: "Inspect", detail: "Edit labels, locks, and placement."),
                    .init(id: "composer-export", title: "Export", detail: "Export the composition."),
                ]
            )
        case .codeConsole:
            return QuickHelpContent(
                title: "Code Console",
                actions: [
                    .init(id: "console-bind", title: "Bind", detail: "Choose a dataset and sheet."),
                    .init(id: "console-prompt", title: "Prompt", detail: "Refresh or copy the external AI prompt."),
                    .init(id: "console-run", title: "Run", detail: "Run Python and inspect outputs."),
                    .init(id: "console-export", title: "Export", detail: "Export generated PDF figures."),
                ]
            )
        }
    }
}

struct QuickHelpSheet: View {
    let workbench: Workbench
    let dismiss: () -> Void
    @Environment(\.dismiss) private var dismissSheet

    private var content: QuickHelpContent {
        QuickHelpCatalog.content(for: workbench)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(content.actions) { action in
                        HStack(alignment: .top, spacing: 10) {
                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 92, alignment: .leading)

                            Text(action.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle(content.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismissSheet()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 320)
    }
}
