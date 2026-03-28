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
                    ToolbarItemGroup(placement: .automatic) {
                        Button("Import", systemImage: "tray.and.arrow.down") {
                            model.beginImportForActiveWorkbench()
                        }

                        Button("Export", systemImage: "square.and.arrow.up") {
                            Task { await model.exportActiveWorkbench() }
                        }

                        Button("Reveal", systemImage: "folder") {
                            model.revealActiveOutput()
                        }

                        Button(
                            model.inspectorPresented ? "Hide Inspector" : "Show Inspector",
                            systemImage: model.inspectorPresented ? "sidebar.right" : "sidebar.right"
                        ) {
                            model.toggleInspector()
                        }
                    }

                    ToolbarItem(placement: .status) {
                        runtimeStatusView
                    }
                }
        }
        .inspector(isPresented: $model.inspectorPresented) {
            activeInspectorView
                .frame(minWidth: 280)
        }
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
        case .dataCleanup:
            DataCleanupWorkbenchView(session: model.dataCleanupSession)
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
        case .dataCleanup:
            CleanupInspectorView(session: model.dataCleanupSession)
        case .composer:
            ComposerInspectorView(session: model.composerSession)
        case .codeConsole:
            CodeConsoleContextView(session: model.codeConsoleSession)
        }
    }

    @ViewBuilder
    private var runtimeStatusView: some View {
        switch model.runtime.status {
        case .idle:
            Label("Sidecar idle", systemImage: "bolt.horizontal.circle")
                .foregroundStyle(.secondary)
        case .starting:
            Label("Starting sidecar", systemImage: "bolt.horizontal.circle.fill")
                .foregroundStyle(.secondary)
        case .running:
            Label("Sidecar ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help(message)
        }
    }
}
