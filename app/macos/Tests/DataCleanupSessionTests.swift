import Foundation
import XCTest
@testable import SciPlotGodMac

@MainActor
final class DataCleanupSessionTests: XCTestCase {
    func testCleanupHappyPathPreprocessInspectExportAndOpenInPlot() async throws {
        let outputWorkbookURL = URL(fileURLWithPath: "/tmp/prepared.xlsx")
        let exportDirectoryURL = URL(fileURLWithPath: "/tmp/cleanup_bundle", isDirectory: true)
        let client = MockSidecarClient()
        var chosenFormat: ExportGraphicFormat?
        let session = DataCleanupSession(
            chooseDirectory: { _, _ in exportDirectoryURL },
            chooseWorkbookSaveLocation: { _ in outputWorkbookURL },
            chooseComparisonFigureFormat: { _, _ in
                chosenFormat = .tiff
                return .tiff
            },
            materializeComparisonOutputs: { sourceURLs, format in
                chosenFormat = format
                return sourceURLs.map {
                    $0.deletingPathExtension().appendingPathExtension("tiff")
                }
            }
        )
        session.configure(client: client)

        await session.handleImportedRawFiles([
            URL(fileURLWithPath: "/tmp/raw_a.csv"),
        ])

        XCTAssertEqual(session.stage, .review)
        XCTAssertEqual(session.preparedWorkbooks.first?.url, outputWorkbookURL)
        XCTAssertEqual(client.preprocessRequests.first?.outputPath, outputWorkbookURL.path)

        await session.handleImportedWorkbooks([
            URL(fileURLWithPath: "/tmp/second.xlsx"),
        ])

        XCTAssertEqual(session.preparedWorkbooks.count, 2)
        XCTAssertEqual(client.workbookRequests.first?.workbookPath, "/tmp/second.xlsx")

        await session.exportComparisonBundle()

        XCTAssertEqual(session.stage, .export)
        XCTAssertEqual(client.comparisonRequests.first?.workbookPaths.count, 2)
        XCTAssertEqual(session.comparisonExportResponse?.bundleDir, "/tmp/cleanup_bundle")
        XCTAssertEqual(session.comparisonExportDestinationURL, exportDirectoryURL)
        XCTAssertEqual(chosenFormat, .tiff)
        XCTAssertEqual(
            session.comparisonExportFigureURLs.map(\.lastPathComponent),
            ["strength_box.tiff", "modulus_bar.tiff"]
        )

        var openedWorkbook: URL?
        var openedSheet: SheetValue?
        session.openInPlotHandler = { url, sheet in
            openedWorkbook = url
            openedSheet = sheet
        }

        session.openPrimaryWorkbookInPlot()

        XCTAssertEqual(openedWorkbook, outputWorkbookURL)
        XCTAssertEqual(openedSheet, .name("Representative_Curve"))
    }
}
