import Foundation
import Observation
import CoreGraphics

@MainActor
@Observable
final class PlotSession {
    typealias PlotExportDestinationChooser = @MainActor (_ suggestedName: String, _ isMultiOutput: Bool) -> URL?
    typealias PlotExportMaterializer = @MainActor (_ sourceURLs: [URL], _ destinationURL: URL) throws -> [URL]

    private let previewDebounceNanoseconds: UInt64 = 250_000_000

    @ObservationIgnored private var client: (any SidecarClienting)?
    @ObservationIgnored private let chooseExportDestination: PlotExportDestinationChooser
    @ObservationIgnored private let materializeExport: PlotExportMaterializer
    @ObservationIgnored private var inspectedInputPath: String?
    @ObservationIgnored private var inspectedSheet: SheetValue?
    @ObservationIgnored private var inspectionTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var inspectionRevision = 0
    @ObservationIgnored private var previewRevision = 0
    @ObservationIgnored private var thumbnailKindCache: [String: PlotTemplateThumbnailKind] = [:]
    @ObservationIgnored private var stagedExternalPinnedSheet: SheetValue?
    @ObservationIgnored private var stagedExternalPinnedTemplateID: String?
    @ObservationIgnored var renderOptionsDidChange: ((RenderOptionsPayload) -> Void)?

    var isImporterPresented = false
    var isGuidePresented = false
    var isSourceInspectorPresented = false
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

    var liveStatusLabel: String {
        if selectedFileURL == nil {
            return "Awaiting import"
        }
        if isInspecting {
            return "Inspecting source"
        }
        if isPreviewing {
            return previewResponse == nil ? "Rendering preview" : "Refreshing preview"
        }
        if previewResponse != nil {
            return "Preview ready"
        }
        return "Ready"
    }

    var liveStatusSymbol: String {
        if errorMessage != nil {
            return "exclamationmark.triangle.fill"
        }
        if isInspecting || isPreviewing {
            return "arrow.triangle.2.circlepath"
        }
        if previewResponse != nil {
            return "checkmark.circle.fill"
        }
        return "circle.dashed"
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
        schedulePreviewRefresh(policy: .immediate)
    }

    func showGuide() {
        isGuidePresented = true
    }

    func dismissGuide() {
        isGuidePresented = false
    }

    func showSourceInspector() {
        isSourceInspectorPresented = true
    }

    func dismissSourceInspector() {
        isSourceInspectorPresented = false
    }

    func importFile(_ url: URL) {
        prepareSource(url: url, sheet: .index(0), resetTemplate: true)
        scheduleInspection()
    }

    func importFileAndInspect(_ url: URL) async {
        importFile(url)
        await waitUntilInspectionFinishes(for: url)
    }

    func seedFromDataStudio(workbookURL: URL, preferredSheet: SheetValue) {
        prepareSource(url: workbookURL, sheet: preferredSheet, resetTemplate: true)
        scheduleInspection()
    }

    func setSelectedSheet(_ sheet: SheetValue) {
        guard selectedFileURL != nil else {
            selectedSheet = sheet
            return
        }
        guard selectedSheet != sheet || needsInspection else {
            return
        }
        selectedSheet = sheet
        previewRevision += 1
        cancelPreviewTask()
        isPreviewing = false
        invalidateSubmissionArtifacts()
        errorMessage = nil
        scheduleInspection()
    }

    func selectSheetAndReinspect(_ sheet: SheetValue) async {
        setSelectedSheet(sheet)
        guard let selectedFileURL else {
            return
        }
        await waitUntilInspectionFinishes(for: selectedFileURL)
    }

    func chooseTemplate(_ templateID: String) {
        guard selectedTemplateID != templateID else {
            return
        }
        setTemplate(templateID, shouldResetRenderOptions: true)
        schedulePreviewRefresh(policy: .immediate)
    }

    func updateRenderOptions(
        policy: PlotPreviewRefreshPolicy = .debounced,
        mutate: (inout RenderOptionsPayload) -> Void
    ) {
        mutate(&renderOptions)
        notifyRenderOptionsDidChange()
        invalidateSubmissionArtifacts()
        errorMessage = nil
        schedulePreviewRefresh(policy: policy)
    }

    func clearPreviewContext(preserveRenderOptions: Bool = true) {
        cancelInspectionTask()
        cancelPreviewTask()
        selectedFileURL = nil
        selectedSheet = .index(0)
        inspectionResponse = nil
        previewResponse = nil
        preflightResponse = nil
        exportResponse = nil
        userExportURLs = []
        errorMessage = nil
        isInspecting = false
        isPreviewing = false
        isRunningPreflight = false
        isExporting = false
        selectedTemplateID = nil
        inspectedInputPath = nil
        inspectedSheet = nil
        if !preserveRenderOptions {
            renderOptions = RenderOptionsPayload(
                stylePreset: metadata?.defaults.stylePreset ?? "default",
                palettePreset: metadata?.defaults.palettePreset ?? "colorblind_safe",
                visualThemeID: metadata?.visualThemes.first?.id
            )
            notifyRenderOptionsDidChange()
        }
    }

    func loadExternalFigure(
        inputURL: URL,
        sheet: SheetValue,
        preferredTemplateID: String? = nil,
        preferredOptions: RenderOptionsPayload? = nil
    ) async {
        stageExternalFigure(
            inputURL: inputURL,
            sheet: sheet,
            preferredTemplateID: preferredTemplateID,
            preferredOptions: preferredOptions
        )
        await finishLoadingStagedExternalFigure(
            preferredTemplateID: preferredTemplateID,
            preferredOptions: preferredOptions
        )
    }

    func stageExternalFigure(
        inputURL: URL,
        sheet: SheetValue,
        preferredTemplateID: String? = nil,
        preferredOptions: RenderOptionsPayload? = nil
    ) {
        prepareSource(url: inputURL, sheet: sheet, resetTemplate: true)
        stagedExternalPinnedSheet = sheet
        stagedExternalPinnedTemplateID = preferredTemplateID
        if let preferredTemplateID {
            selectedTemplateID = preferredTemplateID
        }
        if let preferredOptions {
            renderOptions = preferredOptions
            notifyRenderOptionsDidChange()
        }
    }

    func finishLoadingStagedExternalFigure(
        preferredTemplateID: String? = nil,
        preferredOptions: RenderOptionsPayload? = nil,
        expectedInputURL: URL? = nil,
        expectedSheet: SheetValue? = nil
    ) async {
        guard let inputURL = expectedInputURL ?? selectedFileURL else {
            return
        }
        defer {
            stagedExternalPinnedSheet = nil
            stagedExternalPinnedTemplateID = nil
        }
        let targetSheet = expectedSheet ?? selectedSheet
        scheduleInspection()
        await waitUntilInspectionFinishes(for: inputURL)
        guard errorMessage == nil else {
            return
        }
        guard selectedFileURL == inputURL, selectedSheet == targetSheet else {
            return
        }

        if let preferredTemplateID,
           selectedTemplateID != preferredTemplateID,
           (compatibleTemplateIDs.contains(preferredTemplateID) || templateSummary(for: preferredTemplateID) != nil)
        {
            chooseTemplate(preferredTemplateID)
        }
        guard selectedFileURL == inputURL, selectedSheet == targetSheet else {
            return
        }

        if let preferredOptions {
            applyExternalRenderOptions(preferredOptions)
        } else {
            await waitUntilPreviewFinishes(for: inputURL)
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

    func openCurrentSource() {
        guard let selectedFileURL else {
            return
        }
        WorkspaceBridge.open(selectedFileURL)
    }

    func revealCurrentSource() {
        guard let selectedFileURL else {
            return
        }
        WorkspaceBridge.reveal([selectedFileURL])
    }

    func openExampleDataTemplate(named filename: String) {
        do {
            let url = try exampleDataTemplateURL(named: filename)
            WorkspaceBridge.open(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealExampleDataTemplates() {
        do {
            WorkspaceBridge.reveal(try availableExampleDataTemplateURLs())
        } catch {
            errorMessage = error.localizedDescription
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
            return templates.prefix(5).map { template in
                PlotTemplateGalleryItem(
                    id: template.id,
                    title: template.label,
                    hint: "Inspect first",
                    selectable: false
                )
            }
        }

        let summariesByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
        return compatibleRecommendations.prefix(5).map { recommendation in
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

    var selectedTemplateRecommendation: TemplateRecommendationResponse? {
        guard let selectedTemplateID else {
            return nil
        }
        return compatibleRecommendations.first { $0.templateID == selectedTemplateID }
            ?? inspectionResponse?.inspection.recommendations.first { $0.templateID == selectedTemplateID }
    }

    var recommendedXAxisLabel: String? {
        if let label = selectedTemplateRecommendation?.inferredMapping["x"], !label.isEmpty {
            return label
        }
        if let label = inspectionResponse?.inspection.recommendations.first?.inferredMapping["x"], !label.isEmpty {
            return label
        }
        return nil
    }

    var recommendedYAxisLabel: String? {
        if let label = selectedTemplateRecommendation?.inferredMapping["y"], !label.isEmpty {
            return label
        }
        if let label = inspectionResponse?.inspection.recommendations.first?.inferredMapping["y"], !label.isEmpty {
            return label
        }
        return nil
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

    var candidateSeriesLabels: [String] {
        inspectionResponse?.dataset?.candidateRoles.series ?? []
    }

    var shouldShowSeriesLegendControls: Bool {
        editableOptionIDs.contains("series_order") && candidateSeriesLabels.count > 1
    }

    var seriesOrderLabels: [String] {
        guard shouldShowSeriesLegendControls else {
            return []
        }

        if let explicit = renderOptions.seriesOrder, !explicit.isEmpty {
            return explicit
        }

        return candidateSeriesLabels
    }

    var canEditSeriesOrder: Bool {
        shouldShowSeriesLegendControls
    }

    func setSeriesOrder(_ labels: [String]) {
        guard shouldShowSeriesLegendControls else {
            return
        }
        let cleaned = labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        renderOptions.seriesOrder = cleaned.isEmpty ? nil : cleaned
        notifyRenderOptionsDidChange()
        invalidateSubmissionArtifacts()
        errorMessage = nil
        schedulePreviewRefresh(policy: .immediate)
    }

    func moveSeriesOrder(from source: IndexSet, to destination: Int) {
        var labels = seriesOrderLabels
        labels.move(fromOffsets: source, toOffset: destination)
        setSeriesOrder(labels)
    }

    func resetSeriesOrder() {
        renderOptions.seriesOrder = nil
        notifyRenderOptionsDidChange()
        invalidateSubmissionArtifacts()
        errorMessage = nil
        schedulePreviewRefresh(policy: .immediate)
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

    func templateThumbnailAspectRatio(for templateID: String) -> CGFloat {
        guard let summary = templateSummary(for: templateID),
              let size = metadata?.sizes.first(where: { $0.id == summary.defaultSize })
        else {
            return 60.0 / 55.0
        }
        guard size.heightMm > 0 else {
            return 60.0 / 55.0
        }
        return CGFloat(size.widthMm / size.heightMm)
    }

    func thumbnailKind(for templateID: String) -> PlotTemplateThumbnailKind {
        if let cached = thumbnailKindCache[templateID] {
            return cached
        }

        let resolved = resolveThumbnailKind(for: templateID)
        thumbnailKindCache[templateID] = resolved
        return resolved
    }

    private func prepareSource(url: URL, sheet: SheetValue, resetTemplate: Bool) {
        cancelInspectionTask()
        previewRevision += 1
        cancelPreviewTask()
        isPreviewing = false
        selectedFileURL = url
        selectedSheet = sheet
        inspectionResponse = nil
        inspectedInputPath = nil
        inspectedSheet = nil
        if resetTemplate {
            selectedTemplateID = nil
        }
        stagedExternalPinnedSheet = nil
        stagedExternalPinnedTemplateID = nil
        invalidateSubmissionArtifacts()
        errorMessage = nil
    }

    private func scheduleInspection() {
        guard let request = currentInspectionRequest() else {
            return
        }

        inspectionRevision += 1
        let revision = inspectionRevision
        cancelInspectionTask()
        isInspecting = true
        errorMessage = nil

        inspectionTask = Task { [weak self] in
            guard let self else { return }
            await self.performInspection(request: request, revision: revision)
        }
    }

    private func performInspection(request: FileRequest, revision: Int) async {
        guard let client else {
            if revision == inspectionRevision {
                isInspecting = false
                inspectionTask = nil
            }
            return
        }

        do {
            let response = try await client.inspectFile(request)
            guard revision == inspectionRevision else {
                return
            }
            applyInspectionResponse(response)
            isInspecting = false
            inspectionTask = nil
        } catch {
            guard revision == inspectionRevision else {
                return
            }
            errorMessage = error.localizedDescription
            isInspecting = false
            inspectionTask = nil
        }
    }

    private func applyInspectionResponse(_ response: InspectFileResponse) {
        inspectionResponse = response
        let resolvedSheet = stagedExternalPinnedSheet ?? response.sheet
        selectedSheet = resolvedSheet
        inspectedInputPath = response.inputPath
        inspectedSheet = resolvedSheet
        invalidateSubmissionArtifacts()
        errorMessage = nil

        if shouldAutoSelectTemplate(after: response, preservingTemplateID: stagedExternalPinnedTemplateID) {
            let preferredTemplateID = response.inspection.recommendations.first?.templateID
                ?? response.inspection.primaryRecommendation.first?.templateID
                ?? selectedTemplateID
            if let preferredTemplateID {
                setTemplate(preferredTemplateID, shouldResetRenderOptions: true)
            }
        }

        schedulePreviewRefresh(policy: .immediate)
    }

    private func shouldAutoSelectTemplate(
        after _: InspectFileResponse,
        preservingTemplateID: String? = nil
    ) -> Bool {
        if let preservingTemplateID, selectedTemplateID == preservingTemplateID {
            return false
        }
        guard let selectedTemplateID else {
            return true
        }
        return !compatibleTemplateIDs.contains(selectedTemplateID)
    }

    private func setTemplate(_ templateID: String, shouldResetRenderOptions: Bool) {
        selectedTemplateID = templateID
        if shouldResetRenderOptions {
            resetRenderOptions(for: templateID)
        }
        invalidateSubmissionArtifacts()
        errorMessage = nil
    }

    private func schedulePreviewRefresh(policy: PlotPreviewRefreshPolicy) {
        guard let request = currentRenderRequest() else {
            return
        }

        previewRevision += 1
        let revision = previewRevision
        cancelPreviewTask()
        isPreviewing = true
        errorMessage = nil

        let delay = policy == .debounced ? previewDebounceNanoseconds : 0
        previewTask = Task { [weak self] in
            guard let self else { return }
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else {
                return
            }
            await self.performPreview(request: request, revision: revision)
        }
    }

    private func performPreview(request: RenderRequest, revision: Int) async {
        guard let client else {
            if revision == previewRevision {
                isPreviewing = false
                previewTask = nil
            }
            return
        }

        do {
            let response = try await client.renderPreview(request)
            guard revision == previewRevision else {
                return
            }
            previewResponse = response
            isPreviewing = false
            errorMessage = nil
            previewTask = nil
        } catch {
            guard revision == previewRevision else {
                return
            }
            errorMessage = error.localizedDescription
            isPreviewing = false
            previewTask = nil
        }
    }

    private func currentInspectionRequest() -> FileRequest? {
        guard let selectedFileURL else {
            return nil
        }
        return .init(inputPath: selectedFileURL.path, sheet: selectedSheet)
    }

    private func currentRenderRequest() -> RenderRequest? {
        guard
            let selectedFileURL,
            let selectedTemplateID,
            !needsInspection
        else {
            return nil
        }

        sanitizeRenderOptionsForCurrentTemplateIfNeeded()

        return .init(
            inputPath: selectedFileURL.path,
            sheet: selectedSheet,
            template: selectedTemplateID,
            options: renderOptions
        )
    }

    private func resetRenderOptions(for templateID: String) {
        let template = metadata?.templates.first { $0.id == templateID }
        let recommendationSummary = recommendedPreviewConfigSummary(for: templateID)

        renderOptions = RenderOptionsPayload(
            size: recommendationSummary["size"]?.stringValue ?? template?.defaultSize,
            xscale: recommendationSummary["xscale"]?.stringValue,
            yscale: recommendationSummary["yscale"]?.stringValue,
            reverseX: recommendationSummary["reverse_x"]?.boolValue ?? false,
            seriesOrder: nil,
            xLabelOverride: nil,
            yLabelOverride: nil,
            baseline: recommendationSummary["baseline"]?.stringValue,
            showColorbar: recommendationSummary["show_colorbar"]?.boolValue,
            stylePreset: defaultStyle(for: template),
            palettePreset: defaultPalette(for: template),
            useSidecar: recommendationSummary["use_sidecar"]?.boolValue ?? true,
            visualThemeID: metadata?.visualThemes.first?.id
        )
        notifyRenderOptionsDidChange()
    }

    private func recommendedPreviewConfigSummary(for templateID: String) -> [String: JSONValue] {
        let selected = inspectionResponse?.inspection.recommendations.first { $0.templateID == templateID }
            ?? compatibleRecommendations.first { $0.templateID == templateID }
            ?? inspectionResponse?.inspection.recommendations.first
            ?? inspectionResponse?.inspection.primaryRecommendation.first
        return selected?.previewConfigSummary ?? [:]
    }

    private func applyExternalRenderOptions(_ options: RenderOptionsPayload) {
        guard let template = selectedTemplateSummary else {
            renderOptions = options
            notifyRenderOptionsDidChange()
            schedulePreviewRefresh(policy: .immediate)
            return
        }

        var resolved = options
        resolved.size = template.allowedSizes.contains(options.size ?? "") ? options.size : template.defaultSize
        if !template.availableStyles.contains(resolved.stylePreset) {
            resolved.stylePreset = defaultStyle(for: template)
        }
        if !template.availablePalettes.contains(resolved.palettePreset) {
            resolved.palettePreset = defaultPalette(for: template)
        }
        renderOptions = resolved
        notifyRenderOptionsDidChange()
        invalidateSubmissionArtifacts()
        errorMessage = nil
        schedulePreviewRefresh(policy: .immediate)
    }

    private func defaultStyle(for template: MetaTemplateSummary?) -> String {
        if let template, template.availableStyles.contains(renderOptions.stylePreset) {
            return renderOptions.stylePreset
        }

        if let template, let defaultStyle = metadata?.defaults.stylePreset, template.availableStyles.contains(defaultStyle) {
            return defaultStyle
        }

        return template?.availableStyles.first ?? metadata?.defaults.stylePreset ?? "default"
    }

    private func defaultPalette(for template: MetaTemplateSummary?) -> String {
        if let template, template.availablePalettes.contains(renderOptions.palettePreset) {
            return renderOptions.palettePreset
        }

        if let template, let defaultPalette = metadata?.defaults.palettePreset, template.availablePalettes.contains(defaultPalette) {
            return defaultPalette
        }

        return template?.availablePalettes.first ?? metadata?.defaults.palettePreset ?? "colorblind_safe"
    }

    private func sanitizeRenderOptionsForCurrentTemplateIfNeeded() {
        var resolved = renderOptions

        if let template = selectedTemplateSummary {
            if !template.availableStyles.contains(resolved.stylePreset) {
                resolved.stylePreset = defaultStyle(for: template)
            }
            if !template.availablePalettes.contains(resolved.palettePreset) {
                resolved.palettePreset = defaultPalette(for: template)
            }
        } else if let metadata {
            let validStyles = Set(metadata.styles.map(\.id))
            let validPalettes = Set(metadata.palettes.map(\.id))

            if !validStyles.contains(resolved.stylePreset) {
                resolved.stylePreset = validStyles.contains(metadata.defaults.stylePreset)
                    ? metadata.defaults.stylePreset
                    : (metadata.styles.first?.id ?? "default")
            }
            if !validPalettes.contains(resolved.palettePreset) {
                resolved.palettePreset = validPalettes.contains(metadata.defaults.palettePreset)
                    ? metadata.defaults.palettePreset
                    : (metadata.palettes.first?.id ?? "colorblind_safe")
            }
        }

        guard resolved != renderOptions else {
            return
        }
        renderOptions = resolved
        notifyRenderOptionsDidChange()
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

    private func shortCompatibilityHint(from recommendation: TemplateRecommendationResponse) -> String {
        let text = recommendation.suitabilityHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let lower = text.lowercased()
            if lower.contains("recommend") {
                return "Recommended"
            }
            if lower.contains("fallback") {
                return "Fallback"
            }
            if lower.contains("compat") {
                return "Compatible"
            }
        }
        if let rank = recommendation.rank {
            return rank == 1 ? "Recommended" : "Compatible"
        }
        return "Compatible"
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

    private func exampleDataTemplateURL(named filename: String) throws -> URL {
        let rootURL = try RepoLocator().locateRepositoryRoot()
        let url = rootURL
            .appendingPathComponent("examples", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    private func availableExampleDataTemplateURLs() throws -> [URL] {
        try [
            "curve_table.csv",
            "replicate_table.csv",
        ].map(exampleDataTemplateURL(named:))
    }

    private func invalidateSubmissionArtifacts() {
        preflightResponse = nil
        exportResponse = nil
        userExportURLs = []
    }

    private func notifyRenderOptionsDidChange() {
        renderOptionsDidChange?(renderOptions)
    }

    private func cancelInspectionTask() {
        inspectionTask?.cancel()
        inspectionTask = nil
    }

    private func cancelPreviewTask() {
        previewTask?.cancel()
        previewTask = nil
    }

    private func waitUntilInspectionFinishes(for _: URL?) async {
        await inspectionTask?.value
    }

    private func waitUntilPreviewFinishes(for _: URL?) async {
        await previewTask?.value
    }
}
