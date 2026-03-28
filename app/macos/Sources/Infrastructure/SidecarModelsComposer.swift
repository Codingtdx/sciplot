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
}

struct ThumbnailRequest: Codable, Equatable, Sendable {
    let filePath: String
    let pageIndex: Int
    let maxSidePx: Int
}

struct PanelThumbnailResponse: Codable, Equatable, Sendable {
    let pngBase64: String
}

struct ComposerPreviewResponse: Codable, Equatable, Sendable {
    let valid: Bool
    let validationError: String?
    let pngBase64: String
    let qa: QAReportResponse?
    let submissionReport: SubmissionReportResponse?
    let suggestedProjectPatch: [[String: JSONValue]]
}

typealias ComposerProjectResponse = ComposerRequestPayload
