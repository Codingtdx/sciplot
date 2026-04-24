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
        exportSnapshotsIfRequested(snapshots)

        for (label, data) in snapshots {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = label
            attachment.lifetime = .keepAlways
            add(attachment)
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

        let importedPlotSession = PlotSession()
        importedPlotSession.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        importedPlotSession.selectedFileURL = URL(fileURLWithPath: "/tmp/imported-curve.csv")
        importedPlotSession.selectedSheet = .name("Representative_Curve")
        importedPlotSession.selectedTemplateID = "area_curve"
        importedPlotSession.renderOptions = RenderOptionsPayload(
            size: "single_panel",
            stylePreset: "presentation",
            palettePreset: "shine",
            visualThemeID: "macarons"
        )
        importedPlotSession.sourceTableResponse = TestPayloads.sourceTablePreview(path: "/tmp/imported-curve.csv")
        importedPlotSession.fitAnalysisResponse = TestPayloads.fitAnalysis(path: "/tmp/imported-curve.csv")

        let dataStudioClient = MockSidecarClient()
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

        let figureSession = DataStudioSession()
        figureSession.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        let figureWorkbook = DataStudioWorkbookItem(
            id: "workbook-figure",
            response: TestPayloads.dataStudioWorkbook(
                id: "workbook-figure",
                path: "/tmp/prepared-strength.xlsx",
                label: "Strength Study"
            )
        )
        figureSession.workbooks = [figureWorkbook]
        figureSession.groupStates = [
            .init(
                workbookPath: figureWorkbook.response.workbookPath,
                displayName: "Strength Study",
                includeInCompare: true,
                sortOrder: 0
            ),
        ]
        figureSession.focusedWorkbookPath = figureWorkbook.response.workbookPath
        figureSession.comparisonSet = TestPayloads.dataStudioComparisonSet()
        figureSession.figurePreferences = [
            .init(
                familyID: "strength",
                selectedTemplateID: "box",
                optionsByTemplate: [
                    "box": RenderOptionsPayload(
                        size: "single_panel",
                        stylePreset: "presentation",
                        palettePreset: "shine",
                        visualThemeID: "macarons"
                    ),
                ],
                fitOptionsByTemplate: [:]
            ),
        ]
        figureSession.selectedFigureFamilyID = "strength"
        figureSession.syncFigureSelection()
        figureSession.plotSession.renderOptions = RenderOptionsPayload(
            size: "single_panel",
            stylePreset: "presentation",
            palettePreset: "shine",
            visualThemeID: "macarons"
        )

        let codeConsoleSession = CodeConsoleSession()
        let codeConsoleRun = try makeCodeConsoleRunFixture()
        codeConsoleSession.latestRunResponse = codeConsoleRun
        codeConsoleSession.selectedGeneratedFilePath = codeConsoleRun.generatedFiles.last?.path
        let codeConsoleThumbnailModel = makeSnapshotQuickLookModel()

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
                "Plot imported inspector",
                snapshotPNGData(
                    for: PlotInspectorView(
                        session: importedPlotSession,
                        plotOptionsAdvancedExpanded: true
                    ),
                    size: CGSize(width: 420, height: 760)
                )
            ),
            (
                "Plot data workbook",
                snapshotPNGData(
                    for: PlotDataWorkbookSheet(session: importedPlotSession),
                    size: CGSize(width: 900, height: 640)
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
                    size: CGSize(width: 460, height: 648)
                )
            ),
            (
                "Data Studio figure inspector",
                snapshotPNGData(
                    for: DataStudioInspectorView(
                        session: figureSession,
                        plotOptionsAdvancedExpanded: true
                    ),
                    size: CGSize(width: 420, height: 840)
                )
            ),
            (
                "Code Console outputs preview",
                snapshotPNGData(
                    for: CodeConsoleOutputsView(
                        session: codeConsoleSession,
                        quickLookThumbnailModel: codeConsoleThumbnailModel,
                        quickLookLoadsOnAppear: false
                    ),
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
        hostingView.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return nil
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    private func makeCodeConsoleRunFixture() throws -> CodeConsoleRunResponse {
        let run = TestPayloads.codeConsoleRun()
        let outputDirectory = URL(fileURLWithPath: run.outputDir, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let pdfURL = URL(fileURLWithPath: run.generatedFiles[0].path)
        let csvURL = URL(fileURLWithPath: run.generatedFiles[1].path)
        try writeSnapshotFixturePDF(to: pdfURL)
        try Data("x,y\n1,2\n".utf8).write(to: csvURL, options: .atomic)
        return run
    }

    private func writeSnapshotFixturePDF(to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 320, height: 220)
        guard
            let consumer = CGDataConsumer(url: url as CFURL),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            XCTFail("Expected code-console snapshot PDF context to be created.")
            return
        }

        context.beginPDFPage(nil)
        context.setFillColor(gray: 1.0, alpha: 1.0)
        context.fill(mediaBox)

        context.setFillColor(red: 0.10, green: 0.34, blue: 0.76, alpha: 1.0)
        context.fill(CGRect(x: 24, y: 150, width: 48, height: 46))

        context.setFillColor(red: 0.18, green: 0.56, blue: 0.32, alpha: 1.0)
        context.fill(CGRect(x: 92, y: 124, width: 48, height: 72))

        context.setFillColor(red: 0.89, green: 0.47, blue: 0.12, alpha: 1.0)
        context.fill(CGRect(x: 160, y: 96, width: 48, height: 100))

        context.setStrokeColor(gray: 0.55, alpha: 1.0)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: 24, y: 54))
        context.addLine(to: CGPoint(x: 292, y: 54))
        context.move(to: CGPoint(x: 24, y: 54))
        context.addLine(to: CGPoint(x: 24, y: 196))
        context.strokePath()

        let title = NSAttributedString(
            string: "Code Console Preview",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 16),
                .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1.0),
            ]
        )
        title.draw(at: CGPoint(x: 24, y: 24))

        context.endPDFPage()
        context.closePDF()
    }

    private func makeSnapshotQuickLookModel() -> QuickLookThumbnailModel {
        let thumbnail = NSImage(size: NSSize(width: 320, height: 220))
        thumbnail.lockFocus()
        defer { thumbnail.unlockFocus() }

        NSColor(calibratedWhite: 0.98, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 320, height: 220)).fill()

        NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.90, alpha: 1.0).setFill()
        NSBezierPath(roundedRect: NSRect(x: 20, y: 30, width: 280, height: 160), xRadius: 18, yRadius: 18).fill()

        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: 42, y: 122, width: 112, height: 16), xRadius: 8, yRadius: 8).fill()
        NSBezierPath(roundedRect: NSRect(x: 42, y: 92, width: 196, height: 12), xRadius: 6, yRadius: 6).fill()
        NSBezierPath(roundedRect: NSRect(x: 42, y: 68, width: 160, height: 12), xRadius: 6, yRadius: 6).fill()

        let model = QuickLookThumbnailModel { _, _ in
            QuickLookThumbnailLoadResult(image: thumbnail, errorMessage: nil)
        }
        model.image = thumbnail
        return model
    }

    private func exportSnapshotsIfRequested(_ snapshots: [(String, Data)]) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SCIPLOT_EXPORT_GUI_SNAPSHOTS"] == "1" else {
            return
        }

        let destinationRoot: URL
        if let explicitPath = environment["SCIPLOT_EXPORT_GUI_SNAPSHOTS_DIR"], explicitPath.isEmpty == false {
            destinationRoot = URL(fileURLWithPath: explicitPath, isDirectory: true)
        } else {
            destinationRoot = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("sciplot-gui-snapshots", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        for (label, data) in snapshots {
            let filename = label
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "/", with: "-")
                .appending(".png")
            let destinationURL = destinationRoot.appendingPathComponent(filename)
            try? data.write(to: destinationURL, options: .atomic)
        }
    }
}

private let expectedSnapshotFingerprints: [String: SnapshotFingerprint] = [
    "Plot template gallery": SnapshotFingerprint(
        differenceHash: 0x80b0b0b0b0b0b0b0,
        averageLuma: 0.3163,
        nonWhiteFraction: 1.0000
    ),
    "Plot imported inspector": SnapshotFingerprint(
        differenceHash: 0x0000010101010101,
        averageLuma: 0.9776,
        nonWhiteFraction: 0.1806
    ),
    "Plot data workbook": SnapshotFingerprint(
        differenceHash: 0x8080808080a48300,
        averageLuma: 0.6247,
        nonWhiteFraction: 0.5139
    ),
    "Data Studio template editor": SnapshotFingerprint(
        differenceHash: 0x7001010909190900,
        averageLuma: 0.9779,
        nonWhiteFraction: 0.1944
    ),
    "Data Studio specimen filter": SnapshotFingerprint(
        differenceHash: 0x8ec0c8c8c8c8c880,
        averageLuma: 0.6377,
        nonWhiteFraction: 0.6111
    ),
    "Data Studio figure inspector": SnapshotFingerprint(
        differenceHash: 0x0101010101010101,
        averageLuma: 0.9770,
        nonWhiteFraction: 0.1528
    ),
    "Code Console outputs preview": SnapshotFingerprint(
        differenceHash: 0x000000c0e0e0c000,
        averageLuma: 0.0492,
        nonWhiteFraction: 1.0000
    ),
    "Composer canvas selection": SnapshotFingerprint(
        differenceHash: 0x8000050001070787,
        averageLuma: 0.9800,
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
