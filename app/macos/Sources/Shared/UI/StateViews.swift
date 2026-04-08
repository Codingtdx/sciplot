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
