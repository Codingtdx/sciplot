import CoreGraphics
import CoreTransferable
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ComposerSession {
    typealias ComposerExportFormatChooser = @MainActor () -> ExportGraphicFormat?
    typealias ComposerExportDestinationChooser = @MainActor (_ suggestedName: String, _ format: ExportGraphicFormat) -> URL?
    typealias ComposerExportMaterializer = @MainActor (_ intermediatePDFURL: URL, _ destinationURL: URL) throws -> Void

    @ObservationIgnored private var client: (any SidecarClienting)?
    @ObservationIgnored private weak var undoManager: UndoManager?
    @ObservationIgnored private var runtimeState = RuntimeState()
    @ObservationIgnored private let asyncCoordination = AsyncCoordination()
    @ObservationIgnored private let previewDelayNanoseconds: UInt64
    @ObservationIgnored private let chooseExportFormat: ComposerExportFormatChooser
    @ObservationIgnored private let chooseExportDestination: ComposerExportDestinationChooser
    @ObservationIgnored private let materializeExport: ComposerExportMaterializer

    var project = ComposerRequestPayload()
    var previewResponse: ComposerPreviewResponse?
    var exportURL: URL?
    var errorMessage: String?
    var focusedPanelID: String?
    var selectedRegionID: String?
    var selectedCells: Set<ComposerGridCell> = []
    var pendingImportKind: ComposerImportKind = .graph
    var isImportMenuPresented = false
    var isImportPresented = false
    var isGuidePresented = false
    var isPreviewing = false
    var isExporting = false
    var activeDragPanelID: String?

    var exportAvailability: ActionAvailability {
        if isExporting {
            return .disabled("Export is already in progress.")
        }
        guard client != nil else {
            return .disabled("The sidecar is not ready yet.")
        }
        guard !project.panels.isEmpty else {
            return .disabled("Import at least one panel before exporting.")
        }
        return .enabled()
    }

    var latestExportItems: [ExportedFileItem] {
        guard let exportURL else {
            return []
        }
        return [ExportedFileItem(url: exportURL)]
    }

    init(
        previewDelayNanoseconds: UInt64 = 300_000_000,
        chooseExportFormat: @escaping ComposerExportFormatChooser = {
            NativeExportCoordinator.chooseComposerExportFormat()
        },
        chooseExportDestination: @escaping ComposerExportDestinationChooser = {
            NativeExportCoordinator.chooseComposerExportLocation(suggestedName: $0, format: $1)
        },
        materializeExport: @escaping ComposerExportMaterializer = {
            try NativeExportCoordinator.materializeComposerExport(
                intermediatePDFURL: $0,
                destinationURL: $1
            )
        }
    ) {
        self.previewDelayNanoseconds = previewDelayNanoseconds
        self.chooseExportFormat = chooseExportFormat
        self.chooseExportDestination = chooseExportDestination
        self.materializeExport = materializeExport
    }

    var selectedPanelID: String? {
        get { focusedPanelID }
        set { focusedPanelID = newValue }
    }

    var orderedPanels: [ComposerPanelPayload] {
        project.panels
    }

    var visibleBoardPanels: [ComposerPanelPayload] {
        project.panels.filter { !$0.hidden && placementTarget(for: $0) != nil }
    }

    var selectedPanel: ComposerPanelPayload? {
        panelByID(focusedPanelID)
    }

    var selectedRegion: ComposerRegionPayload? {
        guard let selectedRegionID else {
            return nil
        }
        return project.regions.first { $0.id == selectedRegionID }
    }

    var selectedFreeRegion: ComposerRegionPayload? {
        guard let region = selectedRegion, region.kind == "free" else {
            return nil
        }
        return region
    }

    var selectedCellSelection: ComposerCellSelection? {
        rectangularSelection(from: selectedCells)
    }

    var selectedPlacementTarget: ComposerPlacementTarget? {
        if let region = selectedFreeRegion {
            return .freeRegion(region.id)
        }
        guard let selection = selectedCellSelection else {
            return nil
        }
        if selection.cellCount == 1 {
            return .cell(selection.origin)
        }
        return .graphSpan(
            origin: selection.origin,
            colSpan: selection.colSpan,
            rowSpan: selection.rowSpan
        )
    }

    var boardQuickActionState: ComposerBoardQuickActionState? {
        if let selection = selectedCellSelection,
           selection.cellCount > 1,
           canMergeSelectedCells {
            return .mergeableMultiCellSelection(selection)
        }
        if let region = selectedFreeRegion,
           canUnmergeSelectedRegion {
            return .emptyMergedRegion(region)
        }
        return nil
    }

    var activePlacementPanelID: String? {
        activeDragPanelID ?? focusedPanelID
    }

    var activePlacementPanel: ComposerPanelPayload? {
        panelByID(activePlacementPanelID)
    }

    var allGridCells: [ComposerGridCell] {
        (0 ..< project.layoutGrid.rows).flatMap { row in
            (0 ..< project.layoutGrid.columns).map { col in
                ComposerGridCell(col: col, row: row)
            }
        }
    }

    var canMergeSelectedCells: Bool {
        guard let selection = selectedCellSelection, selection.cellCount > 1 else {
            return false
        }
        return selection.cells.allSatisfy { isCellMergeable($0) }
    }

    var canUnmergeSelectedRegion: Bool {
        guard let region = selectedFreeRegion, !region.locked else {
            return false
        }
        return regionOccupants(regionID: region.id).isEmpty
    }

    var canPlaceFocusedPanelInSelectedTarget: Bool {
        guard let panelID = focusedPanelID, let target = selectedPlacementTarget else {
            return false
        }
        return canPlace(panelID: panelID, in: target)
    }

    var mergeGuidance: String {
        DerivedState.mergeGuidance(
            selectedCells: selectedCells,
            selectedCellSelection: selectedCellSelection,
            canMergeSelectedCells: canMergeSelectedCells
        )
    }

    var placementGuidance: String {
        DerivedState.placementGuidance(
            selectedPanel: selectedPanel,
            selectedPlacementTarget: selectedPlacementTarget,
            canPlaceInTarget: { panelID, target in
                canPlace(panelID: panelID, in: target)
            }
        )
    }

    var placementActionTitle: String {
        guard let panel = selectedPanel else {
            return "Place Here"
        }
        return panel.hidden ? "Place Here" : "Move Here"
    }

    func configure(client: any SidecarClienting) {
        self.client = client
        schedulePreview()
    }

    func attachUndoManager(_ undoManager: UndoManager?) {
        self.undoManager = undoManager
    }

    func showImportMenu() {
        isImportMenuPresented = true
    }

    func beginImport(kind: ComposerImportKind) {
        isImportMenuPresented = false
        pendingImportKind = kind
        isImportPresented = true
    }

    func showGuide() {
        isGuidePresented = true
    }

    func dismissGuide() {
        isGuidePresented = false
    }

    func handleImportedAssets(_ urls: [URL]) async {
        guard let client else {
            return
        }

        do {
            let previous = project
            let previousPanelIDs = Set(previous.panels.map(\.id))
            let response = try await client.importComposerPanels(
                .init(
                    project: project,
                    filePaths: urls.map(\.path),
                    kind: pendingImportKind.rawValue
                )
            )

            var candidate = response
            let importedPanelIDs = Set(candidate.panels.map(\.id)).subtracting(previousPanelIDs)
            let reflowed = reflowVisiblePanels(in: &candidate)
            if !reflowed {
                hidePanels(withIDs: importedPanelIDs, in: &candidate)
                _ = reflowVisiblePanels(in: &candidate)
                errorMessage = importedPanelIDs.isEmpty
                    ? "The current board layout cannot fit the requested panel sequence."
                    : "Some imported panels could not fit the current board layout and were kept off the board."
            } else {
                errorMessage = nil
            }

            syncPanelZIndices(in: &candidate)
            project = candidate
            exportURL = nil
            clearTargetSelection()
            focusedPanelID = candidate.panels.last?.id
            registerUndo(previousProject: previous, actionName: "Import Panels")
            schedulePreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportComposition() async {
        guard let client else {
            return
        }

        guard let exportFormat = chooseExportFormat() else {
            return
        }
        guard let destinationURL = chooseExportDestination(
            suggestedComposerExportFilename(format: exportFormat),
            exportFormat
        ) else {
            return
        }

        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let response = try await client.composeExport(project)
            let intermediateURL = URL(fileURLWithPath: response.outputPath)
            try materializeExport(intermediateURL, destinationURL)
            exportURL = destinationURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealLatestExport() {
        if let exportURL {
            WorkspaceBridge.reveal([exportURL])
        }
    }

    func openLatestExport(id: String) {
        guard let item = latestExportItems.first(where: { $0.id == id }) else {
            return
        }
        WorkspaceBridge.open(item.url)
    }

    private func suggestedComposerExportFilename(format: ExportGraphicFormat) -> String {
        if let exportURL {
            return NativeExportCoordinator.suggestedGraphicFilename(
                from: exportURL.lastPathComponent,
                format: format
            )
        }
        return NativeExportCoordinator.suggestedGraphicFilename(
            from: "composer-composition",
            format: format
        )
    }

    func focusPanel(_ panelID: String?) {
        focusedPanelID = panelID
    }

    func selectPanelOnCanvas(_ panelID: String?) {
        focusedPanelID = panelID
        clearTargetSelection()
    }

    func clearTransientEditingState() {
        focusedPanelID = nil
        activeDragPanelID = nil
        clearTargetSelection()
    }

    func beginPanelDrag(_ panelID: String) {
        guard let panel = panelByID(panelID), !panel.locked else {
            return
        }
        activeDragPanelID = panelID
        focusedPanelID = panelID
    }

    func endPanelDrag(_ panelID: String? = nil) {
        guard panelID == nil || activeDragPanelID == panelID else {
            return
        }
        activeDragPanelID = nil
    }

    func movePanels(fromOffsets: IndexSet, toOffset: Int) {
        guard !fromOffsets.isEmpty else {
            return
        }

        let previous = project
        var candidate = project
        candidate.panels.move(fromOffsets: fromOffsets, toOffset: toOffset)
        guard reflowVisiblePanels(in: &candidate) else {
            errorMessage = "The current board layout cannot fit the requested panel sequence."
            return
        }
        syncPanelZIndices(in: &candidate)
        commitProject(candidate, previousProject: previous, actionName: "Reorder Panels")
    }

    func updateCellSelection(_ cell: ComposerGridCell, additive: Bool, extend: Bool) {
        if extend, let selectionAnchorCell = runtimeState.selectionAnchorCell {
            selectedCells = Set(rectangularCells(from: selectionAnchorCell, to: cell))
        } else if additive {
            if selectedCells.contains(cell) {
                selectedCells.remove(cell)
            } else {
                selectedCells.insert(cell)
            }
            runtimeState.selectionAnchorCell = runtimeState.selectionAnchorCell ?? cell
        } else {
            selectedCells = [cell]
            runtimeState.selectionAnchorCell = cell
        }
        selectedRegionID = nil
    }

    func beginCellDragSelection(at cell: ComposerGridCell) {
        selectedCells = [cell]
        runtimeState.selectionAnchorCell = cell
        selectedRegionID = nil
    }

    func updateCellDragSelection(to cell: ComposerGridCell) {
        guard let selectionAnchorCell = runtimeState.selectionAnchorCell else {
            beginCellDragSelection(at: cell)
            return
        }
        selectedCells = Set(rectangularCells(from: selectionAnchorCell, to: cell))
        selectedRegionID = nil
    }

    func extendCellSelection(to cell: ComposerGridCell) {
        updateCellSelection(cell, additive: false, extend: true)
    }

    func toggleCellSelection(_ cell: ComposerGridCell) {
        updateCellSelection(cell, additive: true, extend: false)
    }

    func toggleCellSelection(_ cell: ComposerGridCell, additive: Bool) {
        updateCellSelection(cell, additive: additive, extend: false)
    }

    func selectRegion(_ regionID: String?) {
        selectedRegionID = regionID
        selectedCells.removeAll()
        runtimeState.selectionAnchorCell = nil
    }

    func clearTargetSelection() {
        selectedRegionID = nil
        selectedCells.removeAll()
        runtimeState.selectionAnchorCell = nil
    }

    func setAutoLabels(_ enabled: Bool) {
        mutateProject(actionName: "Toggle Auto Labels") { project in
            project.autoLabels = enabled
        }
    }

    func updateSelectedPanel(label: String) {
        guard let selectedPanelID else { return }
        mutateProject(actionName: "Edit Panel Label") { project in
            guard let index = project.panels.firstIndex(where: { $0.id == selectedPanelID }) else {
                return
            }
            project.panels[index].label = label.isEmpty ? nil : label
        }
    }

    func updateSelectedPanel(hidden: Bool) {
        guard let selectedPanelID else { return }
        if hidden {
            removePanelFromBoard(selectedPanelID)
            return
        }

        let previous = project
        var candidate = project
        guard let index = candidate.panels.firstIndex(where: { $0.id == selectedPanelID }) else {
            return
        }
        candidate.panels[index].hidden = false
        guard reflowVisiblePanels(in: &candidate) else {
            errorMessage = "The current board layout cannot fit this panel on the board."
            return
        }
        syncPanelZIndices(in: &candidate)
        commitProject(candidate, previousProject: previous, actionName: "Show Panel")
    }

    func updateSelectedPanel(locked: Bool) {
        guard let selectedPanelID else { return }
        mutateProject(actionName: "Toggle Panel Lock") { project in
            guard let index = project.panels.firstIndex(where: { $0.id == selectedPanelID }) else {
                return
            }
            project.panels[index].locked = locked
        }
    }

    func removeSelectedPanelFromBoard() {
        guard let selectedPanelID else {
            return
        }
        removePanelFromBoard(selectedPanelID)
    }

    func mergeSelectedCells() {
        guard let selection = selectedCellSelection, canMergeSelectedCells else {
            return
        }

        let previous = project
        var candidate = project
        let newRegionID = nextAvailableID(prefix: "region", existing: candidate.regions.map(\.id))
        candidate.regions.append(
            ComposerRegionPayload(
                id: newRegionID,
                kind: "free",
                col: selection.origin.col,
                row: selection.origin.row,
                colSpan: selection.colSpan,
                rowSpan: selection.rowSpan,
                label: nil,
                locked: false,
                slotKind: nil
            )
        )
        commitProject(candidate, previousProject: previous, actionName: "Merge Cells")
        selectedRegionID = newRegionID
        selectedCells.removeAll()
        runtimeState.selectionAnchorCell = nil
    }

    func unmergeSelectedRegion() {
        guard let region = selectedFreeRegion, canUnmergeSelectedRegion else {
            return
        }

        let previous = project
        var candidate = project
        candidate.regions.removeAll { $0.id == region.id }
        for index in candidate.texts.indices where candidate.texts[index].regionID == region.id {
            candidate.texts[index].regionID = nil
        }
        commitProject(candidate, previousProject: previous, actionName: "Unmerge Region")
        selectedRegionID = nil
    }

    func placeFocusedPanelInSelectedTarget() {
        guard let panelID = focusedPanelID, let target = selectedPlacementTarget else {
            return
        }
        place(panelID: panelID, in: target)
    }

    func place(panelID: String, in target: ComposerPlacementTarget) {
        guard canPlace(panelID: panelID, in: target) else {
            return
        }

        let previous = project
        var candidate = project
        let occupantID = occupantPanelID(at: target, in: candidate, excluding: [panelID])
        let sourceTarget = placementTarget(forPanelID: panelID, in: candidate)

        if let occupantID {
            guard let sourceTarget else {
                errorMessage = "Only panels already on the board can swap positions."
                return
            }
            applyPlacement(panelID: panelID, to: target, in: &candidate)
            applyPlacement(panelID: occupantID, to: sourceTarget, in: &candidate)
        } else {
            applyPlacement(panelID: panelID, to: target, in: &candidate)
        }

        rewriteCanonicalOrderFromBoard(in: &candidate)
        syncPanelZIndices(in: &candidate)
        commitProject(candidate, previousProject: previous, actionName: "Move Panel")
        focusedPanelID = panelID
        activeDragPanelID = nil
        clearTargetSelection()
    }

    func canPlace(panelID: String, in target: ComposerPlacementTarget) -> Bool {
        guard let panel = panelByID(panelID), !panel.locked else {
            return false
        }
        if !isStructurallyCompatible(panel: panel, with: target, in: project) {
            return false
        }

        let occupantID = occupantPanelID(at: target, in: project, excluding: [panelID])
        let sourceTarget = placementTarget(forPanelID: panelID, in: project)

        if let occupantID {
            guard let occupant = panelByID(occupantID), !occupant.locked,
                  let sourceTarget
            else {
                return false
            }
            guard isStructurallyCompatible(panel: occupant, with: sourceTarget, in: project) else {
                return false
            }
            return targetIsAvailable(target, in: project, excluding: [panelID, occupantID]) &&
                targetIsAvailable(sourceTarget, in: project, excluding: [panelID, occupantID])
        }

        return targetIsAvailable(target, in: project, excluding: [panelID])
    }

    func graphCompatibleTargets(for panelID: String) -> [ComposerPlacementTarget] {
        guard let panel = panelByID(panelID), panel.kind == "graph" else {
            return []
        }
        let span = graphSpan(for: panel, in: project)
        guard span.colSpan > 1 || span.rowSpan > 1 else {
            return []
        }

        let maxCol = max(0, project.layoutGrid.columns - span.colSpan)
        let maxRow = max(0, project.layoutGrid.rows - span.rowSpan)
        var targets: [ComposerPlacementTarget] = []

        for row in 0 ... maxRow {
            for col in 0 ... maxCol {
                let target = ComposerPlacementTarget.graphSpan(
                    origin: ComposerGridCell(col: col, row: row),
                    colSpan: span.colSpan,
                    rowSpan: span.rowSpan
                )
                if isStructurallyCompatible(panel: panel, with: target, in: project) {
                    targets.append(target)
                }
            }
        }
        return targets
    }

    func placementSummary(for panel: ComposerPanelPayload) -> String {
        if panel.hidden {
            return "Off Board"
        }
        switch placementTarget(for: panel) {
        case let .freeRegion(regionID):
            guard let region = regionByID(regionID) else {
                return "Merged Region"
            }
            return "Merged region \(regionSummary(region))"
        case let .cell(cell):
            return "Cell \(cellDisplayLabel(cell))"
        case let .graphSpan(origin, colSpan, rowSpan):
            if colSpan == 1, rowSpan == 1 {
                return "Cell \(cellDisplayLabel(origin))"
            }
            let trailingCell = ComposerGridCell(col: origin.col + colSpan - 1, row: origin.row + rowSpan - 1)
            return "\(cellDisplayLabel(origin))-\(cellDisplayLabel(trailingCell))"
        case nil:
            return "Off Board"
        }
    }

    func resolvedLabel(for panel: ComposerPanelPayload) -> String {
        guard panel.kind == "graph" else {
            return panel.label ?? ""
        }
        if !project.autoLabels {
            return panel.label ?? ""
        }
        let orderedGraphPanels = project.panels.filter {
            !$0.hidden && $0.kind == "graph" && placementTarget(for: $0) != nil
        }
        guard let index = orderedGraphPanels.firstIndex(where: { $0.id == panel.id }) else {
            return panel.label ?? ""
        }
        guard let scalar = UnicodeScalar(65 + index) else {
            return panel.label ?? ""
        }
        return String(scalar)
    }

    func cellRectMm(for cell: ComposerGridCell) -> CGRect {
        cellRectMm(for: cell, in: project)
    }

    func panelRectMm(for panel: ComposerPanelPayload) -> CGRect {
        CGRect(x: panel.xMm, y: panel.yMm, width: panel.wMm, height: panel.hMm)
    }

    func regionRectMm(for region: ComposerRegionPayload) -> CGRect {
        regionRectMm(for: region, in: project)
    }

    func targetRectMm(for target: ComposerPlacementTarget) -> CGRect? {
        switch target {
        case let .cell(cell):
            return cellRectMm(for: cell, in: project)
        case let .freeRegion(regionID):
            guard let region = regionByID(regionID) else {
                return nil
            }
            return regionRectMm(for: region, in: project)
        case let .graphSpan(origin, colSpan, rowSpan):
            let selection = ComposerCellSelection(origin: origin, colSpan: colSpan, rowSpan: rowSpan)
            return rectMm(for: selection, in: project)
        }
    }

    func boardQuickActionRectMm(for state: ComposerBoardQuickActionState) -> CGRect? {
        switch state {
        case let .mergeableMultiCellSelection(selection):
            return targetRectMm(
                for: .graphSpan(
                    origin: selection.origin,
                    colSpan: selection.colSpan,
                    rowSpan: selection.rowSpan
                )
            )
        case let .emptyMergedRegion(region):
            return regionRectMm(for: region)
        }
    }

    func regionCovering(cell: ComposerGridCell) -> ComposerRegionPayload? {
        project.regions.first { region in
            let cells = cells(for: region)
            return cells.contains(cell)
        }
    }

    func panelForRegion(_ regionID: String) -> ComposerPanelPayload? {
        project.panels.first { !$0.hidden && $0.regionID == regionID }
    }

    func placementTargetForPanelID(_ panelID: String) -> ComposerPlacementTarget? {
        placementTarget(forPanelID: panelID, in: project)
    }

    func panelsAssigned(to regionID: String) -> [ComposerPanelPayload] {
        project.panels.filter { !$0.hidden && $0.regionID == regionID }
    }

    func regionSummary(_ region: ComposerRegionPayload) -> String {
        let origin = ComposerGridCell(col: region.col, row: region.row)
        if region.colSpan == 1, region.rowSpan == 1 {
            return cellDisplayLabel(origin)
        }
        let trailingCell = ComposerGridCell(
            col: region.col + region.colSpan - 1,
            row: region.row + region.rowSpan - 1
        )
        return "\(cellDisplayLabel(origin))-\(cellDisplayLabel(trailingCell)) (\(region.colSpan)x\(region.rowSpan))"
    }

    func cellDisplayLabel(_ cell: ComposerGridCell) -> String {
        let columnScalar = UnicodeScalar(65 + cell.col).map(String.init) ?? "?"
        return "\(columnScalar)\(cell.row + 1)"
    }

    func schedulePreview() {
        asyncCoordination.preview.schedule(delayNanoseconds: previewDelayNanoseconds) { [weak self] revision in
            guard let self else { return }
            await self.requestPreview(revision: revision)
        }
    }

    private func requestPreview(revision: Int) async {
        guard let client else {
            return
        }

        isPreviewing = true
        defer {
            if asyncCoordination.preview.isLatest(revision) {
                isPreviewing = false
            }
        }

        do {
            let response = try await client.composePreview(project)
            guard asyncCoordination.preview.isLatest(revision), !Task.isCancelled else {
                return
            }
            previewResponse = response
            errorMessage = nil
        } catch {
            guard asyncCoordination.preview.isLatest(revision), !Task.isCancelled else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func mutateProject(actionName: String, mutation: (inout ComposerRequestPayload) -> Void) {
        let previous = project
        mutation(&project)
        exportURL = nil
        errorMessage = nil
        registerUndo(previousProject: previous, actionName: actionName)
        schedulePreview()
    }

    private func commitProject(
        _ nextProject: ComposerRequestPayload,
        previousProject: ComposerRequestPayload,
        actionName: String
    ) {
        project = nextProject
        exportURL = nil
        errorMessage = nil
        registerUndo(previousProject: previousProject, actionName: actionName)
        schedulePreview()
    }

    private func registerUndo(previousProject: ComposerRequestPayload, actionName: String) {
        guard let undoManager else {
            return
        }

        let currentProject = project
        undoManager.registerUndo(withTarget: self) { session in
            session.project = previousProject
            session.registerUndo(previousProject: currentProject, actionName: actionName)
            session.exportURL = nil
            session.schedulePreview()
        }
        undoManager.setActionName(actionName)
    }

    private func rectangularSelection(from cells: Set<ComposerGridCell>) -> ComposerCellSelection? {
        guard !cells.isEmpty else {
            return nil
        }

        let columns = cells.map(\.col)
        let rows = cells.map(\.row)
        guard let minCol = columns.min(),
              let maxCol = columns.max(),
              let minRow = rows.min(),
              let maxRow = rows.max()
        else {
            return nil
        }

        let expectedCount = (maxCol - minCol + 1) * (maxRow - minRow + 1)
        guard expectedCount == cells.count else {
            return nil
        }

        let selection = ComposerCellSelection(
            origin: ComposerGridCell(col: minCol, row: minRow),
            colSpan: maxCol - minCol + 1,
            rowSpan: maxRow - minRow + 1
        )
        return Set(selection.cells) == cells ? selection : nil
    }

    private func rectangularCells(from start: ComposerGridCell, to end: ComposerGridCell) -> [ComposerGridCell] {
        let minCol = min(start.col, end.col)
        let maxCol = max(start.col, end.col)
        let minRow = min(start.row, end.row)
        let maxRow = max(start.row, end.row)
        return (minRow ... maxRow).flatMap { row in
            (minCol ... maxCol).map { col in
                ComposerGridCell(col: col, row: row)
            }
        }
    }

    private func panelByID(_ panelID: String?) -> ComposerPanelPayload? {
        guard let panelID else {
            return nil
        }
        return project.panels.first { $0.id == panelID }
    }

    private func panelByID(_ panelID: String?, in project: ComposerRequestPayload) -> ComposerPanelPayload? {
        guard let panelID else {
            return nil
        }
        return project.panels.first { $0.id == panelID }
    }

    private func graphSpan(
        for panel: ComposerPanelPayload,
        in project: ComposerRequestPayload
    ) -> (colSpan: Int, rowSpan: Int, slotKind: String?) {
        if let regionID = panel.regionID,
           let region = regionByID(regionID, in: project),
           region.kind == "graph"
        {
            return (region.colSpan, region.rowSpan, region.slotKind)
        }
        let colSpan = max(1, Int(round(panel.wMm / project.layoutGrid.cellWidthMm)))
        let rowSpan = max(1, Int(round(panel.hMm / project.layoutGrid.cellHeightMm)))
        let slotKind = (colSpan == 1 && rowSpan == 2) ? "structure" : nil
        return (colSpan, rowSpan, slotKind)
    }

    private func regionByID(_ regionID: String) -> ComposerRegionPayload? {
        project.regions.first { $0.id == regionID }
    }

    private func regionByID(_ regionID: String, in project: ComposerRequestPayload) -> ComposerRegionPayload? {
        project.regions.first { $0.id == regionID }
    }

    private func regionRectMm(for region: ComposerRegionPayload, in project: ComposerRequestPayload) -> CGRect {
        CGRect(
            x: project.layoutGrid.frameXMm + Double(region.col) * project.layoutGrid.cellWidthMm,
            y: project.layoutGrid.frameYMm + Double(region.row) * project.layoutGrid.cellHeightMm,
            width: Double(region.colSpan) * project.layoutGrid.cellWidthMm,
            height: Double(region.rowSpan) * project.layoutGrid.cellHeightMm
        )
    }

    private func cellRectMm(for cell: ComposerGridCell, in project: ComposerRequestPayload) -> CGRect {
        CGRect(
            x: project.layoutGrid.frameXMm + Double(cell.col) * project.layoutGrid.cellWidthMm,
            y: project.layoutGrid.frameYMm + Double(cell.row) * project.layoutGrid.cellHeightMm,
            width: project.layoutGrid.cellWidthMm,
            height: project.layoutGrid.cellHeightMm
        )
    }

    private func rectMm(for selection: ComposerCellSelection, in project: ComposerRequestPayload) -> CGRect {
        CGRect(
            x: project.layoutGrid.frameXMm + Double(selection.origin.col) * project.layoutGrid.cellWidthMm,
            y: project.layoutGrid.frameYMm + Double(selection.origin.row) * project.layoutGrid.cellHeightMm,
            width: Double(selection.colSpan) * project.layoutGrid.cellWidthMm,
            height: Double(selection.rowSpan) * project.layoutGrid.cellHeightMm
        )
    }

    private func cellMatchingPanel(_ panel: ComposerPanelPayload, in project: ComposerRequestPayload) -> ComposerGridCell? {
        let tolerance = 0.25
        let cells = (0 ..< project.layoutGrid.rows).flatMap { row in
            (0 ..< project.layoutGrid.columns).map { col in
                ComposerGridCell(col: col, row: row)
            }
        }
        for cell in cells {
            let rect = cellRectMm(for: cell, in: project)
            if abs(panel.xMm - rect.minX) <= tolerance,
               abs(panel.yMm - rect.minY) <= tolerance,
               abs(panel.wMm - rect.width) <= tolerance,
               abs(panel.hMm - rect.height) <= tolerance {
                return cell
            }
        }
        return nil
    }

    private func placementTarget(for panel: ComposerPanelPayload) -> ComposerPlacementTarget? {
        placementTarget(for: panel, in: project)
    }

    private func placementTarget(forPanelID panelID: String, in project: ComposerRequestPayload) -> ComposerPlacementTarget? {
        guard let panel = panelByID(panelID, in: project) else {
            return nil
        }
        return placementTarget(for: panel, in: project)
    }

    private func placementTarget(for panel: ComposerPanelPayload, in project: ComposerRequestPayload) -> ComposerPlacementTarget? {
        guard !panel.hidden else {
            return nil
        }
        if let regionID = panel.regionID, let region = regionByID(regionID, in: project) {
            if region.kind == "free" {
                return .freeRegion(region.id)
            }
            if region.colSpan == 1, region.rowSpan == 1 {
                return .cell(.init(col: region.col, row: region.row))
            }
            return .graphSpan(
                origin: .init(col: region.col, row: region.row),
                colSpan: region.colSpan,
                rowSpan: region.rowSpan
            )
        }
        if let matchedCell = cellMatchingPanel(panel, in: project) {
            return .cell(matchedCell)
        }
        return nil
    }

    private func cells(for region: ComposerRegionPayload) -> [ComposerGridCell] {
        (region.row ..< region.row + region.rowSpan).flatMap { row in
            (region.col ..< region.col + region.colSpan).map { col in
                ComposerGridCell(col: col, row: row)
            }
        }
    }

    private func cells(for target: ComposerPlacementTarget, in project: ComposerRequestPayload) -> [ComposerGridCell] {
        switch target {
        case let .cell(cell):
            return [cell]
        case let .freeRegion(regionID):
            guard let region = regionByID(regionID, in: project) else {
                return []
            }
            return cells(for: region)
        case let .graphSpan(origin, colSpan, rowSpan):
            return ComposerCellSelection(origin: origin, colSpan: colSpan, rowSpan: rowSpan).cells
        }
    }

    private func freeRegions(in project: ComposerRequestPayload) -> [ComposerRegionPayload] {
        project.regions
            .filter { $0.kind == "free" }
            .sorted { lhs, rhs in
                if lhs.row != rhs.row { return lhs.row < rhs.row }
                if lhs.col != rhs.col { return lhs.col < rhs.col }
                return lhs.id < rhs.id
            }
    }

    private func structuralBlockedCells(in project: ComposerRequestPayload) -> Set<ComposerGridCell> {
        Set(freeRegions(in: project).flatMap(cells(for:)))
    }

    private func panelOccupiedCells(panelID: String? = nil, in project: ComposerRequestPayload, excluding excludedPanelIDs: Set<String>) -> Set<ComposerGridCell> {
        let occupiedCells: [ComposerGridCell] = project.panels
            .filter { !$0.hidden && !excludedPanelIDs.contains($0.id) && (panelID == nil || $0.id == panelID) }
            .flatMap { panel in
                guard let target = placementTarget(for: panel, in: project) else {
                    return [ComposerGridCell]()
                }
                switch target {
                case .freeRegion:
                    return []
                default:
                    return cells(for: target, in: project)
                }
            }
        return Set(occupiedCells)
    }

    private func targetIsAvailable(
        _ target: ComposerPlacementTarget,
        in project: ComposerRequestPayload,
        excluding excludedPanelIDs: Set<String>
    ) -> Bool {
        switch target {
        case let .freeRegion(regionID):
            guard let region = regionByID(regionID, in: project),
                  region.kind == "free",
                  !region.locked
            else {
                return false
            }
            return regionOccupants(regionID: regionID, in: project, excluding: excludedPanelIDs).isEmpty
        case .cell, .graphSpan:
            let structuralBlocked = structuralBlockedCells(in: project)
            let occupied = panelOccupiedCells(in: project, excluding: excludedPanelIDs)
            let targetCells = Set(cells(for: target, in: project))
            return structuralBlocked.isDisjoint(with: targetCells) && occupied.isDisjoint(with: targetCells)
        }
    }

    private func isStructurallyCompatible(
        panel: ComposerPanelPayload,
        with target: ComposerPlacementTarget,
        in project: ComposerRequestPayload
    ) -> Bool {
        switch target {
        case .cell:
            if panel.kind != "graph" {
                return true
            }
            let span = graphSpan(for: panel, in: project)
            return span.colSpan == 1 && span.rowSpan == 1
        case let .freeRegion(regionID):
            guard panel.kind == "asset",
                  let region = regionByID(regionID, in: project)
            else {
                return false
            }
            return region.kind == "free"
        case let .graphSpan(_, colSpan, rowSpan):
            guard panel.kind == "graph" else {
                return false
            }
            let span = graphSpan(for: panel, in: project)
            return span.colSpan == colSpan && span.rowSpan == rowSpan
        }
    }

    private func occupantPanelID(
        at target: ComposerPlacementTarget,
        in project: ComposerRequestPayload,
        excluding excludedPanelIDs: Set<String>
    ) -> String? {
        project.panels.first { panel in
            guard !panel.hidden, !excludedPanelIDs.contains(panel.id) else {
                return false
            }
            return placementTarget(for: panel, in: project) == target
        }?.id
    }

    private func regionOccupants(regionID: String, in project: ComposerRequestPayload? = nil, excluding excludedPanelIDs: Set<String> = []) -> [ComposerPanelPayload] {
        let activeProject = project ?? self.project
        return activeProject.panels.filter { !$0.hidden && $0.regionID == regionID && !excludedPanelIDs.contains($0.id) }
    }

    private func isCellMergeable(_ cell: ComposerGridCell) -> Bool {
        regionCovering(cell: cell) == nil &&
            occupantPanelID(at: .cell(cell), in: project, excluding: []) == nil
    }

    private func nextAvailableID(prefix: String, existing: [String]) -> String {
        var candidate = 1
        let taken = Set(existing)
        while taken.contains("\(prefix)-\(candidate)") {
            candidate += 1
        }
        return "\(prefix)-\(candidate)"
    }

    private func syncPanelZIndices(in project: inout ComposerRequestPayload) {
        for index in project.panels.indices {
            project.panels[index].zIndex = index
        }
    }

    private func hidePanels(withIDs panelIDs: Set<String>, in project: inout ComposerRequestPayload) {
        guard !panelIDs.isEmpty else {
            return
        }
        for index in project.panels.indices where panelIDs.contains(project.panels[index].id) {
            hidePanel(at: index, in: &project)
        }
    }

    private func hidePanel(at index: Int, in project: inout ComposerRequestPayload) {
        let regionID = project.panels[index].regionID
        project.panels[index].hidden = true
        project.panels[index].regionID = nil
        if project.panels[index].kind == "graph", let regionID {
            project.regions.removeAll { $0.kind == "graph" && $0.id == regionID }
        }
    }

    private func removePanelFromBoard(_ panelID: String) {
        guard let panel = panelByID(panelID), !panel.locked else {
            return
        }

        let previous = project
        var candidate = project
        guard let index = candidate.panels.firstIndex(where: { $0.id == panelID }) else {
            return
        }
        hidePanel(at: index, in: &candidate)
        _ = reflowVisiblePanels(in: &candidate)
        rewriteCanonicalOrderFromBoard(in: &candidate)
        syncPanelZIndices(in: &candidate)
        commitProject(candidate, previousProject: previous, actionName: "Remove From Board")
        focusedPanelID = panelID
        clearTargetSelection()
    }

    private func firstAvailableGraphSelection(
        for panel: ComposerPanelPayload,
        in project: ComposerRequestPayload,
        occupiedCells: Set<ComposerGridCell>
    ) -> ComposerCellSelection? {
        let span = graphSpan(for: panel, in: project)
        let maxCol = max(0, project.layoutGrid.columns - span.colSpan)
        let maxRow = max(0, project.layoutGrid.rows - span.rowSpan)
        let structuralBlocked = structuralBlockedCells(in: project)

        for row in 0 ... maxRow {
            for col in 0 ... maxCol {
                let selection = ComposerCellSelection(
                    origin: ComposerGridCell(col: col, row: row),
                    colSpan: span.colSpan,
                    rowSpan: span.rowSpan
                )
                let selectionCells = Set(selection.cells)
                if structuralBlocked.isDisjoint(with: selectionCells),
                   occupiedCells.isDisjoint(with: selectionCells) {
                    return selection
                }
            }
        }

        return nil
    }

    private func firstAvailableAssetTarget(
        in project: ComposerRequestPayload,
        occupiedCells: Set<ComposerGridCell>,
        usedFreeRegionIDs: Set<String>
    ) -> ComposerPlacementTarget? {
        let blockedCells = structuralBlockedCells(in: project)
        var rankedTargets: [(row: Int, col: Int, target: ComposerPlacementTarget)] = []

        for region in freeRegions(in: project) where !region.locked && !usedFreeRegionIDs.contains(region.id) {
            rankedTargets.append((row: region.row, col: region.col, target: .freeRegion(region.id)))
        }

        for row in 0 ..< project.layoutGrid.rows {
            for col in 0 ..< project.layoutGrid.columns {
                let cell = ComposerGridCell(col: col, row: row)
                guard !blockedCells.contains(cell), !occupiedCells.contains(cell) else {
                    continue
                }
                rankedTargets.append((row: row, col: col, target: .cell(cell)))
            }
        }

        rankedTargets.sort {
            if $0.row != $1.row { return $0.row < $1.row }
            if $0.col != $1.col { return $0.col < $1.col }
            switch ($0.target, $1.target) {
            case (.freeRegion, .cell):
                return true
            case (.cell, .freeRegion):
                return false
            default:
                return false
            }
        }
        return rankedTargets.first?.target
    }

    private func reflowVisiblePanels(in project: inout ComposerRequestPayload) -> Bool {
        let sourceProject = project
        let visiblePanelIDs = sourceProject.panels.filter { !$0.hidden }.map(\.id)
        let freeRegionTargets = freeRegions(in: sourceProject)
        let previousTargets: [String: ComposerPlacementTarget] = Dictionary(
            uniqueKeysWithValues: visiblePanelIDs.compactMap { panelID in
                guard let panel = panelByID(panelID, in: sourceProject),
                      let target = placementTarget(for: panel, in: sourceProject)
                else {
                    return nil
                }
                return (panelID, target)
            }
        )

        var candidate = project
        candidate.regions = freeRegionTargets
        var occupiedCells = structuralBlockedCells(in: candidate)
        var usedFreeRegionIDs: Set<String> = []

        for index in candidate.panels.indices {
            if candidate.panels[index].hidden {
                candidate.panels[index].regionID = nil
            } else {
                candidate.panels[index].regionID = nil
            }
        }

        for panelID in visiblePanelIDs {
            guard let panelIndex = candidate.panels.firstIndex(where: { $0.id == panelID }) else {
                return false
            }

            let sourcePanel = sourceProject.panels[panelIndex]
            if sourcePanel.kind == "graph" {
                guard let selection = firstAvailableGraphSelection(
                    for: sourcePanel,
                    in: sourceProject,
                    occupiedCells: occupiedCells
                ) else {
                    return false
                }
                applyPlacement(panelID: panelID, to: selection.cellCount == 1 ? .cell(selection.origin) : .graphSpan(
                    origin: selection.origin,
                    colSpan: selection.colSpan,
                    rowSpan: selection.rowSpan
                ), in: &candidate)
                occupiedCells.formUnion(selection.cells)
            } else {
                guard let target = firstAvailableAssetTarget(
                    in: candidate,
                    occupiedCells: occupiedCells,
                    usedFreeRegionIDs: usedFreeRegionIDs
                ) else {
                    return false
                }
                applyPlacement(panelID: panelID, to: target, in: &candidate)
                switch target {
                case let .freeRegion(regionID):
                    usedFreeRegionIDs.insert(regionID)
                case let .cell(cell):
                    occupiedCells.insert(cell)
                case .graphSpan:
                    break
                }
            }
        }

        for panel in sourceProject.panels where !panel.hidden && panel.locked {
            if placementTarget(forPanelID: panel.id, in: candidate) != previousTargets[panel.id] {
                return false
            }
        }

        project = candidate
        return true
    }

    private func applyPlacement(
        panelID: String,
        to target: ComposerPlacementTarget,
        in project: inout ComposerRequestPayload
    ) {
        guard let panelIndex = project.panels.firstIndex(where: { $0.id == panelID }) else {
            return
        }

        let previousRegionID = project.panels[panelIndex].regionID
        if project.panels[panelIndex].kind == "graph", let previousRegionID {
            project.regions.removeAll { $0.kind == "graph" && $0.id == previousRegionID }
        }

        project.panels[panelIndex].hidden = false
        project.panels[panelIndex].slotID = nil

        switch target {
        case let .cell(cell):
            if project.panels[panelIndex].kind == "graph" {
                let span = graphSpan(for: project.panels[panelIndex], in: project)
                let regionID = previousRegionID ?? nextAvailableID(prefix: "region", existing: project.regions.map(\.id))
                let region = ComposerRegionPayload(
                    id: regionID,
                    kind: "graph",
                    col: cell.col,
                    row: cell.row,
                    colSpan: span.colSpan,
                    rowSpan: span.rowSpan,
                    label: nil,
                    locked: false,
                    slotKind: span.slotKind
                )
                project.regions.append(region)
                let rect = regionRectMm(for: region, in: project)
                project.panels[panelIndex].regionID = region.id
                project.panels[panelIndex].xMm = rect.minX
                project.panels[panelIndex].yMm = rect.minY
                project.panels[panelIndex].wMm = rect.width
                project.panels[panelIndex].hMm = rect.height
            } else {
                let rect = cellRectMm(for: cell, in: project)
                project.panels[panelIndex].regionID = nil
                project.panels[panelIndex].xMm = rect.minX
                project.panels[panelIndex].yMm = rect.minY
                project.panels[panelIndex].wMm = rect.width
                project.panels[panelIndex].hMm = rect.height
            }
        case let .freeRegion(regionID):
            guard let region = regionByID(regionID, in: project) else {
                return
            }
            let rect = regionRectMm(for: region, in: project)
            project.panels[panelIndex].regionID = region.id
            project.panels[panelIndex].xMm = rect.minX
            project.panels[panelIndex].yMm = rect.minY
            project.panels[panelIndex].wMm = rect.width
            project.panels[panelIndex].hMm = rect.height
        case let .graphSpan(origin, colSpan, rowSpan):
            let span = graphSpan(for: project.panels[panelIndex], in: project)
            guard span.colSpan == colSpan, span.rowSpan == rowSpan else {
                return
            }
            let regionID = previousRegionID ?? nextAvailableID(prefix: "region", existing: project.regions.map(\.id))
            let region = ComposerRegionPayload(
                id: regionID,
                kind: "graph",
                col: origin.col,
                row: origin.row,
                colSpan: colSpan,
                rowSpan: rowSpan,
                label: nil,
                locked: false,
                slotKind: span.slotKind
            )
            project.regions.append(region)
            let rect = regionRectMm(for: region, in: project)
            project.panels[panelIndex].regionID = region.id
            project.panels[panelIndex].xMm = rect.minX
            project.panels[panelIndex].yMm = rect.minY
            project.panels[panelIndex].wMm = rect.width
            project.panels[panelIndex].hMm = rect.height
        }
    }

    private func rewriteCanonicalOrderFromBoard(in project: inout ComposerRequestPayload) {
        let hiddenPanels = project.panels.filter(\.hidden)
        let visiblePanels = project.panels.filter { !$0.hidden }
        let orderedVisible = visiblePanels.sorted { lhs, rhs in
            boardOrderingKey(for: lhs, in: project) < boardOrderingKey(for: rhs, in: project)
        }
        let hiddenIDs = Set(hiddenPanels.map(\.id))
        project.panels = orderedVisible + project.panels.filter { hiddenIDs.contains($0.id) }
    }

    private func boardOrderingKey(for panel: ComposerPanelPayload, in project: ComposerRequestPayload) -> ComposerBoardOrderingKey {
        switch placementTarget(for: panel, in: project) {
        case let .cell(cell):
            return ComposerBoardOrderingKey(row: cell.row, col: cell.col, area: 1, panelID: panel.id)
        case let .freeRegion(regionID):
            if let region = regionByID(regionID, in: project) {
                return ComposerBoardOrderingKey(
                    row: region.row,
                    col: region.col,
                    area: region.colSpan * region.rowSpan,
                    panelID: panel.id
                )
            }
        case let .graphSpan(origin, colSpan, rowSpan):
            return ComposerBoardOrderingKey(
                row: origin.row,
                col: origin.col,
                area: colSpan * rowSpan,
                panelID: panel.id
            )
        case nil:
            break
        }
        return ComposerBoardOrderingKey(row: .max, col: .max, area: .max, panelID: panel.id)
    }
}

private extension ComposerSession {
    struct RuntimeState {
        var selectionAnchorCell: ComposerGridCell?
    }

    @MainActor
    final class AsyncCoordination {
        let preview = AsyncLatestTaskCoordinator()
    }

    enum DerivedState {
        static func mergeGuidance(
            selectedCells: Set<ComposerGridCell>,
            selectedCellSelection: ComposerCellSelection?,
            canMergeSelectedCells: Bool
        ) -> String {
            guard !selectedCells.isEmpty else {
                return "Select adjacent empty cells on the 3x3 grid to merge them into one region."
            }
            guard let selection = selectedCellSelection else {
                return "Use a rectangular cell selection for merge."
            }
            guard selection.cellCount > 1 else {
                return "A single cell is selected. Add adjacent cells if you want to merge."
            }
            guard canMergeSelectedCells else {
                return "Merge requires an empty rectangular selection with no existing panel or merged-region coverage."
            }
            return "This \(selection.colSpan)x\(selection.rowSpan) selection can be merged into one free region."
        }

        static func placementGuidance(
            selectedPanel: ComposerPanelPayload?,
            selectedPlacementTarget: ComposerPlacementTarget?,
            canPlaceInTarget: (_ panelID: String, _ target: ComposerPlacementTarget) -> Bool
        ) -> String {
            guard let panel = selectedPanel else {
                return "Select a panel from the Library or the board, then choose a target cell or merged region."
            }
            if panel.hidden {
                return "This panel is off the board. Select a target and place it back into the composition."
            }
            if panel.locked {
                return "Unlock this panel before moving it on the board."
            }
            guard let target = selectedPlacementTarget else {
                return "Drag the panel directly, or select a destination cell / region to move it there."
            }
            return canPlaceInTarget(panel.id, target)
                ? "This destination is valid."
                : "That destination is not valid for the selected panel."
        }
    }
}
