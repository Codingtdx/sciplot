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
    let figure: PreviewFigureMetadata
    let axes: [PreviewAxisMetadata]
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
