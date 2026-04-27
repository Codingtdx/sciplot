import SwiftUI

@main
struct SciPlotGodApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("SciPlot God") {
            RootSplitView(model: model)
                .frame(minWidth: 1160, minHeight: 760)
        }
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .commands {
            AppCommands(model: model)
        }
    }
}
