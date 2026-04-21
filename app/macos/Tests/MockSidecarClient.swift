import Foundation
@testable import SciPlotGodMac

@MainActor
final class MockSidecarClient: SidecarClienting {
    enum MockError: Error {
        case unimplemented(String)
    }

    var healthResponse = HealthResponse(status: "ok", version: "5.0.0")
    var metaResponse = TestPayloads.meta()
    var contractResponse = TestPayloads.contract()
    var dataStudioTemplatesResponse = TestPayloads.dataStudioTemplateList()
    var dataStudioSourcePreviewResponse = TestPayloads.dataStudioSourcePreview()
    var dataStudioTemplateResponse = TestPayloads.dataStudioTemplate()
    var dataStudioWorkbookResponse = TestPayloads.dataStudioWorkbook()
    var dataStudioImportWorkbookResponse = TestPayloads.dataStudioImportWorkbook()
    var dataStudioWorkbookPreviewResponse = TestPayloads.dataStudioWorkbookPreview()
    var dataStudioComparisonContextResponse = TestPayloads.dataStudioComparisonContext()
    var dataStudioComparisonPreviewResponse = TestPayloads.dataStudioComparisonPreview()
    var dataStudioComparisonExportResponse = TestPayloads.dataStudioComparisonExport()
    var dataStudioSessionResponse = TestPayloads.dataStudioSession()
    var inspectResponse = TestPayloads.inspectFile()
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
    var dataStudioTemplateListHandler: (() async throws -> DataStudioTemplateListResponse)?
    var dataStudioSourcePreviewHandler: ((DataStudioSourcePreviewRequest) async throws -> DataStudioSourcePreviewResponse)?
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
    var codeConsoleContextHandler: ((CodeConsoleContextRequest) async throws -> CodeConsoleContextResponse)?
    var codeConsoleRunHandler: ((CodeConsoleRunRequest) async throws -> CodeConsoleRunResponse)?
    var preflightHandler: ((RenderRequest) async throws -> PreflightRenderResponse)?
    var renderHandler: ((RenderRequest) async throws -> RenderPreviewResponse)?
    var exportHandler: ((ExportRenderRequest) async throws -> ExportRenderResponse)?

    private(set) var inspectRequests: [FileRequest] = []
    private(set) var dataStudioSourcePreviewRequests: [DataStudioSourcePreviewRequest] = []
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

    func fetchDataStudioTemplates() async throws -> DataStudioTemplateListResponse {
        if let dataStudioTemplateListHandler {
            return try await dataStudioTemplateListHandler()
        }
        return dataStudioTemplatesResponse
    }

    func previewDataStudioSource(_ request: DataStudioSourcePreviewRequest) async throws -> DataStudioSourcePreviewResponse {
        dataStudioSourcePreviewRequests.append(request)
        if let dataStudioSourcePreviewHandler {
            return try await dataStudioSourcePreviewHandler(request)
        }
        return dataStudioSourcePreviewResponse
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
