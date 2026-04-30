import SwiftUI

struct PlotRefineView: View {
    @Bindable var session: PlotSession

    var body: some View {
        PlotPreviewStage(session: session)
    }
}

struct PlotPreviewStage: View {
    @Bindable var session: PlotSession
    @Environment(\.displayScale) private var displayScale
    @Environment(\.proWorkspaceTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let previewBucket = PlotPreviewPixelBucket(stageSize: geometry.size, displayScale: displayScale)
            ZStack(alignment: .topTrailing) {
                theme.stageBackground

                previewSurface
                    .padding(34)

                if session.isPreviewing, session.previewResponse?.previews.first != nil {
                    updatingBadge
                        .padding(16)
                }

                if let errorMessage = session.errorMessage {
                    PlotStageDiagnosticBanner(message: errorMessage)
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(MotionTokens.stateTransition)
                }
            }
            .task(id: previewBucket) {
                session.updatePreviewPixelBucket(stageSize: geometry.size, displayScale: displayScale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var previewSurface: some View {
        if let preview = session.previewResponse?.previews.first {
            PlotInteractivePreviewSurface(session: session, preview: preview)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PlotEmptyPreviewPage(
                isBusy: session.isInspecting || session.isPreviewing,
                hasSource: session.selectedFileURL != nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var updatingBadge: some View {
        ProgressView()
            .controlSize(.small)
            .padding(10)
            .glassEffect(.regular, in: Capsule())
            .foregroundStyle(.secondary)
            .transition(MotionTokens.stateTransition)
    }
}

private struct PlotInteractivePreviewSurface: View {
    @Bindable var session: PlotSession
    let preview: PreviewItemResponse

    var body: some View {
        GeometryReader { geometry in
            let mapper = PlotPreviewCoordinateMapper(
                metadata: preview.interactionMetadata,
                viewportSize: geometry.size
            )
            ZStack {
                if let previewPNG = preview.pngBase64,
                   !previewPNG.isEmpty,
                   PreviewImageDecoder.decodeBase64PNG(previewPNG) != nil
                {
                    Base64PreviewImageView(base64PNG: previewPNG)
                } else {
                    Base64PDFPreviewView(base64PDF: preview.pdfBase64)
                }

                InteractivePlotOverlay(session: session, mapper: mapper)
            }
        }
    }
}

struct PlotPreviewCoordinateMapper: Equatable {
    let metadata: PreviewInteractionMetadata?
    let viewportSize: CGSize

    var imageRect: CGRect {
        guard let figure = metadata?.figure else {
            return CGRect(origin: .zero, size: viewportSize)
        }
        let imageWidth = max(CGFloat(figure.pixelWidth), 1)
        let imageHeight = max(CGFloat(figure.pixelHeight), 1)
        let imageAspect = imageWidth / imageHeight
        let viewportAspect = max(viewportSize.width, 1) / max(viewportSize.height, 1)
        if viewportAspect > imageAspect {
            let height = viewportSize.height
            let width = height * imageAspect
            return CGRect(x: (viewportSize.width - width) / 2, y: 0, width: width, height: height)
        }
        let width = viewportSize.width
        let height = width / imageAspect
        return CGRect(x: 0, y: (viewportSize.height - height) / 2, width: width, height: height)
    }

    var primaryAxis: PreviewAxisMetadata? {
        metadata?.axes.first(where: { $0.role == "primary" }) ?? metadata?.axes.first
    }

    var axisRect: CGRect {
        guard let metadata, let axis = primaryAxis else {
            return imageRect
        }
        let figureWidth = max(CGFloat(metadata.figure.pixelWidth), 1)
        let figureHeight = max(CGFloat(metadata.figure.pixelHeight), 1)
        return CGRect(
            x: imageRect.minX + CGFloat(axis.bboxPixels.x) / figureWidth * imageRect.width,
            y: imageRect.minY + CGFloat(axis.bboxPixels.y) / figureHeight * imageRect.height,
            width: CGFloat(axis.bboxPixels.width) / figureWidth * imageRect.width,
            height: CGFloat(axis.bboxPixels.height) / figureHeight * imageRect.height
        )
    }

    func dataPoint(at location: CGPoint) -> PlotCanvasDataPoint? {
        let rect = axisRect
        guard rect.width > 0, rect.height > 0 else {
            return nil
        }
        let clampedX = clamp((location.x - rect.minX) / rect.width)
        let clampedTopY = clamp((location.y - rect.minY) / rect.height)
        guard let axis = primaryAxis else {
            return PlotCanvasDataPoint(x: Double(clampedX), y: Double(1 - clampedTopY))
        }
        let x = mappedValue(
            fraction: axis.xReversed ? 1 - clampedX : clampedX,
            range: axis.xRange,
            scale: axis.xScale
        )
        let yFromBottom = 1 - clampedTopY
        let y = mappedValue(
            fraction: axis.yReversed ? 1 - yFromBottom : yFromBottom,
            range: axis.yRange,
            scale: axis.yScale
        )
        return PlotCanvasDataPoint(x: x, y: y)
    }

    func viewPoint(for dataPoint: PlotCanvasDataPoint) -> CGPoint? {
        guard let axis = primaryAxis else {
            return pointForAxesFraction(x: dataPoint.x, y: dataPoint.y)
        }
        guard
            let xFraction = fraction(for: dataPoint.x, range: axis.xRange, scale: axis.xScale),
            let yFraction = fraction(for: dataPoint.y, range: axis.yRange, scale: axis.yScale)
        else {
            return nil
        }
        let rect = axisRect
        let xPosition = axis.xReversed ? 1 - xFraction : xFraction
        let yPosition = axis.yReversed ? 1 - yFraction : yFraction
        return CGPoint(
            x: rect.minX + CGFloat(xPosition) * rect.width,
            y: rect.maxY - CGFloat(yPosition) * rect.height
        )
    }

    func pointForAxesFraction(x: Double, y: Double) -> CGPoint {
        let rect = axisRect
        return CGPoint(
            x: rect.minX + CGFloat(clamp(x)) * rect.width,
            y: rect.maxY - CGFloat(clamp(y)) * rect.height
        )
    }

    func rect(for annotation: ShapeAnnotationPayload) -> CGRect? {
        guard
            let start = viewPoint(for: PlotCanvasDataPoint(x: annotation.xStart, y: annotation.yStart)),
            let end = viewPoint(for: PlotCanvasDataPoint(x: annotation.xEnd, y: annotation.yEnd))
        else {
            return nil
        }
        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }

    func point(for annotation: TextAnnotationPayload) -> CGPoint? {
        if annotation.coordinateSpace == "data" {
            return viewPoint(for: PlotCanvasDataPoint(x: annotation.x, y: annotation.y))
        }
        return pointForAxesFraction(x: annotation.x, y: annotation.y)
    }

    func guideLinePath(for guide: ReferenceGuidePayload) -> Path? {
        guard guide.kind == "line", let value = guide.value else {
            return nil
        }
        let rect = axisRect
        var path = Path()
        if guide.axisTarget == "x" {
            guard let point = viewPoint(for: PlotCanvasDataPoint(x: value, y: primaryAxis?.yRange.first ?? 0)) else {
                return nil
            }
            path.move(to: CGPoint(x: point.x, y: rect.minY))
            path.addLine(to: CGPoint(x: point.x, y: rect.maxY))
        } else {
            guard let point = viewPoint(for: PlotCanvasDataPoint(x: primaryAxis?.xRange.first ?? 0, y: value)) else {
                return nil
            }
            path.move(to: CGPoint(x: rect.minX, y: point.y))
            path.addLine(to: CGPoint(x: rect.maxX, y: point.y))
        }
        return path
    }

    func guideRegionRect(for guide: ReferenceGuidePayload) -> CGRect? {
        guard guide.kind == "band", let start = guide.start, let end = guide.end else {
            return nil
        }
        let rect = axisRect
        if guide.axisTarget == "x" {
            guard
                let startPoint = viewPoint(for: PlotCanvasDataPoint(x: start, y: primaryAxis?.yRange.first ?? 0)),
                let endPoint = viewPoint(for: PlotCanvasDataPoint(x: end, y: primaryAxis?.yRange.first ?? 0))
            else {
                return nil
            }
            let x0 = min(startPoint.x, endPoint.x)
            return CGRect(x: x0, y: rect.minY, width: abs(startPoint.x - endPoint.x), height: rect.height)
        }
        guard
            let startPoint = viewPoint(for: PlotCanvasDataPoint(x: primaryAxis?.xRange.first ?? 0, y: start)),
            let endPoint = viewPoint(for: PlotCanvasDataPoint(x: primaryAxis?.xRange.first ?? 0, y: end))
        else {
            return nil
        }
        let y0 = min(startPoint.y, endPoint.y)
        return CGRect(x: rect.minX, y: y0, width: rect.width, height: abs(startPoint.y - endPoint.y))
    }

    func guideValue(at location: CGPoint, axisTarget: String) -> Double? {
        guard let point = dataPoint(at: location) else {
            return nil
        }
        return axisTarget == "x" ? point.x : point.y
    }

    private func mappedValue(fraction: CGFloat, range: [Double], scale: String) -> Double {
        guard range.count >= 2 else {
            return Double(fraction)
        }
        let lower = range[0]
        let upper = range[1]
        let t = Double(clamp(fraction))
        if scale == "log", lower > 0, upper > 0 {
            let lo = log10(lower)
            let hi = log10(upper)
            return pow(10, lo + (hi - lo) * t)
        }
        return lower + (upper - lower) * t
    }

    private func fraction(for value: Double, range: [Double], scale: String) -> Double? {
        guard range.count >= 2 else {
            return value
        }
        let lower = range[0]
        let upper = range[1]
        guard upper != lower else {
            return nil
        }
        if scale == "log" {
            guard lower > 0, upper > 0, value > 0 else {
                return nil
            }
            let lo = log10(lower)
            let hi = log10(upper)
            return min(max((log10(value) - lo) / (hi - lo), 0), 1)
        }
        return min(max((value - lower) / (upper - lower), 0), 1)
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct InteractivePlotOverlay: View {
    @Bindable var session: PlotSession
    let mapper: PlotPreviewCoordinateMapper
    @State private var dragStartLocation: CGPoint?
    @State private var dragCurrentLocation: CGPoint?
    @State private var lastDragDataPoint: PlotCanvasDataPoint?
    @State private var activeHitTarget: PlotOverlayHitTarget?
    @State private var pendingCalloutTarget: PlotCanvasDataPoint?

    var body: some View {
        Canvas { context, _ in
            drawExistingObjects(in: &context)
            drawPendingCalloutTarget(in: &context)
            drawDraft(in: &context)
        }
        .allowsHitTesting(false)
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .gesture(canvasGesture)
        }
        .animation(.easeOut(duration: 0.12), value: session.canvasSelection.id)
    }

    private var canvasGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleDragChanged(value)
            }
            .onEnded { value in
                handleDragEnded(value)
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        if dragStartLocation == nil {
            dragStartLocation = value.startLocation
        }
        dragCurrentLocation = value.location

        if session.canvasInteractionMode.isPlacementMode {
            return
        }

        if activeHitTarget == nil {
            activeHitTarget = hitTarget(at: value.startLocation)
            if let selection = activeHitTarget?.selection {
                session.selectPlotLayer(selection)
            }
            lastDragDataPoint = mapper.dataPoint(at: value.startLocation)
        }

        guard
            value.translation.width * value.translation.width + value.translation.height * value.translation.height > 9,
            let currentPoint = mapper.dataPoint(at: value.location)
        else {
            return
        }

        switch activeHitTarget {
        case .move:
            if let lastDragDataPoint {
                session.moveSelectedOverlay(
                    delta: PlotCanvasDataPoint(
                        x: currentPoint.x - lastDragDataPoint.x,
                        y: currentPoint.y - lastDragDataPoint.y
                    )
                )
            }
            lastDragDataPoint = currentPoint
        case .resizeShape(let id, let handle):
            session.selectPlotLayer(.shapeAnnotation(id))
            session.resizeSelectedOverlay(handle: handle, point: currentPoint)
        case nil:
            break
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        defer {
            dragStartLocation = nil
            dragCurrentLocation = nil
            lastDragDataPoint = nil
            activeHitTarget = nil
        }

        if session.canvasInteractionMode.isPlacementMode {
            commitPlacement(from: value.startLocation, to: value.location)
            return
        }

        if abs(value.translation.width) < 3, abs(value.translation.height) < 3 {
            if let selection = hitTarget(at: value.location)?.selection {
                session.selectPlotLayer(selection)
            } else {
                session.selectCanvasSelection(.figure)
            }
        }
    }

    private func commitPlacement(from startLocation: CGPoint, to endLocation: CGPoint) {
        let mode = session.canvasInteractionMode
        switch mode {
        case .select:
            return
        case .text:
            guard let point = mapper.dataPoint(at: endLocation) else { return }
            session.commitCanvasDraft(.text(point: point, displayStyle: "plain", connectorTarget: nil))
        case .callout:
            guard let point = mapper.dataPoint(at: endLocation) else { return }
            if let target = pendingCalloutTarget {
                session.commitCanvasDraft(.text(point: point, displayStyle: "callout", connectorTarget: target))
                pendingCalloutTarget = nil
            } else {
                pendingCalloutTarget = point
            }
        case .rectangle, .ellipse, .bracket:
            guard
                let start = mapper.dataPoint(at: startLocation),
                let end = mapper.dataPoint(at: endLocation)
            else { return }
            let kind: String
            switch mode {
            case .ellipse:
                kind = "ellipse"
            case .bracket:
                kind = "bracket"
            default:
                kind = "rectangle"
            }
            session.commitCanvasDraft(.shape(kind: kind, start: start, end: end))
        case .guideLine(let axisTarget):
            guard let value = mapper.guideValue(at: endLocation, axisTarget: axisTarget) else { return }
            session.commitCanvasDraft(.guideLine(axisTarget: axisTarget, value: value))
        case .guideRegion(let axisTarget):
            guard
                let start = mapper.guideValue(at: startLocation, axisTarget: axisTarget),
                let end = mapper.guideValue(at: endLocation, axisTarget: axisTarget)
            else { return }
            session.commitCanvasDraft(.guideRegion(axisTarget: axisTarget, start: start, end: end))
        }
    }

    private func hitTarget(at location: CGPoint) -> PlotOverlayHitTarget? {
        for annotation in session.shapeAnnotations.reversed() {
            guard let rect = mapper.rect(for: annotation) else { continue }
            if session.canvasSelection == .layer(.shapeAnnotation(annotation.id)),
               let handle = resizeHandle(for: location, in: rect, annotation: annotation) {
                return .resizeShape(id: annotation.id, handle: handle)
            }
            if rect.insetBy(dx: -8, dy: -8).contains(location) {
                return .move(.shapeAnnotation(annotation.id))
            }
        }

        for annotation in session.textAnnotations.reversed() {
            guard let point = mapper.point(for: annotation) else { continue }
            if distance(from: location, to: point) <= 18 {
                return .move(.textAnnotation(annotation.id))
            }
        }

        for guide in session.referenceGuides.reversed() {
            if guide.kind == "band", let rect = mapper.guideRegionRect(for: guide), rect.insetBy(dx: -8, dy: -8).contains(location) {
                return .move(.referenceGuide(guide.id))
            }
            if guide.kind == "line", let path = mapper.guideLinePath(for: guide), pathContains(location, near: path) {
                return .move(.referenceGuide(guide.id))
            }
        }
        return nil
    }

    private func resizeHandle(
        for location: CGPoint,
        in rect: CGRect,
        annotation: ShapeAnnotationPayload
    ) -> PlotCanvasResizeHandle? {
        let handles: [(CGPoint, PlotCanvasResizeHandle)]
        if annotation.kind == "bracket" {
            handles = [
                (CGPoint(x: rect.minX, y: rect.midY), .start),
                (CGPoint(x: rect.maxX, y: rect.midY), .end),
            ]
        } else {
            handles = [
                (CGPoint(x: rect.minX, y: rect.minY), .topLeft),
                (CGPoint(x: rect.maxX, y: rect.minY), .topRight),
                (CGPoint(x: rect.minX, y: rect.maxY), .bottomLeft),
                (CGPoint(x: rect.maxX, y: rect.maxY), .bottomRight),
            ]
        }
        return handles.first { distance(from: location, to: $0.0) <= 10 }?.1
    }

    private func drawExistingObjects(in context: inout GraphicsContext) {
        let accent = Color.accentColor.opacity(0.82)
        let secondary = Color.secondary.opacity(0.45)
        for guide in session.referenceGuides {
            let selected = session.canvasSelection == .layer(.referenceGuide(guide.id))
            if let rect = mapper.guideRegionRect(for: guide) {
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(accent.opacity(selected ? 0.14 : 0.06)))
                if selected {
                    context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(accent), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            } else if let path = mapper.guideLinePath(for: guide), selected {
                context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            } else if let path = mapper.guideLinePath(for: guide) {
                context.stroke(path, with: .color(secondary), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }

        for annotation in session.shapeAnnotations {
            guard let rect = mapper.rect(for: annotation) else { continue }
            let selected = session.canvasSelection == .layer(.shapeAnnotation(annotation.id))
            let path = shapePath(for: annotation, rect: rect)
            context.stroke(path, with: .color(selected ? accent : secondary), lineWidth: selected ? 2 : 1)
            if selected {
                drawHandles(for: annotation, rect: rect, in: &context)
            }
        }

        for annotation in session.textAnnotations {
            guard let point = mapper.point(for: annotation) else { continue }
            let selected = session.canvasSelection == .layer(.textAnnotation(annotation.id))
            let rect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
            context.fill(Path(ellipseIn: rect), with: .color(selected ? accent : secondary))
            if selected {
                context.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(accent), lineWidth: 2)
            }
        }
    }

    private func drawPendingCalloutTarget(in context: inout GraphicsContext) {
        guard let pendingCalloutTarget, let point = mapper.viewPoint(for: pendingCalloutTarget) else {
            return
        }
        let rect = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
        context.stroke(Path(ellipseIn: rect), with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
    }

    private func drawDraft(in context: inout GraphicsContext) {
        guard
            let startLocation = dragStartLocation,
            let currentLocation = dragCurrentLocation,
            session.canvasInteractionMode.isPlacementMode
        else {
            return
        }
        let rect = CGRect(
            x: min(startLocation.x, currentLocation.x),
            y: min(startLocation.y, currentLocation.y),
            width: abs(startLocation.x - currentLocation.x),
            height: abs(startLocation.y - currentLocation.y)
        )
        let accent = Color.accentColor.opacity(0.84)
        switch session.canvasInteractionMode {
        case .rectangle:
            context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(accent), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
        case .ellipse:
            context.stroke(Path(ellipseIn: rect), with: .color(accent), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
        case .bracket:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
        case .guideRegion:
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(accent.opacity(0.13)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(accent), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
        case .guideLine(let axisTarget):
            var path = Path()
            if axisTarget == "x" {
                path.move(to: CGPoint(x: currentLocation.x, y: mapper.axisRect.minY))
                path.addLine(to: CGPoint(x: currentLocation.x, y: mapper.axisRect.maxY))
            } else {
                path.move(to: CGPoint(x: mapper.axisRect.minX, y: currentLocation.y))
                path.addLine(to: CGPoint(x: mapper.axisRect.maxX, y: currentLocation.y))
            }
            context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
        case .text, .callout:
            let marker = CGRect(x: currentLocation.x - 6, y: currentLocation.y - 6, width: 12, height: 12)
            context.fill(Path(ellipseIn: marker), with: .color(accent))
        case .select:
            break
        }
    }

    private func shapePath(for annotation: ShapeAnnotationPayload, rect: CGRect) -> Path {
        if annotation.kind == "ellipse" {
            return Path(ellipseIn: rect)
        }
        if annotation.kind == "bracket" {
            var path = Path()
            if annotation.bracketOrientation == "vertical" {
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            } else {
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
            return path
        }
        return Path(roundedRect: rect, cornerRadius: 3)
    }

    private func drawHandles(for annotation: ShapeAnnotationPayload, rect: CGRect, in context: inout GraphicsContext) {
        let points: [CGPoint]
        if annotation.kind == "bracket" {
            points = [
                CGPoint(x: rect.minX, y: rect.midY),
                CGPoint(x: rect.maxX, y: rect.midY),
            ]
        } else {
            points = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY),
            ]
        }
        for point in points {
            let handleRect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: handleRect), with: .color(.white))
            context.stroke(Path(ellipseIn: handleRect), with: .color(.accentColor), lineWidth: 1.5)
        }
    }

    private func pathContains(_ location: CGPoint, near path: Path) -> Bool {
        path.strokedPath(StrokeStyle(lineWidth: 12)).contains(location)
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

private extension PlotOverlayHitTarget {
    var selection: PlotLayerSelection? {
        switch self {
        case .move(let selection):
            return selection
        case .resizeShape(let id, _):
            return .shapeAnnotation(id)
        }
    }
}

struct PlotStageDiagnosticBanner: View {
    let message: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        DiagnosticIssueCard(message: DiagnosticMessage(detail: message))
            .background(.regularMaterial, in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct PlotEmptyPreviewPage: View {
    let isBusy: Bool
    let hasSource: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                }

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
                    .glassEffect(.regular, in: Capsule())
            }
        }
        .aspectRatio(1.12, contentMode: .fit)
        .frame(maxWidth: 760)
    }
}
