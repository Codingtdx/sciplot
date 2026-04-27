import SwiftUI

struct PlotDataTransformInspectorView: View {
    @Bindable var session: PlotSession
    @State private var selection: PlotDataPipelineSelection?

    var body: some View {
        PlotDataPipelineInspectorView(
            session: session,
            selection: $selection
        )
    }
}
