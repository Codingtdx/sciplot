import AppKit
import SwiftUI

struct ComposerCanvasView: View {
    @Bindable var session: ComposerSession

    @State private var hoveredDropTarget: ComposerPlacementTarget?
    @State private var activeQuickActionToken: String?

    var body: some View {
        GeometryReader { geometry in
            let metrics = ComposerCanvasMetrics(project: session.project, size: geometry.size)
            let quickActionContext = boardQuickActionContext()

            ZStack(alignment: .topLeading) {
                ComposerCanvasBoard(metrics: metrics)

                ForEach(session.allGridCells) { cell in
                    ComposerCanvasCellView(
                        rect: metrics.rect(for: cell),
                        label: session.cellDisplayLabel(cell),
                        isSelected: session.selectedCells.contains(cell),
                        isMergeable: session.selectedCells.contains(cell) && session.canMergeSelectedCells,
                        isCoveredByRegion: session.regionCovering(cell: cell) != nil,
                        isHoveredDropTarget: hoveredDropTarget == .cell(cell),
                        canPlaceHere: session.activePlacementPanelID.map { session.canPlace(panelID: $0, in: .cell(cell)) } == true,
                        onTap: {
                            session.updateCellSelection(
                                cell,
                                additive: isCommandModifierPressed,
                                extend: isShiftModifierPressed
                            )
                        },
                        onSelectOnly: {
                            session.updateCellSelection(cell, additive: false, extend: false)
                        },
                        onClearSelection: {
                            session.clearTransientEditingState()
                        },
                        onMerge: {
                            session.mergeSelectedCells()
                        },
                        onPlaceHere: {
                            session.updateCellSelection(cell, additive: false, extend: false)
                            session.placeFocusedPanelInSelectedTarget()
                        }
                    )
                    .dropDestination(
                        for: ComposerPanelDragPayload.self,
                        action: { items, _ in
                            handleDrop(items, into: .cell(cell))
                        },
                        isTargeted: { isTargeted in
                            updateHoveredDropTarget(isTargeted, for: .cell(cell))
                        }
                    )
                }

                ForEach(freeRegions) { region in
                    ComposerFreeRegionView(
                        rect: metrics.rect(for: region),
                        title: session.regionSummary(region),
                        isSelected: session.selectedRegionID == region.id,
                        isHoveredDropTarget: hoveredDropTarget == .freeRegion(region.id),
                        canPlaceHere: session.activePlacementPanelID.map { session.canPlace(panelID: $0, in: .freeRegion(region.id)) } == true,
                        onTap: {
                            session.selectRegion(region.id)
                        },
                        onUnmerge: {
                            session.selectRegion(region.id)
                            session.unmergeSelectedRegion()
                        },
                        onPlaceHere: {
                            session.selectRegion(region.id)
                            session.placeFocusedPanelInSelectedTarget()
                        },
                        onClearSelection: {
                            session.clearTransientEditingState()
                        }
                    )
                    .dropDestination(
                        for: ComposerPanelDragPayload.self,
                        action: { items, _ in
                            handleDrop(items, into: .freeRegion(region.id))
                        },
                        isTargeted: { isTargeted in
                            updateHoveredDropTarget(isTargeted, for: .freeRegion(region.id))
                        }
                    )
                }

                if let graphSpanPanelID = graphSpanOverlayPanelID {
                    ForEach(session.graphCompatibleTargets(for: graphSpanPanelID), id: \.self) { target in
                        if let rect = rect(for: target, metrics: metrics) {
                            ComposerGraphSpanDropView(
                                rect: rect,
                                label: graphSpanLabel(for: target),
                                isHoveredDropTarget: hoveredDropTarget == target
                            )
                            .dropDestination(
                                for: ComposerPanelDragPayload.self,
                                action: { items, _ in
                                    handleDrop(items, into: target)
                                },
                                isTargeted: { isTargeted in
                                    updateHoveredDropTarget(isTargeted, for: target)
                                }
                            )
                        }
                    }
                }

                ForEach(visiblePanels) { panel in
                    ComposerPlacedPanelView(
                        panel: panel,
                        rect: metrics.rect(for: panel),
                        label: panel.kind == "graph" ? session.resolvedLabel(for: panel) : "",
                        isSelected: session.selectedPanelID == panel.id,
                        onTap: {
                            session.selectPanelOnCanvas(panel.id)
                        },
                        onRemoveFromBoard: {
                            session.selectPanelOnCanvas(panel.id)
                            session.removeSelectedPanelFromBoard()
                        },
                        onClearSelection: {
                            session.clearTransientEditingState()
                        },
                        onDragStarted: {
                            session.beginPanelDrag(panel.id)
                        },
                        onDragEnded: {
                            session.endPanelDrag(panel.id)
                        }
                    )
                }

                if let quickActionContext,
                   let quickActionRect = session.boardQuickActionRectMm(for: quickActionContext) {
                    Color.clear
                        .frame(
                            width: max(quickActionRect.width * metrics.scale, 1),
                            height: max(quickActionRect.height * metrics.scale, 1)
                        )
                        .position(metrics.rect(forMmRect: quickActionRect).center)
                        .id(quickActionContext.token)
                        .anchorPreference(
                            key: ComposerSelectionAnchorPreferenceKey.self,
                            value: .bounds
                        ) { anchor in
                            ComposerSelectionAnchorPreference(anchor: anchor, token: quickActionContext.token)
                        }
                }
            }
            .overlayPreferenceValue(ComposerSelectionAnchorPreferenceKey.self) { preference in
                GeometryReader { proxy in
                    if let preference,
                       let quickActionContext,
                       quickActionContext.token == preference.token {
                        let anchorRect = proxy[preference.anchor]
                        Color.clear
                            .frame(width: max(anchorRect.width, 1), height: max(anchorRect.height, 1))
                            .position(x: anchorRect.midX, y: anchorRect.midY)
                            .id(quickActionContext.token)
                            .popover(
                                isPresented: quickActionPopoverBinding(for: quickActionContext.token),
                                attachmentAnchor: .rect(.bounds),
                                arrowEdge: .bottom
                            ) {
                                ComposerBoardQuickActionPopover(
                                    session: session,
                                    context: quickActionContext
                                )
                            }
                    }
                }
            }
            .onChange(of: quickActionContext?.token) { _, newToken in
                hoveredDropTarget = nil
                activeQuickActionToken = newToken
            }
        }
    }

    private var visiblePanels: [ComposerPanelPayload] {
        session.visibleBoardPanels
    }

    private var freeRegions: [ComposerRegionPayload] {
        session.project.regions.filter { $0.kind == "free" }
    }

    private var graphSpanOverlayPanelID: String? {
        guard let panel = session.activePlacementPanel, panel.kind == "graph" else {
            return nil
        }
        let targets = session.graphCompatibleTargets(for: panel.id)
        return targets.isEmpty ? nil : panel.id
    }

    private var isCommandModifierPressed: Bool {
        NSApp.currentEvent?.modifierFlags.contains(.command) == true
    }

    private var isShiftModifierPressed: Bool {
        NSApp.currentEvent?.modifierFlags.contains(.shift) == true
    }

    private func boardQuickActionContext() -> ComposerBoardQuickActionState? {
        session.boardQuickActionState
    }

    private func quickActionPopoverBinding(for token: String) -> Binding<Bool> {
        Binding(
            get: { activeQuickActionToken == token },
            set: { isPresented in
                if !isPresented {
                    activeQuickActionToken = nil
                }
            }
        )
    }

    private func updateHoveredDropTarget(_ isTargeted: Bool, for target: ComposerPlacementTarget) {
        if isTargeted,
           let panelID = session.activePlacementPanelID,
           session.canPlace(panelID: panelID, in: target) {
            hoveredDropTarget = target
        } else if hoveredDropTarget == target {
            hoveredDropTarget = nil
        }
    }

    private func handleDrop(_ items: [ComposerPanelDragPayload], into target: ComposerPlacementTarget) -> Bool {
        guard let payload = items.first, session.canPlace(panelID: payload.panelID, in: target) else {
            return false
        }
        session.place(panelID: payload.panelID, in: target)
        hoveredDropTarget = nil
        return true
    }

    private func rect(for target: ComposerPlacementTarget, metrics: ComposerCanvasMetrics) -> CGRect? {
        guard let mmRect = session.targetRectMm(for: target) else {
            return nil
        }
        return metrics.rect(forMmRect: mmRect)
    }

    private func graphSpanLabel(for target: ComposerPlacementTarget) -> String {
        guard case let .graphSpan(_, colSpan, rowSpan) = target else {
            return ""
        }
        return "\(colSpan)x\(rowSpan) graph span"
    }
}

private struct ComposerCanvasBoard: View {
    let metrics: ComposerCanvasMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor),
                            Color(nsColor: .windowBackgroundColor),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )

            RoundedRectangle(cornerRadius: 24)
                .fill(.white)
                .frame(
                    width: metrics.frameRect.width,
                    height: metrics.frameRect.height
                )
                .position(metrics.frameRect.center)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.03), radius: 8, y: 4)
        }
    }
}

private struct ComposerCanvasCellView: View {
    let rect: CGRect
    let label: String
    let isSelected: Bool
    let isMergeable: Bool
    let isCoveredByRegion: Bool
    let isHoveredDropTarget: Bool
    let canPlaceHere: Bool
    let onTap: () -> Void
    let onSelectOnly: () -> Void
    let onClearSelection: () -> Void
    let onMerge: () -> Void
    let onPlaceHere: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(strokeColor, style: StrokeStyle(lineWidth: strokeWidth, dash: dashPattern))
            )
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .frame(width: rect.width, height: rect.height)
            .position(rect.center)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .onTapGesture(perform: onTap)
            .contextMenu {
                Button("Select Cell", action: onSelectOnly)
                Button("Merge", action: onMerge)
                    .disabled(!isMergeable)
                Button("Place Here", action: onPlaceHere)
                    .disabled(!canPlaceHere)
                Divider()
                Button("Clear Selection", action: onClearSelection)
            }
    }

    private var fillColor: Color {
        if isHoveredDropTarget {
            return .accentColor.opacity(0.18)
        }
        if isMergeable {
            return .accentColor.opacity(0.16)
        }
        if isSelected {
            return .accentColor.opacity(0.12)
        }
        if isCoveredByRegion {
            return Color.black.opacity(0.04)
        }
        return .clear
    }

    private var strokeColor: Color {
        if isHoveredDropTarget {
            return .accentColor
        }
        if isMergeable {
            return .accentColor.opacity(0.95)
        }
        if isSelected {
            return .accentColor.opacity(0.8)
        }
        return Color.black.opacity(0.08)
    }

    private var strokeWidth: CGFloat {
        isHoveredDropTarget || isSelected ? 2 : 1
    }

    private var dashPattern: [CGFloat] {
        (isHoveredDropTarget || isMergeable) ? [] : [5, 5]
    }
}

private struct ComposerFreeRegionView: View {
    let rect: CGRect
    let title: String
    let isSelected: Bool
    let isHoveredDropTarget: Bool
    let canPlaceHere: Bool
    let onTap: () -> Void
    let onUnmerge: () -> Void
    let onPlaceHere: () -> Void
    let onClearSelection: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(isHoveredDropTarget ? Color.accentColor.opacity(0.16) : Color.accentColor.opacity(isSelected ? 0.1 : 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(
                        isHoveredDropTarget ? Color.accentColor : Color.accentColor.opacity(isSelected ? 0.85 : 0.45),
                        style: StrokeStyle(lineWidth: isHoveredDropTarget || isSelected ? 2 : 1, dash: [8, 5])
                    )
            )
            .overlay(alignment: .topLeading) {
                Label(title, systemImage: "square.split.2x1")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(10)
            }
            .frame(width: rect.width, height: rect.height)
            .position(rect.center)
            .contentShape(RoundedRectangle(cornerRadius: 22))
            .onTapGesture(perform: onTap)
            .contextMenu {
                Button("Unmerge", action: onUnmerge)
                Button("Place Here", action: onPlaceHere)
                    .disabled(!canPlaceHere)
                Divider()
                Button("Clear Selection", action: onClearSelection)
            }
    }
}

private struct ComposerGraphSpanDropView: View {
    let rect: CGRect
    let label: String
    let isHoveredDropTarget: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(
                isHoveredDropTarget ? Color.accentColor : Color.accentColor.opacity(0.45),
                style: StrokeStyle(lineWidth: isHoveredDropTarget ? 2.5 : 1.5, dash: [10, 6])
            )
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isHoveredDropTarget ? Color.accentColor.opacity(0.14) : Color.accentColor.opacity(0.05))
            )
            .overlay {
                if isHoveredDropTarget {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .frame(width: rect.width, height: rect.height)
            .position(rect.center)
    }
}

private struct ComposerPlacedPanelView: View {
    let panel: ComposerPanelPayload
    let rect: CGRect
    let label: String
    let isSelected: Bool
    let onTap: () -> Void
    let onRemoveFromBoard: () -> Void
    let onClearSelection: () -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ComposerPanelThumbnailView(
                url: URL(fileURLWithPath: panel.filePath),
                size: rect.size,
                cornerRadius: 20
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2.5 : 1)
            )

            if panel.kind == "graph", !label.isEmpty {
                Text(label)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .offset(x: -10, y: -10)
            }

        }
        .frame(width: rect.width, height: rect.height)
        .position(rect.center)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(isSelected ? 0.08 : 0.03), radius: 10, y: 6)
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button("Remove From Board", action: onRemoveFromBoard)
            Divider()
            Button("Clear Selection", action: onClearSelection)
        }
        .draggable(
            ComposerPanelDragPayload(panelID: panel.id, sourceSurface: .canvas)
        ) {
            ComposerPanelDragPreview(panel: panel)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onDragStarted() }
                .onEnded { _ in onDragEnded() }
        )
    }

    private var borderColor: Color {
        if isSelected {
            return .accentColor
        }
        return Color.black.opacity(0.12)
    }
}

private struct ComposerPanelDragPreview: View {
    let panel: ComposerPanelPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(panel.kind == "graph" ? "Graph" : "Asset", systemImage: panel.kind == "graph" ? "chart.xyaxis.line" : "photo")
                .font(.caption.weight(.semibold))
            Text(URL(fileURLWithPath: panel.filePath).lastPathComponent)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ComposerBoardQuickActionPopover: View {
    @Bindable var session: ComposerSession
    let context: ComposerBoardQuickActionState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch context {
            case let .mergeableMultiCellSelection(selection):
                Text(selection.cellCount > 1 ? "\(selection.colSpan)x\(selection.rowSpan) selection" : "Cell \(session.cellDisplayLabel(selection.origin))")
                    .font(.headline)

                Text(session.mergeGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if selection.cellCount > 1 {
                    Button("Merge") {
                        session.mergeSelectedCells()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canMergeSelectedCells)
                }

                if session.canPlaceFocusedPanelInSelectedTarget {
                    Button(session.placementActionTitle) {
                        session.placeFocusedPanelInSelectedTarget()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Clear Selection") {
                    session.clearTransientEditingState()
                }
                .buttonStyle(.bordered)

            case let .emptyMergedRegion(region):
                Text("Merged region")
                    .font(.headline)

                Text(session.regionSummary(region))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Unmerge") {
                    session.selectRegion(region.id)
                    session.unmergeSelectedRegion()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.canUnmergeSelectedRegion)

                if session.canPlaceFocusedPanelInSelectedTarget {
                    Button(session.placementActionTitle) {
                        session.selectRegion(region.id)
                        session.placeFocusedPanelInSelectedTarget()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Clear Selection") {
                    session.clearTransientEditingState()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(minWidth: 220, alignment: .leading)
    }
}

private struct ComposerCanvasMetrics {
    let project: ComposerRequestPayload
    let size: CGSize
    let canvasRect: CGRect
    let frameRect: CGRect
    let scale: CGFloat

    init(project: ComposerRequestPayload, size: CGSize, padding: CGFloat = 24) {
        self.project = project
        self.size = size

        let availableWidth = max(size.width - padding * 2, 240)
        let availableHeight = max(size.height - padding * 2, 220)
        let canvasWidth = CGFloat(project.canvasWidthMm)
        let canvasHeight = CGFloat(project.canvasHeightMm)
        let scale = min(availableWidth / canvasWidth, availableHeight / canvasHeight)
        let scaledWidth = canvasWidth * scale
        let scaledHeight = canvasHeight * scale
        let origin = CGPoint(
            x: (size.width - scaledWidth) / 2,
            y: (size.height - scaledHeight) / 2
        )

        self.scale = scale
        self.canvasRect = CGRect(origin: origin, size: CGSize(width: scaledWidth, height: scaledHeight))
        self.frameRect = CGRect(
            x: origin.x + CGFloat(project.layoutGrid.frameXMm) * scale,
            y: origin.y + CGFloat(project.layoutGrid.frameYMm) * scale,
            width: CGFloat(project.layoutGrid.frameWidthMm) * scale,
            height: CGFloat(project.layoutGrid.frameHeightMm) * scale
        )
    }

    func rect(for cell: ComposerGridCell) -> CGRect {
        rect(
            xMm: project.layoutGrid.frameXMm + Double(cell.col) * project.layoutGrid.cellWidthMm,
            yMm: project.layoutGrid.frameYMm + Double(cell.row) * project.layoutGrid.cellHeightMm,
            wMm: project.layoutGrid.cellWidthMm,
            hMm: project.layoutGrid.cellHeightMm
        )
    }

    func rect(for region: ComposerRegionPayload) -> CGRect {
        rect(
            xMm: project.layoutGrid.frameXMm + Double(region.col) * project.layoutGrid.cellWidthMm,
            yMm: project.layoutGrid.frameYMm + Double(region.row) * project.layoutGrid.cellHeightMm,
            wMm: Double(region.colSpan) * project.layoutGrid.cellWidthMm,
            hMm: Double(region.rowSpan) * project.layoutGrid.cellHeightMm
        )
    }

    func rect(for panel: ComposerPanelPayload) -> CGRect {
        rect(xMm: panel.xMm, yMm: panel.yMm, wMm: panel.wMm, hMm: panel.hMm)
    }

    func rect(forMmRect mmRect: CGRect) -> CGRect {
        rect(
            xMm: mmRect.minX,
            yMm: mmRect.minY,
            wMm: mmRect.width,
            hMm: mmRect.height
        )
    }

    private func rect(xMm: Double, yMm: Double, wMm: Double, hMm: Double) -> CGRect {
        CGRect(
            x: canvasRect.minX + CGFloat(xMm) * scale,
            y: canvasRect.minY + CGFloat(yMm) * scale,
            width: CGFloat(wMm) * scale,
            height: CGFloat(hMm) * scale
        )
    }
}

private struct ComposerSelectionAnchorPreference {
    let anchor: Anchor<CGRect>
    let token: String
}

private struct ComposerSelectionAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: ComposerSelectionAnchorPreference? = nil

    static func reduce(value: inout ComposerSelectionAnchorPreference?, nextValue: () -> ComposerSelectionAnchorPreference?) {
        value = nextValue() ?? value
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
