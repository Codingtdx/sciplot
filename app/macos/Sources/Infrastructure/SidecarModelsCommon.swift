import Foundation

struct HealthResponse: Codable, Equatable, Sendable {
    let status: String
    let version: String
}

struct StatusResponse: Codable, Equatable, Sendable {
    let status: String
}

struct PathResponse: Codable, Equatable, Sendable {
    let outputPath: String
}

struct QAIssueResponse: Codable, Equatable, Sendable {
    let id: String
    let severity: String
    let metricValue: JSONValue?
    let target: JSONValue?
    let message: String
}

struct QAReportResponse: Codable, Equatable, Sendable {
    let score: Double
    let grade: String
    let issues: [QAIssueResponse]
    let autofixesApplied: [String]
}

struct SubmissionCheckResponse: Codable, Equatable, Sendable {
    let id: String
    let status: String
    let message: String
    let metricValue: JSONValue?
    let target: JSONValue?
    let source: String?
}

struct SubmissionReportResponse: Codable, Equatable, Sendable {
    let context: String
    let readiness: String
    let summary: String
    let template: String?
    let stylePreset: String?
    let palettePreset: String?
    let outputCount: Int
    let outputFilenames: [String]
    let blockers: [String]
    let checks: [SubmissionCheckResponse]
}

struct PreviewItemResponse: Codable, Equatable, Sendable {
    let filename: String
    let pdfBase64: String
    let pngBase64: String?
    let qa: QAReportResponse?
    let interactionMetadata: PreviewInteractionMetadata?

    init(
        filename: String,
        pdfBase64: String,
        pngBase64: String? = nil,
        qa: QAReportResponse?,
        interactionMetadata: PreviewInteractionMetadata? = nil
    ) {
        self.filename = filename
        self.pdfBase64 = pdfBase64
        self.pngBase64 = pngBase64
        self.qa = qa
        self.interactionMetadata = interactionMetadata
    }
}

struct PreviewInteractionMetadata: Codable, Equatable, Sendable {
    let schemaVersion: Int?
    let figure: PreviewFigureMetadata
    let axes: [PreviewAxisMetadata]
    let artists: [PreviewArtistMetadata]
    let objects: [PreviewInteractionObjectMetadata]

    init(
        schemaVersion: Int? = nil,
        figure: PreviewFigureMetadata,
        axes: [PreviewAxisMetadata],
        artists: [PreviewArtistMetadata] = [],
        objects: [PreviewInteractionObjectMetadata] = []
    ) {
        self.schemaVersion = schemaVersion
        self.figure = figure
        self.axes = axes
        self.artists = artists
        self.objects = objects
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case figure
        case axes
        case artists
        case objects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
        figure = try container.decode(PreviewFigureMetadata.self, forKey: .figure)
        axes = try container.decodeIfPresent([PreviewAxisMetadata].self, forKey: .axes) ?? []
        artists = try container.decodeIfPresent([PreviewArtistMetadata].self, forKey: .artists) ?? []
        objects = try container.decodeIfPresent([PreviewInteractionObjectMetadata].self, forKey: .objects) ?? []
    }
}

struct PreviewFigureMetadata: Codable, Equatable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
}

struct PreviewAxisMetadata: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let role: String
    let bboxPixels: PreviewBBoxMetadata
    let xRange: [Double]
    let yRange: [Double]
    let xScale: String
    let yScale: String
    let xReversed: Bool
    let yReversed: Bool
}

struct PreviewBBoxMetadata: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct PreviewArtistMetadata: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: String
    let axisID: String
    let seriesID: String?
    let label: String?
    let bboxPixels: PreviewBBoxMetadata
    let points: [[Double]]

    init(
        id: String,
        kind: String,
        axisID: String,
        seriesID: String? = nil,
        label: String? = nil,
        bboxPixels: PreviewBBoxMetadata,
        points: [[Double]]
    ) {
        self.id = id
        self.kind = kind
        self.axisID = axisID
        self.seriesID = seriesID
        self.label = label
        self.bboxPixels = bboxPixels
        self.points = points
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case axisID = "axisId"
        case seriesID = "seriesId"
        case label
        case bboxPixels
        case points
    }
}

struct PreviewInteractionPayloadRefMetadata: Codable, Equatable, Sendable {
    let type: String
    let id: String
}

struct PreviewInteractionObjectMetadata: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: String
    let label: String?
    let axisID: String?
    let bboxPixels: PreviewBBoxMetadata
    let points: [[Double]]
    let payloadRef: PreviewInteractionPayloadRefMetadata?
    let operations: [String]

    init(
        id: String,
        kind: String,
        label: String? = nil,
        axisID: String? = nil,
        bboxPixels: PreviewBBoxMetadata,
        points: [[Double]] = [],
        payloadRef: PreviewInteractionPayloadRefMetadata? = nil,
        operations: [String] = ["select", "more"]
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.axisID = axisID
        self.bboxPixels = bboxPixels
        self.points = points
        self.payloadRef = payloadRef
        self.operations = operations
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case label
        case axisID = "axisId"
        case bboxPixels
        case points
        case payloadRef
        case operations
    }
}
