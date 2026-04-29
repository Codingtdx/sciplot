import SwiftUI

struct DataStudioInspectorView: View {
    @Bindable var session: DataStudioSession
    private let plotOptionsAdvancedExpanded: Bool

    init(session: DataStudioSession, plotOptionsAdvancedExpanded: Bool = false) {
        self.session = session
        self.plotOptionsAdvancedExpanded = plotOptionsAdvancedExpanded
    }

    var body: some View {
        DataStudioPreparationInspectorView(session: session)
    }
}

struct DataStudioPreparationInspectorView: View {
    @Bindable var session: DataStudioSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                figureSection
                actionsSection
                outputsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .inspectorSurface()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous))
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous)
        )
    }

    private var figureSection: some View {
        InspectorSection(title: "Figure") {
            if session.orderedGroups.isEmpty {
                InspectorEmptyState(message: "No figure")
            } else {
                AdaptiveInspectorTextRow(
                    title: "Group",
                    value: session.focusedWorkbook.map { session.displayName(for: $0) } ?? "No focused group"
                )
                AdaptiveInspectorTextRow(
                    title: "Figure",
                    value: session.currentRecipeLabel,
                    secondaryValue: session.currentRecipe == nil
                )
                AdaptiveInspectorTextRow(
                    title: "Groups",
                    value: "\(session.includedGroups.count) included"
                )
            }
        }
    }

    private var actionsSection: some View {
        InspectorSection(title: "Actions") {
            InspectorActionStack {
                Button("Open in Plot") {
                    session.openCurrentFigureInPlot()
                }
                .buttonStyle(.bordered)
                .disabled(!session.canOpenCurrentFigureInPlot)
                .help(
                    session.canOpenCurrentFigureInPlot
                        ? "Open the prepared workbook, sheet, figure type, and current options in Plot."
                        : "Choose a supported figure before opening in Plot."
                )
                .inspectorActionButton()

                Button("Analysis") {
                    session.showAnalysis()
                }
                .buttonStyle(.bordered)
                .disabled(session.focusedWorkbook == nil && session.currentRecipe == nil)
                .help("Open source data and fit analysis for the current Data Studio context.")
                .inspectorActionButton()
            }
        }
    }

    private var outputsSection: some View {
        InspectorSection(title: "Outputs") {
            InspectorActionStack {
                Button("Reveal Workbook") {
                    session.revealFocusedWorkbook()
                }
                .buttonStyle(.bordered)
                .disabled(session.focusedWorkbook == nil)
                .help(
                    session.focusedWorkbook == nil
                        ? "Select a workbook group first."
                        : "Reveal the focused workbook in Finder."
                )
                .inspectorActionButton()

                Button("Reveal Output") {
                    session.revealLatestExport()
                }
                .buttonStyle(.bordered)
                .disabled(!session.revealOutputAvailability.isEnabled)
                .help(session.revealOutputAvailability.reason ?? "Reveal the latest output location in Finder.")
                .inspectorActionButton()
            }

            if session.comparisonExportResponse != nil {
                DisclosureGroup("Latest Export") {
                    InspectorActionStack {
                        Button("Open Comparison Workbook") {
                            session.openLatestComparisonWorkbook()
                        }
                        .buttonStyle(.bordered)
                        .disabled(session.latestComparisonWorkbookURL == nil)
                        .help(
                            session.latestComparisonWorkbookURL == nil
                                ? "Export a bundle first."
                                : "Open the latest exported comparison workbook."
                        )
                        .inspectorActionButton()

                        ForEach(session.comparisonFilteredWorkbookItems) { item in
                            Button("Open \(item.response.label) Workbook") {
                                session.openFilteredWorkbook(id: item.id)
                            }
                            .buttonStyle(.bordered)
                            .help("Open the filtered workbook for \(item.response.label).")
                            .inspectorActionButton()
                        }

                        ForEach(session.comparisonFigureItems) { item in
                            Button("Open \(item.response.label)") {
                                session.selectComparisonFigure(id: item.id)
                                session.openSelectedComparisonFigure()
                            }
                            .buttonStyle(.bordered)
                            .help("Open the exported figure file for \(item.response.label).")
                            .inspectorActionButton()
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
    }
}
