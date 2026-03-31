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
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
            let axisColor = Color.secondary.opacity(0.6)
            let strokeColor = Color.accentColor
            let fillColor = Color.accentColor.opacity(0.35)

            drawAxes(in: rect, context: &context, axisColor: axisColor)

            switch kind {
            case .curve:
                drawCurve(in: rect, context: &context, color: strokeColor, withPoints: false)
            case .pointLine:
                drawCurve(in: rect, context: &context, color: strokeColor, withPoints: true)
            case .scatter:
                drawScatter(in: rect, context: &context, color: fillColor)
            case .bar:
                drawBars(in: rect, context: &context, color: fillColor)
            case .box:
                drawBoxes(in: rect, context: &context, color: strokeColor)
            case .violin:
                drawViolins(in: rect, context: &context, color: fillColor)
            case .heatmap:
                drawHeatmap(in: rect, context: &context)
            case .fallback:
                drawScatter(in: rect, context: &context, color: fillColor)
            }
        }
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private func drawAxes(in rect: CGRect, context: inout GraphicsContext, axisColor: Color) {
        let left = rect.minX + 10
        let bottom = rect.maxY - 8
        var axisPath = Path()
        axisPath.move(to: CGPoint(x: left, y: rect.minY + 8))
        axisPath.addLine(to: CGPoint(x: left, y: bottom))
        axisPath.addLine(to: CGPoint(x: rect.maxX - 6, y: bottom))
        context.stroke(axisPath, with: .color(axisColor), lineWidth: 1)
    }

    private func drawCurve(
        in rect: CGRect,
        context: inout GraphicsContext,
        color: Color,
        withPoints: Bool
    ) {
        let points = samplePlotPoints(in: rect)
        var path = Path()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        context.stroke(path, with: .color(color), lineWidth: 1.8)

        guard withPoints else {
            return
        }
        for point in points {
            let dotRect = CGRect(x: point.x - 1.8, y: point.y - 1.8, width: 3.6, height: 3.6)
            context.fill(Path(ellipseIn: dotRect), with: .color(color))
        }
    }

    private func drawScatter(in rect: CGRect, context: inout GraphicsContext, color: Color) {
        for point in samplePlotPoints(in: rect) {
            let dotRect = CGRect(x: point.x - 2.2, y: point.y - 2.2, width: 4.4, height: 4.4)
            context.fill(Path(ellipseIn: dotRect), with: .color(color))
        }
    }

    private func drawBars(in rect: CGRect, context: inout GraphicsContext, color: Color) {
        let barWidths: CGFloat = 8
        let baseY = rect.maxY - 8
        let startX = rect.minX + 18
        let heights: [CGFloat] = [12, 20, 30, 24]
        for (index, height) in heights.enumerated() {
            let x = startX + CGFloat(index) * 12
            let barRect = CGRect(x: x, y: baseY - height, width: barWidths, height: height)
            context.fill(Path(roundedRect: barRect, cornerRadius: 2), with: .color(color))
        }
    }

    private func drawBoxes(in rect: CGRect, context: inout GraphicsContext, color: Color) {
        let centers: [CGFloat] = [rect.minX + 24, rect.minX + 40, rect.minX + 56]
        for center in centers {
            let boxRect = CGRect(x: center - 4, y: rect.midY - 8, width: 8, height: 14)
            context.stroke(Path(roundedRect: boxRect, cornerRadius: 2), with: .color(color), lineWidth: 1.5)
            var whisker = Path()
            whisker.move(to: CGPoint(x: center, y: boxRect.minY - 6))
            whisker.addLine(to: CGPoint(x: center, y: boxRect.maxY + 6))
            context.stroke(whisker, with: .color(color), lineWidth: 1)
        }
    }

    private func drawViolins(in rect: CGRect, context: inout GraphicsContext, color: Color) {
        let centers: [CGFloat] = [rect.minX + 24, rect.minX + 42, rect.minX + 60]
        for center in centers {
            var shape = Path()
            shape.move(to: CGPoint(x: center, y: rect.minY + 16))
            shape.addQuadCurve(
                to: CGPoint(x: center, y: rect.maxY - 14),
                control: CGPoint(x: center + 6, y: rect.midY)
            )
            shape.addQuadCurve(
                to: CGPoint(x: center, y: rect.minY + 16),
                control: CGPoint(x: center - 6, y: rect.midY)
            )
            context.fill(shape, with: .color(color))
        }
    }

    private func drawHeatmap(in rect: CGRect, context: inout GraphicsContext) {
        let cols = 5
        let rows = 3
        let cellWidth = (rect.width - 20) / CGFloat(cols)
        let cellHeight = (rect.height - 18) / CGFloat(rows)
        let startX = rect.minX + 12
        let startY = rect.minY + 8
        for row in 0..<rows {
            for col in 0..<cols {
                let t = Double((row * cols) + col) / Double(rows * cols)
                let rect = CGRect(
                    x: startX + CGFloat(col) * cellWidth,
                    y: startY + CGFloat(row) * cellHeight,
                    width: cellWidth - 1,
                    height: cellHeight - 1
                )
                let color = Color(
                    hue: 0.58 - (0.35 * t),
                    saturation: 0.65,
                    brightness: 0.92 - (0.28 * t)
                )
                context.fill(Path(rect), with: .color(color))
            }
        }
    }

    private func samplePlotPoints(in rect: CGRect) -> [CGPoint] {
        let left = rect.minX + 12
        let bottom = rect.maxY - 8
        let width = rect.width - 20
        let height = rect.height - 16
        let pairs: [(CGFloat, CGFloat)] = [
            (0.0, 0.85),
            (0.22, 0.62),
            (0.46, 0.5),
            (0.7, 0.32),
            (1.0, 0.2),
        ]
        return pairs.map { x, y in
            CGPoint(x: left + (x * width), y: (bottom - (y * height)))
        }
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quinary.opacity(0.35), in: Capsule())
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
        .opacity(enabled ? 1 : 0.78)
    }

    private var cardBackground: some ShapeStyle {
        selected ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
    }
}
