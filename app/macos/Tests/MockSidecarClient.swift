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
    var inspectResponse = TestPayloads.inspectFile()
    var codeConsoleContextResponse = TestPayloads.codeConsoleContext()
    var codeConsoleRunResponse = TestPayloads.codeConsoleRun()
    var preflightResponse = TestPayloads.preflight()
    var previewResponse = TestPayloads.renderPreview()
    var exportResponse = TestPayloads.exportRender()
    var preprocessResponse = TestPayloads.tensilePreprocess()
    var workbookSummaryResponse = TestPayloads.tensileWorkbookSummary(path: "/tmp/second.xlsx", label: "Second Group")
    var comparisonResponse = TestPayloads.tensileComparison()
    var thumbnailResponse = PanelThumbnailResponse(pngBase64: TestPayloads.pngBase64)
    var composePreviewResponse = TestPayloads.composerPreview()
    var composeExportResponse = PathResponse(outputPath: "/tmp/composer-export.pdf")
    var importedComposerProject = TestPayloads.composerProject()
    var inspectHandler: ((FileRequest) async throws -> InspectFileResponse)?
    var codeConsoleContextHandler: ((CodeConsoleContextRequest) async throws -> CodeConsoleContextResponse)?
    var codeConsoleRunHandler: ((CodeConsoleRunRequest) async throws -> CodeConsoleRunResponse)?
    var preflightHandler: ((RenderRequest) async throws -> PreflightRenderResponse)?
    var renderHandler: ((RenderRequest) async throws -> RenderPreviewResponse)?
    var exportHandler: ((ExportRenderRequest) async throws -> ExportRenderResponse)?

    private(set) var inspectRequests: [FileRequest] = []
    private(set) var codeConsoleContextRequests: [CodeConsoleContextRequest] = []
    private(set) var codeConsoleRunRequests: [CodeConsoleRunRequest] = []
    private(set) var preflightRequests: [RenderRequest] = []
    private(set) var renderRequests: [RenderRequest] = []
    private(set) var exportRequests: [ExportRenderRequest] = []
    private(set) var preprocessRequests: [TensileReplicateRequest] = []
    private(set) var workbookRequests: [TensileWorkbookRequest] = []
    private(set) var comparisonRequests: [TensileComparisonExportRequest] = []
    private(set) var thumbnailRequests: [ThumbnailRequest] = []
    private(set) var composePreviewRequests: [ComposerRequestPayload] = []
    private(set) var composeExportRequests: [ComposerRequestPayload] = []
    private(set) var composerImportRequests: [ComposerImportRequestPayload] = []

    func fetchHealth() async throws -> HealthResponse {
        healthResponse
    }

    func fetchMeta() async throws -> SidecarMetaResponse {
        metaResponse
    }

    func fetchPlotContract() async throws -> PlotContractResponse {
        contractResponse
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

    func preprocessTensileReplicates(_ request: TensileReplicateRequest) async throws -> TensileReplicateResponseModel {
        preprocessRequests.append(request)
        return preprocessResponse
    }

    func inspectTensileWorkbook(_ request: TensileWorkbookRequest) async throws -> TensileWorkbookSummaryResponse {
        workbookRequests.append(request)
        return workbookSummaryResponse
    }

    func exportTensileComparison(_ request: TensileComparisonExportRequest) async throws -> TensileComparisonExportResponse {
        comparisonRequests.append(request)
        return comparisonResponse
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
