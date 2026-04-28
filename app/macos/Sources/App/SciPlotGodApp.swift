import SwiftUI

@main
struct SciPlotGodApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("SciPlot God") {
            RootSplitView(model: model)
                .frame(minWidth: 1440, minHeight: 780)
        }
        .defaultSize(width: 1520, height: 900)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .commands {
            AppCommands(model: model)
        }
    }
}
