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
            Button("Import or Open") {
                model.beginImportForActiveWorkbench()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Export Current Result") {
                Task { await model.exportActiveWorkbench() }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Reveal in Finder") {
                model.revealActiveOutput()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Button(model.inspectorPresented ? "Hide Inspector" : "Show Inspector") {
                model.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
