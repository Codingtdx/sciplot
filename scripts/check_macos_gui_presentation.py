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
            ".windowStyle(.plain)",
            ".defaultLaunchBehavior(.presented)",
            ".restorationBehavior(.disabled)",
            "@State private var model = SciPlotGodAppState.model",
            "final class AppWindowManager",
            "AppAppearanceMode",
            "preferredColorScheme",
            "openLauncherAfterSceneAttempt",
            "applicationShouldHandleReopen",
            "hasVisibleWindow(id:",
            "BorderlessLauncherWindow",
            "window.styleMask = [.borderless]",
            "window.isOpaque = false",
            "window.backgroundColor = .clear",
        ),
        forbidden=(
            "TestHostView",
            "XCTestConfigurationFilePath",
            "@State private var model: AppModel?",
            "if let model",
            "Settings {",
            ".defaultSize(width: 700",
            "applicationDidBecomeActive",
            "openLauncherIfNoVisibleWindows",
            "SciPlotGod debug:",
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
            "DataStudioWorkbenchView(",
            "ComposerWorkbenchView(",
            "CodeConsoleWorkbenchView(",
        ),
        forbidden=(
            "NavigationSplitView(",
            "WorkbenchSidebarRail",
            "WorkbenchContentShell",
            "WorkbenchTwoPaneWindow",
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
            "func newProject()",
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
            ".proGlassPanel(theme: theme, cornerRadius: ProCornerPolicy.launcher)",
            "LauncherWelcomeSurface",
            "LauncherModuleEntryRow",
            "LauncherCloseButton",
            "@Environment(\\.openWindow)",
            "@Environment(\\.proWorkspaceTheme)",
            "model.beginLauncherPrimaryAction(for:",
            "Workbench.allCases",
            ".frame(width: 760, height: 460)",
            "WindowDragGesture",
            "dismiss()",
        ),
        forbidden=(
            "confirmationDialog(",
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
            ".frame(maxWidth: .infinity, maxHeight: .infinity)",
            ".padding(28)",
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
            'Menu("Appearance")',
            "ForEach(AppAppearanceMode.allCases)",
            "appearanceModeRawValue = mode.rawValue",
            'Button("New Project")',
            "model.newProject()",
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
            "PlotAdjustmentRailMetrics",
            "PlotTypeChooserSheet",
            "PlotTypeCard",
            "@Environment(\\.proWorkspaceTheme)",
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
            ".preferredColorScheme(.dark)",
        ),
    ),
    SourceCheck(
        label="Shared UI no longer defines the old global workbench header shell",
        path="app/macos/Sources/Shared/UI/StateViews.swift",
        required=(
            "static let minWidth: CGFloat = 320",
            "static let idealWidth: CGFloat = 360",
            "static let maxWidth: CGFloat = 420",
            "enum ProWorkspaceTheme",
            "struct ProWorkspaceThemeKey",
            "var proWorkspaceTheme",
            "rootBackground",
            "stageBackground",
            "panelFill",
            "rowFill",
            "selectedRowFill",
            "var isCodexLikeLightWorkspace",
            "enum ProCornerPolicy",
            "func proGlassPanel",
            "func proGlassRail",
            "func proGlassRow",
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
            "Color(red: 0.78, green: 0.81, blue: 0.84)",
            "Color(red: 0.88, green: 0.90, blue: 0.92)",
        ),
    ),
    SourceCheck(
        label="macOS app icon asset catalog is configured",
        path="app/macos/SciPlotGod.xcodeproj/project.pbxproj",
        required=(
            "Assets.xcassets",
            "Assets.xcassets in Resources",
            "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon",
        ),
    ),
    SourceCheck(
        label="App icon set includes the required macOS sizes",
        path="app/macos/Assets.xcassets/AppIcon.appiconset/Contents.json",
        required=(
            '"idiom": "mac"',
            '"size": "16x16"',
            '"size": "32x32"',
            '"size": "128x128"',
            '"size": "256x256"',
            '"size": "512x512"',
            '"scale": "1x"',
            '"scale": "2x"',
        ),
    ),
    SourceCheck(
        label="macOS frontend design handoff documents Pro workspace and Liquid Glass",
        path="docs/macos-frontend-design.md",
        required=(
            "# macOS Frontend Design Handoff",
            "Liquid Glass",
            "Pro workspace",
            "Launcher",
            "Plot",
            "Data Studio",
            "Composer",
            "Code Console",
            "App Icon",
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
        label="Plot inspector routes explicit adjustment categories",
        path="app/macos/Sources/Features/Plot/PlotInspectorView.swift",
        required=(
            "adjustmentCategory: PlotAdjustmentCategory?",
            "adjustmentCategoryContent",
            "PlotSelectionInspectorView",
            "session.canvasSelection",
            "PlotSelectedLayerEditorView(",
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
        label="Plot adjustment sections stay grouped by drawing workflow",
        path="app/macos/Sources/Features/Plot/PlotInspectorAdjustmentContent.swift",
        required=(
            "figureAdjustmentContent",
            "axesAdjustmentContent",
            "legendAdjustmentContent",
            "guidesAdjustmentContent",
            "fitAdjustmentContent",
            "functionsAdjustmentContent",
            "annotationsAdjustmentContent",
            "advancedAxesAdjustmentContent",
            'InspectorSection(title: "Guides")',
            'InspectorSection(title: "Functions")',
            'InspectorSection(title: "Annotations")',
            'InspectorSection(title: "Advanced Axes")',
        ),
        forbidden=(
            "PlotFloatingToolPalette(",
            ".popover(",
            'Button("Export")',
        ),
    ),
    SourceCheck(
        label="Plot figure axis legend controls stay in focused files",
        path="app/macos/Sources/Features/Plot/PlotInspectorFigureAxisSections.swift",
        required=(
            "plotOptionsSection",
            "axesSection",
            "seriesSection",
            'InspectorSection(title: "Axis")',
            'InspectorSection(title: "Fit Overlay")',
            "SortableSeriesListView(",
            'Button("Reset Series Order")',
        ),
        forbidden=(
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
            "PlotStageDiagnosticBanner",
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
        label="Data Studio uses Plot-style preparation workspace",
        path="app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift",
        required=(
            "DataStudioPreparationInspectorView(session: session)",
            "DataStudioGroupRailView(session: session)",
            "DataStudioPreviewWorkspaceView(session: session)",
            "DataStudioAnalysisSheet(session: session)",
            "isInspectorPresented",
            "@Environment(\\.proWorkspaceTheme)",
        ),
        forbidden=(
            'EmptyStateCard(title: "No groups")',
            'SubtleStageHint(title: "Import workbook groups"',
            'SubtleStageHint(title: "Import groups to choose figures"',
            'title: "Import source files to build workbook groups"',
            "Import raw data to build workbook groups.",
            "DataStudioFigureChoiceSection",
            "HSplitView",
            "WorkbenchTwoPaneWindow",
            ".preferredColorScheme(.dark)",
        ),
    ),
    SourceCheck(
        label="Data Studio left rail owns group and figure selection",
        path="app/macos/Sources/Features/DataStudio/DataStudioGroupRailView.swift",
        required=(
            'WorkbenchRailTitle(title: "Workbook Groups"',
            "DataStudioFigureRailSection",
            "DataStudioFigureRailRow",
            "figureFamilyBinding",
            "proGlassPanel(theme: theme)",
        ),
        forbidden=(
            'SubtleStageHint(title: "Import workbook groups"',
            "WorkbenchTwoPaneWindow",
            'Label("Import"',
        ),
    ),
    SourceCheck(
        label="Data Studio preview workspace reuses Plot preview without onboarding cards",
        path="app/macos/Sources/Features/DataStudio/DataStudioPreviewWorkspaceView.swift",
        required=(
            "PlotRefineView(session: session.plotSession)",
            "DataStudioFocusedWorkbookStrip",
            "DataStudioInlinePreviewBanner",
        ),
        forbidden=(
            'SubtleStageHint(title: "Import groups to choose figures"',
            'title: "Import source files to build workbook groups"',
            "Import raw data to build workbook groups.",
        ),
    ),
    SourceCheck(
        label="Data Studio inspector is preparation and handoff focused",
        path="app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift",
        required=(
            "DataStudioPreparationInspectorView",
            'InspectorSection(title: "Actions")',
            'InspectorSection(title: "Figure")',
            'Button("Open in Plot")',
            'Button("Analysis")',
        ),
        forbidden=(
            "PlotInspectorView(",
            'Section("Figure")',
            'Section("Actions")',
            'InspectorEmptyState(message: "No figure controls")',
            'Button("Export Bundle")',
            "figureTemplateBinding",
            'AdaptiveInspectorControlRow(title: "Template")',
            'AdaptiveInspectorControlRow(title: "Fit")',
        ),
    ),
    SourceCheck(
        label="Composer root uses the shared Pro workspace shell",
        path="app/macos/Sources/Features/Composer/ComposerWorkbenchView.swift",
        required=(
            "ComposerProWorkspace",
            "ComposerAssetBrowserView(session: session)",
            "ComposerCanvasView(session: session)",
            "ComposerInspectorView(session: session)",
            "@Environment(\\.proWorkspaceTheme)",
            ".proGlassPanel(theme: theme)",
        ),
        forbidden=(
            "HSplitView",
            "WorkbenchTwoPaneWindow",
            'SubtleStageHint(title: "Import panels to start a layout"',
            ".preferredColorScheme(.dark)",
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
            'SubtleStageHint(title: "Import panels to start a layout"',
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
            "CodeConsoleProWorkspace",
            "CodeConsoleSourceRailView",
            "CodeConsoleRunWorkspaceView",
            "CodeConsoleContextView(session: session)",
            'Picker("Sheet", selection: selectedSheetSelection)',
            "@Environment(\\.proWorkspaceTheme)",
            ".proGlassPanel(theme: theme)",
            ".padding(.top, 54)",
        ),
        forbidden=(
            "HSplitView",
            "WorkbenchTwoPaneWindow",
            'SubtleStageHint(',
            ".frame(minHeight: 480",
            ".frame(minHeight: 260",
            "EmptyStateCard(",
            'Button("Open Source")',
            'Button("Reveal")',
            ".preferredColorScheme(.dark)",
        ),
    ),
    SourceCheck(
        label="Code Console editor cards fit inside the Pro workspace stage",
        path="app/macos/Sources/Features/CodeConsole/CodeConsoleEditorView.swift",
        required=(
            "private func promptHeader",
            ".layoutPriority(1)",
        ),
        forbidden=(
            ".frame(minHeight: 150, maxHeight: 220)",
            ".frame(minHeight: 320)",
        ),
    ),
    SourceCheck(
        label="Code Console outputs avoid hero cards",
        path="app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift",
        forbidden=(
            'EmptyStateCard(title: "No run output")',
            'EmptyStateCard(title: "No preview selected")',
            'title: "Run code to inspect outputs"',
            'SubtleStageHint(title: "Select an output to preview"',
            "EmptyStateCard(",
        ),
    ),
    SourceCheck(
        label="UI/UX audit report documents the post-implementation review",
        path="docs/ui-ux-audit-2026-04-29.md",
        required=(
            "# SciPlot God UI/UX Audit",
            "Pixelmator Pro",
            "DataGraph",
            "Origin",
            "Prism",
            "Figma",
            "Keynote",
            "VS Code",
            "Jupyter",
            "Reasonable",
            "Needs attention",
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
    "app/macos/Sources/Features/Plot/PlotInspectorAdjustmentContent.swift",
    "app/macos/Sources/Features/Plot/PlotInspectorFigureAxisSections.swift",
    "app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift",
    "app/macos/Sources/Features/Composer/ComposerInspectorView.swift",
    "app/macos/Sources/Features/CodeConsole/CodeConsoleContextView.swift",
)

WORKBENCH_ROOTS = (
    "app/macos/Sources/Features/Plot/PlotWorkbenchView.swift",
    "app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift",
    "app/macos/Sources/Features/DataStudio/DataStudioGroupRailView.swift",
    "app/macos/Sources/Features/DataStudio/DataStudioPreviewWorkspaceView.swift",
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
        shaped_glass_source = _read_source(root, "app/macos/Sources/Shared/UI/StateViews.swift")
        for helper in ("proGlassPanel", "proGlassRail", "proGlassRow"):
            helper_start = shaped_glass_source.index(f"func {helper}")
            helper_end = shaped_glass_source.find("\n    func ", helper_start + 1)
            if helper_end == -1:
                helper_end = shaped_glass_source.find("\n}", helper_start)
            helper_source = shaped_glass_source[helper_start:helper_end]
            for token in (".background(", "in: shape", ".clipShape(shape)", ".glassEffect("):
                if token not in helper_source:
                    issues.append(
                        "app/macos/Sources/Shared/UI/StateViews.swift: "
                        f"{helper} must use shaped background, clipping, and glassEffect; missing {token!r}"
                    )

        light_theme_start = shaped_glass_source.index("case .light:")
        light_theme_end = shaped_glass_source.index("case .dark:", light_theme_start)
        light_theme_source = shaped_glass_source[light_theme_start:light_theme_end]
        if "isCodexLikeLightWorkspace" not in shaped_glass_source:
            issues.append(
                "app/macos/Sources/Shared/UI/StateViews.swift: "
                "light theme must expose a testable Codex-like workspace marker"
            )
        if "0.78" in light_theme_source or "0.80" in light_theme_source:
            issues.append(
                "app/macos/Sources/Shared/UI/StateViews.swift: "
                "light workspace tokens must avoid cold gray 0.78/0.80 stage values"
            )
    except (AssertionError, ValueError) as error:
        issues.append(f"app/macos/Sources/Shared/UI/StateViews.swift: shaped glass/theme check failed: {error}")

    for relative_path in WORKBENCH_ROOTS + ("app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift",):
        try:
            source = _read_source(root, relative_path)
        except AssertionError as error:
            issues.append(str(error))
            continue
        for forbidden in (".background(theme.panelFill)", ".background(theme.rowFill)"):
            if forbidden in source:
                issues.append(
                    f"{relative_path}: glass surfaces must use shaped proGlass helpers, found {forbidden!r}"
                )

    try:
        icon_contents = _read_source(root, "app/macos/Assets.xcassets/AppIcon.appiconset/Contents.json")
        for filename in (
            "AppIcon-16.png",
            "AppIcon-32.png",
            "AppIcon-128.png",
            "AppIcon-256.png",
            "AppIcon-512.png",
            "AppIcon-1024.png",
        ):
            if filename not in icon_contents:
                issues.append(
                    "app/macos/Assets.xcassets/AppIcon.appiconset/Contents.json: "
                    f"missing icon image {filename!r}"
                )
            elif not (root / "app/macos/Assets.xcassets/AppIcon.appiconset" / filename).exists():
                issues.append(
                    "app/macos/Assets.xcassets/AppIcon.appiconset: "
                    f"referenced icon image is missing {filename!r}"
                )
        if not (root / "docs/assets/sciplot-god-app-icon.svg").exists():
            issues.append("docs/assets/sciplot-god-app-icon.svg: source icon artwork is missing")
        else:
            icon_source = _read_source(root, "docs/assets/sciplot-god-app-icon.svg")
            for old_shell_token in ('<rect x="224" y="214"', 'width="576" height="610"', "white figure page"):
                if old_shell_token in icon_source:
                    issues.append(
                        "docs/assets/sciplot-god-app-icon.svg: "
                        "app icon must be an abstract native mark, not the old white chart page shell"
                    )
    except AssertionError as error:
        issues.append(str(error))

    try:
        app_scene = _read_source(root, "app/macos/Sources/App/SciPlotGodApp.swift")
        command_attachment_count = app_scene.count("AppCommands(model: model")
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

    try:
        root_split = _read_source(root, "app/macos/Sources/App/RootSplitView.swift")
        if "PlotReplacementConfirmationHost" not in root_split:
            issues.append(
                "app/macos/Sources/App/RootSplitView.swift: "
                "Plot replacement confirmation must be hosted by the Plot window"
            )
        shared_chrome_start = root_split.index("private struct AppWindowSharedChrome")
        shared_chrome_end = root_split.index("struct WorkbenchWindowOpenHandler", shared_chrome_start)
        shared_chrome_source = root_split[shared_chrome_start:shared_chrome_end]
        if "confirmationDialog(" in shared_chrome_source:
            issues.append(
                "app/macos/Sources/App/RootSplitView.swift: "
                "shared window chrome must not present Plot replacement confirmation over Launcher"
            )
    except (AssertionError, ValueError) as error:
        issues.append(f"app/macos/Sources/App/RootSplitView.swift: Plot replacement host check failed: {error}")

    try:
        plot_inspector = _read_source(root, "app/macos/Sources/Features/Plot/PlotInspectorFigureAxisSections.swift")
        series_start = plot_inspector.index("var seriesSection")
        next_section = plot_inspector.find("\n    @ViewBuilder", series_start)
        if next_section == -1:
            next_section = plot_inspector.find("\n    var", series_start + 1)
        series_source = plot_inspector[series_start:next_section]
        if 'DisclosureGroup("Advanced")' in series_source:
            issues.append(
                "app/macos/Sources/Features/Plot/PlotInspectorFigureAxisSections.swift: "
                "Legend order is the primary Legend function and must not be hidden in Advanced"
            )
        for required in ("SortableSeriesListView(", 'Button("Reset Series Order")'):
            if required not in series_source:
                issues.append(
                    "app/macos/Sources/Features/Plot/PlotInspectorFigureAxisSections.swift: "
                    f"Legend section must expose {required!r} directly"
                )
        axes_start = plot_inspector.index("var axesSection")
        axes_end = plot_inspector.index("var fitOverlaySection", axes_start)
        axes_source = plot_inspector[axes_start:axes_end]
        if 'DisclosureGroup("Advanced")' in axes_source:
            issues.append(
                "app/macos/Sources/Features/Plot/PlotInspectorFigureAxisSections.swift: "
                "Axis range and tick controls are primary Axes controls and must not be hidden in Advanced"
            )
        for required in ("axisScaleControls", "axisRangeControls"):
            if required not in axes_source:
                issues.append(
                    "app/macos/Sources/Features/Plot/PlotInspectorFigureAxisSections.swift: "
                    f"Axes section must expose {required!r} directly"
                )
    except (AssertionError, ValueError) as error:
        issues.append(
            "app/macos/Sources/Features/Plot/PlotInspectorFigureAxisSections.swift: "
            f"Legend/Axes section check failed: {error}"
        )

    try:
        plot_refine = _read_source(root, "app/macos/Sources/Features/Plot/PlotRefineView.swift")
        for marker in ("struct PlotStageDiagnosticBanner", "private struct PlotEmptyPreviewPage"):
            marker_start = plot_refine.index(marker)
            next_struct = plot_refine.find("\nstruct ", marker_start + 1)
            next_private_struct = plot_refine.find("\nprivate struct ", marker_start + 1)
            candidates = [idx for idx in (next_struct, next_private_struct) if idx != -1]
            marker_end = min(candidates) if candidates else len(plot_refine)
            marker_source = plot_refine[marker_start:marker_end]
            if ".shadow(" in marker_source:
                issues.append(
                    "app/macos/Sources/Features/Plot/PlotRefineView.swift: "
                    f"{marker} must not add decorative shadow behind the preview stage"
                )
    except (AssertionError, ValueError) as error:
        issues.append(f"app/macos/Sources/Features/Plot/PlotRefineView.swift: preview shadow check failed: {error}")

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
