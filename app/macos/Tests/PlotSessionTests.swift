import Foundation
import XCTest
@testable import SciPlotGodMac

@MainActor
final class PlotSessionTests: XCTestCase {
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
