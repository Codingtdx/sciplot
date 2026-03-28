import Foundation

struct TensileReplicateRequest: Codable, Equatable, Sendable {
    let filePaths: [String]
    let outputPath: String
    let groupName: String?
}

struct TensileWorkbookRequest: Codable, Equatable, Sendable {
    let workbookPath: String
}

struct TensileComparisonExportRequest: Codable, Equatable, Sendable {
    let workbookPaths: [String]
    let outputDir: String
}

struct TensileMetricSummaryResponse: Codable, Equatable, Sendable {
    let label: String
    let unit: String
    let mean: Double?
    let std: Double?
}

struct TensileReplicateResponseModel: Codable, Equatable, Sendable {
    let outputPath: String
    let groupName: String
    let preferredSheet: String
    let sheetNames: [String]
    let sampleCount: Int
    let representativeFilename: String
    let metrics: [TensileMetricSummaryResponse]
    let warnings: [String]
}

struct TensileWorkbookSummaryResponse: Codable, Equatable, Sendable {
    let workbookPath: String
    let label: String
    let sheetNames: [String]
    let sampleCount: Int
    let representativeFilename: String
    let metrics: [TensileMetricSummaryResponse]
}

struct TensileComparisonExportResponse: Codable, Equatable, Sendable {
    let bundleDir: String
    let comparisonWorkbookPath: String
    let labels: [String]
    let outputs: [String]
}
