import SwiftUI

struct DataStudioPreviewWorkspaceView: View {
    @Bindable var session: DataStudioSession
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        VStack(spacing: ProWorkspaceMetrics.panelSpacing) {
            previewStage

            if let focusedWorkbook = session.focusedWorkbook {
                DataStudioFocusedWorkbookStrip(session: session, workbook: focusedWorkbook)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var previewStage: some View {
        ZStack(alignment: .top) {
            stageContent

            if let warning = session.previewWarning {
                DataStudioInlinePreviewBanner(message: warning, stale: session.isPreviewStale) {
                    session.retryPreviewRefresh()
                }
                .frame(maxWidth: 640)
                .padding(.top, 18)
                .padding(.horizontal, 28)
            }

            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var stageContent: some View {
        if session.orderedGroups.isEmpty {
            emptyStage(title: "No workbook groups", systemImage: "tablecells")
        } else if session.includedGroups.isEmpty {
            emptyStage(title: "No included groups", systemImage: "checklist")
        } else {
            PlotRefineView(session: session.plotSession)
        }
    }

    private func emptyStage(title: String, systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous)
                .fill(theme.previewSurround)

            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

struct DataStudioFocusedWorkbookStrip: View {
    @Bindable var session: DataStudioSession
    let workbook: DataStudioWorkbookItem
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Focused Group")
                    .font(.headline)
                Spacer()
                DataStudioSpecimenFilterPrimaryTrigger(session: session, workbook: workbook)
            }

            if !displayedMetrics.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    ForEach(Array(displayedMetrics.prefix(3)), id: \.id) { metric in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(metric.unit.isEmpty ? metric.label : "\(metric.label) (\(metric.unit))")
                                .font(.subheadline.weight(.semibold))
                            Text(metric.mean?.formatted(.number.precision(.fractionLength(2))) ?? "n/a")
                                .font(.title3.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }
            }

            if !notices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(notices.prefix(3))) { notice in
                        Label(notice.message, systemImage: notice.style.systemImage)
                            .font(.footnote)
                            .foregroundStyle(notice.style == .warning ? .orange : .secondary)
                    }
                }
            }
        }
        .padding(14)
        .proGlassPanel(theme: theme, cornerRadius: ProWorkspaceMetrics.outerCornerRadius)
    }

    private var displayedMetrics: [DataStudioMetricSummaryResponse] {
        session.displayedMetrics(for: workbook)
    }

    private var notices: [DataStudioFocusedWorkbookNotice] {
        session.focusedWorkbookNotices(for: workbook)
    }
}

struct DataStudioInlinePreviewBanner: View {
    let message: String
    let stale: Bool
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(stale ? .orange : .yellow)

            Text(message)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 12)

            Button("Retry Preview", action: retry)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background((stale ? Color.orange : Color.yellow).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder((stale ? Color.orange : Color.yellow).opacity(0.16), lineWidth: 1)
        )
    }
}
