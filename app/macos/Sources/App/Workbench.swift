import SwiftUI

enum Workbench: String, CaseIterable, Hashable, Identifiable {
    case plot
    case dataStudio
    case composer
    case codeConsole

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plot:
            return "Plot"
        case .dataStudio:
            return "Data Studio"
        case .composer:
            return "Composer"
        case .codeConsole:
            return "Code Console"
        }
    }

    var subtitle: String {
        switch self {
        case .plot:
            return "Publication-ready figure workflow"
        case .dataStudio:
            return "Template-driven workbook analysis"
        case .composer:
            return "Canvas-first panel composition"
        case .codeConsole:
            return "Context-aware native shell"
        }
    }

    var systemImage: String {
        switch self {
        case .plot:
            return "chart.xyaxis.line"
        case .dataStudio:
            return "tablecells"
        case .composer:
            return "square.on.square.squareshape.controlhandles"
        case .codeConsole:
            return "terminal"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .plot:
            return "1"
        case .dataStudio:
            return "2"
        case .composer:
            return "3"
        case .codeConsole:
            return "4"
        }
    }
}
