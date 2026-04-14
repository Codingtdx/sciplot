import SwiftUI

struct DataStudioCreateTemplateEditorSheet: View {
    @Bindable var session: DataStudioSession

    private var preview: DataStudioRawFilePreviewResponse? {
        session.sourcePreview
    }

    private var editorPresentation: DataStudioTemplateEditorPresentation {
        session.templateEditorPresentation
    }

    private var selectedBlock: DataStudioSheetBlockResponse? {
        guard let preview else {
            return nil
        }
        for sheet in preview.sheets {
            if let explicitID = session.selectedPreviewBlockID,
               let block = sheet.blocks.first(where: { $0.id == explicitID })
            {
                return block
            }
        }
        return preview.sheets.first?.blocks.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorHeader

            Divider()

            HSplitView {
                previewColumn
                    .frame(minWidth: 340, idealWidth: 380, maxWidth: 430, maxHeight: .infinity)

                editorColumn
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            DataStudioSheetFooter {
                Button("Back") {
                    session.goBackInImportWizard()
                }

                Button("Cancel Import") {
                    session.dismissImportWizard()
                }

                Spacer()

                Button("Save Template") {
                    Task { await session.saveTemplateDraft() }
                }
                .buttonStyle(.bordered)
                .disabled(!editorPresentation.saveTemplateAvailability.isEnabled)
                .help(
                    editorPresentation.saveTemplateAvailability.reason
                        ?? "Save this parse template and return to the resolver."
                )

                Button("Save Template and Continue Import") {
                    Task { await session.saveTemplateAndContinueImport() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!editorPresentation.saveTemplateAndContinueAvailability.isEnabled)
                .help(
                    editorPresentation.saveTemplateAndContinueAvailability.reason
                        ?? "Save this parse template and immediately build the workbook."
                )
            }
        }
        .frame(minWidth: 1000, idealWidth: 1040, minHeight: 660, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create Parse Template")
                .font(.headline)

            if let preview {
                Text(URL(fileURLWithPath: preview.sourcePath).lastPathComponent)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(20)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Blocks") {
                if let preview {
                    List(selection: selectedBlockBinding) {
                        ForEach(preview.sheets, id: \.sheetName) { sheet in
                            Section(sheet.sheetName) {
                                ForEach(sheet.blocks, id: \.id) { block in
                                    DataStudioPreviewBlockRow(block: block)
                                        .tag(Optional(block.id))
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 180, maxHeight: 240)
                } else {
                    Text("No blocks")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Table Preview") {
                if let block = selectedBlock {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(block.label)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(block.rowCount) × \(block.colCount)")
                                .foregroundStyle(.secondary)
                        }

                        if let previewCaption = editorPresentation.previewCaption {
                            Label(previewCaption, systemImage: "eye")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        KeyValueGrid(values: [
                            ("Sheet", block.sheetName),
                            ("Header Row", block.headerRowIndex.map { String($0 + 1) } ?? "Not detected"),
                            ("Unit Row", block.unitRowIndex.map { String($0 + 1) } ?? "Not detected"),
                            ("Data Starts", block.dataStartRowIndex.map { String($0 + 1) } ?? "Not detected"),
                        ])

                        DataStudioBlockTablePreview(
                            block: block,
                            hoveredRanges: session.hoveredPreviewRanges,
                            selectedRanges: session.pinnedPreviewRanges
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Select a detected block to preview the sample table.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(18)
    }

    private var editorColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Template") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Template Name", text: $session.templateDraftLabel)
                            .textFieldStyle(.roundedBorder)
                        TextField("Template Description", text: $session.templateDraftDescription, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let suggestion = editorPresentation.primaryCurveSuggestion {
                    GroupBox("Recommended Curve") {
                        DataStudioSuggestionCard(session: session, presentation: suggestion)
                    }
                }

                if let suggestion = editorPresentation.primaryMetricSuggestion {
                    GroupBox("Recommended Metrics") {
                        DataStudioSuggestionCard(session: session, presentation: suggestion)
                    }
                }

                if let suggestion = editorPresentation.primaryMetadataSuggestion {
                    GroupBox("Recommended Metadata") {
                        DataStudioSuggestionCard(session: session, presentation: suggestion)
                    }
                }

                if let suggestion = editorPresentation.primaryStructureSuggestion {
                    GroupBox("Detected Structure") {
                        DataStudioSuggestionCard(session: session, presentation: suggestion)
                    }
                }

                GroupBox("Selected for Template") {
                    if editorPresentation.selectedSummaryItems.isEmpty && session.selectedCandidateIDs.isEmpty {
                        Text("Nothing selected")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            if !editorPresentation.selectedSummaryItems.isEmpty {
                                ForEach(editorPresentation.selectedSummaryItems) { item in
                                    LabeledContent(item.title) {
                                        Text(item.value)
                                            .font(.footnote)
                                            .multilineTextAlignment(.trailing)
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }

                            let advancedSelections = editorPresentation.advancedCandidates.filter {
                                session.selectedCandidateIDs.contains($0.id)
                            }
                            if !advancedSelections.isEmpty {
                                Divider()
                                Text("Additional Advanced Fields")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                DataStudioCandidateSectionList(
                                    session: session,
                                    candidates: advancedSelections,
                                    compact: true
                                )
                            }
                        }
                    }
                }

                if !editorPresentation.secondaryCurveSuggestions.isEmpty
                    || !editorPresentation.advancedCandidates.isEmpty
                    || preview != nil
                {
                    GroupBox {
                        DisclosureGroup("Advanced", isExpanded: $session.showAdvancedCandidates) {
                            VStack(alignment: .leading, spacing: 14) {
                                if !editorPresentation.secondaryCurveSuggestions.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Other Possible Curves")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        ForEach(editorPresentation.secondaryCurveSuggestions) { suggestion in
                                            DataStudioSuggestionCard(
                                                session: session,
                                                presentation: suggestion,
                                                compact: true
                                            )
                                        }
                                    }
                                }

                                if !editorPresentation.advancedCandidates.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Manual Candidate Overrides")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        DataStudioCandidateSectionList(
                                            session: session,
                                            candidates: editorPresentation.advancedCandidates
                                        )
                                    }
                                }

                                if let preview {
                                    DataStudioTechnicalDetailsDisclosure(preview: preview)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private var selectedBlockBinding: Binding<String?> {
        Binding(
            get: { session.selectedPreviewBlockID ?? selectedBlock?.id },
            set: { newValue in
                guard let newValue else {
                    return
                }
                session.selectPreviewBlock(id: newValue)
            }
        )
    }
}

private struct DataStudioPreviewBlockRow: View {
    let block: DataStudioSheetBlockResponse

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.label)
                    .font(.body)
                Text("\(block.rowCount) × \(block.colCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if block.headerRowIndex != nil {
                Image(systemName: "tablecells.badge.ellipsis")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DataStudioSuggestionCard: View {
    @Bindable var session: DataStudioSession
    let presentation: DataStudioSuggestionCardPresentation
    var compact = false

    private var isSelected: Bool {
        session.selectedSuggestionIDs.contains(presentation.id)
    }

    private var isPreviewing: Bool {
        session.hoveredSuggestionID == presentation.id
    }

    var body: some View {
        Button {
            session.toggleSuggestion(id: presentation.id)
        } label: {
            DataStudioSuggestionCardChrome(
                accentColor: accentColor,
                borderColor: borderColor,
                backgroundColor: backgroundColor,
                borderWidth: borderWidth,
                compact: compact
            ) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: iconName)
                        .foregroundStyle(accentColor)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                        ForEach(Array(presentation.values.enumerated()), id: \.offset) { _, value in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(accentColor.opacity(0.85))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                Text(value)
                                    .font(compact ? .footnote : .callout)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                        }

                        if let location = presentation.location, !location.isEmpty {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            session.setHoveredSuggestion(id: isHovering ? presentation.id : nil)
        }
    }

    private var iconName: String {
        switch presentation.kind {
        case .curve:
            return "waveform.path.ecg"
        case .metric:
            return "chart.bar.xaxis"
        case .metadata:
            return "tag"
        case .structure:
            return "tablecells"
        }
    }

    private var accentColor: Color {
        switch presentation.kind {
        case .curve:
            return .blue
        case .metric:
            return .green
        case .metadata:
            return .cyan
        case .structure:
            return .orange
        }
    }

    private var backgroundColor: Color {
        if isPreviewing {
            return accentColor.opacity(0.14)
        }
        return isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isPreviewing {
            return accentColor.opacity(0.9)
        }
        if isSelected {
            return Color.accentColor.opacity(0.75)
        }
        return Color(nsColor: .separatorColor).opacity(0.45)
    }

    private var borderWidth: CGFloat {
        if isPreviewing {
            return 2
        }
        return isSelected ? 1.4 : 1
    }
}

private struct DataStudioSuggestionCardChrome<Content: View>: View {
    let accentColor: Color
    let borderColor: Color
    let backgroundColor: Color
    let borderWidth: CGFloat
    let compact: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(compact ? 12 : 14)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
    }
}

private struct DataStudioTechnicalDetailsDisclosure: View {
    let preview: DataStudioRawFilePreviewResponse

    var body: some View {
        DisclosureGroup("Technical Details") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("File Type", value: preview.fileType.uppercased())
                LabeledContent("Sheets", value: "\(preview.sheets.count)")
                if let encoding = preview.encoding, !encoding.isEmpty {
                    LabeledContent("Encoding", value: encoding)
                }
                if let delimiter = preview.delimiter, !delimiter.isEmpty {
                    LabeledContent("Delimiter", value: delimiter)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        }
    }
}

private struct DataStudioCandidateSectionList: View {
    @Bindable var session: DataStudioSession
    let candidates: [DataStudioFieldCandidateResponse]
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                if index > 0 {
                    Divider()
                }
                DataStudioCandidateRow(
                    session: session,
                    candidate: candidate,
                    compact: compact
                )
                .padding(.vertical, compact ? 6 : 8)
            }
        }
    }
}

private struct DataStudioCandidateRow: View {
    @Bindable var session: DataStudioSession
    let candidate: DataStudioFieldCandidateResponse
    var compact: Bool

    var body: some View {
        Toggle(isOn: candidateSelectionBinding) {
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(candidate.label)
                        .font(.body.weight(.semibold))
                    Text(candidate.kindLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
    }

    private var candidateSelectionBinding: Binding<Bool> {
        Binding(
            get: { session.selectedCandidateIDs.contains(candidate.id) },
            set: { newValue in
                session.setCandidateSelection(id: candidate.id, isSelected: newValue)
            }
        )
    }
}

private struct DataStudioBlockTablePreview: View {
    let block: DataStudioSheetBlockResponse
    let hoveredRanges: [DataStudioPreviewRangeResponse]
    let selectedRanges: [DataStudioPreviewRangeResponse]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    tableHeaderCell("", hoveredRoles: [], selectedRoles: [])
                        .frame(width: 44)
                    ForEach(0 ..< columnCount, id: \.self) { column in
                        tableHeaderCell(
                            columnLabel(for: column),
                            hoveredRoles: columnRoles(for: column, in: hoveredRanges),
                            selectedRoles: columnRoles(for: column, in: selectedRanges)
                        )
                        .frame(minWidth: 110, maxWidth: 140)
                    }
                }

                ForEach(Array(block.sampleRows.enumerated()), id: \.offset) { rowOffset, row in
                    HStack(spacing: 0) {
                        tableRowIndexCell(
                            rowNumber(for: rowOffset),
                            hoveredRoles: rowRoles(for: rowOffset, in: hoveredRanges),
                            selectedRoles: rowRoles(for: rowOffset, in: selectedRanges)
                        )
                        .frame(width: 44)
                        ForEach(0 ..< columnCount, id: \.self) { column in
                            tableDataCell(
                                value: column < row.count ? row[column].displayString : "",
                                rowOffset: rowOffset,
                                columnOffset: column
                            )
                            .frame(minWidth: 110, maxWidth: 140, minHeight: 30, alignment: .leading)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.22))
            )
        }
        .frame(minHeight: 320)
    }

    private var columnCount: Int {
        max(block.colCount, block.sampleRows.map(\.count).max() ?? 0)
    }

    private func tableHeaderCell(
        _ text: String,
        hoveredRoles: [String],
        selectedRoles: [String]
    ) -> some View {
        let highlight = highlightState(hoveredRoles: hoveredRoles, selectedRoles: selectedRoles)
        return VStack(spacing: 4) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let badgeRole = preferredBadgeRole(from: highlight.roles) {
                roleBadge(for: badgeRole, compact: true)
            } else {
                Spacer()
                    .frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(highlight.fill)
        .overlay(Rectangle().stroke(highlight.stroke, lineWidth: highlight.lineWidth))
    }

    private func tableRowIndexCell(
        _ text: String,
        hoveredRoles: [String],
        selectedRoles: [String]
    ) -> some View {
        let highlight = highlightState(hoveredRoles: hoveredRoles, selectedRoles: selectedRoles)
        return VStack(spacing: 3) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let badgeRole = preferredBadgeRole(from: highlight.roles) {
                roleBadge(for: badgeRole, compact: true)
            } else {
                Spacer()
                    .frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(highlight.fill)
        .overlay(Rectangle().stroke(highlight.stroke, lineWidth: highlight.lineWidth))
    }

    private func tableDataCell(value: String, rowOffset: Int, columnOffset: Int) -> some View {
        let hoveredRoles = matchingRoles(rowOffset: rowOffset, columnOffset: columnOffset, in: hoveredRanges)
        let selectedRoles = matchingRoles(rowOffset: rowOffset, columnOffset: columnOffset, in: selectedRanges)
        let highlight = highlightState(hoveredRoles: hoveredRoles, selectedRoles: selectedRoles)
        return Text(value)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlight.fill)
            .overlay(
                Rectangle()
                    .stroke(highlight.stroke, lineWidth: highlight.lineWidth)
            )
    }

    private func matchingRoles(
        rowOffset: Int,
        columnOffset: Int,
        in ranges: [DataStudioPreviewRangeResponse]
    ) -> [String] {
        let absoluteRow = block.range.startRow + rowOffset
        let absoluteColumn = block.range.startCol + columnOffset
        let ordered = ranges.filter { range in
            range.sheetName == block.sheetName &&
            (range.blockID == nil || range.blockID == block.id) &&
            absoluteRow >= range.startRow &&
            absoluteRow <= range.endRow &&
            absoluteColumn >= range.startCol &&
            absoluteColumn <= range.endCol
        }
        return ordered
            .map(\.role)
            .sorted { rolePriority($0) < rolePriority($1) }
    }

    private func columnRoles(for columnOffset: Int, in ranges: [DataStudioPreviewRangeResponse]) -> [String] {
        let absoluteColumn = block.range.startCol + columnOffset
        return ranges
            .filter { range in
                range.sheetName == block.sheetName &&
                (range.blockID == nil || range.blockID == block.id) &&
                !["header_row", "unit_row"].contains(range.role) &&
                absoluteColumn >= range.startCol &&
                absoluteColumn <= range.endCol
            }
            .map(\.role)
            .sorted { rolePriority($0) < rolePriority($1) }
    }

    private func rowRoles(for rowOffset: Int, in ranges: [DataStudioPreviewRangeResponse]) -> [String] {
        let absoluteRow = block.range.startRow + rowOffset
        return ranges
            .filter { range in
                range.sheetName == block.sheetName &&
                (range.blockID == nil || range.blockID == block.id) &&
                ["header_row", "unit_row"].contains(range.role) &&
                absoluteRow >= range.startRow &&
                absoluteRow <= range.endRow
            }
            .map(\.role)
            .sorted { rolePriority($0) < rolePriority($1) }
    }

    private func highlightState(
        hoveredRoles: [String],
        selectedRoles: [String]
    ) -> (roles: [String], fill: Color, stroke: Color, lineWidth: CGFloat) {
        if let role = hoveredRoles.first {
            let accent = color(forRole: role)
            return (hoveredRoles, accent.opacity(0.24), accent.opacity(0.98), 2)
        }
        if let role = selectedRoles.first {
            let accent = color(forRole: role)
            return (selectedRoles, accent.opacity(0.14), accent.opacity(0.74), 1.35)
        }
        return ([], Color(nsColor: .windowBackgroundColor), Color(nsColor: .separatorColor).opacity(0.35), 0.5)
    }

    private func preferredBadgeRole(from roles: [String]) -> String? {
        if roles.contains("x") {
            return "x"
        }
        if roles.contains("y") {
            return "y"
        }
        if roles.contains("metric") {
            return "metric"
        }
        if roles.contains("metadata") {
            return "metadata"
        }
        if roles.contains("header_row") {
            return "header_row"
        }
        if roles.contains("unit_row") {
            return "unit_row"
        }
        return nil
    }

    private func rolePriority(_ role: String) -> Int {
        switch role {
        case "x":
            return 0
        case "y":
            return 1
        case "metric":
            return 2
        case "metadata":
            return 3
        case "header_row":
            return 4
        case "unit_row":
            return 5
        default:
            return 9
        }
    }

    private func roleBadge(for role: String, compact: Bool) -> some View {
        Text(roleBadgeLabel(for: role))
            .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 2 : 4)
            .background(color(forRole: role), in: Capsule())
    }

    private func roleBadgeLabel(for role: String) -> String {
        switch role {
        case "x":
            return "X"
        case "y":
            return "Y"
        case "metric":
            return "Metric"
        case "metadata":
            return "Meta"
        case "header_row":
            return "Header"
        case "unit_row":
            return "Unit"
        default:
            return role
        }
    }

    private func color(forRole role: String) -> Color {
        switch role {
        case "x":
            return .blue
        case "y":
            return .orange
        case "metric":
            return .green
        case "metadata":
            return .cyan
        case "header_row", "unit_row":
            return .orange
        default:
            return .secondary
        }
    }

    private func rowNumber(for rowOffset: Int) -> String {
        String(block.range.startRow + rowOffset + 1)
    }

    private func columnLabel(for offset: Int) -> String {
        let absolute = block.range.startCol + offset
        return spreadsheetColumnLabel(for: absolute)
    }

    private func spreadsheetColumnLabel(for zeroBasedIndex: Int) -> String {
        var value = zeroBasedIndex + 1
        var result = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            result = String(UnicodeScalar(65 + remainder)!) + result
            value = (value - 1) / 26
        }
        return result
    }
}

private extension DataStudioFieldCandidateResponse {
    var kindLabel: String {
        kind
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
