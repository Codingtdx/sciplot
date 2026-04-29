import AppKit
import SwiftUI

struct LauncherWindowRoot: View {
    @Bindable var model: AppModel

    var body: some View {
        AppWindowSharedChrome(model: model, bootstrapOnAppear: false) {
            LauncherView(model: model)
        }
        .toolbar(removing: .title)
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .containerBackground(.clear, for: .window)
        .background(WindowToolbarConfigurator())
    }
}

struct WorkbenchWindowRoot: View {
    let workbench: Workbench
    @Bindable var model: AppModel

    var body: some View {
        AppWindowSharedChrome(model: model) {
            workbenchContent
        }
        .focusedSceneValue(\.workbenchCommandContext, workbench)
        .toolbar {
            WorkbenchWindowToolbarContent(workbench: workbench, model: model)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(WindowToolbarConfigurator())
        .onAppear {
            model.selectedWorkbench = workbench
            model.refreshCodeConsoleContext()
        }
    }

    @ViewBuilder
    private var workbenchContent: some View {
        switch workbench {
        case .plot:
            PlotWorkbenchView(
                session: model.plotSession,
                isInspectorPresented: model.isInspectorPresented(for: .plot)
            )
        case .dataStudio:
            DataStudioWorkbenchView(
                session: model.dataStudioSession,
                isInspectorPresented: model.isInspectorPresented(for: .dataStudio)
            )
        case .composer:
            ComposerWorkbenchView(
                session: model.composerSession,
                isInspectorPresented: model.isInspectorPresented(for: .composer)
            )
        case .codeConsole:
            CodeConsoleWorkbenchView(
                session: model.codeConsoleSession,
                isInspectorPresented: model.isInspectorPresented(for: .codeConsole)
            )
        }
    }
}

private struct AppWindowSharedChrome<Content: View>: View {
    @Bindable var model: AppModel
    let bootstrapOnAppear: Bool
    let content: Content
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceModeRawValue = AppAppearanceMode.system.rawValue

    init(
        model: AppModel,
        bootstrapOnAppear: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.model = model
        self.bootstrapOnAppear = bootstrapOnAppear
        self.content = content()
    }

    var body: some View {
        content
            .proWorkspaceAppearance(appearanceMode: appearanceMode)
            .task {
                if bootstrapOnAppear {
                    await model.bootstrapIfNeeded()
                }
            }
            .modifier(WorkbenchWindowOpenHandler(model: model))
            .sheet(isPresented: $model.isQuickHelpPresented, onDismiss: {
                model.dismissQuickHelp()
            }) {
                QuickHelpSheet(
                    workbench: model.quickHelpWorkbench ?? model.selectedWorkbench,
                    dismiss: { model.dismissQuickHelp() }
                )
            }
            .confirmationDialog(
                "Replace the current Plot session?",
                isPresented: $model.isPlotReplacementConfirmationPresented
            ) {
                Button("Replace Current Session", role: .destructive) {
                    model.confirmPendingPlotReplacement()
                }
                Button("Cancel", role: .cancel) {
                    model.cancelPendingPlotReplacement()
                }
            } message: {
                Text("Opening a new Plot input will replace the current imported dataset and template state.")
            }
    }

    private var appearanceMode: AppAppearanceMode {
        AppAppearanceMode.storedValue(from: appearanceModeRawValue)
    }
}

struct WorkbenchWindowOpenHandler: ViewModifier {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onChange(of: model.requestedWorkbenchWindow) { _, requestedWindow in
                guard let requestedWindow else {
                    return
                }
                openWindow(id: requestedWindow.windowSceneID)
                AppWindowManager.shared.openWorkbenchAfterSceneAttempt(requestedWindow, model: model)
                model.consumeRequestedWorkbenchWindow(requestedWindow)
            }
    }
}

private struct WorkbenchWindowToolbarContent: ToolbarContent {
    let workbench: Workbench
    @Bindable var model: AppModel

    var body: some ToolbarContent {
        ToolbarItem(id: "workbenchActionGroup", placement: .primaryAction) {
            WorkbenchWindowActionGroup(workbench: workbench, model: model)
        }
    }
}

private struct WorkbenchWindowActionGroup: View {
    let workbench: Workbench
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.beginImport(for: workbench)
            } label: {
                Image(systemName: "tray.and.arrow.down")
            }
            .help("Import or Open")

            Button {
                Task { await model.export(for: workbench) }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(!model.exportAvailability(for: workbench).isEnabled)
            .help(model.exportHelpText(for: workbench))

            if workbench == .plot {
                Button {
                    model.showPlotDataWorkbook()
                } label: {
                    Image(systemName: "tablecells")
                }
                .disabled(!model.plotSession.dataWorkbookAvailability.isEnabled)
                .help(model.plotSession.dataWorkbookAvailability.reason ?? "Open Data Workbook")
            }

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)

            Button {
                model.showLauncher()
                openWindow(id: "launcher")
                AppWindowManager.shared.openLauncherAfterSceneAttempt(model: model)
            } label: {
                Image(systemName: "square.grid.2x2")
            }
            .help("Launcher")

            Button {
                model.showHelp(for: workbench)
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help("Quick Help")

            Button {
                model.toggleInspector(for: workbench)
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help(model.isInspectorPresented(for: workbench) ? "Hide Inspector" : "Show Inspector")
        }
        .controlSize(.regular)
    }
}

private struct WindowToolbarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let toolbar = view.window?.toolbar else {
                return
            }
            for delay in [0.0, 0.05, 0.15, 0.35, 0.8, 1.2] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak toolbar] in
                    guard let toolbar else {
                        return
                    }
                    configure(toolbar)
                }
            }
        }
    }

    private func configure(_ toolbar: NSToolbar) {
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
    }
}
