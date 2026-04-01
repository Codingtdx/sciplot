import Foundation
import XCTest
@testable import SciPlotGodMac

@MainActor
final class CodeConsoleSessionTests: XCTestCase {
    func testCodeConsoleContextRefreshesAndRunsWithBoundPlotState() async {
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
                warnings: [],
                reviewTemplateID: nil,
                reviewInspection: nil,
                reviewDataset: nil,
                reviewPreview: nil,
                reviewSubmissionReport: nil,
                reviewErrorMessage: nil
            ),
        ]

        let client = MockSidecarClient()
        let session = CodeConsoleSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta())

        session.refreshContext(plot: plot, dataCleanup: cleanup)
        await session.refreshCurrentContext()

        XCTAssertEqual(session.availableBindings.count, 2)
        XCTAssertEqual(session.selectedSourceFilename, "sample.csv")
        XCTAssertTrue(session.promptText.contains("src.code_console_runtime"))
        XCTAssertTrue(session.editorText.contains("console.save_figure"))
        XCTAssertFalse(session.boundContext.isEmpty)
        XCTAssertEqual(client.codeConsoleContextRequests.last?.template, "curve")

        session.editorText = "print('hello code console')"
        await session.runCurrentCode()

        XCTAssertEqual(client.codeConsoleRunRequests.count, 1)
        XCTAssertEqual(session.latestRunResponse?.status, "succeeded")
        XCTAssertEqual(session.selectedGeneratedFile?.name, "sample.pdf")
        XCTAssertTrue(session.outputsSummary.contains("files"))
    }
}
