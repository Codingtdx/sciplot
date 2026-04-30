import Foundation
import SwiftUI

struct FitModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let glyphKind: FitModelGlyph.Kind

    var isCustom: Bool {
        id == "custom_function"
    }

    static let all: [FitModelOption] = [
        FitModelOption(id: "linear", title: "Linear", glyphKind: .linear),
        FitModelOption(id: "polynomial_2", title: "Polynomial 2", glyphKind: .polynomial2),
        FitModelOption(id: "polynomial_3", title: "Polynomial 3", glyphKind: .polynomial3),
        FitModelOption(id: "exponential", title: "Exponential", glyphKind: .exponential),
        FitModelOption(id: "logarithmic", title: "Logarithmic", glyphKind: .logarithmic),
        FitModelOption(id: "power_law", title: "Power Law", glyphKind: .powerLaw),
        FitModelOption(id: "gaussian", title: "Gaussian", glyphKind: .gaussian),
        FitModelOption(id: "logistic", title: "Logistic", glyphKind: .logistic),
        FitModelOption(id: "custom_function", title: "Custom", glyphKind: .custom),
    ]
}

struct FitModelGrid: View {
    let selectedModelID: String
    let isEnabled: Bool
    let disabledReason: String?
    var disabledOptionIDs: Set<String> = []
    var optionHelp: (FitModelOption) -> String?
    let select: (FitModelOption) -> Void

    private let columns = [
        GridItem(.flexible(minimum: 118), spacing: 8),
        GridItem(.flexible(minimum: 118), spacing: 8),
    ]

    init(
        selectedModelID: String,
        isEnabled: Bool,
        disabledReason: String?,
        disabledOptionIDs: Set<String> = [],
        optionHelp: @escaping (FitModelOption) -> String? = { _ in nil },
        select: @escaping (FitModelOption) -> Void
    ) {
        self.selectedModelID = selectedModelID
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
        self.disabledOptionIDs = disabledOptionIDs
        self.optionHelp = optionHelp
        self.select = select
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(FitModelOption.all) { option in
                let optionIsEnabled = isEnabled && !disabledOptionIDs.contains(option.id)
                FitModelCard(
                    option: option,
                    isSelected: selectedModelID == option.id,
                    isEnabled: optionIsEnabled
                ) {
                    select(option)
                }
                .disabled(!optionIsEnabled)
                .help(optionHelp(option) ?? disabledReason ?? option.title)
            }
        }
    }
}

struct FitModelCard: View {
    let option: FitModelOption
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                FitModelGlyph(kind: option.glyphKind, isSelected: isSelected, isEnabled: isEnabled)
                    .frame(height: 42)

                Text(option.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(isEnabled ? .primary : .tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: ProCornerPolicy.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .proGlassRow(theme: theme, isSelected: isSelected, cornerRadius: ProCornerPolicy.row)
        .overlay {
            RoundedRectangle(cornerRadius: ProCornerPolicy.row, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.62) : theme.hairline,
                    lineWidth: isSelected ? 1.2 : 0.7
                )
        }
        .opacity(isEnabled ? 1.0 : 0.48)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct FitModelGlyph: View {
    enum Kind: Hashable, Sendable {
        case linear
        case polynomial2
        case polynomial3
        case exponential
        case logarithmic
        case powerLaw
        case gaussian
        case logistic
        case custom
    }

    let kind: Kind
    let isSelected: Bool
    let isEnabled: Bool
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5)
            drawAxes(in: rect, context: &context)

            var curve = Path()
            for index in 0...44 {
                let t = CGFloat(index) / 44.0
                let point = point(for: t, in: rect)
                if index == 0 {
                    curve.move(to: point)
                } else {
                    curve.addLine(to: point)
                }
            }

            context.stroke(
                curve,
                with: .color((isEnabled ? Color.accentColor : Color.secondary).opacity(isSelected ? 0.95 : 0.72)),
                style: StrokeStyle(lineWidth: isSelected ? 2.2 : 1.8, lineCap: .round, lineJoin: .round)
            )

            if kind == .custom {
                drawCustomPoints(in: rect, context: &context)
            }
        }
    }

    private func drawAxes(in rect: CGRect, context: inout GraphicsContext) {
        var axes = Path()
        axes.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        axes.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        axes.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        axes.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        context.stroke(axes, with: .color(theme.hairline.opacity(isEnabled ? 1.0 : 0.55)), lineWidth: 0.8)
    }

    private func drawCustomPoints(in rect: CGRect, context: inout GraphicsContext) {
        for t in [0.18, 0.38, 0.62, 0.82] as [CGFloat] {
            let point = point(for: t, in: rect)
            let dot = CGRect(x: point.x - 2.0, y: point.y - 2.0, width: 4.0, height: 4.0)
            context.fill(Path(ellipseIn: dot), with: .color(Color.accentColor.opacity(isEnabled ? 0.9 : 0.45)))
        }
    }

    private func point(for t: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * t,
            y: rect.minY + rect.height * normalizedY(t)
        )
    }

    private func normalizedY(_ t: CGFloat) -> CGFloat {
        let value: Double
        let x = Double(t)
        switch kind {
        case .linear:
            value = 0.78 - 0.58 * x
        case .polynomial2:
            value = 0.22 + 1.85 * pow(x - 0.54, 2)
        case .polynomial3:
            value = 0.78 - 0.62 * (3 * x * x - 2 * x * x * x)
        case .exponential:
            value = 0.82 - 0.68 * ((exp(2.4 * x) - 1) / (exp(2.4) - 1))
        case .logarithmic:
            value = 0.82 - 0.62 * (log(1 + 5 * x) / log(6))
        case .powerLaw:
            value = 0.82 - 0.66 * pow(x, 1.8)
        case .gaussian:
            value = 0.82 - 0.68 * exp(-pow((x - 0.5) / 0.18, 2) / 2)
        case .logistic:
            value = 0.79 - 0.62 / (1 + exp(-9 * (x - 0.5)))
        case .custom:
            value = 0.52 - 0.18 * sin(2.0 * .pi * x) - 0.12 * sin(5.0 * .pi * x)
        }
        return CGFloat(min(max(value, 0.12), 0.88))
    }
}

struct FitResultSummaryPanel: View {
    let isLoading: Bool
    let errorMessage: String?
    let rows: [(String, String)]
    let warnings: [String]
    let seriesSummaries: [FitSeriesSummaryResponse]
    let selectedSeriesID: String?
    let selectSeries: (String?) -> Void
    let retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                FitInlineBanner(message: errorMessage, retry: retry)
            } else if isLoading && rows.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if rows.isEmpty {
                InspectorEmptyState(message: "No fit results")
            } else {
                if seriesSummaries.count > 1 {
                    fitSeriesChips
                }

                if let equation = value(for: "Equation") {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Equation")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(equation)
                            .font(.caption)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    metricChip(title: "R2", value: value(for: "R²"))
                    metricChip(title: "RMSE", value: value(for: "RMSE"))
                    metricChip(title: "Points", value: value(for: "Points"))
                }

                ForEach(warnings.prefix(2), id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var fitSeriesChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(seriesSummaries) { summary in
                    FitSeriesChip(
                        title: summary.seriesLabel,
                        isSelected: selectedSeriesID == summary.seriesID
                    ) {
                        selectSeries(summary.seriesID)
                    }
                }
            }
        }
    }

    private func metricChip(title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value ?? "-")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func value(for label: String) -> String? {
        rows.first(where: { $0.0 == label })?.1
    }
}

private struct FitSeriesChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .proGlassRow(theme: theme, isSelected: isSelected, cornerRadius: ProCornerPolicy.smallRow)
    }
}

private struct FitInlineBanner: View {
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            if let retry {
                Button("Retry", action: retry)
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: ProCornerPolicy.smallRow, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ProCornerPolicy.smallRow, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 0.8)
        }
    }
}
