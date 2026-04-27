import SwiftUI

enum PlotTemplateThumbnailKind: String, Sendable {
    case curve
    case pointLine = "point_line"
    case areaCurve = "area_curve"
    case stepLine = "step_line"
    case stackedCurve = "stacked_curve"
    case stackedArea = "stacked_area"
    case segmentedStackedCurve = "segmented_stacked_curve"
    case scatter
    case bubbleScatter = "bubble_scatter"
    case scatterFit = "scatter_fit"
    case meanBand = "mean_band"
    case bar
    case pointError = "point_error"
    case lollipopError = "lollipop_error"
    case histogramDensity = "histogram_density"
    case densityArea = "density_area"
    case box
    case boxStrip = "box_strip"
    case violin
    case violinBox = "violin_box"
    case heatmap
    case annotatedHeatmap = "annotated_heatmap"
    case fallback
}

struct PlotTemplateView: View {
    @Bindable var session: PlotSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkbenchRailTitle(title: "Templates", trailing: "\(session.templateGalleryItems.count)")

            if session.templateGalleryItems.isEmpty {
                SubtleStageHint(
                    title: "Import data to choose a template",
                    systemImage: "tray.and.arrow.down"
                )
            } else {
                List(selection: selectedTemplateBinding) {
                    ForEach(session.templateGalleryItems) { item in
                        PlotTemplateRow(
                            title: item.title,
                            kind: item.thumbnailKind,
                            aspectRatio: item.aspectRatio,
                            enabled: item.selectable
                        )
                        .tag(Optional(item.id))
                        .disabled(!item.availability.isEnabled)
                        .help(item.availability.reason ?? item.description ?? "Use \(item.title).")
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
                .scrollContentBackground(.hidden)
                .animation(MotionTokens.list, value: session.templateGalleryItems.map(\.id))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var selectedTemplateBinding: Binding<String?> {
        Binding(
            get: { session.selectedTemplateID },
            set: { newValue in
                guard let newValue,
                      session.templateGalleryItems.contains(where: { $0.id == newValue && $0.selectable })
                else {
                    return
                }
                session.chooseTemplate(newValue)
            }
        )
    }
}

private struct PlotTemplateRow: View {
    let title: String
    let kind: PlotTemplateThumbnailKind
    let aspectRatio: CGFloat
    let enabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            PlotTemplateThumbnailView(kind: kind, aspectRatio: aspectRatio)
                .frame(width: 34, height: 26)
                .opacity(enabled ? 1.0 : 0.55)

            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(enabled ? 1.0 : 0.6)
    }
}

struct PlotTemplateThumbnailView: View {
    let kind: PlotTemplateThumbnailKind
    let aspectRatio: CGFloat

    var body: some View {
        Canvas { context, size in
            let frame = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            let plotRect = normalizedPlotRect(in: frame)
            let palette = ThumbnailPalette()

            drawPanelChrome(in: frame, context: &context, palette: palette)
            drawGrid(in: plotRect, context: &context, color: palette.grid)
            drawAxes(in: plotRect, context: &context, color: palette.axis)

            switch kind {
            case .curve:
                drawCurve(in: plotRect, context: &context, palette: palette, withPoints: false)
            case .pointLine:
                drawCurve(in: plotRect, context: &context, palette: palette, withPoints: true)
            case .areaCurve:
                drawAreaCurve(in: plotRect, context: &context, palette: palette)
            case .stepLine:
                drawStepLine(in: plotRect, context: &context, palette: palette)
            case .stackedCurve:
                drawStackedCurves(in: plotRect, context: &context, palette: palette, reservedHeaderFraction: 0)
            case .stackedArea:
                drawStackedCurves(
                    in: plotRect,
                    context: &context,
                    palette: palette,
                    reservedHeaderFraction: 0,
                    filled: true
                )
            case .segmentedStackedCurve:
                drawStackedCurves(in: plotRect, context: &context, palette: palette, reservedHeaderFraction: 0.18)
            case .scatter:
                drawScatter(in: plotRect, context: &context, palette: palette)
            case .bubbleScatter:
                drawBubbleScatter(in: plotRect, context: &context, palette: palette)
            case .scatterFit:
                drawScatterFit(in: plotRect, context: &context, palette: palette)
            case .meanBand:
                drawMeanBand(in: plotRect, context: &context, palette: palette)
            case .bar:
                drawBars(in: plotRect, context: &context, palette: palette)
            case .pointError:
                drawPointError(in: plotRect, context: &context, palette: palette, withStems: false)
            case .lollipopError:
                drawPointError(in: plotRect, context: &context, palette: palette, withStems: true)
            case .histogramDensity:
                drawHistogramDensity(in: plotRect, context: &context, palette: palette)
            case .densityArea:
                drawDensityArea(in: plotRect, context: &context, palette: palette)
            case .box:
                drawBoxes(in: plotRect, context: &context, palette: palette)
            case .boxStrip:
                drawBoxes(in: plotRect, context: &context, palette: palette)
                drawStripOverlay(in: plotRect, context: &context, palette: palette)
            case .violin:
                drawViolins(in: plotRect, context: &context, palette: palette)
            case .violinBox:
                drawViolins(in: plotRect, context: &context, palette: palette)
                drawCompactBoxOverlay(in: plotRect, context: &context, palette: palette)
            case .heatmap:
                drawHeatmap(in: plotRect, context: &context)
            case .annotatedHeatmap:
                drawHeatmap(in: plotRect, context: &context)
                drawHeatmapAnnotations(in: plotRect, context: &context, palette: palette)
            case .fallback:
                drawScatter(in: plotRect, context: &context, palette: palette)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.13), lineWidth: 1)
        )
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private func normalizedPlotRect(in frame: CGRect) -> CGRect {
        let leftInset = max(8, frame.width * 0.09)
        let rightInset = max(6, frame.width * 0.05)
        let topInset = max(7, frame.height * 0.12)
        let bottomInset = max(8, frame.height * 0.13)
        return frame.inset(by: EdgeInsets(top: topInset, leading: leftInset, bottom: bottomInset, trailing: rightInset))
    }

    private func drawPanelChrome(
        in frame: CGRect,
        context: inout GraphicsContext,
        palette: ThumbnailPalette
    ) {
        context.fill(
            Path(roundedRect: frame, cornerRadius: 8, style: .continuous),
            with: .linearGradient(
                Gradient(colors: [palette.panelTop, palette.panelBottom]),
                startPoint: CGPoint(x: frame.midX, y: frame.minY),
                endPoint: CGPoint(x: frame.midX, y: frame.maxY)
            )
        )
    }

    private func drawGrid(in rect: CGRect, context: inout GraphicsContext, color: Color) {
        var gridPath = Path()
        let ticks: [CGFloat] = [0.2, 0.4, 0.6, 0.8]
        for tick in ticks {
            let y = rect.maxY - (tick * rect.height)
            gridPath.move(to: CGPoint(x: rect.minX, y: y))
            gridPath.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        for tick in ticks {
            let x = rect.minX + (tick * rect.width)
            gridPath.move(to: CGPoint(x: x, y: rect.minY))
            gridPath.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        context.stroke(
            gridPath,
            with: .color(color),
            style: StrokeStyle(lineWidth: 0.7, lineCap: .round, dash: [1.8, 2.6])
        )
    }

    private func drawAxes(in rect: CGRect, context: inout GraphicsContext, color: Color) {
        var axisPath = Path()
        axisPath.move(to: CGPoint(x: rect.minX, y: rect.minY))
        axisPath.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        axisPath.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        context.stroke(axisPath, with: .color(color), lineWidth: 1.05)
    }

    private func drawCurve(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette, withPoints: Bool) {
        let primary = sampleCurvePointsA(in: rect)
        let secondary = sampleCurvePointsB(in: rect)

        var path = Path()
        path.move(to: primary[0])
        primary.dropFirst().forEach { path.addLine(to: $0) }
        context.stroke(path, with: .color(palette.primary), lineWidth: 1.8)

        var secondaryPath = Path()
        secondaryPath.move(to: secondary[0])
        secondary.dropFirst().forEach { secondaryPath.addLine(to: $0) }
        context.stroke(secondaryPath, with: .color(palette.secondary), lineWidth: 1.35)

        guard withPoints else {
            return
        }

        for point in primary {
            let dotRect = CGRect(x: point.x - 1.6, y: point.y - 1.6, width: 3.2, height: 3.2)
            context.fill(Path(ellipseIn: dotRect), with: .color(palette.primary))
        }
    }

    private func drawAreaCurve(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        let primary = sampleCurvePointsA(in: rect)
        let secondary = sampleCurvePointsB(in: rect)

        var primaryFill = Path()
        primaryFill.move(to: CGPoint(x: primary[0].x, y: rect.maxY))
        primary.forEach { primaryFill.addLine(to: $0) }
        primaryFill.addLine(to: CGPoint(x: primary.last?.x ?? rect.maxX, y: rect.maxY))
        primaryFill.closeSubpath()
        context.fill(primaryFill, with: .color(palette.primary.opacity(0.18)))

        var secondaryFill = Path()
        secondaryFill.move(to: CGPoint(x: secondary[0].x, y: rect.maxY))
        secondary.forEach { secondaryFill.addLine(to: $0) }
        secondaryFill.addLine(to: CGPoint(x: secondary.last?.x ?? rect.maxX, y: rect.maxY))
        secondaryFill.closeSubpath()
        context.fill(secondaryFill, with: .color(palette.secondary.opacity(0.14)))

        drawCurve(in: rect, context: &context, palette: palette, withPoints: false)
    }

    private func drawStepLine(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        let primary = sampleCurvePointsA(in: rect)
        let secondary = sampleCurvePointsB(in: rect)

        var primaryPath = Path()
        primaryPath.move(to: primary[0])
        for index in 1..<primary.count {
            let previous = primary[index - 1]
            let point = primary[index]
            primaryPath.addLine(to: CGPoint(x: point.x, y: previous.y))
            primaryPath.addLine(to: point)
        }
        context.stroke(primaryPath, with: .color(palette.primary), lineWidth: 1.8)

        var secondaryPath = Path()
        secondaryPath.move(to: secondary[0])
        for index in 1..<secondary.count {
            let previous = secondary[index - 1]
            let point = secondary[index]
            secondaryPath.addLine(to: CGPoint(x: point.x, y: previous.y))
            secondaryPath.addLine(to: point)
        }
        context.stroke(secondaryPath, with: .color(palette.secondary), lineWidth: 1.35)
    }

    private func drawScatter(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        let pointsA: [CGPoint] = [
            plotPoint(0.13, 0.18, in: rect),
            plotPoint(0.27, 0.31, in: rect),
            plotPoint(0.41, 0.47, in: rect),
            plotPoint(0.62, 0.65, in: rect),
            plotPoint(0.78, 0.79, in: rect),
        ]
        let pointsB: [CGPoint] = [
            plotPoint(0.2, 0.25, in: rect),
            plotPoint(0.34, 0.39, in: rect),
            plotPoint(0.55, 0.52, in: rect),
            plotPoint(0.72, 0.69, in: rect),
        ]

        var trend = Path()
        trend.move(to: plotPoint(0.08, 0.12, in: rect))
        trend.addLine(to: plotPoint(0.86, 0.84, in: rect))
        context.stroke(
            trend,
            with: .color(palette.primary.opacity(0.65)),
            style: StrokeStyle(lineWidth: 1.15, lineCap: .round, dash: [3, 2])
        )

        for point in pointsA {
            let dotRect = CGRect(x: point.x - 2.1, y: point.y - 2.1, width: 4.2, height: 4.2)
            context.fill(Path(ellipseIn: dotRect), with: .color(palette.primary.opacity(0.82)))
        }
        for point in pointsB {
            let dotRect = CGRect(x: point.x - 1.9, y: point.y - 1.9, width: 3.8, height: 3.8)
            context.fill(Path(ellipseIn: dotRect), with: .color(palette.secondary.opacity(0.88)))
        }
    }

    private func drawBubbleScatter(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        let bubbles: [(CGPoint, CGFloat, Color)] = [
            (plotPoint(0.18, 0.24, in: rect), 5.0, palette.primary.opacity(0.78)),
            (plotPoint(0.32, 0.38, in: rect), 7.0, palette.secondary.opacity(0.66)),
            (plotPoint(0.52, 0.49, in: rect), 4.2, palette.primary.opacity(0.72)),
            (plotPoint(0.7, 0.69, in: rect), 8.2, palette.secondary.opacity(0.62)),
            (plotPoint(0.82, 0.78, in: rect), 5.6, palette.primary.opacity(0.76)),
        ]

        var trend = Path()
        trend.move(to: plotPoint(0.1, 0.14, in: rect))
        trend.addLine(to: plotPoint(0.88, 0.82, in: rect))
        context.stroke(
            trend,
            with: .color(palette.axis.opacity(0.65)),
            style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [3.2, 2.2])
        )

        for (center, radius, color) in bubbles {
            let bubbleRect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: bubbleRect), with: .color(color))
        }
    }

    private func drawScatterFit(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        drawScatter(in: rect, context: &context, palette: palette)

        var fit = Path()
        fit.move(to: plotPoint(0.08, 0.11, in: rect))
        fit.addLine(to: plotPoint(0.9, 0.86, in: rect))
        context.stroke(fit, with: .color(palette.primary.opacity(0.9)), lineWidth: 1.3)
    }

    private func drawMeanBand(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        let centerline = sampleCurvePointsA(in: rect)
        let upper = centerline.map { CGPoint(x: $0.x, y: $0.y - 4.5) }
        let lower = centerline.reversed().map { CGPoint(x: $0.x, y: $0.y + 4.5) }

        var band = Path()
        band.move(to: upper[0])
        upper.dropFirst().forEach { band.addLine(to: $0) }
        lower.forEach { band.addLine(to: $0) }
        band.closeSubpath()
        context.fill(band, with: .color(palette.secondary.opacity(0.25)))

        var line = Path()
        line.move(to: centerline[0])
        centerline.dropFirst().forEach { line.addLine(to: $0) }
        context.stroke(line, with: .color(palette.primary), lineWidth: 1.7)
    }

    private func drawStackedCurves(
        in rect: CGRect,
        context: inout GraphicsContext,
        palette: ThumbnailPalette,
        reservedHeaderFraction: CGFloat,
        filled: Bool = false
    ) {
        if reservedHeaderFraction > 0 {
            let reservedRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: rect.height * reservedHeaderFraction
            )
            context.fill(
                Path(roundedRect: reservedRect, cornerRadius: 4),
                with: .color(palette.secondary.opacity(0.12))
            )
        }

        let adjustedRect = CGRect(
            x: rect.minX,
            y: rect.minY + rect.height * reservedHeaderFraction,
            width: rect.width,
            height: rect.height * (1 - reservedHeaderFraction)
        )
        let offsets: [CGFloat] = [0, 7, 14]
        let colors: [Color] = [palette.primary, palette.secondary, palette.axis.opacity(0.82)]

        for (offset, color) in zip(offsets, colors) {
            let points = sampleCurvePointsA(in: adjustedRect).map { CGPoint(x: $0.x, y: $0.y + offset) }
            if filled, let first = points.first, let last = points.last {
                var fill = Path()
                fill.move(to: CGPoint(x: first.x, y: adjustedRect.maxY))
                points.forEach { fill.addLine(to: $0) }
                fill.addLine(to: CGPoint(x: last.x, y: adjustedRect.maxY))
                fill.closeSubpath()
                context.fill(fill, with: .color(color.opacity(0.18)))
            }
            var path = Path()
            path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }
            context.stroke(path, with: .color(color), lineWidth: 1.3)
        }
    }

    private func drawBars(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        let heights: [CGFloat] = [0.28, 0.46, 0.73, 0.58]
        let slot = rect.width / CGFloat(max(heights.count, 1))
        for (index, height) in heights.enumerated() {
            let centerX = rect.minX + (CGFloat(index) + 0.5) * slot
            let barWidth = slot * 0.58
            let barHeight = rect.height * height
            let barRect = CGRect(
                x: centerX - barWidth / 2,
                y: rect.maxY - barHeight,
                width: barWidth,
                height: barHeight
            )
            let color = index % 2 == 0 ? palette.primary.opacity(0.86) : palette.secondary.opacity(0.9)
            context.fill(Path(roundedRect: barRect, cornerRadius: 2.6), with: .color(color))

            var cap = Path()
            cap.move(to: CGPoint(x: centerX, y: barRect.minY - 5))
            cap.addLine(to: CGPoint(x: centerX, y: barRect.minY - 1.2))
            cap.move(to: CGPoint(x: centerX - 2.8, y: barRect.minY - 5))
            cap.addLine(to: CGPoint(x: centerX + 2.8, y: barRect.minY - 5))
            context.stroke(cap, with: .color(palette.axis.opacity(0.72)), lineWidth: 0.9)
        }
    }

    private func drawPointError(
        in rect: CGRect,
        context: inout GraphicsContext,
        palette: ThumbnailPalette,
        withStems: Bool
    ) {
        let points: [(CGFloat, CGFloat, CGFloat)] = [
            (0.16, 0.32, 0.10),
            (0.38, 0.49, 0.13),
            (0.62, 0.69, 0.11),
            (0.82, 0.58, 0.09),
        ]

        for (xFraction, yFraction, errorHeight) in points {
            let center = plotPoint(xFraction, yFraction, in: rect)
            let top = plotPoint(xFraction, min(0.96, yFraction + errorHeight), in: rect)
            let bottom = plotPoint(xFraction, max(0.08, yFraction - errorHeight), in: rect)

            if withStems {
                let baseline = plotPoint(xFraction, 0.02, in: rect)
                var stem = Path()
                stem.move(to: baseline)
                stem.addLine(to: center)
                context.stroke(stem, with: .color(palette.secondary.opacity(0.62)), lineWidth: 1.2)
            }

            var errorBar = Path()
            errorBar.move(to: top)
            errorBar.addLine(to: bottom)
            errorBar.move(to: CGPoint(x: top.x - 3, y: top.y))
            errorBar.addLine(to: CGPoint(x: top.x + 3, y: top.y))
            errorBar.move(to: CGPoint(x: bottom.x - 3, y: bottom.y))
            errorBar.addLine(to: CGPoint(x: bottom.x + 3, y: bottom.y))
            context.stroke(errorBar, with: .color(palette.axis.opacity(0.78)), lineWidth: 0.95)

            let markerRect = CGRect(x: center.x - 2.8, y: center.y - 2.8, width: 5.6, height: 5.6)
            context.fill(Path(ellipseIn: markerRect), with: .color(palette.primary))
        }
    }

    private func drawBoxes(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        let centers: [CGFloat] = stride(from: 0.2, through: 0.8, by: 0.3).map {
            rect.minX + CGFloat($0) * rect.width
        }
        for center in centers {
            let boxRect = CGRect(x: center - 5.6, y: rect.midY - 8, width: 11.2, height: 15.8)
            context.fill(Path(roundedRect: boxRect, cornerRadius: 2.2), with: .color(palette.secondary.opacity(0.25)))
            context.stroke(Path(roundedRect: boxRect, cornerRadius: 2.2), with: .color(palette.primary), lineWidth: 1.1)

            var median = Path()
            median.move(to: CGPoint(x: boxRect.minX + 1.2, y: boxRect.midY))
            median.addLine(to: CGPoint(x: boxRect.maxX - 1.2, y: boxRect.midY))
            context.stroke(median, with: .color(palette.primary.opacity(0.82)), lineWidth: 1.1)

            var whisker = Path()
            whisker.move(to: CGPoint(x: center, y: boxRect.minY - 7))
            whisker.addLine(to: CGPoint(x: center, y: boxRect.maxY + 7))
            whisker.move(to: CGPoint(x: center - 3.5, y: boxRect.minY - 7))
            whisker.addLine(to: CGPoint(x: center + 3.5, y: boxRect.minY - 7))
            whisker.move(to: CGPoint(x: center - 3.5, y: boxRect.maxY + 7))
            whisker.addLine(to: CGPoint(x: center + 3.5, y: boxRect.maxY + 7))
            context.stroke(whisker, with: .color(palette.axis.opacity(0.8)), lineWidth: 0.95)
        }
    }

    private func drawStripOverlay(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        let jitteredPoints: [CGPoint] = [
            plotPoint(0.18, 0.32, in: rect),
            plotPoint(0.21, 0.45, in: rect),
            plotPoint(0.22, 0.57, in: rect),
            plotPoint(0.5, 0.36, in: rect),
            plotPoint(0.49, 0.48, in: rect),
            plotPoint(0.52, 0.62, in: rect),
            plotPoint(0.79, 0.29, in: rect),
            plotPoint(0.81, 0.44, in: rect),
            plotPoint(0.78, 0.56, in: rect),
        ]

        for point in jitteredPoints {
            let dotRect = CGRect(x: point.x - 1.7, y: point.y - 1.7, width: 3.4, height: 3.4)
            context.fill(Path(ellipseIn: dotRect), with: .color(palette.primary.opacity(0.58)))
        }
    }

    private func drawViolins(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        let centers: [CGFloat] = stride(from: 0.2, through: 0.8, by: 0.3).map {
            rect.minX + CGFloat($0) * rect.width
        }
        for center in centers {
            var shape = Path()
            shape.move(to: CGPoint(x: center, y: rect.minY + 8))
            shape.addQuadCurve(
                to: CGPoint(x: center, y: rect.maxY - 7),
                control: CGPoint(x: center + 7.2, y: rect.midY)
            )
            shape.addQuadCurve(
                to: CGPoint(x: center, y: rect.minY + 8),
                control: CGPoint(x: center - 7.2, y: rect.midY)
            )
            context.fill(shape, with: .color(palette.secondary.opacity(0.45)))
            context.stroke(shape, with: .color(palette.primary.opacity(0.75)), lineWidth: 1)
        }
    }

    private func drawCompactBoxOverlay(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        let centers: [CGFloat] = stride(from: 0.2, through: 0.8, by: 0.3).map {
            rect.minX + CGFloat($0) * rect.width
        }
        for center in centers {
            let boxRect = CGRect(x: center - 4.2, y: rect.midY - 6.2, width: 8.4, height: 12.4)
            context.fill(Path(roundedRect: boxRect, cornerRadius: 1.8), with: .color(Color.white.opacity(0.7)))
            context.stroke(Path(roundedRect: boxRect, cornerRadius: 1.8), with: .color(palette.axis.opacity(0.82)), lineWidth: 0.9)
        }
    }

    private func drawHeatmap(in rect: CGRect, context: inout GraphicsContext) {
        let cols = 6
        let rows = 4
        let topStripHeight = max(4, rect.height * 0.12)
        let gridTop = rect.minY + topStripHeight + 2
        let usableHeight = max(8, rect.maxY - gridTop)
        let cellWidth = rect.width / CGFloat(cols)
        let cellHeight = usableHeight / CGFloat(rows)
        let startX = rect.minX
        let startY = gridTop

        for col in 0..<cols {
            let t = Double(col) / Double(max(cols - 1, 1))
            let stripRect = CGRect(
                x: startX + CGFloat(col) * cellWidth,
                y: rect.minY,
                width: cellWidth,
                height: topStripHeight
            )
            let stripColor = Color(
                hue: 0.58 - (0.35 * t),
                saturation: 0.70,
                brightness: 0.90 - (0.25 * t)
            )
            context.fill(Path(stripRect), with: .color(stripColor))
        }

        for row in 0..<rows {
            for col in 0..<cols {
                let t = Double((row * cols) + col) / Double(rows * cols)
                let cellRect = CGRect(
                    x: startX + CGFloat(col) * cellWidth,
                    y: startY + CGFloat(row) * cellHeight,
                    width: cellWidth - 0.7,
                    height: cellHeight - 0.7
                )
                let color = Color(
                    hue: 0.58 - (0.35 * t),
                    saturation: 0.68,
                    brightness: 0.93 - (0.30 * t)
                )
                context.fill(Path(cellRect), with: .color(color))
            }
        }
    }

    private func drawHeatmapAnnotations(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        let annotationPoints: [CGPoint] = [
            plotPoint(0.16, 0.18, in: rect),
            plotPoint(0.44, 0.43, in: rect),
            plotPoint(0.71, 0.67, in: rect),
        ]
        for point in annotationPoints {
            let markerRect = CGRect(x: point.x - 2.0, y: point.y - 2.0, width: 4.0, height: 4.0)
            context.stroke(Path(ellipseIn: markerRect), with: .color(palette.axis.opacity(0.82)), lineWidth: 0.8)
        }
    }

    private func drawHistogramDensity(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        let bins: [(CGFloat, CGFloat)] = [
            (0.12, 0.18),
            (0.24, 0.36),
            (0.36, 0.58),
            (0.48, 0.74),
            (0.60, 0.51),
            (0.72, 0.29),
        ]

        let barWidth = rect.width * 0.08
        for (index, bin) in bins.enumerated() {
            let centerX = rect.minX + bin.0 * rect.width
            let height = rect.height * bin.1
            let barRect = CGRect(
                x: centerX - barWidth / 2,
                y: rect.maxY - height,
                width: barWidth,
                height: height
            )
            let color = index.isMultiple(of: 2) ? palette.primary.opacity(0.25) : palette.secondary.opacity(0.25)
            context.fill(Path(roundedRect: barRect, cornerRadius: 1.4), with: .color(color))
        }

        let leftDensity = [(0.08, 0.16), (0.22, 0.42), (0.4, 0.71), (0.58, 0.52), (0.78, 0.22)]
            .map { plotPoint($0.0, $0.1, in: rect) }
        let rightDensity = [(0.1, 0.12), (0.28, 0.28), (0.46, 0.49), (0.63, 0.61), (0.83, 0.44)]
            .map { plotPoint($0.0, $0.1, in: rect) }

        var leftPath = Path()
        leftPath.move(to: leftDensity[0])
        leftDensity.dropFirst().forEach { leftPath.addLine(to: $0) }
        context.stroke(leftPath, with: .color(palette.primary), lineWidth: 1.3)

        var rightPath = Path()
        rightPath.move(to: rightDensity[0])
        rightDensity.dropFirst().forEach { rightPath.addLine(to: $0) }
        context.stroke(rightPath, with: .color(palette.secondary), lineWidth: 1.2)
    }

    private func drawDensityArea(in rect: CGRect, context: inout GraphicsContext, palette: ThumbnailPalette) {
        let leftDensity = [(0.08, 0.16), (0.22, 0.42), (0.4, 0.71), (0.58, 0.52), (0.78, 0.22)]
            .map { plotPoint($0.0, $0.1, in: rect) }
        let rightDensity = [(0.1, 0.12), (0.28, 0.28), (0.46, 0.49), (0.63, 0.61), (0.83, 0.44)]
            .map { plotPoint($0.0, $0.1, in: rect) }

        func fillDensity(_ points: [CGPoint], color: Color) {
            guard let first = points.first, let last = points.last else {
                return
            }
            var fill = Path()
            fill.move(to: CGPoint(x: first.x, y: rect.maxY))
            points.forEach { fill.addLine(to: $0) }
            fill.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            fill.closeSubpath()
            context.fill(fill, with: .color(color.opacity(0.22)))

            var stroke = Path()
            stroke.move(to: points[0])
            points.dropFirst().forEach { stroke.addLine(to: $0) }
            context.stroke(stroke, with: .color(color), lineWidth: 1.25)
        }

        fillDensity(leftDensity, color: palette.primary)
        fillDensity(rightDensity, color: palette.secondary)
    }

    private func sampleCurvePointsA(in rect: CGRect) -> [CGPoint] {
        [(0.06, 0.14), (0.22, 0.23), (0.39, 0.42), (0.58, 0.57), (0.8, 0.79), (0.95, 0.88)]
            .map { plotPoint($0.0, $0.1, in: rect) }
    }

    private func sampleCurvePointsB(in rect: CGRect) -> [CGPoint] {
        [(0.06, 0.2), (0.24, 0.31), (0.42, 0.45), (0.62, 0.63), (0.84, 0.72), (0.95, 0.78)]
            .map { plotPoint($0.0, $0.1, in: rect) }
    }

    private func plotPoint(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + (x * rect.width), y: rect.maxY - (y * rect.height))
    }
}

private struct ThumbnailPalette {
    let panelTop = Color(nsColor: .windowBackgroundColor).opacity(0.95)
    let panelBottom = Color(nsColor: .controlBackgroundColor).opacity(0.95)
    let axis = Color.secondary.opacity(0.72)
    let grid = Color.secondary.opacity(0.20)
    let primary = Color.accentColor
    let secondary = Color.blue.opacity(0.78)
}

private extension CGRect {
    func inset(by insets: EdgeInsets) -> CGRect {
        CGRect(
            x: minX + insets.leading,
            y: minY + insets.top,
            width: width - insets.leading - insets.trailing,
            height: height - insets.top - insets.bottom
        )
    }
}
