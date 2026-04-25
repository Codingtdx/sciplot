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
                    .init(id: "plot-import", title: "Import", detail: "Open a source file from the toolbar or Command menu."),
                    .init(id: "plot-template", title: "Template", detail: "Pick a compatible template from the left gallery rail."),
                    .init(id: "plot-refine", title: "Refine", detail: "Use Inspector for style, axis, legend, and advanced overlays."),
                    .init(id: "plot-export", title: "Export", detail: "Export from toolbar or Inspector Actions as PDF or 300 dpi TIFF."),
                ]
            )
        case .dataStudio:
            return QuickHelpContent(
                title: "Data Studio",
                actions: [
                    .init(id: "ds-import", title: "Import", detail: "Run the native import wizard to build or open workbook groups."),
                    .init(id: "ds-groups", title: "Group Review", detail: "Rename, reorder, include, or auto-filter groups from the left rail."),
                    .init(id: "ds-compare", title: "Compare Preview", detail: "Choose figure family/template and refine from the shared Inspector."),
                    .init(id: "ds-export", title: "Export", detail: "Export bundle outputs from toolbar or Inspector Actions."),
                ]
            )
        case .composer:
            return QuickHelpContent(
                title: "Composer",
                actions: [
                    .init(id: "composer-import", title: "Import", detail: "Import graph PDFs or assets from the toolbar."),
                    .init(id: "composer-layout", title: "Layout", detail: "Select cells or regions, then place, merge, and arrange panels."),
                    .init(id: "composer-inspect", title: "Inspect", detail: "Use Inspector to edit labels, locks, and placement controls."),
                    .init(id: "composer-export", title: "Export", detail: "Export composition from toolbar or Inspector Actions."),
                ]
            )
        case .codeConsole:
            return QuickHelpContent(
                title: "Code Console",
                actions: [
                    .init(id: "console-bind", title: "Bind Context", detail: "Import or select a bound dataset and target sheet."),
                    .init(id: "console-prompt", title: "Prompt And Code", detail: "Refresh/copy prompt, then paste Python into the editor."),
                    .init(id: "console-run", title: "Run", detail: "Run code to generate managed outputs and previews."),
                    .init(id: "console-export", title: "Export", detail: "Export generated PDF figures from toolbar or Inspector Actions."),
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
            List {
                Section("Core Actions") {
                    ForEach(content.actions) { action in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(action.title)
                                .font(.headline)
                            Text(action.detail)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.inset)
            .navigationTitle("\(content.title) Quick Help")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismissSheet()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}
