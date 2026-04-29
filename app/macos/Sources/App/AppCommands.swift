import SwiftUI

private struct WorkbenchCommandContextKey: FocusedValueKey {
    typealias Value = Workbench
}

extension FocusedValues {
    var workbenchCommandContext: Workbench? {
        get { self[WorkbenchCommandContextKey.self] }
        set { self[WorkbenchCommandContextKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    let model: AppModel
    @Binding var appearanceModeRawValue: String
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.workbenchCommandContext) private var focusedWorkbench

    var body: some Commands {
        CommandMenu("Workbench") {
            ForEach(Workbench.allCases) { workbench in
                Button(workbench.title) {
                    model.requestOpenWindow(for: workbench)
                    openWindow(id: workbench.windowSceneID)
                    AppWindowManager.shared.openWorkbenchAfterSceneAttempt(workbench, model: model)
                }
                .keyboardShortcut(workbench.shortcutKey, modifiers: [.command])
            }
        }

        CommandMenu("Plot Tools") {
            ForEach(PlotTool.allCases) { tool in
                plotToolButton(tool)
            }
        }

        CommandGroup(after: .toolbar) {
            Menu("Appearance") {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Button {
                        appearanceModeRawValue = mode.rawValue
                    } label: {
                        Label(mode.title, systemImage: appearanceMode == mode ? "checkmark" : mode.systemImage)
                    }
                }
            }
        }

        CommandGroup(after: .newItem) {
            Button("New Data Studio Session") {
                model.newDataStudioSession()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(commandWorkbench != .dataStudio)

            Button("Import or Open") {
                let workbench = commandWorkbench
                model.requestOpenWindow(for: workbench)
                openWindow(id: workbench.windowSceneID)
                AppWindowManager.shared.openWorkbenchAfterSceneAttempt(workbench, model: model)
                model.beginImport(for: workbench)
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Save Project…") {
                let workbench = commandWorkbench
                Task { await model.saveProject(for: workbench) }
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(!model.saveProjectAvailability(for: commandWorkbench).isEnabled)

            Button("Save Project As…") {
                let workbench = commandWorkbench
                Task { await model.saveProjectAs(for: workbench) }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!model.saveProjectAvailability(for: commandWorkbench).isEnabled)

            Button(model.exportCommandTitle(for: commandWorkbench)) {
                let workbench = commandWorkbench
                Task { await model.export(for: workbench) }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!model.exportAvailability(for: commandWorkbench).isEnabled)

            Button("Reveal in Finder") {
                model.revealOutput(for: commandWorkbench)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!model.revealAvailability(for: commandWorkbench).isEnabled)

            Button("Clear Current Session", role: .destructive) {
                model.clearCurrentDataStudioSession()
            }
            .disabled(commandWorkbench != .dataStudio)
        }

        CommandGroup(after: .sidebar) {
            Button(model.isInspectorPresented(for: commandWorkbench) ? "Hide Inspector" : "Show Inspector") {
                model.toggleInspector(for: commandWorkbench)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    private var commandWorkbench: Workbench {
        focusedWorkbench ?? model.selectedWorkbench
    }

    private var appearanceMode: AppAppearanceMode {
        AppAppearanceMode.storedValue(from: appearanceModeRawValue)
    }

    @ViewBuilder
    private func plotToolButton(_ tool: PlotTool) -> some View {
        let availability = model.plotSession.plotToolAvailability(for: tool)
        let title = "\(tool.title) Tool"
        let button = Button(title) {
            model.plotSession.activatePlotTool(tool)
        }
        .disabled(commandWorkbench != .plot || !availability.isEnabled)

        if let shortcutKey = tool.shortcutKey {
            button.keyboardShortcut(shortcutKey, modifiers: [.command, .option])
        } else {
            button
        }
    }
}
