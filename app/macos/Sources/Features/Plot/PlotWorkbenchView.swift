import AppKit
import SwiftUI

struct PlotWorkbenchView: View {
    @Bindable var session: PlotSession
    var isInspectorPresented = true
    @Environment(\.undoManager) private var undoManager
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        PlotPixelmatorWorkspace(
            session: session,
            isInspectorPresented: isInspectorPresented
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.rootBackground)
        .onAppear {
            session.attachUndoManager(undoManager)
        }
        .fileImporter(
            isPresented: bindingForImporter,
            allowedContentTypes: FileTypeCatalog.plotDocumentInputs,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let first = urls.first {
                    session.handleImportedDocument(first)
                }
            case let .failure(error):
                if isUserCancellationError(error) {
                    session.errorMessage = nil
                } else {
                    session.errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: bindingForDataWorkbook) {
            PlotDataWorkbookSheet(session: session)
        }
        .sheet(isPresented: bindingForStyleStudio) {
            PlotStyleStudioSheet(session: session)
        }
    }

    private var bindingForImporter: Binding<Bool> {
        Binding(
            get: { session.isImporterPresented },
            set: { session.isImporterPresented = $0 }
        )
    }

    private var bindingForDataWorkbook: Binding<Bool> {
        Binding(
            get: { session.isDataWorkbookPresented },
            set: { session.isDataWorkbookPresented = $0 }
        )
    }

    private var bindingForStyleStudio: Binding<Bool> {
        Binding(
            get: { session.isStyleStudioPresented },
            set: { session.isStyleStudioPresented = $0 }
        )
    }
}

private struct PlotPixelmatorWorkspace: View {
    @Bindable var session: PlotSession
    let isInspectorPresented: Bool

    var body: some View {
        HStack(spacing: ProWorkspaceMetrics.panelSpacing) {
            PlotSourceTypePanel(session: session)
                .frame(width: ProWorkspaceMetrics.plotSourcePanelWidth)
                .frame(maxHeight: .infinity)
                .padding(.leading, ProWorkspaceMetrics.stagePadding)
                .padding(.vertical, ProWorkspaceMetrics.stagePadding)

            PlotRefineView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, ProWorkspaceMetrics.stagePadding)

            if isInspectorPresented {
                PlotAdjustmentInspector(session: session)
                    .inspectorColumnWidth()
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, ProWorkspaceMetrics.stagePadding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            PlotAdjustmentRail(session: session)
                .frame(width: ProWorkspaceMetrics.adjustmentRailOuterWidth)
                .frame(maxHeight: .infinity)
                .padding(.trailing, 10)
                .padding(.vertical, ProWorkspaceMetrics.stagePadding)
        }
        .animation(MotionTokens.selection, value: isInspectorPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlotSourceTypePanel: View {
    @Bindable var session: PlotSession
    @State private var isPlotTypeChooserPresented = false
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            sheetPicker
                .padding(.horizontal, 12)
                .padding(.top, 12)

            Divider()
                .padding(.horizontal, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Plot Types")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                            Spacer(minLength: 0)

                            Button {
                                isPlotTypeChooserPresented = true
                            } label: {
                                Label("More", systemImage: "square.grid.2x2")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .disabled(session.plotTypeItems.isEmpty)
                            .help("Show every compatible plot type.")
                        }

                        if session.templateGalleryItems.isEmpty {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 24, weight: .regular))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(session.templateGalleryItems) { item in
                                    PlotTypeCard(
                                        item: item,
                                        isSelected: session.effectiveTemplateID == item.id,
                                        action: { choose(item) }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .proGlassPanel(theme: theme)
        .sheet(isPresented: $isPlotTypeChooserPresented) {
            PlotTypeChooserSheet(session: session, isPresented: $isPlotTypeChooserPresented)
        }
    }

    private var sheetPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "tablecells")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Picker("", selection: sheetBinding) {
                ForEach(session.availableSheets, id: \.self) { sheet in
                    Text(sheet.displayName).tag(sheet)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .disabled(session.selectedFileURL == nil || session.availableSheets.count < 2)
            .help(session.selectedFileURL == nil ? "Import data before choosing a sheet." : "Choose the sheet to inspect.")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .proGlassRow(theme: theme, cornerRadius: ProCornerPolicy.row)
    }

    private var sheetBinding: Binding<SheetValue> {
        Binding {
            session.selectedSheet
        } set: { sheet in
            session.setSelectedSheet(sheet)
        }
    }

    private func choose(_ item: PlotTemplateGalleryItem) {
        guard item.selectable else {
            return
        }
        session.chooseTemplate(item.id)
        session.selectPlotAdjustmentCategory(.figure)
    }
}

private struct PlotTypeCard: View {
    let item: PlotTemplateGalleryItem
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        Button(action: action) {
            PlotTemplateRow(
                title: item.title,
                kind: item.thumbnailKind,
                aspectRatio: item.aspectRatio,
                enabled: item.selectable
            )
            .environment(\.plotTemplateRowThumbnailSize, CGSize(width: 84, height: 56))
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: ProWorkspaceMetrics.innerCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!item.availability.isEnabled)
        .help(item.availability.reason ?? item.description ?? "Use \(item.title).")
        .proGlassRow(theme: theme, isSelected: isSelected, cornerRadius: ProCornerPolicy.row)
    }
}

private struct PlotTypeChooserSheet: View {
    @Bindable var session: PlotSession
    @Binding var isPresented: Bool
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search plot types", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.innerCornerRadius, style: .continuous))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredItems) { item in
                            PlotTypeCard(
                                item: item,
                                isSelected: session.effectiveTemplateID == item.id,
                                action: {
                                    guard item.selectable else {
                                        return
                                    }
                                    session.chooseTemplate(item.id)
                                    session.selectPlotAdjustmentCategory(.figure)
                                    isPresented = false
                                }
                            )
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
            .padding(20)
            .navigationTitle("Plot Types")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private var filteredItems: [PlotTemplateGalleryItem] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return session.plotTypeItems
        }
        return session.plotTypeItems.filter { item in
            item.title.lowercased().contains(needle)
                || (item.description ?? "").lowercased().contains(needle)
        }
    }
}

private struct PlotAdjustmentInspector: View {
    @Bindable var session: PlotSession
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        PlotInspectorView(
            session: session,
            adjustmentCategory: session.selectedPlotAdjustmentCategory
        )
        .proGlassPanel(theme: theme)
    }
}

private struct PlotAdjustmentRail: View {
    @Bindable var session: PlotSession
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        VStack(spacing: PlotAdjustmentRailMetrics.itemSpacing) {
            ForEach(PlotAdjustmentCategory.railCategories) { item in
                railButton(item)
            }
            Spacer(minLength: 0)
        }
        .frame(width: PlotAdjustmentRailMetrics.railWidth)
        .padding(.vertical, PlotAdjustmentRailMetrics.verticalPadding)
        .proGlassRail(theme: theme, cornerRadius: PlotAdjustmentRailMetrics.outerCornerRadius)
    }

    private func railButton(_ item: PlotAdjustmentRailItem) -> some View {
        let availability = session.plotAdjustmentAvailability(for: item.category)
        return Button {
            session.selectPlotAdjustmentCategory(item.category)
        } label: {
            Image(systemName: item.category.systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: PlotAdjustmentRailMetrics.itemSize, height: PlotAdjustmentRailMetrics.itemSize)
                .contentShape(RoundedRectangle(cornerRadius: PlotAdjustmentRailMetrics.itemCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(session.selectedPlotAdjustmentCategory == item.category ? Color.accentColor : Color.primary)
        .background {
            if session.selectedPlotAdjustmentCategory == item.category {
                RoundedRectangle(cornerRadius: PlotAdjustmentRailMetrics.itemCornerRadius, style: .continuous)
                    .fill(theme.selectedRowFill)
            }
        }
        .disabled(!availability.isEnabled)
        .help(availability.reason ?? item.category.help)
    }
}

private enum PlotAdjustmentRailMetrics {
    static let railWidth: CGFloat = 44
    static let itemSize: CGFloat = 34
    static let itemSpacing: CGFloat = 4
    static let verticalPadding: CGFloat = 7
    static let outerCornerRadius: CGFloat = ProCornerPolicy.rail
    static let itemCornerRadius: CGFloat = 10
}

private struct PlotStyleStudioSheet: View {
    @Bindable var session: PlotSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomPlotThemePackagePayload
    @State private var selectedThemeID: String?

    init(session: PlotSession) {
        self.session = session
        let current = session.renderOptions.customThemeDraft ?? PlotStyleStudioSheet.makeDraft(from: session)
        _draft = State(initialValue: current)
        _selectedThemeID = State(initialValue: session.renderOptions.customThemeID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                themeList
                    .frame(width: 240)
                Divider()
                previewPane
                    .frame(minWidth: 380)
                Divider()
                controlsPane
                    .frame(width: 360)
            }
        }
        .frame(minWidth: 1040, minHeight: 660)
        .task {
            await session.loadPlotThemes()
        }
        .onChange(of: draft) { _, newValue in
            Task { await session.applyStyleStudioDraft(sanitized(newValue)) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Plot Style Studio")
                .font(.title3.weight(.semibold))
            if session.isPreviewingStyleStudioDraft {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            Button("Preview") {
                Task { await session.applyStyleStudioDraft(sanitized(draft)) }
            }
            .keyboardShortcut("p", modifiers: [.command])
            Button("Update") {
                Task { await session.updateStyleStudioTheme(sanitized(draft)) }
            }
            .disabled(!canUpdateDraft || session.isSavingStyleStudioTheme)
            Button("Save Theme") {
                Task { await session.saveStyleStudioTheme(sanitized(draft)) }
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(session.isSavingStyleStudioTheme)
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var themeList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Themes")
                    .font(.headline)
                Spacer()
                Button {
                    selectedThemeID = nil
                    draft = Self.makeDraft(from: session)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Create a new custom theme.")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(session.plotThemes) { theme in
                        PlotStyleThemeRow(
                            theme: theme,
                            isSelected: selectedThemeID == theme.id,
                            useTheme: {
                                selectedThemeID = theme.id
                                session.applySavedPlotTheme(theme)
                                draft = Self.makeDraft(from: theme, session: session)
                            },
                            duplicateTheme: {
                                selectedThemeID = nil
                                draft = Self.makeDraft(from: theme, session: session)
                            }
                        )
                    }
                }
            }

            Button(role: .destructive) {
                if let selectedThemeID {
                    Task { await session.deleteStyleStudioTheme(id: selectedThemeID) }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedThemeID == nil || selectedTheme?.builtin == true)
            .help(selectedTheme?.builtin == true ? "Built-in themes cannot be deleted." : "Delete the selected user theme.")
        }
        .padding(16)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(0.10), radius: 18, y: 8)

                if let preview = session.previewResponse?.previews.first {
                    if let png = preview.pngBase64 {
                        Base64PreviewImageView(base64PNG: png)
                            .padding(18)
                    } else {
                        Base64PDFPreviewView(base64PDF: preview.pdfBase64)
                            .padding(18)
                    }
                } else {
                    SubtleStageHint(title: "No preview", systemImage: "chart.xyaxis.line")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error = session.styleStudioErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !session.styleStudioWarnings.isEmpty {
                Label(session.styleStudioWarnings.joined(separator: " "), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
    }

    private var controlsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InspectorSection(title: "Package") {
                    AdaptiveInspectorControlRow(title: "Name") {
                        TextField("Name", text: labelBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                    AdaptiveInspectorControlRow(title: "ID") {
                        TextField("user/theme", text: idBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                    if let styles = session.metadata?.styles, !styles.isEmpty {
                        AdaptiveInspectorControlRow(title: "Base") {
                            Picker("", selection: baseStyleBinding) {
                                ForEach(styles) { style in
                                    Text(style.label).tag(style.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                }

                InspectorSection(title: "Typography") {
                    sliderRow(title: "Font", binding: hardNumberBinding("typography", "font_size_pt", fallback: 7.0), range: 5...14, suffix: "pt")
                    sliderRow(title: "Legend", binding: hardNumberBinding("typography", "legend_font_size_pt", fallback: 6.2), range: 5...12, suffix: "pt")
                }

                InspectorSection(title: "Stroke") {
                    sliderRow(title: "Line", binding: hardNumberBinding("stroke", "line_width_pt", fallback: 1.1), range: 0.3...4.0, suffix: "pt")
                    sliderRow(title: "Axis", binding: hardNumberBinding("stroke", "axis_linewidth_pt", fallback: 0.6), range: 0.2...2.0, suffix: "pt")
                }

                InspectorSection(title: "Markers") {
                    sliderRow(title: "Size", binding: hardNumberBinding("stroke", "marker_size_pt", fallback: 4.2), range: 1.0...10.0, suffix: "pt")
                    sliderRow(title: "Alpha", binding: hardNumberBinding("stroke", "marker_alpha", fallback: 0.95), range: 0.1...1.0, suffix: "")
                }

                InspectorSection(title: "Grid") {
                    AdaptiveInspectorControlRow(title: "Visible") {
                        Toggle("", isOn: jsonBoolBinding("axes.grid", fallback: true))
                            .labelsHidden()
                    }
                    sliderRow(title: "Alpha", binding: expertNumberBinding("grid.alpha", fallback: 0.18), range: 0.0...1.0, suffix: "")
                    AdaptiveInspectorControlRow(title: "Style") {
                        Picker("", selection: expertStringBinding("grid.linestyle", fallback: "-")) {
                            Text("Solid").tag("-")
                            Text("Dashed").tag("--")
                            Text("Dotted").tag(":")
                            Text("Dash Dot").tag("-.")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                InspectorSection(title: "Legend") {
                    AdaptiveInspectorControlRow(title: "Frame") {
                        Toggle("", isOn: expertBoolBinding("legend.frameon", fallback: true))
                            .labelsHidden()
                    }
                    AdaptiveInspectorControlRow(title: "Rounded") {
                        Toggle("", isOn: expertBoolBinding("legend.fancybox", fallback: true))
                            .labelsHidden()
                    }
                }

                InspectorSection(title: "Palette") {
                    ForEach(0..<6, id: \.self) { index in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(color(for: paletteColor(at: index)))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                )
                            TextField("#RRGGBB", text: paletteBinding(index))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                InspectorSection(title: "Background") {
                    if let palettes = session.metadata?.palettes, !palettes.isEmpty {
                        AdaptiveInspectorControlRow(title: "Preset") {
                            Picker("", selection: palettePresetBinding) {
                                Text("None").tag("")
                                ForEach(palettes) { palette in
                                    Text(palette.label).tag(palette.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                    if let themes = session.metadata?.visualThemes, !themes.isEmpty {
                        AdaptiveInspectorControlRow(title: "Surface") {
                            Picker("", selection: visualThemeBinding) {
                                Text("Default").tag("")
                                ForEach(themes) { theme in
                                    Text(theme.label).tag(theme.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                }

                InspectorSection(title: "Expert") {
                    AdaptiveInspectorControlRow(title: "Axes Fill") {
                        TextField("axes.facecolor", text: expertStringBinding("axes.facecolor", fallback: ""))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                    }
                    AdaptiveInspectorControlRow(title: "Text") {
                        TextField("text.color", text: expertStringBinding("text.color", fallback: ""))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                    }
                }
            }
            .padding(16)
        }
    }

    private var selectedTheme: PlotThemeSummaryResponse? {
        session.plotThemes.first { $0.id == selectedThemeID }
    }

    private var canUpdateDraft: Bool {
        guard let selectedTheme else {
            return false
        }
        return !selectedTheme.builtin && selectedTheme.id == draft.id
    }

    private var labelBinding: Binding<String> {
        Binding(
            get: { draft.label },
            set: { draft.label = $0 }
        )
    }

    private var idBinding: Binding<String> {
        Binding(
            get: { draft.id },
            set: { draft.id = $0 }
        )
    }

    private var baseStyleBinding: Binding<String> {
        Binding(
            get: { draft.baseStyleID },
            set: { draft.baseStyleID = $0 }
        )
    }

    private var palettePresetBinding: Binding<String> {
        Binding(
            get: { draft.palettePreset ?? "" },
            set: { draft.palettePreset = $0.isEmpty ? nil : $0 }
        )
    }

    private var visualThemeBinding: Binding<String> {
        Binding(
            get: { draft.visualThemeID ?? "" },
            set: { draft.visualThemeID = $0.isEmpty ? nil : $0 }
        )
    }

    private func sliderRow(title: String, binding: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        AdaptiveInspectorControlRow(title: title) {
            HStack(spacing: 8) {
                Slider(value: binding, in: range, step: 0.1)
                    .frame(width: 118)
                Text("\(binding.wrappedValue.formatted(.number.precision(.fractionLength(0...1))))\(suffix)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    private func hardNumberBinding(_ group: String, _ key: String, fallback: Double) -> Binding<Double> {
        Binding(
            get: { draft.hardOverrides[group]?[key]?.numberValue ?? fallback },
            set: { value in
                var values = draft.hardOverrides[group] ?? [:]
                values[key] = .number(value)
                draft.hardOverrides[group] = values
            }
        )
    }

    private func jsonBoolBinding(_ key: String, fallback: Bool) -> Binding<Bool> {
        Binding(
            get: { draft.softOverrides[key]?.boolValue ?? fallback },
            set: { draft.softOverrides[key] = .bool($0) }
        )
    }

    private func expertBoolBinding(_ key: String, fallback: Bool) -> Binding<Bool> {
        Binding(
            get: { draft.expertRcParams[key]?.boolValue ?? fallback },
            set: { draft.expertRcParams[key] = .bool($0) }
        )
    }

    private func expertNumberBinding(_ key: String, fallback: Double) -> Binding<Double> {
        Binding(
            get: { draft.expertRcParams[key]?.numberValue ?? fallback },
            set: { draft.expertRcParams[key] = .number($0) }
        )
    }

    private func expertStringBinding(_ key: String, fallback: String) -> Binding<String> {
        Binding(
            get: { draft.expertRcParams[key]?.stringValue ?? fallback },
            set: { value in
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draft.expertRcParams.removeValue(forKey: key)
                } else {
                    draft.expertRcParams[key] = .string(value)
                }
            }
        )
    }

    private func paletteBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { paletteColor(at: index) },
            set: { value in
                var colors = draft.palette.categorical
                while colors.count <= index {
                    colors.append("")
                }
                colors[index] = value
                draft.palette.categorical = colors
            }
        )
    }

    private func paletteColor(at index: Int) -> String {
        guard draft.palette.categorical.indices.contains(index) else {
            return ""
        }
        return draft.palette.categorical[index]
    }

    private func sanitized(_ package: CustomPlotThemePackagePayload) -> CustomPlotThemePackagePayload {
        var resolved = package
        resolved.id = resolved.id.trimmingCharacters(in: .whitespacesAndNewlines)
        resolved.label = resolved.label.trimmingCharacters(in: .whitespacesAndNewlines)
        resolved.palette.categorical = resolved.palette.categorical
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return resolved
    }

    private static func makeDraft(from session: PlotSession) -> CustomPlotThemePackagePayload {
        let styleID = session.renderOptions.stylePreset
        return CustomPlotThemePackagePayload(
            id: "user/\(safeThemeSuffix(styleID))_custom",
            label: "\(styleID.replacingOccurrences(of: "_", with: " ").capitalized) Custom",
            baseStyleID: styleID,
            palettePreset: session.renderOptions.palettePreset,
            visualThemeID: session.renderOptions.visualThemeID
        )
    }

    private static func makeDraft(from theme: PlotThemeSummaryResponse, session: PlotSession) -> CustomPlotThemePackagePayload {
        let suffix = safeThemeSuffix(theme.id.replacingOccurrences(of: "/", with: "_"))
        return CustomPlotThemePackagePayload(
            id: theme.builtin ? "user/\(suffix)_custom" : theme.id,
            label: theme.builtin ? "\(theme.label) Custom" : theme.label,
            baseStyleID: theme.baseStyleID,
            palettePreset: theme.palettePreset ?? session.renderOptions.palettePreset,
            visualThemeID: theme.visualThemeID ?? session.renderOptions.visualThemeID,
            palette: .init(categorical: theme.swatches)
        )
    }

    private static func safeThemeSuffix(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-"))
        let scalars = value.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        let suffix = scalars.joined().trimmingCharacters(in: CharacterSet(charactersIn: "_.-"))
        return suffix.isEmpty ? "theme" : suffix
    }

    private func color(for hex: String) -> Color {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
            return Color.secondary.opacity(0.12)
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

private struct PlotStyleThemeRow: View {
    let theme: PlotThemeSummaryResponse
    let isSelected: Bool
    let useTheme: () -> Void
    let duplicateTheme: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: useTheme) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(theme.label)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        if theme.builtin {
                            Text("Built-in")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 4) {
                        ForEach(theme.swatches.prefix(5), id: \.self) { swatch in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color(for: swatch))
                                .frame(width: 14, height: 14)
                        }
                        Text(theme.baseStyleID)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 7)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                }
            }

            Button(action: duplicateTheme) {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.borderless)
            .help("Use this theme as the starting point.")
        }
    }

    private func color(for hex: String) -> Color {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
            return Color.secondary.opacity(0.12)
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}
