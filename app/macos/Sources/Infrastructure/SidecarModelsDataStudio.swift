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

struct DataStudioTemplateSourceFormatResponse: Codable, Equatable, Sendable {
    let encoding: String?
    let delimiter: String?
    let sheetName: String?

    init(encoding: String? = nil, delimiter: String? = nil, sheetName: String? = nil) {
        self.encoding = encoding
        self.delimiter = delimiter
        self.sheetName = sheetName
    }
}

struct DataStudioTemplateSegmentSelectorResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let resultLabel: String?
    let intervalIndex: Int?
    let headerRowIndex: Int?
    let unitRowIndex: Int?
    let dataStartRowIndex: Int?
    let startRow: Int?
    let endRow: Int?

    init(
        id: String,
        label: String,
        resultLabel: String? = nil,
        intervalIndex: Int? = nil,
        headerRowIndex: Int? = nil,
        unitRowIndex: Int? = nil,
        dataStartRowIndex: Int? = nil,
        startRow: Int? = nil,
        endRow: Int? = nil
    ) {
        self.id = id
        self.label = label
        self.resultLabel = resultLabel
        self.intervalIndex = intervalIndex
        self.headerRowIndex = headerRowIndex
        self.unitRowIndex = unitRowIndex
        self.dataStartRowIndex = dataStartRowIndex
        self.startRow = startRow
        self.endRow = endRow
    }
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
    let sampleName: String?
    let optional: Bool

    init(
        id: String,
        role: String,
        label: String,
        sheetName: String? = nil,
        blockID: String? = nil,
        columnName: String? = nil,
        columnIndex: Int? = nil,
        rowLabelContains: String? = nil,
        cellValueContains: [String] = [],
        unitHint: String? = nil,
        sampleName: String? = nil,
        optional: Bool = false
    ) {
        self.id = id
        self.role = role
        self.label = label
        self.sheetName = sheetName
        self.blockID = blockID
        self.columnName = columnName
        self.columnIndex = columnIndex
        self.rowLabelContains = rowLabelContains
        self.cellValueContains = cellValueContains
        self.unitHint = unitHint
        self.sampleName = sampleName
        self.optional = optional
    }

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
        case sampleName
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
    let outputKind: String
    let comparisonEnabled: Bool
    let sourceFormat: DataStudioTemplateSourceFormatResponse
    let segmentPolicy: String
    let segmentSelectors: [DataStudioTemplateSegmentSelectorResponse]
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
        case outputKind
        case comparisonEnabled
        case sourceFormat
        case segmentPolicy
        case segmentSelectors
        case metadata
    }
}

struct DataStudioTemplateListResponse: Codable, Equatable, Sendable {
    let templates: [DataStudioTemplateResponse]
}

struct ImportSelectionPayload: Codable, Equatable, Sendable {
    let filterID: String
    let inputPath: String
    let selectedSheetOrSegment: String?
    let options: [String: JSONValue]
    let profile: ImportFilterProfilePayload?
    let diagnostics: [ImportDiagnosticPayload]

    init(
        filterID: String,
        inputPath: String,
        selectedSheetOrSegment: String? = nil,
        options: [String: JSONValue] = [:],
        profile: ImportFilterProfilePayload? = nil,
        diagnostics: [ImportDiagnosticPayload] = []
    ) {
        self.filterID = filterID
        self.inputPath = inputPath
        self.selectedSheetOrSegment = selectedSheetOrSegment
        self.options = options
        self.profile = profile
        self.diagnostics = diagnostics
    }

    enum CodingKeys: String, CodingKey {
        case filterID = "filterId"
        case inputPath
        case selectedSheetOrSegment
        case options
        case profile
        case diagnostics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filterID = try container.decode(String.self, forKey: .filterID)
        inputPath = try container.decode(String.self, forKey: .inputPath)
        selectedSheetOrSegment = try container.decodeIfPresent(String.self, forKey: .selectedSheetOrSegment)
        options = try container.decodeIfPresent([String: JSONValue].self, forKey: .options) ?? [:]
        profile = try container.decodeIfPresent(ImportFilterProfilePayload.self, forKey: .profile)
        diagnostics = try container.decodeIfPresent([ImportDiagnosticPayload].self, forKey: .diagnostics) ?? []
    }
}

struct TemplateRoleMatchPayload: Codable, Equatable, Sendable {
    let role: String
    let label: String
    let sourceLabel: String?
    let status: String
    let confidence: Double

    init(
        role: String,
        label: String,
        sourceLabel: String? = nil,
        status: String = "matched",
        confidence: Double = 1
    ) {
        self.role = role
        self.label = label
        self.sourceLabel = sourceLabel
        self.status = status
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        label = try container.decode(String.self, forKey: .label)
        sourceLabel = try container.decodeIfPresent(String.self, forKey: .sourceLabel)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "matched"
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 1
    }
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
    let matchedRoles: [TemplateRoleMatchPayload]
    let missingRoles: [String]
    let ambiguousRoles: [String]
    let matchedStructureID: String?
    let diagnostics: [ImportDiagnosticPayload]

    var id: String { templateID }

    init(
        templateID: String,
        label: String,
        family: String,
        confidence: Double,
        reasons: [String] = [],
        warnings: [String] = [],
        matchedSheetNames: [String] = [],
        autoSelected: Bool = false,
        matchedRoles: [TemplateRoleMatchPayload] = [],
        missingRoles: [String] = [],
        ambiguousRoles: [String] = [],
        matchedStructureID: String? = nil,
        diagnostics: [ImportDiagnosticPayload] = []
    ) {
        self.templateID = templateID
        self.label = label
        self.family = family
        self.confidence = confidence
        self.reasons = reasons
        self.warnings = warnings
        self.matchedSheetNames = matchedSheetNames
        self.autoSelected = autoSelected
        self.matchedRoles = matchedRoles
        self.missingRoles = missingRoles
        self.ambiguousRoles = ambiguousRoles
        self.matchedStructureID = matchedStructureID
        self.diagnostics = diagnostics
    }

    enum CodingKeys: String, CodingKey {
        case templateID = "templateId"
        case label
        case family
        case confidence
        case reasons
        case warnings
        case matchedSheetNames
        case autoSelected
        case matchedRoles
        case missingRoles
        case ambiguousRoles
        case matchedStructureID = "matchedStructureId"
        case diagnostics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        templateID = try container.decode(String.self, forKey: .templateID)
        label = try container.decode(String.self, forKey: .label)
        family = try container.decode(String.self, forKey: .family)
        confidence = try container.decode(Double.self, forKey: .confidence)
        reasons = try container.decodeIfPresent([String].self, forKey: .reasons) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        matchedSheetNames = try container.decodeIfPresent([String].self, forKey: .matchedSheetNames) ?? []
        autoSelected = try container.decodeIfPresent(Bool.self, forKey: .autoSelected) ?? false
        matchedRoles = try container.decodeIfPresent([TemplateRoleMatchPayload].self, forKey: .matchedRoles) ?? []
        missingRoles = try container.decodeIfPresent([String].self, forKey: .missingRoles) ?? []
        ambiguousRoles = try container.decodeIfPresent([String].self, forKey: .ambiguousRoles) ?? []
        matchedStructureID = try container.decodeIfPresent(String.self, forKey: .matchedStructureID)
        diagnostics = try container.decodeIfPresent([ImportDiagnosticPayload].self, forKey: .diagnostics) ?? []
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
    let selectedAsRepresentative: Bool

    init(
        workbookPath: String,
        specimenId: String,
        included: Bool,
        selectedAsRepresentative: Bool = false
    ) {
        self.workbookPath = workbookPath
        self.specimenId = specimenId
        self.included = included
        self.selectedAsRepresentative = selectedAsRepresentative
    }

    var id: String { "\(workbookPath)::\(specimenId)" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workbookPath = try container.decode(String.self, forKey: .workbookPath)
        specimenId = try container.decode(String.self, forKey: .specimenId)
        included = try container.decode(Bool.self, forKey: .included)
        selectedAsRepresentative = try container.decodeIfPresent(Bool.self, forKey: .selectedAsRepresentative) ?? false
    }
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
    let compositeSignedScore: Double?
    let distanceFromMeanScore: Double?
    let scoreSide: String
    let autoRuleRole: String
    let eligibleForAutoFilter: Bool

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
    let dataContainers: [DataContainerPayload]

    var id: String { workbookID }

    init(
        workbookID: String,
        workbookPath: String,
        label: String,
        templateMatch: DataStudioTemplateMatchResponse,
        sourceFiles: [String],
        sheetNames: [String],
        preferredSheet: String,
        parsedSampleCount: Int,
        failedSampleCount: Int,
        representativeFilename: String,
        metrics: [DataStudioMetricSummaryResponse] = [],
        warnings: [String] = [],
        exclusions: [String] = [],
        samples: [DataStudioWorkbookSampleResponse] = [],
        dataContainers: [DataContainerPayload] = []
    ) {
        self.workbookID = workbookID
        self.workbookPath = workbookPath
        self.label = label
        self.templateMatch = templateMatch
        self.sourceFiles = sourceFiles
        self.sheetNames = sheetNames
        self.preferredSheet = preferredSheet
        self.parsedSampleCount = parsedSampleCount
        self.failedSampleCount = failedSampleCount
        self.representativeFilename = representativeFilename
        self.metrics = metrics
        self.warnings = warnings
        self.exclusions = exclusions
        self.samples = samples
        self.dataContainers = dataContainers
    }

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
        case dataContainers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workbookID = try container.decode(String.self, forKey: .workbookID)
        workbookPath = try container.decode(String.self, forKey: .workbookPath)
        label = try container.decode(String.self, forKey: .label)
        templateMatch = try container.decode(DataStudioTemplateMatchResponse.self, forKey: .templateMatch)
        sourceFiles = try container.decodeIfPresent([String].self, forKey: .sourceFiles) ?? []
        sheetNames = try container.decodeIfPresent([String].self, forKey: .sheetNames) ?? []
        preferredSheet = try container.decodeIfPresent(String.self, forKey: .preferredSheet) ?? "Representative_Curve"
        parsedSampleCount = try container.decodeIfPresent(Int.self, forKey: .parsedSampleCount) ?? 0
        failedSampleCount = try container.decodeIfPresent(Int.self, forKey: .failedSampleCount) ?? 0
        representativeFilename = try container.decodeIfPresent(String.self, forKey: .representativeFilename) ?? ""
        metrics = try container.decodeIfPresent([DataStudioMetricSummaryResponse].self, forKey: .metrics) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        exclusions = try container.decodeIfPresent([String].self, forKey: .exclusions) ?? []
        samples = try container.decodeIfPresent([DataStudioWorkbookSampleResponse].self, forKey: .samples) ?? []
        dataContainers = try container.decodeIfPresent([DataContainerPayload].self, forKey: .dataContainers) ?? []
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
    let fitOptionsByTemplate: [String: FitOptionsPayload]

    var id: String { familyID }

    enum CodingKeys: String, CodingKey {
        case familyID = "familyId"
        case selectedTemplateID = "selectedTemplateId"
        case optionsByTemplate
        case fitOptionsByTemplate
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

struct DataStudioFilteredWorkbookResponse: Codable, Equatable, Sendable, Identifiable {
    let path: String
    let label: String
    let sourceWorkbookPath: String
    let representativeFilename: String

    var id: String { path }
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
    let filteredWorkbooks: [DataStudioFilteredWorkbookResponse]
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

struct DataStudioCreateTemplateRequest: Codable, Equatable, Sendable {
    let label: String
    let templateID: String?
    let description: String
    let outputKind: String
    let comparisonEnabled: Bool
    let sourceFormat: DataStudioTemplateSourceFormatResponse
    let segmentPolicy: String
    let segmentSelectors: [DataStudioTemplateSegmentSelectorResponse]
    let fieldBindings: [DataStudioTemplateFieldBindingResponse]
    let matchConditions: [DataStudioTemplateConditionResponse]

    init(
        label: String,
        templateID: String? = nil,
        description: String = "",
        outputKind: String = "curve_metrics",
        comparisonEnabled: Bool = true,
        sourceFormat: DataStudioTemplateSourceFormatResponse = .init(),
        segmentPolicy: String = "single_table",
        segmentSelectors: [DataStudioTemplateSegmentSelectorResponse] = [],
        fieldBindings: [DataStudioTemplateFieldBindingResponse] = [],
        matchConditions: [DataStudioTemplateConditionResponse] = []
    ) {
        self.label = label
        self.templateID = templateID
        self.description = description
        self.outputKind = outputKind
        self.comparisonEnabled = comparisonEnabled
        self.sourceFormat = sourceFormat
        self.segmentPolicy = segmentPolicy
        self.segmentSelectors = segmentSelectors
        self.fieldBindings = fieldBindings
        self.matchConditions = matchConditions
    }

    enum CodingKeys: String, CodingKey {
        case label
        case templateID = "templateId"
        case description
        case outputKind
        case comparisonEnabled
        case sourceFormat
        case segmentPolicy
        case segmentSelectors
        case fieldBindings
        case matchConditions
    }
}

struct DataStudioTemplatePreviewSegmentResponse: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let curveCount: Int
    let metricCount: Int
    let rowCount: Int
}

struct DataStudioNormalizedOutputPreviewPayload: Codable, Equatable, Sendable {
    let selectedStructureID: String?
    let roleMapping: [TemplateRoleMatchPayload]
    let seriesCount: Int
    let metricCount: Int
    let matrixRowCount: Int
    let sampleRows: [[JSONValue]]
    let warnings: [String]
    let errors: [String]

    init(
        selectedStructureID: String? = nil,
        roleMapping: [TemplateRoleMatchPayload] = [],
        seriesCount: Int = 0,
        metricCount: Int = 0,
        matrixRowCount: Int = 0,
        sampleRows: [[JSONValue]] = [],
        warnings: [String] = [],
        errors: [String] = []
    ) {
        self.selectedStructureID = selectedStructureID
        self.roleMapping = roleMapping
        self.seriesCount = seriesCount
        self.metricCount = metricCount
        self.matrixRowCount = matrixRowCount
        self.sampleRows = sampleRows
        self.warnings = warnings
        self.errors = errors
    }

    enum CodingKeys: String, CodingKey {
        case selectedStructureID = "selectedStructureId"
        case roleMapping
        case seriesCount
        case metricCount
        case matrixRowCount
        case sampleRows
        case warnings
        case errors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedStructureID = try container.decodeIfPresent(String.self, forKey: .selectedStructureID)
        roleMapping = try container.decodeIfPresent([TemplateRoleMatchPayload].self, forKey: .roleMapping) ?? []
        seriesCount = try container.decodeIfPresent(Int.self, forKey: .seriesCount) ?? 0
        metricCount = try container.decodeIfPresent(Int.self, forKey: .metricCount) ?? 0
        matrixRowCount = try container.decodeIfPresent(Int.self, forKey: .matrixRowCount) ?? 0
        sampleRows = try container.decodeIfPresent([[JSONValue]].self, forKey: .sampleRows) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        errors = try container.decodeIfPresent([String].self, forKey: .errors) ?? []
    }
}

struct DataStudioTemplatePreviewRequest: Codable, Equatable, Sendable {
    let sourcePath: String
    let template: DataStudioCreateTemplateRequest
    let importSelection: ImportSelectionPayload?
    let importProfile: ImportFilterProfilePayload?
    let importDiagnostics: [ImportDiagnosticPayload]
    let selectedSheetOrSegment: String?

    init(
        sourcePath: String,
        template: DataStudioCreateTemplateRequest,
        importSelection: ImportSelectionPayload? = nil,
        importProfile: ImportFilterProfilePayload? = nil,
        importDiagnostics: [ImportDiagnosticPayload] = [],
        selectedSheetOrSegment: String? = nil
    ) {
        self.sourcePath = sourcePath
        self.template = template
        self.importSelection = importSelection
        self.importProfile = importProfile
        self.importDiagnostics = importDiagnostics
        self.selectedSheetOrSegment = selectedSheetOrSegment
    }
}

struct DataStudioTemplateRecommendationsRequest: Codable, Equatable, Sendable {
    let sourcePath: String
    let importSelection: ImportSelectionPayload?
    let importProfile: ImportFilterProfilePayload?
    let importDiagnostics: [ImportDiagnosticPayload]
    let selectedSheetOrSegment: String?

    init(
        sourcePath: String,
        importSelection: ImportSelectionPayload? = nil,
        importProfile: ImportFilterProfilePayload? = nil,
        importDiagnostics: [ImportDiagnosticPayload] = [],
        selectedSheetOrSegment: String? = nil
    ) {
        self.sourcePath = sourcePath
        self.importSelection = importSelection
        self.importProfile = importProfile
        self.importDiagnostics = importDiagnostics
        self.selectedSheetOrSegment = selectedSheetOrSegment
    }
}

struct DataStudioTemplateRecommendationsResponse: Codable, Equatable, Sendable {
    let matches: [DataStudioTemplateMatchResponse]
    let diagnostics: [ImportDiagnosticPayload]

    init(matches: [DataStudioTemplateMatchResponse] = [], diagnostics: [ImportDiagnosticPayload] = []) {
        self.matches = matches
        self.diagnostics = diagnostics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matches = try container.decodeIfPresent([DataStudioTemplateMatchResponse].self, forKey: .matches) ?? []
        diagnostics = try container.decodeIfPresent([ImportDiagnosticPayload].self, forKey: .diagnostics) ?? []
    }
}

struct DataStudioTemplatePreviewResponse: Codable, Equatable, Sendable {
    let templateID: String
    let outputKind: String
    let parsedSampleCount: Int
    let failedSampleCount: Int
    let seriesCount: Int
    let metricCount: Int
    let matrixRowCount: Int
    let missingRoles: [String]
    let warnings: [String]
    let errors: [String]
    let segments: [DataStudioTemplatePreviewSegmentResponse]
    let normalizedOutputPreview: DataStudioNormalizedOutputPreviewPayload?
    let dataContainers: [DataContainerPayload]

    init(
        templateID: String,
        outputKind: String,
        parsedSampleCount: Int,
        failedSampleCount: Int,
        seriesCount: Int,
        metricCount: Int,
        matrixRowCount: Int,
        missingRoles: [String] = [],
        warnings: [String] = [],
        errors: [String] = [],
        segments: [DataStudioTemplatePreviewSegmentResponse] = [],
        normalizedOutputPreview: DataStudioNormalizedOutputPreviewPayload? = nil,
        dataContainers: [DataContainerPayload] = []
    ) {
        self.templateID = templateID
        self.outputKind = outputKind
        self.parsedSampleCount = parsedSampleCount
        self.failedSampleCount = failedSampleCount
        self.seriesCount = seriesCount
        self.metricCount = metricCount
        self.matrixRowCount = matrixRowCount
        self.missingRoles = missingRoles
        self.warnings = warnings
        self.errors = errors
        self.segments = segments
        self.normalizedOutputPreview = normalizedOutputPreview
        self.dataContainers = dataContainers
    }

    enum CodingKeys: String, CodingKey {
        case templateID = "templateId"
        case outputKind
        case parsedSampleCount
        case failedSampleCount
        case seriesCount
        case metricCount
        case matrixRowCount
        case missingRoles
        case warnings
        case errors
        case segments
        case normalizedOutputPreview
        case dataContainers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        templateID = try container.decode(String.self, forKey: .templateID)
        outputKind = try container.decode(String.self, forKey: .outputKind)
        parsedSampleCount = try container.decodeIfPresent(Int.self, forKey: .parsedSampleCount) ?? 0
        failedSampleCount = try container.decodeIfPresent(Int.self, forKey: .failedSampleCount) ?? 0
        seriesCount = try container.decodeIfPresent(Int.self, forKey: .seriesCount) ?? 0
        metricCount = try container.decodeIfPresent(Int.self, forKey: .metricCount) ?? 0
        matrixRowCount = try container.decodeIfPresent(Int.self, forKey: .matrixRowCount) ?? 0
        missingRoles = try container.decodeIfPresent([String].self, forKey: .missingRoles) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        errors = try container.decodeIfPresent([String].self, forKey: .errors) ?? []
        segments = try container.decodeIfPresent([DataStudioTemplatePreviewSegmentResponse].self, forKey: .segments) ?? []
        normalizedOutputPreview = try container.decodeIfPresent(
            DataStudioNormalizedOutputPreviewPayload.self,
            forKey: .normalizedOutputPreview
        )
        dataContainers = try container.decodeIfPresent([DataContainerPayload].self, forKey: .dataContainers) ?? []
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
    let importSelection: ImportSelectionPayload?

    init(
        filePaths: [String],
        outputPath: String,
        templateID: String,
        groupName: String? = nil,
        importSelection: ImportSelectionPayload? = nil
    ) {
        self.filePaths = filePaths
        self.outputPath = outputPath
        self.templateID = templateID
        self.groupName = groupName
        self.importSelection = importSelection
    }

    enum CodingKeys: String, CodingKey {
        case filePaths
        case outputPath
        case templateID = "templateId"
        case groupName
        case importSelection
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
    let figureFitOptionsByRecipeID: [String: FitOptionsPayload]

    init(
        workbookPaths: [String],
        outputDir: String,
        groupStates: [DataStudioGroupStatePayload] = [],
        specimenStates: [DataStudioSpecimenStatePayload] = [],
        selectedRecipeIDs: [String] = [],
        figureOptionsByRecipeID: [String: RenderOptionsPayload] = [:],
        figureFitOptionsByRecipeID: [String: FitOptionsPayload] = [:]
    ) {
        self.workbookPaths = workbookPaths
        self.outputDir = outputDir
        self.groupStates = groupStates
        self.specimenStates = specimenStates
        self.selectedRecipeIDs = selectedRecipeIDs
        self.figureOptionsByRecipeID = figureOptionsByRecipeID
        self.figureFitOptionsByRecipeID = figureFitOptionsByRecipeID
    }

    enum CodingKeys: String, CodingKey {
        case workbookPaths
        case outputDir
        case groupStates
        case specimenStates
        case selectedRecipeIDs = "selectedRecipeIds"
        case figureOptionsByRecipeID = "figureOptionsByRecipeId"
        case figureFitOptionsByRecipeID = "figureFitOptionsByRecipeId"
    }
}

struct DataStudioSessionNormalizeRequest: Codable, Equatable, Sendable {
    let payload: [String: JSONValue]
}
