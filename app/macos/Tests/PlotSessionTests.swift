import AppKit
import Foundation
import PDFKit
import XCTest
@testable import SciPlotGodMac

@MainActor
final class PlotSessionTests: XCTestCase {
    func testExportAvailabilityExplainsBlockingStates() async throws {
        let session = PlotSession()
        XCTAssertFalse(session.exportAvailability.isEnabled)
        XCTAssertTrue(session.exportAvailability.reason?.contains("sidecar") ?? false)

        let client = MockSidecarClient()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        XCTAssertFalse(session.exportAvailability.isEnabled)
        XCTAssertTrue(session.exportAvailability.reason?.contains("Import a source file") ?? false)

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        XCTAssertTrue(session.exportAvailability.isEnabled)
        XCTAssertNil(session.exportAvailability.reason)
    }

    func testUndoRestoresTemplateAndRenderOptions() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        let undoManager = UndoManager()
        session.attachUndoManager(undoManager)
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        XCTAssertEqual(session.selectedTemplateID, "curve")
        session.chooseTemplate("bar")
        XCTAssertEqual(session.selectedTemplateID, "bar")
        undoManager.undo()
        XCTAssertEqual(session.selectedTemplateID, "curve")

        let originalXScale = session.renderOptions.xscale
        session.updateRenderOptions(policy: .immediate) { $0.xscale = "log" }
        XCTAssertEqual(session.renderOptions.xscale, "log")
        undoManager.undo()
        XCTAssertEqual(session.renderOptions.xscale, originalXScale)
    }

    func testImportAutomaticallyInspectsSelectsTemplateAndRendersPreview() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))

        await waitUntil(
            { session.previewResponse != nil && session.inspectionResponse != nil },
            timeout: 2.0
        )

        XCTAssertEqual(client.inspectRequests.first?.inputPath, "/tmp/sample.csv")
        XCTAssertEqual(client.inspectRequests.first?.sheet, .index(0))
        XCTAssertEqual(session.selectedSheet, .name("Representative_Curve"))
        XCTAssertEqual(session.selectedTemplateID, "curve")
        XCTAssertEqual(client.renderRequests.first?.template, "curve")
        XCTAssertEqual(session.previewResponse?.previews.first?.filename, "sample_curve.pdf")
        XCTAssertEqual(session.liveStatusLabel, "Preview ready")
    }

    func testSheetChangesReinspectAndRefreshPreviewWithoutClearingTheLastResult() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        let initialPreview = session.previewResponse
        client.inspectHandler = { request in
            try await Task.sleep(nanoseconds: 120_000_000)
            return InspectFileResponse(
                inputPath: request.inputPath,
                sheet: .name("Strength_Box"),
                sheetNames: ["Representative_Curve", "Strength_Box"],
                inspection: client.inspectResponse.inspection,
                dataset: client.inspectResponse.dataset
            )
        }
        client.renderHandler = { request in
            try await Task.sleep(nanoseconds: 120_000_000)
            return RenderPreviewResponse(
                template: request.template,
                requestedTemplateID: request.template,
                canonicalID: request.template,
                role: "plot",
                lifecyclePolicy: "stable",
                implementationID: request.template,
                sheet: request.sheet,
                previews: [
                    .init(filename: "strength_box_preview.pdf", pdfBase64: TestPayloads.pdfBase64, qa: nil),
                ],
                submissionReport: TestPayloads.submissionReport()
            )
        }

        session.setSelectedSheet(.name("Strength_Box"))

        XCTAssertEqual(session.previewResponse, initialPreview)
        XCTAssertTrue(session.isInspecting)

        await waitUntil(
            { session.previewResponse?.previews.first?.filename == "strength_box_preview.pdf" },
            timeout: 3.0
        )

        XCTAssertEqual(client.inspectRequests.last?.sheet, .name("Strength_Box"))
        XCTAssertEqual(client.renderRequests.last?.sheet, .name("Strength_Box"))
        XCTAssertEqual(session.selectedSheet, .name("Strength_Box"))
        XCTAssertEqual(session.previewResponse?.previews.first?.filename, "strength_box_preview.pdf")
    }

    func testTemplateChangeRefreshesPreviewWithoutClearingTheLastResult() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse?.previews.first?.filename == "sample_curve.pdf" }, timeout: 2.0)

        let initialPreview = session.previewResponse
        client.renderHandler = { request in
            try await Task.sleep(nanoseconds: 120_000_000)
            return RenderPreviewResponse(
                template: request.template,
                requestedTemplateID: request.template,
                canonicalID: request.template,
                role: "plot",
                lifecyclePolicy: "stable",
                implementationID: request.template,
                sheet: request.sheet,
                previews: [
                    .init(
                        filename: request.template == "bar" ? "sample_bar.pdf" : "sample_curve.pdf",
                        pdfBase64: TestPayloads.pdfBase64,
                        qa: nil
                    ),
                ],
                submissionReport: TestPayloads.submissionReport()
            )
        }

        session.chooseTemplate("bar")

        XCTAssertEqual(session.previewResponse, initialPreview)
        XCTAssertTrue(session.isPreviewing)

        await waitUntil(
            { session.previewResponse?.previews.first?.filename == "sample_bar.pdf" },
            timeout: 3.0
        )

        XCTAssertEqual(client.renderRequests.last?.template, "bar")
        XCTAssertEqual(session.selectedTemplateID, "bar")
        XCTAssertEqual(session.previewResponse?.previews.first?.filename, "sample_bar.pdf")
    }

    func testDebouncedNumericEditsRefreshOnlyAfterThePause() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        let initialRenderCount = client.renderRequests.count
        session.updateRenderOptions(policy: .debounced) { $0.xMin = 1.0 }
        try await Task.sleep(nanoseconds: 80_000_000)
        session.updateRenderOptions(policy: .debounced) { $0.xMin = 2.0 }

        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(client.renderRequests.count, initialRenderCount)

        await waitUntil({ client.renderRequests.count == initialRenderCount + 1 }, timeout: 3.0)
        XCTAssertEqual(session.renderOptions.xMin, 2.0)
        XCTAssertEqual(session.previewResponse?.previews.first?.filename, "sample_curve.pdf")
    }

    func testLoadingExternalFigureWithoutPreferredOptionsResetsManualAxisOverrides() async throws {
        let client = MockSidecarClient()
        client.inspectHandler = { request in
            TestPayloads.inspectFile(path: request.inputPath)
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.updateRenderOptions(policy: .immediate) {
            $0.xMin = -10
            $0.yMin = -10
        }
        await waitUntil(
            {
                client.renderRequests.last?.options.xMin == -10 &&
                client.renderRequests.last?.options.yMin == -10
            },
            timeout: 3.0
        )

        await session.loadExternalFigure(
            inputURL: URL(fileURLWithPath: "/tmp/external.xlsx"),
            sheet: .name("Representative_Curve"),
            preferredTemplateID: "curve",
            preferredOptions: nil
        )

        XCTAssertEqual(session.selectedFileURL?.path, "/tmp/external.xlsx")
        XCTAssertNil(session.renderOptions.xMin)
        XCTAssertNil(session.renderOptions.xMax)
        XCTAssertNil(session.renderOptions.yMin)
        XCTAssertNil(session.renderOptions.yMax)
        XCTAssertEqual(client.inspectRequests.last?.inputPath, "/tmp/external.xlsx")
        XCTAssertEqual(client.renderRequests.last?.inputPath, "/tmp/external.xlsx")
        XCTAssertNil(client.renderRequests.last?.options.xMin)
        XCTAssertNil(client.renderRequests.last?.options.xMax)
        XCTAssertNil(client.renderRequests.last?.options.yMin)
        XCTAssertNil(client.renderRequests.last?.options.yMax)
    }

    func testAxisLabelOverridesRefreshPreviewAndReachRenderRequests() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        let initialRenderCount = client.renderRequests.count
        session.updateRenderOptions(policy: .debounced) {
            $0.xLabelOverride = "Extension"
            $0.yLabelOverride = "Stress"
        }

        await waitUntil({ client.renderRequests.count == initialRenderCount + 1 }, timeout: 3.0)

        XCTAssertEqual(client.renderRequests.last?.options.xLabelOverride, "Extension")
        XCTAssertEqual(client.renderRequests.last?.options.yLabelOverride, "Stress")
    }

    func testTickLabelOptionsRefreshPreviewAndReachRenderRequests() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        let initialRenderCount = client.renderRequests.count
        session.updateRenderOptions(policy: .immediate) {
            $0.xTickDensity = "sparse"
            $0.xTickEdgeLabels = "hide_min"
            $0.yTickDensity = "dense"
            $0.yTickEdgeLabels = "hide_both"
        }

        await waitUntil({ client.renderRequests.count == initialRenderCount + 1 }, timeout: 3.0)

        XCTAssertEqual(session.renderOptions.xTickDensity, "sparse")
        XCTAssertEqual(session.renderOptions.xTickEdgeLabels, "hide_min")
        XCTAssertEqual(session.renderOptions.yTickDensity, "dense")
        XCTAssertEqual(session.renderOptions.yTickEdgeLabels, "hide_both")
        XCTAssertEqual(client.renderRequests.last?.options.xTickDensity, "sparse")
        XCTAssertEqual(client.renderRequests.last?.options.xTickEdgeLabels, "hide_min")
        XCTAssertEqual(client.renderRequests.last?.options.yTickDensity, "dense")
        XCTAssertEqual(client.renderRequests.last?.options.yTickEdgeLabels, "hide_both")
    }

    func testRenderRequestAutoSanitizesLegacyStylePreset() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)

        let baseMeta = TestPayloads.meta()
        let strictMeta = SidecarMetaResponse(
            version: baseMeta.version,
            defaults: .init(stylePreset: "default", palettePreset: "colorblind_safe"),
            sizes: baseMeta.sizes,
            styles: [
                .init(
                    id: "default",
                    label: "Default",
                    public: true,
                    description: "Default style.",
                    hardConstraints: true,
                    presetNote: "Default preset"
                ),
                .init(
                    id: "nature",
                    label: "Nature",
                    public: true,
                    description: "Nature style.",
                    hardConstraints: true,
                    presetNote: "Nature preset"
                ),
            ],
            palettes: [
                .init(
                    id: "colorblind_safe",
                    label: "Colorblind Safe",
                    public: true,
                    description: "Default palette.",
                    swatches: ["#112233", "#445566"]
                ),
            ],
            templates: baseMeta.templates.map {
                .init(
                    id: $0.id,
                    label: $0.label,
                    description: $0.description,
                    category: $0.category,
                    defaultSize: $0.defaultSize,
                    allowedSizes: $0.allowedSizes,
                    editableOptions: $0.editableOptions,
                    defaultOptions: $0.defaultOptions,
                    availableStyles: ["default", "nature"],
                    availablePalettes: ["colorblind_safe"],
                    canonicalID: $0.canonicalID,
                    role: $0.role,
                    lifecyclePolicy: $0.lifecyclePolicy,
                    implementationID: $0.implementationID
                )
            },
            templateIds: baseMeta.templateIds,
            sizeIds: baseMeta.sizeIds,
            palettePresetIds: ["colorblind_safe"],
            visualThemes: baseMeta.visualThemes
        )

        session.apply(meta: strictMeta, contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        let initialRenderCount = client.renderRequests.count
        session.updateRenderOptions(policy: .immediate) {
            $0.stylePreset = "journal_calm"
        }

        await waitUntil({ client.renderRequests.count == initialRenderCount + 1 }, timeout: 3.0)

        XCTAssertEqual(client.renderRequests.last?.options.stylePreset, "default")
        XCTAssertEqual(session.renderOptions.stylePreset, "default")
        XCTAssertNil(session.errorMessage)
    }

    func testSeriesLegendControlsOnlyAppearForMultiSeriesTemplates() async throws {
        let client = MockSidecarClient()
        client.inspectResponse = TestPayloads.multiSeriesInspectFile(path: "/tmp/multiseries.csv")

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.multiSeriesMeta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/multiseries.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        XCTAssertTrue(session.shouldShowSeriesLegendControls)
        XCTAssertEqual(session.seriesOrderLabels, ["Series A", "Series B"])

        let singleSeriesSession = PlotSession()
        singleSeriesSession.configure(client: MockSidecarClient())
        singleSeriesSession.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        singleSeriesSession.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ singleSeriesSession.previewResponse != nil }, timeout: 2.0)

        XCTAssertFalse(singleSeriesSession.shouldShowSeriesLegendControls)
    }

    func testPlotExportUsesBaseStemModeForRheologyMultiOutput() async throws {
        let client = MockSidecarClient()
        client.inspectResponse = InspectFileResponse(
            inputPath: "/tmp/sample.csv",
            sheet: .name("Representative_Curve"),
            sheetNames: ["Representative_Curve", "Strength_Box"],
            inspection: .init(
                model: "frequency_sweep",
                modelLabel: client.inspectResponse.inspection.modelLabel,
                recommendations: client.inspectResponse.inspection.recommendations,
                primaryRecommendation: client.inspectResponse.inspection.primaryRecommendation,
                alternativeRecommendations: client.inspectResponse.inspection.alternativeRecommendations,
                advancedTemplates: client.inspectResponse.inspection.advancedTemplates,
                recommendationConfidence: client.inspectResponse.inspection.recommendationConfidence,
                recommendationSummary: client.inspectResponse.inspection.recommendationSummary,
                warnings: client.inspectResponse.inspection.warnings,
                signals: client.inspectResponse.inspection.signals
            ),
            dataset: client.inspectResponse.dataset
        )
        client.exportResponse = ExportRenderResponse(
            requestedTemplateID: "point_line",
            canonicalID: "point_line",
            role: "canonical",
            lifecyclePolicy: "canonical",
            implementationID: "plot.point_line",
            outputs: [
                "/tmp/plot_exports/freq_storage_modulus_point_line.pdf",
                "/tmp/plot_exports/freq_loss_modulus_point_line.pdf",
            ],
            outputDir: "/tmp/plot_exports",
            previewOutputs: [],
            artifactPaths: [],
            manifestPath: nil,
            submissionReport: nil
        )

        var chooserIsMultiOutput: Bool?
        let session = PlotSession(
            chooseExportDestination: { _, isMultiOutput in
                chooserIsMultiOutput = isMultiOutput
                return URL(fileURLWithPath: "/tmp/user_exports/rheology_group.pdf")
            },
            materializeExport: { _, destination in
                [
                    destination.deletingLastPathComponent().appendingPathComponent("rheology_group_storage_modulus_point_line.pdf"),
                    destination.deletingLastPathComponent().appendingPathComponent("rheology_group_loss_modulus_point_line.pdf"),
                ]
            }
        )
        session.configure(client: client)
        session.apply(meta: TestPayloads.multiSeriesMeta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)
        session.chooseTemplate("point_line")
        await session.exportCurrentSelection()

        XCTAssertEqual(chooserIsMultiOutput, true)
        XCTAssertEqual(session.userExportURLs.count, 2)
    }

    func testPlotExportCanMaterializeTIFFOutput() async throws {
        let client = MockSidecarClient()

        var materializedDestination: URL?
        let session = PlotSession(
            chooseExportDestination: { _, _ in
                URL(fileURLWithPath: "/tmp/user_exports/sample_curve.tiff")
            },
            materializeExport: { sourceURLs, destination in
                XCTAssertEqual(sourceURLs.map(\.pathExtension), ["pdf"])
                XCTAssertEqual(destination.pathExtension.lowercased(), "tiff")
                materializedDestination = destination
                return [destination]
            }
        )
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)
        await session.exportCurrentSelection()

        XCTAssertEqual(materializedDestination?.path, "/tmp/user_exports/sample_curve.tiff")
        XCTAssertEqual(session.userExportURLs.map { $0.pathExtension.lowercased() }, ["tiff"])
    }

    func testPreviewErrorShowsOnlyUserFacingTailSentence() async throws {
        let client = MockSidecarClient()
        client.renderHandler = { _ in
            throw SidecarError.httpStatus(
                400,
                "Could not render the live preview. Tensile curves must use linear axes. Log x / y is not supported."
            )
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.errorMessage != nil }, timeout: 2.0)

        XCTAssertEqual(session.errorMessage, "Log x / y is not supported.")
    }

    private func waitUntil(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for PlotSession state")
    }
}

@MainActor
final class PDFPreviewViewTests: XCTestCase {
    func testPlotPDFViewConfiguresSinglePageFitDefaults() {
        let view = PlotPDFView()
        view.configureForPlotPreview()

        XCTAssertEqual(view.displayMode, .singlePage)
        XCTAssertFalse(view.displaysPageBreaks)
        XCTAssertTrue(view.autoScales)
    }

    func testPlotPDFViewResetToFitRestoresStableZoomRange() throws {
        guard
            let data = Data(base64Encoded: TestPayloads.pdfBase64),
            let document = PDFDocument(data: data)
        else {
            XCTFail("Expected valid fixture PDF payload.")
            return
        }

        let view = PlotPDFView()
        view.configureForPlotPreview()
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        view.document = document
        view.autoScales = false
        view.scaleFactor = max(2.0, view.scaleFactorForSizeToFit * 2.0)

        view.resetToFit()

        XCTAssertTrue(view.autoScales)
        XCTAssertGreaterThan(view.scaleFactor, 0.0)
        XCTAssertGreaterThan(view.minScaleFactor, 0.0)
        XCTAssertGreaterThan(view.maxScaleFactor, view.minScaleFactor)
    }

    func testPlotPDFViewResetToFitWaitsForUsableBounds() throws {
        guard
            let data = Data(base64Encoded: TestPayloads.pdfBase64),
            let document = PDFDocument(data: data)
        else {
            XCTFail("Expected valid fixture PDF payload.")
            return
        }

        let view = PlotPDFView()
        view.configureForPlotPreview()
        view.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        view.document = document
        view.autoScales = false
        view.scaleFactor = 0.05

        view.resetToFit()
        let beforeResizeScale = view.scaleFactor

        view.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.autoScales)
        XCTAssertGreaterThan(view.scaleFactor, beforeResizeScale)
        XCTAssertGreaterThan(view.maxScaleFactor, view.minScaleFactor)
    }

    func testPreviewImageDecoderCachesDecodedPNGImageInstances() {
        guard
            let firstImage = PreviewImageDecoder.decodeBase64PNG(TestPayloads.pngBase64),
            let secondImage = PreviewImageDecoder.decodeBase64PNG(TestPayloads.pngBase64)
        else {
            XCTFail("Expected valid PNG preview payload")
            return
        }

        XCTAssertTrue(firstImage === secondImage)
    }

    func testPreviewImageDecoderLooksLikePDFHeader() {
        guard
            let pdfData = PreviewImageDecoder.decodeBase64Data(TestPayloads.pdfBase64),
            let pngData = PreviewImageDecoder.decodeBase64Data(TestPayloads.pngBase64)
        else {
            XCTFail("Expected decodable preview payloads")
            return
        }

        XCTAssertTrue(PreviewImageDecoder.looksLikePDFData(pdfData))
        XCTAssertFalse(PreviewImageDecoder.looksLikePDFData(pngData))
    }
}
