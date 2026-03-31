import SwiftUI

struct OptionRowCard<Content: View>: View {
    let title: String
    let detail: String?
    let emphasized: Bool
    let content: Content

    init(
        title: String,
        detail: String? = nil,
        emphasized: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.emphasized = emphasized
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(emphasized ? .semibold : .regular))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(width: 120, alignment: .leading)

            Spacer(minLength: 10)

            content
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(emphasized ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(emphasized ? 0.18 : 0.12), lineWidth: 1)
        )
    }
}
