import AppKit
import Foundation
import ImageIO
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

        session.updateFitModel("polynomial_2")
        XCTAssertEqual(session.fitOptions.modelID, "polynomial_2")
        undoManager.undo()
        XCTAssertEqual(session.fitOptions.modelID, "linear")
    }

    func testAxisBreaksRoundTripThroughSessionSanitization() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.applyExternalRenderOptions(
            RenderOptionsPayload(
                stylePreset: "nature",
                palettePreset: "colorblind_safe",
                visualThemeID: "clean_light",
                xAxisBreaks: [AxisBreakPayload(id: "x-gap", enabled: true, start: 0.8, end: 1.2, displayMode: "split")],
                yAxisBreaks: [AxisBreakPayload(id: "y-gap", enabled: true, start: 1.4, end: 2.2, displayMode: "compress")]
            )
        )

        XCTAssertEqual(session.renderOptions.xAxisBreaks?.first?.id, "x-gap")
        XCTAssertEqual(session.renderOptions.xAxisBreaks?.first?.displayMode, "split")
        XCTAssertNil(session.renderOptions.yAxisBreaks)

        session.updateRenderOptions(policy: .immediate) { $0.xscale = "log" }
        session.sanitizeRenderOptionsForCurrentTemplateIfNeeded()

        XCTAssertNil(session.renderOptions.xAxisBreaks)
        XCTAssertNil(session.renderOptions.yAxisBreaks)

        session.updateRenderOptions(policy: .immediate) {
            $0.extraYAxis = ExtraAxisPayload(enabled: true, position: "right", title: "Secondary")
        }
        session.sanitizeRenderOptionsForCurrentTemplateIfNeeded()

        XCTAssertNil(session.renderOptions.yAxisBreaks)
        XCTAssertEqual(session.renderOptions.extraYAxis?.title, "Secondary")
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
        XCTAssertEqual(session.liveStatusSymbol, "checkmark.circle.fill")
    }

    func testStyleStudioDraftAndSaveRefreshPreviewWithCustomThemePayload() async throws {
        let client = MockSidecarClient()
        let draft = CustomPlotThemePackagePayload(
            id: "user/nature_plus",
            label: "Nature Plus",
            baseStyleID: "nature",
            palettePreset: "colorblind_safe",
            visualThemeID: "clean_light",
            palette: CustomPlotThemePalettePayload(categorical: ["#0ea5e9", "#f97316"]),
            hardOverrides: ["typography": ["font_size_pt": .number(7.2)]],
            softOverrides: ["axes.grid": .bool(true)],
            expertRcParams: ["grid.linestyle": .string(":")]
        )
        client.plotThemePreviewResponse = PlotThemePreviewResponse(theme: draft, blockedKeys: [], warnings: [])
        client.plotThemeSaveResponse = PlotThemeSaveResponse(theme: draft, blockedKeys: [], warnings: [])

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        let initialRenderCount = client.renderRequests.count
        await session.applyStyleStudioDraft(draft)

        await waitUntil({ client.renderRequests.count == initialRenderCount + 1 }, timeout: 3.0)
        XCTAssertEqual(session.renderOptions.customThemeDraft?.id, "user/nature_plus")
        XCTAssertEqual(client.renderRequests.last?.options.customThemeDraft?.id, "user/nature_plus")

        await session.saveStyleStudioTheme(draft)

        XCTAssertEqual(client.plotThemeSaveRequests.last?.theme.id, "user/nature_plus")
        XCTAssertEqual(session.renderOptions.customThemeID, "user/nature_plus")
        XCTAssertEqual(session.renderOptions.customThemeDraft?.id, "user/nature_plus")
    }

    func testProjectDirtyTracksDurablePlotStateOnly() async throws {
        let client = MockSidecarClient()
        client.saveProjectHandler = { request in
            SaveProjectResponse(projectPath: request.projectPath, payload: request.payload)
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        XCTAssertTrue(session.isProjectDirty)

        await session.saveProject(to: URL(fileURLWithPath: "/tmp/sample.sciplotgod"))

        XCTAssertFalse(session.isProjectDirty)
        XCTAssertEqual(session.projectURL?.path, "/tmp/sample.sciplotgod")

        session.showDataWorkbook()
        session.sourceTableOffset = 50
        session.errorMessage = "Temporary"

        XCTAssertFalse(session.isProjectDirty)

        session.updateRenderOptions(policy: .immediate) { $0.xMin = 1.0 }

        XCTAssertTrue(session.isProjectDirty)

        await session.saveProject(to: URL(fileURLWithPath: "/tmp/sample.sciplotgod"))
        XCTAssertFalse(session.isProjectDirty)

        session.updateFitEnabled(true)
        XCTAssertTrue(session.isProjectDirty)
    }

    func testOpenProjectRestoresPlotStateAndClearsDirty() async throws {
        let client = MockSidecarClient()
        let restoredPayload = TestPayloads.plotProjectPayload(
            sourcePath: "/tmp/restored/project-source.csv",
            projectName: "Curve Study",
            templateID: "area_curve",
            sheet: .name("RestoredSheet"),
            fitOptions: FitOptionsPayload(enabled: true, modelID: "polynomial_2"),
            renderOptions: RenderOptionsPayload(
                size: "single_panel",
                stylePreset: "presentation",
                palettePreset: "shine",
                visualThemeID: "shine",
                extraXAxis: ExtraAxisPayload(
                    enabled: true,
                    position: "top",
                    title: "Gallons",
                    dataValue: 3.78541,
                    displayValue: 1.0
                ),
                extraYAxis: ExtraAxisPayload(
                    enabled: true,
                    position: "right",
                    bindingMode: "series_assignment",
                    seriesIDs: ["Sample B"],
                    title: "Half Stress",
                    dataValue: 2.0,
                    displayValue: 1.0
                ),
                referenceGuides: [
                    ReferenceGuidePayload(
                        id: "target-line",
                        enabled: true,
                        kind: "line",
                        axisTarget: "y_primary",
                        value: 2.5,
                        label: "Target"
                    ),
                    ReferenceGuidePayload(
                        id: "window-region",
                        enabled: true,
                        kind: "band",
                        axisTarget: "x",
                        value: nil,
                        start: 0.5,
                        end: 1.5,
                        label: "Window"
                    )
                ],
                textAnnotations: [
                    TextAnnotationPayload(
                        id: "note-1",
                        enabled: true,
                        text: "Peak",
                        coordinateSpace: "data",
                        x: 1.5,
                        y: 2.2,
                        yAxisTarget: "y_primary",
                        horizontalAlignment: "right",
                        verticalAlignment: "bottom",
                        displayStyle: "callout",
                        connectorEnabled: true,
                        targetX: 1.0,
                        targetY: 2.0,
                        targetYAxisTarget: "y_primary"
                    )
                ],
                shapeAnnotations: [
                    ShapeAnnotationPayload(
                        id: "focus-window",
                        enabled: true,
                        kind: "rectangle",
                        bracketOrientation: "horizontal",
                        xStart: 0.5,
                        xEnd: 1.5,
                        yStart: 2.0,
                        yEnd: 3.0,
                        yAxisTarget: "y_primary",
                        label: "Window"
                    )
                ]
            )
        )
        client.openProjectResponse = TestPayloads.openProjectResponse(
            projectPath: "/tmp/curve.sciplotgod",
            restoredSourcePath: "/tmp/restored/project-source.csv",
            payload: restoredPayload
        )
        client.inspectHandler = { request in
            InspectFileResponse(
                inputPath: request.inputPath,
                sheet: request.sheet,
                sheetNames: ["RestoredSheet"],
                inspection: client.inspectResponse.inspection,
                dataset: client.inspectResponse.dataset
            )
        }
        client.renderHandler = { request in
            RenderPreviewResponse(
                template: request.template,
                requestedTemplateID: request.template,
                canonicalID: request.template,
                role: "plot",
                lifecyclePolicy: "stable",
                implementationID: request.template,
                sheet: request.sheet,
                previews: [.init(filename: "restored_preview.pdf", pdfBase64: TestPayloads.pdfBase64, qa: nil)],
                submissionReport: TestPayloads.submissionReport()
            )
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.openProject(URL(fileURLWithPath: "/tmp/curve.sciplotgod"))
        await waitUntil({ session.previewResponse?.previews.first?.filename == "restored_preview.pdf" }, timeout: 2.0)

        XCTAssertEqual(client.openProjectRequests.first?.projectPath, "/tmp/curve.sciplotgod")
        XCTAssertEqual(session.projectURL?.path, "/tmp/curve.sciplotgod")
        XCTAssertEqual(session.selectedFileURL?.path, "/tmp/restored/project-source.csv")
        XCTAssertEqual(session.selectedSheet, .name("RestoredSheet"))
        XCTAssertEqual(session.selectedTemplateID, "area_curve")
        XCTAssertEqual(session.renderOptions.stylePreset, "presentation")
        XCTAssertEqual(session.renderOptions.palettePreset, "shine")
        XCTAssertEqual(session.renderOptions.visualThemeID, "shine")
        XCTAssertEqual(
            session.renderOptions.extraXAxis,
            ExtraAxisPayload(enabled: true, position: "top", title: "Gallons", dataValue: 3.78541, displayValue: 1.0)
        )
        XCTAssertEqual(
            session.renderOptions.extraYAxis,
            ExtraAxisPayload(
                enabled: true,
                position: "right",
                bindingMode: "series_assignment",
                seriesIDs: ["Sample B"],
                title: "Half Stress",
                dataValue: 2.0,
                displayValue: 1.0
            )
        )
        XCTAssertEqual(
            session.renderOptions.referenceGuides,
            [
                ReferenceGuidePayload(
                    id: "target-line",
                    enabled: true,
                    kind: "line",
                    axisTarget: "y_primary",
                    value: 2.5,
                    label: "Target"
                ),
                ReferenceGuidePayload(
                    id: "window-region",
                    enabled: true,
                    kind: "band",
                    axisTarget: "x",
                    value: nil,
                    start: 0.5,
                    end: 1.5,
                    label: "Window"
                )
            ]
        )
        XCTAssertEqual(session.renderOptions.textAnnotations?.first?.text, "Peak")
        XCTAssertEqual(session.renderOptions.textAnnotations?.first?.coordinateSpace, "data")
        XCTAssertEqual(session.renderOptions.shapeAnnotations?.first?.label, "Window")
        XCTAssertEqual(session.fitOptions, FitOptionsPayload(enabled: true, modelID: "polynomial_2"))
        XCTAssertFalse(session.isProjectDirty)
    }

    func testOpenProjectWithCoreAdvancedStateKeepsTransformAwareInspectAndWorkbookRequests() async throws {
        let client = MockSidecarClient()
        let restoredOptions = RenderOptionsPayload(
            size: "single_panel",
            stylePreset: "nature",
            palettePreset: "colorblind_safe",
            visualThemeID: "clean_light",
            referenceGuides: [
                ReferenceGuidePayload(
                    id: "target-line",
                    enabled: true,
                    kind: "line",
                    axisTarget: "y_primary",
                    value: 2.5,
                    label: "Target"
                )
            ],
            textAnnotations: [
                TextAnnotationPayload(
                    id: "note-1",
                    enabled: true,
                    text: "Peak",
                    coordinateSpace: "data",
                    x: 1.5,
                    y: 2.2,
                    yAxisTarget: "y_primary",
                    horizontalAlignment: "right",
                    verticalAlignment: "bottom",
                    displayStyle: "callout",
                    connectorEnabled: true,
                    targetX: 1.0,
                    targetY: 2.0,
                    targetYAxisTarget: "y_primary"
                )
            ],
            shapeAnnotations: [
                ShapeAnnotationPayload(
                    id: "focus-window",
                    enabled: true,
                    kind: "rectangle",
                    bracketOrientation: "horizontal",
                    xStart: 0.5,
                    xEnd: 1.5,
                    yStart: 2.0,
                    yEnd: 3.0,
                    yAxisTarget: "y_primary",
                    label: "Window"
                )
            ],
            dataVariables: [
                DataVariablePayload(
                    id: "scale",
                    enabled: true,
                    kind: "scalar",
                    label: "Scale",
                    value: 2.0
                )
            ],
            dataTransforms: [
                DataTransformPayload(
                    id: "double-y",
                    enabled: true,
                    kind: "derived_column",
                    targetColumn: "Y_scaled",
                    expression: "col('Y') * var('scale')"
                ),
                DataTransformPayload(
                    id: "filter-window",
                    enabled: true,
                    kind: "row_filter",
                    label: "Window",
                    column: "X",
                    filterOperator: "between",
                    lower: 1.0,
                    upper: 2.0
                )
            ]
        )
        let restoredPayload = TestPayloads.plotProjectPayload(
            sourcePath: "/tmp/restored/core-advanced.csv",
            projectName: "Core Advanced",
            templateID: "curve",
            sheet: .name("RestoredSheet"),
            fitOptions: FitOptionsPayload(enabled: true, modelID: "polynomial_2"),
            renderOptions: restoredOptions
        )
        client.openProjectResponse = TestPayloads.openProjectResponse(
            projectPath: "/tmp/core-advanced.sciplotgod",
            restoredSourcePath: "/tmp/restored/core-advanced.csv",
            payload: restoredPayload
        )
        client.inspectHandler = { request in
            InspectFileResponse(
                inputPath: request.inputPath,
                sheet: request.sheet,
                sheetNames: ["RestoredSheet"],
                inspection: client.inspectResponse.inspection,
                dataset: client.inspectResponse.dataset
            )
        }
        client.renderHandler = { request in
            RenderPreviewResponse(
                template: request.template,
                requestedTemplateID: request.template,
                canonicalID: request.template,
                role: "plot",
                lifecyclePolicy: "stable",
                implementationID: request.template,
                sheet: request.sheet,
                previews: [.init(filename: "core_advanced_preview.pdf", pdfBase64: TestPayloads.pdfBase64, qa: nil)],
                submissionReport: TestPayloads.submissionReport()
            )
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.openProject(URL(fileURLWithPath: "/tmp/core-advanced.sciplotgod"))
        await waitUntil({ session.previewResponse?.previews.first?.filename == "core_advanced_preview.pdf" }, timeout: 2.0)

        XCTAssertEqual(client.inspectRequests.last?.inputPath, "/tmp/restored/core-advanced.csv")
        XCTAssertEqual(client.inspectRequests.last?.sheet, .name("RestoredSheet"))
        XCTAssertEqual(client.inspectRequests.last?.options?.dataVariables?.first?.id, "scale")
        XCTAssertEqual(client.inspectRequests.last?.options?.dataTransforms?.last?.filterOperator, "between")

        XCTAssertEqual(client.renderRequests.last?.fitOptions, FitOptionsPayload(enabled: true, modelID: "polynomial_2"))
        XCTAssertEqual(client.renderRequests.last?.options.referenceGuides?.first?.label, "Target")
        XCTAssertEqual(client.renderRequests.last?.options.textAnnotations?.first?.text, "Peak")
        XCTAssertEqual(client.renderRequests.last?.options.shapeAnnotations?.first?.label, "Window")
        XCTAssertEqual(client.renderRequests.last?.options.dataVariables?.first?.id, "scale")
        XCTAssertEqual(client.renderRequests.last?.options.dataTransforms?.first?.targetColumn, "Y_scaled")

        session.showDataWorkbook()
        session.refreshDataWorkbookIfNeeded()
        session.selectDataWorkbookTab(.transformed)
        await waitUntil(
            { client.sourceTablePreviewRequests.last?.options?.dataTransforms?.first?.targetColumn == "Y_scaled" },
            timeout: 2.0
        )

        session.selectDataWorkbookTab(.fit)
        await waitUntil(
            {
                client.fitAnalysisRequests.last?.options?.dataTransforms?.last?.filterOperator == "between" &&
                    client.fitAnalysisRequests.last?.modelID == "polynomial_2"
            },
            timeout: 2.0
        )

        XCTAssertEqual(session.fitOptions, FitOptionsPayload(enabled: true, modelID: "polynomial_2"))
        XCTAssertEqual(session.renderOptions.dataVariables?.first?.id, "scale")
        XCTAssertEqual(session.renderOptions.dataTransforms?.last?.filterOperator, "between")
        XCTAssertFalse(session.isProjectDirty)
    }

    func testOpenProjectWithFunctionCurveAxesAndAnalyticalLayerRestoresPreviewState() async throws {
        let client = MockSidecarClient()
        let restoredOptions = RenderOptionsPayload(
            size: "single_panel",
            stylePreset: "nature",
            palettePreset: "colorblind_safe",
            visualThemeID: "clean_light",
            extraXAxis: ExtraAxisPayload(
                enabled: true,
                position: "top",
                title: "Gallons",
                dataValue: 3.78541,
                displayValue: 1.0
            ),
            extraYAxis: ExtraAxisPayload(
                enabled: true,
                position: "right",
                bindingMode: "series_assignment",
                seriesIDs: ["Model"],
                title: "Half Stress",
                dataValue: 2.0,
                displayValue: 1.0
            ),
            analyticalLayers: [
                AnalyticalLayerPayload(
                    id: "function-1",
                    enabled: true,
                    kind: "function",
                    expression: "sin(x) + 1",
                    xStart: 0.0,
                    xEnd: 3.0,
                    sampleCount: 120,
                    yAxisTarget: "y_primary",
                    label: "Model"
                )
            ]
        )
        let restoredPayload = TestPayloads.plotProjectPayload(
            sourcePath: "/tmp/restored/function-advanced.csv",
            projectName: "Function Advanced",
            templateID: "function_curve",
            sheet: .name("RestoredSheet"),
            fitOptions: FitOptionsPayload(enabled: false, modelID: "linear"),
            renderOptions: restoredOptions
        )
        client.openProjectResponse = TestPayloads.openProjectResponse(
            projectPath: "/tmp/function-advanced.sciplotgod",
            restoredSourcePath: "/tmp/restored/function-advanced.csv",
            payload: restoredPayload
        )
        client.inspectHandler = { request in
            InspectFileResponse(
                inputPath: request.inputPath,
                sheet: request.sheet,
                sheetNames: ["RestoredSheet"],
                inspection: client.inspectResponse.inspection,
                dataset: client.inspectResponse.dataset
            )
        }
        client.renderHandler = { request in
            RenderPreviewResponse(
                template: request.template,
                requestedTemplateID: request.template,
                canonicalID: request.template,
                role: "plot",
                lifecyclePolicy: "stable",
                implementationID: request.template,
                sheet: request.sheet,
                previews: [.init(filename: "function_advanced_preview.pdf", pdfBase64: TestPayloads.pdfBase64, qa: nil)],
                submissionReport: TestPayloads.submissionReport()
            )
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.openProject(URL(fileURLWithPath: "/tmp/function-advanced.sciplotgod"))
        await waitUntil({ session.previewResponse?.previews.first?.filename == "function_advanced_preview.pdf" }, timeout: 2.0)

        XCTAssertEqual(session.selectedTemplateID, "function_curve")
        XCTAssertEqual(client.renderRequests.last?.options.extraXAxis?.title, "Gallons")
        XCTAssertEqual(client.renderRequests.last?.options.extraYAxis?.bindingMode, "series_assignment")
        XCTAssertEqual(client.renderRequests.last?.options.extraYAxis?.seriesIDs, ["Model"])
        XCTAssertEqual(client.renderRequests.last?.options.analyticalLayers?.first?.expression, "sin(x) + 1")
        XCTAssertEqual(client.renderRequests.last?.options.analyticalLayers?.first?.sampleCount, 120)
        XCTAssertEqual(session.renderOptions.extraXAxis?.title, "Gallons")
        XCTAssertEqual(session.renderOptions.extraYAxis?.seriesIDs, ["Model"])
        XCTAssertEqual(session.renderOptions.analyticalLayers?.first?.label, "Model")
        XCTAssertFalse(session.isProjectDirty)
    }

    func testOpenProjectWithAxisBreaksRestoresPreviewState() async throws {
        let client = MockSidecarClient()
        let restoredOptions = RenderOptionsPayload(
            size: "single_panel",
            stylePreset: "editorial",
            palettePreset: "roma",
            visualThemeID: "roma",
            xAxisBreaks: [
                AxisBreakPayload(id: "x-gap", enabled: true, start: 0.8, end: 1.2, displayMode: "split")
            ],
            yAxisBreaks: [
                AxisBreakPayload(id: "y-gap", enabled: false, start: 1.4, end: 2.2, displayMode: "compress")
            ]
        )
        let restoredPayload = TestPayloads.plotProjectPayload(
            sourcePath: "/tmp/restored/axis-breaks.csv",
            projectName: "Axis Breaks",
            templateID: "step_line",
            sheet: .name("RestoredSheet"),
            fitOptions: FitOptionsPayload(enabled: false, modelID: "linear"),
            renderOptions: restoredOptions
        )
        client.openProjectResponse = TestPayloads.openProjectResponse(
            projectPath: "/tmp/axis-breaks.sciplotgod",
            restoredSourcePath: "/tmp/restored/axis-breaks.csv",
            payload: restoredPayload
        )
        client.inspectHandler = { request in
            InspectFileResponse(
                inputPath: request.inputPath,
                sheet: request.sheet,
                sheetNames: ["RestoredSheet"],
                inspection: client.inspectResponse.inspection,
                dataset: client.inspectResponse.dataset
            )
        }
        client.renderHandler = { request in
            RenderPreviewResponse(
                template: request.template,
                requestedTemplateID: request.template,
                canonicalID: request.template,
                role: "plot",
                lifecyclePolicy: "stable",
                implementationID: request.template,
                sheet: request.sheet,
                previews: [.init(filename: "axis_breaks_preview.pdf", pdfBase64: TestPayloads.pdfBase64, qa: nil)],
                submissionReport: TestPayloads.submissionReport()
            )
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        await session.openProject(URL(fileURLWithPath: "/tmp/axis-breaks.sciplotgod"))
        await waitUntil({ session.previewResponse?.previews.first?.filename == "axis_breaks_preview.pdf" }, timeout: 2.0)

        XCTAssertEqual(session.selectedTemplateID, "step_line")
        XCTAssertEqual(client.renderRequests.last?.options.xAxisBreaks?.first?.id, "x-gap")
        XCTAssertEqual(client.renderRequests.last?.options.xAxisBreaks?.first?.displayMode, "split")
        XCTAssertEqual(client.renderRequests.last?.options.yAxisBreaks?.first?.displayMode, "compress")
        XCTAssertEqual(session.renderOptions.xAxisBreaks?.first?.id, "x-gap")
        XCTAssertEqual(session.renderOptions.yAxisBreaks?.first?.displayMode, "compress")
        XCTAssertFalse(session.isProjectDirty)
    }

    func testDataWorkbookLoadsSourceTableAndFitAnalysis() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.showDataWorkbook()
        session.refreshDataWorkbookIfNeeded()
        await waitUntil({ session.sourceTableResponse != nil }, timeout: 2.0)

        XCTAssertEqual(client.sourceTablePreviewRequests.count, 1)

        session.selectDataWorkbookTab(.fit)
        await waitUntil({ session.fitAnalysisResponse != nil }, timeout: 2.0)

        XCTAssertEqual(client.fitAnalysisRequests.count, 1)
        XCTAssertEqual(session.fitAnalysisResponse?.equationDisplay, TestPayloads.fitAnalysis().equationDisplay)

        session.updateFitModel("polynomial_2")
        await waitUntil({ client.fitAnalysisRequests.last?.modelID == "polynomial_2" }, timeout: 2.0)
    }

    func testDataWorkbookSourceTableIgnoresStaleResponse() async throws {
        let client = MockSidecarClient()
        var staleContinuation: CheckedContinuation<SourceTablePreviewResponse, Never>?
        client.sourceTablePreviewHandler = { request in
            if request.offset == 50 {
                return await withCheckedContinuation { continuation in
                    staleContinuation = continuation
                }
            }
            return TestPayloads.sourceTablePreview(path: request.inputPath, offset: request.offset)
        }

        let session = PlotSession()
        session.configure(client: client)
        session.selectedFileURL = URL(fileURLWithPath: "/tmp/sample.csv")
        session.showDataWorkbook()

        session.loadSourceTablePreview(offset: 50)
        await waitUntil({ client.sourceTablePreviewRequests.count == 1 }, timeout: 2.0)
        session.loadSourceTablePreview(offset: 0)
        await waitUntil({ session.sourceTableResponse?.offset == 0 }, timeout: 2.0)

        staleContinuation?.resume(returning: TestPayloads.sourceTablePreview(path: "/tmp/sample.csv", offset: 50))
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(session.sourceTableResponse?.offset, 0)
        XCTAssertFalse(session.isLoadingSourceTable)
    }

    func testDataWorkbookFitAnalysisIgnoresStaleResponse() async throws {
        let client = MockSidecarClient()
        var staleContinuation: CheckedContinuation<FitAnalysisResponse, Never>?
        client.fitAnalysisHandler = { request in
            if request.offset == 50 {
                return await withCheckedContinuation { continuation in
                    staleContinuation = continuation
                }
            }
            return TestPayloads.fitAnalysis(path: request.inputPath, offset: request.offset)
        }

        let session = PlotSession()
        session.configure(client: client)
        session.selectedFileURL = URL(fileURLWithPath: "/tmp/sample.csv")
        session.inspectionResponse = TestPayloads.inspectFile()
        session.runtimeState.inspectedInputPath = "/tmp/sample.csv"
        session.runtimeState.inspectedSheet = session.selectedSheet

        session.loadFitAnalysis(offset: 50)
        await waitUntil({ client.fitAnalysisRequests.count == 1 }, timeout: 2.0)
        session.loadFitAnalysis(offset: 0)
        await waitUntil({ session.fitAnalysisResponse?.offset == 0 }, timeout: 2.0)

        staleContinuation?.resume(returning: TestPayloads.fitAnalysis(path: "/tmp/sample.csv", offset: 50))
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(session.fitAnalysisResponse?.offset, 0)
        XCTAssertFalse(session.isLoadingFitAnalysis)
    }

    func testFitOverlayEditsRefreshPreviewAndPersistIntoProjectPayload() async throws {
        let client = MockSidecarClient()
        client.saveProjectHandler = { request in
            SaveProjectResponse(projectPath: request.projectPath, payload: request.payload)
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        let initialRenderCount = client.renderRequests.count

        session.updateFitEnabled(true)
        await waitUntil({ client.renderRequests.count == initialRenderCount + 1 }, timeout: 2.0)
        XCTAssertEqual(client.renderRequests.last?.fitOptions, FitOptionsPayload(enabled: true, modelID: "linear"))

        session.updateFitModel("polynomial_3")
        await waitUntil({ client.renderRequests.last?.fitOptions.modelID == "polynomial_3" }, timeout: 2.0)

        await session.saveProject(to: URL(fileURLWithPath: "/tmp/fit.sciplotgod"))
        XCTAssertEqual(
            client.saveProjectRequests.last?.payload.plot?.fitOptions,
            FitOptionsPayload(enabled: true, modelID: "polynomial_3")
        )
    }

    func testActivatingPlotToolsDoesNotCreatePlotObjects() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        let initialRenderCount = client.renderRequests.count

        session.activatePlotTool(.fit)
        XCTAssertEqual(session.selectedPlotAdjustmentCategory, .fit)
        session.activatePlotTool(.guide)
        XCTAssertEqual(session.selectedPlotAdjustmentCategory, .guides)
        session.activatePlotTool(.text)
        XCTAssertEqual(session.selectedPlotAdjustmentCategory, .annotations)
        session.activatePlotTool(.shape)
        XCTAssertEqual(session.selectedPlotAdjustmentCategory, .annotations)
        session.activatePlotTool(.function)
        session.activatePlotTool(.axisBreak)
        XCTAssertEqual(session.selectedPlotAdjustmentCategory, .advancedAxes)
        session.activatePlotTool(.secondaryAxis)
        XCTAssertEqual(session.selectedPlotAdjustmentCategory, .advancedAxes)

        XCTAssertEqual(session.selectedPlotTool, .secondaryAxis)
        XCTAssertFalse(session.fitOptions.enabled)
        XCTAssertTrue(session.referenceGuides.isEmpty)
        XCTAssertTrue(session.textAnnotations.isEmpty)
        XCTAssertTrue(session.shapeAnnotations.isEmpty)
        XCTAssertTrue(session.analyticalLayers.isEmpty)
        XCTAssertTrue(session.xAxisBreaks.isEmpty)
        XCTAssertTrue(session.yAxisBreaks.isEmpty)
        XCTAssertFalse(session.renderOptions.extraYAxis?.enabled ?? false)
        XCTAssertEqual(client.renderRequests.count, initialRenderCount)
    }

    func testFunctionToolShortcutRoutesToFunctionAdjustmentWhenTemplateSupportsIt() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.chooseTemplate("function_curve")
        session.activatePlotTool(.function)

        XCTAssertEqual(session.selectedPlotAdjustmentCategory, .functions)
        XCTAssertTrue(session.analyticalLayers.isEmpty)
    }

    func testPlotTypeItemsExposeFullContractFedListBeforeImport() {
        let session = PlotSession()
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        XCTAssertEqual(session.plotTypeItems.count, TestPayloads.meta().templates.count)
        XCTAssertEqual(session.templateGalleryItems.count, 5)
        XCTAssertTrue(session.plotTypeItems.allSatisfy { !$0.selectable })
    }

    func testOpeningDataWorkbookDefaultsToSourceDataFromToolbar() {
        let session = PlotSession()

        session.dataWorkbookTab = .fit
        session.showDataWorkbook()

        XCTAssertTrue(session.isDataWorkbookPresented)
        XCTAssertEqual(session.dataWorkbookTab, .sourceData)
    }

    func testReferenceGuideEditsRefreshPreviewAndPersistIntoProjectPayload() async throws {
        let client = MockSidecarClient()
        client.saveProjectHandler = { request in
            SaveProjectResponse(projectPath: request.projectPath, payload: request.payload)
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.addReferenceGuide(kind: "line")
        guard let lineID = session.renderOptions.referenceGuides?.first?.id else {
            XCTFail("Expected a reference guide to be created.")
            return
        }
        session.updateReferenceGuide(id: lineID) {
            $0.enabled = true
            $0.kind = "line"
            $0.axisTarget = "y_primary"
            $0.value = 2.5
            $0.label = "Target"
        }
        await waitUntil(
            {
                client.renderRequests.last?.options.referenceGuides?.first?.label == "Target"
            },
            timeout: 2.0
        )

        session.addReferenceGuide(kind: "band")
        guard let bandID = session.renderOptions.referenceGuides?.last?.id else {
            XCTFail("Expected a second reference guide to be created.")
            return
        }
        session.updateReferenceGuide(id: bandID) {
            $0.enabled = true
            $0.kind = "band"
            $0.axisTarget = "x"
            $0.start = 0.5
            $0.end = 1.5
            $0.label = "Window"
        }
        await waitUntil(
            {
                client.renderRequests.last?.options.referenceGuides?.count == 2
            },
            timeout: 2.0
        )

        await session.saveProject(to: URL(fileURLWithPath: "/tmp/guides.sciplotgod"))
        XCTAssertEqual(
            client.saveProjectRequests.last?.payload.plot?.renderOptions.referenceGuides,
            [
                ReferenceGuidePayload(
                    id: lineID,
                    enabled: true,
                    kind: "line",
                    axisTarget: "y_primary",
                    value: 2.5,
                    label: "Target"
                ),
                ReferenceGuidePayload(
                    id: bandID,
                    enabled: true,
                    kind: "band",
                    axisTarget: "x",
                    value: nil,
                    start: 0.5,
                    end: 1.5,
                    label: "Window"
                )
            ]
        )
    }

    func testAnalyticalFunctionLayerEditsRefreshPreviewAndPersistIntoProjectPayload() async throws {
        let client = MockSidecarClient()
        client.saveProjectHandler = { request in
            SaveProjectResponse(projectPath: request.projectPath, payload: request.payload)
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.addAnalyticalFunctionLayer()
        guard let layerID = session.renderOptions.analyticalLayers?.first?.id else {
            XCTFail("Expected an analytical function layer to be created.")
            return
        }
        session.updateAnalyticalLayer(id: layerID, policy: .immediate) {
            $0.expression = "sin(x) + 1"
            $0.xStart = 0.0
            $0.xEnd = 3.0
            $0.sampleCount = 120
            $0.yAxisTarget = "y_primary"
            $0.label = "Model"
        }
        await waitUntil(
            {
                client.renderRequests.last?.options.analyticalLayers?.first?.expression == "sin(x) + 1"
            },
            timeout: 2.0
        )

        await session.saveProject(to: URL(fileURLWithPath: "/tmp/functions.sciplotgod"))
        XCTAssertEqual(
            client.saveProjectRequests.last?.payload.plot?.renderOptions.analyticalLayers,
            [
                AnalyticalLayerPayload(
                    id: layerID,
                    enabled: true,
                    kind: "function",
                    expression: "sin(x) + 1",
                    xStart: 0.0,
                    xEnd: 3.0,
                    sampleCount: 120,
                    yAxisTarget: "y_primary",
                    label: "Model"
                )
            ]
        )
    }

    func testAnalyticalFunctionLayerPreviewSurfacesBackendExpressionErrors() async throws {
        let client = MockSidecarClient()
        client.renderHandler = { request in
            if request.options.analyticalLayers?.first?.expression == "foo(x)" {
                throw SidecarError.httpStatus(400, "Function layer expression is not allowed: unknown name foo.")
            }
            return TestPayloads.renderPreview()
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.addAnalyticalFunctionLayer()
        guard let layerID = session.renderOptions.analyticalLayers?.first?.id else {
            XCTFail("Expected an analytical function layer to be created.")
            return
        }
        session.updateAnalyticalLayer(id: layerID, policy: .immediate) {
            $0.expression = "foo(x)"
        }

        await waitUntil({ session.errorMessage?.contains("unknown name foo") == true }, timeout: 2.0)
        XCTAssertEqual(client.renderRequests.last?.options.analyticalLayers?.first?.expression, "foo(x)")
    }

    func testDataTransformEditsRefreshPreviewUndoAndPersistIntoProjectPayload() async throws {
        let client = MockSidecarClient()
        client.saveProjectHandler = { request in
            SaveProjectResponse(projectPath: request.projectPath, payload: request.payload)
        }

        let session = PlotSession()
        let undoManager = UndoManager()
        session.attachUndoManager(undoManager)
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        let initialRenderCount = client.renderRequests.count
        session.addDataVariable(kind: "scalar")
        guard let variableID = session.renderOptions.dataVariables?.first?.id else {
            XCTFail("Expected a data variable to be created.")
            return
        }
        session.updateDataVariable(id: variableID, policy: .immediate) {
            $0.id = "scale"
            $0.value = 2.0
        }
        session.addDataTransform(kind: "row_filter")
        guard let transformID = session.renderOptions.dataTransforms?.first?.id else {
            XCTFail("Expected a data transform to be created.")
            return
        }
        session.updateDataTransform(id: transformID, policy: .immediate) {
            $0.column = "X"
            $0.filterOperator = "between"
            $0.lower = 1.0
            $0.upper = 2.0
        }
        await waitUntil(
            {
                client.renderRequests.count > initialRenderCount &&
                    client.renderRequests.last?.options.dataVariables?.first?.id == "scale" &&
                    client.renderRequests.last?.options.dataTransforms?.first?.column == "X"
            },
            timeout: 2.0
        )

        undoManager.undo()
        XCTAssertNotEqual(session.renderOptions.dataTransforms?.first?.column, "X")

        let persistedVariableID: String
        if session.renderOptions.dataVariables?.first == nil {
            session.addDataVariable(kind: "scalar")
            persistedVariableID = session.renderOptions.dataVariables?.first?.id ?? variableID
        } else {
            persistedVariableID = session.renderOptions.dataVariables?.first?.id ?? variableID
        }
        session.updateDataVariable(id: persistedVariableID, policy: .immediate) {
            $0.id = "scale"
            $0.value = 2.0
        }

        let persistedTransformID: String
        if session.renderOptions.dataTransforms?.first == nil {
            session.addDataTransform(kind: "row_filter")
            persistedTransformID = session.renderOptions.dataTransforms?.first?.id ?? transformID
        } else {
            persistedTransformID = transformID
        }
        session.updateDataTransform(id: persistedTransformID, policy: .immediate) {
            $0.column = "X"
            $0.filterOperator = "between"
            $0.lower = 1.0
            $0.upper = 2.0
        }
        await session.saveProject(to: URL(fileURLWithPath: "/tmp/transforms.sciplotgod"))
        XCTAssertEqual(client.saveProjectRequests.last?.payload.plot?.renderOptions.dataTransforms?.first?.column, "X")
        XCTAssertEqual(client.saveProjectRequests.last?.payload.plot?.renderOptions.dataTransforms?.first?.filterOperator, "between")
        XCTAssertEqual(client.saveProjectRequests.last?.payload.plot?.renderOptions.dataVariables?.first?.id, "scale")
    }

    func testDataWorkbookTransformedTabRequestsTransformAwarePreview() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.addDataTransform(kind: "derived_column")
        guard let transformID = session.renderOptions.dataTransforms?.first?.id else {
            XCTFail("Expected a data transform to be created.")
            return
        }
        session.updateDataTransform(id: transformID, policy: .immediate) {
            $0.targetColumn = "radius"
            $0.expression = "sqrt(x*x + y*y)"
        }
        session.isDataWorkbookPresented = true
        session.selectDataWorkbookTab(.transformed)

        await waitUntil(
            { client.sourceTablePreviewRequests.last?.options?.dataTransforms?.first?.targetColumn == "radius" },
            timeout: 2.0
        )
    }

    func testDataPipelineSummaryCountsVariablesAndActiveTransforms() async throws {
        let session = PlotSession()

        XCTAssertFalse(session.dataPipelineSummary.hasPipeline)
        XCTAssertEqual(session.dataPipelineSummary.title, "No data edits")
        XCTAssertEqual(session.dataPipelineSummary.detail, "Source data is used directly.")

        session.addDataVariable(kind: "scalar")
        session.addDataVariable(kind: "expression")
        session.addDataTransform(kind: "derived_column")
        session.addDataTransform(kind: "row_filter")

        guard let disabledTransformID = session.renderOptions.dataTransforms?.last?.id else {
            XCTFail("Expected a data transform to disable.")
            return
        }
        session.updateDataTransform(id: disabledTransformID, policy: .immediate) {
            $0.enabled = false
        }

        XCTAssertTrue(session.dataPipelineSummary.hasPipeline)
        XCTAssertEqual(session.dataPipelineSummary.title, "2 variables, 2 transforms")
        XCTAssertEqual(session.dataPipelineSummary.detail, "1 active transform, 1 disabled")
    }

    func testReferenceGuideSelectionAndNudgeRefreshPreview() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.addReferenceGuide(kind: "line")
        guard let guideID = session.renderOptions.referenceGuides?.first?.id else {
            XCTFail("Expected a reference guide to be created.")
            return
        }
        XCTAssertEqual(session.selectedReferenceGuideID, guideID)

        session.nudgeReferenceGuide(id: guideID, deltaX: 0, deltaY: 0.25, policy: .immediate)
        await waitUntil(
            {
                client.renderRequests.last?.options.referenceGuides?.first?.value == 0.25
            },
            timeout: 2.0
        )

        session.removeReferenceGuide(id: guideID)
        XCTAssertNil(session.selectedReferenceGuideID)
    }

    func testExtraAxisEditsRefreshPreviewAndPersistIntoProjectPayload() async throws {
        let client = MockSidecarClient()
        client.saveProjectHandler = { request in
            SaveProjectResponse(projectPath: request.projectPath, payload: request.payload)
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.updateExtraXAxis {
            $0.enabled = true
            $0.position = "top"
            $0.title = "Gallons"
            $0.dataValue = 3.78541
            $0.displayValue = 1.0
        }
        await waitUntil(
            {
                client.renderRequests.last?.options.extraXAxis
                    == ExtraAxisPayload(enabled: true, position: "top", title: "Gallons", dataValue: 3.78541, displayValue: 1.0)
            },
            timeout: 2.0
        )

        session.updateExtraYAxis {
            $0.enabled = true
            $0.position = "right"
            $0.bindingMode = "series_assignment"
            $0.seriesIDs = ["Sample B"]
            $0.title = "Half Stress"
            $0.dataValue = 2.0
            $0.displayValue = 1.0
        }
        await waitUntil(
            {
                client.renderRequests.last?.options.extraYAxis
                    == ExtraAxisPayload(
                        enabled: true,
                        position: "right",
                        bindingMode: "series_assignment",
                        seriesIDs: ["Sample B"],
                        title: "Half Stress",
                        dataValue: 2.0,
                        displayValue: 1.0
                    )
            },
            timeout: 2.0
        )

        await session.saveProject(to: URL(fileURLWithPath: "/tmp/extra-axes.sciplotgod"))
        XCTAssertEqual(
            client.saveProjectRequests.last?.payload.plot?.renderOptions.extraXAxis,
            ExtraAxisPayload(enabled: true, position: "top", title: "Gallons", dataValue: 3.78541, displayValue: 1.0)
        )
        XCTAssertEqual(
            client.saveProjectRequests.last?.payload.plot?.renderOptions.extraYAxis,
            ExtraAxisPayload(
                enabled: true,
                position: "right",
                bindingMode: "series_assignment",
                seriesIDs: ["Sample B"],
                title: "Half Stress",
                dataValue: 2.0,
                displayValue: 1.0
            )
        )
    }

    func testTextAnnotationEditsRefreshPreviewAndPersistIntoProjectPayload() async throws {
        let client = MockSidecarClient()
        client.saveProjectHandler = { request in
            SaveProjectResponse(projectPath: request.projectPath, payload: request.payload)
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.addTextAnnotation(displayStyle: "callout", connectorEnabled: true)
        guard let annotationID = session.renderOptions.textAnnotations?.first?.id else {
            XCTFail("Expected a text annotation to be created.")
            return
        }

        session.updateTextAnnotation(id: annotationID) {
            $0.text = "Peak"
            $0.coordinateSpace = "data"
            $0.x = 1.5
            $0.y = 2.2
            $0.yAxisTarget = "y_primary"
            $0.horizontalAlignment = "right"
            $0.verticalAlignment = "bottom"
            $0.targetX = 1.0
            $0.targetY = 1.8
            $0.targetYAxisTarget = "y_primary"
        }

        await waitUntil(
            {
                client.renderRequests.last?.options.textAnnotations?.first?.text == "Peak" &&
                    client.renderRequests.last?.options.textAnnotations?.first?.coordinateSpace == "data"
            },
            timeout: 2.0
        )

        await session.saveProject(to: URL(fileURLWithPath: "/tmp/annotations.sciplotgod"))
        XCTAssertEqual(client.saveProjectRequests.last?.payload.plot?.renderOptions.textAnnotations?.count, 1)
        XCTAssertEqual(client.saveProjectRequests.last?.payload.plot?.renderOptions.textAnnotations?.first?.text, "Peak")
        XCTAssertEqual(client.saveProjectRequests.last?.payload.plot?.renderOptions.textAnnotations?.first?.x, 1.5)
        XCTAssertEqual(client.saveProjectRequests.last?.payload.plot?.renderOptions.textAnnotations?.first?.y, 2.2)
        XCTAssertEqual(client.saveProjectRequests.last?.payload.plot?.renderOptions.textAnnotations?.first?.displayStyle, "callout")
        XCTAssertEqual(client.saveProjectRequests.last?.payload.plot?.renderOptions.textAnnotations?.first?.connectorEnabled, true)
    }

    func testTextAnnotationSelectionAndNudgeClampsAxesFraction() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.addTextAnnotation()
        guard let annotationID = session.renderOptions.textAnnotations?.first?.id else {
            XCTFail("Expected a text annotation to be created.")
            return
        }
        XCTAssertEqual(session.selectedTextAnnotationID, annotationID)

        session.nudgeTextAnnotationPosition(
            id: annotationID,
            deltaX: 0.8,
            deltaY: 0.2,
            includeTarget: false,
            policy: .immediate
        )
        await waitUntil(
            {
                let item = client.renderRequests.last?.options.textAnnotations?.first
                return item?.x == 1.0 && item?.y == 1.0
            },
            timeout: 2.0
        )

        session.removeTextAnnotation(id: annotationID)
        XCTAssertNil(session.selectedTextAnnotationID)
    }

    func testShapeAnnotationSelectionAndNudgeRefreshPreview() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.addShapeAnnotation(kind: "rectangle")
        guard let annotationID = session.renderOptions.shapeAnnotations?.first?.id else {
            XCTFail("Expected a shape annotation to be created.")
            return
        }
        XCTAssertEqual(session.selectedShapeAnnotationID, annotationID)

        session.nudgeShapeAnnotation(id: annotationID, deltaX: 0.1, deltaY: -0.1, policy: .immediate)
        await waitUntil(
            {
                guard let item = client.renderRequests.last?.options.shapeAnnotations?.first else {
                    return false
                }
                return abs(item.xStart - 0.3) < 0.0001 &&
                    abs(item.xEnd - 0.9) < 0.0001 &&
                    abs(item.yStart - 0.1) < 0.0001 &&
                    abs(item.yEnd - 0.7) < 0.0001
            },
            timeout: 2.0
        )

        session.removeShapeAnnotation(id: annotationID)
        XCTAssertNil(session.selectedShapeAnnotationID)
    }

    func testCanvasPlacementCreatesTextAnnotationPayload() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.commitCanvasDraft(
            .text(
                point: PlotCanvasDataPoint(x: 4.0, y: 12.0),
                displayStyle: "plain",
                connectorTarget: nil
            )
        )

        let annotation = try XCTUnwrap(session.renderOptions.textAnnotations?.first)
        XCTAssertEqual(annotation.coordinateSpace, "data")
        XCTAssertEqual(annotation.x, 4.0)
        XCTAssertEqual(annotation.y, 12.0)
        XCTAssertEqual(annotation.displayStyle, "plain")
        XCTAssertEqual(session.canvasSelection, .layer(.textAnnotation(annotation.id)))
    }

    func testCanvasPlacementCreatesReferenceGuidePayload() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.commitCanvasDraft(.guideLine(axisTarget: "x", value: 3.5))
        session.commitCanvasDraft(.guideRegion(axisTarget: "y_primary", start: 10.0, end: 20.0))

        let guides = try XCTUnwrap(session.renderOptions.referenceGuides)
        XCTAssertEqual(guides[0].kind, "line")
        XCTAssertEqual(guides[0].axisTarget, "x")
        XCTAssertEqual(guides[0].value, 3.5)
        XCTAssertEqual(guides[1].kind, "band")
        XCTAssertEqual(guides[1].axisTarget, "y_primary")
        XCTAssertEqual(guides[1].start, 10.0)
        XCTAssertEqual(guides[1].end, 20.0)
    }

    func testCanvasPlacementCreatesShapeAnnotationPayload() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.commitCanvasDraft(
            .shape(
                kind: "rectangle",
                start: PlotCanvasDataPoint(x: 1.0, y: 2.0),
                end: PlotCanvasDataPoint(x: 5.0, y: 8.0)
            )
        )

        let annotation = try XCTUnwrap(session.renderOptions.shapeAnnotations?.first)
        XCTAssertEqual(annotation.kind, "rectangle")
        XCTAssertEqual(annotation.xStart, 1.0)
        XCTAssertEqual(annotation.xEnd, 5.0)
        XCTAssertEqual(annotation.yStart, 2.0)
        XCTAssertEqual(annotation.yEnd, 8.0)
        XCTAssertEqual(session.canvasSelection, .layer(.shapeAnnotation(annotation.id)))
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

    func testLegacyGroupedBarTemplateMigratesToBar() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.chooseTemplate("grouped_bar_error")

        await waitUntil({ client.renderRequests.last?.template == "bar" }, timeout: 2.0)
        XCTAssertEqual(session.selectedTemplateID, "bar")
        XCTAssertEqual(client.renderRequests.last?.template, "bar")
    }

    func testThumbnailKindUsesPresentationKindFromMetadata() {
        let session = PlotSession()
        let baseMeta = TestPayloads.meta()
        let templates = baseMeta.templates.map { template in
            guard template.id == "bar" else {
                return template
            }
            return MetaTemplateSummary(
                id: template.id,
                label: template.label,
                description: template.description,
                category: template.category,
                presentationKind: "histogram_density",
                defaultSize: template.defaultSize,
                allowedSizes: template.allowedSizes,
                editableOptions: template.editableOptions,
                defaultOptions: template.defaultOptions,
                availableStyles: template.availableStyles,
                availablePalettes: template.availablePalettes,
                canonicalID: template.canonicalID,
                role: template.role,
                lifecyclePolicy: template.lifecyclePolicy,
                implementationID: template.implementationID
            )
        }
        let meta = SidecarMetaResponse(
            version: baseMeta.version,
            defaults: baseMeta.defaults,
            sizes: baseMeta.sizes,
            styles: baseMeta.styles,
            palettes: baseMeta.palettes,
            templates: templates,
            templateIds: baseMeta.templateIds,
            sizeIds: baseMeta.sizeIds,
            palettePresetIds: baseMeta.palettePresetIds,
            visualThemes: baseMeta.visualThemes
        )

        session.apply(meta: meta, contract: TestPayloads.contract())

        XCTAssertEqual(session.thumbnailKind(for: "bar"), .histogramDensity)
    }

    func testTemplateGalleryPresentationExplainsDisabledTemplatesBeforeInspect() {
        let session = PlotSession()
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        let items = session.templateGalleryItems

        XCTAssertFalse(items.isEmpty)
        XCTAssertFalse(items[0].availability.isEnabled)
        XCTAssertTrue(items[0].availability.reason?.contains("Import a source file") ?? false)
        XCTAssertEqual(items[0].thumbnailKind, session.thumbnailKind(for: items[0].id))
    }

    func testResetSeriesOrderAvailabilityExplainsBlockedStates() async throws {
        let client = MockSidecarClient()
        client.inspectResponse = TestPayloads.multiSeriesInspectFile(path: "/tmp/multiseries.csv")
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.multiSeriesMeta(), contract: TestPayloads.contract())

        XCTAssertFalse(session.resetSeriesOrderAvailability.isEnabled)
        XCTAssertTrue(session.resetSeriesOrderAvailability.reason?.contains("does not expose reorderable legend entries") ?? false)

        session.importFile(URL(fileURLWithPath: "/tmp/multiseries.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        XCTAssertFalse(session.resetSeriesOrderAvailability.isEnabled)
        XCTAssertTrue(session.resetSeriesOrderAvailability.reason?.contains("already matches the source order") ?? false)

        session.setSeriesOrder(["Series B", "Series A"])
        XCTAssertTrue(session.resetSeriesOrderAvailability.isEnabled)
        XCTAssertNil(session.resetSeriesOrderAvailability.reason)
    }

    func testSeriesOrderRowsExplainBlockedMoveDirections() async throws {
        let client = MockSidecarClient()
        client.inspectResponse = TestPayloads.multiSeriesInspectFile(path: "/tmp/multiseries.csv")
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.multiSeriesMeta(), contract: TestPayloads.contract())

        XCTAssertEqual(session.seriesOrderRows.count, 0)

        session.importFile(URL(fileURLWithPath: "/tmp/multiseries.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        let rows = session.seriesOrderRows
        XCTAssertEqual(rows.map(\.title), ["Series A", "Series B"])
        XCTAssertFalse(rows[0].moveUpAvailability.isEnabled)
        XCTAssertTrue(rows[0].moveUpAvailability.reason?.contains("already first") ?? false)
        XCTAssertTrue(rows[0].moveDownAvailability.isEnabled)
        XCTAssertTrue(rows[1].moveUpAvailability.isEnabled)
        XCTAssertFalse(rows[1].moveDownAvailability.isEnabled)
        XCTAssertTrue(rows[1].moveDownAvailability.reason?.contains("already last") ?? false)

        session.moveSeriesOrder(id: rows[1].id, by: -1)
        XCTAssertEqual(session.seriesOrderLabels, ["Series B", "Series A"])
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
            defaults: .init(stylePreset: "nature", palettePreset: "colorblind_safe"),
            sizes: baseMeta.sizes,
            styles: [
                .init(
                    id: "nature",
                    label: "Nature",
                    public: true,
                    description: "Nature style.",
                    hardConstraints: true,
                    presetNote: "Nature preset",
                    recommendedPalettePreset: "colorblind_safe",
                    recommendedVisualThemeID: "clean_light"
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
                    presentationKind: $0.presentationKind,
                    defaultSize: $0.defaultSize,
                    allowedSizes: $0.allowedSizes,
                    editableOptions: $0.editableOptions,
                    defaultOptions: $0.defaultOptions,
                    availableStyles: ["nature"],
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
            $0.stylePreset = "default"
        }

        await waitUntil({ client.renderRequests.count == initialRenderCount + 1 }, timeout: 3.0)

        XCTAssertEqual(client.renderRequests.last?.options.stylePreset, "nature")
        XCTAssertEqual(session.renderOptions.stylePreset, "nature")
        XCTAssertNil(session.errorMessage)
    }

    func testTemplateResetUsesRecommendedThemeAndPaletteWhileKeepingIndependentEdits() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        XCTAssertEqual(session.selectedTemplateID, "curve")
        XCTAssertEqual(session.renderOptions.stylePreset, "nature")
        XCTAssertEqual(session.renderOptions.palettePreset, "colorblind_safe")
        XCTAssertEqual(session.renderOptions.visualThemeID, "clean_light")

        session.updateRenderOptions(policy: .immediate) {
            $0.visualThemeID = "macarons"
        }
        XCTAssertEqual(session.renderOptions.palettePreset, "colorblind_safe")
        XCTAssertEqual(session.renderOptions.visualThemeID, "macarons")

        session.updateRenderOptions(policy: .immediate) {
            $0.palettePreset = "infographic"
        }
        XCTAssertEqual(session.renderOptions.palettePreset, "infographic")
        XCTAssertEqual(session.renderOptions.visualThemeID, "macarons")

        session.chooseTemplate("box")
        XCTAssertEqual(session.selectedTemplateID, "box")
        XCTAssertEqual(session.renderOptions.stylePreset, "nature")
        XCTAssertEqual(session.renderOptions.palettePreset, "colorblind_safe")
        XCTAssertEqual(session.renderOptions.visualThemeID, "clean_light")
    }

    func testTemplateResetAppliesIndependentStylePaletteAndThemeDefaultsForNewCurveTemplates() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.chooseTemplate("area_curve")
        XCTAssertEqual(session.renderOptions.stylePreset, "presentation")
        XCTAssertEqual(session.renderOptions.palettePreset, "infographic")
        XCTAssertEqual(session.renderOptions.visualThemeID, "presentation_like")

        session.chooseTemplate("stacked_area")
        XCTAssertEqual(session.renderOptions.stylePreset, "presentation")
        XCTAssertEqual(session.renderOptions.palettePreset, "infographic")
        XCTAssertEqual(session.renderOptions.visualThemeID, "presentation_like")

        session.chooseTemplate("step_line")
        XCTAssertEqual(session.renderOptions.stylePreset, "editorial")
        XCTAssertEqual(session.renderOptions.palettePreset, "roma")
        XCTAssertEqual(session.renderOptions.visualThemeID, "roma")
    }

    func testTemplateResetAppliesIndependentDefaultsForNewDensityAreaTemplate() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.chooseTemplate("density_area")

        XCTAssertEqual(session.renderOptions.stylePreset, "presentation")
        XCTAssertEqual(session.renderOptions.palettePreset, "infographic")
        XCTAssertEqual(session.renderOptions.visualThemeID, "presentation_like")
    }

    func testThemeSelectionAppliesRecommendedPaletteAndBackgroundWhileAllowingIndependentOverrides() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.selectStylePreset("presentation")
        XCTAssertEqual(session.renderOptions.stylePreset, "presentation")
        XCTAssertEqual(session.renderOptions.palettePreset, "infographic")
        XCTAssertEqual(session.renderOptions.visualThemeID, "presentation_like")

        session.updateRenderOptions(policy: .immediate) {
            $0.palettePreset = "vintage"
            $0.visualThemeID = "roma"
        }
        XCTAssertEqual(session.renderOptions.stylePreset, "presentation")
        XCTAssertEqual(session.renderOptions.palettePreset, "vintage")
        XCTAssertEqual(session.renderOptions.visualThemeID, "roma")

        session.selectStylePreset("editorial")
        XCTAssertEqual(session.renderOptions.stylePreset, "editorial")
        XCTAssertEqual(session.renderOptions.palettePreset, "roma")
        XCTAssertEqual(session.renderOptions.visualThemeID, "roma")
    }

    func testPublicationStylesSurfacePublisherStylesBeforeLegacyDisplayStyles() async throws {
        let session = PlotSession()
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        XCTAssertEqual(session.publicationStyles.map(\.id), ["nature", "acs", "science", "wiley", "elsevier"])
        XCTAssertEqual(session.legacyDisplayStyles.map(\.id), ["editorial", "presentation", "poster"])
    }

    func testPublisherStyleSelectionAppliesContractRecommendedPaletteAndBackground() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        session.selectStylePreset("acs")
        XCTAssertEqual(session.renderOptions.stylePreset, "acs")
        XCTAssertEqual(session.renderOptions.palettePreset, "okabe_ito")
        XCTAssertEqual(session.renderOptions.visualThemeID, "clean_light")

        session.selectStylePreset("elsevier")
        XCTAssertEqual(session.renderOptions.stylePreset, "elsevier")
        XCTAssertEqual(session.renderOptions.palettePreset, "muted")
        XCTAssertEqual(session.renderOptions.visualThemeID, "soft_grid")
    }

    func testInspectionCancellationDoesNotSurfaceError() async {
        let client = MockSidecarClient()
        client.inspectHandler = { _ in
            throw CancellationError()
        }

        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/cancelled.csv"))
        await waitUntil({ session.isInspecting == false }, timeout: 2.0)

        XCTAssertNil(session.errorMessage)
        XCTAssertNil(session.inspectionResponse)
    }

    func testPreviewCancellationDoesNotSurfaceError() async throws {
        let client = MockSidecarClient()
        let session = PlotSession()
        session.configure(client: client)
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())

        session.importFile(URL(fileURLWithPath: "/tmp/sample.csv"))
        await waitUntil({ session.previewResponse != nil }, timeout: 2.0)

        client.renderHandler = { _ in
            throw CancellationError()
        }

        session.chooseTemplate("area_curve")
        await waitUntil({ session.isPreviewing == false }, timeout: 2.0)

        XCTAssertNil(session.errorMessage)
        XCTAssertNotNil(session.previewResponse)
    }

    func testExternalRenderOptionsFallbackThemeOnlyWhenMissing() {
        let session = PlotSession()
        session.apply(meta: TestPayloads.meta(), contract: TestPayloads.contract())
        session.selectedTemplateID = "curve"

        session.applyExternalRenderOptions(
            RenderOptionsPayload(
                size: "single_panel",
                stylePreset: "nature",
                palettePreset: "infographic",
                visualThemeID: nil
            )
        )

        XCTAssertEqual(session.renderOptions.palettePreset, "infographic")
        XCTAssertEqual(session.renderOptions.visualThemeID, "clean_light")

        session.applyExternalRenderOptions(
            RenderOptionsPayload(
                size: "single_panel",
                stylePreset: "nature",
                palettePreset: "macarons",
                visualThemeID: "infographic"
            )
        )

        XCTAssertEqual(session.renderOptions.palettePreset, "macarons")
        XCTAssertEqual(session.renderOptions.visualThemeID, "infographic")
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

        var callOrder: [String] = []
        var chooserIsMultiOutput: Bool?
        var chooserSuggestedName: String?
        var chooserFormat: ExportGraphicFormat?
        let session = PlotSession(
            chooseExportFormat: { isMultiOutput in
                callOrder.append("format")
                XCTAssertTrue(isMultiOutput)
                return .pdf
            },
            chooseExportDestination: { suggestedName, isMultiOutput, format in
                callOrder.append("destination")
                chooserSuggestedName = suggestedName
                chooserIsMultiOutput = isMultiOutput
                chooserFormat = format
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

        XCTAssertEqual(callOrder, ["format", "destination"])
        XCTAssertEqual(chooserIsMultiOutput, true)
        XCTAssertEqual(chooserFormat, .pdf)
        XCTAssertEqual(chooserSuggestedName, "sample_point_line.pdf")
        XCTAssertEqual(session.userExportURLs.count, 2)
        XCTAssertEqual(
            session.latestExportItems.map(\.label),
            [
                "rheology_group_storage_modulus_point_line.pdf",
                "rheology_group_loss_modulus_point_line.pdf",
            ]
        )
    }

    func testPlotExportCanMaterializeTIFFOutput() async throws {
        let client = MockSidecarClient()

        var callOrder: [String] = []
        var chooserSuggestedName: String?
        var materializedDestination: URL?
        let session = PlotSession(
            chooseExportFormat: { isMultiOutput in
                callOrder.append("format")
                XCTAssertFalse(isMultiOutput)
                return .tiff
            },
            chooseExportDestination: { suggestedName, _, format in
                callOrder.append("destination")
                chooserSuggestedName = suggestedName
                XCTAssertEqual(format, .tiff)
                return URL(fileURLWithPath: "/tmp/user_exports/sample_curve.tiff")
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

        XCTAssertEqual(callOrder, ["format", "destination"])
        XCTAssertEqual(chooserSuggestedName, "sample_curve.tiff")
        XCTAssertEqual(materializedDestination?.path, "/tmp/user_exports/sample_curve.tiff")
        XCTAssertEqual(session.userExportURLs.map { $0.pathExtension.lowercased() }, ["tiff"])
        XCTAssertEqual(session.latestExportItems.map(\.label), ["sample_curve.tiff"])
    }

    func testNativeTIFFExportPreservesPDFVerticalOrientation() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sciplot-tiff-orientation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourcePDFURL = tempDirectory.appendingPathComponent("orientation-source.pdf")
        let destinationTIFFURL = tempDirectory.appendingPathComponent("orientation-output.tiff")
        try writeOrientationProbePDF(to: sourcePDFURL)

        _ = try NativeExportCoordinator.materializePlotOutputs(
            sourceURLs: [sourcePDFURL],
            destinationURL: destinationTIFFURL
        )

        guard
            let tiffData = try? Data(contentsOf: destinationTIFFURL),
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            XCTFail("Expected TIFF export to be readable.")
            return
        }

        guard
            let imageSource = CGImageSourceCreateWithURL(destinationTIFFURL as CFURL, nil),
            let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        else {
            XCTFail("Expected TIFF export metadata to be readable.")
            return
        }
        let orientation = (imageProperties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
        let tiffProperties = imageProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let tiffOrientation = (tiffProperties?[kCGImagePropertyTIFFOrientation] as? NSNumber)?.intValue
        XCTAssertEqual(orientation, 1)
        XCTAssertEqual(tiffOrientation, 1)

        let sampleX = min(max(bitmap.pixelsWide / 2, 0), max(bitmap.pixelsWide - 1, 0))
        // NSBitmapImageRep samples pixels from a top-left origin.
        let topY = min(4, max(bitmap.pixelsHigh - 1, 0))
        let bottomY = max(bitmap.pixelsHigh - 5, 0)

        guard
            let topColor = bitmap.colorAt(x: sampleX, y: topY)?.usingColorSpace(NSColorSpace.sRGB),
            let bottomColor = bitmap.colorAt(x: sampleX, y: bottomY)?.usingColorSpace(NSColorSpace.sRGB)
        else {
            XCTFail("Expected TIFF export to expose sample pixels.")
            return
        }

        XCTAssertGreaterThan(topColor.redComponent, 0.8)
        XCTAssertLessThan(topColor.blueComponent, 0.25)
        XCTAssertGreaterThan(bottomColor.blueComponent, 0.8)
        XCTAssertLessThan(bottomColor.redComponent, 0.25)
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

    private func writeOrientationProbePDF(to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 72, height: 72)
        guard
            let consumer = CGDataConsumer(url: url as CFURL),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            XCTFail("Expected PDF probe context to be created.")
            return
        }

        context.beginPDFPage(nil)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(mediaBox)

        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: mediaBox.width, height: 16))

        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: mediaBox.height - 16, width: mediaBox.width, height: 16))

        context.endPDFPage()
        context.closePDF()
    }

    func testOpenCurrentSourceSurfacesMissingFileError() {
        let session = PlotSession()
        session.selectedFileURL = URL(fileURLWithPath: "/tmp/does-not-exist.csv")

        session.openCurrentSource()

        XCTAssertTrue(session.errorMessage?.contains("Couldn't find") ?? false)
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
