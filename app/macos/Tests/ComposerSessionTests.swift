import Foundation
import XCTest
@testable import SciPlotGodMac

@MainActor
final class ComposerSessionTests: XCTestCase {
    func testExportAvailabilityExplainsBlockingStates() {
        let session = ComposerSession()
        XCTAssertFalse(session.exportAvailability.isEnabled)
        XCTAssertTrue(session.exportAvailability.reason?.contains("sidecar") ?? false)

        let client = MockSidecarClient()
        session.configure(client: client)
        XCTAssertFalse(session.exportAvailability.isEnabled)
        XCTAssertTrue(session.exportAvailability.reason?.contains("Import at least one panel") ?? false)

        session.project.panels = [graphPanel(id: "panel-1", col: 0, row: 0, zIndex: 0)]
        XCTAssertTrue(session.exportAvailability.isEnabled)
        XCTAssertNil(session.exportAvailability.reason)
    }

    func testBoardGeometryResolvesAllNineCellsFromBoardLocalPoints() {
        let geometry = ComposerBoardGeometry(
            project: ComposerRequestPayload(),
            boardSize: CGSize(width: 360, height: 330)
        )

        for row in 0 ..< 3 {
            for col in 0 ..< 3 {
                let cell = ComposerGridCell(col: col, row: row)
                let rect = geometry.rect(for: cell)
                let center = CGPoint(x: rect.midX, y: rect.midY)
                XCTAssertEqual(geometry.cell(at: center), cell)
            }
        }
    }

    func testSingleCellSelectionTracksExactClickedCell() {
        let session = ComposerSession()

        session.beginCellDragSelection(at: .init(col: 1, row: 2))

        XCTAssertEqual(session.selectedCells, Set([.init(col: 1, row: 2)]))
        XCTAssertEqual(session.selectedCellSelection, .init(origin: .init(col: 1, row: 2), colSpan: 1, rowSpan: 1))
    }

    func testCommandToggleSelectionTracksExactCells() {
        let session = ComposerSession()

        session.beginCellDragSelection(at: .init(col: 0, row: 1))
        session.toggleCellSelection(.init(col: 1, row: 1))

        XCTAssertEqual(session.selectedCells, Set([.init(col: 0, row: 1), .init(col: 1, row: 1)]))
    }

    func testShiftExtensionBuildsRectangularSelectionFromAnchor() {
        let session = ComposerSession()

        session.beginCellDragSelection(at: .init(col: 0, row: 0))
        session.extendCellSelection(to: .init(col: 1, row: 1))

        XCTAssertEqual(
            session.selectedCells,
            Set([
                .init(col: 0, row: 0),
                .init(col: 1, row: 0),
                .init(col: 0, row: 1),
                .init(col: 1, row: 1),
            ])
        )
        XCTAssertEqual(session.selectedCellSelection, .init(origin: .init(col: 0, row: 0), colSpan: 2, rowSpan: 2))
    }

    func testDragSelectionBuildsRectangularSelection() {
        let session = ComposerSession()

        session.beginCellDragSelection(at: .init(col: 1, row: 0))
        session.updateCellDragSelection(to: .init(col: 2, row: 2))

        XCTAssertEqual(
            session.selectedCells,
            Set([
                .init(col: 1, row: 0),
                .init(col: 2, row: 0),
                .init(col: 1, row: 1),
                .init(col: 2, row: 1),
                .init(col: 1, row: 2),
                .init(col: 2, row: 2),
            ])
        )
        XCTAssertEqual(session.selectedCellSelection, .init(origin: .init(col: 1, row: 0), colSpan: 2, rowSpan: 3))
    }

    func testMergeAvailabilityRequiresEmptyRectangularSelection() {
        let session = ComposerSession()

        session.beginCellDragSelection(at: .init(col: 0, row: 0))
        session.updateCellDragSelection(to: .init(col: 1, row: 0))
        XCTAssertTrue(session.canMergeSelectedCells)

        session.project.panels = [
            graphPanel(id: "panel-1", col: 1, row: 0, zIndex: 0),
        ]
        XCTAssertFalse(session.canMergeSelectedCells)
    }

    func testMergeCreatesSelectableMergedRegion() {
        let session = ComposerSession()

        session.beginCellDragSelection(at: .init(col: 0, row: 0))
        session.updateCellDragSelection(to: .init(col: 1, row: 0))
        session.mergeSelectedCells()

        XCTAssertNotNil(session.selectedRegionID)
        XCTAssertEqual(session.selectedFreeRegion?.id, session.selectedRegionID)
        XCTAssertEqual(session.selectedFreeRegion?.colSpan, 2)
        XCTAssertEqual(session.selectedFreeRegion?.rowSpan, 1)
    }

    func testComposerHappyPathImportPreviewAndExport() async throws {
        let client = MockSidecarClient()
        let destinationURL = URL(fileURLWithPath: "/tmp/user_exports/composer-final.pdf")
        var chooserSuggestedName: String?
        var materializeCall: (URL, URL)?
        let session = ComposerSession(
            previewDelayNanoseconds: 10_000_000,
            chooseExportDestination: { suggestedName in
                chooserSuggestedName = suggestedName
                return destinationURL
            },
            materializeExport: { intermediatePDFURL, destination in
                materializeCall = (intermediatePDFURL, destination)
            }
        )
        session.configure(client: client)

        session.beginImport(kind: .graph)
        await session.handleImportedAssets([
            URL(fileURLWithPath: "/tmp/panel.pdf"),
        ])

        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(client.composerImportRequests.first?.kind, "graph")
        XCTAssertEqual(session.selectedPanelID, "panel-1")
        XCTAssertEqual(session.previewResponse?.submissionReport?.summary, "Ready for export.")

        await session.exportComposition()

        XCTAssertEqual(client.composeExportRequests.first?.version, 2)
        XCTAssertEqual(chooserSuggestedName, "composer-composition.pdf")
        XCTAssertEqual(materializeCall?.0.path, "/tmp/composer-export.pdf")
        XCTAssertEqual(materializeCall?.1, destinationURL)
        XCTAssertEqual(session.exportURL, destinationURL)
    }

    func testComposerExportPassesTiffDestinationToMaterializer() async {
        let client = MockSidecarClient()
        let destinationURL = URL(fileURLWithPath: "/tmp/user_exports/composer-final.tiff")
        var materializeDestination: URL?
        let session = ComposerSession(
            chooseExportDestination: { _ in destinationURL },
            materializeExport: { _, destination in
                materializeDestination = destination
            }
        )
        session.configure(client: client)

        await session.exportComposition()

        XCTAssertEqual(materializeDestination, destinationURL)
        XCTAssertEqual(session.exportURL, destinationURL)
    }

    func testShiftSelectionMergeCreatesFreeRegionWithoutChangingPanelOrder() {
        let session = ComposerSession()
        session.project.panels = [
            graphPanel(id: "panel-1", col: 2, row: 0, zIndex: 0),
            graphPanel(id: "panel-2", col: 0, row: 1, zIndex: 1),
        ]

        session.updateCellSelection(.init(col: 0, row: 0), additive: false, extend: false)
        session.updateCellSelection(.init(col: 1, row: 0), additive: false, extend: true)
        session.mergeSelectedCells()

        XCTAssertEqual(session.project.panels.map(\.id), ["panel-1", "panel-2"])
        XCTAssertEqual(session.project.regions.count, 1)
        XCTAssertEqual(session.project.regions.first?.kind, "free")
        XCTAssertEqual(session.project.regions.first?.colSpan, 2)
        XCTAssertEqual(session.project.regions.first?.rowSpan, 1)
    }

    func testUnmergeSelectedRegionRemovesFreeRegionWithoutChangingCanonicalOrder() {
        let session = ComposerSession()
        session.project.panels = [
            graphPanel(id: "panel-1", col: 2, row: 0, zIndex: 0),
            graphPanel(id: "panel-2", col: 0, row: 1, zIndex: 1),
        ]

        session.toggleCellSelection(.init(col: 0, row: 0), additive: false)
        session.toggleCellSelection(.init(col: 1, row: 0), additive: true)
        session.mergeSelectedCells()
        let regionID = session.project.regions.first?.id

        XCTAssertEqual(session.project.panels.map(\.id), ["panel-1", "panel-2"])

        session.selectRegion(regionID)
        session.unmergeSelectedRegion()

        XCTAssertTrue(session.project.regions.isEmpty)
        XCTAssertEqual(session.project.panels.map(\.id), ["panel-1", "panel-2"])
        XCTAssertNil(session.selectedRegionID)
    }

    func testBoardQuickActionStateTracksMergeableSelectionAndClearsForPanelSelection() {
        let session = ComposerSession()
        session.project.panels = [
            graphPanel(id: "panel-1", col: 2, row: 2, zIndex: 0),
        ]

        session.updateCellSelection(.init(col: 0, row: 0), additive: false, extend: false)
        session.updateCellSelection(.init(col: 1, row: 0), additive: false, extend: true)

        XCTAssertEqual(
            session.boardQuickActionState,
            .mergeableMultiCellSelection(
                ComposerCellSelection(origin: .init(col: 0, row: 0), colSpan: 2, rowSpan: 1)
            )
        )

        session.selectPanelOnCanvas("panel-1")
        XCTAssertNil(session.boardQuickActionState)

        session.updateCellSelection(.init(col: 0, row: 0), additive: false, extend: false)
        session.updateCellSelection(.init(col: 1, row: 0), additive: false, extend: true)
        XCTAssertEqual(
            session.boardQuickActionState,
            .mergeableMultiCellSelection(
                ComposerCellSelection(origin: .init(col: 0, row: 0), colSpan: 2, rowSpan: 1)
            )
        )
    }

    func testBoardQuickActionStateOnlyTracksEmptyMergedRegions() {
        let session = ComposerSession()
        let emptyRegion = ComposerRegionPayload(
            id: "region-free-1",
            kind: "free",
            col: 0,
            row: 0,
            colSpan: 2,
            rowSpan: 1,
            label: nil,
            locked: false,
            slotKind: nil
        )
        session.project.regions = [emptyRegion]

        session.selectRegion(emptyRegion.id)
        XCTAssertEqual(session.boardQuickActionState, .emptyMergedRegion(emptyRegion))

        session.project.panels = [
            assetPanel(id: "asset-1", regionID: emptyRegion.id, xMm: 0, yMm: 2.5, wMm: 120, hMm: 55, zIndex: 0),
        ]
        XCTAssertNil(session.boardQuickActionState)
    }

    func testLibraryReorderReflowsBoardIntoCanonicalOrder() {
        let session = ComposerSession()
        session.project.panels = [
            graphPanel(id: "panel-1", col: 0, row: 0, zIndex: 0),
            graphPanel(id: "panel-2", col: 1, row: 0, zIndex: 1),
        ]

        session.movePanels(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        XCTAssertEqual(session.project.panels.map(\.id), ["panel-2", "panel-1"])
        XCTAssertEqual(session.project.panels[0].xMm, 0)
        XCTAssertEqual(session.project.panels[0].yMm, 2.5)
        XCTAssertEqual(session.project.panels[1].xMm, 60)
        XCTAssertEqual(session.project.panels[1].yMm, 2.5)
        XCTAssertEqual(session.project.panels.map(\.zIndex), [0, 1])
    }

    func testLibraryReorderPreservesMergedRegionTopologyWhileReflowingBoard() {
        let session = ComposerSession()
        let freeRegion = ComposerRegionPayload(
            id: "region-free-1",
            kind: "free",
            col: 0,
            row: 0,
            colSpan: 2,
            rowSpan: 1,
            label: nil,
            locked: false,
            slotKind: nil
        )
        session.project.regions = [freeRegion]
        session.project.panels = [
            assetPanel(id: "asset-1", regionID: freeRegion.id, xMm: 0, yMm: 2.5, wMm: 120, hMm: 55, zIndex: 0),
            graphPanel(id: "panel-1", col: 2, row: 0, zIndex: 1, regionID: "region-graph-1"),
            graphPanel(id: "panel-2", col: 0, row: 1, zIndex: 2, regionID: "region-graph-2"),
        ]
        session.project.regions.append(graphRegion(id: "region-graph-1", col: 2, row: 0))
        session.project.regions.append(graphRegion(id: "region-graph-2", col: 0, row: 1))

        session.movePanels(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(session.project.panels.map(\.id), ["panel-2", "asset-1", "panel-1"])
        XCTAssertEqual(session.project.regions.filter { $0.kind == "free" }.count, 1)
        XCTAssertEqual(session.project.regions.first { $0.kind == "free" }?.colSpan, 2)
        XCTAssertEqual(session.project.panels[0].xMm, 120)
        XCTAssertEqual(session.project.panels[0].yMm, 2.5)
        XCTAssertEqual(session.project.panels[1].regionID, freeRegion.id)
        XCTAssertEqual(session.project.panels[2].xMm, 0)
        XCTAssertEqual(session.project.panels[2].yMm, 57.5)
    }

    func testBoardMoveToEmptyTargetRewritesCanonicalOrder() {
        let session = ComposerSession()
        session.project.panels = [
            graphPanel(id: "panel-1", col: 0, row: 0, zIndex: 0),
            graphPanel(id: "panel-2", col: 1, row: 0, zIndex: 1),
        ]

        session.place(panelID: "panel-1", in: .cell(.init(col: 2, row: 1)))

        XCTAssertEqual(session.project.panels.map(\.id), ["panel-2", "panel-1"])
        XCTAssertEqual(session.project.panels[0].xMm, 60)
        XCTAssertEqual(session.project.panels[0].yMm, 2.5)
        XCTAssertEqual(session.project.panels[1].xMm, 120)
        XCTAssertEqual(session.project.panels[1].yMm, 57.5)
    }

    func testBoardSwapRewritesCanonicalOrderAndSwapsPositions() {
        let session = ComposerSession()
        session.project.panels = [
            graphPanel(id: "panel-1", col: 0, row: 0, zIndex: 0),
            graphPanel(id: "panel-2", col: 1, row: 0, zIndex: 1),
        ]

        XCTAssertTrue(session.canPlace(panelID: "panel-2", in: .cell(.init(col: 0, row: 0))))

        session.place(panelID: "panel-2", in: .cell(.init(col: 0, row: 0)))

        XCTAssertEqual(session.project.panels.map(\.id), ["panel-2", "panel-1"])
        XCTAssertEqual(session.project.panels[0].xMm, 0)
        XCTAssertEqual(session.project.panels[1].xMm, 60)
    }

    func testRemoveFromBoardKeepsPanelInLibraryOrderButExcludesItFromBoard() {
        let session = ComposerSession()
        session.project.panels = [
            graphPanel(id: "panel-1", col: 0, row: 0, zIndex: 0),
            graphPanel(id: "panel-2", col: 1, row: 0, zIndex: 1),
        ]

        session.selectPanelOnCanvas("panel-1")
        session.removeSelectedPanelFromBoard()

        XCTAssertEqual(session.project.panels.map(\.id), ["panel-2", "panel-1"])
        XCTAssertTrue(session.project.panels[1].hidden)
        XCTAssertEqual(session.visibleBoardPanels.map(\.id), ["panel-2"])
    }

    func testResolvedLabelsFollowCanonicalPanelOrder() {
        let session = ComposerSession()
        session.project.panels = [
            graphPanel(id: "panel-2", col: 0, row: 0, zIndex: 0),
            graphPanel(id: "panel-1", col: 1, row: 0, zIndex: 1),
        ]

        XCTAssertEqual(session.resolvedLabel(for: session.project.panels[0]), "A")
        XCTAssertEqual(session.resolvedLabel(for: session.project.panels[1]), "B")
    }
}

private func graphPanel(
    id: String,
    col: Int,
    row: Int,
    zIndex: Int,
    regionID: String? = nil
) -> ComposerPanelPayload {
    ComposerPanelPayload(
        id: id,
        filePath: "/tmp/\(id).pdf",
        pageIndex: 0,
        xMm: Double(col) * 60.0,
        yMm: 2.5 + Double(row) * 55.0,
        wMm: 60,
        hMm: 55,
        locked: false,
        hidden: false,
        label: nil,
        kind: "graph",
        zIndex: zIndex,
        groupID: nil,
        regionID: regionID,
        slotID: nil,
        cropRect: .init()
    )
}

private func assetPanel(
    id: String,
    regionID: String?,
    xMm: Double,
    yMm: Double,
    wMm: Double,
    hMm: Double,
    zIndex: Int
) -> ComposerPanelPayload {
    ComposerPanelPayload(
        id: id,
        filePath: "/tmp/\(id).png",
        pageIndex: 0,
        xMm: xMm,
        yMm: yMm,
        wMm: wMm,
        hMm: hMm,
        locked: false,
        hidden: false,
        label: nil,
        kind: "asset",
        zIndex: zIndex,
        groupID: nil,
        regionID: regionID,
        slotID: nil,
        cropRect: .init()
    )
}

private func graphRegion(id: String, col: Int, row: Int) -> ComposerRegionPayload {
    ComposerRegionPayload(
        id: id,
        kind: "graph",
        col: col,
        row: row,
        colSpan: 1,
        rowSpan: 1,
        label: nil,
        locked: false,
        slotKind: nil
    )
}
