import SwiftUI

struct DataStudioSpecimenFilterPanel: View {
    @Bindable var session: DataStudioSession
    let workbook: DataStudioWorkbookItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Specimen Filter")
                        .font(.headline)
                    Text("Review exclusions for \(workbook.response.label) while keeping the comparison preview visible.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    session.closeSpecimenFilter()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let refreshMessage {
                Label(refreshMessage.message, systemImage: refreshMessage.symbol)
                    .font(.footnote)
                    .foregroundStyle(refreshMessage.tint)
            }

            if let preview = currentPreview {
                if preview.supported {
                    supportedContent(preview: preview)
                } else {
                    unsupported(preview: preview)
                }
            } else {
                VStack {
                    Spacer()
                    ProgressView("Loading specimen preview…")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .background(.quinary.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var currentPreview: DataStudioWorkbookPreviewResponse? {
        guard let preview = session.specimenFilterPreview, preview.workbookPath == workbook.response.workbookPath else {
            return nil
        }
        return preview
    }

    private var refreshMessage: (message: String, symbol: String, tint: Color)? {
        switch session.focusedWorkbookPreviewRefreshState {
        case let .refreshing(workbookPath) where workbookPath == workbook.response.workbookPath:
            return ("Refreshing specimen summary…", "arrow.triangle.2.circlepath", .secondary)
        case let .failed(workbookPath, message) where workbookPath == workbook.response.workbookPath:
            return (message, "exclamationmark.triangle.fill", .orange)
        default:
            return nil
        }
    }

    @ViewBuilder
    private func supportedContent(preview: DataStudioWorkbookPreviewResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DataStudioSpecimenSummaryGrid(preview: preview)

                DataStudioRecommendationCard(
                    session: session,
                    workbookPath: preview.workbookPath,
                    preview: preview
                )

                if !recommendedSpecimens(preview).isEmpty {
                    DataStudioSpecimenSection(
                        title: "Recommended",
                        subtitle: "Suggested high/low exclusions based on the combined Strength / Modulus / Elongation z-score.",
                        specimens: recommendedSpecimens(preview),
                        workbookPath: preview.workbookPath,
                        session: session
                    )
                }

                DataStudioSpecimenSection(
                    title: "All Specimens",
                    subtitle: "Toggle included specimens for representative selection, mean/std, and error bars.",
                    specimens: preview.specimens,
                    workbookPath: preview.workbookPath,
                    session: session
                )

                Text(impactText(for: preview))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func unsupported(preview: DataStudioWorkbookPreviewResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Specimen filter unavailable")
                .font(.headline)
            Text(preview.unsupportedReason)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func recommendedSpecimens(_ preview: DataStudioWorkbookPreviewResponse) -> [DataStudioSpecimenPreviewResponse] {
        preview.specimens.filter { preview.suggestedExclusionIds.contains($0.specimenId) }
    }

    private func impactText(for preview: DataStudioWorkbookPreviewResponse) -> String {
        "Keeping \(preview.includedSpecimenCount) of \(preview.totalSpecimenCount) specimens for mean/std and error bars."
    }
}

private struct DataStudioSpecimenSummaryGrid: View {
    let preview: DataStudioWorkbookPreviewResponse

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 10)], spacing: 10) {
            summaryCard(title: "Included", value: "\(preview.includedSpecimenCount)")
            summaryCard(title: "Excluded", value: "\(preview.excludedSpecimenCount)")
            summaryCard(title: "Resulting Reps", value: "\(preview.includedSpecimenCount)")
        }
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct DataStudioRecommendationCard: View {
    @Bindable var session: DataStudioSession
    let workbookPath: String
    let preview: DataStudioWorkbookPreviewResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recommendation")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(recommendationTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(recommendationSpecimens.isEmpty ? Color.secondary : .orange)
            }

            Text(recommendationMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Apply Recommendation") {
                    session.applySuggestedExclusions(for: workbookPath)
                }
                .buttonStyle(.borderedProminent)
                .disabled(recommendationSpecimens.isEmpty)

                Button("Restore All") {
                    session.restoreAllSpecimens(for: workbookPath)
                }
                .buttonStyle(.bordered)

                Button("Retry Preview") {
                    session.retryPreviewRefresh()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var recommendationSpecimens: [DataStudioSpecimenPreviewResponse] {
        preview.specimens.filter { preview.suggestedExclusionIds.contains($0.specimenId) }
    }

    private var recommendationTitle: String {
        recommendationSpecimens.isEmpty ? "No pending recommendation" : "Exclude \(recommendationSpecimens.count)"
    }

    private var recommendationMessage: String {
        if !recommendationSpecimens.isEmpty {
            let names = recommendationSpecimens.map(\.filename).joined(separator: ", ")
            return "Suggested exclusions: \(names). This rule removes one high and one low outlier from the current included tensile set."
        }
        if !preview.suggestionSupportReason.isEmpty {
            return preview.suggestionSupportReason
        }
        return "No automatic exclusions are available for the current included set."
    }
}

private struct DataStudioSpecimenSection: View {
    let title: String
    let subtitle: String
    let specimens: [DataStudioSpecimenPreviewResponse]
    let workbookPath: String
    @Bindable var session: DataStudioSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(specimens) { specimen in
                    DataStudioSpecimenListRow(
                        session: session,
                        workbookPath: workbookPath,
                        specimen: specimen,
                        suggested: specimen.suggestedExclusion
                    )
                }
            }
        }
    }
}

private struct DataStudioSpecimenListRow: View {
    @Bindable var session: DataStudioSession
    let workbookPath: String
    let specimen: DataStudioSpecimenPreviewResponse
    let suggested: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { specimen.included },
                    set: { session.updateSpecimenInclusion(for: workbookPath, specimenId: specimen.specimenId, included: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(specimen.filename)
                        .font(.body.weight(.semibold))

                    if suggested {
                        statusTag("Recommended", tint: .yellow)
                    }
                    if !specimen.included {
                        statusTag("Excluded", tint: .secondary)
                    }
                    if !specimen.triadComplete {
                        statusTag("Incomplete", tint: .orange)
                    }
                    if !specimen.warnings.isEmpty {
                        statusTag("Warning", tint: .orange)
                    }
                }

                HStack(spacing: 14) {
                    metric("Strength", value: specimen.metrics["Strength"], unit: "MPa")
                    metric("Modulus", value: specimen.metrics["Modulus"], unit: "MPa")
                    metric("Elongation", value: specimen.metrics["Elongation"], unit: "%")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            if !specimen.miniCurvePoints.isEmpty {
                DataStudioMiniCurvePreview(points: specimen.miniCurvePoints)
                    .frame(width: 110, height: 44)
            }
        }
        .padding(12)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 16))
        .animation(MotionTokens.selection, value: specimen.included)
        .animation(MotionTokens.selection, value: suggested)
    }

    private var backgroundColor: Color {
        if suggested {
            return Color.yellow.opacity(0.10)
        }
        if specimen.included {
            return Color(nsColor: .controlBackgroundColor)
        }
        return Color(nsColor: .quaternaryLabelColor).opacity(0.08)
    }

    private func metric(_ title: String, value: Double??, unit: String) -> some View {
        let resolved = value ?? nil
        let text = resolved?.formatted(.number.precision(.fractionLength(2))) ?? "n/a"
        return Text("\(title) \(text) \(unit)")
    }

    private func statusTag(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct DataStudioMiniCurvePreview: View {
    let points: [DataStudioCurvePointResponse]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard let first = normalized.first else {
                    return
                }
                path.move(to: point(from: first, in: geometry.size))
                for value in normalized.dropFirst() {
                    path.addLine(to: point(from: value, in: geometry.size))
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .padding(.vertical, 4)
        }
        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }

    private var normalized: [(x: Double, y: Double)] {
        guard
            let minX = points.map(\.x).min(),
            let maxX = points.map(\.x).max(),
            let minY = points.map(\.y).min(),
            let maxY = points.map(\.y).max()
        else {
            return []
        }
        let xSpan = max(maxX - minX, 0.0001)
        let ySpan = max(maxY - minY, 0.0001)
        return points.map { point in
            ((point.x - minX) / xSpan, (point.y - minY) / ySpan)
        }
    }

    private func point(from value: (x: Double, y: Double), in size: CGSize) -> CGPoint {
        CGPoint(
            x: value.x * max(size.width - 8, 1) + 4,
            y: (1 - value.y) * max(size.height - 8, 1) + 4
        )
    }
}
