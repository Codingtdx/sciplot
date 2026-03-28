import Foundation

@MainActor
protocol SidecarClienting: AnyObject {
    func fetchHealth() async throws -> HealthResponse
    func fetchMeta() async throws -> SidecarMetaResponse
    func fetchPlotContract() async throws -> PlotContractResponse
    func inspectFile(_ request: FileRequest) async throws -> InspectFileResponse
    func preflightRender(_ request: RenderRequest) async throws -> PreflightRenderResponse
    func renderPreview(_ request: RenderRequest) async throws -> RenderPreviewResponse
    func exportRender(_ request: ExportRenderRequest) async throws -> ExportRenderResponse
    func preprocessTensileReplicates(_ request: TensileReplicateRequest) async throws -> TensileReplicateResponseModel
    func inspectTensileWorkbook(_ request: TensileWorkbookRequest) async throws -> TensileWorkbookSummaryResponse
    func exportTensileComparison(_ request: TensileComparisonExportRequest) async throws -> TensileComparisonExportResponse
    func panelThumbnail(_ request: ThumbnailRequest) async throws -> PanelThumbnailResponse
    func composePreview(_ request: ComposerRequestPayload) async throws -> ComposerPreviewResponse
    func composeExport(_ request: ComposerRequestPayload) async throws -> PathResponse
    func importComposerPanels(_ request: ComposerImportRequestPayload) async throws -> ComposerProjectResponse
    func composerThreeUp(_ filePaths: [String]) async throws -> ComposerProjectResponse
    func composerTwoUpEditorial(_ filePaths: [String]) async throws -> ComposerProjectResponse
}

@MainActor
final class SidecarClient: SidecarClienting {
    private let runtime: SidecarRuntime
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(runtime: SidecarRuntime, session: URLSession = .shared) {
        self.runtime = runtime
        self.session = session

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    func fetchHealth() async throws -> HealthResponse {
        try await get("health")
    }

    func fetchMeta() async throws -> SidecarMetaResponse {
        try await get("meta")
    }

    func fetchPlotContract() async throws -> PlotContractResponse {
        try await get("plot-contract")
    }

    func inspectFile(_ request: FileRequest) async throws -> InspectFileResponse {
        try await post("inspect-file", body: request)
    }

    func preflightRender(_ request: RenderRequest) async throws -> PreflightRenderResponse {
        try await post("preflight-render", body: request)
    }

    func renderPreview(_ request: RenderRequest) async throws -> RenderPreviewResponse {
        try await post("render-preview", body: request)
    }

    func exportRender(_ request: ExportRenderRequest) async throws -> ExportRenderResponse {
        try await post("export-render", body: request)
    }

    func preprocessTensileReplicates(_ request: TensileReplicateRequest) async throws -> TensileReplicateResponseModel {
        try await post("preprocess-tensile-replicates", body: request)
    }

    func inspectTensileWorkbook(_ request: TensileWorkbookRequest) async throws -> TensileWorkbookSummaryResponse {
        try await post("inspect-tensile-workbook", body: request)
    }

    func exportTensileComparison(_ request: TensileComparisonExportRequest) async throws -> TensileComparisonExportResponse {
        try await post("export-tensile-comparison", body: request)
    }

    func panelThumbnail(_ request: ThumbnailRequest) async throws -> PanelThumbnailResponse {
        try await post("panel-thumbnail", body: request)
    }

    func composePreview(_ request: ComposerRequestPayload) async throws -> ComposerPreviewResponse {
        try await post("compose-preview", body: request)
    }

    func composeExport(_ request: ComposerRequestPayload) async throws -> PathResponse {
        try await post("compose-export", body: request)
    }

    func importComposerPanels(_ request: ComposerImportRequestPayload) async throws -> ComposerProjectResponse {
        try await post("composer/import-panels", body: request)
    }

    func composerThreeUp(_ filePaths: [String]) async throws -> ComposerProjectResponse {
        try await post("composer/three-up", body: filePaths)
    }

    func composerTwoUpEditorial(_ filePaths: [String]) async throws -> ComposerProjectResponse {
        try await post("composer/two-up-editorial", body: filePaths)
    }

    private func get<Response: Decodable>(_ path: String) async throws -> Response {
        try await runtime.ensureRunning()
        let request = URLRequest(url: runtime.baseURL.appendingPathComponent(path))
        return try await perform(request)
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await runtime.ensureRunning()

        var request = URLRequest(url: runtime.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SidecarError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SidecarError.invalidResponse("The sidecar did not return an HTTP response.")
        }

        guard 200 ..< 300 ~= http.statusCode else {
            if
                let payload = try? decoder.decode([String: String].self, from: data),
                let detail = payload["detail"]
            {
                throw SidecarError.httpStatus(http.statusCode, detail)
            }

            let detail = String(decoding: data, as: UTF8.self)
            throw SidecarError.httpStatus(http.statusCode, detail)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw SidecarError.invalidResponse(error.localizedDescription)
        }
    }
}
