import AppKit
import SwiftUI

@main
struct SciPlotGodApp: App {
    @NSApplicationDelegateAdaptor(AppActivationDelegate.self) private var appDelegate
    @State private var model = SciPlotGodAppState.model

    var body: some Scene {
        WindowGroup("SciPlot God", id: "launcher") {
            LauncherWindowRoot(model: model)
                .frame(width: 660, height: 360)
        }
        .defaultSize(width: 660, height: 360)
        .windowResizability(.contentSize)
        .windowStyle(.plain)
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

@MainActor
private enum SciPlotGodAppState {
    static let model = AppModel()
}

@MainActor
final class AppActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppWindowManager.shared.openLauncherAfterSceneAttempt(model: SciPlotGodAppState.model)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppWindowManager.shared.openLauncher(model: SciPlotGodAppState.model)
        }
        return true
    }
}

@MainActor
final class AppWindowManager: NSObject, NSWindowDelegate {
    static let shared = AppWindowManager()

    private var controllers: [String: NSWindowController] = [:]

    func openLauncherAfterSceneAttempt(model: AppModel) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.openLauncher(model: model)
        }
    }

    func openWorkbenchAfterSceneAttempt(_ workbench: Workbench, model: AppModel) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.openWorkbench(workbench, model: model)
        }
    }

    func openLauncher(model: AppModel) {
        let id = "launcher"
        if let controller = controllers[id], let window = controller.window {
            configureLauncherWindow(window)
            present(window)
            return
        }

        if let existingWindow = NSApp.windows.first(where: { window in
            window.identifier?.rawValue == id || window.title == "SciPlot God"
        }) {
            configureLauncherWindow(existingWindow)
            present(existingWindow)
            return
        }

        let controller = NSWindowController(
            window: BorderlessLauncherWindow(
                contentRect: NSRect(origin: .zero, size: CGSize(width: 660, height: 360)),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
        )
        guard let window = controller.window else {
            return
        }
        window.contentViewController = NSHostingController(rootView: LauncherWindowRoot(model: model))
        configureLauncherWindow(window)
        window.center()

        controllers[id] = controller
        present(window)
    }

    func openWorkbench(_ workbench: Workbench, model: AppModel) {
        model.selectedWorkbench = workbench
        let sizing = sizing(for: workbench)
        openWindow(
            id: workbench.windowSceneID,
            title: workbench.title,
            size: sizing.defaultSize,
            minSize: sizing.minSize
        ) {
            WorkbenchWindowRoot(workbench: workbench, model: model)
        }
    }

    private func openWindow<Content: View>(
        id: String,
        title: String,
        size: CGSize,
        minSize: CGSize,
        @ViewBuilder content: () -> Content
    ) {
        if let controller = controllers[id], let window = controller.window {
            present(window)
            return
        }
        if let existingWindow = NSApp.windows.first(where: { window in
            window.identifier?.rawValue == id || window.title == title
        }) {
            present(existingWindow)
            return
        }

        let controller = NSWindowController(
            window: NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
        )
        guard let window = controller.window else {
            return
        }

        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.title = title
        window.minSize = minSize
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: content())
        window.center()

        controllers[id] = controller
        present(window)
    }

    private func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func configureLauncherWindow(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier("launcher")
        window.title = "SciPlot God"
        window.setContentSize(CGSize(width: 660, height: 360))
        window.minSize = CGSize(width: 660, height: 360)
        window.maxSize = CGSize(width: 660, height: 360)
        window.styleMask = [.borderless]
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func sizing(for workbench: Workbench) -> (defaultSize: CGSize, minSize: CGSize) {
        switch workbench {
        case .plot:
            return (CGSize(width: 1520, height: 900), CGSize(width: 1280, height: 760))
        case .dataStudio, .composer, .codeConsole:
            return (CGSize(width: 1360, height: 840), CGSize(width: 1180, height: 740))
        }
    }
}

private final class BorderlessLauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
