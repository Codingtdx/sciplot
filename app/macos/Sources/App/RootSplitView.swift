import SwiftUI

struct RootSplitView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(Workbench.allCases, selection: $model.selectedWorkbench) { workbench in
                Label(workbench.title, systemImage: workbench.systemImage)
                    .tag(workbench)
            }
            .navigationTitle("SciPlot God")
            .listStyle(.sidebar)
        } detail: {
            activeWorkbenchView
                .navigationTitle(model.selectedWorkbench.title)
                .toolbar {
                    activeToolbarContent
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
        .toolbar(removing: .sidebarToggle)
        .task {
            await model.bootstrapIfNeeded()
        }
        .onChange(of: model.selectedWorkbench) { _, _ in
            model.refreshCodeConsoleContext()
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
    private var activeWorkbenchView: some View {
        switch model.selectedWorkbench {
        case .plot:
            PlotWorkbenchView(session: model.plotSession, bootstrapErrorMessage: model.bootstrapErrorMessage)
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
            PlotInspectorView(session: model.plotSession)
        case .dataStudio:
            DataStudioInspectorView(session: model.dataStudioSession)
        case .composer:
            ComposerInspectorView(session: model.composerSession)
        case .codeConsole:
            CodeConsoleContextView(session: model.codeConsoleSession)
        }
    }

    @ToolbarContentBuilder
    private var activeToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button("Import", systemImage: "tray.and.arrow.down") {
                model.beginImportForActiveWorkbench()
            }

            Button("Export", systemImage: "square.and.arrow.up") {
                Task { await model.exportActiveWorkbench() }
            }

            Button("Help", systemImage: "questionmark.circle") {
                model.showHelpForActiveWorkbench()
            }

            Button(
                model.inspectorPresented ? "Hide Inspector" : "Show Inspector",
                systemImage: "sidebar.right"
            ) {
                model.toggleInspector()
            }

            if model.selectedWorkbench == .dataStudio {
                Menu {
                    Button("New Data Studio Session") {
                        model.newDataStudioSession()
                    }

                    Button("Clear Current Session", role: .destructive) {
                        model.clearCurrentDataStudioSession()
                    }
                } label: {
                    Label("Data Studio Menu", systemImage: "ellipsis.circle")
                }
            }
        }
    }
}
