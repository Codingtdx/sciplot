import SwiftUI

struct PlotOverlayTransformControls: View {
    let title: String
    let xLabel: String
    let yLabel: String
    let xValue: Double
    let yValue: Double
    let stepX: Double
    let stepY: Double
    let onAdjust: (Double, Double) -> Void

    @State private var dragTranslation: CGSize = .zero
    private let padSize = CGSize(width: 118, height: 74)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                VStack(spacing: 6) {
                    movePad
                    HStack(spacing: 6) {
                        Text("\(xLabel): \(formatted(xValue))")
                        Text("\(yLabel): \(formatted(yValue))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                nudgeButtons
            }
        }
    }

    private var movePad: some View {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - dragTranslation.width,
                    height: value.translation.height - dragTranslation.height
                )
                dragTranslation = value.translation

                let xScale = max(stepX, 0.0001) * 12.0
                let yScale = max(stepY, 0.0001) * 12.0
                let deltaX = Double(delta.width / padSize.width) * xScale
                let deltaY = Double(-delta.height / padSize.height) * yScale
                onAdjust(deltaX, deltaY)
            }
            .onEnded { _ in
                dragTranslation = .zero
            }

        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))

            Path { path in
                path.move(to: CGPoint(x: 0, y: padSize.height / 2))
                path.addLine(to: CGPoint(x: padSize.width, y: padSize.height / 2))
                path.move(to: CGPoint(x: padSize.width / 2, y: 0))
                path.addLine(to: CGPoint(x: padSize.width / 2, y: padSize.height))
            }
            .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            Circle()
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: 14, height: 14)
        }
        .frame(width: padSize.width, height: padSize.height)
        .contentShape(Rectangle())
        .gesture(drag)
    }

    private var nudgeButtons: some View {
        VStack(spacing: 4) {
            Button {
                onAdjust(0, stepY)
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            HStack(spacing: 4) {
                Button {
                    onAdjust(-stepX, 0)
                } label: {
                    Image(systemName: "arrow.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onAdjust(stepX, 0)
                } label: {
                    Image(systemName: "arrow.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                onAdjust(0, -stepY)
            } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)))
    }
}
