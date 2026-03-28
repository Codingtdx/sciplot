import Foundation
import Observation

struct CodeConsoleContextItem: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String
    let detail: String
}

@MainActor
@Observable
final class CodeConsoleSession {
    var editorText = """
    # Code Console is present in product scope, but this repository does not yet expose
    # a native runner / prompt sidecar API. This shell intentionally avoids inventing one.
    """
    var boundContext: [CodeConsoleContextItem] = []
    var outputsSummary = "No controlled runner backend is available in the current repository."
    let unavailableReason = "Code Console is a first-class workbench, but the repo does not yet expose the runner/prompt backend APIs needed to execute code here."

    func refreshContext(plot: PlotSession, dataCleanup: DataCleanupSession) {
        var items: [CodeConsoleContextItem] = []

        if let fileURL = plot.selectedFileURL {
            items.append(
                .init(
                    id: "plot-input",
                    label: "Bound dataset",
                    value: fileURL.lastPathComponent,
                    detail: plot.selectedSheet.displayName
                )
            )
        }

        if let templateID = plot.selectedTemplateID {
            items.append(
                .init(
                    id: "plot-template",
                    label: "Plot context",
                    value: templateID,
                    detail: plot.renderOptions.size ?? "Contract default size"
                )
            )
        }

        if let workbookURL = dataCleanup.primaryWorkbookURL {
            items.append(
                .init(
                    id: "cleanup-workbook",
                    label: "Prepared workbook",
                    value: workbookURL.lastPathComponent,
                    detail: dataCleanup.primaryPreferredSheet?.displayName ?? "Representative_Curve"
                )
            )
        }

        boundContext = items
    }
}
