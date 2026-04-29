from __future__ import annotations

from pathlib import Path

from scripts import check_macos_gui_presentation


def _write_sources(root: Path, overrides: dict[str, str] | None = None) -> None:
    sources = {
        "app/macos/Sources/App/SciPlotGodApp.swift": """
import SwiftUI
@main
struct SciPlotGodApp: App {
    @State private var model = SciPlotGodAppState.model
    var body: some Scene {
        WindowGroup("SciPlot God", id: "launcher") { LauncherWindowRoot(model: model) }
            .defaultSize(width: 1520, height: 900)
            .windowResizability(.contentMinSize)
            .defaultLaunchBehavior(.presented)
            .restorationBehavior(.disabled)
            .commands { AppCommands(model: model) }
        Window("Plot", id: Workbench.plot.windowSceneID) {
            WorkbenchWindowRoot(workbench: .plot, model: model)
        }
        Window("Data Studio", id: Workbench.dataStudio.windowSceneID) {
            WorkbenchWindowRoot(workbench: .dataStudio, model: model)
        }
        Window("Composer", id: Workbench.composer.windowSceneID) {
            WorkbenchWindowRoot(workbench: .composer, model: model)
        }
        Window("Code Console", id: Workbench.codeConsole.windowSceneID) {
            WorkbenchWindowRoot(workbench: .codeConsole, model: model)
        }
    }
}
private enum SciPlotGodAppState {
    static let model = AppModel()
}
final class AppWindowManager {
    func openLauncherAfterSceneAttempt() {}
}
""",
        "app/macos/Sources/App/RootSplitView.swift": """
struct LauncherWindowRoot {
    var body: some View {
        AppWindowSharedChrome(model: model, bootstrapOnAppear: false) {
            LauncherView(model: model)
        }
            .modifier(WorkbenchWindowOpenHandler(model: model))
    }
}
struct WorkbenchWindowRoot {
    let workbench: Workbench
    var body: some View {
        PlotWorkbenchView(session: model.plotSession)
            .focusedSceneValue(\\.workbenchCommandContext, workbench)
            .modifier(WorkbenchWindowOpenHandler(model: model))
    }
}
private struct WorkbenchWindowToolbarContent {
    var body: some View {
        WorkbenchWindowToolbarContent(workbench: workbench, model: model)
        ToolbarItem(id: "workbenchActionGroup", placement: .primaryAction) {
            model.beginImport(for: workbench)
            model.export(for: workbench)
            if workbench == .plot {
                model.showPlotDataWorkbook()
            }
            model.showHelp(for: workbench)
            model.toggleInspector(for: workbench)
        }
    }
}
struct WorkbenchWindowOpenHandler {}
private struct WindowToolbarConfigurator {}
""",
        "app/macos/Sources/App/AppModel.swift": """
final class AppModel {
    var requestedWorkbenchWindow: Workbench?
    func enterWorkbench(_ workbench: Workbench) {}
    func showLauncher() {}
    func beginLauncherPrimaryAction(for workbench: Workbench) { beginImport(for: workbench) }
    func beginImport(for workbench: Workbench) {}
    func export(for workbench: Workbench) async {}
    func saveProject(for workbench: Workbench) async {}
    func showHelp(for workbench: Workbench) {}
    func requestOpenWindow(for workbench: Workbench) {}
}
""",
        "app/macos/Sources/App/LauncherView.swift": """
struct LauncherView {
    @Environment(\\.openWindow) private var openWindow
    var body: some View {
        GlassEffectContainer {
            Workbench.allCases
            LauncherWelcomeSurface()
            LauncherModuleEntryRow()
            Button("Plot") { openWindow(id: Workbench.plot.windowSceneID) }
            Button("Import") { model.beginLauncherPrimaryAction(for: .plot) }
            Button("Data Studio") { model.beginLauncherPrimaryAction(for: .dataStudio) }
            Button("Composer") { model.beginLauncherPrimaryAction(for: .composer) }
            Button("Code Console") { model.beginLauncherPrimaryAction(for: .codeConsole) }
        }
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
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
    adjustmentCategory: PlotAdjustmentCategory?
    adjustmentCategoryContent
    figureAdjustmentContent
    axesAdjustmentContent
    legendAdjustmentContent
    guidesAdjustmentContent
    fitAdjustmentContent
    functionsAdjustmentContent
    annotationsAdjustmentContent
    advancedAxesAdjustmentContent
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
PlotPreviewStage(session: session)
Base64PreviewImageView(base64PNG: previewPNG)
Base64PDFPreviewView(base64PDF: preview.pdfBase64)
ProgressView()
""",
        "app/macos/Sources/Features/Plot/PlotInspectorMode.swift": """
enum PlotAdjustmentCategory {
    static let railCategories = [
        PlotAdjustmentRailItem(category: .figure),
        PlotAdjustmentRailItem(category: .axes),
        PlotAdjustmentRailItem(category: .legend),
        PlotAdjustmentRailItem(category: .guides),
        PlotAdjustmentRailItem(category: .fit),
        PlotAdjustmentRailItem(category: .functions),
        PlotAdjustmentRailItem(category: .annotations),
        PlotAdjustmentRailItem(category: .advancedAxes)
    ]
    var title: String { "Figure" }
}
struct PlotAdjustmentRailItem {}
func plotAdjustmentAvailability() {}
func selectPlotAdjustmentCategory() {}
enum PlotTool {}
enum PlotCanvasSelection {}
enum PlotLayerSelection {}
var shortcutKey = "v"
func plotToolAvailability() {}
func activatePlotTool() {}
func selectCanvasSelection() {}
""",
        "app/macos/Sources/Features/Plot/PlotWorkbenchView.swift": """
PlotPixelmatorWorkspace(session: session)
PlotSourceTypePanel(session: session)
PlotRefineView(session: session)
PlotAdjustmentInspector(session: session)
PlotAdjustmentRail(session: session)
@State private var isPlotTypeChooserPresented = false
ForEach(session.templateGalleryItems) { item in PlotTypeCard(item: item) }
Button { isPlotTypeChooserPresented = true } label: {
    Label("More", systemImage: "square.grid.2x2")
}
.sheet(isPresented: $isPlotTypeChooserPresented) {
    PlotTypeChooserSheet(session: session, isPresented: $isPlotTypeChooserPresented)
}
ForEach(session.plotTypeItems) { item in item.title }
""",
        "app/macos/Sources/Shared/UI/StateViews.swift": """
enum InspectorColumnLayoutPolicy {
    static let minWidth: CGFloat = 320
    static let idealWidth: CGFloat = 360
    static let maxWidth: CGFloat = 420
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
            "DataStudioFigureRailSection(session: session)\n"
            "DataStudioFigureRailRow\n"
            "let figureFamilyBinding = Binding<String?>.constant(nil)\n"
        ),
        "app/macos/Sources/Features/Composer/ComposerAssetBrowserView.swift": (
            "enum ComposerLibraryFilter {}\n"
            "Picker(\"Library Filter\", selection: .constant(ComposerLibraryFilter.all)) {}\n"
            "let filteredPanels = []\n"
            "ComposerLibraryRow(panel: panel)\n"
            "SubtleStageHint(title: \"Library\")\n"
        ),
        "app/macos/Sources/Features/Composer/ComposerCanvasView.swift": (
            "RoundedRectangle(cornerRadius: 22)\n"
        ),
        "app/macos/Sources/Features/Composer/ComposerInspectorView.swift": (
            "InspectorSection(title: \"Selection\") {}\n"
            "InspectorSection(title: \"Placement\") {}\n"
            "InspectorSection(title: \"Panel\") {}\n"
            "InspectorSection(title: \"Actions\") {}\n"
            "InspectorSection(title: \"Preview\") { ComposerInspectorPreviewContent() }\n"
        ),
        "app/macos/Sources/Features/Composer/ComposerWorkbenchView.swift": "ComposerCanvasView()\n",
        "app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift": (
            "CodeConsoleSourceRailView(session: session)\nCodeConsoleOutputsView()\n"
            "CodeConsoleRunWorkspaceView(session: session)\n"
            "Picker(\"Sheet\", selection: selectedSheetSelection)\n"
        ),
        "app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift": (
            "SubtleStageHint(title: \"Run\")\n"
        ),
        "app/macos/Sources/Features/CodeConsole/CodeConsoleContextView.swift": (
            "InspectorSection(title: \"Binding\")\n"
            "InspectorSection(title: \"Runner\")\n"
            "InspectorSection(title: \"Outputs & Handoff\")\n"
            "InspectorSection(title: \"Advanced\")\n"
            "private var advancedSection: some View {}\n"
            "Button(\"Open Source\") {}\n"
            "Button(\"Reveal Source\") {}\n"
        ),
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


def test_gui_presentation_checks_reject_duplicate_app_commands(tmp_path: Path) -> None:
    _write_sources(
        tmp_path,
        {
            "app/macos/Sources/App/SciPlotGodApp.swift": """
import SwiftUI
@main
struct SciPlotGodApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup("SciPlot God", id: "launcher") { LauncherWindowRoot(model: model) }
            .defaultSize(width: 1520, height: 900)
            .windowResizability(.contentMinSize)
            .defaultLaunchBehavior(.presented)
            .restorationBehavior(.disabled)
            .commands { AppCommands(model: model) }
        Window("Plot", id: Workbench.plot.windowSceneID) {
            WorkbenchWindowRoot(workbench: .plot, model: model)
        }
            .commands { AppCommands(model: model) }
        Window("Data Studio", id: Workbench.dataStudio.windowSceneID) {
            WorkbenchWindowRoot(workbench: .dataStudio, model: model)
        }
        Window("Composer", id: Workbench.composer.windowSceneID) {
            WorkbenchWindowRoot(workbench: .composer, model: model)
        }
        Window("Code Console", id: Workbench.codeConsole.windowSceneID) {
            WorkbenchWindowRoot(workbench: .codeConsole, model: model)
        }
    }
}
"""
        },
    )

    issues = check_macos_gui_presentation.run_checks(tmp_path)

    assert any("AppCommands must be attached exactly once" in issue for issue in issues)
