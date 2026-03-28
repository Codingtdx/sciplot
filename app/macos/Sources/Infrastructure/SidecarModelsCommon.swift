import Foundation

struct HealthResponse: Codable, Equatable, Sendable {
    let status: String
    let version: String
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
    let pngBase64: String
    let qa: QAReportResponse?
}
