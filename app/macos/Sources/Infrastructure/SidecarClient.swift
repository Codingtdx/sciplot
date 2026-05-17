import Foundation

@MainActor
protocol SidecarClienting: AnyObject {
    func fetchHealth() async throws -> HealthResponse
    func fetchMeta() async throws -> SidecarMetaResponse
    func fetchPlotContract() async throws -> PlotContractResponse
    func fetchPlotThemes() async throws -> PlotThemeListResponse
    func previewPlotTheme(_ request: PlotThemePreviewRequest) async throws -> PlotThemePreviewResponse
    func savePlotTheme(_ request: PlotThemeSaveRequest) async throws -> PlotThemeSaveResponse
    func updatePlotTheme(themeID: String, request: PlotThemeSaveRequest) async throws -> PlotThemeSaveResponse
    func deletePlotTheme(themeID: String) async throws
    func fetchScientificTextRules() async throws -> ScientificTextRuleListResponse
    func previewScientificTextRule(_ request: ScientificTextRulePayload) async throws -> ScientificTextRulePreviewResponse
    func saveScientificTextRule(_ request: ScientificTextRulePayload) async throws -> ScientificTextRuleResponse
    func updateScientificTextRule(ruleID: String, request: ScientificTextRulePayload) async throws -> ScientificTextRuleResponse
    func deleteScientificTextRule(ruleID: String) async throws
    func fetchDataStudioTemplates() async throws -> DataStudioTemplateListResponse
    func recommendDataStudioTemplates(_ request: DataStudioTemplateRecommendationsRequest) async throws -> DataStudioTemplateRecommendationsResponse
    func previewDataStudioTemplate(_ request: DataStudioTemplatePreviewRequest) async throws -> DataStudioTemplatePreviewResponse
    func createDataStudioTemplate(_ request: DataStudioCreateTemplateRequest) async throws -> DataStudioTemplateResponse
    func updateDataStudioTemplate(templateID: String, request: DataStudioUpdateTemplateRequest) async throws -> DataStudioTemplateResponse
    func deleteDataStudioTemplate(templateID: String) async throws
    func buildDataStudioWorkbook(_ request: DataStudioBuildWorkbookRequest) async throws -> DataStudioWorkbookResponse
    func importDataStudioWorkbook(_ request: DataStudioImportWorkbookRequest) async throws -> DataStudioImportWorkbookResponse
    func previewDataStudioWorkbook(_ request: DataStudioWorkbookPreviewRequest) async throws -> DataStudioWorkbookPreviewResponse
    func comparisonContextDataStudio(_ request: DataStudioComparisonContextRequest) async throws -> DataStudioComparisonContextResponse
    func previewDataStudioComparison(_ request: DataStudioPreviewComparisonRequest) async throws -> DataStudioComparisonPreviewResponse
    func exportDataStudioComparison(_ request: DataStudioExportComparisonRequest) async throws -> DataStudioComparisonExportResponse
    func normalizeDataStudioSession(_ request: DataStudioSessionNormalizeRequest) async throws -> DataStudioSessionResponse
    func inspectFile(_ request: FileRequest) async throws -> InspectFileResponse
    func sourceTablePreview(_ request: SourceTablePreviewRequest) async throws -> SourceTablePreviewResponse
    func fitAnalysis(_ request: FitAnalysisRequest) async throws -> FitAnalysisResponse
    func analysisOperation(_ request: AnalysisOperationRequest) async throws -> AnalysisOperationResponse
    func importPreview(_ request: ImportPreviewRequest) async throws -> ImportPreviewResponse
    func normalizePlotEditCommand(_ request: PlotEditCommandNormalizeRequest) async throws -> PlotEditCommandNormalizeResponse
    func saveProject(_ request: SaveProjectRequest) async throws -> SaveProjectResponse
    func openProject(_ request: OpenProjectRequest) async throws -> OpenProjectResponse
    func codeConsoleContext(_ request: CodeConsoleContextRequest) async throws -> CodeConsoleContextResponse
    func runCodeConsole(_ request: CodeConsoleRunRequest) async throws -> CodeConsoleRunResponse
    func preflightRender(_ request: RenderRequest) async throws -> PreflightRenderResponse
    func renderPreview(_ request: RenderRequest) async throws -> RenderPreviewResponse
    func exportRender(_ request: ExportRenderRequest) async throws -> ExportRenderResponse
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

    func fetchPlotThemes() async throws -> PlotThemeListResponse {
        try await get("plot-themes")
    }

    func previewPlotTheme(_ request: PlotThemePreviewRequest) async throws -> PlotThemePreviewResponse {
        try await post("plot-themes/preview", body: request)
    }

    func savePlotTheme(_ request: PlotThemeSaveRequest) async throws -> PlotThemeSaveResponse {
        try await post("plot-themes", body: request)
    }

    func updatePlotTheme(themeID: String, request: PlotThemeSaveRequest) async throws -> PlotThemeSaveResponse {
        try await put("plot-themes/\(themeID)", body: request)
    }

    func deletePlotTheme(themeID: String) async throws {
        let _: StatusResponse = try await delete("plot-themes/\(themeID)", responseType: StatusResponse.self)
    }

    func fetchScientificTextRules() async throws -> ScientificTextRuleListResponse {
        try await get("scientific-text/rules")
    }

    func previewScientificTextRule(_ request: ScientificTextRulePayload) async throws -> ScientificTextRulePreviewResponse {
        try await post("scientific-text/rules/preview", body: request)
    }

    func saveScientificTextRule(_ request: ScientificTextRulePayload) async throws -> ScientificTextRuleResponse {
        try await post("scientific-text/rules", body: request)
    }

    func updateScientificTextRule(ruleID: String, request: ScientificTextRulePayload) async throws -> ScientificTextRuleResponse {
        try await put("scientific-text/rules/\(ruleID)", body: request)
    }

    func deleteScientificTextRule(ruleID: String) async throws {
        let _: StatusResponse = try await delete("scientific-text/rules/\(ruleID)", responseType: StatusResponse.self)
    }

    func fetchDataStudioTemplates() async throws -> DataStudioTemplateListResponse {
        try await get("data-studio/templates")
    }

    func recommendDataStudioTemplates(_ request: DataStudioTemplateRecommendationsRequest) async throws -> DataStudioTemplateRecommendationsResponse {
        try await post("data-studio/template-recommendations", body: request)
    }

    func previewDataStudioTemplate(_ request: DataStudioTemplatePreviewRequest) async throws -> DataStudioTemplatePreviewResponse {
        try await post("data-studio/template-preview", body: request)
    }

    func createDataStudioTemplate(_ request: DataStudioCreateTemplateRequest) async throws -> DataStudioTemplateResponse {
        try await post("data-studio/templates", body: request)
    }

    func updateDataStudioTemplate(templateID: String, request: DataStudioUpdateTemplateRequest) async throws -> DataStudioTemplateResponse {
        try await put("data-studio/templates/\(templateID)", body: request)
    }

    func deleteDataStudioTemplate(templateID: String) async throws {
        let _: StatusResponse = try await delete("data-studio/templates/\(templateID)", responseType: StatusResponse.self)
    }

    func buildDataStudioWorkbook(_ request: DataStudioBuildWorkbookRequest) async throws -> DataStudioWorkbookResponse {
        try await post("data-studio/build-workbook", body: request)
    }

    func importDataStudioWorkbook(_ request: DataStudioImportWorkbookRequest) async throws -> DataStudioImportWorkbookResponse {
        try await post("data-studio/import-workbook", body: request)
    }

    func previewDataStudioWorkbook(_ request: DataStudioWorkbookPreviewRequest) async throws -> DataStudioWorkbookPreviewResponse {
        try await post("data-studio/workbook-preview", body: request)
    }

    func comparisonContextDataStudio(_ request: DataStudioComparisonContextRequest) async throws -> DataStudioComparisonContextResponse {
        try await post("data-studio/comparison-context", body: request)
    }

    func previewDataStudioComparison(_ request: DataStudioPreviewComparisonRequest) async throws -> DataStudioComparisonPreviewResponse {
        try await post("data-studio/comparison-preview", body: request)
    }

    func exportDataStudioComparison(_ request: DataStudioExportComparisonRequest) async throws -> DataStudioComparisonExportResponse {
        try await post("data-studio/comparison-export", body: request)
    }

    func normalizeDataStudioSession(_ request: DataStudioSessionNormalizeRequest) async throws -> DataStudioSessionResponse {
        try await post("data-studio/session/normalize", body: request)
    }

    func inspectFile(_ request: FileRequest) async throws -> InspectFileResponse {
        try await post("inspect-file", body: request)
    }

    func sourceTablePreview(_ request: SourceTablePreviewRequest) async throws -> SourceTablePreviewResponse {
        try await post("source-table-preview", body: request)
    }

    func fitAnalysis(_ request: FitAnalysisRequest) async throws -> FitAnalysisResponse {
        try await post("fit-analysis", body: request)
    }

    func analysisOperation(_ request: AnalysisOperationRequest) async throws -> AnalysisOperationResponse {
        try await post("analysis-operation", body: request)
    }

    func importPreview(_ request: ImportPreviewRequest) async throws -> ImportPreviewResponse {
        try await post("import-preview", body: request)
    }

    func normalizePlotEditCommand(_ request: PlotEditCommandNormalizeRequest) async throws -> PlotEditCommandNormalizeResponse {
        try await post("plot-edit-command/normalize", body: request)
    }

    func saveProject(_ request: SaveProjectRequest) async throws -> SaveProjectResponse {
        try await post("save-project", body: request)
    }

    func openProject(_ request: OpenProjectRequest) async throws -> OpenProjectResponse {
        try await post("open-project", body: request)
    }

    func codeConsoleContext(_ request: CodeConsoleContextRequest) async throws -> CodeConsoleContextResponse {
        try await post("code-console/context", body: request)
    }

    func runCodeConsole(_ request: CodeConsoleRunRequest) async throws -> CodeConsoleRunResponse {
        try await post("code-console/run", body: request)
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

    private func put<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await runtime.ensureRunning()

        var request = URLRequest(url: runtime.baseURL.appendingPathComponent(path))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func delete<Response: Decodable>(_ path: String, responseType: Response.Type) async throws -> Response {
        try await runtime.ensureRunning()

        var request = URLRequest(url: runtime.baseURL.appendingPathComponent(path))
        request.httpMethod = "DELETE"
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
            if let decodingError = error as? DecodingError {
                throw SidecarError.invalidResponse(
                    decodeErrorDescription(
                        decodingError,
                        request: request,
                        responseBody: data
                    )
                )
            }
            throw SidecarError.invalidResponse(error.localizedDescription)
        }
    }

    private func decodeErrorDescription(
        _ error: DecodingError,
        request: URLRequest,
        responseBody: Data
    ) -> String {
        let endpoint = request.url?.path ?? "(unknown endpoint)"
        let hasBody = !responseBody.isEmpty

        switch error {
        case let .keyNotFound(key, context):
            let path = (context.codingPath + [key]).map(\.stringValue).joined(separator: ".")
            return "Missing key `\(key.stringValue)` while decoding `\(path)` from \(endpoint)."
        case let .typeMismatch(type, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            let location = path.isEmpty ? "(root)" : path
            return "Type mismatch for `\(type)` at `\(location)` from \(endpoint)."
        case let .valueNotFound(type, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            let location = path.isEmpty ? "(root)" : path
            return "Missing value for `\(type)` at `\(location)` from \(endpoint)."
        case let .dataCorrupted(context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            let location = path.isEmpty ? "(root)" : path
            let suffix = hasBody ? "" : " Response body is empty."
            return "Data corrupted at `\(location)` from \(endpoint): \(context.debugDescription).\(suffix)"
        @unknown default:
            let suffix = hasBody ? "" : " Response body is empty."
            return "Decoding failed from \(endpoint).\(suffix)"
        }
    }
}
