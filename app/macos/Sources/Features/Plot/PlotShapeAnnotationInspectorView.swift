import SwiftUI

struct PlotShapeAnnotationInspectorView: View {
    @Bindable var session: PlotSession
    @State private var selection: PlotLayerSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlotInspectorLayerListView(session: session, selection: $selection)
            PlotSelectedLayerEditorView(session: session, selection: selection)
            PlotArrangeInspectorView(session: session, selection: selection)
        }
    }
}
