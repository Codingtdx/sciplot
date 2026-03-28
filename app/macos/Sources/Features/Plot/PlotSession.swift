import Foundation
import Observation

enum PlotStage: String, CaseIterable, Identifiable {
    case importData
    case template
    case refineExport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .importData:
            return "Import"
        case .template:
            return "Template"
        case .refineExport:
            return "Refine & Export"
        }
    }
}

struct PlotSampleColumn: Identifiable, Hashable {
    let id: Int
    let title: String
}

struct PlotSampleRow: Identifiable, Hashable {
    let id: Int
    let values: [JSONValue]

    func value(at index: Int) -> JSONValue {
        guard values.indices.contains(index) else {
            return .null
        }
        return values[index]
    }
}

@MainActor
@Observable
final class PlotSession {
    @ObservationIgnored private var client: (any SidecarClienting)?

    var stage: PlotStage = .importData
    var isImporterPresented = false
    var selectedFileURL: URL?
    var selectedSheet: SheetValue = .index(0)
    var inspectionResponse: InspectFileResponse?
    var metadata: SidecarMetaResponse?
    var contract: PlotContractResponse?
    var selectedTemplateID: String?
    var renderOptions = RenderOptionsPayload()
    var previewResponse: RenderPreviewResponse?
    var preflightResponse: PreflightRenderResponse?
    var exportResponse: ExportRenderResponse?
    var errorMessage: String?
    var isInspecting = false
    var isPreviewing = false
    var isRunningPreflight = false
    var isExporting = false

    var hasSessionContent: Bool {
        selectedFileURL != nil || inspectionResponse != nil || selectedTemplateID != nil
    }

    func configure(client: any SidecarClienting) {
        self.client = client
    }

    func apply(meta: SidecarMetaResponse, contract: PlotContractResponse) {
        metadata = meta
        self.contract = contract
        renderOptions.stylePreset = meta.defaults.stylePreset
        renderOptions.palettePreset = meta.defaults.palettePreset
        renderOptions.visualThemeID = meta.visualThemes.first?.id
    }

    func handleImportedFile(_ url: URL) {
        selectedFileURL = url
        selectedSheet = .index(0)
        inspectionResponse = nil
        selectedTemplateID = nil
        previewResponse = nil
        preflightResponse = nil
        exportResponse = nil
        errorMessage = nil
        stage = .importData
    }

    func seedFromCleanup(workbookURL: URL, preferredSheet: SheetValue) {
        handleImportedFile(workbookURL)
        selectedSheet = preferredSheet
    }

    func inspectCurrentFile() async {
        guard let client, let selectedFileURL else {
            return
        }

        isInspecting = true
        errorMessage = nil

        defer { isInspecting = false }

        do {
            let response = try await client.inspectFile(
                .init(inputPath: selectedFileURL.path, sheet: selectedSheet)
            )
            inspectionResponse = response
            selectedSheet = response.sheet
            chooseInitialTemplate(from: response)
            stage = .template
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseTemplate(_ templateID: String) {
        selectedTemplateID = templateID
        resetRenderOptions(for: templateID)
        previewResponse = nil
        preflightResponse = nil
        exportResponse = nil
        stage = .refineExport
    }

    func renderPreviewIfNeeded() async {
        guard previewResponse == nil else {
            return
        }
        await renderPreview()
    }

    func renderPreview() async {
        guard let request = currentRenderRequest() else {
            return
        }

        isPreviewing = true
        errorMessage = nil
        defer { isPreviewing = false }

        do {
            previewResponse = try await client?.renderPreview(request)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runPreflight() async {
        guard let request = currentRenderRequest() else {
            return
        }

        isRunningPreflight = true
        errorMessage = nil
        defer { isRunningPreflight = false }

        do {
            preflightResponse = try await client?.preflightRender(request)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportCurrentSelection() async {
        guard
            let client,
            let selectedFileURL,
            let selectedTemplateID
        else {
            return
        }

        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            exportResponse = try await client.exportRender(
                .init(
                    inputPath: selectedFileURL.path,
                    sheet: selectedSheet,
                    template: selectedTemplateID,
                    options: renderOptions,
                    outputDir: nil
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealLatestExport() {
        if let manifestPath = exportResponse?.manifestPath {
            WorkspaceBridge.reveal([URL(fileURLWithPath: manifestPath)])
        } else if let outputDir = exportResponse?.outputDir {
            WorkspaceBridge.reveal([URL(fileURLWithPath: outputDir)])
        }
    }

    var availableSheets: [SheetValue] {
        guard let inspectionResponse, !inspectionResponse.sheetNames.isEmpty else {
            return [.index(0)]
        }
        return inspectionResponse.sheetNames.map(SheetValue.name)
    }

    var availableTemplateSummaries: [MetaTemplateSummary] {
        metadata?.templates ?? []
    }

    var recommendedTemplateIDs: Set<String> {
        Set(inspectionResponse?.inspection.recommendations.map(\.templateID) ?? [])
    }

    var recommendedTemplates: [MetaTemplateSummary] {
        availableTemplateSummaries.filter { recommendedTemplateIDs.contains($0.id) }
    }

    var disabledTemplates: [MetaTemplateSummary] {
        availableTemplateSummaries.filter { !recommendedTemplateIDs.contains($0.id) }
    }

    var selectedTemplateSummary: MetaTemplateSummary? {
        availableTemplateSummaries.first { $0.id == selectedTemplateID }
    }

    var editableOptionIDs: Set<String> {
        Set(selectedTemplateSummary?.editableOptions ?? [])
    }

    var allowedSizes: [MetaSizeResponse] {
        guard let selectedTemplateSummary else {
            return metadata?.sizes ?? []
        }
        return (metadata?.sizes ?? []).filter { selectedTemplateSummary.allowedSizes.contains($0.id) }
    }

    var availableStyles: [MetaStyleResponse] {
        guard let selectedTemplateSummary else {
            return metadata?.styles ?? []
        }
        return (metadata?.styles ?? []).filter { selectedTemplateSummary.availableStyles.contains($0.id) }
    }

    var availablePalettes: [MetaPaletteResponse] {
        guard let selectedTemplateSummary else {
            return metadata?.palettes ?? []
        }
        return (metadata?.palettes ?? []).filter { selectedTemplateSummary.availablePalettes.contains($0.id) }
    }

    var sampleColumns: [PlotSampleColumn] {
        if let dataset = inspectionResponse?.dataset, !dataset.columnProfiles.isEmpty {
            return dataset.columnProfiles.enumerated().map { index, profile in
                PlotSampleColumn(id: index, title: profile.name)
            }
        }

        let maxCount = inspectionResponse?.dataset?.sampleRows.first?.count ?? 0
        return (0..<maxCount).map { PlotSampleColumn(id: $0, title: "Column \($0 + 1)") }
    }

    var sampleRows: [PlotSampleRow] {
        inspectionResponse?.dataset?.sampleRows.enumerated().map { index, values in
            PlotSampleRow(id: index, values: values)
        } ?? []
    }

    private func currentRenderRequest() -> RenderRequest? {
        guard
            let selectedFileURL,
            let selectedTemplateID
        else {
            return nil
        }

        return .init(
            inputPath: selectedFileURL.path,
            sheet: selectedSheet,
            template: selectedTemplateID,
            options: renderOptions
        )
    }

    private func chooseInitialTemplate(from response: InspectFileResponse) {
        if let first = response.inspection.primaryRecommendation.first {
            chooseTemplate(first.templateID)
            return
        }

        chooseTemplate(response.inspection.recommendation.template)
    }

    private func resetRenderOptions(for templateID: String) {
        let template = metadata?.templates.first { $0.id == templateID }
        let recommendation = inspectionResponse?.inspection.recommendation

        renderOptions = RenderOptionsPayload(
            size: template?.defaultSize,
            xscale: recommendation?.xscale,
            yscale: recommendation?.yscale,
            reverseX: recommendation?.reverseX ?? false,
            baseline: recommendation?.baseline,
            showColorbar: recommendation?.showColorbar,
            stylePreset: defaultStyle(for: template),
            palettePreset: defaultPalette(for: template),
            useSidecar: true,
            visualThemeID: metadata?.visualThemes.first?.id
        )
    }

    private func defaultStyle(for template: MetaTemplateSummary?) -> String {
        if let template, template.availableStyles.contains(renderOptions.stylePreset) {
            return renderOptions.stylePreset
        }

        if let template, let defaultStyle = metadata?.defaults.stylePreset, template.availableStyles.contains(defaultStyle) {
            return defaultStyle
        }

        return template?.availableStyles.first ?? metadata?.defaults.stylePreset ?? "journal_calm"
    }

    private func defaultPalette(for template: MetaTemplateSummary?) -> String {
        if let template, template.availablePalettes.contains(renderOptions.palettePreset) {
            return renderOptions.palettePreset
        }

        if let template, let defaultPalette = metadata?.defaults.palettePreset, template.availablePalettes.contains(defaultPalette) {
            return defaultPalette
        }

        return template?.availablePalettes.first ?? metadata?.defaults.palettePreset ?? "aqua_graphite"
    }
}
