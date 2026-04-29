import SwiftUI

struct SortableSeriesListRow: Identifiable, Equatable {
    let id: String
    let title: String
    let positionLabel: String
    let moveUpAvailability: ActionAvailability
    let moveDownAvailability: ActionAvailability
}

struct SortableSeriesListView: View {
    let title: String
    let rows: [SortableSeriesListRow]
    let moveItem: (_ id: String, _ offset: Int) -> Void
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if rows.isEmpty {
                Text("No legend entries")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                            Text(row.title)
                                .lineLimit(1)
                            Spacer()
                            Text(row.positionLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                moveItem(row.id, -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!row.moveUpAvailability.isEnabled)
                            .help(
                                row.moveUpAvailability.reason
                                    ?? "Move \(row.title) earlier in the legend order."
                            )

                            Button {
                                moveItem(row.id, 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!row.moveDownAvailability.isEnabled)
                            .help(
                                row.moveDownAvailability.reason
                                    ?? "Move \(row.title) later in the legend order."
                            )
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .proGlassRow(theme: theme, cornerRadius: ProCornerPolicy.smallRow)
                    }
                }
            }
        }
        .padding(12)
        .background(theme.rowFill.opacity(0.7), in: RoundedRectangle(cornerRadius: ProCornerPolicy.preview, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: ProCornerPolicy.preview, style: .continuous))
    }
}
