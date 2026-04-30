import SwiftUI

extension PlotInspectorView {
    func objectList(emptyMessage: String, rows: [PlotAdjustmentObjectRow]) -> some View {
        Group {
            if rows.isEmpty {
                InspectorEmptyState(message: emptyMessage)
            } else {
                VStack(spacing: 2) {
                    ForEach(rows) { row in
                        PlotAdjustmentObjectButton(
                            row: row,
                            isSelected: session.canvasSelection == .layer(row.selection)
                        ) {
                            session.selectPlotLayer(row.selection)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    var selectedGuideEditor: some View {
        if case .layer(let selection) = session.canvasSelection,
           case .referenceGuide = selection {
            PlotSelectedLayerEditorView(session: session, selection: selection)
        }
    }

    @ViewBuilder
    var selectedFunctionEditor: some View {
        if case .layer(let selection) = session.canvasSelection,
           case .function = selection {
            PlotSelectedLayerEditorView(session: session, selection: selection)
        }
    }

    @ViewBuilder
    var selectedAnnotationEditor: some View {
        if case .layer(let selection) = session.canvasSelection {
            switch selection {
            case .textAnnotation, .shapeAnnotation:
                PlotSelectedLayerEditorView(session: session, selection: selection)
            case .fitOverlay, .function, .referenceGuide, .series:
                EmptyView()
            }
        }
    }

    var annotationRows: [PlotAdjustmentObjectRow] {
        let textRows = session.textAnnotations.map {
            PlotAdjustmentObjectRow(
                id: "text:\($0.id)",
                title: annotationTitle($0),
                detail: $0.connectorEnabled ? "Callout" : "Text",
                systemImage: $0.connectorEnabled ? "text.bubble" : "character.cursor.ibeam",
                selection: .textAnnotation($0.id)
            )
        }
        let shapeRows = session.shapeAnnotations.map {
            PlotAdjustmentObjectRow(
                id: "shape:\($0.id)",
                title: shapeTitle($0),
                detail: shapeKindLabel($0.kind),
                systemImage: shapeSymbol($0.kind),
                selection: .shapeAnnotation($0.id)
            )
        }
        return textRows + shapeRows
    }

    func addShape(kind: String) {
        session.addShapeAnnotation(kind: kind)
        if let id = session.selectedShapeAnnotationID {
            session.selectPlotLayer(.shapeAnnotation(id))
        }
    }

    func functionTitle(_ layer: AnalyticalLayerPayload) -> String {
        let label = layer.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? layer.expression : label
    }

    func shapeTitle(_ annotation: ShapeAnnotationPayload) -> String {
        let label = annotation.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !label.isEmpty {
            return label
        }
        return shapeKindLabel(annotation.kind)
    }

    func shapeKindLabel(_ kind: String) -> String {
        switch kind {
        case "ellipse":
            return "Ellipse"
        case "bracket":
            return "Bracket"
        default:
            return "Rectangle"
        }
    }

    func shapeSymbol(_ kind: String) -> String {
        switch kind {
        case "ellipse":
            return "oval"
        case "bracket":
            return "square.split.diagonal"
        default:
            return "rectangle"
        }
    }
}
