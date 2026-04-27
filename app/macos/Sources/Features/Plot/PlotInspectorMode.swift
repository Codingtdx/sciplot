import SwiftUI

enum PlotInspectorMode: String, CaseIterable, Identifiable {
    case figure
    case data
    case layers
    case arrange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .figure:
            return "Figure"
        case .data:
            return "Data"
        case .layers:
            return "Layers"
        case .arrange:
            return "Arrange"
        }
    }

    var systemImage: String {
        switch self {
        case .figure:
            return "paintpalette"
        case .data:
            return "point.3.connected.trianglepath.dotted"
        case .layers:
            return "square.stack.3d.up"
        case .arrange:
            return "arrow.up.left.and.arrow.down.right"
        }
    }
}

enum PlotDataPipelineSelection: Hashable, Identifiable {
    case variable(String)
    case transform(String)

    var id: String {
        switch self {
        case .variable(let id):
            return "variable:\(id)"
        case .transform(let id):
            return "transform:\(id)"
        }
    }
}

enum PlotLayerSelection: Hashable, Identifiable {
    case fitOverlay
    case function(String)
    case referenceGuide(String)
    case textAnnotation(String)
    case shapeAnnotation(String)
    case series(String)

    var id: String {
        switch self {
        case .fitOverlay:
            return "fit-overlay"
        case .function(let id):
            return "function:\(id)"
        case .referenceGuide(let id):
            return "guide:\(id)"
        case .textAnnotation(let id):
            return "text:\(id)"
        case .shapeAnnotation(let id):
            return "shape:\(id)"
        case .series(let id):
            return "series:\(id)"
        }
    }

    var isMovableOverlay: Bool {
        switch self {
        case .referenceGuide, .textAnnotation, .shapeAnnotation:
            return true
        case .fitOverlay, .function, .series:
            return false
        }
    }
}

struct PlotInspectorModePicker: View {
    @Binding var selection: PlotInspectorMode

    var body: some View {
        Picker("Inspector Mode", selection: $selection) {
            ForEach(PlotInspectorMode.allCases) { mode in
                Label(mode.title, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
    }
}
