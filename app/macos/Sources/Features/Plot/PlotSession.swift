import Foundation
import Observation

enum PlotWorkspaceMode: String, CaseIterable, Identifiable {
    case review
    case refine

    var id: String { rawValue }
}

struct PlotTemplateGalleryItem: Identifiable, Hashable {
    let id: String
    let title: String
    let hint: String
    let selectable: Bool
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
    typealias PlotExportDestinationChooser = @MainActor (_ suggestedName: String, _ isMultiOutput: Bool) -> URL?
    typealias PlotExportMaterializer = @MainActor (_ sourceURLs: [URL], _ destinationURL: URL) throws -> [URL]

    @ObservationIgnored private var client: (any SidecarClienting)?
    @ObservationIgnored private let chooseExportDestination: PlotExportDestinationChooser
    @ObservationIgnored private let materializeExport: PlotExportMaterializer
    @ObservationIgnored private var inspectedInputPath: String?
    @ObservationIgnored private var inspectedSheet: SheetValue?
    @ObservationIgnored private var thumbnailKindCache: [String: PlotTemplateThumbnailKind] = [:]

    var workspaceMode: PlotWorkspaceMode = .review
    var isImporterPresented = false
    var selectedFileURL: URL?
    var selectedSheet: SheetValue = .index(0)
    var inspectionResponse: InspectFileResponse?
    var metadata: SidecarMetaResponse?
    var contract: PlotContractResponse?
    var selectedTemplateID: String?
    var renderOptions = RenderOptionsPayload() {
        didSet {
            guard renderOptions != oldValue else {
                return
            }
            invalidateRenderArtifacts()
        }
    }
    var previewResponse: RenderPreviewResponse?
    var preflightResponse: PreflightRenderResponse?
    var exportResponse: ExportRenderResponse?
    var errorMessage: String?
    var isInspecting = false
    var isPreviewing = false
    var isRunningPreflight = false
    var isExporting = false
    var userExportURLs: [URL] = []

    init(
        chooseExportDestination: @escaping PlotExportDestinationChooser = {
            NativeExportCoordinator.choosePlotExportLocation(suggestedName: $0, isMultiOutput: $1)
        },
        materializeExport: @escaping PlotExportMaterializer = {
            try NativeExportCoordinator.materializePlotOutputs(sourceURLs: $0, destinationURL: $1)
        }
    ) {
        self.chooseExportDestination = chooseExportDestination
        self.materializeExport = materializeExport
    }

    var hasSessionContent: Bool {
        selectedFileURL != nil || inspectionResponse != nil || selectedTemplateID != nil
    }

    var hasRenderableSelection: Bool {
        selectedFileURL != nil && selectedTemplateID != nil && !needsInspection
    }

    var needsInspection: Bool {
        guard let selectedFileURL else {
            return false
        }
        guard let inspectedInputPath, let inspectedSheet else {
            return true
        }
        return inspectedInputPath != selectedFileURL.path || inspectedSheet != selectedSheet || inspectionResponse == nil
    }

    var canContinueToRefine: Bool {
        hasRenderableSelection
            && !isInspecting
            && !isPreviewing
            && (workspaceMode != .refine || previewResponse == nil)
    }

    var inspectOrReviewActionTitle: String {
        needsInspection ? "Inspect" : "Review"
    }

    var canInspectOrReviewAction: Bool {
        if needsInspection {
            return selectedFileURL != nil && !isInspecting
        }
        return workspaceMode != .review
    }

    var selectedSourceFilename: String? {
        selectedFileURL?.lastPathComponent
    }

    var selectedSourcePath: String? {
        selectedFileURL?.path
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
        inspectedInputPath = nil
        inspectedSheet = nil
        invalidateRenderArtifacts()
        userExportURLs = []
        errorMessage = nil
        workspaceMode = .review
    }

    func importFileAndInspect(_ url: URL) async {
        handleImportedFile(url)
        await inspectCurrentFile()
    }

    func seedFromCleanup(workbookURL: URL, preferredSheet: SheetValue) {
        handleImportedFile(workbookURL)
        selectedSheet = preferredSheet
        Task {
            await inspectCurrentFile()
        }
    }

    func selectSheetAndReinspect(_ sheet: SheetValue) async {
        guard selectedFileURL != nil else {
            selectedSheet = sheet
            return
        }

        guard selectedSheet != sheet || needsInspection else {
            return
        }

        selectedSheet = sheet
        inspectionResponse = nil
        selectedTemplateID = nil
        inspectedInputPath = nil
        inspectedSheet = nil
        invalidateRenderArtifacts()
        workspaceMode = .review
        await inspectCurrentFile()
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
            inspectedInputPath = selectedFileURL.path
            inspectedSheet = response.sheet
            chooseInitialTemplate(from: response)
            workspaceMode = .review
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runInspectOrReviewAction() async {
        if needsInspection {
            await inspectCurrentFile()
        } else {
            returnToReview()
        }
    }

    func chooseTemplate(_ templateID: String) {
        guard selectedTemplateID != templateID else {
            return
        }
        selectedTemplateID = templateID
        resetRenderOptions(for: templateID)
        workspaceMode = .review
        userExportURLs = []
        errorMessage = nil
        invalidateRenderArtifacts()
    }

    func renderPreviewIfNeeded() async {
        guard previewResponse == nil else {
            return
        }
        await renderPreview()
    }

    func continueToRefine() async {
        guard canContinueToRefine else {
            return
        }
        workspaceMode = .refine
        await renderPreviewIfNeeded()
    }

    func returnToReview() {
        workspaceMode = .review
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
            let selectedTemplateID,
            hasRenderableSelection
        else {
            return
        }

        let isMultiOutput = isMultiOutputTemplate(templateID: selectedTemplateID)
        guard let destinationURL = chooseExportDestination(
            suggestedPlotExportFilename(templateID: selectedTemplateID),
            isMultiOutput
        ) else {
            return
        }

        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let response = try await client.exportRender(
                .init(
                    inputPath: selectedFileURL.path,
                    sheet: selectedSheet,
                    template: selectedTemplateID,
                    options: renderOptions,
                    outputDir: nil
                )
            )
            let sourceURLs = response.outputs.map { URL(fileURLWithPath: $0) }
            userExportURLs = try materializeExport(sourceURLs, destinationURL)
            exportResponse = response
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealLatestExport() {
        if !userExportURLs.isEmpty {
            WorkspaceBridge.reveal(userExportURLs)
        }
    }

    var latestExportDestinationDescription: String? {
        guard !userExportURLs.isEmpty else {
            return nil
        }
        if userExportURLs.count == 1 {
            return userExportURLs[0].path
        }
        return userExportURLs[0].deletingLastPathComponent().path
    }

    var availableSheets: [SheetValue] {
        if let inspectionResponse, !inspectionResponse.sheetNames.isEmpty {
            return inspectionResponse.sheetNames.map(SheetValue.name)
        }
        if selectedFileURL != nil {
            return [selectedSheet]
        }
        return [.index(0)]
    }

    var availableTemplateSummaries: [MetaTemplateSummary] {
        metadata?.templates ?? []
    }

    var templateGalleryItems: [PlotTemplateGalleryItem] {
        let templates = availableTemplateSummaries
        guard !templates.isEmpty else {
            return []
        }

        guard inspectionResponse != nil else {
            return templates.map { template in
                PlotTemplateGalleryItem(
                    id: template.id,
                    title: template.label,
                    hint: shortGalleryHint(for: template),
                    selectable: false
                )
            }
        }

        let summariesByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
        return compatibleRecommendations.map { recommendation in
            let summary = summariesByID[recommendation.templateID]
            return PlotTemplateGalleryItem(
                id: recommendation.templateID,
                title: summary?.label ?? recommendation.templateID,
                hint: shortCompatibilityHint(from: recommendation),
                selectable: true
            )
        }
    }

    var compatibleRecommendations: [TemplateRecommendationResponse] {
        guard let inspection = inspectionResponse?.inspection else {
            return []
        }

        let orderedCandidates = inspection.primaryRecommendation + inspection.alternativeRecommendations + inspection.advancedTemplates
        let source = orderedCandidates.isEmpty ? inspection.recommendations : orderedCandidates
        var seen: Set<String> = []
        return source.filter { candidate in
            seen.insert(candidate.templateID).inserted
        }
    }

    var compatibleTemplateIDs: Set<String> {
        Set(compatibleRecommendations.map(\.templateID))
    }

    var unavailableTemplateCount: Int {
        max(0, availableTemplateSummaries.count - compatibleTemplateIDs.count)
    }

    var selectedTemplateRecommendation: TemplateRecommendationResponse? {
        guard let selectedTemplateID else {
            return nil
        }
        return compatibleRecommendations.first { $0.templateID == selectedTemplateID }
            ?? inspectionResponse?.inspection.recommendations.first { $0.templateID == selectedTemplateID }
    }

    func templateSummary(for templateID: String) -> MetaTemplateSummary? {
        availableTemplateSummaries.first { $0.id == templateID }
    }

    func templateLabel(for templateID: String) -> String {
        templateSummary(for: templateID)?.label ?? templateID
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

    var candidateRoleRows: [(String, String)] {
        guard let roles = inspectionResponse?.dataset?.candidateRoles else {
            return []
        }

        let pairs: [(String, [String])] = [
            ("X", roles.x),
            ("Y", roles.y),
            ("Z", roles.z),
            ("Group", roles.group),
            ("Sample", roles.sample),
            ("Value", roles.value),
            ("Metric", roles.metric),
            ("Label", roles.label),
            ("Series", roles.series),
        ]

        return pairs.compactMap { title, values in
            guard !values.isEmpty else {
                return nil
            }
            return (title, values.prefix(3).joined(separator: ", "))
        }
    }

    var inferredMappingRows: [(String, String)] {
        guard let mapping = selectedTemplateRecommendation?.inferredMapping else {
            return []
        }

        return mapping
            .filter { !$0.value.isEmpty }
            .map { (key: $0.key, value: $0.value) }
            .sorted { $0.key < $1.key }
    }

    func thumbnailKind(for templateID: String) -> PlotTemplateThumbnailKind {
        if let cached = thumbnailKindCache[templateID] {
            return cached
        }

        let resolved = resolveThumbnailKind(for: templateID)
        thumbnailKindCache[templateID] = resolved
        return resolved
    }

    private func currentRenderRequest() -> RenderRequest? {
        guard
            let selectedFileURL,
            let selectedTemplateID,
            !needsInspection
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
        let preferredTemplateID = response.inspection.primaryRecommendation.first?.templateID
            ?? response.inspection.recommendation.template
        selectedTemplateID = preferredTemplateID
        resetRenderOptions(for: preferredTemplateID)
        invalidateRenderArtifacts()
        errorMessage = nil
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

    private func suggestedPlotExportFilename(templateID: String) -> String {
        if let exportResponse,
           let firstOutput = exportResponse.outputs.first
        {
            return URL(fileURLWithPath: firstOutput).lastPathComponent
        }
        if let selectedFileURL {
            return "\(selectedFileURL.deletingPathExtension().lastPathComponent)_\(templateID).pdf"
        }
        return "\(templateID).pdf"
    }

    private func isMultiOutputTemplate(templateID: String) -> Bool {
        guard templateID == "point_line" || templateID == "curve" else {
            return false
        }
        guard let model = inspectionResponse?.inspection.model else {
            return false
        }
        return model == "frequency_sweep" || model == "temperature_sweep" || model == "stress_relaxation"
    }

    private func shortGalleryHint(for template: MetaTemplateSummary) -> String {
        switch template.category.lowercased() {
        case "curve":
            return "Curve"
        case "stats":
            return "Statistics"
        case "heatmap":
            return "Heatmap"
        default:
            return "Template"
        }
    }

    private func shortCompatibilityHint(from recommendation: TemplateRecommendationResponse) -> String {
        let text = recommendation.suitabilityHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return truncateHint(text)
        }
        if let rank = recommendation.rank {
            return rank == 1 ? "Top match" : "Rank #\(rank)"
        }
        return "Compatible"
    }

    private func truncateHint(_ text: String, limit: Int = 28) -> String {
        guard text.count > limit else {
            return text
        }
        let index = text.index(text.startIndex, offsetBy: limit)
        return "\(text[..<index])…"
    }

    private func resolveThumbnailKind(for templateID: String) -> PlotTemplateThumbnailKind {
        let normalizedID = templateID.lowercased()
        let category = templateSummary(for: templateID)?.category.lowercased() ?? ""

        if normalizedID.contains("heatmap") || category.contains("heatmap") {
            return .heatmap
        }
        if normalizedID.contains("bar") || normalizedID.contains("hist") || category.contains("stats") {
            return .bar
        }
        if normalizedID.contains("box") {
            return .box
        }
        if normalizedID.contains("violin") {
            return .violin
        }
        if normalizedID.contains("scatter") {
            return .scatter
        }
        if normalizedID.contains("point_line") || normalizedID.contains("pointline") {
            return .pointLine
        }
        if normalizedID.contains("curve") || normalizedID.contains("line") || category.contains("curve") {
            return .curve
        }
        return .fallback
    }

    private func invalidateRenderArtifacts() {
        previewResponse = nil
        preflightResponse = nil
        exportResponse = nil
        userExportURLs = []
    }
}
