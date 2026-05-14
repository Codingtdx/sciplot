import SwiftUI

enum PlotAdjustmentCategory: String, CaseIterable, Identifiable {
    case figure
    case axes
    case legend
    case guides
    case fit
    case functions
    case annotations
    case advancedAxes

    var id: String { rawValue }

    static let railCategories: [PlotAdjustmentRailItem] = [
        PlotAdjustmentRailItem(category: .figure),
        PlotAdjustmentRailItem(category: .axes),
        PlotAdjustmentRailItem(category: .legend),
        PlotAdjustmentRailItem(category: .guides),
        PlotAdjustmentRailItem(category: .fit),
        PlotAdjustmentRailItem(category: .functions),
        PlotAdjustmentRailItem(category: .annotations),
        PlotAdjustmentRailItem(category: .advancedAxes),
    ]

    var title: String {
        switch self {
        case .figure:
            return "Figure"
        case .axes:
            return "Axes"
        case .legend:
            return "Legend"
        case .guides:
            return "Guides"
        case .fit:
            return "Fit"
        case .functions:
            return "Functions"
        case .annotations:
            return "Annotations"
        case .advancedAxes:
            return "Advanced Axes"
        }
    }

    var systemImage: String {
        switch self {
        case .figure:
            return "rectangle.inset.filled"
        case .axes:
            return "chart.xyaxis.line"
        case .legend:
            return "list.number"
        case .guides:
            return "ruler"
        case .fit:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .functions:
            return "function"
        case .annotations:
            return "text.bubble"
        case .advancedAxes:
            return "arrow.left.and.right"
        }
    }

    var help: String {
        switch self {
        case .figure:
            return "Adjust canvas size, style, palette, and figure theme."
        case .axes:
            return "Adjust axis scales, ranges, tick density, and baseline."
        case .legend:
            return "Manually order legend and series entries."
        case .guides:
            return "Add and edit reference lines and regions."
        case .fit:
            return "Configure fit model and fit overlay."
        case .functions:
            return "Add and edit analytical function layers."
        case .annotations:
            return "Add and edit text notes, callouts, and shape annotations."
        case .advancedAxes:
            return "Configure secondary axes and broken axes."
        }
    }
}

struct PlotAdjustmentRailItem: Identifiable, Hashable {
    let category: PlotAdjustmentCategory

    var id: String {
        category.id
    }
}

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
            return "character.cursor.ibeam"
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

    var adjustmentCategory: PlotAdjustmentCategory {
        switch self {
        case .select:
            return .figure
        case .panZoom:
            return .axes
        case .dataCursor:
            return .figure
        case .fit:
            return .fit
        case .guide:
            return .guides
        case .text, .shape:
            return .annotations
        case .function:
            return .functions
        case .axisBreak, .secondaryAxis:
            return .advancedAxes
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
    func plotAdjustmentAvailability(for category: PlotAdjustmentCategory) -> ActionAvailability {
        switch category {
        case .figure:
            guard effectiveTemplateID != nil else {
                return .disabled("Import data before adjusting the figure.")
            }
            return .enabled()
        case .axes:
            guard effectiveTemplateID != nil else {
                return .disabled("Import data before adjusting axes.")
            }
            let axisOptionIDs: Set<String> = [
                "xscale",
                "yscale",
                "reverse_x",
                "x_min",
                "x_max",
                "y_min",
                "y_max",
                "x_tick_density",
                "x_tick_edge_labels",
                "y_tick_density",
                "y_tick_edge_labels",
                "baseline",
            ]
            guard !editableOptionIDs.isDisjoint(with: axisOptionIDs) else {
                return .disabled("This plot does not expose axis range controls.")
            }
            return .enabled()
        case .legend:
            guard canEditSeriesOrder else {
                return .disabled("This plot does not expose reorderable legend entries.")
            }
            return .enabled()
        case .guides:
            return referenceGuideAvailability
        case .fit:
            return fitOverlayAvailability
        case .functions:
            return analyticalLayerAvailability
        case .annotations:
            if textAnnotationAvailability.isEnabled || shapeAnnotationAvailability.isEnabled {
                return .enabled()
            }
            return .disabled(textAnnotationAvailability.reason ?? shapeAnnotationAvailability.reason ?? "Annotations are unavailable.")
        case .advancedAxes:
            let availabilities = [
                extraXAxisAvailability,
                extraYAxisAvailability,
                xAxisBreakAvailability,
                yAxisBreakAvailability,
            ]
            if availabilities.contains(where: \.isEnabled) {
                return .enabled()
            }
            return .disabled(
                availabilities.compactMap(\.reason).first
                    ?? "This plot does not expose secondary or broken axes."
            )
        }
    }

    func selectPlotAdjustmentCategory(_ category: PlotAdjustmentCategory) {
        guard plotAdjustmentAvailability(for: category).isEnabled else {
            return
        }

        selectedPlotAdjustmentCategory = category
        switch category {
        case .figure:
            selectCanvasSelection(.figure)
        case .axes:
            selectCanvasSelection(.axis(.x))
        case .legend:
            if let seriesID = seriesOrderLabels.first {
                selectPlotLayer(.series(seriesID))
            }
        case .guides:
            if let id = selectedReferenceGuideID ?? referenceGuides.last?.id {
                selectPlotLayer(.referenceGuide(id))
            } else {
                selectCanvasSelection(.figure)
            }
        case .fit:
            if fitOptions.enabled {
                selectPlotLayer(.fitOverlay)
            } else {
                selectCanvasSelection(.figure)
            }
        case .functions:
            if let layer = analyticalLayers.last {
                selectPlotLayer(.function(layer.id))
            } else {
                selectCanvasSelection(.figure)
            }
        case .annotations:
            if let id = selectedTextAnnotationID ?? textAnnotations.last?.id {
                selectPlotLayer(.textAnnotation(id))
            } else if let id = selectedShapeAnnotationID ?? shapeAnnotations.last?.id {
                selectPlotLayer(.shapeAnnotation(id))
            } else {
                selectCanvasSelection(.figure)
            }
        case .advancedAxes:
            selectCanvasSelection(.axis(.y))
        }
    }

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
        selectPlotAdjustmentCategory(tool.adjustmentCategory)
        switch tool {
        case .select, .panZoom:
            canvasInteractionMode = .select
        case .dataCursor:
            canvasInteractionMode = .select
            selectCanvasSelection(.figure)
        case .fit:
            canvasInteractionMode = .select
            if fitOptions.enabled {
                selectPlotLayer(.fitOverlay)
            }
        case .guide:
            if let id = selectedReferenceGuideID ?? referenceGuides.last?.id {
                canvasInteractionMode = .select
                selectPlotLayer(.referenceGuide(id))
            } else {
                beginCanvasPlacement(.guideLine(axisTarget: "y_primary"))
            }
        case .text:
            if let id = selectedTextAnnotationID ?? textAnnotations.last?.id {
                canvasInteractionMode = .select
                selectPlotLayer(.textAnnotation(id))
            } else {
                beginCanvasPlacement(.text)
            }
        case .shape:
            if let id = selectedShapeAnnotationID ?? shapeAnnotations.last?.id {
                canvasInteractionMode = .select
                selectPlotLayer(.shapeAnnotation(id))
            } else {
                beginCanvasPlacement(.rectangle)
            }
        case .function:
            canvasInteractionMode = .select
            if let layer = analyticalLayers.last {
                selectPlotLayer(.function(layer.id))
            }
        case .axisBreak:
            canvasInteractionMode = .select
            if xAxisBreakAvailability.isEnabled {
                selectCanvasSelection(.axis(.x))
            } else if yAxisBreakAvailability.isEnabled {
                selectCanvasSelection(.axis(.y))
            }
        case .secondaryAxis:
            canvasInteractionMode = .select
            selectCanvasSelection(.axis(.y))
        }
    }

    func selectCanvasSelection(_ selection: PlotCanvasSelection) {
        canvasSelection = selection
        switch selection {
        case .layer(let layer):
            selectPlotLayer(layer)
        case .figure, .axis, .dataPipeline:
            selectedSeriesQuickEditorID = nil
            selectedReferenceGuideID = nil
            selectedTextAnnotationID = nil
            selectedShapeAnnotationID = nil
        }
    }

    func selectPlotLayer(_ layer: PlotLayerSelection?) {
        guard let layer else {
            canvasSelection = .figure
            selectedSeriesQuickEditorID = nil
            selectedReferenceGuideID = nil
            selectedTextAnnotationID = nil
            selectedShapeAnnotationID = nil
            return
        }

        canvasSelection = .layer(layer)
        switch layer {
        case .referenceGuide(let id):
            selectedSeriesQuickEditorID = nil
            selectedReferenceGuideID = id
            selectedTextAnnotationID = nil
            selectedShapeAnnotationID = nil
        case .textAnnotation(let id):
            selectedSeriesQuickEditorID = nil
            selectedReferenceGuideID = nil
            selectedTextAnnotationID = id
            selectedShapeAnnotationID = nil
        case .shapeAnnotation(let id):
            selectedSeriesQuickEditorID = nil
            selectedReferenceGuideID = nil
            selectedTextAnnotationID = nil
            selectedShapeAnnotationID = id
        case .series(let id):
            selectedSeriesQuickEditorID = id
            selectedReferenceGuideID = nil
            selectedTextAnnotationID = nil
            selectedShapeAnnotationID = nil
        case .fitOverlay, .function:
            selectedSeriesQuickEditorID = nil
            selectedReferenceGuideID = nil
            selectedTextAnnotationID = nil
            selectedShapeAnnotationID = nil
        }
    }
}
