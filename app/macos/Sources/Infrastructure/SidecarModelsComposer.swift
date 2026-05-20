import Foundation

struct ComposerCropRectPayload: Codable, Equatable, Sendable {
    var x: Double = 0.0
    var y: Double = 0.0
    var width: Double = 1.0
    var height: Double = 1.0
}

struct ComposerLayoutGridPayload: Codable, Equatable, Sendable {
    var columns: Int = 3
    var rows: Int = 3
    var cellWidthMm: Double = 60.0
    var cellHeightMm: Double = 55.0
    var frameXMm: Double = 0.0
    var frameYMm: Double = 2.5
    var frameWidthMm: Double = 180.0
    var frameHeightMm: Double = 165.0
}

struct ComposerRegionPayload: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var kind: String
    var col: Int
    var row: Int
    var colSpan: Int
    var rowSpan: Int
    var label: String?
    var locked: Bool = false
    var slotKind: String?
}

struct ComposerAssetRefPayload: Codable, Equatable, Sendable, Identifiable {
    var id: String { assetID }
    var assetID: String
    var sourceModule: String
    var sourceGraphNodeID: String?
    var artifactManifestID: String?
    var label: String
    var kind: String
    var mimeType: String?
    var sha256: String
    var embeddedPath: String?
    var refreshPolicy: String
    var preflightStatus: String
    var help: String

    init(
        assetID: String,
        sourceModule: String,
        sourceGraphNodeID: String? = nil,
        artifactManifestID: String? = nil,
        label: String,
        kind: String = "figure",
        mimeType: String? = nil,
        sha256: String = "",
        embeddedPath: String? = nil,
        refreshPolicy: String = "manual",
        preflightStatus: String = "ready",
        help: String = "Linked Composer artifact managed through the project artifact manifest."
    ) {
        self.assetID = assetID
        self.sourceModule = sourceModule
        self.sourceGraphNodeID = sourceGraphNodeID
        self.artifactManifestID = artifactManifestID
        self.label = label
        self.kind = kind
        self.mimeType = mimeType
        self.sha256 = sha256
        self.embeddedPath = embeddedPath
        self.refreshPolicy = refreshPolicy
        self.preflightStatus = preflightStatus
        self.help = help
    }

    enum CodingKeys: String, CodingKey {
        case assetID = "assetId"
        case sourceModule
        case sourceGraphNodeID = "sourceGraphNodeId"
        case artifactManifestID = "artifactManifestId"
        case label
        case kind
        case mimeType
        case sha256
        case embeddedPath
        case refreshPolicy
        case preflightStatus
        case help
    }
}

struct ComposerPanelPayload: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var filePath: String
    var pageIndex: Int = 0
    var xMm: Double
    var yMm: Double
    var wMm: Double
    var hMm: Double
    var locked: Bool = false
    var hidden: Bool = false
    var label: String?
    var kind: String = "graph"
    var zIndex: Int = 0
    var groupID: String?
    var regionID: String?
    var slotID: String?
    var cropRect: ComposerCropRectPayload = .init()
    var assetRef: ComposerAssetRefPayload?

    enum CodingKeys: String, CodingKey {
        case id
        case filePath
        case pageIndex
        case xMm
        case yMm
        case wMm
        case hMm
        case locked
        case hidden
        case label
        case kind
        case zIndex
        case groupID = "groupId"
        case regionID = "regionId"
        case slotID = "slotId"
        case cropRect
        case assetRef
    }
}

struct ComposerTextPayload: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var text: String
    var xMm: Double
    var yMm: Double
    var fontSizePt: Double = 8.0
    var align: String = "left"
    var zIndex: Int = 0
    var locked: Bool = false
    var hidden: Bool = false
    var groupID: String?
    var regionID: String?
    var slotID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case xMm
        case yMm
        case fontSizePt
        case align
        case zIndex
        case locked
        case hidden
        case groupID = "groupId"
        case regionID = "regionId"
        case slotID = "slotId"
    }
}

struct ComposerRequestPayload: Codable, Equatable, Sendable {
    var version: Int = 2
    var mode: String = "composer"
    var canvasWidthMm: Double = 180.0
    var canvasHeightMm: Double = 170.0
    var gridMm: Double = 0.5
    var layoutGrid: ComposerLayoutGridPayload = .init()
    var regions: [ComposerRegionPayload] = []
    var panels: [ComposerPanelPayload] = []
    var texts: [ComposerTextPayload] = []
    var autoLabels: Bool = true
}

struct ComposerImportRequestPayload: Codable, Equatable, Sendable {
    let project: ComposerRequestPayload
    let filePaths: [String]
    let kind: String
    let assetRefs: [ComposerAssetRefPayload]

    init(
        project: ComposerRequestPayload,
        filePaths: [String],
        kind: String,
        assetRefs: [ComposerAssetRefPayload] = []
    ) {
        self.project = project
        self.filePaths = filePaths
        self.kind = kind
        self.assetRefs = assetRefs
    }
}

struct ThumbnailRequest: Codable, Equatable, Sendable {
    let filePath: String
    let pageIndex: Int
    let maxSidePx: Int
}

struct PanelThumbnailResponse: Codable, Equatable, Sendable {
    let pngBase64: String
}

struct ComposerPreflightDiagnosticPayload: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let severity: String
    let message: String
    let panelID: String?
    let sourceModule: String?
    let help: String

    enum CodingKeys: String, CodingKey {
        case id
        case severity
        case message
        case panelID = "panelId"
        case sourceModule
        case help
    }
}

struct ComposerExportPreflightPayload: Codable, Equatable, Sendable {
    let status: String
    let diagnostics: [ComposerPreflightDiagnosticPayload]
    let blockingPanelIDs: [String]
    let help: String

    enum CodingKeys: String, CodingKey {
        case status
        case diagnostics
        case blockingPanelIDs = "blockingPanelIds"
        case help
    }
}

struct ComposerPreviewResponse: Codable, Equatable, Sendable {
    let valid: Bool
    let validationError: String?
    let pngBase64: String
    let qa: QAReportResponse?
    let submissionReport: SubmissionReportResponse?
    let suggestedProjectPatch: [[String: JSONValue]]
    let exportPreflight: ComposerExportPreflightPayload?

    init(
        valid: Bool,
        validationError: String?,
        pngBase64: String,
        qa: QAReportResponse? = nil,
        submissionReport: SubmissionReportResponse? = nil,
        suggestedProjectPatch: [[String: JSONValue]] = [],
        exportPreflight: ComposerExportPreflightPayload? = nil
    ) {
        self.valid = valid
        self.validationError = validationError
        self.pngBase64 = pngBase64
        self.qa = qa
        self.submissionReport = submissionReport
        self.suggestedProjectPatch = suggestedProjectPatch
        self.exportPreflight = exportPreflight
    }
}

typealias ComposerProjectResponse = ComposerRequestPayload
