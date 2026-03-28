import Foundation
import XCTest
@testable import SciPlotGodMac

@MainActor
final class CodeConsoleSessionTests: XCTestCase {
    func testCodeConsoleContextAndUnavailableState() {
        let plot = PlotSession()
        plot.handleImportedFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        plot.selectedSheet = .name("Representative_Curve")
        plot.selectedTemplateID = "curve"
        plot.renderOptions.size = "single_panel"

        let cleanup = DataCleanupSession()
        cleanup.preparedWorkbooks = [
            .init(
                id: "/tmp/prepared.xlsx",
                url: URL(fileURLWithPath: "/tmp/prepared.xlsx"),
                label: "Prepared",
                preferredSheet: .name("Representative_Curve"),
                sampleCount: 3,
                representativeFilename: "sample.csv",
                metrics: [],
                sheetNames: ["Representative_Curve"],
                warnings: []
            ),
        ]

        let session = CodeConsoleSession()
        session.refreshContext(plot: plot, dataCleanup: cleanup)

        XCTAssertEqual(session.boundContext.count, 3)
        XCTAssertTrue(session.outputsSummary.contains("No controlled runner backend"))
        XCTAssertTrue(session.unavailableReason.contains("does not yet expose"))
        XCTAssertTrue(session.editorText.contains("does not yet expose"))
    }
}
