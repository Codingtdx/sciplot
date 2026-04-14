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
                        isHoveredDropTarget: hoveredDropTarget == .cell(cell)
                    )
                    .allowsHitTesting(false)
                }

                ForEach(freeRegions) { region in
                    ComposerFreeRegionView(
                        rect: metrics.rect(for: region),
                        title: session.regionSummary(region),
                        isSelected: session.selectedRegionID == region.id,
                        isHoveredDropTarget: hoveredDropTarget == .freeRegion(region.id)
                    )
                    .allowsHitTesting(false)
                }

                if let graphSpanPanelID = graphSpanOverlayPanelID {
                    ForEach(session.graphCompatibleTargets(for: graphSpanPanelID), id: \.self) { target in
                        if let rect = rect(for: target, metrics: metrics) {
                            ComposerGraphSpanDropView(
                                rect: rect,
                                label: graphSpanLabel(for: target),
                                isHoveredDropTarget: hoveredDropTarget == target
                            )
                            .allowsHitTesting(false)
                        }
                    }
                }

                ForEach(visiblePanels) { panel in
                    ComposerPlacedPanelView(
                        panel: panel,
                        rect: metrics.rect(for: panel),
                        label: panel.kind == "graph" ? session.resolvedLabel(for: panel) : "",
                        isSelected: session.selectedPanelID == panel.id
                    )
                    .allowsHitTesting(false)
                }

                ComposerBoardInteractionLayer(
                    session: session,
                    metrics: metrics,
                    visiblePanels: visiblePanels,
                    freeRegions: freeRegions,
                    hoveredDropTarget: $hoveredDropTarget
                )
                .frame(width: metrics.frameRect.width, height: metrics.frameRect.height)
                .position(metrics.frameRect.center)

                if let quickActionContext,
                   let quickActionRect = session.boardQuickActionRectMm(for: quickActionContext) {
                    Color.clear
                        .frame(
                            width: max(quickActionRect.width * metrics.scale, 1),
                            height: max(quickActionRect.height * metrics.scale, 1)
                        )
                        .position(metrics.rect(forMmRect: quickActionRect).center)
                        .id(quickActionContext.token)
                        .allowsHitTesting(false)
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
                            .allowsHitTesting(false)
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
            .animation(MotionTokens.selection, value: isSelected)
            .animation(MotionTokens.selection, value: isHoveredDropTarget)
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
            .animation(MotionTokens.selection, value: isSelected)
            .animation(MotionTokens.selection, value: isHoveredDropTarget)
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
        .animation(MotionTokens.selection, value: isSelected)
    }

    private var borderColor: Color {
        if isSelected {
            return .accentColor
        }
        return Color.black.opacity(0.12)
    }
}

private struct ComposerBoardQuickActionPopover: View {
    @Bindable var session: ComposerSession
    let context: ComposerBoardQuickActionState

    var body: some View {
        let presentation = session.editPresentation

        VStack(alignment: .leading, spacing: 12) {
            switch context {
            case let .mergeableMultiCellSelection(selection):
                Text(selection.cellCount > 1 ? "\(selection.colSpan)x\(selection.rowSpan) selection" : "Cell \(session.cellDisplayLabel(selection.origin))")
                    .font(.headline)

                if selection.cellCount > 1 {
                    Button("Merge") {
                        session.mergeSelectedCells()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!presentation.mergeSelectedCellsAvailability.isEnabled)
                    .help(
                        presentation.mergeSelectedCellsAvailability.reason
                            ?? "Merge the selected empty cells into one free region."
                    )
                }

                if session.shouldShowPlacementAction {
                    Button(session.placementActionTitle) {
                        session.placeFocusedPanelInSelectedTarget()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.placementAvailability.isEnabled)
                    .help(
                        presentation.placementAvailability.reason
                            ?? "Place the focused panel into the selected target."
                    )
                }

                Button("Clear Selection") {
                    session.clearTransientEditingState()
                }
                .buttonStyle(.bordered)

            case let .emptyMergedRegion(region):
                Text(session.regionSummary(region))
                    .font(.headline)

                Button("Unmerge") {
                    session.selectRegion(region.id)
                    session.unmergeSelectedRegion()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!presentation.unmergeSelectedRegionAvailability.isEnabled)
                .help(
                    presentation.unmergeSelectedRegionAvailability.reason
                        ?? "Return the selected free region back to its underlying grid cells."
                )

                if session.shouldShowPlacementAction {
                    Button(session.placementActionTitle) {
                        session.selectRegion(region.id)
                        session.placeFocusedPanelInSelectedTarget()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.placementAvailability.isEnabled)
                    .help(
                        presentation.placementAvailability.reason
                            ?? "Place the focused panel into the selected target."
                    )
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

private enum ComposerBoardInputState {
    case idle
    case panelInteraction(panelID: String, startPoint: CGPoint, canDrag: Bool, didMove: Bool)
    case cellSelection(mode: ComposerBoardCellSelectionMode, lastCell: ComposerGridCell)
    case regionSelection(regionID: String)
}

private enum ComposerBoardCellSelectionMode {
    case dragRectangle
    case extendFromAnchor
    case toggle
}

private enum ComposerBoardHitTarget {
    case panel(String)
    case region(String)
    case cell(ComposerGridCell)
}

private struct ComposerBoardModifierState {
    let additive: Bool
    let extend: Bool
}

@MainActor
private struct ComposerBoardInteractionLayer: View {
    @Bindable var session: ComposerSession
    let metrics: ComposerCanvasMetrics
    let visiblePanels: [ComposerPanelPayload]
    let freeRegions: [ComposerRegionPayload]
    @Binding var hoveredDropTarget: ComposerPlacementTarget?

    @State private var interactionState: ComposerBoardInputState = .idle

    var body: some View {
        let boardGeometry = metrics.boardGeometry

        Color.clear
            .contentShape(Rectangle())
            .gesture(boardGesture(boardGeometry: boardGeometry))
            .contextMenu {
                if session.canMergeSelectedCells {
                    Button("Merge") {
                        session.mergeSelectedCells()
                    }
                }

                if session.canUnmergeSelectedRegion {
                    Button("Unmerge") {
                        session.unmergeSelectedRegion()
                    }
                }

                if session.canPlaceFocusedPanelInSelectedTarget {
                    Button(session.placementActionTitle) {
                        session.placeFocusedPanelInSelectedTarget()
                    }
                }

                if !session.selectedCells.isEmpty || session.selectedFreeRegion != nil || session.selectedPanel != nil {
                    Divider()
                    Button("Clear Selection") {
                        session.clearTransientEditingState()
                    }
                }
            }
            .dropDestination(for: ComposerPanelDragPayload.self) { items, location in
                handleExternalDrop(items, at: location, boardGeometry: boardGeometry)
            } isTargeted: { isTargeted in
                if !isTargeted {
                    hoveredDropTarget = nil
                }
            }
            .onDisappear {
                hoveredDropTarget = nil
                interactionState = .idle
            }
    }

    private func boardGesture(boardGeometry: ComposerBoardGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if case .idle = interactionState {
                    beginInteraction(at: value.startLocation, boardGeometry: boardGeometry)
                }
                updateInteraction(at: value.location, boardGeometry: boardGeometry)
            }
            .onEnded { value in
                if case .idle = interactionState {
                    beginInteraction(at: value.startLocation, boardGeometry: boardGeometry)
                }
                finishInteraction(at: value.location, boardGeometry: boardGeometry)
            }
    }

    private func beginInteraction(at point: CGPoint, boardGeometry: ComposerBoardGeometry) {
        hoveredDropTarget = nil

        switch hitTarget(at: point, boardGeometry: boardGeometry) {
        case let .panel(panelID):
            guard let panel = visiblePanels.first(where: { $0.id == panelID }) else {
                interactionState = .idle
                return
            }
            session.selectPanelOnCanvas(panelID)
            if !panel.locked {
                session.beginPanelDrag(panelID)
            }
            interactionState = .panelInteraction(
                panelID: panelID,
                startPoint: point,
                canDrag: !panel.locked,
                didMove: false
            )

        case let .region(regionID):
            session.selectRegion(regionID)
            interactionState = .regionSelection(regionID: regionID)

        case let .cell(cell):
            let modifiers = currentModifierState()
            if modifiers.extend {
                session.extendCellSelection(to: cell)
                interactionState = .cellSelection(mode: .extendFromAnchor, lastCell: cell)
            } else if modifiers.additive {
                session.toggleCellSelection(cell)
                interactionState = .cellSelection(mode: .toggle, lastCell: cell)
            } else {
                session.beginCellDragSelection(at: cell)
                interactionState = .cellSelection(mode: .dragRectangle, lastCell: cell)
            }

        case nil:
            interactionState = .idle
        }
    }

    private func currentModifierState() -> ComposerBoardModifierState {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        return ComposerBoardModifierState(
            additive: flags.contains(.command),
            extend: flags.contains(.shift)
        )
    }

    private func updateInteraction(at point: CGPoint, boardGeometry: ComposerBoardGeometry) {
        switch interactionState {
        case let .panelInteraction(panelID, startPoint, canDrag, didMove):
            guard canDrag else {
                return
            }
            let moved = didMove || startPoint.distance(to: point) >= 4
            if moved {
                hoveredDropTarget = resolvePlacementTarget(
                    for: panelID,
                    at: point,
                    boardGeometry: boardGeometry
                )
            }
            interactionState = .panelInteraction(
                panelID: panelID,
                startPoint: startPoint,
                canDrag: canDrag,
                didMove: moved
            )

        case let .cellSelection(mode, lastCell):
            guard let cell = boardGeometry.clampedCell(at: point), cell != lastCell else {
                return
            }
            switch mode {
            case .dragRectangle:
                session.updateCellDragSelection(to: cell)
            case .extendFromAnchor:
                session.extendCellSelection(to: cell)
            case .toggle:
                break
            }
            interactionState = .cellSelection(mode: mode, lastCell: cell)

        case .regionSelection, .idle:
            break
        }
    }

    private func finishInteraction(at point: CGPoint, boardGeometry: ComposerBoardGeometry) {
        defer {
            hoveredDropTarget = nil
            interactionState = .idle
        }

        switch interactionState {
        case let .panelInteraction(panelID, _, canDrag, didMove):
            if canDrag,
               didMove,
               let target = resolvePlacementTarget(for: panelID, at: point, boardGeometry: boardGeometry)
            {
                session.place(panelID: panelID, in: target)
            }
            session.endPanelDrag(panelID)

        case .cellSelection, .regionSelection, .idle:
            break
        }
    }

    private func handleExternalDrop(
        _ items: [ComposerPanelDragPayload],
        at point: CGPoint,
        boardGeometry: ComposerBoardGeometry
    ) -> Bool {
        guard let payload = items.first,
              let target = resolvePlacementTarget(for: payload.panelID, at: point, boardGeometry: boardGeometry),
              session.canPlace(panelID: payload.panelID, in: target)
        else {
            hoveredDropTarget = nil
            return false
        }

        session.place(panelID: payload.panelID, in: target)
        session.endPanelDrag(payload.panelID)
        hoveredDropTarget = nil
        return true
    }

    private func hitTarget(at point: CGPoint, boardGeometry: ComposerBoardGeometry) -> ComposerBoardHitTarget? {
        if let panel = panel(at: point, excluding: nil, boardGeometry: boardGeometry) {
            return .panel(panel.id)
        }
        if let region = freeRegion(at: point, boardGeometry: boardGeometry) {
            return .region(region.id)
        }
        if let cell = boardGeometry.cell(at: point) {
            return .cell(cell)
        }
        return nil
    }

    private func resolvePlacementTarget(
        for panelID: String,
        at point: CGPoint,
        boardGeometry: ComposerBoardGeometry
    ) -> ComposerPlacementTarget? {
        if let occupant = panel(at: point, excluding: panelID, boardGeometry: boardGeometry),
           let target = session.placementTargetForPanelID(occupant.id),
           session.canPlace(panelID: panelID, in: target)
        {
            return target
        }

        if let graphTarget = graphSpanTarget(for: panelID, at: point, boardGeometry: boardGeometry),
           session.canPlace(panelID: panelID, in: graphTarget)
        {
            return graphTarget
        }

        if let region = freeRegion(at: point, boardGeometry: boardGeometry) {
            let target = ComposerPlacementTarget.freeRegion(region.id)
            if session.canPlace(panelID: panelID, in: target) {
                return target
            }
        }

        if let cell = boardGeometry.clampedCell(at: point) {
            let target = ComposerPlacementTarget.cell(cell)
            if session.canPlace(panelID: panelID, in: target) {
                return target
            }
        }

        return nil
    }

    private func graphSpanTarget(
        for panelID: String,
        at point: CGPoint,
        boardGeometry: ComposerBoardGeometry
    ) -> ComposerPlacementTarget? {
        let candidates = session.graphCompatibleTargets(for: panelID).compactMap { target -> (ComposerPlacementTarget, CGFloat)? in
            guard let rect = rect(for: target, boardGeometry: boardGeometry),
                  rect.contains(point)
            else {
                return nil
            }
            return (target, rect.center.distance(to: point))
        }

        return candidates.min { lhs, rhs in
            lhs.1 < rhs.1
        }?.0
    }

    private func panel(
        at point: CGPoint,
        excluding excludedPanelID: String?,
        boardGeometry: ComposerBoardGeometry
    ) -> ComposerPanelPayload? {
        visiblePanels
            .reversed()
            .first { panel in
                panel.id != excludedPanelID && boardGeometry.rect(for: panel).contains(point)
            }
    }

    private func freeRegion(at point: CGPoint, boardGeometry: ComposerBoardGeometry) -> ComposerRegionPayload? {
        freeRegions
            .reversed()
            .first { region in
                boardGeometry.rect(for: region).contains(point)
            }
    }

    private func rect(
        for target: ComposerPlacementTarget,
        boardGeometry: ComposerBoardGeometry
    ) -> CGRect? {
        switch target {
        case let .cell(cell):
            return boardGeometry.rect(for: cell)
        case let .freeRegion(regionID):
            guard let region = freeRegions.first(where: { $0.id == regionID }) else {
                return nil
            }
            return boardGeometry.rect(for: region)
        case let .graphSpan(origin, colSpan, rowSpan):
            return boardGeometry.rect(
                for: ComposerCellSelection(origin: origin, colSpan: colSpan, rowSpan: rowSpan)
            )
        }
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

    var boardGeometry: ComposerBoardGeometry {
        ComposerBoardGeometry(project: project, boardSize: frameRect.size)
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

struct ComposerBoardGeometry {
    let project: ComposerRequestPayload
    let boardSize: CGSize
    let scale: CGFloat

    init(project: ComposerRequestPayload, boardSize: CGSize) {
        self.project = project
        self.boardSize = boardSize
        let frameWidth = max(CGFloat(project.layoutGrid.frameWidthMm), 1)
        self.scale = boardSize.width / frameWidth
    }

    func rect(for cell: ComposerGridCell) -> CGRect {
        CGRect(
            x: CGFloat(cell.col) * cellWidth,
            y: CGFloat(cell.row) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
    }

    func rect(for selection: ComposerCellSelection) -> CGRect {
        CGRect(
            x: CGFloat(selection.origin.col) * cellWidth,
            y: CGFloat(selection.origin.row) * cellHeight,
            width: CGFloat(selection.colSpan) * cellWidth,
            height: CGFloat(selection.rowSpan) * cellHeight
        )
    }

    func rect(for region: ComposerRegionPayload) -> CGRect {
        CGRect(
            x: CGFloat(region.col) * cellWidth,
            y: CGFloat(region.row) * cellHeight,
            width: CGFloat(region.colSpan) * cellWidth,
            height: CGFloat(region.rowSpan) * cellHeight
        )
    }

    func rect(for panel: ComposerPanelPayload) -> CGRect {
        CGRect(
            x: CGFloat(panel.xMm - project.layoutGrid.frameXMm) * scale,
            y: CGFloat(panel.yMm - project.layoutGrid.frameYMm) * scale,
            width: CGFloat(panel.wMm) * scale,
            height: CGFloat(panel.hMm) * scale
        )
    }

    func cell(at point: CGPoint) -> ComposerGridCell? {
        guard point.x >= 0,
              point.y >= 0,
              point.x < boardSize.width,
              point.y < boardSize.height
        else {
            return nil
        }
        return clampedCell(at: point)
    }

    func clampedCell(at point: CGPoint) -> ComposerGridCell? {
        guard project.layoutGrid.columns > 0, project.layoutGrid.rows > 0 else {
            return nil
        }

        let clampedX = min(max(point.x, 0), max(boardSize.width - 0.001, 0))
        let clampedY = min(max(point.y, 0), max(boardSize.height - 0.001, 0))
        let col = min(project.layoutGrid.columns - 1, max(0, Int(floor(clampedX / cellWidth))))
        let row = min(project.layoutGrid.rows - 1, max(0, Int(floor(clampedY / cellHeight))))
        return ComposerGridCell(col: col, row: row)
    }

    private var cellWidth: CGFloat {
        CGFloat(project.layoutGrid.cellWidthMm) * scale
    }

    private var cellHeight: CGFloat {
        CGFloat(project.layoutGrid.cellHeightMm) * scale
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

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}
