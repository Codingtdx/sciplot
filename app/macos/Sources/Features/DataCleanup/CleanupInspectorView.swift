import SwiftUI

struct CleanupInspectorView: View {
    let session: DataCleanupSession

    var body: some View {
        Form {
            contextSection
            reviewSection
            compareExportSection
            handoffOutputSection
        }
        .formStyle(.grouped)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var contextSection: some View {
        Section("Context") {
            LabeledContent("Stage", value: session.stage.title)
            LabeledContent("Raw inputs", value: "\(session.rawInputURLs.count)")
            LabeledContent("Prepared", value: "\(session.preparedWorkbooks.count)")

            if let focusedWorkbook = session.focusedWorkbook {
                LabeledContent("Focused", value: focusedWorkbook.url.lastPathComponent)
                LabeledContent("Sheet", value: focusedWorkbook.preferredSheet.displayName)
                LabeledContent("Warnings", value: "\(focusedWorkbook.warnings.count)")
            }

            if let primaryWorkbook = session.primaryWorkbook {
                LabeledContent("Primary", value: primaryWorkbook.url.lastPathComponent)
            }

            if let errorMessage = session.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
    }

    private var reviewSection: some View {
        Section("Review") {
            Button("Refresh Preview") {
                Task { await session.refreshFocusedReview() }
            }
            .disabled(!session.canRefreshFocusedReview)

            Button("Set as Primary") {
                session.setFocusedWorkbookAsPrimary()
            }
            .disabled(!session.canSetFocusedAsPrimary)

            Button("Remove Workbook", role: .destructive) {
                session.removeFocusedWorkbook()
            }
            .disabled(!session.canRemoveFocusedWorkbook)
        }
    }

    private var compareExportSection: some View {
        Section("Compare / Export") {
            Button("Export Comparison Bundle") {
                Task { await session.exportComparisonBundle() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.canExportComparison)

            if let comparisonExportResponse = session.comparisonExportResponse {
                LabeledContent("Outputs", value: "\(comparisonExportResponse.figureOutputs.count)")
                LabeledContent("Format", value: session.selectedComparisonFigureFormatLabel)

                if !session.comparisonFigureItems.isEmpty {
                    Picker("Figure", selection: selectedFigureBinding) {
                        ForEach(session.comparisonFigureItems) { item in
                            Text(item.label).tag(item.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var handoffOutputSection: some View {
        Section("Handoff / Output") {
            Button("Open in Plot") {
                session.openPrimaryWorkbookInPlot()
            }
            .disabled(!session.canOpenInPlot)

            Button("Open Selected Figure") {
                session.openSelectedComparisonFigure()
            }
            .disabled(!session.canOpenSelectedComparisonFigure)

            Button("Reveal Bundle") {
                session.revealLatestExport()
            }
            .disabled(!session.canRevealLatestExport)

            if let comparisonExportResponse = session.comparisonExportResponse {
                LabeledContent(
                    "Bundle",
                    value: session.comparisonExportDestinationURL?.path ?? comparisonExportResponse.bundleDir
                )
                LabeledContent(
                    "Workbook",
                    value: URL(fileURLWithPath: comparisonExportResponse.comparisonWorkbookPath).lastPathComponent
                )
            } else if let primaryWorkbookURL = session.primaryWorkbookURL {
                LabeledContent("Workbook", value: primaryWorkbookURL.lastPathComponent)
            }
        }
    }

    private var selectedFigureBinding: Binding<String> {
        Binding(
            get: { session.selectedComparisonFigureItem?.id ?? "" },
            set: { session.selectComparisonFigure(id: $0) }
        )
    }
}
