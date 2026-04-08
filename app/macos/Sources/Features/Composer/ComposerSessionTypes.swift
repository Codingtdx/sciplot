import CoreGraphics
import CoreTransferable
import Foundation
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

enum ComposerBoardQuickActionState: Equatable, Sendable {
    case mergeableMultiCellSelection(ComposerCellSelection)
    case emptyMergedRegion(ComposerRegionPayload)

    var token: String {
        switch self {
        case let .mergeableMultiCellSelection(selection):
            return "mergeable:\(selection.origin.col),\(selection.origin.row),\(selection.colSpan),\(selection.rowSpan)"
        case let .emptyMergedRegion(region):
            return "empty-region:\(region.id)"
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

struct ComposerBoardOrderingKey: Comparable {
    let row: Int
    let col: Int
    let area: Int
    let panelID: String

    static func < (lhs: ComposerBoardOrderingKey, rhs: ComposerBoardOrderingKey) -> Bool {
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        if lhs.col != rhs.col { return lhs.col < rhs.col }
        if lhs.area != rhs.area { return lhs.area < rhs.area }
        return lhs.panelID < rhs.panelID
    }
}
