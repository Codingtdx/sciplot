import SwiftUI

struct DataStudioSpecimenFilterPrimaryTrigger: View {
    @Bindable var session: DataStudioSession
    let workbook: DataStudioWorkbookItem

    var body: some View {
        let presentation = session.specimenFilterPresentation(for: workbook.response.workbookPath)
        Button {
            session.openSpecimenFilter(
                for: workbook.response.workbookPath,
                anchor: .focusedStrip(workbookPath: workbook.response.workbookPath)
            )
        } label: {
            Text(presentation.title)
                .font(.subheadline.weight(.semibold))
            .frame(minWidth: 108, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .help(presentation.help)
        .popover(
            isPresented: isPresentedBinding,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            DataStudioSpecimenFilterPopover(session: session, workbook: workbook)
        }
    }

    private var isPresentedBinding: Binding<Bool> {
        Binding(
            get: {
                session.specimenFilterAnchor == .focusedStrip(workbookPath: workbook.response.workbookPath)
            },
            set: { isPresented in
                if isPresented {
                    session.openSpecimenFilter(
                        for: workbook.response.workbookPath,
                        anchor: .focusedStrip(workbookPath: workbook.response.workbookPath)
                    )
                } else {
                    session.closeSpecimenFilter()
                }
            }
        )
    }
}

struct DataStudioSpecimenFilterPopover: View {
    @Bindable var session: DataStudioSession
    let workbook: DataStudioWorkbookItem
    @State private var isAdvancedExpanded = false

    var body: some View {
        let presentation = session.specimenFilterPresentation(for: workbook.response.workbookPath)
        VStack(alignment: .leading, spacing: 16) {
            header

            if let refreshMessage = refreshMessage() {
                Label(refreshMessage.message, systemImage: refreshMessage.symbol)
                    .font(.footnote)
                    .foregroundStyle(refreshMessage.tint)
            }

            if let baselinePreview {
                if baselinePreview.supported {
                    supportedContent(presentation: presentation)
                } else {
                    unavailable(reason: baselinePreview.unsupportedReason)
                }
            } else {
                BusyStateCard(title: "Loading Specimen Filter")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(width: 460, height: 620, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Specimen Filter")
                .font(.headline)

            Spacer()

            Button {
                session.closeSpecimenFilter()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var baselinePreview: DataStudioWorkbookPreviewResponse? {
        session.baselineWorkbookPreview(for: workbook.response.workbookPath)
    }

    private func refreshMessage() -> (message: String, symbol: String, tint: Color)? {
        let workbookPath = workbook.response.workbookPath
        switch session.focusedWorkbookPreviewRefreshState {
        case let .failed(currentPath, message) where currentPath == workbookPath:
            return (message, "exclamationmark.triangle.fill", .orange)
        default:
            break
        }
        switch session.baselineWorkbookPreviewRefreshState {
        case let .failed(currentPath, message) where currentPath == workbookPath:
            return (message, "exclamationmark.triangle.fill", .orange)
        default:
            return nil
        }
    }

    private func supportedContent(
        presentation: DataStudioSpecimenFilterPresentation
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(presentation.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if presentation.hasPendingChanges {
                        Text("Edited")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }

                if let reason = presentation.autoFilterReason, !presentation.autoFilterSupported {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DataStudioSpecimenFilterRankedList(
                    sortDescriptor: presentation.sortDescriptor,
                    rows: presentation.rankedRows
                )

                actionSection(presentation: presentation)

                DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
                    DataStudioSpecimenFilterAdvancedSection(
                        session: session,
                        workbookPath: workbook.response.workbookPath
                    )
                    .padding(.top, 10)
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 2)
        }
    }

    private func unavailable(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Specimen filter unavailable")
                .font(.headline)
            Text(reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionSection(
        presentation: DataStudioSpecimenFilterPresentation
    ) -> some View {
        HStack(spacing: 10) {
            Button("Use Auto Keep 5") {
                session.applySuggestedExclusions(for: workbook.response.workbookPath)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!presentation.canApplyAuto)
            .help(presentation.autoFilterReason ?? "Keep the five specimens closest to the mean.")

            Button("Turn Off") {
                session.restoreAllSpecimens(for: workbook.response.workbookPath)
            }
            .buttonStyle(.bordered)
            .disabled(!presentation.canTurnOff)
            .help("Restore all specimens to the comparison preview.")

            Spacer()
        }
    }
}

private struct DataStudioSpecimenFilterRankedList: View {
    let sortDescriptor: DataStudioSpecimenFilterSortDescriptor
    let rows: [DataStudioSpecimenFilterRankedRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sortDescriptor.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if rows.isEmpty {
                EmptyStateCard(title: "No Specimen Ranking")
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        DataStudioSpecimenFilterRankedRowView(
                            row: row,
                            unit: sortDescriptor.unit
                        )
                        if row.showsCutoffAfter {
                            HStack(spacing: 8) {
                                Divider()
                                Text("Auto cutoff")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Divider()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        if row.id != rows.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

private struct DataStudioSpecimenFilterRankedRowView: View {
    let row: DataStudioSpecimenFilterRankedRow
    let unit: String?

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(row.rank)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 32, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(valueLabel)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.disposition.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.14), in: Capsule())
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var valueLabel: String {
        guard let value = row.sortValue else {
            return "n/a"
        }
        return value.formatted(.number.precision(.fractionLength(2)))
    }

    private var tint: Color {
        switch row.disposition {
        case .keep:
            return .green
        case .out:
            return .orange
        case .ineligible:
            return .secondary
        }
    }
}

private struct DataStudioSpecimenFilterAdvancedSection: View {
    @Bindable var session: DataStudioSession
    let workbookPath: String

    var body: some View {
        let presentation = session.specimenFilterPresentation(for: workbookPath)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button("Apply Changes") {
                    session.applyManualFilter(for: workbookPath)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!presentation.hasPendingChanges || presentation.isBusy)

                Button("Use Auto Representative") {
                    session.restoreAutoRepresentativeSelection(for: workbookPath)
                }
                .buttonStyle(.bordered)
                .disabled(session.draftRepresentativeSpecimenID(for: workbookPath) == nil || presentation.isBusy)

                Button("Revert") {
                    session.revertDraftSpecimenStates(for: workbookPath)
                }
                .buttonStyle(.bordered)
                .disabled(!presentation.hasPendingChanges)

                Spacer()
            }

            VStack(spacing: 0) {
                headerRow
                Divider()
                ForEach(presentation.advancedRows) { specimen in
                    DataStudioSpecimenFilterAdvancedRow(
                        session: session,
                        workbookPath: workbookPath,
                        specimen: specimen
                    )
                    Divider()
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("Include")
                .frame(width: 54, alignment: .leading)
            Text("Rep.")
                .frame(width: 40, alignment: .leading)
            Text("Elong.")
                .frame(width: 64, alignment: .trailing)
            Text("Strength")
                .frame(width: 70, alignment: .trailing)
            Text("Modulus")
                .frame(width: 70, alignment: .trailing)
            Text("Status")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct DataStudioSpecimenFilterAdvancedRow: View {
    @Bindable var session: DataStudioSession
    let workbookPath: String
    let specimen: DataStudioSpecimenPreviewResponse

    var body: some View {
        HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { session.draftSpecimenIncluded(for: workbookPath, specimenId: specimen.specimenId) },
                    set: { session.updateDraftSpecimenInclusion(for: workbookPath, specimenId: specimen.specimenId, included: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .frame(width: 54, alignment: .leading)

            Button {
                session.updateDraftRepresentativeSelection(for: workbookPath, specimenId: specimen.specimenId)
            } label: {
                Image(systemName: representativeSymbolName)
                    .foregroundStyle(representativeTint)
            }
            .buttonStyle(.plain)
            .disabled(!canSelectRepresentative)
            .help(representativeHelp)
            .frame(width: 40, alignment: .leading)

            numeric(specimen.metrics["Elongation"] ?? nil)
                .frame(width: 64, alignment: .trailing)
            numeric(specimen.metrics["Strength"] ?? nil)
                .frame(width: 70, alignment: .trailing)
            numeric(specimen.metrics["Modulus"] ?? nil)
                .frame(width: 70, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    switch specimen.autoRuleRole {
                    case "keep":
                        tag("Auto Keep", tint: .green)
                    case "exclude":
                        tag("Auto Out", tint: .orange)
                    default:
                        EmptyView()
                    }
                    if session.draftSpecimenSelectedAsRepresentative(for: workbookPath, specimenId: specimen.specimenId) {
                        tag("Representative", tint: .blue)
                    }
                    if !specimen.eligibleForAutoFilter {
                        tag("Ineligible", tint: .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func numeric(_ value: Double?) -> some View {
        Text(value?.formatted(.number.precision(.fractionLength(2))) ?? "n/a")
            .font(.footnote)
            .monospacedDigit()
    }

    private var canSelectRepresentative: Bool {
        session.draftSpecimenIncluded(for: workbookPath, specimenId: specimen.specimenId) && !specimen.miniCurvePoints.isEmpty
    }

    private var representativeSymbolName: String {
        session.draftSpecimenSelectedAsRepresentative(for: workbookPath, specimenId: specimen.specimenId)
            ? "checkmark.circle.fill"
            : "circle"
    }

    private var representativeTint: Color {
        canSelectRepresentative ? .blue : .secondary
    }

    private var representativeHelp: String {
        if !session.draftSpecimenIncluded(for: workbookPath, specimenId: specimen.specimenId) {
            return "Include this specimen before selecting it as the representative curve."
        }
        if specimen.miniCurvePoints.isEmpty {
            return "Curve preview unavailable for this specimen."
        }
        if session.draftSpecimenSelectedAsRepresentative(for: workbookPath, specimenId: specimen.specimenId) {
            return "Representative curve is manually pinned to this specimen."
        }
        return "Use this specimen as the representative curve."
    }

    private func tag(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}
