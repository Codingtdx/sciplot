import SwiftUI

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Workbench") {
            ForEach(Workbench.allCases) { workbench in
                Button(workbench.title) {
                    model.switchWorkbench(workbench)
                }
                .keyboardShortcut(workbench.shortcutKey, modifiers: [.command])
            }
        }

        CommandGroup(after: .newItem) {
            Button("New Data Studio Session") {
                model.newDataStudioSession()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(model.selectedWorkbench != .dataStudio)

            Button("Import or Open") {
                model.beginImportForActiveWorkbench()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button(model.activeExportCommandTitle) {
                Task { await model.exportActiveWorkbench() }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!model.activeExportAvailability.isEnabled)

            Button("Reveal in Finder") {
                model.revealActiveOutput()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!model.activeRevealAvailability.isEnabled)

            Button("Clear Current Session", role: .destructive) {
                model.clearCurrentDataStudioSession()
            }
            .disabled(model.selectedWorkbench != .dataStudio)
        }

        CommandGroup(after: .sidebar) {
            Button(model.inspectorPresented ? "Hide Inspector" : "Show Inspector") {
                model.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
