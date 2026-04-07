import SwiftUI

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
