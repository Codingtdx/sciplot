import SwiftUI

struct PlotInspectorView<LeadingSections: View, TrailingSections: View>: View {
    @Bindable var session: PlotSession
    let styleSectionTitle: String
    let adjustmentCategory: PlotAdjustmentCategory?
    let showsPlotInspectorModes: Bool
    private let leadingSections: LeadingSections
    private let trailingSections: TrailingSections
    @State var isPlotOptionsAdvancedExpanded: Bool

    init(
        session: PlotSession,
        styleSectionTitle: String = "Figure",
        adjustmentCategory: PlotAdjustmentCategory? = nil,
        plotOptionsAdvancedExpanded: Bool = false,
        showsPlotInspectorModes: Bool = true,
        @ViewBuilder leadingSections: () -> LeadingSections = { EmptyView() },
        @ViewBuilder trailingSections: () -> TrailingSections = { EmptyView() }
    ) {
        self.session = session
        self.styleSectionTitle = styleSectionTitle
        self.adjustmentCategory = adjustmentCategory
        self.showsPlotInspectorModes = showsPlotInspectorModes
        self.leadingSections = leadingSections()
        self.trailingSections = trailingSections()
        _isPlotOptionsAdvancedExpanded = State(initialValue: plotOptionsAdvancedExpanded)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                leadingSections
                if let adjustmentCategory {
                    adjustmentCategoryContent(adjustmentCategory)
                } else if showsPlotInspectorModes {
                    PlotSelectionInspectorView(session: session) {
                        plotOptionsSection
                        if shouldShowAxesSection {
                            axesSection
                        }
                    } axisContent: {
                        if shouldShowAxesSection {
                            axesSection
                        } else {
                            InspectorSection(title: "Axis") {
                                InspectorEmptyState(message: "Select a plotted axis")
                            }
                        }
                    }
                } else {
                    plotOptionsSection
                    if session.supportsFitOverlayControls {
                        fitOverlaySection
                    }
                    if shouldShowAxesSection {
                        axesSection
                    }
                    if session.shouldShowSeriesLegendControls {
                        seriesSection
                    }
                }
                trailingSections
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .inspectorSurface()
    }

    @ViewBuilder
    private func adjustmentCategoryContent(_ category: PlotAdjustmentCategory) -> some View {
        switch category {
        case .figure:
            figureAdjustmentContent
        case .axes:
            axesAdjustmentContent
        case .legend:
            legendAdjustmentContent
        case .guides:
            guidesAdjustmentContent
        case .fit:
            fitAdjustmentContent
        case .functions:
            functionsAdjustmentContent
        case .annotations:
            annotationsAdjustmentContent
        case .advancedAxes:
            advancedAxesAdjustmentContent
        }
    }


}

extension PlotInspectorView where LeadingSections == EmptyView, TrailingSections == EmptyView {
    init(session: PlotSession, styleSectionTitle: String = "Figure") {
        self.init(
            session: session,
            styleSectionTitle: styleSectionTitle,
            leadingSections: { EmptyView() },
            trailingSections: { EmptyView() }
        )
    }

    init(
        session: PlotSession,
        styleSectionTitle: String = "Figure",
        adjustmentCategory: PlotAdjustmentCategory
    ) {
        self.init(
            session: session,
            styleSectionTitle: styleSectionTitle,
            adjustmentCategory: adjustmentCategory,
            leadingSections: { EmptyView() },
            trailingSections: { EmptyView() }
        )
    }
}

struct PlotAdjustmentObjectRow: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let selection: PlotLayerSelection
}

struct PlotAdjustmentObjectButton: View {
    let row: PlotAdjustmentObjectRow
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: row.systemImage)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(row.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .proGlassRow(theme: theme, isSelected: isSelected, cornerRadius: ProCornerPolicy.smallRow)
    }
}

private struct PlotSelectionInspectorView<FigureContent: View, AxisContent: View>: View {
    @Bindable var session: PlotSession
    let figureContent: FigureContent
    let axisContent: AxisContent

    init(
        session: PlotSession,
        @ViewBuilder figureContent: () -> FigureContent,
        @ViewBuilder axisContent: () -> AxisContent
    ) {
        self.session = session
        self.figureContent = figureContent()
        self.axisContent = axisContent()
    }

    var body: some View {
        switch session.canvasSelection {
        case .figure:
            figureContent
        case .axis:
            axisContent
        case .layer(let layer):
            PlotSelectedLayerEditorView(session: session, selection: layer)
        case .dataPipeline:
            InspectorSection(title: "Data") {
                AdaptiveInspectorTextRow(title: "Pipeline", value: session.dataPipelineSummary.title)
                Button {
                    session.showDataWorkbook(tab: .transformed)
                } label: {
                    Label("Open Workbook", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!session.dataTransformAvailability.isEnabled)
                .help(session.dataTransformAvailability.reason ?? "Open the data pipeline in Data Workbook.")
            }
        }
    }
}
