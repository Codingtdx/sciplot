import SwiftUI

struct PlotInteractivePreviewSurface: View {
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

    var artists: [PreviewArtistMetadata] {
        metadata?.artists ?? []
    }

    var objects: [PreviewInteractionObjectMetadata] {
        metadata?.objects ?? []
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

    func viewPoint(forPixelPoint point: [Double]) -> CGPoint? {
        guard let metadata, point.count >= 2 else {
            return nil
        }
        let figureWidth = max(CGFloat(metadata.figure.pixelWidth), 1)
        let figureHeight = max(CGFloat(metadata.figure.pixelHeight), 1)
        return CGPoint(
            x: imageRect.minX + CGFloat(point[0]) / figureWidth * imageRect.width,
            y: imageRect.minY + CGFloat(point[1]) / figureHeight * imageRect.height
        )
    }

    func viewPoints(for artist: PreviewArtistMetadata) -> [CGPoint] {
        artist.points.compactMap { viewPoint(forPixelPoint: $0) }
    }

    func viewPoints(for object: PreviewInteractionObjectMetadata) -> [CGPoint] {
        object.points.compactMap { viewPoint(forPixelPoint: $0) }
    }

    func viewRect(forPixelBBox bbox: PreviewBBoxMetadata) -> CGRect {
        guard let metadata else {
            return imageRect
        }
        let figureWidth = max(CGFloat(metadata.figure.pixelWidth), 1)
        let figureHeight = max(CGFloat(metadata.figure.pixelHeight), 1)
        return CGRect(
            x: imageRect.minX + CGFloat(bbox.x) / figureWidth * imageRect.width,
            y: imageRect.minY + CGFloat(bbox.y) / figureHeight * imageRect.height,
            width: CGFloat(bbox.width) / figureWidth * imageRect.width,
            height: CGFloat(bbox.height) / figureHeight * imageRect.height
        )
    }

    func nearestSeriesArtist(at location: CGPoint, tolerance: CGFloat = 12) -> PreviewArtistMetadata? {
        var nearest: (artist: PreviewArtistMetadata, distance: CGFloat)?
        for artist in artists where artist.seriesID != nil {
            let hitRect = viewRect(forPixelBBox: artist.bboxPixels).insetBy(dx: -tolerance, dy: -tolerance)
            guard hitRect.contains(location) else {
                continue
            }
            let points = viewPoints(for: artist)
            guard !points.isEmpty else {
                continue
            }
            let distance = distanceToSeries(location, points: points, kind: artist.kind)
            guard distance <= tolerance else {
                continue
            }
            if nearest == nil || distance < nearest!.distance {
                nearest = (artist, distance)
            }
        }
        return nearest?.artist
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

    private func distanceToSeries(_ location: CGPoint, points: [CGPoint], kind: String) -> CGFloat {
        if kind == "series_points" || points.count == 1 {
            return points.map { distance(from: location, to: $0) }.min() ?? .greatestFiniteMagnitude
        }
        var nearest = CGFloat.greatestFiniteMagnitude
        for index in 0..<(points.count - 1) {
            nearest = min(nearest, distance(from: location, toSegmentFrom: points[index], to: points[index + 1]))
        }
        return nearest
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return distance(from: point, to: start)
        }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return distance(from: point, to: CGPoint(x: start.x + t * dx, y: start.y + t * dy))
    }
}

struct PlotInteractionHit: Equatable {
    let object: PreviewInteractionObjectMetadata
    let distance: CGFloat

    var seriesID: String? {
        object.seriesID
    }
}

extension PreviewInteractionObjectMetadata {
    var seriesID: String? {
        guard payloadRef?.type == "series" else {
            return nil
        }
        return payloadRef?.id
    }
}

struct PlotInteractionHitTester: Equatable {
    let mapper: PlotPreviewCoordinateMapper

    func hitTest(at location: CGPoint, tolerance: CGFloat = 12) -> PlotInteractionHit? {
        if let objectHit = nearestObject(at: location, tolerance: tolerance) {
            return objectHit
        }
        return legacySeriesHit(at: location, tolerance: tolerance)
    }

    private func nearestObject(at location: CGPoint, tolerance: CGFloat) -> PlotInteractionHit? {
        var nearest: PlotInteractionHit?
        for object in mapper.objects {
            let rect = mapper.viewRect(forPixelBBox: object.bboxPixels)
            let expandedRect = rect.insetBy(dx: -tolerance, dy: -tolerance)
            guard expandedRect.contains(location) else {
                continue
            }
            let distance = distanceToObject(location, object: object, rect: rect)
            guard distance <= tolerance || rect.contains(location) else {
                continue
            }
            if nearest == nil || objectPriority(object) > objectPriority(nearest!.object) || (
                objectPriority(object) == objectPriority(nearest!.object) && distance < nearest!.distance
            ) {
                nearest = PlotInteractionHit(object: object, distance: distance)
            }
        }
        return nearest
    }

    private func legacySeriesHit(at location: CGPoint, tolerance: CGFloat) -> PlotInteractionHit? {
        guard let artist = mapper.nearestSeriesArtist(at: location, tolerance: tolerance) else {
            return nil
        }
        let seriesID = artist.seriesID ?? artist.label ?? artist.id
        return PlotInteractionHit(
            object: PreviewInteractionObjectMetadata(
                id: artist.id,
                kind: artist.kind,
                label: artist.label,
                axisID: artist.axisID,
                bboxPixels: artist.bboxPixels,
                points: artist.points,
                payloadRef: PreviewInteractionPayloadRefMetadata(type: "series", id: seriesID),
                operations: ["select", "quick_edit", "drag_offset"]
            ),
            distance: 0
        )
    }

    private func distanceToObject(
        _ location: CGPoint,
        object: PreviewInteractionObjectMetadata,
        rect: CGRect
    ) -> CGFloat {
        let points = mapper.viewPoints(for: object)
        if object.kind == "series_points" || object.kind == "heatmap_cell" || object.kind == "table_cell" {
            if !points.isEmpty {
                return points.map { distance(from: location, to: $0) }.min() ?? .greatestFiniteMagnitude
            }
            return rect.contains(location) ? 0 : distance(from: location, to: nearestPoint(on: rect, from: location))
        }
        if object.kind == "series_line", points.count >= 2 {
            var nearest = CGFloat.greatestFiniteMagnitude
            for index in 0..<(points.count - 1) {
                nearest = min(nearest, distance(from: location, toSegmentFrom: points[index], to: points[index + 1]))
            }
            return nearest
        }
        return rect.contains(location) ? 0 : distance(from: location, to: nearestPoint(on: rect, from: location))
    }

    private func objectPriority(_ object: PreviewInteractionObjectMetadata) -> Int {
        switch object.kind {
        case "text_annotation", "shape_annotation", "reference_guide":
            return 50
        case "series_line", "series_points", "bar", "distribution_body":
            return 40
        case "legend_entry", "legend":
            return 30
        case "x_axis", "y_axis", "axis_title", "x_label", "y_label", "axis", "colorbar":
            return 20
        default:
            return 10
        }
    }

    private func nearestPoint(on rect: CGRect, from point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return distance(from: point, to: start)
        }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return distance(from: point, to: CGPoint(x: start.x + t * dx, y: start.y + t * dy))
    }
}

struct InteractivePlotOverlay: View {
    @Bindable var session: PlotSession
    let mapper: PlotPreviewCoordinateMapper
    @State private var dragStartLocation: CGPoint?
    @State private var dragCurrentLocation: CGPoint?
    @State private var lastDragDataPoint: PlotCanvasDataPoint?
    @State private var activeHitTarget: PlotOverlayHitTarget?
    @State private var activeInteractionHit: PlotInteractionHit?
    @State private var seriesDragTranslation: CGSize?
    @State private var seriesDragDataDelta: PlotCanvasDataPoint?
    @State private var pendingCalloutTarget: PlotCanvasDataPoint?
    @State private var seriesQuickEditorAnchor: CGPoint?
    @State private var lastClickLocation: CGPoint?
    @State private var lastClickTime: Date?

    var body: some View {
        Canvas { context, _ in
            drawExistingObjects(in: &context)
            drawPendingCalloutTarget(in: &context)
            drawSeriesDragGhost(in: &context)
            drawDraft(in: &context)
        }
        .allowsHitTesting(false)
        .overlay {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(canvasGesture)
                seriesQuickEditorAnchorView
            }
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

    @ViewBuilder
    private var seriesQuickEditorAnchorView: some View {
        if let seriesQuickEditorAnchor, let seriesID = session.selectedSeriesQuickEditorID {
            Color.clear
                .frame(width: 1, height: 1)
                .position(seriesQuickEditorAnchor)
                .popover(isPresented: seriesQuickEditorPopoverBinding, arrowEdge: .top) {
                    PlotSeriesQuickEditorPopover(session: session, seriesID: seriesID)
                }
        }
    }

    private var seriesQuickEditorPopoverBinding: Binding<Bool> {
        Binding(
            get: { session.selectedSeriesQuickEditorID != nil && seriesQuickEditorAnchor != nil },
            set: { presented in
                if !presented {
                    seriesQuickEditorAnchor = nil
                }
            }
        )
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
            } else if activeInteractionHit == nil {
                activeInteractionHit = PlotInteractionHitTester(mapper: mapper).hitTest(at: value.startLocation)
                if let object = activeInteractionHit?.object {
                    session.selectPreviewObject(object)
                }
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
            if let seriesID = activeInteractionHit?.seriesID,
               let startPoint = mapper.dataPoint(at: value.startLocation) {
                seriesDragTranslation = value.translation
                seriesDragDataDelta = PlotCanvasDataPoint(
                    x: currentPoint.x - startPoint.x,
                    y: currentPoint.y - startPoint.y
                )
                session.selectPlotLayer(.series(seriesID))
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        defer {
            dragStartLocation = nil
            dragCurrentLocation = nil
            lastDragDataPoint = nil
            activeHitTarget = nil
            activeInteractionHit = nil
            seriesDragTranslation = nil
            seriesDragDataDelta = nil
        }

        if session.canvasInteractionMode.isPlacementMode {
            commitPlacement(from: value.startLocation, to: value.location)
            return
        }

        if abs(value.translation.width) < 3, abs(value.translation.height) < 3 {
            handleClick(at: value.location)
        } else if let seriesID = activeInteractionHit?.seriesID,
                  let delta = seriesDragDataDelta {
            session.commitPreviewSeriesDrag(
                seriesID: seriesID,
                xOffset: delta.x,
                yOffset: delta.y,
                policy: .debounced
            )
        }
    }

    private func handleClick(at location: CGPoint) {
        let now = Date()
        let isDoubleClick = lastClickTime.map { now.timeIntervalSince($0) <= 0.35 } == true
            && lastClickLocation.map { distance(from: location, to: $0) <= 8 } == true

        if isDoubleClick {
            if let hit = PlotInteractionHitTester(mapper: mapper).hitTest(at: location) {
                if session.openPreviewObjectQuickEditor(hit.object), hit.seriesID != nil {
                    seriesQuickEditorAnchor = location
                } else {
                    seriesQuickEditorAnchor = nil
                }
                lastClickLocation = nil
                lastClickTime = nil
                return
            }
        }

        lastClickLocation = location
        lastClickTime = now
        if let selection = hitTarget(at: location)?.selection {
            session.selectPlotLayer(selection)
            seriesQuickEditorAnchor = nil
        } else if let hit = PlotInteractionHitTester(mapper: mapper).hitTest(at: location) {
            session.selectPreviewObject(hit.object)
            seriesQuickEditorAnchor = nil
        } else if session.selectPreviewSeries(at: location, mapper: mapper) {
            seriesQuickEditorAnchor = nil
        } else {
            session.selectCanvasSelection(.figure)
            seriesQuickEditorAnchor = nil
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
            if textSelectionRect(for: annotation, at: point).insetBy(dx: -8, dy: -8).contains(location) {
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
        let accent = Color.accentColor.opacity(0.78)
        let secondary = Color.secondary.opacity(0.45)
        drawSelectedPreviewObject(in: &context)
        drawSelectedSeriesArtist(in: &context)

        for guide in session.referenceGuides {
            let selected = session.canvasSelection == .layer(.referenceGuide(guide.id))
            if let rect = mapper.guideRegionRect(for: guide) {
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(accent.opacity(selected ? 0.12 : 0.05)))
                if selected {
                    context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(accent), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            } else if let path = mapper.guideLinePath(for: guide), selected {
                context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            } else if let path = mapper.guideLinePath(for: guide) {
                context.stroke(path, with: .color(secondary), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }

        for annotation in session.shapeAnnotations {
            guard let rect = mapper.rect(for: annotation) else { continue }
            let selected = session.canvasSelection == .layer(.shapeAnnotation(annotation.id))
            let path = shapePath(for: annotation, rect: rect)
            context.stroke(path, with: .color(selected ? accent : secondary), lineWidth: selected ? 1.75 : 1)
            if selected {
                drawRoundedSquareHandles(for: annotation, rect: rect, in: &context)
            }
        }

        for annotation in session.textAnnotations {
            guard let point = mapper.point(for: annotation) else { continue }
            if session.canvasSelection == .layer(.textAnnotation(annotation.id)) {
                drawTextSelection(for: annotation, at: point, in: &context)
            }
        }
    }

    private func drawSelectedSeriesArtist(in context: inout GraphicsContext) {
        guard case .layer(.series(let seriesID)) = session.canvasSelection else {
            return
        }
        if let object = mapper.objects.first(where: { $0.seriesID == seriesID }) {
            drawInteractionObject(object, in: &context, color: Color.accentColor.opacity(0.72), dashed: true)
            return
        }
        guard let artist = mapper.artists.first(where: { $0.seriesID == seriesID }) else {
            return
        }
        let points = mapper.viewPoints(for: artist)
        guard !points.isEmpty else {
            return
        }
        let accent = Color.accentColor.opacity(0.72)
        if artist.kind == "series_points" {
            for point in points {
                let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                context.stroke(Path(ellipseIn: rect), with: .color(accent), lineWidth: 1.4)
            }
            return
        }
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
    }

    private func drawSelectedPreviewObject(in context: inout GraphicsContext) {
        guard let selectedID = session.selectedPreviewObjectID,
              let object = mapper.objects.first(where: { $0.id == selectedID }),
              object.seriesID == nil
        else {
            return
        }
        drawInteractionObject(object, in: &context, color: Color.accentColor.opacity(0.66), dashed: true)
    }

    private func drawInteractionObject(
        _ object: PreviewInteractionObjectMetadata,
        in context: inout GraphicsContext,
        color: Color,
        dashed: Bool
    ) {
        let points = mapper.viewPoints(for: object)
        if object.kind == "series_line", points.count >= 2 {
            var path = Path()
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: dashed ? [5, 3] : []))
            return
        }
        if object.kind == "series_points", !points.isEmpty {
            for point in points {
                let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1.4)
            }
            return
        }
        let rect = mapper.viewRect(forPixelBBox: object.bboxPixels)
        guard rect.width > 0, rect.height > 0 else {
            return
        }
        let path = Path(roundedRect: rect, cornerRadius: 3)
        context.fill(path, with: .color(color.opacity(0.04)))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.25, dash: dashed ? [4, 3] : []))
    }

    private func drawSeriesDragGhost(in context: inout GraphicsContext) {
        guard let hit = activeInteractionHit,
              let translation = seriesDragTranslation,
              hit.seriesID != nil
        else {
            return
        }
        let points = mapper.viewPoints(for: hit.object).map {
            CGPoint(x: $0.x + translation.width, y: $0.y + translation.height)
        }
        guard !points.isEmpty else {
            return
        }
        let color = Color.accentColor.opacity(0.38)
        if hit.object.kind == "series_points" {
            for point in points {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)), with: .color(color))
            }
            return
        }
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
    }

    private func drawTextSelection(
        for annotation: TextAnnotationPayload,
        at point: CGPoint,
        in context: inout GraphicsContext
    ) {
        let rect = textSelectionRect(for: annotation, at: point)
        let accent = Color.accentColor.opacity(0.72)
        let path = Path(roundedRect: rect, cornerRadius: 4)
        context.fill(path, with: .color(Color.accentColor.opacity(0.035)))
        context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 1.25, dash: [4, 3]))

        var baseline = Path()
        baseline.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY + 2))
        baseline.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY + 2))
        context.stroke(baseline, with: .color(accent), lineWidth: 1.25)
    }

    private func textSelectionRect(for annotation: TextAnnotationPayload, at point: CGPoint) -> CGRect {
        let textWidth = max(38, min(CGFloat(annotation.text.count) * 7.0 + 18, 180))
        let textHeight: CGFloat = annotation.displayStyle == "callout" ? 28 : 24
        let originX: CGFloat
        switch annotation.horizontalAlignment {
        case "left":
            originX = point.x
        case "right":
            originX = point.x - textWidth
        default:
            originX = point.x - textWidth / 2
        }

        let originY: CGFloat
        switch annotation.verticalAlignment {
        case "center":
            originY = point.y - textHeight / 2
        case "bottom":
            originY = point.y - textHeight
        default:
            originY = point.y
        }

        return CGRect(x: originX, y: originY, width: textWidth, height: textHeight)
    }

    private func drawPendingCalloutTarget(in context: inout GraphicsContext) {
        guard let pendingCalloutTarget, let point = mapper.viewPoint(for: pendingCalloutTarget) else {
            return
        }
        drawTargetTick(at: point, in: &context)
    }

    private func drawTargetTick(at point: CGPoint, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: point.x - 8, y: point.y))
        path.addLine(to: CGPoint(x: point.x - 3, y: point.y))
        path.move(to: CGPoint(x: point.x + 3, y: point.y))
        path.addLine(to: CGPoint(x: point.x + 8, y: point.y))
        path.move(to: CGPoint(x: point.x, y: point.y - 8))
        path.addLine(to: CGPoint(x: point.x, y: point.y - 3))
        path.move(to: CGPoint(x: point.x, y: point.y + 3))
        path.addLine(to: CGPoint(x: point.x, y: point.y + 8))
        context.stroke(path, with: .color(Color.accentColor.opacity(0.78)), style: StrokeStyle(lineWidth: 1.6, dash: [3, 2]))
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
        let accent = Color.accentColor.opacity(0.78)
        switch session.canvasInteractionMode {
        case .rectangle:
            context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(accent), style: StrokeStyle(lineWidth: 1.75, dash: [5, 3]))
        case .ellipse:
            context.stroke(Path(ellipseIn: rect), with: .color(accent), style: StrokeStyle(lineWidth: 1.75, dash: [5, 3]))
        case .bracket:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 1.75, dash: [5, 3]))
        case .guideRegion:
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(accent.opacity(0.10)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(accent), style: StrokeStyle(lineWidth: 1.75, dash: [5, 3]))
        case .guideLine(let axisTarget):
            var path = Path()
            if axisTarget == "x" {
                path.move(to: CGPoint(x: currentLocation.x, y: mapper.axisRect.minY))
                path.addLine(to: CGPoint(x: currentLocation.x, y: mapper.axisRect.maxY))
            } else {
                path.move(to: CGPoint(x: mapper.axisRect.minX, y: currentLocation.y))
                path.addLine(to: CGPoint(x: mapper.axisRect.maxX, y: currentLocation.y))
            }
            context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 1.75, dash: [5, 3]))
        case .text, .callout:
            drawTargetTick(at: currentLocation, in: &context)
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

    private func drawRoundedSquareHandles(
        for annotation: ShapeAnnotationPayload,
        rect: CGRect,
        in context: inout GraphicsContext
    ) {
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
            let handleRect = CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)
            let path = Path(roundedRect: handleRect, cornerRadius: 2)
            context.fill(path, with: .color(Color.white.opacity(0.88)))
            context.stroke(path, with: .color(Color.accentColor.opacity(0.82)), lineWidth: 1.2)
        }
    }

    private func pathContains(_ location: CGPoint, near path: Path) -> Bool {
        path.strokedPath(StrokeStyle(lineWidth: 12)).contains(location)
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

private struct PlotSeriesQuickEditorPopover: View {
    @Bindable var session: PlotSession
    let seriesID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.secondary)
                Text(seriesID)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }

            Toggle("Visible", isOn: visibleBinding)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Color")
                        .foregroundStyle(.secondary)
                    TextField("#1f77b4", text: colorBinding)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Width")
                        .foregroundStyle(.secondary)
                    TextField("Auto", text: lineWidthBinding)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Marker")
                        .foregroundStyle(.secondary)
                    Picker("", selection: markerBinding) {
                        Text("None").tag("none")
                        Text("Circle").tag("circle")
                        Text("Square").tag("square")
                        Text("Diamond").tag("diamond")
                        Text("Triangle").tag("triangle")
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Axis")
                        .foregroundStyle(.secondary)
                    Picker("", selection: yAxisBinding) {
                        Text("Primary Y").tag("y_primary")
                        Text("Secondary Y").tag("y_secondary")
                    }
                    .labelsHidden()
                }
            }

            Divider()

            HStack {
                Button {
                    session.updateSeriesOffset(seriesID: seriesID, policy: .immediate) {
                        $0.xOffset = 0
                        $0.yOffset = 0
                    }
                } label: {
                    Label("Reset Offset", systemImage: "arrow.counterclockwise")
                }
                .disabled(seriesOffset.xOffset == 0 && seriesOffset.yOffset == 0)

                Spacer()

                Button {
                    session.selectPlotLayer(.series(seriesID))
                    session.selectedPlotAdjustmentCategory = .legend
                } label: {
                    Label("More", systemImage: "sidebar.right")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(width: 270)
        .padding(12)
    }

    private var seriesStyle: SeriesStylePayload {
        session.renderOptions.seriesStyles?.first(where: { $0.seriesID == seriesID }) ?? SeriesStylePayload(seriesID: seriesID)
    }

    private var seriesOffset: SeriesOffsetPayload {
        session.renderOptions.seriesOffsets?.first(where: { $0.seriesID == seriesID }) ?? SeriesOffsetPayload(seriesID: seriesID)
    }

    private var visibleBinding: Binding<Bool> {
        Binding(
            get: { seriesStyle.enabled },
            set: { enabled in
                session.updateSeriesStyle(seriesID: seriesID, policy: .immediate) { $0.enabled = enabled }
            }
        )
    }

    private var colorBinding: Binding<String> {
        Binding(
            get: { seriesStyle.color ?? "" },
            set: { color in
                session.updateSeriesStyle(seriesID: seriesID, policy: .debounced) {
                    let trimmed = color.trimmingCharacters(in: .whitespacesAndNewlines)
                    $0.color = trimmed.isEmpty ? nil : trimmed
                }
            }
        )
    }

    private var lineWidthBinding: Binding<String> {
        Binding(
            get: {
                guard let lineWidth = seriesStyle.lineWidth else {
                    return ""
                }
                return String(format: "%.2f", lineWidth)
            },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty || Double(trimmed) != nil else {
                    return
                }
                session.updateSeriesStyle(seriesID: seriesID, policy: .debounced) {
                    $0.lineWidth = trimmed.isEmpty ? nil : Double(trimmed)
                }
            }
        )
    }

    private var markerBinding: Binding<String> {
        Binding(
            get: { seriesStyle.marker ?? "none" },
            set: { marker in
                session.updateSeriesStyle(seriesID: seriesID, policy: .immediate) {
                    $0.marker = marker == "none" ? nil : marker
                }
            }
        )
    }

    private var yAxisBinding: Binding<String> {
        Binding(
            get: { seriesStyle.yAxisTarget ?? "y_primary" },
            set: { target in
                session.updateSeriesStyle(seriesID: seriesID, policy: .immediate) {
                    $0.yAxisTarget = target
                }
            }
        )
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
