import AppKit
import SwiftUI

enum InspectorColumnLayoutPolicy {
    static let minWidth: CGFloat = 360
    static let idealWidth: CGFloat = 400
    static let maxWidth: CGFloat = 460
}

@MainActor
enum MotionTokens {
    static let workbenchSwitch: Animation = .smooth(duration: 0.2)
    static let selection: Animation = .snappy(duration: 0.16, extraBounce: 0.0)
    static let status: Animation = .snappy(duration: 0.14, extraBounce: 0.0)
    static let list: Animation = .smooth(duration: 0.18)
    static let stateTransition: AnyTransition = .opacity.combined(with: .move(edge: .bottom))
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
            .background(Color(nsColor: .windowBackgroundColor))
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

struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "sparkles.rectangle.stack")
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(.quinary.opacity(0.25), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ErrorStateCard: View {
    let title: String
    let message: String
    let retryTitle: String?
    let retryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let retryTitle, let retryAction {
                Button(retryTitle, action: retryAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.quinary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

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

            if isExpanded {
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
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.quinary.opacity(0.32), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct BusyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(.quinary.opacity(0.25), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12, content: { content })
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct InspectorEmptyState: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
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
            .foregroundStyle(.secondary)
    }

    private var stackedLabel: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var horizontalValue: some View {
        Text(value)
            .foregroundStyle(secondaryValue ? .secondary : .primary)
            .fixedSize(horizontal: true, vertical: false)
            .inspectorSelectable(selectable)
    }

    private var stackedValue: some View {
        Text(value)
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
