import Foundation

enum DataStudioImportKind: String, Identifiable {
    case rawFiles
    case existingWorkbook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rawFiles:
            return "Raw Files"
        case .existingWorkbook:
            return "Existing Workbook"
        }
    }

    var summary: String {
        switch self {
        case .rawFiles:
            return "Import source csv / txt / xls / xlsx files and let Data Studio match or create a parse template."
        case .existingWorkbook:
            return "Import a prepared workbook directly into the current group list and compare context."
        }
    }
}

enum DataStudioImportDisposition: String, Identifiable {
    case addToCurrentSession
    case startNewSession

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addToCurrentSession:
            return "Add to Current Session"
        case .startNewSession:
            return "Start New Session"
        }
    }
}

enum DataStudioImportWizardStep: String, Equatable {
    case scope
    case kind
    case resolver
    case createTemplate
}

enum DataStudioActivity: Equatable {
    case idle
    case loadingTemplates
    case previewingSource
    case creatingTemplate
    case buildingWorkbook
    case importingWorkbooks
    case previewingComparison
    case exportingComparison
}

enum DataStudioWorkbookPreviewRefreshState: Equatable {
    case idle
    case refreshing(workbookPath: String)
    case failed(workbookPath: String, message: String)
}

enum DataStudioSpecimenFilterMode: String, Equatable {
    case off
    case auto
    case manual

    var defaultHelp: String {
        switch self {
        case .off:
            return "Open the ranked specimen list and automatic keep-5 filter."
        case .auto:
            return "The comparison preview is using Auto Keep 5."
        case .manual:
            return "The comparison preview is using a manual specimen filter."
        }
    }
}

enum DataStudioSpecimenFilterAnchor: Equatable {
    case focusedStrip(workbookPath: String)

    var workbookPath: String {
        switch self {
        case let .focusedStrip(workbookPath):
            return workbookPath
        }
    }

    func retargeted(to workbookPath: String) -> Self {
        .focusedStrip(workbookPath: workbookPath)
    }
}

enum DataStudioSpecimenFilterRankDisposition: Equatable {
    case keep
    case out
    case ineligible

    var title: String {
        switch self {
        case .keep:
            return "Keep"
        case .out:
            return "Out"
        case .ineligible:
            return "Ineligible"
        }
    }
}

struct DataStudioSpecimenFilterRankedRow: Identifiable, Equatable {
    let id: String
    let rank: Int
    let distanceFromMeanScore: Double?
    let disposition: DataStudioSpecimenFilterRankDisposition
    let showsCutoffAfter: Bool
}

struct DataStudioWorkbookItem: Identifiable, Equatable {
    let id: String
    var response: DataStudioWorkbookResponse

    var workbookURL: URL {
        URL(fileURLWithPath: response.workbookPath)
    }
}

struct DataStudioGroupRowItem: Identifiable, Equatable {
    let workbook: DataStudioWorkbookItem
    let state: DataStudioGroupStatePayload

    var id: String { workbook.response.workbookPath }
}

struct DataStudioSpecimenFilterPresentation {
    let mode: DataStudioSpecimenFilterMode
    let title: String
    let summary: String?
    let help: String
    let rowBadge: String?
    let hasPendingChanges: Bool
    let isBusy: Bool
    let totalSpecimenCount: Int
    let appliedIncludedCount: Int
    let autoKeepCount: Int
    let autoFilterSupported: Bool
    let autoFilterReason: String?
    let canApplyAuto: Bool
    let canTurnOff: Bool
    let rankedRows: [DataStudioSpecimenFilterRankedRow]
    let advancedRows: [DataStudioSpecimenPreviewResponse]
}

struct DataStudioFigureFamilyItem: Identifiable, Equatable {
    let id: String
    let title: String
    let metricID: String?
    let recipes: [DataStudioComparisonRecipeResponse]
}

struct DataStudioFigureTemplateItem: Identifiable, Equatable {
    let id: String
    let label: String
    let recipeID: String
}

struct DataStudioExportFigureItem: Identifiable, Equatable {
    let id: String
    let response: DataStudioFigureOutputResponse
    let url: URL
}

struct DataStudioTemplateSummaryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
}
