from __future__ import annotations

from pathlib import Path

from scripts import check_macos_gui_presentation


def _write_sources(root: Path, overrides: dict[str, str] | None = None) -> None:
    sources = {
        "app/macos/Sources/App/SciPlotGodApp.swift": """
import SwiftUI
@main
struct SciPlotGodApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup("SciPlot God") { RootSplitView(model: model) }
            .defaultSize(width: 1520, height: 900)
            .windowResizability(.contentMinSize)
            .defaultLaunchBehavior(.presented)
            .restorationBehavior(.disabled)
            .commands { AppCommands(model: model) }
    }
}
""",
        "app/macos/Sources/App/RootSplitView.swift": """
struct RootSplitView {
    var body: some View {
        NavigationSplitView(columnVisibility: $model.columnVisibility) {}
        WorkbenchSidebarRail()
        WorkbenchContentShell(title: "Plot") {}
        WorkbenchToolbarContent()
        InspectorChromeRoot(title: "Figure") {}
    }
}
private struct WorkbenchToolbarContent {
    var body: some View {
        ToolbarItem(id: "globalActionGroup", placement: .primaryAction) {}
        WorkbenchHeaderActionGroup(model: model)
    }
}
private struct WorkbenchHeaderActionGroup {
    func body() {
        model.beginImportForActiveWorkbench()
        model.exportActiveWorkbench()
        model.showHelpForActiveWorkbench()
        model.toggleInspector()
        Image(systemName: "sidebar.right")
    }
}
private struct WindowToolbarConfigurator {}
""",
        "app/macos/Sources/App/AppCommands.swift": """
struct AppCommands {
    var body: some Commands {
        CommandMenu("Plot Tools") {
            model.plotSession.activatePlotTool(tool)
                .keyboardShortcut(shortcutKey, modifiers: [.command, .option])
        }
    }
}
""",
        "app/macos/Sources/Features/Plot/PlotTemplateView.swift": """
enum PlotTemplateRailDensity { case regular, compact }
struct PlotTemplateLibraryView {
    var body: some View {
        WorkbenchRailTitle(title: "Templates")
        PlotCompactTemplateLibraryView()
        PlotTemplateRow()
        PlotTemplateBrowserPopover()
    }
}
""",
        "app/macos/Sources/Features/Plot/PlotInspectorView.swift": """
ScrollView {
    PlotSelectionInspectorView()
    session.canvasSelection
    PlotSelectedLayerEditorView()
    InspectorSection(title: "Axis") {}
    InspectorSection(title: "Fit Overlay") {}
}
""",
        "app/macos/Sources/Features/Plot/PlotDataPipelineInspectorView.swift": """
struct PlotDataPipelineInspectorView {
    let selection: PlotDataPipelineSelection? = nil
    var pipelineList: String { "" }
    var selectedEditor: String { "" }
    func pipelineRow() {}
}
""",
        "app/macos/Sources/Features/Plot/PlotInspectorLayerListView.swift": """
struct PlotInspectorLayerListView {
    let selection: PlotLayerSelection? = nil
    func layerRow() {}
    func select(id: String) {
        session.selectedReferenceGuideID = id
        session.selectedTextAnnotationID = id
        session.selectedShapeAnnotationID = id
    }
}
""",
        "app/macos/Sources/Features/Plot/PlotSelectedLayerEditorView.swift": """
struct PlotSelectedLayerEditorView {
    let selection: PlotLayerSelection?
    let exactGuideValueEditor = "Value"
    let exactGuideRangeEditor = "Start End"
}
""",
        "app/macos/Sources/Features/Plot/PlotRefineView.swift": """
PlotFloatingToolPalette(session: session)
ProgressView()
""",
        "app/macos/Sources/Features/Plot/PlotInspectorMode.swift": """
enum PlotTool {}
enum PlotCanvasSelection {}
struct PlotFloatingToolPalette {
    static let floatingPaletteTools = [PlotTool.select]
    static let floatingPaletteToolGroups = [[PlotTool.select]]
    var title: String { "Select" }
    var shortcutKey = "v"
    var opensToolPopover = true
    func plotToolAvailability() {}
    func activatePlotTool() {}
    func selectCanvasSelection() {}
}
struct PlotToolPopoverContent {}
struct PlotGuideToolCreateForm {
    let axisTarget = "x"
    let valueText = "0"
    let startText = "0"
    let endText = "1"
}
enum PlotLayerSelection {}
""",
        "app/macos/Sources/Features/Plot/PlotWorkbenchView.swift": """
PlotTemplateLibraryView(session: session, density: templateRailDensity)
PlotWorkspaceLayoutPolicy.templateRailCollapseThreshold
PlotTemplateRailDensity.compact
""",
        "app/macos/Sources/Shared/UI/StateViews.swift": """
enum WorkbenchHeaderMetrics {
    static let height: CGFloat = 56
}
enum InspectorColumnLayoutPolicy {
    static let minWidth: CGFloat = 360
}
struct WorkbenchContentShell {
    var body: some View {
        EmptyView().frame(height: WorkbenchHeaderMetrics.height)
    }
}
struct InspectorHeaderTabs {}
struct InspectorChromeRoot {
    var body: some View {
        EmptyView().frame(height: WorkbenchHeaderMetrics.height)
    }
}
""",
        "app/macos/Sources/Features/Plot/PlotDataWorkbookSheet.swift": (
            "struct PlotDataWorkbookSheet { let dataPipelineSummary = \"\" }\n"
        ),
        "app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift": (
            "InspectorSection(title: \"Actions\")\nInspectorSection(title: \"Figure\")\n"
        ),
        "app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift": (
            "WorkbenchRailTitle(title: \"Workbook Groups\")\n"
        ),
        "app/macos/Sources/Features/Composer/ComposerAssetBrowserView.swift": "SubtleStageHint(title: \"Import\")\n",
        "app/macos/Sources/Features/Composer/ComposerCanvasView.swift": (
            "RoundedRectangle(cornerRadius: 22)\n"
        ),
        "app/macos/Sources/Features/Composer/ComposerInspectorView.swift": (
            "InspectorSection(title: \"Preview\") { ComposerInspectorPreviewContent() }\n"
        ),
        "app/macos/Sources/Features/Composer/ComposerWorkbenchView.swift": "ComposerCanvasView()\n",
        "app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift": (
            "CodeConsoleOutputsView()\n"
        ),
        "app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift": (
            "SubtleStageHint(title: \"Run\")\n"
        ),
        "app/macos/Sources/Features/CodeConsole/CodeConsoleContextView.swift": "InspectorSection()\n",
    }
    if overrides:
        sources.update(overrides)

    for relative_path, content in sources.items():
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def test_gui_presentation_checks_accept_expected_grammar(tmp_path: Path) -> None:
    _write_sources(tmp_path)

    issues = check_macos_gui_presentation.run_checks(tmp_path)

    assert issues == []


def test_gui_presentation_checks_report_forbidden_card_grammar(tmp_path: Path) -> None:
    _write_sources(
        tmp_path,
        {
            "app/macos/Sources/Features/Plot/PlotTemplateView.swift": (
                "PlotTemplateRow()\nPlotTemplateCard()\n"
            )
        },
    )

    issues = check_macos_gui_presentation.run_checks(tmp_path)

    assert any("PlotTemplateCard" in issue for issue in issues)
