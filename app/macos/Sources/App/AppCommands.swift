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

        CommandMenu("Plot Tools") {
            ForEach(PlotTool.allCases) { tool in
                plotToolButton(tool)
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

            Button("Save Project…") {
                Task { await model.saveProject() }
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(!model.activeSaveProjectAvailability.isEnabled)

            Button("Save Project As…") {
                Task { await model.saveProjectAs() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!model.activeSaveProjectAvailability.isEnabled)

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

    @ViewBuilder
    private func plotToolButton(_ tool: PlotTool) -> some View {
        let availability = model.plotSession.plotToolAvailability(for: tool)
        let title = "\(tool.title) Tool"
        let button = Button(title) {
            model.plotSession.activatePlotTool(tool)
        }
        .disabled(model.selectedWorkbench != .plot || !availability.isEnabled)

        if let shortcutKey = tool.shortcutKey {
            button.keyboardShortcut(shortcutKey, modifiers: [.command, .option])
        } else {
            button
        }
    }
}
