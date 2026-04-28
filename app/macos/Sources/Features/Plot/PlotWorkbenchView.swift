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
        HStack(spacing: 12) {
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
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 10) {
            sourceHeader
                .padding(.horizontal, 12)
                .padding(.top, 12)

            Divider()
                .padding(.horizontal, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Plot Types")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(filteredPlotTypeItems) { item in
                                PlotTypeButton(item: item, isSelected: session.effectiveTemplateID == item.id) {
                                    guard item.selectable else {
                                        return
                                    }
                                    session.chooseTemplate(item.id)
                                    session.selectPlotAdjustmentCategory(.figure)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Data Tables")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        VStack(spacing: 4) {
                            ForEach(PlotDataWorkbookTab.allCases) { tab in
                                PlotDataWorkbookEntry(
                                    session: session,
                                    tab: tab,
                                    availability: workbookAvailability(for: tab)
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }

            Divider()
                .padding(.horizontal, 12)

            PlotTypeSearchField(text: $searchText)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var sourceHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    session.isImporterPresented = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(.plain)
                .help("Import or Open")

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.selectedSourceFilename ?? "Import or open data")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(session.selectedFileURL == nil ? "CSV, Excel, or project" : session.selectedSheet.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

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
    }

    private var sheetBinding: Binding<SheetValue> {
        Binding {
            session.selectedSheet
        } set: { sheet in
            session.setSelectedSheet(sheet)
        }
    }

    private var filteredPlotTypeItems: [PlotTemplateGalleryItem] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return session.plotTypeItems
        }
        return session.plotTypeItems.filter { item in
            item.title.lowercased().contains(needle)
                || (item.description ?? "").lowercased().contains(needle)
        }
    }

    private func workbookAvailability(for tab: PlotDataWorkbookTab) -> ActionAvailability {
        switch tab {
        case .sourceData, .transformed, .variables:
            return session.dataWorkbookAvailability
        case .fit:
            return session.fitAnalysisAvailability
        }
    }
}

private struct PlotTypeButton: View {
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
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!item.availability.isEnabled)
        .help(item.availability.reason ?? item.description ?? "Use \(item.title).")
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.05))
        }
    }
}

private struct PlotDataWorkbookEntry: View {
    @Bindable var session: PlotSession
    let tab: PlotDataWorkbookTab
    let availability: ActionAvailability

    var body: some View {
        Button {
            session.showDataWorkbook()
            session.selectDataWorkbookTab(tab)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(session.dataWorkbookTab == tab ? Color.accentColor : Color.secondary)
                    .frame(width: 20)

                Text(tab.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 6)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!availability.isEnabled)
        .help(availability.reason ?? "Open \(tab.title).")
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(session.dataWorkbookTab == tab ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.04))
        }
    }

    private var systemImage: String {
        switch tab {
        case .sourceData:
            return "tablecells"
        case .transformed:
            return "line.3.horizontal.decrease.circle"
        case .variables:
            return "number.square"
        case .fit:
            return "point.topleft.down.curvedto.point.bottomright.up"
        }
    }
}

private struct PlotTypeSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: Capsule())
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
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
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
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
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
