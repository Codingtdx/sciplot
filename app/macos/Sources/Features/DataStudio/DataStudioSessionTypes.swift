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

enum DataStudioImportFlowState: Equatable {
    case idle
    case wizard(step: DataStudioImportWizardStep)
    case importer(kind: DataStudioImportKind)

    var wizardStep: DataStudioImportWizardStep? {
        guard case let .wizard(step) = self else {
            return nil
        }
        return step
    }

    var importerKind: DataStudioImportKind? {
        guard case let .importer(kind) = self else {
            return nil
        }
        return kind
    }

    var isWizardPresented: Bool {
        wizardStep != nil
    }

    var isImporterPresented: Bool {
        importerKind != nil
    }
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

enum DataStudioSpecimenFilterSortKey: Equatable {
    case metric(metricID: String)
    case distanceFromMean
}

struct DataStudioSpecimenFilterSortDescriptor: Equatable {
    let key: DataStudioSpecimenFilterSortKey
    let label: String
    let unit: String?

    var sortsHighToLow: Bool {
        switch key {
        case .metric:
            return true
        case .distanceFromMean:
            return false
        }
    }
}

struct DataStudioSpecimenFilterRankedRow: Identifiable, Equatable {
    let id: String
    let rank: Int
    let sortValue: Double?
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
    let help: String
    let rowBadge: String?
    let hasPendingChanges: Bool
    let isBusy: Bool
    let autoFilterSupported: Bool
    let autoFilterReason: String?
    let useAutoKeepAvailability: ActionAvailability
    let turnOffAvailability: ActionAvailability
    let applyDraftAvailability: ActionAvailability
    let useAutoRepresentativeAvailability: ActionAvailability
    let revertDraftAvailability: ActionAvailability
    let sortDescriptor: DataStudioSpecimenFilterSortDescriptor
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

struct DataStudioExportFilteredWorkbookItem: Identifiable, Equatable {
    let id: String
    let response: DataStudioFilteredWorkbookResponse
    let url: URL
}

struct DataStudioTemplateSummaryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
}

enum DataStudioSuggestionCardKind: Equatable {
    case curve
    case metric
    case metadata
    case structure
}

struct DataStudioSuggestionCardPresentation: Identifiable, Equatable {
    let id: String
    let kind: DataStudioSuggestionCardKind
    let values: [String]
    let location: String?
}

struct DataStudioResolverPresentation: Equatable {
    let recommendedMatches: [DataStudioTemplateMatchResponse]
    let otherTemplates: [DataStudioTemplateResponse]
    let useSelectedTemplateAvailability: ActionAvailability
}

struct DataStudioTemplateEditorPresentation: Equatable {
    let previewCaption: String?
    let primaryCurveSuggestion: DataStudioSuggestionCardPresentation?
    let primaryMetricSuggestion: DataStudioSuggestionCardPresentation?
    let primaryMetadataSuggestion: DataStudioSuggestionCardPresentation?
    let primaryStructureSuggestion: DataStudioSuggestionCardPresentation?
    let secondaryCurveSuggestions: [DataStudioSuggestionCardPresentation]
    let advancedCandidates: [DataStudioFieldCandidateResponse]
    let selectedSummaryItems: [DataStudioTemplateSummaryItem]
    let saveTemplateAvailability: ActionAvailability
    let saveTemplateAndContinueAvailability: ActionAvailability
}
