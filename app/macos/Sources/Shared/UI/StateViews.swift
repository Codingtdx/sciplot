import AppKit
import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    static let storageKey = "appAppearanceMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "Follow System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    func effectiveColorScheme(system: ColorScheme) -> ColorScheme {
        preferredColorScheme ?? system
    }

    static func storedValue(from rawValue: String) -> AppAppearanceMode {
        AppAppearanceMode(rawValue: rawValue) ?? .system
    }
}

enum InspectorColumnLayoutPolicy {
    static let minWidth: CGFloat = 320
    static let idealWidth: CGFloat = 360
    static let maxWidth: CGFloat = 420
}

enum ProWorkspaceMetrics {
    static let panelSpacing: CGFloat = 12
    static let outerCornerRadius: CGFloat = 22
    static let innerCornerRadius: CGFloat = 12
    static let leftRailMinWidth: CGFloat = 280
    static let leftRailIdealWidth: CGFloat = 320
    static let leftRailMaxWidth: CGFloat = 360
}

enum ProCornerPolicy {
    static let outer: CGFloat = 22
    static let launcher: CGFloat = 30
    static let rail: CGFloat = 18
    static let row: CGFloat = 12
    static let smallRow: CGFloat = 10
    static let preview: CGFloat = 14
}

enum ProWorkspaceTheme: Equatable, Sendable {
    case light
    case dark

    init(colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    var rootBackground: Color {
        switch self {
        case .light:
            return Color(red: 0.985, green: 0.982, blue: 0.972)
        case .dark:
            return Color(red: 0.075, green: 0.078, blue: 0.085)
        }
    }

    var stageBackground: Color {
        switch self {
        case .light:
            return Color(red: 0.956, green: 0.952, blue: 0.940)
        case .dark:
            return Color(red: 0.045, green: 0.048, blue: 0.054)
        }
    }

    var panelFill: Color {
        switch self {
        case .light:
            return Color.white.opacity(0.74)
        case .dark:
            return Color.white.opacity(0.045)
        }
    }

    var rowFill: Color {
        switch self {
        case .light:
            return Color.white.opacity(0.58)
        case .dark:
            return Color.white.opacity(0.065)
        }
    }

    var selectedRowFill: Color {
        switch self {
        case .light:
            return Color.accentColor.opacity(0.14)
        case .dark:
            return Color.accentColor.opacity(0.16)
        }
    }

    var previewSurround: Color {
        switch self {
        case .light:
            return Color(red: 0.930, green: 0.926, blue: 0.912)
        case .dark:
            return Color(red: 0.040, green: 0.043, blue: 0.050)
        }
    }

    var hairline: Color {
        switch self {
        case .light:
            return Color.black.opacity(0.08)
        case .dark:
            return Color.white.opacity(0.10)
        }
    }

    var isCodexLikeLightWorkspace: Bool {
        self == .light
    }
}

struct ProWorkspaceThemeKey: EnvironmentKey {
    static let defaultValue = ProWorkspaceTheme(colorScheme: .dark)
}

extension EnvironmentValues {
    var proWorkspaceTheme: ProWorkspaceTheme {
        get { self[ProWorkspaceThemeKey.self] }
        set { self[ProWorkspaceThemeKey.self] = newValue }
    }
}

private struct ProWorkspaceAppearanceModifier: ViewModifier {
    let appearanceMode: AppAppearanceMode
    @Environment(\.colorScheme) private var systemColorScheme

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearanceMode.preferredColorScheme)
            .environment(
                \.proWorkspaceTheme,
                ProWorkspaceTheme(colorScheme: appearanceMode.effectiveColorScheme(system: systemColorScheme))
            )
    }
}

extension View {
    func proWorkspaceAppearance(appearanceMode: AppAppearanceMode) -> some View {
        modifier(ProWorkspaceAppearanceModifier(appearanceMode: appearanceMode))
    }

    func proGlassPanel(
        theme: ProWorkspaceTheme,
        cornerRadius: CGFloat = ProCornerPolicy.outer,
        showsBorder: Bool = true
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(theme.panelFill, in: shape)
            .clipShape(shape)
            .glassEffect(.regular.interactive(), in: shape)
            .overlay {
                if showsBorder {
                    shape.stroke(theme.hairline, lineWidth: 0.8)
                }
            }
    }

    func proGlassRail(
        theme: ProWorkspaceTheme,
        cornerRadius: CGFloat = ProCornerPolicy.rail
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(theme.panelFill, in: shape)
            .clipShape(shape)
            .glassEffect(.regular.interactive(), in: shape)
            .overlay {
                shape.stroke(theme.hairline, lineWidth: 0.8)
            }
    }

    func proGlassRow(
        theme: ProWorkspaceTheme,
        isSelected: Bool = false,
        cornerRadius: CGFloat = ProCornerPolicy.row
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(isSelected ? theme.selectedRowFill : theme.rowFill, in: shape)
            .clipShape(shape)
            .glassEffect(.regular.interactive(), in: shape)
    }
}

@MainActor
enum MotionTokens {
    static let workbenchSwitch: Animation = .smooth(duration: 0.2)
    static let selection: Animation = .snappy(duration: 0.16, extraBounce: 0.0)
    static let status: Animation = .snappy(duration: 0.14, extraBounce: 0.0)
    static let list: Animation = .smooth(duration: 0.18)
    static let stateTransition: AnyTransition = .opacity.combined(with: .move(edge: .bottom))
}

private enum StatusCopy {
    static func short(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let firstLine = trimmed
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? trimmed
        let collapsed = firstLine
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else {
            return nil
        }
        guard collapsed.count > 120 else {
            return collapsed
        }

        let cutoff = collapsed.index(collapsed.startIndex, offsetBy: 117)
        return String(collapsed[..<cutoff]) + "..."
    }
}

struct ActionAvailability: Equatable, Sendable {
    let isEnabled: Bool
    let reason: String?

    static func enabled() -> ActionAvailability {
        ActionAvailability(isEnabled: true, reason: nil)
    }

    static func disabled(_ reason: String) -> ActionAvailability {
        ActionAvailability(isEnabled: false, reason: reason)
    }
}

struct ExportedFileItem: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let url: URL

    init(url: URL, label: String? = nil) {
        self.id = url.standardizedFileURL.path
        self.label = label ?? url.lastPathComponent
        self.url = url
    }
}

struct DiagnosticMessage: Equatable, Sendable {
    let summary: String
    let detail: String

    init(summary: String, detail: String) {
        self.summary = summary
        self.detail = detail
    }

    init(detail: String) {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = trimmed.split(separator: "\n").first {
            let summary = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                self.summary = String(summary)
                self.detail = trimmed
                return
            }
        }
        self.summary = "Operation failed"
        self.detail = trimmed
    }
}

struct InspectorSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension View {
    func inspectorSurface() -> some View {
        modifier(InspectorSurfaceModifier())
    }

    func inspectorActionButton() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func inspectorSelectable(_ selectable: Bool) -> some View {
        if selectable {
            textSelection(.enabled)
        } else {
            self
        }
    }
}

struct WorkbenchRailTitle: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
            Spacer(minLength: 8)
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SubtleStageHint: View {
    let title: String
    var systemImage: String? = nil
    var alignment: Alignment = .bottomLeading

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .padding(.vertical, 14)
    }
}

struct EmptyStateCard: View {
    let title: String
    var message: String? = nil

    var body: some View {
        let summary = StatusCopy.short(message)
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "sparkles.rectangle.stack")
                .font(.headline)
            if let summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.vertical, 14)
    }
}

struct LatestExportList: View {
    let items: [ExportedFileItem]
    let openButtonTitle: (ExportedFileItem) -> String
    let openButtonHelp: (ExportedFileItem) -> String
    let openAction: (ExportedFileItem) -> Void

    var body: some View {
        guard !items.isEmpty else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    Button(openButtonTitle(item)) {
                        openAction(item)
                    }
                    .buttonStyle(.bordered)
                    .help(openButtonHelp(item))
                    .inspectorActionButton()
                }
            }
            .padding(.top, 6)
        )
    }
}

struct ErrorStateCard: View {
    let title: String
    let message: String
    let retryTitle: String?
    let retryAction: (() -> Void)?

    private var summaryMessage: String {
        StatusCopy.short(message) ?? "Operation failed. Try again."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text(summaryMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let retryTitle, let retryAction {
                Button(retryTitle, action: retryAction)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }
}

struct DiagnosticIssueCard: View {
    let message: DiagnosticMessage
    let retryTitle: String?
    let retryAction: (() -> Void)?
    @State private var isExpanded = false

    init(
        message: DiagnosticMessage,
        retryTitle: String? = nil,
        retryAction: (() -> Void)? = nil
    ) {
        self.message = message
        self.retryTitle = retryTitle
        self.retryAction = retryAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text(message.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if message.detail != message.summary {
                    Button {
                        withAnimation(MotionTokens.selection) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Hide details" : "Show details")
                }
            }

            if isExpanded, message.detail != message.summary {
                ScrollView {
                    Text(message.detail)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 130)
                .padding(10)
                .background(.quinary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 10) {
                    Button("Copy Details") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(message.detail, forType: .string)
                    }
                    .buttonStyle(.bordered)

                    if let retryTitle, let retryAction {
                        Button(retryTitle, action: retryAction)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.16), lineWidth: 1)
        )
    }
}

struct BusyStateCard: View {
    let title: String
    var message: String? = nil

    var body: some View {
        let summary = StatusCopy.short(message)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(.headline)
            }
            if let summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.vertical, 14)
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12, content: { content })
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

struct InspectorEmptyState: View {
    let message: String

    var body: some View {
        Text(StatusCopy.short(message) ?? "No content")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AdaptiveInspectorTextRow: View {
    let title: String
    let value: String
    var selectable: Bool = false
    var secondaryValue: Bool = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            LabeledContent {
                horizontalValue
            } label: {
                horizontalLabel
            }

            VStack(alignment: .leading, spacing: 4) {
                stackedLabel
                stackedValue
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var horizontalLabel: some View {
        Text(title)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var stackedLabel: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var horizontalValue: some View {
        Text(value)
            .font(.callout)
            .foregroundStyle(secondaryValue ? .secondary : .primary)
            .fixedSize(horizontal: true, vertical: false)
            .inspectorSelectable(selectable)
    }

    private var stackedValue: some View {
        Text(value)
            .font(.callout)
            .foregroundStyle(secondaryValue ? .secondary : .primary)
            .fixedSize(horizontal: false, vertical: true)
            .inspectorSelectable(selectable)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AdaptiveInspectorControlRow<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            LabeledContent {
                HStack(spacing: 0) {
                    Spacer(minLength: 12)
                    content
                        .fixedSize(horizontal: true, vertical: false)
                }
            } label: {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InspectorActionStack<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KeyValueGrid: View {
    let values: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(values, id: \.0) { item in
                GridRow {
                    Text(item.0)
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
