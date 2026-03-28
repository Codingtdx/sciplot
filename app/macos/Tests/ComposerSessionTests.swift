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
}
