import Foundation

struct RenderOptionsPayload: Codable, Equatable, Sendable {
    var size: String?
    var xscale: String?
    var yscale: String?
    var reverseX: Bool
    var xMin: Double?
    var xMax: Double?
    var yMin: Double?
    var yMax: Double?
    var xTickDensity: String?
    var yTickDensity: String?
    var xTickEdgeLabels: String?
    var yTickEdgeLabels: String?
    var seriesOrder: [String]?
    var xLabelOverride: String?
    var yLabelOverride: String?
    var baseline: String?
    var showColorbar: Bool?
    var stylePreset: String
    var palettePreset: String
    var useSidecar: Bool?
    var visualThemeID: String?

    init(
        size: String? = nil,
        xscale: String? = nil,
        yscale: String? = nil,
        reverseX: Bool = false,
        xMin: Double? = nil,
        xMax: Double? = nil,
        yMin: Double? = nil,
        yMax: Double? = nil,
        xTickDensity: String? = nil,
        yTickDensity: String? = nil,
        xTickEdgeLabels: String? = nil,
        yTickEdgeLabels: String? = nil,
        seriesOrder: [String]? = nil,
        xLabelOverride: String? = nil,
        yLabelOverride: String? = nil,
        baseline: String? = nil,
        showColorbar: Bool? = nil,
        stylePreset: String = "nature",
        palettePreset: String = "colorblind_safe",
        useSidecar: Bool? = nil,
        visualThemeID: String? = nil
    ) {
        self.size = size
        self.xscale = xscale
        self.yscale = yscale
        self.reverseX = reverseX
        self.xMin = xMin
        self.xMax = xMax
        self.yMin = yMin
        self.yMax = yMax
        self.xTickDensity = xTickDensity
        self.yTickDensity = yTickDensity
        self.xTickEdgeLabels = xTickEdgeLabels
        self.yTickEdgeLabels = yTickEdgeLabels
        self.seriesOrder = seriesOrder
        self.xLabelOverride = xLabelOverride
        self.yLabelOverride = yLabelOverride
        self.baseline = baseline
        self.showColorbar = showColorbar
        self.stylePreset = stylePreset
        self.palettePreset = palettePreset
        self.useSidecar = useSidecar
        self.visualThemeID = visualThemeID
    }

    enum CodingKeys: String, CodingKey {
        case size
        case xscale
        case yscale
        case reverseX
        case xMin
        case xMax
        case yMin
        case yMax
        case xTickDensity
        case yTickDensity
        case xTickEdgeLabels
        case yTickEdgeLabels
        case seriesOrder
        case xLabelOverride
        case yLabelOverride
        case baseline
        case showColorbar
        case stylePreset
        case palettePreset
        case useSidecar
        case visualThemeID = "visualThemeId"
    }
}

struct FitOptionsPayload: Codable, Equatable, Sendable {
    var enabled: Bool
    var modelID: String

    init(enabled: Bool = false, modelID: String = "linear") {
        self.enabled = enabled
        self.modelID = modelID
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case modelID = "modelId"
    }
}

struct FileRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
}

struct SourceTablePreviewRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let offset: Int
    let limit: Int
}

struct SourceTablePreviewResponse: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let offset: Int
    let limit: Int
    let totalRows: Int
    let totalCols: Int
    let columnHeaders: [String]
    let rows: [[JSONValue]]
    let candidateRoles: PlotCandidateRolesResponse
    let detectedXLabel: String?
    let detectedYLabel: String?
}

struct FitAnalysisRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let modelID: String
    let seriesID: String?
    let offset: Int
    let limit: Int

    init(
        inputPath: String,
        sheet: SheetValue,
        modelID: String = "linear",
        seriesID: String? = nil,
        offset: Int = 0,
        limit: Int = 50
    ) {
        self.inputPath = inputPath
        self.sheet = sheet
        self.modelID = modelID
        self.seriesID = seriesID
        self.offset = offset
        self.limit = limit
    }

    enum CodingKeys: String, CodingKey {
        case inputPath
        case sheet
        case modelID = "modelId"
        case seriesID = "seriesId"
        case offset
        case limit
    }
}

struct FitDerivedRowResponse: Codable, Equatable, Sendable, Identifiable {
    let rowIndex: Int
    let x: Double
    let y: Double
    let yFit: Double
    let residual: Double

    var id: Int { rowIndex }
}

struct FitSeriesSummaryResponse: Codable, Equatable, Sendable, Identifiable {
    let seriesID: String
    let seriesLabel: String
    let equationDisplay: String
    let rSquared: Double
    let rmse: Double
    let pointCount: Int
    let slope: Double?
    let intercept: Double?
    let warnings: [String]

    var id: String { seriesID }

    enum CodingKeys: String, CodingKey {
        case seriesID = "seriesId"
        case seriesLabel
        case equationDisplay
        case rSquared
        case rmse
        case pointCount
        case slope
        case intercept
        case warnings
    }
}

struct FitAnalysisResponse: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let modelID: String
    let xLabel: String?
    let yLabel: String?
    let selectedSeriesID: String?
    let equationDisplay: String
    let slope: Double?
    let intercept: Double?
    let rSquared: Double
    let rmse: Double
    let pointCount: Int
    let seriesSummaries: [FitSeriesSummaryResponse]
    let warnings: [String]
    let totalRows: Int
    let offset: Int
    let limit: Int
    let rows: [FitDerivedRowResponse]

    enum CodingKeys: String, CodingKey {
        case inputPath
        case sheet
        case modelID = "modelId"
        case xLabel
        case yLabel
        case selectedSeriesID = "selectedSeriesId"
        case equationDisplay
        case slope
        case intercept
        case rSquared
        case rmse
        case pointCount
        case seriesSummaries
        case warnings
        case totalRows
        case offset
        case limit
        case rows
    }
}

struct CodeConsoleContextRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let template: String?
    let options: RenderOptionsPayload
    let sourceKind: String?
    let sourceLabel: String?

    init(
        inputPath: String,
        sheet: SheetValue,
        template: String? = nil,
        options: RenderOptionsPayload = RenderOptionsPayload(),
        sourceKind: String? = nil,
        sourceLabel: String? = nil
    ) {
        self.inputPath = inputPath
        self.sheet = sheet
        self.template = template
        self.options = options
        self.sourceKind = sourceKind
        self.sourceLabel = sourceLabel
    }
}

struct CodeConsoleContextResponse: Codable, Equatable, Sendable {
    let contextID: String
    let inputPath: String
    let sheet: SheetValue
    let sheetNames: [String]
    let inspection: InputInspectionResponse
    let dataset: PlotDatasetPreviewResponse?
    let template: String
    let options: RenderOptionsPayload
    let promptText: String
    let starterCode: String
    let sourceKind: String?
    let sourceLabel: String?
}

struct CodeConsoleRunRequest: Codable, Equatable, Sendable {
    let contextID: String?
    let context: CodeConsoleContextRequest?
    let code: String
    let timeoutSeconds: Int

    init(
        contextID: String? = nil,
        context: CodeConsoleContextRequest? = nil,
        code: String,
        timeoutSeconds: Int
    ) {
        self.contextID = contextID
        self.context = context
        self.code = code
        self.timeoutSeconds = timeoutSeconds
    }
}

struct CodeConsoleGeneratedFileResponse: Codable, Equatable, Sendable, Identifiable {
    let path: String
    let name: String
    let fileType: String
    let sizeBytes: Int

    var id: String { path }
}

struct CodeConsoleRunResponse: Codable, Equatable, Sendable {
    let status: String
    let exitCode: Int?
    let durationSeconds: Double
    let stdout: String
    let stderr: String
    let runDir: String
    let outputDir: String
    let scriptPath: String
    let promptPath: String
    let contextPath: String
    let stdoutPath: String
    let stderrPath: String
    let generatedFiles: [CodeConsoleGeneratedFileResponse]
}

struct RenderRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let template: String
    let options: RenderOptionsPayload
    let fitOptions: FitOptionsPayload

    init(
        inputPath: String,
        sheet: SheetValue,
        template: String,
        options: RenderOptionsPayload,
        fitOptions: FitOptionsPayload = FitOptionsPayload()
    ) {
        self.inputPath = inputPath
        self.sheet = sheet
        self.template = template
        self.options = options
        self.fitOptions = fitOptions
    }
}

struct ExportRenderRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let template: String
    let options: RenderOptionsPayload
    let fitOptions: FitOptionsPayload
    let outputDir: String?

    init(
        inputPath: String,
        sheet: SheetValue,
        template: String,
        options: RenderOptionsPayload,
        fitOptions: FitOptionsPayload = FitOptionsPayload(),
        outputDir: String? = nil
    ) {
        self.inputPath = inputPath
        self.sheet = sheet
        self.template = template
        self.options = options
        self.fitOptions = fitOptions
        self.outputDir = outputDir
    }
}

struct PlotProjectSourceProvenancePayload: Codable, Equatable, Sendable {
    let originalInputPath: String?
    let savedInputMtimeNs: Int?
    let savedAt: String?
}

struct PlotProjectPayload: Codable, Equatable, Sendable {
    let sessionKind: String
    let sourceFilename: String
    let sourceMediaType: String?
    let embeddedSourceRelpath: String
    let sourceSHA256: String
    let sheet: SheetValue
    let selectedTemplateID: String
    let renderOptions: RenderOptionsPayload
    let projectDisplayName: String?
    let sourceProvenance: PlotProjectSourceProvenancePayload

    enum CodingKeys: String, CodingKey {
        case sessionKind
        case sourceFilename
        case sourceMediaType
        case embeddedSourceRelpath
        case sourceSHA256
        case sheet
        case selectedTemplateID
        case renderOptions
        case projectDisplayName
        case sourceProvenance
    }
}

struct DataStudioProjectWorkbookPayload: Codable, Equatable, Sendable, Identifiable {
    let workbookFilename: String
    let embeddedWorkbookRelpath: String
    let workbookSHA256: String
    let originalWorkbookPath: String?
    let savedWorkbookMtimeNs: Int?

    var id: String { embeddedWorkbookRelpath }

    enum CodingKeys: String, CodingKey {
        case workbookFilename
        case embeddedWorkbookRelpath
        case workbookSHA256
        case originalWorkbookPath
        case savedWorkbookMtimeNs
    }
}

struct DataStudioProjectPayload: Codable, Equatable, Sendable {
    let sessionKind: String
    let version: Int
    let selectedTemplateID: String?
    let workbookPaths: [String]
    let selectedWorkbookID: String?
    let primaryWorkbookID: String?
    let selectedRecipeID: String?
    let comparisonRecipeIDs: [String]
    let selectedFigureFamilyID: String?
    let selectedFigureTemplateID: String?
    let groupStates: [DataStudioGroupStatePayload]
    let specimenStates: [DataStudioSpecimenStatePayload]
    let figurePreferences: [DataStudioFigurePreferencePayload]
    let importedPaths: [String]
    let templateDraftPath: String?
    let embeddedWorkbooks: [DataStudioProjectWorkbookPayload]
    let projectDisplayName: String?
    let sourceProvenance: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case sessionKind
        case version
        case selectedTemplateID
        case workbookPaths
        case selectedWorkbookID
        case primaryWorkbookID
        case selectedRecipeID
        case comparisonRecipeIDs
        case selectedFigureFamilyID
        case selectedFigureTemplateID
        case groupStates
        case specimenStates
        case figurePreferences
        case importedPaths
        case templateDraftPath
        case embeddedWorkbooks
        case projectDisplayName
        case sourceProvenance
    }
}

struct ProjectBundlePayload: Codable, Equatable, Sendable {
    let version: Int
    let selectedWorkbench: String
    let plot: PlotProjectPayload?
    let dataStudio: DataStudioProjectPayload?
    let composer: JSONValue?
    let codeConsole: JSONValue?
    let artifacts: [String: JSONValue]
}

struct SaveProjectRequest: Codable, Equatable, Sendable {
    let projectPath: String
    let sourcePath: String?
    let payload: ProjectBundlePayload
}

struct SaveProjectResponse: Codable, Equatable, Sendable {
    let projectPath: String
    let payload: ProjectBundlePayload
}

struct OpenProjectRequest: Codable, Equatable, Sendable {
    let projectPath: String
}

struct OpenProjectResponse: Codable, Equatable, Sendable {
    let projectPath: String
    let restoredSourcePath: String?
    let restoredWorkbookPaths: [String]
    let payload: ProjectBundlePayload
}

struct TemplateRecommendationResponse: Codable, Equatable, Sendable, Identifiable {
    let templateID: String
    let canonicalID: String
    let role: String
    let lifecyclePolicy: String
    let implementationID: String
    let score: Double
    let rank: Int?
    let reason: String
    let suitabilityHint: String
    let scoreGapToTop: Double
    let whyHardMatch: [String]
    let whySoftPrior: [String]
    let inferredMapping: [String: String]
    let optionalEnhancements: [String]
    let previewConfigSummary: [String: JSONValue]

    var id: String { templateID }

    enum CodingKeys: String, CodingKey {
        case templateID = "templateId"
        case canonicalID = "canonicalId"
        case role
        case lifecyclePolicy
        case implementationID = "implementationId"
        case score
        case rank
        case reason
        case suitabilityHint
        case scoreGapToTop
        case whyHardMatch
        case whySoftPrior
        case inferredMapping
        case optionalEnhancements
        case previewConfigSummary
    }
}

struct InputInspectionResponse: Codable, Equatable, Sendable {
    let model: String
    let modelLabel: String
    let recommendations: [TemplateRecommendationResponse]
    let primaryRecommendation: [TemplateRecommendationResponse]
    let alternativeRecommendations: [TemplateRecommendationResponse]
    let advancedTemplates: [TemplateRecommendationResponse]
    let recommendationConfidence: Double
    let recommendationSummary: String
    let warnings: [String]
    let signals: [String]
}

struct PlotColumnProfileResponse: Codable, Equatable, Sendable {
    let name: String
    let headerPreview: [String?]
    let inferredType: String
    let nonEmptyCount: Int
    let missingCount: Int
    let minValue: Double?
    let maxValue: Double?
}

struct PlotCandidateRolesResponse: Codable, Equatable, Sendable {
    let x: [String]
    let y: [String]
    let z: [String]
    let group: [String]
    let sample: [String]
    let value: [String]
    let metric: [String]
    let label: [String]
    let series: [String]
}

struct PlotDatasetPreviewResponse: Codable, Equatable, Sendable {
    let datasetID: String
    let sourcePath: String?
    let sheet: SheetValue?
    let model: String
    let rawRows: Int
    let rawCols: Int
    let columnProfiles: [PlotColumnProfileResponse]
    let candidateRoles: PlotCandidateRolesResponse
    let dataShapes: [String]
    let semanticSignals: [String]
    let qualityFlags: [String]
    let sampleRows: [[JSONValue]]

    enum CodingKeys: String, CodingKey {
        case datasetID = "datasetId"
        case sourcePath
        case sheet
        case model
        case rawRows
        case rawCols
        case columnProfiles
        case candidateRoles
        case dataShapes
        case semanticSignals
        case qualityFlags
        case sampleRows
    }
}

struct InspectFileResponse: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let sheetNames: [String]
    let inspection: InputInspectionResponse
    let dataset: PlotDatasetPreviewResponse?
}

struct PreflightResultResponse: Codable, Equatable, Sendable {
    let template: String
    let requestedTemplateID: String
    let canonicalID: String
    let role: String
    let lifecyclePolicy: String
    let implementationID: String
    let warnings: [String]
    let errors: [String]
    let outputFilenames: [String]
    let submissionReport: SubmissionReportResponse?

    enum CodingKeys: String, CodingKey {
        case template
        case requestedTemplateID = "requestedTemplateId"
        case canonicalID = "canonicalId"
        case role
        case lifecyclePolicy
        case implementationID = "implementationId"
        case warnings
        case errors
        case outputFilenames
        case submissionReport
    }
}

struct PreflightRenderResponse: Codable, Equatable, Sendable {
    let inputPath: String
    let template: String
    let requestedTemplateID: String
    let canonicalID: String
    let role: String
    let lifecyclePolicy: String
    let implementationID: String
    let sheet: SheetValue
    let options: RenderOptionsPayload
    let preflight: PreflightResultResponse

    enum CodingKeys: String, CodingKey {
        case inputPath
        case template
        case requestedTemplateID = "requestedTemplateId"
        case canonicalID = "canonicalId"
        case role
        case lifecyclePolicy
        case implementationID = "implementationId"
        case sheet
        case options
        case preflight
    }
}

struct RenderPreviewResponse: Codable, Equatable, Sendable {
    let template: String
    let requestedTemplateID: String
    let canonicalID: String
    let role: String
    let lifecyclePolicy: String
    let implementationID: String
    let sheet: SheetValue
    let previews: [PreviewItemResponse]
    let submissionReport: SubmissionReportResponse?

    enum CodingKeys: String, CodingKey {
        case template
        case requestedTemplateID = "requestedTemplateId"
        case canonicalID = "canonicalId"
        case role
        case lifecyclePolicy
        case implementationID = "implementationId"
        case sheet
        case previews
        case submissionReport
    }
}

struct ExportRenderResponse: Codable, Equatable, Sendable {
    let requestedTemplateID: String
    let canonicalID: String
    let role: String
    let lifecyclePolicy: String
    let implementationID: String
    let outputs: [String]
    let outputDir: String
    let previewOutputs: [String]
    let artifactPaths: [String]
    let manifestPath: String?
    let submissionReport: SubmissionReportResponse?

    enum CodingKeys: String, CodingKey {
        case requestedTemplateID = "requestedTemplateId"
        case canonicalID = "canonicalId"
        case role
        case lifecyclePolicy
        case implementationID = "implementationId"
        case outputs
        case outputDir
        case previewOutputs
        case artifactPaths
        case manifestPath
        case submissionReport
    }
}

struct MetaDefaultsResponse: Codable, Equatable, Sendable {
    let stylePreset: String
    let palettePreset: String
}

struct MetaSizeResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let widthMm: Double
    let heightMm: Double
}

struct MetaStyleResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let `public`: Bool
    let description: String
    let hardConstraints: Bool
    let presetNote: String
}

struct MetaPaletteResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let `public`: Bool
    let description: String
    let swatches: [String]
}

struct MetaTemplateSummary: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let description: String
    let category: String
    let presentationKind: String
    let defaultSize: String
    let allowedSizes: [String]
    let editableOptions: [String]
    let defaultOptions: [String: JSONValue]
    let availableStyles: [String]
    let availablePalettes: [String]
    let canonicalID: String
    let role: String
    let lifecyclePolicy: String
    let implementationID: String

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case description
        case category
        case presentationKind
        case defaultSize
        case allowedSizes
        case editableOptions
        case defaultOptions
        case availableStyles
        case availablePalettes
        case canonicalID = "canonicalId"
        case role
        case lifecyclePolicy
        case implementationID = "implementationId"
    }
}

struct VisualThemeResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let description: String
}

struct SidecarMetaResponse: Codable, Equatable, Sendable {
    let version: Int
    let defaults: MetaDefaultsResponse
    let sizes: [MetaSizeResponse]
    let styles: [MetaStyleResponse]
    let palettes: [MetaPaletteResponse]
    let templates: [MetaTemplateSummary]
    let templateIds: [String]
    let sizeIds: [String]
    let palettePresetIds: [String]
    let visualThemes: [VisualThemeResponse]
}

struct ContractTemplateResponse: Codable, Equatable, Sendable {
    let label: String
    let description: String
    let category: String
    let presentationKind: String
    let defaultSize: String
    let allowedSizes: [String]
    let editableOptions: [String]
    let defaultOptions: [String: JSONValue]
    let availableStyles: [String]
    let availablePalettes: [String]
    let hardRules: [String]
    let softRules: [String]
}

struct ContractSizePresetResponse: Codable, Equatable, Sendable {
    let label: String
    let widthMm: Double
    let heightMm: Double
}

struct PlotContractResponse: Codable, Equatable, Sendable {
    let version: Int
    let defaults: MetaDefaultsResponse
    let sizePresets: [String: ContractSizePresetResponse]
    let styles: [String: JSONValue]
    let palettes: [String: JSONValue]
    let templates: [String: ContractTemplateResponse]
}
