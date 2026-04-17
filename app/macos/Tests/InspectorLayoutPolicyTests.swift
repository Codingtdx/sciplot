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
        let snapshots = try await canonicalWorkbenchSnapshots()

        for (label, data) in snapshots {
            XCTAssertGreaterThan(data.count, 1_000, "\(label) should produce a non-trivial bitmap.")
        }
    }

    func testGuiSnapshotFingerprintsStayStable() async throws {
        let snapshots = try await canonicalWorkbenchSnapshots()

        for (label, data) in snapshots {
            let fingerprint = try XCTUnwrap(
                SnapshotFingerprint.make(fromPNGData: data),
                "\(label) should decode into a snapshot fingerprint."
            )
            guard let expected = expectedSnapshotFingerprints[label] else {
                XCTFail("Missing fingerprint fixture for \(label): \(fingerprint.debugSummary)")
                continue
            }
            XCTAssertTrue(
                fingerprint.matches(expected),
                "\(label) fingerprint drifted. expected \(expected.debugSummary) got \(fingerprint.debugSummary)"
            )
        }
    }

    private func canonicalWorkbenchSnapshots() async throws -> [(String, Data)] {
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

        let rawSnapshots: [(String, Data?)] = [
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

        return try rawSnapshots.map { label, data in
            let imageData = try XCTUnwrap(data, "\(label) should render to PNG data.")
            return (label, imageData)
        }
    }

    private func snapshotPNGData<V: View>(for view: V, size: CGSize) -> Data? {
        let rootedView = AnyView(
            view
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.colorScheme, .light)
        )
        let hostingView = NSHostingView(rootView: rootedView)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.setFrameSize(size)
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return nil
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
}

private let expectedSnapshotFingerprints: [String: SnapshotFingerprint] = [
    "Plot template gallery": SnapshotFingerprint(
        differenceHash: 0x80b0b0b0b0b0b0b0,
        averageLuma: 0.3163,
        nonWhiteFraction: 1.0000
    ),
    "Data Studio template editor": SnapshotFingerprint(
        differenceHash: 0x700108090c0c0c0c,
        averageLuma: 0.9591,
        nonWhiteFraction: 0.5417
    ),
    "Data Studio specimen filter": SnapshotFingerprint(
        differenceHash: 0x06c0c8c8c8c8c000,
        averageLuma: 0.6560,
        nonWhiteFraction: 0.6111
    ),
    "Code Console outputs preview": SnapshotFingerprint(
        differenceHash: 0x0000000000000000,
        averageLuma: 0.0000,
        nonWhiteFraction: 1.0000
    ),
    "Composer canvas selection": SnapshotFingerprint(
        differenceHash: 0x8000150000070787,
        averageLuma: 0.9840,
        nonWhiteFraction: 0.2083
    ),
]

private struct SnapshotFingerprint: Equatable {
    let differenceHash: UInt64
    let averageLuma: Double
    let nonWhiteFraction: Double

    var debugSummary: String {
        let hash = String(format: "%016llx", differenceHash)
        return "hash=\(hash) luma=\(String(format: "%.4f", averageLuma)) coverage=\(String(format: "%.4f", nonWhiteFraction))"
    }

    static func make(fromPNGData data: Data) -> SnapshotFingerprint? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let width = 9
        let height = 8
        let bytesPerRow = width
        let pixelCount = width * height
        var pixels = [UInt8](repeating: 0, count: pixelCount)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        var bitIndex = 0
        for row in 0..<height {
            for column in 0..<(width - 1) {
                let left = pixels[row * width + column]
                let right = pixels[row * width + column + 1]
                if left > right {
                    hash |= UInt64(1) << UInt64(bitIndex)
                }
                bitIndex += 1
            }
        }

        let averageLuma = pixels.reduce(0.0) { $0 + Double($1) / 255.0 } / Double(pixelCount)
        let nonWhiteFraction = Double(pixels.filter { $0 < 247 }.count) / Double(pixelCount)
        return SnapshotFingerprint(
            differenceHash: hash,
            averageLuma: averageLuma,
            nonWhiteFraction: nonWhiteFraction
        )
    }

    func matches(
        _ expected: SnapshotFingerprint,
        hashTolerance: Int = 8,
        lumaTolerance: Double = 0.05,
        coverageTolerance: Double = 0.08
    ) -> Bool {
        let hashDistance = (differenceHash ^ expected.differenceHash).nonzeroBitCount
        return hashDistance <= hashTolerance
            && abs(averageLuma - expected.averageLuma) <= lumaTolerance
            && abs(nonWhiteFraction - expected.nonWhiteFraction) <= coverageTolerance
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
