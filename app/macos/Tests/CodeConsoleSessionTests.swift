import Foundation
import XCTest
@testable import SciPlotGodMac

@MainActor
final class CodeConsoleSessionTests: XCTestCase {
    func testCodeConsoleContextRefreshesAndRunsWithBoundPlotState() async {
        let plot = PlotSession()
        plot.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        plot.selectedSheet = .name("Representative_Curve")
        plot.selectedTemplateID = "curve"
        plot.renderOptions.size = "single_panel"

        let dataStudio = DataStudioSession()
        dataStudio.workbooks = [
            .init(
                id: "workbook-1",
                response: TestPayloads.dataStudioWorkbook(
                    id: "workbook-1",
                    path: "/tmp/prepared.xlsx",
                    label: "Prepared"
                )
            ),
        ]
        dataStudio.groupStates = [
            .init(
                workbookPath: "/tmp/prepared.xlsx",
                displayName: "Prepared",
                includeInCompare: true,
                sortOrder: 0
            ),
        ]
        dataStudio.focusedWorkbookPath = "/tmp/prepared.xlsx"

        let client = MockSidecarClient()
        let session = CodeConsoleSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta())

        session.refreshContext(plot: plot, dataStudio: dataStudio)
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

    func testContextRefreshDebouncesRapidBindingChangesToLatestRequest() async {
        let plot = PlotSession()
        plot.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        plot.selectedSheet = .index(0)
        plot.selectedTemplateID = "curve"

        let client = MockSidecarClient()
        client.codeConsoleContextHandler = { request in
            try await Task.sleep(nanoseconds: 60_000_000)
            let base = TestPayloads.codeConsoleContext(path: request.inputPath)
            return CodeConsoleContextResponse(
                contextID: base.contextID,
                inputPath: base.inputPath,
                sheet: request.sheet,
                sheetNames: base.sheetNames,
                inspection: base.inspection,
                dataset: base.dataset,
                template: base.template,
                options: base.options,
                promptText: base.promptText,
                starterCode: base.starterCode,
                sourceKind: base.sourceKind,
                sourceLabel: base.sourceLabel
            )
        }

        let session = CodeConsoleSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta())

        session.refreshContext(plot: plot, dataStudio: DataStudioSession())
        session.setSelectedSheet(.name("Strength_Box"))
        session.setSelectedSheet(.name("Representative_Curve"))

        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(client.codeConsoleContextRequests.count, 1)
        XCTAssertEqual(client.codeConsoleContextRequests.last?.sheet, .name("Representative_Curve"))
        XCTAssertEqual(session.contextResponse?.sheet, .name("Representative_Curve"))
    }
}
