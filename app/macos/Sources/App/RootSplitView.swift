import AppKit
import SwiftUI

struct RootSplitView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            WorkbenchSidebarRail(selection: $model.selectedWorkbench)
        } detail: {
            activeWorkbenchDetail
                .id(model.selectedWorkbench)
                .transition(MotionTokens.stateTransition)
                .animation(MotionTokens.workbenchSwitch, value: model.selectedWorkbench)
                .navigationTitle(activeWindowTitle)
                .navigationSubtitle(activeWindowSubtitle ?? "")
                .toolbar {
                    WorkbenchToolbarContent(model: model)
                }
                .overlay(alignment: .trailing) {
                    if !model.inspectorPresented {
                        InspectorEdgeRevealButton {
                            model.showInspector()
                        }
                        .padding(.trailing, 10)
                        .transition(MotionTokens.stateTransition)
                    }
                }
        }
        .inspector(isPresented: $model.inspectorPresented) {
            InspectorChromeRoot(title: activeInspectorTitle) {
                model.hideInspector()
            } content: {
                activeInspectorContent
            }
        }
        .toolbar(removing: .sidebarToggle)
        .inspectorColumnWidth(
            min: InspectorColumnLayoutPolicy.minWidth,
            ideal: InspectorColumnLayoutPolicy.idealWidth,
            max: InspectorColumnLayoutPolicy.maxWidth
        )
        .task {
            await model.bootstrapIfNeeded()
        }
        .onChange(of: model.selectedWorkbench) { _, _ in
            model.refreshCodeConsoleContext()
        }
        .onOpenURL { url in
            model.openPlotDocument(url)
        }
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
        .background(WindowToolbarConfigurator())
    }

    @ViewBuilder
    private var activeWorkbenchDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let runtimeIssueMessage = model.runtimeIssueMessage {
                DiagnosticIssueCard(
                    message: runtimeIssueMessage,
                    retryTitle: "Retry Runtime"
                ) {
                    Task { await model.bootstrapIfNeeded() }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            activeWorkbenchView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var activeWorkbenchView: some View {
        switch model.selectedWorkbench {
        case .plot:
            PlotWorkbenchView(session: model.plotSession)
        case .dataStudio:
            DataStudioWorkbenchView(session: model.dataStudioSession)
        case .composer:
            ComposerWorkbenchView(session: model.composerSession)
        case .codeConsole:
            CodeConsoleWorkbenchView(session: model.codeConsoleSession)
        }
    }

    @ViewBuilder
    private var activeInspectorContent: some View {
        switch model.selectedWorkbench {
        case .plot:
            PlotInspectorView(session: model.plotSession) {
                EmptyView()
            } trailingSections: {
                EmptyView()
            }
        case .dataStudio:
            DataStudioInspectorView(session: model.dataStudioSession)
        case .composer:
            ComposerInspectorView(session: model.composerSession)
        case .codeConsole:
            CodeConsoleContextView(session: model.codeConsoleSession)
        }
    }

    private var activeInspectorTitle: String {
        switch model.selectedWorkbench {
        case .plot:
            return plotInspectorTitle
        case .dataStudio:
            return "Data Studio"
        case .composer:
            return "Composer"
        case .codeConsole:
            return "Console"
        }
    }

    private var plotInspectorTitle: String {
        switch model.plotSession.canvasSelection {
        case .figure:
            return "Figure"
        case .axis(let axis):
            return axis.title
        case .dataPipeline:
            return "Data"
        case .layer(let layer):
            switch layer {
            case .fitOverlay:
                return "Fit Overlay"
            case .function:
                return "Function"
            case .referenceGuide:
                return "Guide"
            case .textAnnotation:
                return "Text"
            case .shapeAnnotation:
                return "Shape"
            case .series:
                return "Series"
            }
        }
    }

    private var activeWindowTitle: String {
        switch model.selectedWorkbench {
        case .plot:
            return model.plotSession.selectedSourceFilename ?? Workbench.plot.title
        case .dataStudio:
            return model.dataStudioSession.focusedWorkbook == nil
                ? Workbench.dataStudio.title
                : model.dataStudioSession.focusTitle
        case .composer:
            if let selectedPanelID = model.composerSession.selectedPanelID,
               let panel = model.composerSession.orderedPanels.first(where: { $0.id == selectedPanelID }) {
                return URL(fileURLWithPath: panel.filePath).lastPathComponent
            }
            return Workbench.composer.title
        case .codeConsole:
            return model.codeConsoleSession.selectedSourceFilename ?? Workbench.codeConsole.title
        }
    }

    private var activeWindowSubtitle: String? {
        switch model.selectedWorkbench {
        case .plot:
            return model.plotSession.selectedFileURL == nil ? nil : model.plotSession.selectedSheet.displayName
        case .dataStudio:
            return model.dataStudioSession.focusedWorkbook == nil ? nil : model.dataStudioSession.currentRecipeLabel
        case .composer:
            let count = model.composerSession.project.panels.count
            return count == 0 ? nil : "\(count) panels"
        case .codeConsole:
            return model.codeConsoleSession.selectedFileURL == nil ? nil : model.codeConsoleSession.selectedSheet.displayName
        }
    }

}

private struct WorkbenchSidebarRail: View {
    @Binding var selection: Workbench

    var body: some View {
        List(Workbench.allCases, selection: $selection) { workbench in
            Label(workbench.title, systemImage: workbench.systemImage)
                .lineLimit(1)
                .tag(workbench)
        }
        .listStyle(.sidebar)
        .navigationTitle("")
    }
}

private struct WorkbenchToolbarContent: ToolbarContent {
    @Bindable var model: AppModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                model.toggleWorkbenchSidebar()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help(model.columnVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.beginImportForActiveWorkbench()
            } label: {
                Image(systemName: "tray.and.arrow.down")
            }
            .help("Import or Open")

            Button {
                Task { await model.exportActiveWorkbench() }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(!model.activeExportAvailability.isEnabled)
            .help(model.activeExportHelpText)

            Button {
                model.showHelpForActiveWorkbench()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help("Quick Help")
        }
    }
}

private struct InspectorEdgeRevealButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 52)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        .help("Show Inspector")
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

        for index in toolbar.items.indices.reversed() {
            let rawIdentifier = toolbar.items[index].itemIdentifier.rawValue
            if rawIdentifier == "com.apple.SwiftUI.navigationSplitView.toggleSidebar"
                || rawIdentifier.contains("navigationSplitView.toggleSidebar") {
                toolbar.removeItem(at: index)
            }
        }
    }
}
