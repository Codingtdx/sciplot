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

    static let floatingPaletteTools: [PlotTool] = [
        .select,
        .panZoom,
        .fit,
        .guide,
        .text,
        .shape,
        .function,
        .axisBreak,
        .secondaryAxis,
    ]

    static let floatingPaletteToolGroups: [[PlotTool]] = [
        [
            .select,
            .panZoom,
        ],
        [
            .fit,
            .guide,
            .text,
            .shape,
            .function,
        ],
        [
            .axisBreak,
            .secondaryAxis,
        ],
    ]

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

    var opensToolPopover: Bool {
        switch self {
        case .guide, .text, .shape, .function:
            return true
        case .select, .panZoom, .dataCursor, .fit, .axisBreak, .secondaryAxis:
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

struct PlotFloatingToolPalette: View {
    @Bindable var session: PlotSession
    @State private var presentedTool: PlotTool?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(PlotTool.floatingPaletteToolGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Divider()
                        .frame(height: 24)
                        .padding(.horizontal, 2)
                }

                ForEach(group) { tool in
                    toolButton(tool)
                }
            }
        }
        .padding(7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private func toolButton(_ tool: PlotTool) -> some View {
        let availability = session.plotToolAvailability(for: tool)
        Button {
            session.activatePlotTool(tool)
            presentedTool = tool.opensToolPopover ? tool : nil
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(session.selectedPlotTool == tool ? Color.accentColor : Color.primary)
        .background {
            if session.selectedPlotTool == tool {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
            }
        }
        .disabled(!availability.isEnabled)
        .help(availability.reason ?? tool.help)
        .popover(isPresented: popoverBinding(for: tool), arrowEdge: .bottom) {
            PlotToolPopoverContent(
                session: session,
                tool: tool,
                dismiss: {
                    presentedTool = nil
                }
            )
        }
    }

    private func popoverBinding(for tool: PlotTool) -> Binding<Bool> {
        Binding(
            get: { presentedTool == tool },
            set: { isPresented in
                if !isPresented, presentedTool == tool {
                    presentedTool = nil
                }
            }
        )
    }
}

private struct PlotToolPopoverContent: View {
    @Bindable var session: PlotSession
    let tool: PlotTool
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tool.title, systemImage: tool.systemImage)
                .font(.headline)

            switch tool {
            case .guide:
                PlotGuideToolCreateForm(session: session, dismiss: dismiss)
            case .text:
                Button {
                    addText(displayStyle: "plain", connectorEnabled: false)
                } label: {
                    Label("Add Text", systemImage: "plus")
                }
                Button {
                    addText(displayStyle: "callout", connectorEnabled: true)
                } label: {
                    Label("Add Callout", systemImage: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                }
            case .shape:
                Button {
                    addShape(kind: "rectangle")
                } label: {
                    Label("Add Rectangle", systemImage: "rectangle")
                }
                Button {
                    addShape(kind: "ellipse")
                } label: {
                    Label("Add Ellipse", systemImage: "oval")
                }
                Button {
                    addShape(kind: "bracket")
                } label: {
                    Label("Add Bracket", systemImage: "square.split.diagonal")
                }
            case .function:
                Button {
                    addFunction()
                } label: {
                    Label("Add Function", systemImage: "plus")
                }
            case .select, .panZoom, .dataCursor, .fit, .axisBreak, .secondaryAxis:
                EmptyView()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(12)
        .frame(width: 190, alignment: .leading)
    }

    private func addText(displayStyle: String, connectorEnabled: Bool) {
        session.addTextAnnotation(displayStyle: displayStyle, connectorEnabled: connectorEnabled)
        if let id = session.selectedTextAnnotationID {
            session.selectPlotLayer(.textAnnotation(id))
        }
        dismiss()
    }

    private func addShape(kind: String) {
        session.addShapeAnnotation(kind: kind)
        if let id = session.selectedShapeAnnotationID {
            session.selectPlotLayer(.shapeAnnotation(id))
        }
        dismiss()
    }

    private func addFunction() {
        session.addAnalyticalFunctionLayer()
        if let layer = session.analyticalLayers.last {
            session.selectPlotLayer(.function(layer.id))
        }
        dismiss()
    }
}

private struct PlotGuideToolCreateForm: View {
    @Bindable var session: PlotSession
    let dismiss: () -> Void

    @State private var kind = "line"
    @State private var axisTarget = "y_primary"
    @State private var valueText = "0"
    @State private var startText = "0"
    @State private var endText = "1"
    @State private var labelText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $kind) {
                Text("Line").tag("line")
                Text("Region").tag("band")
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Picker("Axis", selection: $axisTarget) {
                Text("X").tag("x")
                Text("Primary Y").tag("y_primary")
                if session.hasActiveSecondaryYAxis || axisTarget == "y_secondary" {
                    Text("Secondary Y").tag("y_secondary")
                }
            }
            .pickerStyle(.menu)

            if kind == "line" {
                LabeledContent("Value") {
                    TextField("0", text: $valueText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 88)
                }
            } else {
                HStack(spacing: 8) {
                    LabeledContent("Start") {
                        TextField("0", text: $startText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                    }
                    LabeledContent("End") {
                        TextField("1", text: $endText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                    }
                }
            }

            LabeledContent("Label") {
                TextField("Optional", text: $labelText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 124)
            }

            Button {
                addGuide()
            } label: {
                Label(kind == "line" ? "Add Line" : "Add Region", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canCreate)
        }
    }

    private var canCreate: Bool {
        if kind == "line" {
            return parsed(valueText) != nil
        }
        guard let start = parsed(startText), let end = parsed(endText) else {
            return false
        }
        return start != end
    }

    private func addGuide() {
        session.addReferenceGuide(kind: kind, axisTarget: axisTarget)
        guard let id = session.selectedReferenceGuideID else {
            dismiss()
            return
        }

        let label = labelText.trimmingCharacters(in: .whitespacesAndNewlines)
        session.updateReferenceGuide(id: id, policy: .immediate) { guide in
            guide.axisTarget = axisTarget
            guide.label = label.isEmpty ? nil : label
            if kind == "line" {
                guide.value = parsed(valueText) ?? 0
                guide.start = nil
                guide.end = nil
            } else {
                guide.value = nil
                let start = parsed(startText) ?? 0
                let end = parsed(endText) ?? 1
                guide.start = min(start, end)
                guide.end = max(start, end)
            }
        }
        session.selectPlotLayer(.referenceGuide(id))
        dismiss()
    }

    private func parsed(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
