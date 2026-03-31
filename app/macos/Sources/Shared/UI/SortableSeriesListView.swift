import SwiftUI

struct SortableSeriesListView: View {
    let title: String
    let detail: String?
    @Binding var items: [String]
    let canEdit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(canEdit ? "Session-only" : "Read only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                Text("No series labels are available yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                            Text(item)
                                .lineLimit(1)
                            Spacer()
                            Text("#\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                moveItem(at: index, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!canEdit || index == 0)

                            Button {
                                moveItem(at: index, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!canEdit || index == items.count - 1)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(.quinary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func moveItem(at index: Int, by offset: Int) {
        guard canEdit else { return }
        let newIndex = index + offset
        guard items.indices.contains(index), items.indices.contains(newIndex) else { return }
        items.swapAt(index, newIndex)
    }
}
