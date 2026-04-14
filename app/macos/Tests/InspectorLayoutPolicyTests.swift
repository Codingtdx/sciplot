import AppKit
import SwiftUI
import XCTest
@testable import SciPlotGodMac

@MainActor
final class InspectorLayoutPolicyTests: XCTestCase {
    func testUnifiedInspectorColumnWidthPolicyStaysStable() {
        XCTAssertEqual(InspectorColumnLayoutPolicy.minWidth, 360)
        XCTAssertEqual(InspectorColumnLayoutPolicy.idealWidth, 400)
        XCTAssertEqual(InspectorColumnLayoutPolicy.maxWidth, 460)
        XCTAssertLessThan(InspectorColumnLayoutPolicy.minWidth, InspectorColumnLayoutPolicy.idealWidth)
        XCTAssertLessThan(InspectorColumnLayoutPolicy.idealWidth, InspectorColumnLayoutPolicy.maxWidth)
    }

    func testQuickLookThumbnailModelClearsPreviousImageWhenStartingNewLoad() async {
        let firstURL = URL(fileURLWithPath: "/tmp/first.pdf")
        let secondURL = URL(fileURLWithPath: "/tmp/second.pdf")
        let firstImage = NSImage(size: NSSize(width: 8, height: 8))
        let secondImage = NSImage(size: NSSize(width: 10, height: 10))
        let harness = ThumbnailLoaderHarness()
        let model = QuickLookThumbnailModel { url, size in
            await harness.load(url: url, size: size)
        }

        let firstTask = Task {
            await model.load(url: firstURL, size: CGSize(width: 120, height: 120))
        }
        await Task.yield()
        await harness.resolve(
            url: firstURL,
            result: QuickLookThumbnailLoadResult(image: firstImage, errorMessage: nil)
        )
        await firstTask.value
        XCTAssertTrue(model.image === firstImage)

        let secondTask = Task {
            await model.load(url: secondURL, size: CGSize(width: 120, height: 120))
        }
        await Task.yield()

        XCTAssertNil(model.image)
        XCTAssertNil(model.errorMessage)

        await harness.resolve(
            url: secondURL,
            result: QuickLookThumbnailLoadResult(image: secondImage, errorMessage: nil)
        )
        await secondTask.value
        XCTAssertTrue(model.image === secondImage)
    }

    func testQuickLookThumbnailModelIgnoresStaleLoaderResultWhenNewerRequestFinishesFirst() async {
        let firstURL = URL(fileURLWithPath: "/tmp/slow.pdf")
        let secondURL = URL(fileURLWithPath: "/tmp/fast.pdf")
        let staleImage = NSImage(size: NSSize(width: 8, height: 8))
        let freshImage = NSImage(size: NSSize(width: 12, height: 12))
        let model = QuickLookThumbnailModel { url, _ in
            if url == firstURL {
                try? await Task.sleep(nanoseconds: 80_000_000)
                return QuickLookThumbnailLoadResult(image: staleImage, errorMessage: nil)
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
            return QuickLookThumbnailLoadResult(image: freshImage, errorMessage: nil)
        }

        let firstTask = Task {
            await model.load(url: firstURL, size: CGSize(width: 120, height: 120))
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
        let secondTask = Task {
            await model.load(url: secondURL, size: CGSize(width: 120, height: 120))
        }

        await secondTask.value
        await firstTask.value

        XCTAssertTrue(model.image === freshImage)
        XCTAssertNil(model.errorMessage)
    }

    func testGuiSmokeRendersKeyWorkbenchViews() async throws {
        let plotSession = PlotSession()
        plotSession.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        let dataStudioClient = MockSidecarClient()
        dataStudioClient.dataStudioSourcePreviewHandler = { request in
            let preview = TestPayloads.dataStudioSourcePreview(path: request.inputPath)
            return DataStudioSourcePreviewResponse(preview: preview.preview, matches: [])
        }
        let dataStudioSession = DataStudioSession()
        dataStudioSession.configure(client: dataStudioClient)
        dataStudioSession.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        await dataStudioSession.handleImportedRawFiles([URL(fileURLWithPath: "/tmp/raw_a.csv")])
        dataStudioSession.beginCreateTemplateEditor()
        try? await Task.sleep(nanoseconds: 20_000_000)

        let specimenSession = DataStudioSession()
        let specimenWorkbook = DataStudioWorkbookItem(
            id: "workbook-1",
            response: TestPayloads.dataStudioWorkbook()
        )
        specimenSession.workbooks = [specimenWorkbook]
        specimenSession.groupStates = [
            .init(workbookPath: specimenWorkbook.response.workbookPath, displayName: "Prepared", includeInCompare: true, sortOrder: 0),
        ]
        specimenSession.baselineWorkbookPreviewByPath[specimenWorkbook.response.workbookPath] =
            TestPayloads.dataStudioWorkbookPreviewWithSuggestedExclusions(path: specimenWorkbook.response.workbookPath)

        let codeConsoleSession = CodeConsoleSession()
        codeConsoleSession.latestRunResponse = TestPayloads.codeConsoleRun()
        codeConsoleSession.selectedGeneratedFilePath = TestPayloads.codeConsoleRun().generatedFiles.first?.path

        let composerSession = ComposerSession()
        composerSession.selectedCells = [
            ComposerGridCell(col: 0, row: 0),
            ComposerGridCell(col: 1, row: 0),
        ]

        let snapshots: [(String, Data?)] = [
            (
                "Plot template gallery",
                snapshotPNGData(
                    for: PlotTemplateView(session: plotSession),
                    size: CGSize(width: 360, height: 520)
                )
            ),
            (
                "Data Studio template editor",
                snapshotPNGData(
                    for: DataStudioCreateTemplateEditorSheet(session: dataStudioSession),
                    size: CGSize(width: 1100, height: 760)
                )
            ),
            (
                "Data Studio specimen filter",
                snapshotPNGData(
                    for: DataStudioSpecimenFilterPopover(session: specimenSession, workbook: specimenWorkbook),
                    size: CGSize(width: 460, height: 620)
                )
            ),
            (
                "Code Console outputs preview",
                snapshotPNGData(
                    for: CodeConsoleOutputsView(session: codeConsoleSession),
                    size: CGSize(width: 880, height: 720)
                )
            ),
            (
                "Composer canvas selection",
                snapshotPNGData(
                    for: ComposerCanvasView(session: composerSession),
                    size: CGSize(width: 960, height: 720)
                )
            ),
        ]

        for (label, data) in snapshots {
            let imageData = try XCTUnwrap(data, "\(label) should render to PNG data.")
            XCTAssertGreaterThan(imageData.count, 1_000, "\(label) should produce a non-trivial bitmap.")
        }
    }

    private func snapshotPNGData<V: View>(for view: V, size: CGSize) -> Data? {
        let hostingView = NSHostingView(rootView: AnyView(view))
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.setFrameSize(size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return nil
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
}

private actor ThumbnailLoaderHarness {
    private var continuations: [String: CheckedContinuation<QuickLookThumbnailLoadResult, Never>] = [:]

    func load(url: URL, size: CGSize) async -> QuickLookThumbnailLoadResult {
        _ = size
        return await withCheckedContinuation { continuation in
            continuations[url.path] = continuation
        }
    }

    func resolve(url: URL, result: QuickLookThumbnailLoadResult) {
        continuations.removeValue(forKey: url.path)?.resume(returning: result)
    }
}
