import SwiftUI

struct DataStudioCreateTemplateEditorSheet: View {
    @Bindable var session: DataStudioSession

    private var preview: SourceTablePreviewResponse? {
        session.sourcePreview
    }

    private var editorPresentation: DataStudioTemplateEditorPresentation {
        session.templateEditorPresentation
    }

    private var columns: [String] {
        preview?.columnHeaders.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorHeader

            Divider()

            HSplitView {
                sourceColumn
                    .frame(minWidth: 360, idealWidth: 410, maxWidth: 480, maxHeight: .infinity)

                roleMappingColumn
                    .frame(minWidth: 420, idealWidth: 470, maxWidth: .infinity, maxHeight: .infinity)

                validationColumn
                    .frame(minWidth: 300, idealWidth: 330, maxWidth: 380, maxHeight: .infinity)
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
                .help(editorPresentation.saveTemplateAvailability.reason ?? "Save this import template.")

                Button("Save Template and Continue Import") {
                    Task { await session.saveTemplateAndContinueImport() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!editorPresentation.saveTemplateAndContinueAvailability.isEnabled)
                .help(editorPresentation.saveTemplateAndContinueAvailability.reason ?? "Save and build the workbook.")
            }
        }
        .frame(minWidth: 1120, idealWidth: 1210, minHeight: 660, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create Import Template")
                .font(.headline)
            if let preview {
                Text(URL(fileURLWithPath: preview.inputPath).lastPathComponent)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(20)
    }

    private var sourceColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let preview {
                GroupBox("Source Setup") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Segment Policy", selection: segmentPolicyBinding) {
                            Text("Single Table").tag("single_table")
                            Text("Series per Segment").tag("series_per_segment")
                        }
                        .pickerStyle(.segmented)

                        TextField("Sheet", text: sourceSheetBinding)
                            .textFieldStyle(.roundedBorder)
                        HStack(spacing: 10) {
                            TextField("Encoding", text: sourceEncodingBinding)
                                .textFieldStyle(.roundedBorder)
                            TextField("Delimiter", text: sourceDelimiterBinding)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                if !preview.segments.isEmpty {
                    GroupBox("Segments") {
                        List(selection: segmentSelectionBinding) {
                            ForEach(preview.segments) { segment in
                                DataStudioSegmentRow(segment: segment)
                                    .tag(Optional(segment.id))
                            }
                        }
                        .listStyle(.inset)
                        .frame(minHeight: 150, maxHeight: 230)
                    }
                }

                GroupBox("Table") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            if let encoding = preview.encoding {
                                Label(encoding, systemImage: "character.cursor.ibeam")
                            }
                            if let delimiter = preview.delimiter {
                                Label(delimiter == "\t" ? "Tab" : delimiter, systemImage: "tablecells")
                            }
                            Spacer()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        DataStudioSourceTablePreview(session: session, preview: preview)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ContentUnavailableView("No Source", systemImage: "tablecells")
            }
        }
        .padding(18)
    }

    private var roleMappingColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DataStudioTemplateBuilderCard(title: "Template", systemImage: "doc.badge.gearshape") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Template Name", text: $session.templateDraftLabel)
                            .textFieldStyle(.roundedBorder)
                        TextField("Description", text: $session.templateDraftDescription, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Picker("Output", selection: outputKindBinding) {
                            Text("Curves").tag("curve_metrics")
                            Text("Metric Table").tag("metric_table")
                            Text("Matrix / Heatmap").tag("matrix_heatmap")
                        }
                        .pickerStyle(.segmented)
                        if session.templateDraftOutputKind == "curve_metrics" {
                            Toggle("Enable Comparison", isOn: comparisonEnabledBinding)
                                .toggleStyle(.switch)
                                .help("Also generate representative and metric compare sheets.")
                        }
                    }
                }

                DataStudioTemplateBuilderCard(title: "Role Mapping", systemImage: "point.3.connected.trianglepath.dotted") {
                    VStack(alignment: .leading, spacing: 14) {
                        if session.templateDraftOutputKind != "metric_table" {
                            Picker("X", selection: xColumnBinding) {
                                ForEach(columns, id: \.self) { column in
                                    Text(column).tag(column)
                                }
                            }
                        }

                        if session.templateDraftOutputKind == "matrix_heatmap" {
                            DataStudioSingleColumnSelector(
                                title: "Y",
                                columns: columns,
                                selected: session.templateDraftYColumnNames.first,
                                action: { column in
                                    session.templateDraftYColumnNames = [column]
                                    session.invalidateTemplatePreview()
                                }
                            )
                            DataStudioSingleColumnSelector(
                                title: "Value",
                                columns: columns,
                                selected: session.templateDraftMetricColumnNames.first,
                                action: { column in
                                    session.templateDraftMetricColumnNames = [column]
                                    session.invalidateTemplatePreview()
                                }
                            )
                        } else {
                            DataStudioColumnToggleList(
                                title: session.templateDraftOutputKind == "metric_table" ? "Metrics" : "Y",
                                columns: selectableYColumns,
                                selectedColumns: session.templateDraftOutputKind == "metric_table"
                                    ? session.templateDraftMetricColumnNames
                                    : session.templateDraftYColumnNames,
                                toggle: { column, isSelected in
                                    if session.templateDraftOutputKind == "metric_table" {
                                        session.setDraftMetricColumn(column, isSelected: isSelected)
                                    } else {
                                        session.setDraftYColumn(column, isSelected: isSelected)
                                    }
                                }
                            )

                            if session.templateDraftOutputKind == "curve_metrics", session.templateDraftComparisonEnabled {
                                DisclosureGroup("Metrics", isExpanded: $session.showAdvancedCandidates) {
                                    DataStudioColumnToggleList(
                                        title: "",
                                        columns: selectableMetricColumns,
                                        selectedColumns: session.templateDraftMetricColumnNames,
                                        toggle: { column, isSelected in
                                            session.setDraftMetricColumn(column, isSelected: isSelected)
                                        }
                                    )
                                    .padding(.top, 8)
                                }
                            }

                            if session.templateDraftOutputKind == "curve_metrics", !session.templateDraftYColumnNames.isEmpty {
                                GroupBox("Sample Names") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(session.templateDraftYColumnNames, id: \.self) { column in
                                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                                Text(column)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 180, alignment: .leading)
                                                TextField(
                                                    "Sample Name",
                                                    text: Binding(
                                                        get: { session.templateDraftSampleNameByYColumn[column] ?? "" },
                                                        set: { session.setDraftSampleName($0, forYColumn: column) }
                                                    )
                                                )
                                                .textFieldStyle(.roundedBorder)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if !boundColumns.isEmpty {
                            GroupBox("Labels and Units") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(boundColumns, id: \.self) { column in
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(column)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            HStack(spacing: 8) {
                                                TextField(
                                                    "Output Label",
                                                    text: Binding(
                                                        get: { session.templateDraftBindingLabelByColumn[column] ?? column },
                                                        set: { session.setDraftBindingLabel($0, forColumn: column) }
                                                    )
                                                )
                                                .textFieldStyle(.roundedBorder)
                                                TextField(
                                                    "Unit Hint",
                                                    text: Binding(
                                                        get: { session.templateDraftUnitHintByColumn[column] ?? "" },
                                                        set: { session.setDraftUnitHint($0, forColumn: column) }
                                                    )
                                                )
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 110)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private var validationColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DataStudioTemplateBuilderCard(title: "Selected Roles", systemImage: "checklist") {
                    if editorPresentation.selectedSummaryItems.isEmpty {
                        Text("No roles selected")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(editorPresentation.selectedSummaryItems) { item in
                                LabeledContent(item.title) {
                                    Text(item.value)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                    }
                }

                DataStudioTemplateBuilderCard(title: "Normalized Preview", systemImage: "tablecells.badge.ellipsis") {
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            Task { await session.previewTemplateDraft() }
                        } label: {
                            Label("Preview Template", systemImage: "play.rectangle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!session.previewTemplateDraftAvailability.isEnabled)
                        .help(session.previewTemplateDraftAvailability.reason ?? "Validate the current mapping against the source preview.")

                        if let summary = editorPresentation.previewCaption {
                            Label(
                                summary,
                                systemImage: session.templatePreview?.errors.isEmpty == false ? "exclamationmark.triangle" : "checkmark.circle"
                            )
                            .foregroundStyle(session.templatePreview?.errors.isEmpty == false ? .orange : .secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(editorPresentation.validationItems) { item in
                                LabeledContent(item.title) {
                                    Text(item.value)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private var segmentSelectionBinding: Binding<String?> {
        Binding(
            get: { session.selectedPreviewSegmentID },
            set: { session.selectPreviewSegment(id: $0) }
        )
    }

    private var segmentPolicyBinding: Binding<String> {
        Binding(
            get: { session.templateDraftSegmentPolicy },
            set: { session.setTemplateSegmentPolicy($0) }
        )
    }

    private var sourceEncodingBinding: Binding<String> {
        Binding(
            get: { session.templateDraftSourceEncoding },
            set: {
                session.updateTemplateSourceFormat(
                    encoding: $0,
                    delimiter: session.templateDraftSourceDelimiter,
                    sheetName: session.templateDraftSourceSheetName
                )
            }
        )
    }

    private var sourceDelimiterBinding: Binding<String> {
        Binding(
            get: { session.templateDraftSourceDelimiter },
            set: {
                session.updateTemplateSourceFormat(
                    encoding: session.templateDraftSourceEncoding,
                    delimiter: $0,
                    sheetName: session.templateDraftSourceSheetName
                )
            }
        )
    }

    private var sourceSheetBinding: Binding<String> {
        Binding(
            get: { session.templateDraftSourceSheetName },
            set: {
                session.updateTemplateSourceFormat(
                    encoding: session.templateDraftSourceEncoding,
                    delimiter: session.templateDraftSourceDelimiter,
                    sheetName: $0
                )
            }
        )
    }

    private var outputKindBinding: Binding<String> {
        Binding(
            get: { session.templateDraftOutputKind },
            set: { session.setTemplateOutputKind($0) }
        )
    }

    private var comparisonEnabledBinding: Binding<Bool> {
        Binding(
            get: { session.templateDraftComparisonEnabled },
            set: { session.setTemplateComparisonEnabled($0) }
        )
    }

    private var xColumnBinding: Binding<String> {
        Binding(
            get: { session.templateDraftXColumnName ?? columns.first ?? "" },
            set: { session.setDraftXColumn($0.isEmpty ? nil : $0) }
        )
    }

    private var selectableYColumns: [String] {
        columns.filter { $0 != session.templateDraftXColumnName }
    }

    private var selectableMetricColumns: [String] {
        columns.filter { column in
            column != session.templateDraftXColumnName && !session.templateDraftYColumnNames.contains(column)
        }
    }

    private var boundColumns: [String] {
        var result: [String] = []
        func append(_ column: String?) {
            guard let column, !column.isEmpty, !result.contains(column) else {
                return
            }
            result.append(column)
        }
        append(session.templateDraftXColumnName)
        session.templateDraftYColumnNames.forEach { append($0) }
        session.templateDraftMetricColumnNames.forEach { append($0) }
        return result
    }
}

private struct DataStudioTemplateBuilderCard<Content: View>: View {
    let title: String
    let systemImage: String
    private let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))

            content
        }
        .padding(14)
        .background(.quinary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct DataStudioSegmentRow: View {
    let segment: SourceTableSegmentResponse

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(segment.label)
                    .font(.body)
                Text("\(segment.rowCount) rows · \(segment.columnCount) columns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let intervalIndex = segment.intervalIndex {
                Text("#\(intervalIndex)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct DataStudioColumnToggleList: View {
    let title: String
    let columns: [String]
    let selectedColumns: [String]
    let toggle: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            ForEach(columns, id: \.self) { column in
                Toggle(column, isOn: Binding(
                    get: { selectedColumns.contains(column) },
                    set: { toggle(column, $0) }
                ))
                .toggleStyle(.checkbox)
            }
        }
    }
}

private struct DataStudioSingleColumnSelector: View {
    let title: String
    let columns: [String]
    let selected: String?
    let action: (String) -> Void

    var body: some View {
        Picker(title, selection: Binding(
            get: { selected ?? columns.first ?? "" },
            set: { action($0) }
        )) {
            ForEach(columns, id: \.self) { column in
                Text(column).tag(column)
            }
        }
    }
}

private struct DataStudioSourceTablePreview: View {
    @Bindable var session: DataStudioSession
    let preview: SourceTablePreviewResponse

    private var columnCount: Int {
        max(preview.totalCols, preview.columnHeaders.count, preview.rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    tableHeaderCell("#", columnName: nil)
                        .frame(width: 44)
                    ForEach(0 ..< columnCount, id: \.self) { column in
                        tableHeaderCell(header(for: column), columnName: header(for: column))
                            .frame(minWidth: 124, maxWidth: 170, minHeight: 48)
                    }
                }

                ForEach(Array(preview.rows.enumerated()), id: \.offset) { rowOffset, row in
                    DataStudioSourceTableRow(
                        session: session,
                        preview: preview,
                        rowOffset: rowOffset,
                        row: row,
                        columnCount: columnCount
                    )
                }
            }
        }
        .frame(minHeight: 320)
    }

    private func tableHeaderCell(_ text: String, columnName: String?) -> some View {
        Menu {
            if let columnName {
                Button {
                    session.setDraftXColumn(columnName)
                } label: {
                    Label("Use as X", systemImage: "arrow.right")
                }
                Button {
                    session.setDraftYColumn(columnName, isSelected: !session.templateDraftYColumnNames.contains(columnName))
                } label: {
                    Label(
                        session.templateDraftYColumnNames.contains(columnName) ? "Remove Y" : "Use as Y",
                        systemImage: "waveform.path"
                    )
                }
                Button {
                    session.setDraftMetricColumn(columnName, isSelected: !session.templateDraftMetricColumnNames.contains(columnName))
                } label: {
                    Label(
                        session.templateDraftMetricColumnNames.contains(columnName) ? "Remove Metric" : "Use as Metric",
                        systemImage: "number"
                    )
                }
            }
        } label: {
            VStack(spacing: 4) {
                Text(text)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                HStack(spacing: 4) {
                    ForEach(roleLabels(for: columnName), id: \.self) { role in
                        roleBadge(role)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(roleFill(for: columnName ?? ""))
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
    }

    private func header(for column: Int) -> String {
        guard column < preview.columnHeaders.count else {
            return spreadsheetColumnLabel(for: column)
        }
        return preview.columnHeaders[column]
    }

    private func roleLabels(for columnName: String?) -> [String] {
        guard let columnName else {
            return []
        }
        var roles: [String] = []
        if session.templateDraftXColumnName == columnName {
            roles.append("X")
        }
        if session.templateDraftYColumnNames.contains(columnName) {
            roles.append("Y")
        }
        if session.templateDraftMetricColumnNames.contains(columnName) {
            roles.append("M")
        }
        return roles
    }

    private func roleFill(for columnName: String) -> Color {
        if session.templateDraftXColumnName == columnName {
            return .blue.opacity(0.10)
        }
        if session.templateDraftYColumnNames.contains(columnName) {
            return .orange.opacity(0.11)
        }
        if session.templateDraftMetricColumnNames.contains(columnName) {
            return .green.opacity(0.11)
        }
        return Color(nsColor: .windowBackgroundColor)
    }

    private func roleBadge(_ role: String) -> some View {
        Text(role)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(role == "X" ? .blue : role == "Y" ? .orange : .green, in: Capsule())
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

private struct DataStudioSourceTableRow: View {
    @Bindable var session: DataStudioSession
    let preview: SourceTablePreviewResponse
    let rowOffset: Int
    let row: [JSONValue]
    let columnCount: Int

    var body: some View {
        HStack(spacing: 0) {
            Text(rowNumber)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 30)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(Rectangle().stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5))

            ForEach(0 ..< columnCount, id: \.self) { column in
                Text(cellValue(for: column))
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minWidth: 124, maxWidth: 170, minHeight: 30, alignment: .leading)
                    .background(roleFill(for: header(for: column)))
                    .overlay(Rectangle().stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5))
            }
        }
    }

    private var rowNumber: String {
        String(preview.offset + rowOffset + 1)
    }

    private func cellValue(for column: Int) -> String {
        column < row.count ? row[column].displayString : ""
    }

    private func header(for column: Int) -> String {
        guard column < preview.columnHeaders.count else {
            return ""
        }
        return preview.columnHeaders[column]
    }

    private func roleFill(for columnName: String) -> Color {
        if session.templateDraftXColumnName == columnName {
            return .blue.opacity(0.10)
        }
        if session.templateDraftYColumnNames.contains(columnName) {
            return .orange.opacity(0.11)
        }
        if session.templateDraftMetricColumnNames.contains(columnName) {
            return .green.opacity(0.11)
        }
        return Color(nsColor: .windowBackgroundColor)
    }
}
