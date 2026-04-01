import SwiftUI

private enum CleanupRailPane: String, CaseIterable, Identifiable {
    case rawIntake
    case preparedQueue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rawIntake:
            return "Raw Intake"
        case .preparedQueue:
            return "Prepared Queue"
        }
    }
}

struct CleanupImportView: View {
    let session: DataCleanupSession

    @State private var selectedPane: CleanupRailPane = .preparedQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Cleanup Rail", selection: $selectedPane) {
                ForEach(CleanupRailPane.allCases) { pane in
                    Text(pane.title).tag(pane)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch selectedPane {
                case .rawIntake:
                    rawIntakePane
                case .preparedQueue:
                    preparedQueuePane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quinary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .onAppear(perform: syncSelectedPane)
        .onChange(of: session.rawInputURLs.count) { _, _ in
            syncSelectedPane()
        }
        .onChange(of: session.preparedWorkbooks.count) { _, _ in
            syncSelectedPane()
        }
    }

    @ViewBuilder
    private var rawIntakePane: some View {
        if session.rawInputURLs.isEmpty {
            ContentUnavailableView(
                "No raw intake yet",
                systemImage: "doc.text",
                description: Text("Import raw tensile CSV files from the toolbar when you want to preprocess a new workbook.")
            )
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(session.rawInputURLs, id: \.path) { url in
                        RawIntakeCard(
                            title: url.lastPathComponent,
                            staged: session.currentActivity == .preprocessing
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var preparedQueuePane: some View {
        if session.orderedPreparedWorkbooks.isEmpty {
            ContentUnavailableView(
                "No prepared workbooks yet",
                systemImage: "tablecells",
                description: Text("Import raw CSV or open a prepared workbook to populate the cleanup queue.")
            )
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
        } else {
            List(selection: selectionBinding) {
                ForEach(session.orderedPreparedWorkbooks) { workbook in
                    CleanupWorkbookRow(
                        workbook: workbook,
                        isFocused: workbook.id == session.focusedWorkbook?.id,
                        isPrimary: workbook.id == session.primaryWorkbook?.id,
                        setAsPrimary: {
                            session.setPrimaryWorkbook(id: workbook.id)
                        }
                    )
                    .tag(workbook.id)
                }
                .onMove(perform: session.moveComparisonWorkbooks)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { session.focusedWorkbook?.id },
            set: { session.setFocusedWorkbook(id: $0) }
        )
    }

    private func syncSelectedPane() {
        if session.preparedWorkbooks.isEmpty, !session.rawInputURLs.isEmpty {
            selectedPane = .rawIntake
        } else if !session.preparedWorkbooks.isEmpty {
            selectedPane = .preparedQueue
        }
    }
}

private struct RawIntakeCard: View {
    let title: String
    let staged: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if staged {
                railBadge("Staged", style: .focused)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct CleanupWorkbookRow: View {
    let workbook: PreparedWorkbookItem
    let isFocused: Bool
    let isPrimary: Bool
    let setAsPrimary: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(workbook.label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isFocused {
                        railBadge("Focused", style: .focused)
                    }
                    if isPrimary {
                        railBadge("Primary", style: .primary)
                    }
                }

                Text(workbook.url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(workbook.sampleCount) specimens")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: setAsPrimary) {
                Image(systemName: isPrimary ? "star.fill" : "star")
                    .foregroundStyle(isPrimary ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(isPrimary)
            .help(isPrimary ? "Primary workbook" : "Set as primary workbook")
        }
        .padding(.vertical, 4)
    }
}

private enum CleanupRailBadgeStyle {
    case focused
    case primary
}

@ViewBuilder
private func railBadge(_ text: String, style: CleanupRailBadgeStyle) -> some View {
    Text(text)
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor(for: style), in: Capsule())
        .foregroundStyle(foregroundColor(for: style))
}

private func backgroundColor(for style: CleanupRailBadgeStyle) -> Color {
    switch style {
    case .focused:
        return Color.accentColor.opacity(0.14)
    case .primary:
        return Color.secondary.opacity(0.12)
    }
}

private func foregroundColor(for style: CleanupRailBadgeStyle) -> Color {
    switch style {
    case .focused:
        return .accentColor
    case .primary:
        return .secondary
    }
}
