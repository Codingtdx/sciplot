import SwiftUI

enum Workbench: String, CaseIterable, Hashable, Identifiable {
    case plot
    case dataCleanup
    case composer
    case codeConsole

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plot:
            return "Plot"
        case .dataCleanup:
            return "Data Cleanup"
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
        case .dataCleanup:
            return "Workbook cleanup and compare"
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
        case .dataCleanup:
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
        case .dataCleanup:
            return "2"
        case .composer:
            return "3"
        case .codeConsole:
            return "4"
        }
    }
}
