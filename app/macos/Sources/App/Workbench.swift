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

    var windowSceneID: String {
        switch self {
        case .plot:
            return "plot"
        case .dataStudio:
            return "data-studio"
        case .composer:
            return "composer"
        case .codeConsole:
            return "code-console"
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
