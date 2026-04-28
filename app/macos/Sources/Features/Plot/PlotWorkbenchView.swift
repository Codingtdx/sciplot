import SwiftUI

struct PlotWorkbenchView: View {
    @Bindable var session: PlotSession
    var isInspectorPresented = true
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ZStack(alignment: .topLeading) {
            PlotPixelmatorWorkspace(
                session: session,
                isInspectorPresented: isInspectorPresented
            )

            if let errorMessage = session.errorMessage {
                DiagnosticIssueCard(message: DiagnosticMessage(detail: errorMessage))
                    .padding(14)
                    .frame(maxWidth: 520, alignment: .leading)
                    .transition(MotionTokens.stateTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.96))
        .preferredColorScheme(.dark)
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

private enum ProWorkspaceMetrics {
    static let panelSpacing: CGFloat = 12
    static let outerCornerRadius: CGFloat = 22
    static let innerCornerRadius: CGFloat = 12
}

private struct PlotSourceTypePanel: View {
    @Bindable var session: PlotSession
    @State private var isPlotTypeChooserPresented = false

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
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous)
        )
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
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.innerCornerRadius, style: .continuous))
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
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.05))
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

    var body: some View {
        PlotInspectorView(
            session: session,
            adjustmentCategory: session.selectedPlotAdjustmentCategory
        )
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous)
            )
    }
}

private struct PlotAdjustmentRail: View {
    @Bindable var session: PlotSession

    var body: some View {
        VStack(spacing: 0) {
            ForEach(PlotAdjustmentCategory.railCategories) { item in
                railButton(item)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: ProWorkspaceMetrics.outerCornerRadius, style: .continuous)
        )
    }

    private func railButton(_ item: PlotAdjustmentRailItem) -> some View {
        let availability = session.plotAdjustmentAvailability(for: item.category)
        return Button {
            session.selectPlotAdjustmentCategory(item.category)
        } label: {
            Image(systemName: item.category.systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(session.selectedPlotAdjustmentCategory == item.category ? Color.accentColor : Color.primary)
        .background {
            if session.selectedPlotAdjustmentCategory == item.category {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
            }
        }
        .disabled(!availability.isEnabled)
        .help(availability.reason ?? item.category.help)
    }
}
