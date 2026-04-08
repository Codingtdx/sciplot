import SwiftUI

enum PlotTemplateThumbnailKind: String, Sendable {
    case curve
    case pointLine
    case scatter
    case bar
    case box
    case violin
    case heatmap
    case fallback
}

struct PlotTemplateView: View {
    @Bindable var session: PlotSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Templates")
                    .font(.headline)
                Spacer()
                Text("Top 5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if session.templateGalleryItems.isEmpty {
                ContentUnavailableView(
                    "No templates yet",
                    systemImage: "rectangle.grid.2x2",
                    description: Text("Import a file from the toolbar to inspect template recommendations.")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(session.templateGalleryItems) { item in
                            Button {
                                guard item.selectable else {
                                    return
                                }
                                session.chooseTemplate(item.id)
                            } label: {
                                PlotTemplateCard(
                                    title: item.title,
                                    hint: item.hint,
                                    kind: session.thumbnailKind(for: item.id),
                                    aspectRatio: session.templateThumbnailAspectRatio(for: item.id),
                                    selected: session.selectedTemplateID == item.id,
                                    enabled: item.selectable
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!item.selectable)
                        }
                    }
                }
                .animation(MotionTokens.list, value: session.templateGalleryItems.map(\.id))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quinary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
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
            case .scatter:
                drawScatter(in: plotRect, context: &context, palette: palette)
            case .bar:
                drawBars(in: plotRect, context: &context, palette: palette)
            case .box:
                drawBoxes(in: plotRect, context: &context, palette: palette)
            case .violin:
                drawViolins(in: plotRect, context: &context, palette: palette)
            case .heatmap:
                drawHeatmap(in: plotRect, context: &context)
            case .fallback:
                drawScatter(in: plotRect, context: &context, palette: palette)
            }
        }
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

private struct PlotTemplateCard: View {
    let title: String
    let hint: String
    let kind: PlotTemplateThumbnailKind
    let aspectRatio: CGFloat
    let selected: Bool
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlotTemplateThumbnailView(kind: kind, aspectRatio: aspectRatio)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46, idealHeight: 62, maxHeight: 88)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Text(hint)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(hintForeground)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(hintBackground, in: Capsule())
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    selected ? Color.accentColor : Color.secondary.opacity(enabled ? 0.2 : 0.08),
                    lineWidth: selected ? 1.6 : 1
                )
        )
        .shadow(color: Color.black.opacity(selected ? 0.08 : 0.03), radius: selected ? 4 : 2, y: 1)
        .opacity(enabled ? 1 : 0.78)
        .animation(MotionTokens.selection, value: selected)
        .animation(MotionTokens.selection, value: enabled)
    }

    private var cardBackground: some ShapeStyle {
        selected ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
    }

    private var hintForeground: some ShapeStyle {
        if hint.lowercased().contains("recommend") {
            return AnyShapeStyle(Color.accentColor)
        }
        if hint.lowercased().contains("fallback") {
            return AnyShapeStyle(Color.orange)
        }
        return AnyShapeStyle(Color.secondary)
    }

    private var hintBackground: some ShapeStyle {
        if hint.lowercased().contains("recommend") {
            return AnyShapeStyle(Color.accentColor.opacity(0.14))
        }
        if hint.lowercased().contains("fallback") {
            return AnyShapeStyle(Color.orange.opacity(0.14))
        }
        return AnyShapeStyle(Color.secondary.opacity(0.12))
    }
}
