import CoreGraphics
import CoreTransferable
import Foundation
import Observation
import UniformTypeIdentifiers

struct ComposerGridCell: Hashable, Identifiable, Sendable {
    let col: Int
    let row: Int

    var id: String { "\(col)-\(row)" }
}

struct ComposerCellSelection: Equatable, Hashable, Sendable {
    let origin: ComposerGridCell
    let colSpan: Int
    let rowSpan: Int

    var cells: [ComposerGridCell] {
        (origin.row ..< origin.row + rowSpan).flatMap { row in
            (origin.col ..< origin.col + colSpan).map { col in
                ComposerGridCell(col: col, row: row)
            }
        }
    }

    var cellCount: Int { colSpan * rowSpan }
}

enum ComposerImportKind: String, CaseIterable, Identifiable {
    case graph
    case asset

    var id: String { rawValue }
}

enum ComposerPanelSourceSurface: String, Codable, Sendable {
    case library
    case canvas
}

enum ComposerPlacementTarget: Hashable, Sendable {
    case cell(ComposerGridCell)
    case freeRegion(String)
    case graphSpan(origin: ComposerGridCell, colSpan: Int, rowSpan: Int)

    var selection: ComposerCellSelection? {
        switch self {
        case let .cell(cell):
            return ComposerCellSelection(origin: cell, colSpan: 1, rowSpan: 1)
        case let .graphSpan(origin, colSpan, rowSpan):
            return ComposerCellSelection(origin: origin, colSpan: colSpan, rowSpan: rowSpan)
        case .freeRegion:
            return nil
        }
    }
}

struct ComposerPanelDragPayload: Codable, Hashable, Sendable, Transferable {
    let panelID: String
    let sourceSurface: ComposerPanelSourceSurface

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .composerPanelDragPayload)
    }
}

extension UTType {
    static let composerPanelDragPayload = UTType(exportedAs: "com.codegod.composer-panel-drag")
}

@MainActor
@Observable
final class ComposerSession {
    @ObservationIgnored private var client: (any SidecarClienting)?
    @ObservationIgnored private weak var undoManager: UndoManager?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private let previewDelayNanoseconds: UInt64

    var project = ComposerRequestPayload()
    var previewResponse: ComposerPreviewResponse?
    var exportURL: URL?
    var errorMessage: String?
    var focusedPanelID: String?
    var selectedRegionID: String?
    var selectedCells: Set<ComposerGridCell> = []
    var pendingImportKind: ComposerImportKind = .graph
    var isImportPresented = false
    var isGuidePresented = false
    var isPreviewing = false
    var isExporting = false
    var armedReplacementPanelID: String?
    var activeDragPanelID: String?

    init(previewDelayNanoseconds: UInt64 = 300_000_000) {
        self.previewDelayNanoseconds = previewDelayNanoseconds
    }

    var selectedPanelID: String? {
        get { focusedPanelID }
        set { focusedPanelID = newValue }
    }

    var orderedPanels: [ComposerPanelPayload] {
        project.panels
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

    var activePlacementPanelID: String? {
        activeDragPanelID ?? armedReplacementPanelID
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
        return cellsAreAvailable(Set(selection.cells))
    }

    var canUnmergeSelectedRegion: Bool {
        guard let region = selectedFreeRegion else {
            return false
        }
        return !region.locked
    }

    var canPlaceFocusedPanelInSelectedTarget: Bool {
        guard let panelID = focusedPanelID, let target = selectedPlacementTarget else {
            return false
        }
        return canPlace(panelID: panelID, in: target)
    }

    var mergeGuidance: String {
        guard !selectedCells.isEmpty else {
            return "Select adjacent cells on the 3x3 grid to merge them into one free region."
        }
        guard let selection = selectedCellSelection else {
            return "Use a rectangular cell selection for merge actions."
        }
        guard selection.cellCount > 1 else {
            return "A single cell is ready for placement. Select more cells if you want to merge."
        }
        guard cellsAreAvailable(Set(selection.cells)) else {
            return "Merge is available only for empty cells that are not already covered by another region."
        }
        return "This \(selection.colSpan)x\(selection.rowSpan) selection can be merged into one free region."
    }

    var placementGuidance: String {
        guard let panel = selectedPanel else {
            if let armedReplacementPanelID, let replacementPanel = panelByID(armedReplacementPanelID) {
                return "Replace mode is armed for \(replacementPanel.kind == "graph" ? "this graph" : "this asset"). Click or drop onto a valid target."
            }
            return "Choose a panel from the library or canvas to place it into the grid."
        }

        if panel.locked {
            return "Unlock this panel before moving or reassigning it."
        }

        guard let target = selectedPlacementTarget else {
            if armedReplacementPanelID == panel.id {
                return "Replace mode is armed. Choose a valid cell, merged region, or graph span."
            }
            return "Select a cell or merged region to place the focused panel."
        }

        switch target {
        case let .freeRegion(regionID):
            guard let region = regionByID(regionID) else {
                return "Select a valid merged region."
            }
            if region.locked {
                return "Unlock this merged region before placing an asset into it or unmerging it."
            }
            if panel.kind == "graph" {
                return "Graphs stay tied to graph regions. Select a matching graph span instead of a free merged region."
            }
            return "Place this asset into the selected merged region."
        case let .cell(cell):
            if panel.kind == "graph" {
                let requiredSpan = graphSpan(for: panel)
                if requiredSpan.colSpan != 1 || requiredSpan.rowSpan != 1 {
                    return "This graph needs a \(requiredSpan.colSpan)x\(requiredSpan.rowSpan) graph span."
                }
                return canPlace(panelID: panel.id, in: target)
                    ? "Move this graph into \(cellDisplayLabel(cell))."
                    : "That cell is already occupied."
            }
            return "Place this asset into \(cellDisplayLabel(cell))."
        case let .graphSpan(origin, colSpan, rowSpan):
            if panel.kind != "graph" {
                return "Assets can snap into cells or merged regions. Merge this selection first if you want a shared free region."
            }

            let requiredSpan = graphSpan(for: panel)
            if requiredSpan.colSpan != colSpan || requiredSpan.rowSpan != rowSpan {
                return "This graph needs a \(requiredSpan.colSpan)x\(requiredSpan.rowSpan) graph span."
            }

            let trailingCell = ComposerGridCell(col: origin.col + colSpan - 1, row: origin.row + rowSpan - 1)
            let summary = "\(cellDisplayLabel(origin))-\(cellDisplayLabel(trailingCell))"
            return canPlace(panelID: panel.id, in: target)
                ? "Move this graph into \(summary)."
                : "Those target cells are already occupied."
        }
    }

    var placementActionTitle: String {
        guard let panel = selectedPanel else {
            return "Place Panel"
        }
        if armedReplacementPanelID == panel.id {
            return "Replace At Selection"
        }
        if panel.kind == "graph" {
            return "Move Graph Into Selection"
        }
        if selectedFreeRegion != nil {
            return "Place Asset In Region"
        }
        return "Place Asset In Cell"
    }

    func configure(client: any SidecarClienting) {
        self.client = client
        schedulePreview()
    }

    func attachUndoManager(_ undoManager: UndoManager?) {
        self.undoManager = undoManager
    }

    func beginImport(kind: ComposerImportKind) {
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
            let response = try await client.importComposerPanels(
                .init(
                    project: project,
                    filePaths: urls.map(\.path),
                    kind: pendingImportKind.rawValue
                )
            )
            let previous = project
            project = response
            exportURL = nil
            errorMessage = nil
            clearTargetSelection()
            armedReplacementPanelID = nil
            activeDragPanelID = nil
            focusedPanelID = project.panels.last?.id
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

        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let response = try await client.composeExport(project)
            exportURL = URL(fileURLWithPath: response.outputPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealLatestExport() {
        if let exportURL {
            WorkspaceBridge.reveal([exportURL])
        }
    }

    func focusPanel(_ panelID: String?) {
        if armedReplacementPanelID != panelID {
            armedReplacementPanelID = nil
        }
        focusedPanelID = panelID
    }

    func selectPanelOnCanvas(_ panelID: String?) {
        if armedReplacementPanelID != panelID {
            armedReplacementPanelID = nil
        }
        focusedPanelID = panelID
        clearTargetSelection()
    }

    func beginReplacingSelectedPanel() {
        guard let selectedPanelID else {
            return
        }
        beginReplacement(for: selectedPanelID)
    }

    func beginReplacement(for panelID: String) {
        guard let panel = panelByID(panelID), !panel.locked else {
            return
        }
        focusedPanelID = panelID
        clearTargetSelection()
        armedReplacementPanelID = panelID
    }

    func isReplacementArmed(for panelID: String) -> Bool {
        armedReplacementPanelID == panelID
    }

    func clearTransientEditingState() {
        focusedPanelID = nil
        armedReplacementPanelID = nil
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
        mutateProject(actionName: "Reorder Panels") { project in
            project.panels.move(fromOffsets: fromOffsets, toOffset: toOffset)
        }
    }

    func toggleCellSelection(_ cell: ComposerGridCell, additive: Bool) {
        if additive {
            if selectedCells.contains(cell) {
                selectedCells.remove(cell)
            } else {
                selectedCells.insert(cell)
            }
        } else {
            selectedCells = [cell]
        }
        selectedRegionID = nil
    }

    func selectRegion(_ regionID: String?) {
        selectedRegionID = regionID
        selectedCells.removeAll()
    }

    func clearTargetSelection() {
        selectedRegionID = nil
        selectedCells.removeAll()
    }

    func setAutoLabels(_ enabled: Bool) {
        mutateProject(actionName: "Toggle Auto Labels") { project in
            project.autoLabels = enabled
        }
    }

    func updateSelectedPanel(label: String) {
        mutateProject(actionName: "Edit Panel Label") { project in
            guard let index = project.panels.firstIndex(where: { $0.id == focusedPanelID }) else {
                return
            }
            project.panels[index].label = label.isEmpty ? nil : label
        }
    }

    func updateSelectedPanel(hidden: Bool) {
        mutateProject(actionName: "Toggle Panel Visibility") { project in
            guard let index = project.panels.firstIndex(where: { $0.id == focusedPanelID }) else {
                return
            }
            project.panels[index].hidden = hidden
        }
    }

    func updateSelectedPanel(locked: Bool) {
        mutateProject(actionName: "Toggle Panel Lock") { project in
            guard let index = project.panels.firstIndex(where: { $0.id == focusedPanelID }) else {
                return
            }
            project.panels[index].locked = locked
        }
    }

    func mergeSelectedCells() {
        guard let selection = selectedCellSelection, canMergeSelectedCells else {
            return
        }

        let newRegionID = nextAvailableID(prefix: "region", existing: project.regions.map(\.id))
        mutateProject(actionName: "Merge Cells") { project in
            project.regions.append(
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
        }
        selectedRegionID = newRegionID
        selectedCells.removeAll()
    }

    func unmergeSelectedRegion() {
        guard let region = selectedFreeRegion, !region.locked else {
            return
        }

        let regionID = region.id
        mutateProject(actionName: "Unmerge Region") { project in
            project.regions.removeAll { $0.id == regionID }
            for index in project.panels.indices where project.panels[index].regionID == regionID {
                project.panels[index].regionID = nil
            }
            for index in project.texts.indices where project.texts[index].regionID == regionID {
                project.texts[index].regionID = nil
            }
        }
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

        switch target {
        case let .cell(cell):
            guard let panel = panelByID(panelID) else {
                return
            }
            if panel.kind == "graph" {
                placeGraph(
                    panelID: panelID,
                    in: ComposerCellSelection(origin: cell, colSpan: 1, rowSpan: 1)
                )
            } else {
                placeAsset(panelID: panelID, in: cell)
            }
        case let .freeRegion(regionID):
            guard let region = regionByID(regionID) else {
                return
            }
            placeAsset(panelID: panelID, in: region)
        case let .graphSpan(origin, colSpan, rowSpan):
            placeGraph(
                panelID: panelID,
                in: ComposerCellSelection(origin: origin, colSpan: colSpan, rowSpan: rowSpan)
            )
        }

        focusedPanelID = panelID
        armedReplacementPanelID = nil
        activeDragPanelID = nil
        clearTargetSelection()
    }

    func canPlace(panelID: String, in target: ComposerPlacementTarget) -> Bool {
        guard let panel = panelByID(panelID), !panel.locked else {
            return false
        }

        switch target {
        case let .cell(cell):
            if panel.kind == "graph" {
                let requiredSpan = graphSpan(for: panel)
                guard requiredSpan.colSpan == 1, requiredSpan.rowSpan == 1 else {
                    return false
                }
            }
            return cellsAreAvailable(Set([cell]), allowingRegionID: panel.regionID)
        case let .freeRegion(regionID):
            guard panel.kind == "asset",
                  let region = regionByID(regionID),
                  region.kind == "free",
                  !region.locked
            else {
                return false
            }
            return true
        case let .graphSpan(origin, colSpan, rowSpan):
            guard panel.kind == "graph" else {
                return false
            }
            let requiredSpan = graphSpan(for: panel)
            guard requiredSpan.colSpan == colSpan, requiredSpan.rowSpan == rowSpan else {
                return false
            }
            let selection = ComposerCellSelection(origin: origin, colSpan: colSpan, rowSpan: rowSpan)
            return cellsAreAvailable(Set(selection.cells), allowingRegionID: panel.regionID)
        }
    }

    func graphCompatibleTargets(for panelID: String) -> [ComposerPlacementTarget] {
        guard let panel = panelByID(panelID), panel.kind == "graph" else {
            return []
        }

        let span = graphSpan(for: panel)
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
                if canPlace(panelID: panelID, in: target) {
                    targets.append(target)
                }
            }
        }
        return targets
    }

    func releaseFocusedAssetFromRegion() {
        guard let panel = selectedPanel, panel.kind == "asset", panel.regionID != nil else {
            return
        }

        mutateProject(actionName: "Release Asset From Region") { project in
            guard let index = project.panels.firstIndex(where: { $0.id == panel.id }) else {
                return
            }
            project.panels[index].regionID = nil
        }
    }

    func placementSummary(for panel: ComposerPanelPayload) -> String {
        if panel.kind == "graph", let region = regionForPanel(panel) {
            return regionSummary(region)
        }
        if let regionID = panel.regionID, let region = regionByID(regionID) {
            return "Merged region \(regionSummary(region))"
        }
        if let matchedCell = cellMatchingPanel(panel) {
            return "Cell \(cellDisplayLabel(matchedCell))"
        }
        return "Free placement"
    }

    func resolvedLabel(for panel: ComposerPanelPayload) -> String {
        let graphPanels = project.panels.filter { $0.kind == "graph" }
        if !project.autoLabels {
            return panel.label ?? ""
        }

        let ordered = graphPanels.sorted {
            if $0.yMm != $1.yMm { return $0.yMm < $1.yMm }
            if $0.xMm != $1.xMm { return $0.xMm < $1.xMm }
            return $0.id < $1.id
        }

        guard let index = ordered.firstIndex(where: { $0.id == panel.id }) else {
            return panel.label ?? ""
        }

        let scalar = UnicodeScalar(65 + index).map(String.init)
        return scalar ?? panel.label ?? ""
    }

    func cellRectMm(for cell: ComposerGridCell) -> CGRect {
        let grid = project.layoutGrid
        return CGRect(
            x: grid.frameXMm + Double(cell.col) * grid.cellWidthMm,
            y: grid.frameYMm + Double(cell.row) * grid.cellHeightMm,
            width: grid.cellWidthMm,
            height: grid.cellHeightMm
        )
    }

    func panelRectMm(for panel: ComposerPanelPayload) -> CGRect {
        CGRect(
            x: panel.xMm,
            y: panel.yMm,
            width: panel.wMm,
            height: panel.hMm
        )
    }

    func regionRectMm(for region: ComposerRegionPayload) -> CGRect {
        let grid = project.layoutGrid
        return CGRect(
            x: grid.frameXMm + Double(region.col) * grid.cellWidthMm,
            y: grid.frameYMm + Double(region.row) * grid.cellHeightMm,
            width: Double(region.colSpan) * grid.cellWidthMm,
            height: Double(region.rowSpan) * grid.cellHeightMm
        )
    }

    func targetRectMm(for target: ComposerPlacementTarget) -> CGRect? {
        switch target {
        case let .cell(cell):
            return cellRectMm(for: cell)
        case let .freeRegion(regionID):
            guard let region = regionByID(regionID) else {
                return nil
            }
            return regionRectMm(for: region)
        case let .graphSpan(origin, colSpan, rowSpan):
            let selection = ComposerCellSelection(origin: origin, colSpan: colSpan, rowSpan: rowSpan)
            let first = cellRectMm(for: selection.origin)
            return CGRect(
                x: first.minX,
                y: first.minY,
                width: Double(colSpan) * project.layoutGrid.cellWidthMm,
                height: Double(rowSpan) * project.layoutGrid.cellHeightMm
            )
        }
    }

    func regionCovering(cell: ComposerGridCell) -> ComposerRegionPayload? {
        project.regions.first { region in
            cell.col >= region.col &&
                cell.col < region.col + region.colSpan &&
                cell.row >= region.row &&
                cell.row < region.row + region.rowSpan
        }
    }

    func panelForRegion(_ regionID: String) -> ComposerPanelPayload? {
        project.panels.first { $0.regionID == regionID }
    }

    func panelsAssigned(to regionID: String) -> [ComposerPanelPayload] {
        project.panels.filter { $0.regionID == regionID }
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
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(nanoseconds: self.previewDelayNanoseconds)
            await self.requestPreview()
        }
    }

    private func requestPreview() async {
        guard let client else {
            return
        }

        isPreviewing = true
        defer { isPreviewing = false }

        do {
            previewResponse = try await client.composePreview(project)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mutateProject(actionName: String, mutation: (inout ComposerRequestPayload) -> Void) {
        let previous = project
        mutation(&project)
        exportURL = nil
        registerUndo(previousProject: previous, actionName: actionName)
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

        guard Set(selection.cells) == cells else {
            return nil
        }
        return selection
    }

    private func panelByID(_ panelID: String?) -> ComposerPanelPayload? {
        guard let panelID else {
            return nil
        }
        return project.panels.first { $0.id == panelID }
    }

    private func graphSpan(
        for panel: ComposerPanelPayload,
        in project: ComposerRequestPayload? = nil
    ) -> (colSpan: Int, rowSpan: Int, slotKind: String?) {
        let activeProject = project ?? self.project

        if let region = regionForPanel(panel, in: activeProject) {
            return (region.colSpan, region.rowSpan, region.slotKind)
        }

        let grid = activeProject.layoutGrid
        let colSpan = max(1, Int(round(panel.wMm / grid.cellWidthMm)))
        let rowSpan = max(1, Int(round(panel.hMm / grid.cellHeightMm)))
        let slotKind = (colSpan == 1 && rowSpan == 2) ? "structure" : nil
        return (colSpan, rowSpan, slotKind)
    }

    private func regionForPanel(
        _ panel: ComposerPanelPayload,
        in project: ComposerRequestPayload? = nil
    ) -> ComposerRegionPayload? {
        guard let regionID = panel.regionID else {
            return nil
        }
        return regionByID(regionID, in: project)
    }

    private func regionByID(
        _ regionID: String,
        in project: ComposerRequestPayload? = nil
    ) -> ComposerRegionPayload? {
        let activeProject = project ?? self.project
        return activeProject.regions.first { $0.id == regionID }
    }

    private func cellsAreAvailable(_ cells: Set<ComposerGridCell>, allowingRegionID: String? = nil) -> Bool {
        for cell in cells {
            if let region = regionCovering(cell: cell), region.id != allowingRegionID {
                return false
            }
        }
        return true
    }

    private func placeGraph(panelID: String, in selection: ComposerCellSelection) {
        let targetRect = CGRect(
            x: project.layoutGrid.frameXMm + Double(selection.origin.col) * project.layoutGrid.cellWidthMm,
            y: project.layoutGrid.frameYMm + Double(selection.origin.row) * project.layoutGrid.cellHeightMm,
            width: Double(selection.colSpan) * project.layoutGrid.cellWidthMm,
            height: Double(selection.rowSpan) * project.layoutGrid.cellHeightMm
        )

        mutateProject(actionName: "Move Graph Panel") { project in
            guard let panelIndex = project.panels.firstIndex(where: { $0.id == panelID }) else {
                return
            }

            let span = graphSpan(for: project.panels[panelIndex], in: project)
            if let regionID = project.panels[panelIndex].regionID,
               let regionIndex = project.regions.firstIndex(where: { $0.id == regionID }) {
                project.regions[regionIndex].kind = "graph"
                project.regions[regionIndex].col = selection.origin.col
                project.regions[regionIndex].row = selection.origin.row
                project.regions[regionIndex].colSpan = span.colSpan
                project.regions[regionIndex].rowSpan = span.rowSpan
                project.regions[regionIndex].slotKind = span.slotKind
            } else {
                let regionID = nextAvailableID(prefix: "region", existing: project.regions.map(\.id))
                project.regions.append(
                    ComposerRegionPayload(
                        id: regionID,
                        kind: "graph",
                        col: selection.origin.col,
                        row: selection.origin.row,
                        colSpan: span.colSpan,
                        rowSpan: span.rowSpan,
                        label: nil,
                        locked: false,
                        slotKind: span.slotKind
                    )
                )
                project.panels[panelIndex].regionID = regionID
            }

            project.panels[panelIndex].kind = "graph"
            project.panels[panelIndex].xMm = targetRect.minX
            project.panels[panelIndex].yMm = targetRect.minY
            project.panels[panelIndex].wMm = targetRect.width
            project.panels[panelIndex].hMm = targetRect.height
        }
    }

    private func placeAsset(panelID: String, in region: ComposerRegionPayload) {
        let rect = regionRectMm(for: region)
        mutateProject(actionName: "Place Asset") { project in
            guard let panelIndex = project.panels.firstIndex(where: { $0.id == panelID }) else {
                return
            }
            project.panels[panelIndex].regionID = region.id
            project.panels[panelIndex].xMm = rect.minX
            project.panels[panelIndex].yMm = rect.minY
            project.panels[panelIndex].wMm = rect.width
            project.panels[panelIndex].hMm = rect.height
        }
    }

    private func placeAsset(panelID: String, in cell: ComposerGridCell) {
        let rect = cellRectMm(for: cell)
        mutateProject(actionName: "Place Asset") { project in
            guard let panelIndex = project.panels.firstIndex(where: { $0.id == panelID }) else {
                return
            }
            project.panels[panelIndex].regionID = nil
            project.panels[panelIndex].xMm = rect.minX
            project.panels[panelIndex].yMm = rect.minY
            project.panels[panelIndex].wMm = rect.width
            project.panels[panelIndex].hMm = rect.height
        }
    }

    private func cellMatchingPanel(_ panel: ComposerPanelPayload) -> ComposerGridCell? {
        let tolerance = 0.25

        for cell in allGridCells {
            let rect = cellRectMm(for: cell)
            if abs(panel.xMm - rect.minX) <= tolerance,
               abs(panel.yMm - rect.minY) <= tolerance,
               abs(panel.wMm - rect.width) <= tolerance,
               abs(panel.hMm - rect.height) <= tolerance {
                return cell
            }
        }

        return nil
    }

    private func nextAvailableID(prefix: String, existing: [String]) -> String {
        var candidate = 1
        let taken = Set(existing)
        while taken.contains("\(prefix)-\(candidate)") {
            candidate += 1
        }
        return "\(prefix)-\(candidate)"
    }
}
