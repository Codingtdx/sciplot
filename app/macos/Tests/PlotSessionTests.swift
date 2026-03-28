import XCTest
@testable import SciPlotGodMac

@MainActor
final class PlotSessionTests: XCTestCase {
    func testPlotHappyPathInspectTemplatePreviewAndExport() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.handleImportedFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await session.inspectCurrentFile()

        XCTAssertEqual(session.stage, .template)
        XCTAssertEqual(session.selectedTemplateID, "curve")
        XCTAssertEqual(session.sampleRows.count, 3)
        XCTAssertEqual(client.inspectRequests.first?.inputPath, "/tmp/sample.csv")

        await session.runPreflight()
        await session.renderPreview()
        await session.exportCurrentSelection()

        XCTAssertEqual(client.preflightRequests.first?.template, "curve")
        XCTAssertEqual(client.renderRequests.first?.options.size, "single_panel")
        XCTAssertEqual(client.exportRequests.first?.template, "curve")
        XCTAssertEqual(session.previewResponse?.previews.first?.filename, "sample_curve.png")
        XCTAssertEqual(session.exportResponse?.manifestPath, "/tmp/plot_exports/manifest.json")
    }
}
