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
}

private struct PlotPixelmatorWorkspace: View {
    @Bindable var session: PlotSession
    let isInspectorPresented: Bool

    var body: some View {
        HStack(spacing: ProWorkspaceMetrics.panelSpacing) {
            PlotSourceTypePanel(session: session)
                .frame(width: 278)
                .frame(maxHeight: .infinity)
                .padding(.leading, 12)
                .padding(.vertical, 12)

            PlotRefineView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 12)

            if isInspectorPresented {
                PlotAdjustmentInspector(session: session)
                    .frame(width: 340)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            PlotAdjustmentRail(session: session)
                .frame(width: 54)
                .frame(maxHeight: .infinity)
                .padding(.trailing, 10)
                .padding(.vertical, 12)
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
        .background(theme.rowFill, in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.innerCornerRadius, style: .continuous))
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
        .background {
            RoundedRectangle(cornerRadius: ProWorkspaceMetrics.innerCornerRadius, style: .continuous)
                .fill(isSelected ? theme.selectedRowFill : theme.rowFill)
        }
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
    static let outerCornerRadius: CGFloat = 18
    static let itemCornerRadius: CGFloat = 10
}
