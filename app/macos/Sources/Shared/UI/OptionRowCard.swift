import SwiftUI

struct OptionRowCard<Content: View>: View {
    let title: String
    let detail: String?
    let emphasized: Bool
    let content: Content
    @Environment(\.proWorkspaceTheme) private var theme

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
            emphasized ? theme.selectedRowFill : theme.rowFill,
            in: RoundedRectangle(cornerRadius: ProCornerPolicy.row, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: ProCornerPolicy.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ProCornerPolicy.row, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 0.8)
        }
    }
}
