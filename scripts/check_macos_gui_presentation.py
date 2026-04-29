from __future__ import annotations

import argparse
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class SourceCheck:
    label: str
    path: str
    required: tuple[str, ...] = ()
    forbidden: tuple[str, ...] = ()


PRESENTATION_CHECKS: tuple[SourceCheck, ...] = (
    SourceCheck(
        label="app scene exposes launcher plus singleton workbench windows",
        path="app/macos/Sources/App/SciPlotGodApp.swift",
        required=(
            'WindowGroup("SciPlot God", id: "launcher")',
            'Window("Plot", id: Workbench.plot.windowSceneID)',
            'Window("Data Studio", id: Workbench.dataStudio.windowSceneID)',
            'Window("Composer", id: Workbench.composer.windowSceneID)',
            'Window("Code Console", id: Workbench.codeConsole.windowSceneID)',
            ".defaultSize(width:",
            ".windowResizability(.contentMinSize)",
            ".defaultLaunchBehavior(.presented)",
            ".restorationBehavior(.disabled)",
            "@State private var model = SciPlotGodAppState.model",
            "final class AppWindowManager",
            "openLauncherAfterSceneAttempt",
        ),
        forbidden=(
            "TestHostView",
            "XCTestConfigurationFilePath",
            "@State private var model: AppModel?",
            "if let model",
            "Settings {",
        ),
    ),
    SourceCheck(
        label="workbench windows do not use the old global split shell",
        path="app/macos/Sources/App/RootSplitView.swift",
        required=(
            "struct LauncherWindowRoot",
            "struct WorkbenchWindowRoot",
            "WorkbenchWindowOpenHandler",
            "bootstrapOnAppear: false",
            ".focusedSceneValue(\\.workbenchCommandContext, workbench)",
            "WorkbenchWindowToolbarContent(",
            "WindowToolbarConfigurator",
        ),
        forbidden=(
            "NavigationSplitView(",
            "WorkbenchSidebarRail",
            "WorkbenchContentShell",
            "InspectorChromeRoot",
            'Text("SciPlot God")',
            "WorkbenchSegmentedPicker",
            'Picker("Workbench"',
            "ActiveWorkbenchToolbarContent",
            "plotSheetBinding",
            "showDataWorkbook()",
            "PlotExportInspectorSection(session:",
            "InspectorEdgeRevealButton",
            "chevron.forward.2",
            "chevron.backward.2",
            'Image(systemName: "chevron',
            ".toolbar(removing: .sidebarToggle)",
            'ToolbarItem(id: "workbenchSidebarToggle"',
        ),
    ),
    SourceCheck(
        label="AppModel owns launcher navigation and real module actions",
        path="app/macos/Sources/App/AppModel.swift",
        required=(
            "var requestedWorkbenchWindow: Workbench?",
            "func enterWorkbench(_ workbench: Workbench)",
            "func showLauncher()",
            "func beginLauncherPrimaryAction(for workbench: Workbench)",
            "func beginImport(for workbench: Workbench)",
            "func export(for workbench: Workbench) async",
            "func saveProject(for workbench: Workbench) async",
            "func showHelp(for workbench: Workbench)",
            "func requestOpenWindow(for workbench: Workbench)",
        ),
        forbidden=(
            "selectedWorkbench: Workbench?",
            "case start",
            "case home",
        ),
    ),
    SourceCheck(
        label="Launcher uses native glass and real workbench modules",
        path="app/macos/Sources/App/LauncherView.swift",
        required=(
            "struct LauncherView",
            "GlassEffectContainer",
            ".glassEffect(",
            "LauncherWelcomeSurface",
            "LauncherModuleEntryRow",
            "@Environment(\\.openWindow)",
            "model.beginLauncherPrimaryAction(for:",
            "Workbench.allCases",
        ),
        forbidden=(
            "LauncherBackdrop",
            "LauncherModulePreview",
            "PlotLauncherSketch",
            "DataStudioLauncherSketch",
            "ComposerLauncherSketch",
            "CodeConsoleLauncherSketch",
            "LauncherActionPanel",
            "LauncherModuleSelectionView",
            "Color(nsColor: .underPageBackgroundColor)",
            ".overlay(.black.opacity",
            ".frame(maxWidth: 980",
            "Color.accentColor.opacity(0.18)",
            "Magic Wand",
            "Brush",
            "Paint",
            "Eraser",
            "Crop",
        ),
    ),
    SourceCheck(
        label="Plot tools use native commands without stealing text input",
        path="app/macos/Sources/App/AppCommands.swift",
        required=(
            'CommandMenu("Plot Tools")',
            "model.plotSession.activatePlotTool(tool)",
            ".keyboardShortcut(shortcutKey, modifiers: [.command, .option])",
        ),
        forbidden=(),
    ),
    SourceCheck(
        label="Plot workbench uses source/type plus adjustment-category layout",
        path="app/macos/Sources/Features/Plot/PlotWorkbenchView.swift",
        required=(
            "PlotPixelmatorWorkspace",
            "PlotSourceTypePanel",
            "PlotAdjustmentInspector",
            "PlotAdjustmentRail",
            "PlotTypeChooserSheet",
            "PlotTypeCard",
            "session.templateGalleryItems",
            "session.plotTypeItems",
            "isPlotTypeChooserPresented",
            ".sheet(isPresented: $isPlotTypeChooserPresented)",
            'Label("More", systemImage: "square.grid.2x2")',
            "PlotRefineView(session: session)",
        ),
        forbidden=(
            "PlotLayerPanel",
            "PlotVerticalToolRail",
            "PlotFloatingToolPalette",
            "PlotTemplateChooserList",
            "templatePopoverPresented",
            "PlotLibraryPanel",
            "PlotSourceSummary",
            "PlotObjectLibraryView",
            "PlotDataUtilityButton",
            'WorkbenchRailTitle(title: "Source"',
            'WorkbenchRailTitle(title: "Objects"',
            'WorkbenchRailTitle(title: "Templates"',
            'Label("No source"',
            "PlotTemplateView(session:",
            "frame(minWidth: 1160",
            "PlotSourceRailEdgeButton",
            "sourceRailPresented",
            "PlotSourceLibraryView(",
            "PlotSourceRailDensity",
            "PlotTypeSearchField",
            "PlotDataWorkbookEntry",
            "workbookAvailability(for:",
            "session.selectedSourceFilename",
            "session.isImporterPresented = true",
            '"Import or open data"',
            '"CSV, Excel, or project"',
            '"Data Tables"',
            '"Source Data"',
            '"Transformed"',
            '"Variables"',
            "case .fit:",
        ),
    ),
    SourceCheck(
        label="Shared UI no longer defines the old global workbench header shell",
        path="app/macos/Sources/Shared/UI/StateViews.swift",
        required=(
            "static let minWidth: CGFloat = 320",
            "static let idealWidth: CGFloat = 360",
            "static let maxWidth: CGFloat = 420",
        ),
        forbidden=(
            "enum WorkbenchHeaderMetrics",
            "struct WorkbenchContentShell",
            "struct InspectorHeaderTabs",
            "struct InspectorChromeRoot",
            "content\n                .frame(\n                    minWidth: InspectorColumnLayoutPolicy.minWidth",
            ".frame(\n            minWidth: InspectorColumnLayoutPolicy.minWidth",
            "Button(action: hideAction)",
            'help("Hide Inspector")',
        ),
    ),
    SourceCheck(
        label="Plot template browser remains a contract-fed template view",
        path="app/macos/Sources/Features/Plot/PlotTemplateView.swift",
        required=(
            "enum PlotTemplateRailDensity",
            "struct PlotTemplateLibraryView",
            "PlotCompactTemplateLibraryView",
            'WorkbenchRailTitle(title: "Templates"',
            "PlotTemplateBrowserPopover",
        ),
        forbidden=(
            "enum PlotSourceRailDensity",
            "struct PlotSourceLibraryView",
            "PlotCompactSourceLibraryView",
            'RailSectionHeader(title: "Source")',
            'RailSectionHeader(title: "Objects")',
            'RailSectionHeader(title: "Data")',
            "Picker(\"Sheet\"",
            "session.showDataWorkbook()",
            "session.selectDataWorkbookTab(tab)",
            "PlotObjectListItem",
            "PlotDataPreparationRow",
            'title: "Import from toolbar"',
            'title: "Import data"',
            'Label("Import",',
            'Label("Import Data"',
            '"textformat"',
            "session.isImporterPresented = true",
            'title: "No Source"',
            'title: "Objects appear after import"',
            'title: "Templates appear after import"',
        ),
    ),
    SourceCheck(
        label="Plot rail uses compact native rows",
        path="app/macos/Sources/Features/Plot/PlotTemplateView.swift",
        required=("PlotTemplateRow(",),
        forbidden=(
            "PlotTemplateCard(",
            "private struct PlotTemplateCard",
            ".background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10",
        ),
    ),
    SourceCheck(
        label="Plot inspector supports explicit adjustment categories",
        path="app/macos/Sources/Features/Plot/PlotInspectorView.swift",
        required=(
            "adjustmentCategory: PlotAdjustmentCategory?",
            "adjustmentCategoryContent",
            "figureAdjustmentContent",
            "axesAdjustmentContent",
            "legendAdjustmentContent",
            "guidesAdjustmentContent",
            "fitAdjustmentContent",
            "functionsAdjustmentContent",
            "annotationsAdjustmentContent",
            "advancedAxesAdjustmentContent",
            "PlotSelectionInspectorView",
            "session.canvasSelection",
            "PlotSelectedLayerEditorView(",
            'InspectorSection(title: "Axis")',
            'InspectorSection(title: "Fit Overlay")',
        ),
        forbidden=(
            "PlotInspectorModePicker(",
            "PlotDataPipelineInspectorView(",
            "PlotInspectorLayerListView(",
            "Form {",
            "Section(styleSectionTitle)",
            'Section("Actions")',
            'Section("Axis")',
            'Section("Advanced Plot")',
            'InspectorSection(title: "Advanced Plot")',
            'InspectorEmptyState(message: "No figure controls")',
            "PlotExportInspectorSection",
            'Button("Export")',
            ".formStyle(",
        ),
    ),
    SourceCheck(
        label="Plot data inspector uses pipeline list and selected editor",
        path="app/macos/Sources/Features/Plot/PlotDataPipelineInspectorView.swift",
        required=(
            "PlotDataPipelineSelection",
            "pipelineList",
            "selectedEditor",
            "pipelineRow(",
        ),
        forbidden=(
            'DisclosureGroup("Data")',
            "ForEach(session.dataTransforms) { transform in\n                VStack",
            "ForEach(session.dataVariables) { variable in\n                VStack",
        ),
    ),
    SourceCheck(
        label="Plot layer inspector uses selected object grammar",
        path="app/macos/Sources/Features/Plot/PlotInspectorLayerListView.swift",
        required=(
            "PlotLayerSelection",
            "layerRow(",
            "session.selectedReferenceGuideID = id",
            "session.selectedTextAnnotationID = id",
            "session.selectedShapeAnnotationID = id",
        ),
        forbidden=(
            'DisclosureGroup("Text Annotations")',
            'DisclosureGroup("Reference Guides")',
            'DisclosureGroup("Shape Annotations")',
            '"textformat"',
        ),
    ),
    SourceCheck(
        label="Plot selected layer editor keeps one active editor",
        path="app/macos/Sources/Features/Plot/PlotSelectedLayerEditorView.swift",
        required=(
            "PlotSelectedLayerEditorView",
            "selection: PlotLayerSelection?",
            "exactGuideValueEditor",
            "exactGuideRangeEditor",
        ),
        forbidden=(
            "ForEach(session.textAnnotations)",
            "ForEach(session.referenceGuides)",
            "ForEach(session.shapeAnnotations)",
            "ForEach(session.analyticalLayers)",
            "PlotArrangeInspectorView",
            "nudgeReferenceGuide(",
        ),
    ),
    SourceCheck(
        label="Plot preview owns the live preview stage and tool dock",
        path="app/macos/Sources/Features/Plot/PlotRefineView.swift",
        required=(
            "PlotPreviewStage",
            "Base64PreviewImageView(base64PNG:",
            "Base64PDFPreviewView(base64PDF:",
        ),
        forbidden=(
            "PlotToolDock",
            "PlotFloatingToolPalette(",
            'EmptyStateCard(title: "No Preview")',
            "PlotToolOptionsBar(",
            "PlotCanvasOverlayControlsView",
            "selectedMovableLayer",
            'title: "Preview"',
            "Option + Arrow",
            ".keyboardShortcut(shortcut, modifiers: [.option])",
        ),
    ),
    SourceCheck(
        label="Workbench toolbar action group is scoped per module window",
        path="app/macos/Sources/App/RootSplitView.swift",
        required=(
            "private struct WorkbenchWindowToolbarContent",
            "model.beginImport(for: workbench)",
            "model.export(for: workbench)",
            "model.showPlotDataWorkbook()",
            "if workbench == .plot",
            "model.showHelp(for: workbench)",
            "model.toggleInspector(for: workbench)",
        ),
        forbidden=(
            ">>",
            "<<",
            "chevron.forward.2",
            "chevron.backward.2",
        ),
    ),
    SourceCheck(
        label="Plot canvas overlay controls avoid localized text symbol labels",
        path="app/macos/Sources/Features/Plot/PlotRefineView.swift",
        forbidden=(
            'return "textformat"',
            '"textformat"',
        ),
    ),
    SourceCheck(
        label="Plot adjustment categories replace the old popover tool palette",
        path="app/macos/Sources/Features/Plot/PlotInspectorMode.swift",
        required=(
            "enum PlotAdjustmentCategory",
            "struct PlotAdjustmentRailItem",
            "static let railCategories",
            "plotAdjustmentAvailability",
            "selectPlotAdjustmentCategory",
            "enum PlotTool",
            "enum PlotCanvasSelection",
            "PlotLayerSelection",
            "shortcutKey",
            "plotToolAvailability",
            "activatePlotTool",
        ),
        forbidden=(
            "struct PlotFloatingToolPalette",
            "PlotToolPopoverContent",
            "PlotGuideToolCreateForm",
            "floatingPaletteTools",
            "floatingPaletteToolGroups",
            "opensToolPopover",
            ".popover(",
            "struct PlotInspectorModePicker",
            "struct PlotToolStripView",
            "PlotToolOptionsBar",
            ".background(.thinMaterial, in: Capsule())",
            ".keyboardShortcut(shortcutKey, modifiers: [])",
            'return "textformat"',
        ),
    ),
    SourceCheck(
        label="Plot data workbook sheet stays in a dedicated file",
        path="app/macos/Sources/Features/Plot/PlotWorkbenchView.swift",
        forbidden=("struct PlotDataWorkbookSheet",),
    ),
    SourceCheck(
        label="Plot data workbook exposes pipeline summary",
        path="app/macos/Sources/Features/Plot/PlotDataWorkbookSheet.swift",
        required=("struct PlotDataWorkbookSheet", "dataPipelineSummary"),
    ),
    SourceCheck(
        label="Data Studio rail avoids duplicate group empty state",
        path="app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift",
        required=(
            'WorkbenchRailTitle(title: "Workbook Groups"',
            "DataStudioFigureRailSection",
            "DataStudioFigureRailRow",
            "figureFamilyBinding",
        ),
        forbidden=(
            'EmptyStateCard(title: "No groups")',
            "DataStudioFigureChoiceSection",
        ),
    ),
    SourceCheck(
        label="Data Studio inspector uses shared plain sections",
        path="app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift",
        required=('InspectorSection(title: "Actions")', 'InspectorSection(title: "Figure")'),
        forbidden=(
            'Section("Figure")',
            'Section("Actions")',
            'InspectorEmptyState(message: "No figure controls")',
            'Button("Export Bundle")',
            "figureTemplateBinding",
            'AdaptiveInspectorControlRow(title: "Template")',
        ),
    ),
    SourceCheck(
        label="Composer asset rail is a real filtered panel library",
        path="app/macos/Sources/Features/Composer/ComposerAssetBrowserView.swift",
        required=(
            "ComposerLibraryFilter",
            'Picker("Library Filter"',
            "filteredPanels",
            "ComposerLibraryRow",
        ),
        forbidden=(
            'EmptyStateCard(title: "No imported panels")',
            'Button("Import")',
            'Button("Export")',
        ),
    ),
    SourceCheck(
        label="Composer canvas has one primary board boundary",
        path="app/macos/Sources/Features/Composer/ComposerCanvasView.swift",
        forbidden=(
            "RoundedRectangle(cornerRadius: 28)",
            "RoundedRectangle(cornerRadius: 24)",
        ),
    ),
    SourceCheck(
        label="Composer inspector preview avoids nested shell",
        path="app/macos/Sources/Features/Composer/ComposerInspectorView.swift",
        required=(
            "ComposerInspectorPreviewContent",
            'InspectorSection(title: "Selection")',
            'InspectorSection(title: "Placement")',
            'InspectorSection(title: "Panel")',
            'InspectorSection(title: "Actions")',
            'InspectorSection(title: "Preview")',
        ),
        forbidden=('Section("Preview")', 'Button("Export")'),
    ),
    SourceCheck(
        label="Code Console root avoids hero card empty state",
        path="app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift",
        required=(
            "CodeConsoleSourceRailView",
            "CodeConsoleRunWorkspaceView",
            'Picker("Sheet", selection: selectedSheetSelection)',
        ),
        forbidden=(
            "EmptyStateCard(",
            'Button("Open Source")',
            'Button("Reveal")',
        ),
    ),
    SourceCheck(
        label="Code Console outputs avoid hero cards",
        path="app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift",
        forbidden=(
            'EmptyStateCard(title: "No run output")',
            'EmptyStateCard(title: "No preview selected")',
            "EmptyStateCard(",
        ),
    ),
    SourceCheck(
        label="Code Console inspector uses plain sections",
        path="app/macos/Sources/Features/CodeConsole/CodeConsoleContextView.swift",
        required=(
            "InspectorSection(",
            'InspectorSection(title: "Binding")',
            'InspectorSection(title: "Runner")',
            'InspectorSection(title: "Outputs & Handoff")',
            'InspectorSection(title: "Advanced")',
            "private var advancedSection",
            'Button("Open Source")',
            'Button("Reveal Source")',
        ),
        forbidden=(
            ".formStyle(.grouped)",
            'Button("Export")',
            'InspectorSection(title: "Actions")',
            "private var actionsSection",
        ),
    ),
)

INSPECTOR_FILES = (
    "app/macos/Sources/Features/Plot/PlotInspectorView.swift",
    "app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift",
    "app/macos/Sources/Features/Composer/ComposerInspectorView.swift",
    "app/macos/Sources/Features/CodeConsole/CodeConsoleContextView.swift",
)

WORKBENCH_ROOTS = (
    "app/macos/Sources/Features/Plot/PlotWorkbenchView.swift",
    "app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift",
    "app/macos/Sources/Features/Composer/ComposerWorkbenchView.swift",
    "app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift",
)


def _read_source(root: Path, relative_path: str) -> str:
    path = root / relative_path
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise AssertionError(f"{relative_path}: file is missing") from error


def run_checks(root: Path = REPO_ROOT) -> list[str]:
    issues: list[str] = []

    for check in PRESENTATION_CHECKS:
        try:
            source = _read_source(root, check.path)
        except AssertionError as error:
            issues.append(str(error))
            continue

        for token in check.required:
            if token not in source:
                issues.append(f"{check.path}: {check.label}: missing required token {token!r}")
        for token in check.forbidden:
            if token in source:
                issues.append(f"{check.path}: {check.label}: forbidden token still present {token!r}")

    try:
        app_scene = _read_source(root, "app/macos/Sources/App/SciPlotGodApp.swift")
        command_attachment_count = app_scene.count("AppCommands(model: model)")
        if command_attachment_count != 1:
            issues.append(
                "app/macos/Sources/App/SciPlotGodApp.swift: "
                f"AppCommands must be attached exactly once; found {command_attachment_count}"
            )

        root_split = _read_source(root, "app/macos/Sources/App/RootSplitView.swift")
        toolbar_start = root_split.index("private struct WorkbenchWindowToolbarContent")
        toolbar_end = root_split.index("private struct WindowToolbarConfigurator", toolbar_start)
        toolbar_source = root_split[toolbar_start:toolbar_end]
        if ">>" in toolbar_source or "<<" in toolbar_source:
            issues.append(
                "app/macos/Sources/App/RootSplitView.swift: "
                "toolbar must not use chevron text for panel toggles"
            )
    except (AssertionError, ValueError) as error:
        issues.append(f"app/macos/Sources/App/RootSplitView.swift: toolbar structure check failed: {error}")

    try:
        plot_mode = _read_source(root, "app/macos/Sources/Features/Plot/PlotInspectorMode.swift")
        rail_start = plot_mode.index("static let railCategories")
        rail_end = plot_mode.index("var title:", rail_start)
        rail_source = plot_mode[rail_start:rail_end]
        for category in (
            ".figure",
            ".axes",
            ".legend",
            ".guides",
            ".fit",
            ".functions",
            ".annotations",
            ".advancedAxes",
        ):
            if category not in rail_source:
                issues.append(
                    "app/macos/Sources/Features/Plot/PlotInspectorMode.swift: "
                    f"adjustment rail is missing {category}"
                )
        if ".dataCursor" in rail_source:
            issues.append(
                "app/macos/Sources/Features/Plot/PlotInspectorMode.swift: "
                "Data Cursor must not be in the adjustment rail"
            )

        activate_start = plot_mode.index("func activatePlotTool")
        activate_end = plot_mode.index("func selectCanvasSelection", activate_start)
        activate_source = plot_mode[activate_start:activate_end]
        for forbidden_call in (
            "addReferenceGuide(",
            "addTextAnnotation(",
            "addShapeAnnotation(",
            "addAnalyticalFunctionLayer(",
            "addAxisBreak(",
            "updateExtraYAxis",
        ):
            if forbidden_call in activate_source:
                issues.append(
                    "app/macos/Sources/Features/Plot/PlotInspectorMode.swift: "
                    f"activatePlotTool must stay side-effect-light; found {forbidden_call!r}"
                )
    except (AssertionError, ValueError) as error:
        issues.append(f"app/macos/Sources/Features/Plot/PlotInspectorMode.swift: tool structure check failed: {error}")

    for relative_path in WORKBENCH_ROOTS:
        try:
            source = _read_source(root, relative_path)
        except AssertionError as error:
            issues.append(str(error))
            continue
        if "WorkbenchScaffold(" in source:
            issues.append(f"{relative_path}: workbench root must not use WorkbenchScaffold")

    for relative_path in INSPECTOR_FILES:
        try:
            source = _read_source(root, relative_path)
        except AssertionError as error:
            issues.append(str(error))
            continue
        if "InspectorSection(" not in source:
            issues.append(f"{relative_path}: inspector must consume shared InspectorSection grammar")
        if ".buttonStyle(.borderedProminent)" in source:
            issues.append(f"{relative_path}: inspector primary actions should avoid disabled prominent button ghosts")

    return issues


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check macOS GUI presentation grammar at source level.")
    parser.add_argument(
        "--root",
        type=Path,
        default=REPO_ROOT,
        help="Repository root to inspect. Defaults to the current script's repository.",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    issues = run_checks(args.root)
    if issues:
        print("[macos-gui] presentation grammar failed:")
        for issue in issues:
            print(f"  - {issue}")
        return 1

    print("[macos-gui] presentation grammar passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
