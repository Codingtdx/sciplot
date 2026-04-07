import Foundation

struct DataStudioRangeResponse: Codable, Equatable, Sendable {
    let sheetName: String
    let startRow: Int
    let endRow: Int
    let startCol: Int
    let endCol: Int
}

struct DataStudioSheetBlockResponse: Codable, Equatable, Sendable {
    let id: String
    let sheetName: String
    let label: String
    let rowCount: Int
    let colCount: Int
    let range: DataStudioRangeResponse
    let headerRowIndex: Int?
    let unitRowIndex: Int?
    let dataStartRowIndex: Int?
    let sampleRows: [[JSONValue]]
}

struct DataStudioFieldCandidateResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: String
    let label: String
    let confidence: Double
    let rationale: String
    let sheetName: String
    let blockID: String?
    let range: DataStudioRangeResponse?
    let sampleValues: [String]
    let unitHint: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case label
        case confidence
        case rationale
        case sheetName
        case blockID = "blockId"
        case range
        case sampleValues
        case unitHint
    }
}

struct DataStudioPreviewRangeResponse: Codable, Equatable, Sendable, Identifiable {
    let sheetName: String
    let blockID: String?
    let startRow: Int
    let endRow: Int
    let startCol: Int
    let endCol: Int
    let role: String

    var id: String {
        [sheetName, blockID ?? "-", "\(startRow)", "\(endRow)", "\(startCol)", "\(endCol)", role].joined(separator: ":")
    }

    enum CodingKeys: String, CodingKey {
        case sheetName
        case blockID = "blockId"
        case startRow
        case endRow
        case startCol
        case endCol
        case role
    }
}

struct DataStudioBindingSuggestionResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let summary: String
    let sheetName: String
    let blockID: String?
    let candidateIDs: [String]
    let previewRanges: [DataStudioPreviewRangeResponse]
    let defaultSelected: Bool
    let rationale: String
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case summary
        case sheetName
        case blockID = "blockId"
        case candidateIDs = "candidateIds"
        case previewRanges
        case defaultSelected
        case rationale
        case confidence
    }
}

struct DataStudioRawSheetPreviewResponse: Codable, Equatable, Sendable {
    let sheetName: String
    let rowCount: Int
    let colCount: Int
    let sampleRows: [[JSONValue]]
    let blocks: [DataStudioSheetBlockResponse]
}

struct DataStudioRawFilePreviewResponse: Codable, Equatable, Sendable {
    let sourcePath: String
    let fileType: String
    let encoding: String?
    let delimiter: String?
    let sheetNames: [String]
    let sheets: [DataStudioRawSheetPreviewResponse]
    let fieldCandidates: [DataStudioFieldCandidateResponse]
    let bindingSuggestions: [DataStudioBindingSuggestionResponse]
    let recommendedTemplateIDs: [String]
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case sourcePath
        case fileType
        case encoding
        case delimiter
        case sheetNames
        case sheets
        case fieldCandidates
        case bindingSuggestions
        case recommendedTemplateIDs = "recommendedTemplateIds"
        case warnings
    }
}

struct DataStudioTemplateConditionResponse: Codable, Equatable, Sendable {
    let sheetNameContains: [String]
    let textContains: [String]
    let fieldKinds: [String]
    let minimumScore: Double
}

struct DataStudioTemplateFieldBindingResponse: Codable, Equatable, Sendable {
    let id: String
    let role: String
    let label: String
    let sheetName: String?
    let blockID: String?
    let columnName: String?
    let columnIndex: Int?
    let rowLabelContains: String?
    let cellValueContains: [String]
    let unitHint: String?
    let optional: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case label
        case sheetName
        case blockID = "blockId"
        case columnName
        case columnIndex
        case rowLabelContains
        case cellValueContains
        case unitHint
        case optional
    }
}

struct DataStudioTemplateResponse: Codable, Equatable, Sendable, Identifiable {
    let version: Int
    let id: String
    let label: String
    let family: String
    let builtin: Bool
    let description: String
    let fileTypes: [String]
    let parseStrategy: String
    let matchConditions: [DataStudioTemplateConditionResponse]
    let fieldBindings: [DataStudioTemplateFieldBindingResponse]
    let workbookMetricIDs: [String]
    let defaultGroupNameStrategy: String
    let preferredSheetName: String
    let metadata: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case version
        case id
        case label
        case family
        case builtin
        case description
        case fileTypes
        case parseStrategy
        case matchConditions
        case fieldBindings
        case workbookMetricIDs = "workbookMetricIds"
        case defaultGroupNameStrategy
        case preferredSheetName
        case metadata
    }
}

struct DataStudioTemplateListResponse: Codable, Equatable, Sendable {
    let templates: [DataStudioTemplateResponse]
}

struct DataStudioTemplateMatchResponse: Codable, Equatable, Sendable, Identifiable {
    let templateID: String
    let label: String
    let family: String
    let confidence: Double
    let reasons: [String]
    let warnings: [String]
    let matchedSheetNames: [String]
    let autoSelected: Bool

    var id: String { templateID }

    enum CodingKeys: String, CodingKey {
        case templateID = "templateId"
        case label
        case family
        case confidence
        case reasons
        case warnings
        case matchedSheetNames
        case autoSelected
    }
}

struct DataStudioMetricSummaryResponse: Codable, Equatable, Sendable {
    let id: String
    let label: String
    let unit: String
    let mean: Double?
    let std: Double?
}

struct DataStudioWorkbookSampleResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let sourcePath: String
    let filename: String
    let parsed: Bool
    let warnings: [String]
    let exclusions: [String]
    let metrics: [String: Double?]
}

struct DataStudioCurvePointResponse: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
}

struct DataStudioSpecimenStatePayload: Codable, Equatable, Sendable, Identifiable {
    let workbookPath: String
    let specimenId: String
    let included: Bool

    var id: String { "\(workbookPath)::\(specimenId)" }
}

struct DataStudioSpecimenPreviewResponse: Codable, Equatable, Sendable, Identifiable {
    let specimenId: String
    let label: String
    let filename: String
    let sourcePath: String?
    let included: Bool
    let metrics: [String: Double?]
    let warnings: [String]
    let exclusions: [String]
    let miniCurvePoints: [DataStudioCurvePointResponse]
    let triadComplete: Bool
    let suggestedExclusion: Bool

    var id: String { specimenId }
}

struct DataStudioWorkbookResponse: Codable, Equatable, Sendable, Identifiable {
    let workbookID: String
    let workbookPath: String
    let label: String
    let templateMatch: DataStudioTemplateMatchResponse
    let sourceFiles: [String]
    let sheetNames: [String]
    let preferredSheet: String
    let parsedSampleCount: Int
    let failedSampleCount: Int
    let representativeFilename: String
    let metrics: [DataStudioMetricSummaryResponse]
    let warnings: [String]
    let exclusions: [String]
    let samples: [DataStudioWorkbookSampleResponse]

    var id: String { workbookID }

    enum CodingKeys: String, CodingKey {
        case workbookID = "workbookId"
        case workbookPath
        case label
        case templateMatch
        case sourceFiles
        case sheetNames
        case preferredSheet
        case parsedSampleCount
        case failedSampleCount
        case representativeFilename
        case metrics
        case warnings
        case exclusions
        case samples
    }
}

struct DataStudioWorkbookPreviewResponse: Codable, Equatable, Sendable {
    let workbookPath: String
    let label: String
    let supported: Bool
    let unsupportedReason: String
    let totalSpecimenCount: Int
    let includedSpecimenCount: Int
    let excludedSpecimenCount: Int
    let representativeSpecimenId: String?
    let representativeFilename: String?
    let metrics: [DataStudioMetricSummaryResponse]
    let specimens: [DataStudioSpecimenPreviewResponse]
    let warnings: [String]
    let suggestedExclusionIds: [String]
    let suggestionSupported: Bool
    let suggestionSupportReason: String
}

struct DataStudioImportWorkbookResponse: Codable, Equatable, Sendable {
    let workbooks: [DataStudioWorkbookResponse]
}

struct DataStudioGroupStatePayload: Codable, Equatable, Sendable, Identifiable {
    let workbookPath: String
    let displayName: String
    let includeInCompare: Bool
    let sortOrder: Int

    var id: String { workbookPath }
}

struct DataStudioComparisonRecipeResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let category: String
    let templateID: String
    let sheetName: String
    let metricID: String?
    let enabledByDefault: Bool
    let supported: Bool
    let supportReason: String

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case category
        case templateID = "templateId"
        case sheetName
        case metricID = "metricId"
        case enabledByDefault
        case supported
        case supportReason
    }
}

struct DataStudioComparisonSetResponse: Codable, Equatable, Sendable {
    let id: String
    let label: String
    let workbookPaths: [String]
    let workbookLabels: [String]
    let comparisonWorkbookPath: String
    let recipes: [DataStudioComparisonRecipeResponse]
}

struct DataStudioFigurePreferencePayload: Codable, Equatable, Sendable, Identifiable {
    let familyID: String
    let selectedTemplateID: String?
    let optionsByTemplate: [String: RenderOptionsPayload]

    var id: String { familyID }

    enum CodingKeys: String, CodingKey {
        case familyID = "familyId"
        case selectedTemplateID = "selectedTemplateId"
        case optionsByTemplate
    }
}

struct DataStudioFigureOutputResponse: Codable, Equatable, Sendable, Identifiable {
    let path: String
    let label: String
    let category: String
    let templateID: String
    let sheetName: String
    let metricID: String?
    let recipeID: String?

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case path
        case label
        case category
        case templateID = "templateId"
        case sheetName
        case metricID = "metricId"
        case recipeID = "recipeId"
    }
}

struct DataStudioSourcePreviewResponse: Codable, Equatable, Sendable {
    let preview: DataStudioRawFilePreviewResponse
    let matches: [DataStudioTemplateMatchResponse]
}

struct DataStudioComparisonPreviewResponse: Codable, Equatable, Sendable {
    let comparisonSet: DataStudioComparisonSetResponse
    let recipe: DataStudioComparisonRecipeResponse
    let preview: PreviewItemResponse
}

struct DataStudioComparisonContextResponse: Codable, Equatable, Sendable {
    let comparisonSet: DataStudioComparisonSetResponse
    let cacheKey: String?
    let materializedAt: String?
}

struct DataStudioComparisonExportResponse: Codable, Equatable, Sendable {
    let comparisonSet: DataStudioComparisonSetResponse
    let figureOutputs: [DataStudioFigureOutputResponse]
}

struct DataStudioSessionResponse: Codable, Equatable, Sendable {
    let version: Int
    let selectedTemplateID: String?
    let selectedWorkbookID: String?
    let primaryWorkbookID: String?
    let selectedRecipeID: String?
    let workbookPaths: [String]
    let comparisonRecipeIDs: [String]
    let selectedFigureFamilyID: String?
    let selectedFigureTemplateID: String?
    let groupStates: [DataStudioGroupStatePayload]
    let specimenStates: [DataStudioSpecimenStatePayload]
    let figurePreferences: [DataStudioFigurePreferencePayload]
    let importedPaths: [String]
    let templateDraftPath: String?

    init(
        version: Int,
        selectedTemplateID: String?,
        selectedWorkbookID: String?,
        primaryWorkbookID: String?,
        selectedRecipeID: String?,
        workbookPaths: [String],
        comparisonRecipeIDs: [String],
        selectedFigureFamilyID: String?,
        selectedFigureTemplateID: String?,
        groupStates: [DataStudioGroupStatePayload],
        specimenStates: [DataStudioSpecimenStatePayload] = [],
        figurePreferences: [DataStudioFigurePreferencePayload],
        importedPaths: [String],
        templateDraftPath: String?
    ) {
        self.version = version
        self.selectedTemplateID = selectedTemplateID
        self.selectedWorkbookID = selectedWorkbookID
        self.primaryWorkbookID = primaryWorkbookID
        self.selectedRecipeID = selectedRecipeID
        self.workbookPaths = workbookPaths
        self.comparisonRecipeIDs = comparisonRecipeIDs
        self.selectedFigureFamilyID = selectedFigureFamilyID
        self.selectedFigureTemplateID = selectedFigureTemplateID
        self.groupStates = groupStates
        self.specimenStates = specimenStates
        self.figurePreferences = figurePreferences
        self.importedPaths = importedPaths
        self.templateDraftPath = templateDraftPath
    }

    enum CodingKeys: String, CodingKey {
        case version
        case selectedTemplateID = "selectedTemplateId"
        case selectedWorkbookID = "selectedWorkbookId"
        case primaryWorkbookID = "primaryWorkbookId"
        case selectedRecipeID = "selectedRecipeId"
        case workbookPaths
        case comparisonRecipeIDs = "comparisonRecipeIds"
        case selectedFigureFamilyID = "selectedFigureFamilyId"
        case selectedFigureTemplateID = "selectedFigureTemplateId"
        case groupStates
        case specimenStates
        case figurePreferences
        case importedPaths
        case templateDraftPath
    }
}

struct DataStudioSourcePreviewRequest: Codable, Equatable, Sendable {
    let inputPath: String
}

struct DataStudioCreateTemplateRequest: Codable, Equatable, Sendable {
    let sourcePath: String
    let label: String
    let acceptedCandidateIDs: [String]
    let templateID: String?
    let description: String

    enum CodingKeys: String, CodingKey {
        case sourcePath
        case label
        case acceptedCandidateIDs = "acceptedCandidateIds"
        case templateID = "templateId"
        case description
    }
}

struct DataStudioUpdateTemplateRequest: Codable, Equatable, Sendable {
    let newID: String?
    let newLabel: String?

    enum CodingKeys: String, CodingKey {
        case newID = "newId"
        case newLabel
    }
}

struct DataStudioBuildWorkbookRequest: Codable, Equatable, Sendable {
    let filePaths: [String]
    let outputPath: String
    let templateID: String
    let groupName: String?

    enum CodingKeys: String, CodingKey {
        case filePaths
        case outputPath
        case templateID = "templateId"
        case groupName
    }
}

struct DataStudioImportWorkbookRequest: Codable, Equatable, Sendable {
    let workbookPath: String
}

struct DataStudioWorkbookPreviewRequest: Codable, Equatable, Sendable {
    let workbookPath: String
    let specimenStates: [DataStudioSpecimenStatePayload]

    init(workbookPath: String, specimenStates: [DataStudioSpecimenStatePayload] = []) {
        self.workbookPath = workbookPath
        self.specimenStates = specimenStates
    }
}

struct DataStudioComparisonContextRequest: Codable, Equatable, Sendable {
    let workbookPaths: [String]
    let groupStates: [DataStudioGroupStatePayload]
    let specimenStates: [DataStudioSpecimenStatePayload]

    init(
        workbookPaths: [String],
        groupStates: [DataStudioGroupStatePayload] = [],
        specimenStates: [DataStudioSpecimenStatePayload] = []
    ) {
        self.workbookPaths = workbookPaths
        self.groupStates = groupStates
        self.specimenStates = specimenStates
    }
}

struct DataStudioPreviewComparisonRequest: Codable, Equatable, Sendable {
    let workbookPaths: [String]
    let recipeID: String
    let groupStates: [DataStudioGroupStatePayload]
    let specimenStates: [DataStudioSpecimenStatePayload]

    init(
        workbookPaths: [String],
        recipeID: String,
        groupStates: [DataStudioGroupStatePayload] = [],
        specimenStates: [DataStudioSpecimenStatePayload] = []
    ) {
        self.workbookPaths = workbookPaths
        self.recipeID = recipeID
        self.groupStates = groupStates
        self.specimenStates = specimenStates
    }

    enum CodingKeys: String, CodingKey {
        case workbookPaths
        case recipeID = "recipeId"
        case groupStates
        case specimenStates
    }
}

struct DataStudioExportComparisonRequest: Codable, Equatable, Sendable {
    let workbookPaths: [String]
    let outputDir: String
    let groupStates: [DataStudioGroupStatePayload]
    let specimenStates: [DataStudioSpecimenStatePayload]
    let selectedRecipeIDs: [String]
    let figureOptionsByRecipeID: [String: RenderOptionsPayload]

    init(
        workbookPaths: [String],
        outputDir: String,
        groupStates: [DataStudioGroupStatePayload] = [],
        specimenStates: [DataStudioSpecimenStatePayload] = [],
        selectedRecipeIDs: [String] = [],
        figureOptionsByRecipeID: [String: RenderOptionsPayload] = [:]
    ) {
        self.workbookPaths = workbookPaths
        self.outputDir = outputDir
        self.groupStates = groupStates
        self.specimenStates = specimenStates
        self.selectedRecipeIDs = selectedRecipeIDs
        self.figureOptionsByRecipeID = figureOptionsByRecipeID
    }

    enum CodingKeys: String, CodingKey {
        case workbookPaths
        case outputDir
        case groupStates
        case specimenStates
        case selectedRecipeIDs = "selectedRecipeIds"
        case figureOptionsByRecipeID = "figureOptionsByRecipeId"
    }
}

struct DataStudioSessionNormalizeRequest: Codable, Equatable, Sendable {
    let payload: [String: JSONValue]
}
