import SwiftUI

struct RootSplitView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
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
        }
        .inspector(isPresented: $model.inspectorPresented) {
            activeInspectorView
        }
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
    private var activeInspectorView: some View {
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

            Button {
                model.toggleInspector()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help(model.inspectorPresented ? "Hide Inspector" : "Show Inspector")
        }
    }
}
