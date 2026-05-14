import Foundation
@testable import SciPlotMac

@MainActor
final class MockSidecarClient: SidecarClienting {
    enum MockError: Error {
        case unimplemented(String)
    }

    var healthResponse = HealthResponse(status: "ok", version: "0.1.0-beta")
    var metaResponse = TestPayloads.meta()
    var contractResponse = TestPayloads.contract()
    var plotThemesResponse = PlotThemeListResponse(themes: [])
    var plotThemePreviewResponse = PlotThemePreviewResponse(
        theme: CustomPlotThemePackagePayload(id: "user/mock_theme", label: "Mock Theme"),
        blockedKeys: [],
        warnings: []
    )
    var plotThemeSaveResponse = PlotThemeSaveResponse(
        theme: CustomPlotThemePackagePayload(id: "user/mock_theme", label: "Mock Theme"),
        blockedKeys: [],
        warnings: []
    )
    var scientificTextRulesResponse = ScientificTextRuleListResponse(rules: [])
    var scientificTextRulePreviewResponse = ScientificTextRulePreviewResponse(
        rule: ScientificTextRuleResponse(
            id: "unit/mock",
            kind: "unit",
            input: "mock",
            output: "Mock",
            enabled: true,
            canonicalInput: "mock"
        ),
        automaticOutput: "mock",
        effectiveOutput: "Mock",
        errors: [],
        warnings: []
    )
    var scientificTextRuleSaveResponse = ScientificTextRuleResponse(
        id: "unit/mock",
        kind: "unit",
        input: "mock",
        output: "Mock",
        enabled: true,
        canonicalInput: "mock"
    )
    var dataStudioTemplatesResponse = TestPayloads.dataStudioTemplateList()
    var dataStudioTemplateRecommendationsResponse = TestPayloads.dataStudioTemplateRecommendations()
    var dataStudioTemplatePreviewResponse = TestPayloads.dataStudioTemplatePreview()
    var dataStudioTemplateResponse = TestPayloads.dataStudioTemplate()
    var dataStudioWorkbookResponse = TestPayloads.dataStudioWorkbook()
    var dataStudioImportWorkbookResponse = TestPayloads.dataStudioImportWorkbook()
    var dataStudioWorkbookPreviewResponse = TestPayloads.dataStudioWorkbookPreview()
    var dataStudioComparisonContextResponse = TestPayloads.dataStudioComparisonContext()
    var dataStudioComparisonPreviewResponse = TestPayloads.dataStudioComparisonPreview()
    var dataStudioComparisonExportResponse = TestPayloads.dataStudioComparisonExport()
    var dataStudioSessionResponse = TestPayloads.dataStudioSession()
    var inspectResponse = TestPayloads.inspectFile()
    var sourceTablePreviewResponse = TestPayloads.sourceTablePreview()
    var fitAnalysisResponse = TestPayloads.fitAnalysis()
    var saveProjectResponse = TestPayloads.saveProjectResponse()
    var openProjectResponse = TestPayloads.openProjectResponse()
    var codeConsoleContextResponse = TestPayloads.codeConsoleContext()
    var codeConsoleRunResponse = TestPayloads.codeConsoleRun()
    var preflightResponse = TestPayloads.preflight()
    var previewResponse = TestPayloads.renderPreview()
    var exportResponse = TestPayloads.exportRender()
    var thumbnailResponse = PanelThumbnailResponse(pngBase64: TestPayloads.pngBase64)
    var composePreviewResponse = TestPayloads.composerPreview()
    var composeExportResponse = PathResponse(outputPath: "/tmp/composer-export.pdf")
    var importedComposerProject = TestPayloads.composerProject()
    var metaHandler: (() async throws -> SidecarMetaResponse)?
    var plotContractHandler: (() async throws -> PlotContractResponse)?
    var plotThemesHandler: (() async throws -> PlotThemeListResponse)?
    var plotThemePreviewHandler: ((PlotThemePreviewRequest) async throws -> PlotThemePreviewResponse)?
    var plotThemeSaveHandler: ((PlotThemeSaveRequest) async throws -> PlotThemeSaveResponse)?
    var plotThemeUpdateHandler: ((String, PlotThemeSaveRequest) async throws -> PlotThemeSaveResponse)?
    var scientificTextRulesHandler: (() async throws -> ScientificTextRuleListResponse)?
    var scientificTextRulePreviewHandler: ((ScientificTextRulePayload) async throws -> ScientificTextRulePreviewResponse)?
    var scientificTextRuleSaveHandler: ((ScientificTextRulePayload) async throws -> ScientificTextRuleResponse)?
    var scientificTextRuleUpdateHandler: ((String, ScientificTextRulePayload) async throws -> ScientificTextRuleResponse)?
    var dataStudioTemplateListHandler: (() async throws -> DataStudioTemplateListResponse)?
    var dataStudioTemplateRecommendationsHandler: ((DataStudioTemplateRecommendationsRequest) async throws -> DataStudioTemplateRecommendationsResponse)?
    var dataStudioTemplatePreviewHandler: ((DataStudioTemplatePreviewRequest) async throws -> DataStudioTemplatePreviewResponse)?
    var dataStudioCreateTemplateHandler: ((DataStudioCreateTemplateRequest) async throws -> DataStudioTemplateResponse)?
    var dataStudioUpdateTemplateHandler: ((String, DataStudioUpdateTemplateRequest) async throws -> DataStudioTemplateResponse)?
    var dataStudioBuildWorkbookHandler: ((DataStudioBuildWorkbookRequest) async throws -> DataStudioWorkbookResponse)?
    var dataStudioImportWorkbookHandler: ((DataStudioImportWorkbookRequest) async throws -> DataStudioImportWorkbookResponse)?
    var dataStudioWorkbookPreviewHandler: ((DataStudioWorkbookPreviewRequest) async throws -> DataStudioWorkbookPreviewResponse)?
    var dataStudioComparisonContextHandler: ((DataStudioComparisonContextRequest) async throws -> DataStudioComparisonContextResponse)?
    var dataStudioPreviewComparisonHandler: ((DataStudioPreviewComparisonRequest) async throws -> DataStudioComparisonPreviewResponse)?
    var dataStudioExportComparisonHandler: ((DataStudioExportComparisonRequest) async throws -> DataStudioComparisonExportResponse)?
    var dataStudioNormalizeSessionHandler: ((DataStudioSessionNormalizeRequest) async throws -> DataStudioSessionResponse)?
    var inspectHandler: ((FileRequest) async throws -> InspectFileResponse)?
    var sourceTablePreviewHandler: ((SourceTablePreviewRequest) async throws -> SourceTablePreviewResponse)?
    var fitAnalysisHandler: ((FitAnalysisRequest) async throws -> FitAnalysisResponse)?
    var saveProjectHandler: ((SaveProjectRequest) async throws -> SaveProjectResponse)?
    var openProjectHandler: ((OpenProjectRequest) async throws -> OpenProjectResponse)?
    var codeConsoleContextHandler: ((CodeConsoleContextRequest) async throws -> CodeConsoleContextResponse)?
    var codeConsoleRunHandler: ((CodeConsoleRunRequest) async throws -> CodeConsoleRunResponse)?
    var preflightHandler: ((RenderRequest) async throws -> PreflightRenderResponse)?
    var renderHandler: ((RenderRequest) async throws -> RenderPreviewResponse)?
    var exportHandler: ((ExportRenderRequest) async throws -> ExportRenderResponse)?

    private(set) var inspectRequests: [FileRequest] = []
    private(set) var plotThemePreviewRequests: [PlotThemePreviewRequest] = []
    private(set) var plotThemeSaveRequests: [PlotThemeSaveRequest] = []
    private(set) var plotThemeUpdateRequests: [(String, PlotThemeSaveRequest)] = []
    private(set) var plotThemeDeleteIDs: [String] = []
    private(set) var scientificTextRulePreviewRequests: [ScientificTextRulePayload] = []
    private(set) var scientificTextRuleSaveRequests: [ScientificTextRulePayload] = []
    private(set) var scientificTextRuleUpdateRequests: [(String, ScientificTextRulePayload)] = []
    private(set) var scientificTextRuleDeleteIDs: [String] = []
    private(set) var dataStudioTemplateRecommendationRequests: [DataStudioTemplateRecommendationsRequest] = []
    private(set) var dataStudioTemplatePreviewRequests: [DataStudioTemplatePreviewRequest] = []
    private(set) var dataStudioCreateTemplateRequests: [DataStudioCreateTemplateRequest] = []
    private(set) var dataStudioUpdateTemplateRequests: [(String, DataStudioUpdateTemplateRequest)] = []
    private(set) var dataStudioDeleteTemplateIDs: [String] = []
    private(set) var dataStudioBuildWorkbookRequests: [DataStudioBuildWorkbookRequest] = []
    private(set) var dataStudioImportWorkbookRequests: [DataStudioImportWorkbookRequest] = []
    private(set) var dataStudioWorkbookPreviewRequests: [DataStudioWorkbookPreviewRequest] = []
    private(set) var dataStudioComparisonContextRequests: [DataStudioComparisonContextRequest] = []
    private(set) var dataStudioPreviewComparisonRequests: [DataStudioPreviewComparisonRequest] = []
    private(set) var dataStudioExportComparisonRequests: [DataStudioExportComparisonRequest] = []
    private(set) var dataStudioNormalizeSessionRequests: [DataStudioSessionNormalizeRequest] = []
    private(set) var codeConsoleContextRequests: [CodeConsoleContextRequest] = []
    private(set) var codeConsoleRunRequests: [CodeConsoleRunRequest] = []
    private(set) var preflightRequests: [RenderRequest] = []
    private(set) var renderRequests: [RenderRequest] = []
    private(set) var exportRequests: [ExportRenderRequest] = []
    private(set) var sourceTablePreviewRequests: [SourceTablePreviewRequest] = []
    private(set) var fitAnalysisRequests: [FitAnalysisRequest] = []
    private(set) var saveProjectRequests: [SaveProjectRequest] = []
    private(set) var openProjectRequests: [OpenProjectRequest] = []
    private(set) var thumbnailRequests: [ThumbnailRequest] = []
    private(set) var composePreviewRequests: [ComposerRequestPayload] = []
    private(set) var composeExportRequests: [ComposerRequestPayload] = []
    private(set) var composerImportRequests: [ComposerImportRequestPayload] = []

    func fetchHealth() async throws -> HealthResponse {
        healthResponse
    }

    func fetchMeta() async throws -> SidecarMetaResponse {
        if let metaHandler {
            return try await metaHandler()
        }
        return metaResponse
    }

    func fetchPlotContract() async throws -> PlotContractResponse {
        if let plotContractHandler {
            return try await plotContractHandler()
        }
        return contractResponse
    }

    func fetchPlotThemes() async throws -> PlotThemeListResponse {
        if let plotThemesHandler {
            return try await plotThemesHandler()
        }
        return plotThemesResponse
    }

    func previewPlotTheme(_ request: PlotThemePreviewRequest) async throws -> PlotThemePreviewResponse {
        plotThemePreviewRequests.append(request)
        if let plotThemePreviewHandler {
            return try await plotThemePreviewHandler(request)
        }
        return plotThemePreviewResponse
    }

    func savePlotTheme(_ request: PlotThemeSaveRequest) async throws -> PlotThemeSaveResponse {
        plotThemeSaveRequests.append(request)
        if let plotThemeSaveHandler {
            return try await plotThemeSaveHandler(request)
        }
        return plotThemeSaveResponse
    }

    func updatePlotTheme(themeID: String, request: PlotThemeSaveRequest) async throws -> PlotThemeSaveResponse {
        plotThemeUpdateRequests.append((themeID, request))
        if let plotThemeUpdateHandler {
            return try await plotThemeUpdateHandler(themeID, request)
        }
        return plotThemeSaveResponse
    }

    func deletePlotTheme(themeID: String) async throws {
        plotThemeDeleteIDs.append(themeID)
    }

    func fetchScientificTextRules() async throws -> ScientificTextRuleListResponse {
        if let scientificTextRulesHandler {
            return try await scientificTextRulesHandler()
        }
        return scientificTextRulesResponse
    }

    func previewScientificTextRule(_ request: ScientificTextRulePayload) async throws -> ScientificTextRulePreviewResponse {
        scientificTextRulePreviewRequests.append(request)
        if let scientificTextRulePreviewHandler {
            return try await scientificTextRulePreviewHandler(request)
        }
        return scientificTextRulePreviewResponse
    }

    func saveScientificTextRule(_ request: ScientificTextRulePayload) async throws -> ScientificTextRuleResponse {
        scientificTextRuleSaveRequests.append(request)
        if let scientificTextRuleSaveHandler {
            return try await scientificTextRuleSaveHandler(request)
        }
        return scientificTextRuleSaveResponse
    }

    func updateScientificTextRule(
        ruleID: String,
        request: ScientificTextRulePayload
    ) async throws -> ScientificTextRuleResponse {
        scientificTextRuleUpdateRequests.append((ruleID, request))
        if let scientificTextRuleUpdateHandler {
            return try await scientificTextRuleUpdateHandler(ruleID, request)
        }
        return scientificTextRuleSaveResponse
    }

    func deleteScientificTextRule(ruleID: String) async throws {
        scientificTextRuleDeleteIDs.append(ruleID)
    }

    func fetchDataStudioTemplates() async throws -> DataStudioTemplateListResponse {
        if let dataStudioTemplateListHandler {
            return try await dataStudioTemplateListHandler()
        }
        return dataStudioTemplatesResponse
    }

    func recommendDataStudioTemplates(_ request: DataStudioTemplateRecommendationsRequest) async throws -> DataStudioTemplateRecommendationsResponse {
        dataStudioTemplateRecommendationRequests.append(request)
        if let dataStudioTemplateRecommendationsHandler {
            return try await dataStudioTemplateRecommendationsHandler(request)
        }
        return dataStudioTemplateRecommendationsResponse
    }

    func previewDataStudioTemplate(_ request: DataStudioTemplatePreviewRequest) async throws -> DataStudioTemplatePreviewResponse {
        dataStudioTemplatePreviewRequests.append(request)
        if let dataStudioTemplatePreviewHandler {
            return try await dataStudioTemplatePreviewHandler(request)
        }
        return dataStudioTemplatePreviewResponse
    }

    func createDataStudioTemplate(_ request: DataStudioCreateTemplateRequest) async throws -> DataStudioTemplateResponse {
        dataStudioCreateTemplateRequests.append(request)
        if let dataStudioCreateTemplateHandler {
            return try await dataStudioCreateTemplateHandler(request)
        }
        return dataStudioTemplateResponse
    }

    func updateDataStudioTemplate(
        templateID: String,
        request: DataStudioUpdateTemplateRequest
    ) async throws -> DataStudioTemplateResponse {
        dataStudioUpdateTemplateRequests.append((templateID, request))
        if let dataStudioUpdateTemplateHandler {
            return try await dataStudioUpdateTemplateHandler(templateID, request)
        }
        return dataStudioTemplateResponse
    }

    func deleteDataStudioTemplate(templateID: String) async throws {
        dataStudioDeleteTemplateIDs.append(templateID)
    }

    func buildDataStudioWorkbook(_ request: DataStudioBuildWorkbookRequest) async throws -> DataStudioWorkbookResponse {
        dataStudioBuildWorkbookRequests.append(request)
        if let dataStudioBuildWorkbookHandler {
            return try await dataStudioBuildWorkbookHandler(request)
        }
        return dataStudioWorkbookResponse
    }

    func importDataStudioWorkbook(_ request: DataStudioImportWorkbookRequest) async throws -> DataStudioImportWorkbookResponse {
        dataStudioImportWorkbookRequests.append(request)
        if let dataStudioImportWorkbookHandler {
            return try await dataStudioImportWorkbookHandler(request)
        }
        return dataStudioImportWorkbookResponse
    }

    func previewDataStudioWorkbook(_ request: DataStudioWorkbookPreviewRequest) async throws -> DataStudioWorkbookPreviewResponse {
        dataStudioWorkbookPreviewRequests.append(request)
        if let dataStudioWorkbookPreviewHandler {
            return try await dataStudioWorkbookPreviewHandler(request)
        }
        if dataStudioWorkbookPreviewResponse.workbookPath != request.workbookPath {
            return TestPayloads.dataStudioWorkbookPreview(
                path: request.workbookPath,
                label: URL(fileURLWithPath: request.workbookPath).deletingPathExtension().lastPathComponent
            )
        }
        return dataStudioWorkbookPreviewResponse
    }

    func comparisonContextDataStudio(_ request: DataStudioComparisonContextRequest) async throws -> DataStudioComparisonContextResponse {
        dataStudioComparisonContextRequests.append(request)
        if let dataStudioComparisonContextHandler {
            return try await dataStudioComparisonContextHandler(request)
        }
        return dataStudioComparisonContextResponse
    }

    func previewDataStudioComparison(_ request: DataStudioPreviewComparisonRequest) async throws -> DataStudioComparisonPreviewResponse {
        dataStudioPreviewComparisonRequests.append(request)
        if let dataStudioPreviewComparisonHandler {
            return try await dataStudioPreviewComparisonHandler(request)
        }
        if dataStudioComparisonPreviewResponse.recipe.id == request.recipeID {
            return dataStudioComparisonPreviewResponse
        }
        if let requestedRecipe = dataStudioComparisonPreviewResponse.comparisonSet.recipes.first(where: { $0.id == request.recipeID }) {
            return DataStudioComparisonPreviewResponse(
                comparisonSet: dataStudioComparisonPreviewResponse.comparisonSet,
                recipe: requestedRecipe,
                preview: PreviewItemResponse(
                    filename: "\(requestedRecipe.id).pdf",
                    pdfBase64: dataStudioComparisonPreviewResponse.preview.pdfBase64,
                    qa: dataStudioComparisonPreviewResponse.preview.qa
                )
            )
        }
        return dataStudioComparisonPreviewResponse
    }

    func exportDataStudioComparison(_ request: DataStudioExportComparisonRequest) async throws -> DataStudioComparisonExportResponse {
        dataStudioExportComparisonRequests.append(request)
        if let dataStudioExportComparisonHandler {
            return try await dataStudioExportComparisonHandler(request)
        }
        return dataStudioComparisonExportResponse
    }

    func normalizeDataStudioSession(_ request: DataStudioSessionNormalizeRequest) async throws -> DataStudioSessionResponse {
        dataStudioNormalizeSessionRequests.append(request)
        if let dataStudioNormalizeSessionHandler {
            return try await dataStudioNormalizeSessionHandler(request)
        }
        return dataStudioSessionResponse
    }

    func inspectFile(_ request: FileRequest) async throws -> InspectFileResponse {
        inspectRequests.append(request)
        if let inspectHandler {
            return try await inspectHandler(request)
        }
        return inspectResponse
    }

    func sourceTablePreview(_ request: SourceTablePreviewRequest) async throws -> SourceTablePreviewResponse {
        sourceTablePreviewRequests.append(request)
        if let sourceTablePreviewHandler {
            return try await sourceTablePreviewHandler(request)
        }
        return sourceTablePreviewResponse
    }

    func fitAnalysis(_ request: FitAnalysisRequest) async throws -> FitAnalysisResponse {
        fitAnalysisRequests.append(request)
        if let fitAnalysisHandler {
            return try await fitAnalysisHandler(request)
        }
        return fitAnalysisResponse
    }

    func saveProject(_ request: SaveProjectRequest) async throws -> SaveProjectResponse {
        saveProjectRequests.append(request)
        if let saveProjectHandler {
            return try await saveProjectHandler(request)
        }
        return saveProjectResponse
    }

    func openProject(_ request: OpenProjectRequest) async throws -> OpenProjectResponse {
        openProjectRequests.append(request)
        if let openProjectHandler {
            return try await openProjectHandler(request)
        }
        return openProjectResponse
    }

    func codeConsoleContext(_ request: CodeConsoleContextRequest) async throws -> CodeConsoleContextResponse {
        codeConsoleContextRequests.append(request)
        if let codeConsoleContextHandler {
            return try await codeConsoleContextHandler(request)
        }
        return codeConsoleContextResponse
    }

    func runCodeConsole(_ request: CodeConsoleRunRequest) async throws -> CodeConsoleRunResponse {
        codeConsoleRunRequests.append(request)
        if let codeConsoleRunHandler {
            return try await codeConsoleRunHandler(request)
        }
        return codeConsoleRunResponse
    }

    func preflightRender(_ request: RenderRequest) async throws -> PreflightRenderResponse {
        preflightRequests.append(request)
        if let preflightHandler {
            return try await preflightHandler(request)
        }
        return preflightResponse
    }

    func renderPreview(_ request: RenderRequest) async throws -> RenderPreviewResponse {
        renderRequests.append(request)
        if let renderHandler {
            return try await renderHandler(request)
        }
        return previewResponse
    }

    func exportRender(_ request: ExportRenderRequest) async throws -> ExportRenderResponse {
        exportRequests.append(request)
        if let exportHandler {
            return try await exportHandler(request)
        }
        return exportResponse
    }

    func panelThumbnail(_ request: ThumbnailRequest) async throws -> PanelThumbnailResponse {
        thumbnailRequests.append(request)
        return thumbnailResponse
    }

    func composePreview(_ request: ComposerRequestPayload) async throws -> ComposerPreviewResponse {
        composePreviewRequests.append(request)
        return composePreviewResponse
    }

    func composeExport(_ request: ComposerRequestPayload) async throws -> PathResponse {
        composeExportRequests.append(request)
        return composeExportResponse
    }

    func importComposerPanels(_ request: ComposerImportRequestPayload) async throws -> ComposerProjectResponse {
        composerImportRequests.append(request)
        return importedComposerProject
    }

    func composerThreeUp(_ filePaths: [String]) async throws -> ComposerProjectResponse {
        throw MockError.unimplemented("composerThreeUp")
    }

    func composerTwoUpEditorial(_ filePaths: [String]) async throws -> ComposerProjectResponse {
        throw MockError.unimplemented("composerTwoUpEditorial")
    }
}
