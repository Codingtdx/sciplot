import SwiftUI

struct ComposerCanvasView: View {
    let session: ComposerSession

    var body: some View {
        GeometryReader { geometry in
            let scale = min(
                geometry.size.width / session.project.canvasWidthMm,
                geometry.size.height / session.project.canvasHeightMm
            )
            let canvasWidth = session.project.canvasWidthMm * scale
            let canvasHeight = session.project.canvasHeightMm * scale

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                    .frame(width: canvasWidth, height: canvasHeight)

                ForEach(session.project.regions) { region in
                    let rect = regionRect(region, project: session.project, scale: scale)
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }

                ForEach(session.project.panels) { panel in
                    let isSelected = panel.id == session.selectedPanelID
                    let panelLabel = panel.label ?? panel.id
                    let fillColor = panel.kind == "graph" ? Color.accentColor.opacity(0.18) : Color.orange.opacity(0.18)
                    let strokeColor = isSelected ? Color.accentColor : Color.secondary.opacity(0.35)
                    let lineWidth = isSelected ? 2.0 : 1.0
                    RoundedRectangle(cornerRadius: 10)
                        .fill(fillColor)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(strokeColor, lineWidth: lineWidth)
                        }
                        .frame(width: panel.wMm * scale, height: panel.hMm * scale)
                        .overlay(alignment: .topLeading) {
                            Text(panelLabel)
                                .font(.caption.weight(.semibold))
                                .padding(8)
                        }
                        .offset(x: panel.xMm * scale, y: panel.yMm * scale)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if session.selectedPanelID != panel.id {
                                        session.selectPanel(panel.id)
                                    }
                                    session.beginPanelDrag()
                                    session.dragSelectedPanel(translation: value.translation, scale: scale)
                                }
                                .onEnded { _ in
                                    session.endPanelDrag()
                                }
                        )
                        .onTapGesture {
                            session.selectPanel(panel.id)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(.quinary.opacity(0.18), in: RoundedRectangle(cornerRadius: 24))
    }

    private func regionRect(
        _ region: ComposerRegionPayload,
        project: ComposerRequestPayload,
        scale: Double
    ) -> CGRect {
        let grid = project.layoutGrid
        let x = (grid.frameXMm + Double(region.col) * grid.cellWidthMm) * scale
        let y = (grid.frameYMm + Double(region.row) * grid.cellHeightMm) * scale
        let width = Double(region.colSpan) * grid.cellWidthMm * scale
        let height = Double(region.rowSpan) * grid.cellHeightMm * scale
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
