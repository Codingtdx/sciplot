import Foundation
import XCTest
@testable import SciPlotGodMac

@MainActor
final class AppModelTests: XCTestCase {
    func testWorkbenchCommandsRouteToCurrentSession() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

        model.switchWorkbench(.dataCleanup)
        model.beginImportForActiveWorkbench()
        XCTAssertEqual(model.selectedWorkbench, .dataCleanup)
        XCTAssertTrue(model.dataCleanupSession.isRawImporterPresented)

        model.switchWorkbench(.composer)
        model.beginImportForActiveWorkbench()
        XCTAssertTrue(model.composerSession.isImportPresented)
        XCTAssertEqual(model.composerSession.pendingImportKind, .graph)
    }

    func testOpenInPlotSeedsPlotSessionAndContext() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())
        let workbookURL = URL(fileURLWithPath: "/tmp/prepared.xlsx")

        model.openInPlot(workbookURL: workbookURL, preferredSheet: .name("Representative_Curve"))

        XCTAssertEqual(model.selectedWorkbench, .plot)
        XCTAssertEqual(model.plotSession.selectedFileURL, workbookURL)
        XCTAssertEqual(model.plotSession.selectedSheet, .name("Representative_Curve"))
        XCTAssertEqual(model.codeConsoleSession.boundContext.first?.value, "prepared.xlsx")
    }

    func testOpenInPlotRequestsReplacementWhenPlotAlreadyHasContent() {
        let model = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())
        model.plotSession.handleImportedFile(URL(fileURLWithPath: "/tmp/existing.csv"))

        model.openInPlot(
            workbookURL: URL(fileURLWithPath: "/tmp/prepared.xlsx"),
            preferredSheet: .name("Representative_Curve")
        )

        XCTAssertTrue(model.isPlotReplacementConfirmationPresented)
        XCTAssertEqual(model.plotSession.selectedFileURL?.path, "/tmp/existing.csv")

        model.confirmPendingPlotReplacement()

        XCTAssertFalse(model.isPlotReplacementConfirmationPresented)
        XCTAssertEqual(model.plotSession.selectedFileURL?.path, "/tmp/prepared.xlsx")
    }
}
