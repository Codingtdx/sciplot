import AppKit
import SwiftUI
import XCTest
@testable import SciPlotGodMac

final class InspectorLayoutPolicyTests: XCTestCase {
    func testUnifiedInspectorColumnWidthPolicyStaysStable() {
        XCTAssertEqual(InspectorColumnLayoutPolicy.minWidth, 320)
        XCTAssertEqual(InspectorColumnLayoutPolicy.idealWidth, 360)
        XCTAssertEqual(InspectorColumnLayoutPolicy.maxWidth, 420)
        XCTAssertLessThan(InspectorColumnLayoutPolicy.minWidth, InspectorColumnLayoutPolicy.idealWidth)
        XCTAssertLessThan(InspectorColumnLayoutPolicy.idealWidth, InspectorColumnLayoutPolicy.maxWidth)
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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
        importedPlotSession.previewResponse = TestPayloads.renderPreview()

        let launcherModel = AppModel(runtime: SidecarRuntime(), client: MockSidecarClient())

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
                "Launcher",
                snapshotPNGData(
                    for: LauncherView(model: launcherModel),
                    size: CGSize(width: 1180, height: 700),
                    colorScheme: .dark
                )
            ),
            (
                "Plot workspace empty",
                snapshotPNGData(
                    for: PlotWorkbenchView(session: plotSession),
                    size: CGSize(width: 1100, height: 720),
                    colorScheme: .dark
                )
            ),
            (
                "Plot workspace imported",
                snapshotPNGData(
                    for: PlotWorkbenchView(session: importedPlotSession),
                    size: CGSize(width: 1100, height: 720),
                    colorScheme: .dark
                )
            ),
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

    @MainActor
    private func snapshotPNGData<V: View>(
        for view: V,
        size: CGSize,
        colorScheme: ColorScheme = .light
    ) -> Data? {
        let rootedView = AnyView(
            view
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.colorScheme, colorScheme)
        )
        let hostingView = NSHostingView(rootView: rootedView)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.setFrameSize(size)
        hostingView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
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

    @MainActor
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
