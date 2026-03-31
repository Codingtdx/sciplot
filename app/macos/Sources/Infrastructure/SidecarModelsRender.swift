import Foundation

struct RenderOptionsPayload: Codable, Equatable, Sendable {
    var size: String?
    var xscale: String?
    var yscale: String?
    var reverseX: Bool
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
        baseline: String? = nil,
        showColorbar: Bool? = nil,
        stylePreset: String = "journal_calm",
        palettePreset: String = "aqua_graphite",
        useSidecar: Bool? = nil,
        visualThemeID: String? = nil
    ) {
        self.size = size
        self.xscale = xscale
        self.yscale = yscale
        self.reverseX = reverseX
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
        case baseline
        case showColorbar
        case stylePreset
        case palettePreset
        case useSidecar
        case visualThemeID = "visualThemeId"
    }
}

struct FileRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
}

struct RenderRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let template: String
    let options: RenderOptionsPayload
}

struct ExportRenderRequest: Codable, Equatable, Sendable {
    let inputPath: String
    let sheet: SheetValue
    let template: String
    let options: RenderOptionsPayload
    let outputDir: String?
}

struct RecommendationResponse: Codable, Equatable, Sendable {
    let template: String
    let reason: String
    let size: String?
    let xscale: String?
    let yscale: String?
    let reverseX: Bool?
    let baseline: String?
    let showColorbar: Bool?
    let stylePreset: String?
    let palettePreset: String?
    let useSidecar: Bool?
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
    let recommendation: RecommendationResponse
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
    let templateIDs: [String]
    let sizeIDs: [String]
    let palettePresetIDs: [String]
    let visualThemes: [VisualThemeResponse]
}

struct ContractTemplateResponse: Codable, Equatable, Sendable {
    let label: String
    let description: String
    let category: String
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
