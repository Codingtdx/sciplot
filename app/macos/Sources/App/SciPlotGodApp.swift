import SwiftUI

@main
struct SciPlotGodApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("SciPlot God", id: "launcher") {
            LauncherWindowRoot(model: model)
                .frame(minWidth: 920, minHeight: 560)
        }
        .defaultSize(width: 1040, height: 640)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .commands {
            AppCommands(model: model)
        }

        Window("Plot", id: Workbench.plot.windowSceneID) {
            WorkbenchWindowRoot(workbench: .plot, model: model)
                .frame(minWidth: 1280, minHeight: 760)
        }
        .defaultSize(width: 1520, height: 900)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        Window("Data Studio", id: Workbench.dataStudio.windowSceneID) {
            WorkbenchWindowRoot(workbench: .dataStudio, model: model)
                .frame(minWidth: 1180, minHeight: 740)
        }
        .defaultSize(width: 1360, height: 840)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        Window("Composer", id: Workbench.composer.windowSceneID) {
            WorkbenchWindowRoot(workbench: .composer, model: model)
                .frame(minWidth: 1180, minHeight: 740)
        }
        .defaultSize(width: 1360, height: 840)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        Window("Code Console", id: Workbench.codeConsole.windowSceneID) {
            WorkbenchWindowRoot(workbench: .codeConsole, model: model)
                .frame(minWidth: 1180, minHeight: 740)
        }
        .defaultSize(width: 1360, height: 840)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
    }
}
