import SwiftUI

enum PlotTool: String, CaseIterable, Identifiable {
    case select
    case panZoom
    case dataCursor
    case fit
    case guide
    case text
    case shape
    case function
    case axisBreak
    case secondaryAxis

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select:
            return "Select"
        case .panZoom:
            return "Pan"
        case .dataCursor:
            return "Cursor"
        case .fit:
            return "Fit"
        case .guide:
            return "Guide"
        case .text:
            return "Text"
        case .shape:
            return "Shape"
        case .function:
            return "Function"
        case .axisBreak:
            return "Break"
        case .secondaryAxis:
            return "2Y"
        }
    }

    var systemImage: String {
        switch self {
        case .select:
            return "cursorarrow"
        case .panZoom:
            return "hand.draw"
        case .dataCursor:
            return "scope"
        case .fit:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .guide:
            return "ruler"
        case .text:
            return "textformat"
        case .shape:
            return "rectangle.dashed"
        case .function:
            return "function"
        case .axisBreak:
            return "arrow.left.and.right"
        case .secondaryAxis:
            return "chart.line.uptrend.xyaxis"
        }
    }

    var help: String {
        switch self {
        case .select:
            return "Select objects on the figure. Shortcut: ⌥⌘V"
        case .panZoom:
            return "Pan and zoom the preview. Shortcut: ⌥⌘P"
        case .dataCursor:
            return "Inspect plotted values when hit testing is available."
        case .fit:
            return "Edit the fit overlay. Shortcut: ⌥⌘F"
        case .guide:
            return "Add or edit reference guides. Shortcut: ⌥⌘G"
        case .text:
            return "Add or edit text notes and callouts. Shortcut: ⌥⌘T"
        case .shape:
            return "Add or edit shape annotations. Shortcut: ⌥⌘S"
        case .function:
            return "Add or edit function layers. Shortcut: ⌥⌘U"
        case .axisBreak:
            return "Add or edit broken axes. Shortcut: ⌥⌘B"
        case .secondaryAxis:
            return "Edit the secondary Y axis. Shortcut: ⌥⌘Y"
        }
    }

    var shortcutKey: KeyEquivalent? {
        switch self {
        case .select:
            return "v"
        case .panZoom:
            return "p"
        case .dataCursor:
            return nil
        case .fit:
            return "f"
        case .guide:
            return "g"
        case .text:
            return "t"
        case .shape:
            return "s"
        case .function:
            return "u"
        case .axisBreak:
            return "b"
        case .secondaryAxis:
            return "y"
        }
    }

    var showsCanvasOptions: Bool {
        switch self {
        case .fit, .guide, .text, .shape, .function, .axisBreak, .secondaryAxis:
            return true
        case .select, .panZoom, .dataCursor:
            return false
        }
    }
}

enum PlotAxisSelection: String, Hashable, Identifiable {
    case x
    case y

    var id: String { rawValue }

    var title: String {
        switch self {
        case .x:
            return "X Axis"
        case .y:
            return "Y Axis"
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

enum PlotCanvasSelection: Hashable, Identifiable {
    case figure
    case axis(PlotAxisSelection)
    case layer(PlotLayerSelection)
    case dataPipeline(PlotDataPipelineSelection)

    var id: String {
        switch self {
        case .figure:
            return "figure"
        case .axis(let axis):
            return "axis:\(axis.id)"
        case .layer(let layer):
            return "layer:\(layer.id)"
        case .dataPipeline(let item):
            return "data:\(item.id)"
        }
    }
}

extension PlotSession {
    func plotToolAvailability(for tool: PlotTool) -> ActionAvailability {
        switch tool {
        case .select, .panZoom:
            return .enabled()
        case .dataCursor:
            return .disabled("Data cursor needs preview hit testing metadata.")
        case .fit:
            return fitOverlayAvailability
        case .guide:
            return referenceGuideAvailability
        case .text:
            return textAnnotationAvailability
        case .shape:
            return shapeAnnotationAvailability
        case .function:
            return analyticalLayerAvailability
        case .axisBreak:
            if xAxisBreakAvailability.isEnabled {
                return xAxisBreakAvailability
            }
            return yAxisBreakAvailability
        case .secondaryAxis:
            return extraYAxisAvailability
        }
    }

    func activatePlotTool(_ tool: PlotTool) {
        guard plotToolAvailability(for: tool).isEnabled else {
            return
        }

        selectedPlotTool = tool
        switch tool {
        case .select, .panZoom:
            break
        case .dataCursor:
            selectCanvasSelection(.figure)
        case .fit:
            if fitOptions.enabled {
                selectPlotLayer(.fitOverlay)
            }
        case .guide:
            if let id = selectedReferenceGuideID ?? referenceGuides.last?.id {
                selectPlotLayer(.referenceGuide(id))
            }
        case .text:
            if let id = selectedTextAnnotationID ?? textAnnotations.last?.id {
                selectPlotLayer(.textAnnotation(id))
            }
        case .shape:
            if let id = selectedShapeAnnotationID ?? shapeAnnotations.last?.id {
                selectPlotLayer(.shapeAnnotation(id))
            }
        case .function:
            if let layer = analyticalLayers.last {
                selectPlotLayer(.function(layer.id))
            }
        case .axisBreak:
            if xAxisBreakAvailability.isEnabled {
                selectCanvasSelection(.axis(.x))
            } else if yAxisBreakAvailability.isEnabled {
                selectCanvasSelection(.axis(.y))
            }
        case .secondaryAxis:
            selectCanvasSelection(.axis(.y))
        }
    }

    func selectCanvasSelection(_ selection: PlotCanvasSelection) {
        canvasSelection = selection
        switch selection {
        case .layer(let layer):
            selectPlotLayer(layer)
        case .figure, .axis, .dataPipeline:
            selectedReferenceGuideID = nil
            selectedTextAnnotationID = nil
            selectedShapeAnnotationID = nil
        }
    }

    func selectPlotLayer(_ layer: PlotLayerSelection?) {
        guard let layer else {
            canvasSelection = .figure
            selectedReferenceGuideID = nil
            selectedTextAnnotationID = nil
            selectedShapeAnnotationID = nil
            return
        }

        canvasSelection = .layer(layer)
        switch layer {
        case .referenceGuide(let id):
            selectedReferenceGuideID = id
            selectedTextAnnotationID = nil
            selectedShapeAnnotationID = nil
        case .textAnnotation(let id):
            selectedReferenceGuideID = nil
            selectedTextAnnotationID = id
            selectedShapeAnnotationID = nil
        case .shapeAnnotation(let id):
            selectedReferenceGuideID = nil
            selectedTextAnnotationID = nil
            selectedShapeAnnotationID = id
        case .fitOverlay, .function, .series:
            selectedReferenceGuideID = nil
            selectedTextAnnotationID = nil
            selectedShapeAnnotationID = nil
        }
    }
}

struct PlotToolStripView: View {
    @Bindable var session: PlotSession

    var body: some View {
        HStack(spacing: 3) {
            ForEach(PlotTool.allCases) { tool in
                toolButton(tool)
            }
        }
        .padding(5)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private func toolButton(_ tool: PlotTool) -> some View {
        let availability = session.plotToolAvailability(for: tool)
        Button {
            session.activatePlotTool(tool)
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(session.selectedPlotTool == tool ? Color.accentColor : Color.primary)
        .background {
            if session.selectedPlotTool == tool {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
            }
        }
        .disabled(!availability.isEnabled)
        .help(availability.reason ?? tool.help)
    }
}
