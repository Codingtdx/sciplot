import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class PlotSession {
    typealias PlotExportFormatChooser = @MainActor (_ isMultiOutput: Bool) -> ExportGraphicFormat?
    typealias PlotExportDestinationChooser = @MainActor (_ suggestedName: String, _ isMultiOutput: Bool, _ format: ExportGraphicFormat) -> URL?
    typealias PlotExportMaterializer = @MainActor (_ sourceURLs: [URL], _ destinationURL: URL) throws -> [URL]
    typealias PlotProjectSaveChooser = @MainActor (_ suggestedName: String) -> URL?

    struct UndoSnapshot: Equatable {
        let selectedSheet: SheetValue
        let selectedTemplateID: String?
        let renderOptions: RenderOptionsPayload
        let fitOptions: FitOptionsPayload
    }

    struct ProjectSnapshot: Equatable {
        let sourcePath: String
        let selectedSheet: SheetValue
        let selectedTemplateID: String
        let renderOptions: RenderOptionsPayload
        let fitOptions: FitOptionsPayload
    }

    struct RuntimeState {
        var inspectedInputPath: String?
        var inspectedSheet: SheetValue?
        var stagedExternalPinnedSheet: SheetValue?
        var stagedExternalPinnedTemplateID: String?
        var isApplyingUndoRedo = false
        var lastSavedProjectSnapshot: ProjectSnapshot?
    }

    @MainActor
    final class AsyncCoordination {
        let inspection = AsyncLatestTaskCoordinator()
        let preview = AsyncLatestTaskCoordinator()
        let sourceTablePreview = AsyncLatestTaskCoordinator()
        let fitAnalysis = AsyncLatestTaskCoordinator()
    }

    let previewDebounceNanoseconds: UInt64 = 250_000_000

    @ObservationIgnored var client: (any SidecarClienting)?
    @ObservationIgnored let chooseExportFormat: PlotExportFormatChooser
    @ObservationIgnored let chooseExportDestination: PlotExportDestinationChooser
    @ObservationIgnored let materializeExport: PlotExportMaterializer
    @ObservationIgnored let chooseProjectSaveLocation: PlotProjectSaveChooser
    @ObservationIgnored var openProjectDocumentHandler: ((URL) async -> Void)?
    @ObservationIgnored var runtimeState = RuntimeState()
    @ObservationIgnored let asyncCoordination = AsyncCoordination()
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored var renderOptionsDidChange: ((RenderOptionsPayload) -> Void)?
    @ObservationIgnored var fitOptionsDidChange: ((FitOptionsPayload) -> Void)?

    var isImporterPresented = false
    var isDataWorkbookPresented = false
    var isStyleStudioPresented = false
    var isScientificTextDictionaryPresented = false
    var selectedFileURL: URL?
    var projectURL: URL?
    var selectedSheet: SheetValue = .index(0)
    var inspectionResponse: InspectFileResponse?
    var metadata: SidecarMetaResponse?
    var contract: PlotContractResponse?
    var selectedTemplateID: String?
    var renderOptions = RenderOptionsPayload()
    var fitOptions = FitOptionsPayload()
    var previewResponse: RenderPreviewResponse?
    var previewPixelBucket: PlotPreviewPixelBucket?
    var preflightResponse: PreflightRenderResponse?
    var exportResponse: ExportRenderResponse?
    var errorMessage: String?
    var isInspecting = false
    var isPreviewing = false
    var isRunningPreflight = false
    var isExporting = false
    var isSavingProject = false
    var userExportURLs: [URL] = []
    var dataWorkbookTab: PlotDataWorkbookTab = .sourceData
    var sourceTableResponse: SourceTablePreviewResponse?
    var fitAnalysisResponse: FitAnalysisResponse?
    var sourceTableErrorMessage: String?
    var fitAnalysisErrorMessage: String?
    var isLoadingSourceTable = false
    var isLoadingFitAnalysis = false
    var plotThemes: [PlotThemeSummaryResponse] = []
    var styleStudioWarnings: [String] = []
    var styleStudioErrorMessage: String?
    var isPreviewingStyleStudioDraft = false
    var isSavingStyleStudioTheme = false
    var scientificTextRules: [ScientificTextRuleResponse] = []
    var selectedScientificTextRuleID: String?
    var scientificTextRuleDraft = ScientificTextRulePayload()
    var scientificTextRulePreview: ScientificTextRulePreviewResponse?
    var scientificTextDictionaryErrorMessage: String?
    var isLoadingScientificTextRules = false
    var isSavingScientificTextRule = false
    var sourceTableOffset = 0
    var fitAnalysisOffset = 0
    var fitAnalysisSelectedSeriesID: String?
    var selectedPlotTool: PlotTool = .select
    var selectedPlotAdjustmentCategory: PlotAdjustmentCategory = .figure
    var canvasInteractionMode: PlotCanvasInteractionMode = .select
    var canvasSelection: PlotCanvasSelection = .figure
    var selectedSeriesQuickEditorID: String?
    var selectedReferenceGuideID: String?
    var selectedTextAnnotationID: String?
    var selectedShapeAnnotationID: String?
    var sourceProvenance = PlotProjectSourceProvenancePayload(
        originalInputPath: nil,
        savedInputMtimeNs: nil,
        savedAt: nil
    )

    var exportAvailability: ActionAvailability {
        if isExporting {
            return .disabled("Export is already in progress.")
        }
        guard client != nil else {
            return .disabled("The sidecar is not ready yet.")
        }
        guard selectedFileURL != nil else {
            return .disabled("Import a source file before exporting.")
        }
        guard effectiveTemplateID != nil else {
            return .disabled("Choose a template before exporting.")
        }
        guard !needsInspection else {
            return .disabled("Wait for inspect to finish before exporting.")
        }
        return .enabled()
    }

    var saveProjectAvailability: ActionAvailability {
        if isSavingProject {
            return .disabled("Project save is already in progress.")
        }
        guard client != nil else {
            return .disabled("The sidecar is not ready yet.")
        }
        guard currentProjectSnapshot != nil else {
            return .disabled("Import a plot source before saving a project.")
        }
        guard !needsInspection else {
            return .disabled("Wait for inspect to finish before saving the project.")
        }
        return .enabled()
    }

    var scientificTextRuleSaveAvailability: ActionAvailability {
        if isSavingScientificTextRule {
            return .disabled("Scientific text rule save is already in progress.")
        }
        let input = scientificTextRuleDraft.input.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = scientificTextRuleDraft.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return .disabled("Provide the source text before saving.")
        }
        guard !output.isEmpty else {
            return .disabled("Provide the replacement text before saving.")
        }
        guard let scientificTextRulePreview, scientificTextRulePreviewMatchesDraft(scientificTextRulePreview) else {
            return .disabled("Preview the current text rule before saving it.")
        }
        if !scientificTextRulePreview.errors.isEmpty {
            return .disabled(scientificTextRulePreview.errors.joined(separator: " "))
        }
        return .enabled()
    }

    var revealOutputAvailability: ActionAvailability {
        guard !latestExportItems.isEmpty else {
            return .disabled("Export a plot first.")
        }
        return .enabled()
    }

    var latestExportItems: [ExportedFileItem] {
        userExportURLs.map { ExportedFileItem(url: $0) }
    }

    init(
        chooseExportFormat: @escaping PlotExportFormatChooser = {
            NativeExportCoordinator.choosePlotExportFormat(isMultiOutput: $0)
        },
        chooseExportDestination: @escaping PlotExportDestinationChooser = {
            NativeExportCoordinator.choosePlotExportLocation(
                suggestedName: $0,
                isMultiOutput: $1,
                format: $2
            )
        },
        materializeExport: @escaping PlotExportMaterializer = {
            try NativeExportCoordinator.materializePlotOutputs(sourceURLs: $0, destinationURL: $1)
        },
        chooseProjectSaveLocation: @escaping PlotProjectSaveChooser = {
            NativePanels.choosePlotProjectSaveLocation(suggestedName: $0)
        }
    ) {
        self.chooseExportFormat = chooseExportFormat
        self.chooseExportDestination = chooseExportDestination
        self.materializeExport = materializeExport
        self.chooseProjectSaveLocation = chooseProjectSaveLocation
    }

    var hasSessionContent: Bool {
        selectedFileURL != nil || inspectionResponse != nil || effectiveTemplateID != nil
    }

    var hasRenderableSelection: Bool {
        selectedFileURL != nil && effectiveTemplateID != nil && !needsInspection
    }

    var needsInspection: Bool {
        DerivedState.needsInspection(
            selectedFileURL: selectedFileURL,
            inspectedInputPath: runtimeState.inspectedInputPath,
            inspectedSheet: runtimeState.inspectedSheet,
            selectedSheet: selectedSheet,
            inspectionResponse: inspectionResponse
        )
    }

    var liveStatusSymbol: String {
        DerivedState.liveStatusSymbol(
            hasError: errorMessage != nil,
            isInspecting: isInspecting,
            isPreviewing: isPreviewing,
            previewResponse: previewResponse
        )
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

    func attachUndoManager(_ undoManager: UndoManager?) {
        self.undoManager = undoManager
    }

    func apply(meta: SidecarMetaResponse, contract: PlotContractResponse) {
        metadata = meta
        self.contract = contract
        selectedTemplateID = migrateLegacyTemplateID(selectedTemplateID)
        let validStyleIDs = Set(meta.styles.map(\.id))
        let validPaletteIDs = Set(meta.palettes.map(\.id))
        let validThemeIDs = Set(meta.visualThemes.map(\.id))

        renderOptions.stylePreset = validStyleIDs.contains(renderOptions.stylePreset)
            ? renderOptions.stylePreset
            : meta.defaults.stylePreset
        renderOptions.palettePreset = validPaletteIDs.contains(renderOptions.palettePreset)
            ? renderOptions.palettePreset
            : meta.defaults.palettePreset
        if let themeID = renderOptions.visualThemeID, !validThemeIDs.contains(themeID) {
            renderOptions.visualThemeID = nil
        }
        schedulePreviewRefresh(policy: .immediate)
    }

    func showDataWorkbook(tab: PlotDataWorkbookTab = .sourceData) {
        dataWorkbookTab = tab
        isDataWorkbookPresented = true
    }

    func dismissDataWorkbook() {
        isDataWorkbookPresented = false
    }

    func showStyleStudio() {
        styleStudioErrorMessage = nil
        isStyleStudioPresented = true
        Task { await loadPlotThemes() }
    }

    func dismissStyleStudio() {
        isStyleStudioPresented = false
    }

    func showScientificTextDictionary() {
        scientificTextDictionaryErrorMessage = nil
        isScientificTextDictionaryPresented = true
        Task { await loadScientificTextRules() }
    }

    func dismissScientificTextDictionary() {
        isScientificTextDictionaryPresented = false
    }

    func loadScientificTextRules() async {
        guard let client else {
            scientificTextDictionaryErrorMessage = "The sidecar is not ready yet."
            return
        }
        isLoadingScientificTextRules = true
        defer { isLoadingScientificTextRules = false }
        do {
            scientificTextRules = try await client.fetchScientificTextRules().rules
        } catch {
            scientificTextDictionaryErrorMessage = error.localizedDescription
        }
    }

    func beginNewScientificTextRule(kind: String = "unit") {
        selectedScientificTextRuleID = nil
        scientificTextRuleDraft = ScientificTextRulePayload(kind: kind, input: "", output: "", enabled: true)
        scientificTextRulePreview = nil
        scientificTextDictionaryErrorMessage = nil
    }

    func selectScientificTextRule(id: String?) {
        selectedScientificTextRuleID = id
        guard let id, let rule = scientificTextRules.first(where: { $0.id == id }) else {
            beginNewScientificTextRule()
            return
        }
        scientificTextRuleDraft = ScientificTextRulePayload(
            id: rule.id,
            kind: rule.kind,
            input: rule.input,
            output: rule.output,
            enabled: rule.enabled,
            canonicalInput: rule.canonicalInput
        )
        scientificTextRulePreview = nil
        scientificTextDictionaryErrorMessage = nil
    }

    func previewScientificTextRuleDraft() async {
        guard let client else {
            scientificTextDictionaryErrorMessage = "The sidecar is not ready yet."
            return
        }
        scientificTextDictionaryErrorMessage = nil
        do {
            scientificTextRulePreview = try await client.previewScientificTextRule(scientificTextRuleDraft)
        } catch {
            scientificTextDictionaryErrorMessage = error.localizedDescription
        }
    }

    func saveScientificTextRuleDraft() async {
        guard scientificTextRuleSaveAvailability.isEnabled else {
            return
        }
        guard let client else {
            scientificTextDictionaryErrorMessage = "The sidecar is not ready yet."
            return
        }
        isSavingScientificTextRule = true
        scientificTextDictionaryErrorMessage = nil
        defer { isSavingScientificTextRule = false }
        do {
            let rule: ScientificTextRuleResponse
            if let selectedScientificTextRuleID {
                rule = try await client.updateScientificTextRule(
                    ruleID: selectedScientificTextRuleID,
                    request: scientificTextRuleDraft
                )
            } else {
                rule = try await client.saveScientificTextRule(scientificTextRuleDraft)
            }
            upsertScientificTextRule(rule)
            selectScientificTextRule(id: rule.id)
        } catch {
            scientificTextDictionaryErrorMessage = error.localizedDescription
        }
    }

    func deleteScientificTextRule(id: String) async {
        guard let client else {
            scientificTextDictionaryErrorMessage = "The sidecar is not ready yet."
            return
        }
        do {
            try await client.deleteScientificTextRule(ruleID: id)
            scientificTextRules.removeAll { $0.id == id }
            if selectedScientificTextRuleID == id {
                beginNewScientificTextRule()
            }
        } catch {
            scientificTextDictionaryErrorMessage = error.localizedDescription
        }
    }

    func scientificTextRulePreviewMatchesDraft(_ preview: ScientificTextRulePreviewResponse) -> Bool {
        preview.rule.kind == scientificTextRuleDraft.kind
            && preview.rule.input == scientificTextRuleDraft.input.trimmingCharacters(in: .whitespacesAndNewlines)
            && preview.rule.output == scientificTextRuleDraft.output.trimmingCharacters(in: .whitespacesAndNewlines)
            && preview.rule.enabled == scientificTextRuleDraft.enabled
    }

    private func upsertScientificTextRule(_ rule: ScientificTextRuleResponse) {
        if let index = scientificTextRules.firstIndex(where: { $0.id == rule.id }) {
            scientificTextRules[index] = rule
        } else {
            scientificTextRules.append(rule)
        }
        scientificTextRules.sort {
            if $0.kind != $1.kind {
                return $0.kind < $1.kind
            }
            return $0.input.localizedCaseInsensitiveCompare($1.input) == .orderedAscending
        }
    }
}

extension PlotSession {
    static func migrateLegacyTemplateID(_ templateID: String?) -> String? {
        switch templateID {
        case "grouped_bar_error", "grouped_bar_compare":
            return "bar"
        default:
            return templateID
        }
    }

    func migrateLegacyTemplateID(_ templateID: String?) -> String? {
        Self.migrateLegacyTemplateID(templateID)
    }

    enum DerivedState {
        static func needsInspection(
            selectedFileURL: URL?,
            inspectedInputPath: String?,
            inspectedSheet: SheetValue?,
            selectedSheet: SheetValue,
            inspectionResponse: InspectFileResponse?
        ) -> Bool {
            guard let selectedFileURL else {
                return false
            }
            guard let inspectedInputPath, let inspectedSheet else {
                return true
            }
            return inspectedInputPath != selectedFileURL.path || inspectedSheet != selectedSheet || inspectionResponse == nil
        }

        static func liveStatusSymbol(
            hasError: Bool,
            isInspecting: Bool,
            isPreviewing: Bool,
            previewResponse: RenderPreviewResponse?
        ) -> String {
            if hasError {
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
    }
}
