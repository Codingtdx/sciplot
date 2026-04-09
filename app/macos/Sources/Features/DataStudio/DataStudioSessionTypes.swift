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
