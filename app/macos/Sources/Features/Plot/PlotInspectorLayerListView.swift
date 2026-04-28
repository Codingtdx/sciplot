import SwiftUI

struct PlotInspectorLayerListView: View {
    @Bindable var session: PlotSession
    @Binding var selection: PlotLayerSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            layerActions
            layerList
        }
        .onAppear {
            synchronizeSelection()
        }
    }

    private var layerActions: some View {
        InspectorSection(title: "Add") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button("Guide") {
                        session.addReferenceGuide(kind: "line")
                        if let id = session.selectedReferenceGuideID {
                            selection = .referenceGuide(id)
                        }
                    }
                    .disabled(!session.referenceGuideAvailability.isEnabled)
                    .help(session.referenceGuideAvailability.reason ?? "Add a reference guide.")

                    Button("Note") {
                        session.addTextAnnotation()
                        if let id = session.selectedTextAnnotationID {
                            selection = .textAnnotation(id)
                        }
                    }
                    .disabled(!session.textAnnotationAvailability.isEnabled)
                    .help(session.textAnnotationAvailability.reason ?? "Add a text annotation.")

                    Button("Shape") {
                        session.addShapeAnnotation(kind: "rectangle")
                        if let id = session.selectedShapeAnnotationID {
                            selection = .shapeAnnotation(id)
                        }
                    }
                    .disabled(!session.shapeAnnotationAvailability.isEnabled)
                    .help(session.shapeAnnotationAvailability.reason ?? "Add a shape annotation.")
                }
                HStack(spacing: 8) {
                    Button("Function") {
                        session.addAnalyticalFunctionLayer()
                        if let layer = session.analyticalLayers.last {
                            selection = .function(layer.id)
                        }
                    }
                    .disabled(!session.analyticalLayerAvailability.isEnabled)
                    .help(session.analyticalLayerAvailability.reason ?? "Add a function layer.")

                    Button("Region") {
                        session.addReferenceGuide(kind: "band")
                        if let id = session.selectedReferenceGuideID {
                            selection = .referenceGuide(id)
                        }
                    }
                    .disabled(!session.referenceGuideAvailability.isEnabled)
                    .help(session.referenceGuideAvailability.reason ?? "Add a reference region.")

                    Button("Callout") {
                        session.addTextAnnotation(displayStyle: "callout", connectorEnabled: true)
                        if let id = session.selectedTextAnnotationID {
                            selection = .textAnnotation(id)
                        }
                    }
                    .disabled(!session.textAnnotationAvailability.isEnabled)
                    .help(session.textAnnotationAvailability.reason ?? "Add a callout annotation.")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var layerList: some View {
        InspectorSection(title: "Objects") {
            if isLayerListEmpty {
                InspectorEmptyState(message: "No layers")
            } else {
                VStack(spacing: 2) {
                    if session.supportsFitOverlayControls {
                        layerRow(
                            title: "Fit Overlay",
                            subtitle: session.fitModelLabel,
                            systemImage: "chart.xyaxis.line",
                            isEnabled: fitEnabledBinding,
                            isSelected: selection == .fitOverlay,
                            onSelect: {
                                select(.fitOverlay)
                            },
                            onDelete: nil
                        )
                    }

                    ForEach(session.analyticalLayers) { layer in
                        layerRow(
                            title: functionTitle(layer),
                            subtitle: "Function",
                            systemImage: "function",
                            isEnabled: analyticalLayerEnabledBinding(id: layer.id),
                            isSelected: selection == .function(layer.id),
                            onSelect: {
                                select(.function(layer.id))
                            },
                            onDelete: {
                                session.removeAnalyticalLayer(id: layer.id)
                                clearIfSelected(.function(layer.id))
                            }
                        )
                    }

                    ForEach(session.referenceGuides) { guide in
                        layerRow(
                            title: referenceGuideTitle(guide),
                            subtitle: guide.kind == "band" ? "Region" : "Guide",
                            systemImage: guide.kind == "band" ? "rectangle.dashed" : "ruler",
                            isEnabled: referenceGuideEnabledBinding(id: guide.id),
                            isSelected: selection == .referenceGuide(guide.id),
                            onSelect: {
                                select(.referenceGuide(guide.id))
                            },
                            onDelete: {
                                session.removeReferenceGuide(id: guide.id)
                                clearIfSelected(.referenceGuide(guide.id))
                            }
                        )
                    }

                    ForEach(session.textAnnotations) { annotation in
                        layerRow(
                            title: textAnnotationTitle(annotation),
                            subtitle: annotation.connectorEnabled ? "Callout" : "Text",
                            systemImage: annotation.connectorEnabled ? "text.bubble" : "character.cursor.ibeam",
                            isEnabled: textAnnotationEnabledBinding(id: annotation.id),
                            isSelected: selection == .textAnnotation(annotation.id),
                            onSelect: {
                                select(.textAnnotation(annotation.id))
                            },
                            onDelete: {
                                session.removeTextAnnotation(id: annotation.id)
                                clearIfSelected(.textAnnotation(annotation.id))
                            }
                        )
                    }

                    ForEach(session.shapeAnnotations) { annotation in
                        layerRow(
                            title: shapeAnnotationTitle(annotation),
                            subtitle: shapeKindLabel(annotation.kind),
                            systemImage: shapeSymbol(annotation.kind),
                            isEnabled: shapeAnnotationEnabledBinding(id: annotation.id),
                            isSelected: selection == .shapeAnnotation(annotation.id),
                            onSelect: {
                                select(.shapeAnnotation(annotation.id))
                            },
                            onDelete: {
                                session.removeShapeAnnotation(id: annotation.id)
                                clearIfSelected(.shapeAnnotation(annotation.id))
                            }
                        )
                    }

                    ForEach(session.seriesOrderLabels, id: \.self) { seriesID in
                        layerRow(
                            title: seriesID,
                            subtitle: "Legend entry",
                            systemImage: "list.bullet.rectangle",
                            isEnabled: nil,
                            isSelected: selection == .series(seriesID),
                            onSelect: {
                                select(.series(seriesID))
                            },
                            onDelete: nil
                        )
                    }
                }
            }
        }
    }

    private var isLayerListEmpty: Bool {
        !session.supportsFitOverlayControls
            && session.analyticalLayers.isEmpty
            && session.referenceGuides.isEmpty
            && session.textAnnotations.isEmpty
            && session.shapeAnnotations.isEmpty
            && session.seriesOrderLabels.isEmpty
    }

    private func layerRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isEnabled: Binding<Bool>?,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onDelete: (() -> Void)?
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                }
            }
            .buttonStyle(.plain)

            if let isEnabled {
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func synchronizeSelection() {
        if let id = session.selectedReferenceGuideID {
            selection = .referenceGuide(id)
        } else if let id = session.selectedTextAnnotationID {
            selection = .textAnnotation(id)
        } else if let id = session.selectedShapeAnnotationID {
            selection = .shapeAnnotation(id)
        }
    }

    private func select(_ layer: PlotLayerSelection) {
        selection = layer
        switch layer {
        case .referenceGuide(let id):
            session.selectedReferenceGuideID = id
            session.selectedTextAnnotationID = nil
            session.selectedShapeAnnotationID = nil
        case .textAnnotation(let id):
            session.selectedReferenceGuideID = nil
            session.selectedTextAnnotationID = id
            session.selectedShapeAnnotationID = nil
        case .shapeAnnotation(let id):
            session.selectedReferenceGuideID = nil
            session.selectedTextAnnotationID = nil
            session.selectedShapeAnnotationID = id
        case .fitOverlay, .function, .series:
            session.selectedReferenceGuideID = nil
            session.selectedTextAnnotationID = nil
            session.selectedShapeAnnotationID = nil
        }
    }

    private func clearIfSelected(_ layer: PlotLayerSelection) {
        if selection == layer {
            selection = nil
        }
    }

    private func functionTitle(_ layer: AnalyticalLayerPayload) -> String {
        let label = layer.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? layer.expression : label
    }

    private func referenceGuideTitle(_ guide: ReferenceGuidePayload) -> String {
        let label = guide.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !label.isEmpty {
            return label
        }
        return guide.kind == "band" ? "Region" : "Line"
    }

    private func textAnnotationTitle(_ annotation: TextAnnotationPayload) -> String {
        let trimmed = annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Annotation" : trimmed
    }

    private func shapeAnnotationTitle(_ annotation: ShapeAnnotationPayload) -> String {
        let label = annotation.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !label.isEmpty {
            return label
        }
        return shapeKindLabel(annotation.kind)
    }

    private func shapeKindLabel(_ kind: String) -> String {
        switch kind {
        case "ellipse":
            return "Ellipse"
        case "bracket":
            return "Bracket"
        default:
            return "Rectangle"
        }
    }

    private func shapeSymbol(_ kind: String) -> String {
        switch kind {
        case "ellipse":
            return "circle.dashed"
        case "bracket":
            return "square.split.diagonal.2x2"
        default:
            return "rectangle.dashed"
        }
    }

    private var fitEnabledBinding: Binding<Bool> {
        Binding {
            session.fitOptions.enabled
        } set: { enabled in
            session.updateFitEnabled(enabled)
        }
    }

    private func analyticalLayer(_ id: String) -> AnalyticalLayerPayload {
        session.analyticalLayers.first(where: { $0.id == id }) ?? AnalyticalLayerPayload(id: id)
    }

    private func analyticalLayerEnabledBinding(id: String) -> Binding<Bool> {
        Binding {
            analyticalLayer(id).enabled
        } set: { newValue in
            session.updateAnalyticalLayer(id: id, policy: .immediate) { $0.enabled = newValue }
        }
    }

    private func referenceGuide(_ id: String) -> ReferenceGuidePayload {
        session.referenceGuides.first(where: { $0.id == id }) ?? ReferenceGuidePayload(id: id)
    }

    private func referenceGuideEnabledBinding(id: String) -> Binding<Bool> {
        Binding {
            referenceGuide(id).enabled
        } set: { enabled in
            session.updateReferenceGuide(id: id) { $0.enabled = enabled }
        }
    }

    private func textAnnotation(_ id: String) -> TextAnnotationPayload {
        session.textAnnotations.first(where: { $0.id == id }) ?? TextAnnotationPayload(id: id)
    }

    private func textAnnotationEnabledBinding(id: String) -> Binding<Bool> {
        Binding {
            textAnnotation(id).enabled
        } set: { enabled in
            session.updateTextAnnotation(id: id) { $0.enabled = enabled }
        }
    }

    private func shapeAnnotation(_ id: String) -> ShapeAnnotationPayload {
        session.shapeAnnotations.first(where: { $0.id == id }) ?? ShapeAnnotationPayload(id: id)
    }

    private func shapeAnnotationEnabledBinding(id: String) -> Binding<Bool> {
        Binding {
            shapeAnnotation(id).enabled
        } set: { enabled in
            session.updateShapeAnnotation(id: id) { $0.enabled = enabled }
        }
    }
}
