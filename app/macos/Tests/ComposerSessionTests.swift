import Foundation
import XCTest
@testable import SciPlotGodMac

@MainActor
final class ComposerSessionTests: XCTestCase {
    func testComposerHappyPathImportPreviewAndExport() async throws {
        let client = MockSidecarClient()
        let session = ComposerSession(previewDelayNanoseconds: 10_000_000)
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
        XCTAssertEqual(session.exportURL?.path, "/tmp/composer-export.pdf")
    }

    func testMergeSelectedCellsCreatesFreeRegion() {
        let session = ComposerSession()

        session.toggleCellSelection(.init(col: 0, row: 0), additive: false)
        session.toggleCellSelection(.init(col: 1, row: 0), additive: true)
        session.mergeSelectedCells()

        XCTAssertEqual(session.project.regions.count, 1)
        XCTAssertEqual(session.project.regions.first?.kind, "free")
        XCTAssertEqual(session.project.regions.first?.colSpan, 2)
        XCTAssertEqual(session.project.regions.first?.rowSpan, 1)
        XCTAssertEqual(session.selectedRegionID, session.project.regions.first?.id)
    }

    func testUnmergeSelectedRegionRemovesFreeRegion() {
        let session = ComposerSession()

        session.toggleCellSelection(.init(col: 0, row: 0), additive: false)
        session.toggleCellSelection(.init(col: 1, row: 0), additive: true)
        session.mergeSelectedCells()

        XCTAssertEqual(session.project.regions.count, 1)

        session.unmergeSelectedRegion()

        XCTAssertTrue(session.project.regions.isEmpty)
        XCTAssertNil(session.selectedRegionID)
    }

    func testPlaceFocusedGraphMovesRegionIntoCompatibleSelection() {
        let session = ComposerSession()
        session.project = TestPayloads.composerProject()
        session.focusPanel("panel-1")

        session.toggleCellSelection(.init(col: 2, row: 2), additive: false)
        session.placeFocusedPanelInSelectedTarget()

        XCTAssertEqual(session.project.regions.first?.col, 2)
        XCTAssertEqual(session.project.regions.first?.row, 2)
        XCTAssertEqual(session.project.panels.first?.xMm, 120)
        XCTAssertEqual(session.project.panels.first?.yMm, 112.5)
        XCTAssertEqual(session.placementSummary(for: session.project.panels[0]), "C3")
    }

    func testPlaceUsesExplicitPanelIDAndGraphSpanTarget() {
        let session = ComposerSession()
        session.project = TestPayloads.composerProject()

        let target = ComposerPlacementTarget.graphSpan(
            origin: ComposerGridCell(col: 1, row: 1),
            colSpan: 1,
            rowSpan: 1
        )

        XCTAssertTrue(session.canPlace(panelID: "panel-1", in: target))

        session.place(panelID: "panel-1", in: target)

        XCTAssertEqual(session.project.regions.first?.col, 1)
        XCTAssertEqual(session.project.regions.first?.row, 1)
        XCTAssertEqual(session.project.panels.first?.xMm, 60)
        XCTAssertEqual(session.project.panels.first?.yMm, 57.5)
        XCTAssertNil(session.armedReplacementPanelID)
    }

    func testPlaceFocusedAssetSnapsToCellAndMergedRegion() {
        let session = ComposerSession()
        session.project.panels = [
            ComposerPanelPayload(
                id: "asset-1",
                filePath: "/tmp/asset.png",
                pageIndex: 0,
                xMm: 12,
                yMm: 12,
                wMm: 18,
                hMm: 18,
                locked: false,
                hidden: false,
                label: nil,
                kind: "asset",
                zIndex: 0,
                groupID: nil,
                regionID: nil,
                slotID: nil,
                cropRect: .init()
            ),
        ]
        session.focusPanel("asset-1")

        session.toggleCellSelection(.init(col: 1, row: 1), additive: false)
        session.placeFocusedPanelInSelectedTarget()

        XCTAssertEqual(session.project.panels[0].xMm, 60)
        XCTAssertEqual(session.project.panels[0].yMm, 57.5)
        XCTAssertNil(session.project.panels[0].regionID)
        XCTAssertEqual(session.placementSummary(for: session.project.panels[0]), "Cell B2")

        session.toggleCellSelection(.init(col: 0, row: 0), additive: false)
        session.toggleCellSelection(.init(col: 1, row: 0), additive: true)
        session.mergeSelectedCells()
        session.placeFocusedPanelInSelectedTarget()

        XCTAssertEqual(session.project.panels[0].regionID, session.project.regions.first?.id)
        XCTAssertEqual(session.project.panels[0].xMm, 0)
        XCTAssertEqual(session.project.panels[0].yMm, 2.5)
        XCTAssertEqual(session.project.panels[0].wMm, 120)
        XCTAssertEqual(session.project.panels[0].hMm, 55)
    }

    func testPlaceUsesExplicitPanelIDForAssetTargets() throws {
        let session = ComposerSession()
        session.project.panels = [
            ComposerPanelPayload(
                id: "asset-1",
                filePath: "/tmp/asset.png",
                pageIndex: 0,
                xMm: 10,
                yMm: 10,
                wMm: 20,
                hMm: 20,
                locked: false,
                hidden: false,
                label: nil,
                kind: "asset",
                zIndex: 0,
                groupID: nil,
                regionID: nil,
                slotID: nil,
                cropRect: .init()
            ),
        ]

        let cellTarget = ComposerPlacementTarget.cell(.init(col: 2, row: 1))
        XCTAssertTrue(session.canPlace(panelID: "asset-1", in: cellTarget))

        session.place(panelID: "asset-1", in: cellTarget)

        XCTAssertEqual(session.project.panels[0].xMm, 120)
        XCTAssertEqual(session.project.panels[0].yMm, 57.5)

        session.toggleCellSelection(.init(col: 0, row: 1), additive: false)
        session.toggleCellSelection(.init(col: 1, row: 1), additive: true)
        session.mergeSelectedCells()

        let freeRegionID = try XCTUnwrap(session.project.regions.first?.id)
        let freeRegionTarget = ComposerPlacementTarget.freeRegion(freeRegionID)
        XCTAssertTrue(session.canPlace(panelID: "asset-1", in: freeRegionTarget))

        session.place(panelID: "asset-1", in: freeRegionTarget)

        XCTAssertEqual(session.project.panels[0].regionID, freeRegionID)
        XCTAssertEqual(session.project.panels[0].xMm, 0)
        XCTAssertEqual(session.project.panels[0].yMm, 57.5)
        XCTAssertEqual(session.project.panels[0].wMm, 120)
        XCTAssertEqual(session.project.panels[0].hMm, 55)
    }

    func testMovePanelsPreservesProjectPanelOrder() {
        let session = ComposerSession()
        session.project = TestPayloads.composerProject()
        session.project.panels.append(
            ComposerPanelPayload(
                id: "panel-3",
                filePath: "/tmp/panel-3.pdf",
                pageIndex: 0,
                xMm: 120,
                yMm: 57.5,
                wMm: 60,
                hMm: 55,
                locked: false,
                hidden: false,
                label: nil,
                kind: "graph",
                zIndex: 2,
                groupID: nil,
                regionID: nil,
                slotID: nil,
                cropRect: .init()
            )
        )

        session.movePanels(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        XCTAssertEqual(session.project.panels.map(\.id), ["panel-3", "panel-1"])
    }

    func testReplaceStateArmsAndClearsWithoutDeletingContent() {
        let session = ComposerSession()
        session.project = TestPayloads.composerProject()

        session.selectPanelOnCanvas("panel-1")
        session.beginReplacingSelectedPanel()

        XCTAssertEqual(session.armedReplacementPanelID, "panel-1")
        XCTAssertEqual(session.selectedPanelID, "panel-1")
        XCTAssertEqual(session.project.panels.count, 1)

        session.clearTransientEditingState()

        XCTAssertNil(session.armedReplacementPanelID)
        XCTAssertNil(session.selectedPanelID)
        XCTAssertEqual(session.project.panels.count, 1)
    }

    func testResolvedLabelsUseUppercaseAutoLabels() {
        let session = ComposerSession()
        session.project.panels = [
            ComposerPanelPayload(
                id: "panel-2",
                filePath: "/tmp/panel-2.pdf",
                pageIndex: 0,
                xMm: 60,
                yMm: 2.5,
                wMm: 60,
                hMm: 55,
                locked: false,
                hidden: false,
                label: nil,
                kind: "graph",
                zIndex: 0,
                groupID: nil,
                regionID: nil,
                slotID: nil,
                cropRect: .init()
            ),
            ComposerPanelPayload(
                id: "panel-1",
                filePath: "/tmp/panel-1.pdf",
                pageIndex: 0,
                xMm: 0,
                yMm: 2.5,
                wMm: 60,
                hMm: 55,
                locked: false,
                hidden: false,
                label: nil,
                kind: "graph",
                zIndex: 1,
                groupID: nil,
                regionID: nil,
                slotID: nil,
                cropRect: .init()
            ),
        ]

        XCTAssertEqual(session.resolvedLabel(for: session.project.panels[1]), "A")
        XCTAssertEqual(session.resolvedLabel(for: session.project.panels[0]), "B")
    }
}
