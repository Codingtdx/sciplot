import XCTest
@testable import SciPlotGodMac

@MainActor
final class PlotSessionTests: XCTestCase {
    func testPlotHappyPathImportInspectContinuePreviewAndExport() async throws {
        let client = MockSidecarClient()
        let destinationURL = URL(fileURLWithPath: "/tmp/user_exports/custom_curve.pdf")
        var chooserCalls: [(String, Bool)] = []
        var materializeCalls: [([URL], URL)] = []
        let session = PlotSession(
            chooseExportDestination: { suggestedName, isMultiOutput in
                chooserCalls.append((suggestedName, isMultiOutput))
                return destinationURL
            },
            materializeExport: { sourceURLs, destination in
                materializeCalls.append((sourceURLs, destination))
                return [destination]
            }
        )
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.importFileAndInspect(URL(fileURLWithPath: "/tmp/sample.csv"))

        XCTAssertEqual(session.workspaceMode, .review)
        XCTAssertFalse(session.needsInspection)
        XCTAssertEqual(session.selectedTemplateID, "curve")
        XCTAssertEqual(session.sampleRows.count, 3)
        XCTAssertEqual(client.inspectRequests.first?.inputPath, "/tmp/sample.csv")

        await session.continueToRefine()

        XCTAssertEqual(session.workspaceMode, .refine)
        XCTAssertEqual(client.renderRequests.first?.template, "curve")
        XCTAssertEqual(session.previewResponse?.previews.first?.filename, "sample_curve.png")

        await session.runPreflight()
        await session.exportCurrentSelection()

        XCTAssertEqual(client.preflightRequests.first?.template, "curve")
        XCTAssertEqual(client.exportRequests.first?.template, "curve")
        XCTAssertEqual(session.exportResponse?.manifestPath, "/tmp/plot_exports/manifest.json")
        XCTAssertEqual(chooserCalls.count, 1)
        XCTAssertEqual(chooserCalls.first?.1, false)
        XCTAssertEqual(materializeCalls.count, 1)
        XCTAssertEqual(materializeCalls.first?.1, destinationURL)
        XCTAssertEqual(materializeCalls.first?.0.first?.path, "/tmp/plot_exports/sample_curve.pdf")
        XCTAssertEqual(session.userExportURLs, [destinationURL])
    }

    func testSelectingSheetReinspectsAndInvalidatesRenderArtifacts() async {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.importFileAndInspect(URL(fileURLWithPath: "/tmp/sample.csv"))
        await session.continueToRefine()
        await session.runPreflight()

        XCTAssertNotNil(session.previewResponse)
        XCTAssertNotNil(session.preflightResponse)

        client.inspectResponse = InspectFileResponse(
            inputPath: "/tmp/sample.csv",
            sheet: .name("Strength_Box"),
            sheetNames: ["Representative_Curve", "Strength_Box"],
            inspection: client.inspectResponse.inspection,
            dataset: client.inspectResponse.dataset
        )

        await session.selectSheetAndReinspect(.name("Strength_Box"))

        XCTAssertEqual(client.inspectRequests.count, 2)
        XCTAssertEqual(client.inspectRequests.last?.sheet, .name("Strength_Box"))
        XCTAssertEqual(session.selectedSheet, .name("Strength_Box"))
        XCTAssertEqual(session.workspaceMode, .review)
        XCTAssertFalse(session.needsInspection)
        XCTAssertNil(session.previewResponse)
        XCTAssertNil(session.preflightResponse)
        XCTAssertNil(session.exportResponse)
    }

    func testCleanupSeedTriggersImmediateInspectAndStaysInReview() async {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.seedFromCleanup(
            workbookURL: URL(fileURLWithPath: "/tmp/cleanup_prepared.xlsx"),
            preferredSheet: .name("Strength_Box")
        )

        for _ in 0..<20 where client.inspectRequests.isEmpty {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(client.inspectRequests.count, 1)
        XCTAssertEqual(client.inspectRequests.first?.inputPath, "/tmp/cleanup_prepared.xlsx")
        XCTAssertEqual(client.inspectRequests.first?.sheet, .name("Strength_Box"))
        XCTAssertEqual(session.workspaceMode, .review)
    }

    func testTemplateGalleryUsesMetaBeforeInspectAndCompatibleAfterInspect() async {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        XCTAssertEqual(session.templateGalleryItems.map(\.id), ["curve", "bar"])
        XCTAssertTrue(session.templateGalleryItems.allSatisfy { !$0.selectable })

        await session.importFileAndInspect(URL(fileURLWithPath: "/tmp/sample.csv"))

        XCTAssertEqual(session.templateGalleryItems.map(\.id), ["curve"])
        XCTAssertTrue(session.templateGalleryItems.allSatisfy(\.selectable))
        XCTAssertEqual(session.unavailableTemplateCount, 1)
    }

    func testImportInspectPipelinePopulatesSourceAndCompatibleTemplatesAfterBootstrapState() async {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        XCTAssertFalse(session.templateGalleryItems.isEmpty)
        XCTAssertTrue(session.templateGalleryItems.allSatisfy { !$0.selectable })

        await session.importFileAndInspect(URL(fileURLWithPath: "/tmp/runtime-symptom.csv"))

        XCTAssertEqual(session.selectedSourcePath, "/tmp/runtime-symptom.csv")
        XCTAssertEqual(client.inspectRequests.count, 1)
        XCTAssertEqual(client.inspectRequests.first?.inputPath, "/tmp/runtime-symptom.csv")
        XCTAssertNotNil(session.inspectionResponse)
        XCTAssertFalse(session.compatibleRecommendations.isEmpty)
        XCTAssertFalse(session.templateGalleryItems.isEmpty)
        XCTAssertTrue(session.templateGalleryItems.allSatisfy(\.selectable))
        XCTAssertEqual(Set(session.templateGalleryItems.map(\.id)), session.compatibleTemplateIDs)
    }

    func testChangingRenderOptionsInvalidatesPreviewPreflightAndExport() async {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.importFileAndInspect(URL(fileURLWithPath: "/tmp/sample.csv"))
        await session.continueToRefine()
        await session.runPreflight()

        XCTAssertNotNil(session.previewResponse)
        XCTAssertNotNil(session.preflightResponse)

        session.renderOptions.xscale = "log"

        XCTAssertNil(session.previewResponse)
        XCTAssertNil(session.preflightResponse)
        XCTAssertNil(session.exportResponse)
        XCTAssertTrue(session.userExportURLs.isEmpty)
    }

    func testPlotExportUsesBaseStemModeForRheologyMultiOutput() async {
        let client = MockSidecarClient()
        client.inspectResponse = InspectFileResponse(
            inputPath: "/tmp/sample.csv",
            sheet: .name("Representative_Curve"),
            sheetNames: ["Representative_Curve", "Strength_Box"],
            inspection: .init(
                model: "frequency_sweep",
                modelLabel: client.inspectResponse.inspection.modelLabel,
                recommendation: client.inspectResponse.inspection.recommendation,
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
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.importFileAndInspect(URL(fileURLWithPath: "/tmp/sample.csv"))
        session.chooseTemplate("point_line")
        await session.exportCurrentSelection()

        XCTAssertEqual(chooserIsMultiOutput, true)
        XCTAssertEqual(session.userExportURLs.count, 2)
    }
}
