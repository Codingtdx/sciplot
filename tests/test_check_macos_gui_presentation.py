from __future__ import annotations

from pathlib import Path

from scripts import check_macos_gui_presentation


def _write_sources(root: Path, overrides: dict[str, str] | None = None) -> None:
    sources = {
        "app/macos/Sources/App/SciPlotApp.swift": """
import SwiftUI
@main
struct SciPlotApp: App {
    @State private var model = SciPlotAppState.model
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceModeRawValue = AppAppearanceMode.system.rawValue
    var appearanceMode: AppAppearanceMode { .system }
    var body: some Scene {
        WindowGroup("SciPlot", id: "launcher") { LauncherWindowRoot(model: model) }
            .defaultSize(width: 1520, height: 900)
            .windowResizability(.contentMinSize)
            .windowStyle(.plain)
            .preferredColorScheme(appearanceMode.preferredColorScheme)
            .defaultLaunchBehavior(.presented)
            .restorationBehavior(.disabled)
            .commands { AppCommands(model: model, appearanceModeRawValue: appearanceModeRawValueBinding) }
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
private enum SciPlotAppState {
    static let model = AppModel()
}
enum AppAppearanceMode {
    static let storageKey = "appAppearanceMode"
    static let system = AppAppearanceMode()
    var rawValue: String { "system" }
    var preferredColorScheme: ColorScheme? { nil }
}
final class AppWindowManager {
    func openLauncherAfterSceneAttempt() {}
    func applicationShouldHandleReopen() {}
    func hasVisibleWindow(id: String) -> Bool { false }
    func configureLauncherWindow(_ window: NSWindow) {
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
    }
}
final class BorderlessLauncherWindow {}
""",
        "app/macos/Sources/App/RootSplitView.swift": """
struct LauncherWindowRoot {
    var body: some View {
        AppWindowSharedChrome(model: model, bootstrapOnAppear: false) {
            LauncherView(model: model)
        }
            .toolbar(removing: .title)
            .toolbarVisibility(.hidden, for: .windowToolbar)
            .containerBackground(.clear, for: .window)
            .background(WindowToolbarConfigurator())
            .background(LauncherSceneWindowRetirer())
            .modifier(WorkbenchWindowOpenHandler(model: model))
    }
}
private struct LauncherSceneWindowRetirer {}
struct WorkbenchWindowRoot {
    let workbench: Workbench
    var body: some View {
        PlotWorkbenchView(session: model.plotSession)
            .modifier(PlotReplacementConfirmationHost(model: model))
        DataStudioWorkbenchView(session: model.dataStudioSession)
        ComposerWorkbenchView(session: model.composerSession)
        CodeConsoleWorkbenchView(session: model.codeConsoleSession)
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
private struct AppWindowSharedChrome {}
private struct PlotReplacementConfirmationHost {}
struct WorkbenchWindowOpenHandler {}
private struct WindowToolbarConfigurator {}
""",
        "app/macos/Sources/App/AppModel.swift": """
final class AppModel {
    var requestedWorkbenchWindow: Workbench?
    func enterWorkbench(_ workbench: Workbench) {}
    func showLauncher() {}
    func newProject() {}
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
    @Environment(\\.proWorkspaceTheme) private var theme
    var body: some View {
        GlassEffectContainer {
            Workbench.allCases
            LauncherWelcomeSurface()
            LauncherModuleEntryRow()
            Button("Plot") { openWindow(id: Workbench.plot.windowSceneID) }
            WindowDragGesture()
            LauncherCloseButton { dismiss() }
        }
        .frame(width: 760, height: 460)
        .proGlassPanel(theme: theme, cornerRadius: ProCornerPolicy.launcher, showsBorder: false)
    }
}
struct LauncherCloseButton {}
""",
        "app/macos/Sources/App/AppCommands.swift": """
struct AppCommands {
    @Binding var appearanceModeRawValue: String
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Menu("Appearance") {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Button(mode.title) { appearanceModeRawValue = mode.rawValue }
                }
            }
        }
        CommandGroup(after: .newItem) {
            Button("New Project") { model.newProject() }
        }
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
    PlotSelectionInspectorView()
    session.canvasSelection
    PlotSelectedLayerEditorView()
    InspectorSection(title: "Selection") {}
}
""",
        "app/macos/Sources/Features/Plot/PlotInspectorAdjustmentContent.swift": """
figureAdjustmentContent
axesAdjustmentContent
legendAdjustmentContent
guidesAdjustmentContent
fitAdjustmentContent
FitModelInspectorSection(session: session)
functionsAdjustmentContent
annotationsAdjustmentContent
advancedAxesAdjustmentContent
InspectorSection(title: "Guides")
InspectorSection(title: "Functions")
InspectorSection(title: "Annotations")
InspectorSection(title: "Advanced Axes")
PlotCanvasInteractionModeCard()
beginCanvasPlacement(.text)
""",
        "app/macos/Sources/Features/Plot/PlotInspectorFigureAxisSections.swift": """
plotOptionsSection
axesSection
seriesSection
InspectorSection(title: "Axis") {}
var seriesSection: some View {
    InspectorSection(title: "Legend") {
        SortableSeriesListView()
        Button("Reset Series Order") {}
    }
}
var axesSection: some View {
    InspectorSection(title: "Axis") {
        axisScaleControls
        axisRangeControls
    }
}
var fitOverlaySection: some View {}
""",
        "app/macos/Sources/Shared/UI/FitModelGrid.swift": """
struct FitModelOption {
    let id: String
    static let all = [
        FitModelOption(id: "linear"),
        FitModelOption(id: "polynomial_2"),
        FitModelOption(id: "polynomial_3"),
        FitModelOption(id: "exponential"),
        FitModelOption(id: "logarithmic"),
        FitModelOption(id: "power_law"),
        FitModelOption(id: "gaussian"),
        FitModelOption(id: "logistic"),
        FitModelOption(id: "custom_function"),
    ]
}
struct FitModelGrid {}
struct FitModelCard {}
struct FitModelGlyph {
    var body: some View { Canvas { _, _ in } }
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
PlotInteractivePreviewSurface(session: session, preview: preview)
ProgressView()
previewSurface
struct PlotStageDiagnosticBanner {
    let shape = RoundedRectangle(cornerRadius: 14)
}
private struct PlotEmptyPreviewPage {
    let shape = RoundedRectangle(cornerRadius: 8)
}
""",
        "app/macos/Sources/Features/Plot/PlotInteractivePreviewOverlay.swift": """
PlotInteractivePreviewSurface(session: session, preview: preview)
InteractivePlotOverlay(session: session, mapper: mapper)
PlotPreviewCoordinateMapper(metadata: metadata, viewportSize: size)
Base64PreviewImageView(base64PNG: previewPNG)
Base64PDFPreviewView(base64PDF: preview.pdfBase64)
commitCanvasDraft(.text(point: point, displayStyle: "plain", connectorTarget: nil))
drawTextSelection(at: point, in: &context)
drawTargetTick(at: point, in: &context)
drawRoundedSquareHandles(for: annotation, rect: rect, in: &context)
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
PlotAdjustmentRailMetrics
@State private var isPlotTypeChooserPresented = false
ForEach(session.templateGalleryItems) { item in PlotTypeCard(item: item) }
Button { isPlotTypeChooserPresented = true } label: {
    Label("More", systemImage: "square.grid.2x2")
}
.sheet(isPresented: $isPlotTypeChooserPresented) {
    PlotTypeChooserSheet(session: session, isPresented: $isPlotTypeChooserPresented)
}
ForEach(session.plotTypeItems) { item in item.title }
@Environment(\\.proWorkspaceTheme) private var theme
""",
        "app/macos/Sources/Shared/UI/StateViews.swift": """
enum InspectorColumnLayoutPolicy {
    static let minWidth: CGFloat = 320
    static let idealWidth: CGFloat = 360
    static let maxWidth: CGFloat = 420
}
enum ProWorkspaceTheme {
    var rootBackground: Color { .clear }
    var stageBackground: Color {
        switch self {
        case .light:
            return .clear
        case .dark:
            return .clear
        }
    }
    var panelFill: Color { .clear }
    var rowFill: Color { .clear }
    var selectedRowFill: Color { .clear }
    var isCodexLikeLightWorkspace: Bool { true }
}
enum ProCornerPolicy {
    static let outer: CGFloat = 22
    static let rail: CGFloat = 18
    static let row: CGFloat = 12
    static let smallRow: CGFloat = 10
    static let preview: CGFloat = 14
}
struct ProWorkspaceThemeKey {}
extension EnvironmentValues {
    var proWorkspaceTheme: ProWorkspaceTheme { get { ProWorkspaceTheme() } set {} }
}
extension View {
    func proGlassPanel(theme: ProWorkspaceTheme) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return self
            .background(theme.panelFill, in: shape)
            .clipShape(shape)
            .glassEffect(.regular.interactive(), in: shape)
    }
    func proGlassRail(theme: ProWorkspaceTheme) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return self
            .background(theme.panelFill, in: shape)
            .clipShape(shape)
            .glassEffect(.regular.interactive(), in: shape)
    }
    func proGlassRow(theme: ProWorkspaceTheme) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return self
            .background(theme.rowFill, in: shape)
            .clipShape(shape)
            .glassEffect(.regular.interactive(), in: shape)
    }
}
""",
        "app/macos/SciPlot.xcodeproj/project.pbxproj": """
Assets.xcassets
Assets.xcassets in Resources
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon
Sources/Features/Plot/PlotRefineView.swift
Sources/Features/Plot/PlotInteractivePreviewOverlay.swift
""",
        "app/macos/Assets.xcassets/AppIcon.appiconset/Contents.json": """
{
  "images" : [
    { "filename": "AppIcon-16.png", "idiom": "mac", "scale": "1x", "size": "16x16" },
    { "filename": "AppIcon-32.png", "idiom": "mac", "scale": "2x", "size": "16x16" },
    { "filename": "AppIcon-32.png", "idiom": "mac", "scale": "1x", "size": "32x32" },
    { "filename": "AppIcon-64.png", "idiom": "mac", "scale": "2x", "size": "32x32" },
    { "filename": "AppIcon-128.png", "idiom": "mac", "scale": "1x", "size": "128x128" },
    { "filename": "AppIcon-256.png", "idiom": "mac", "scale": "2x", "size": "128x128" },
    { "filename": "AppIcon-256.png", "idiom": "mac", "scale": "1x", "size": "256x256" },
    { "filename": "AppIcon-512.png", "idiom": "mac", "scale": "2x", "size": "256x256" },
    { "filename": "AppIcon-512.png", "idiom": "mac", "scale": "1x", "size": "512x512" },
    { "filename": "AppIcon-1024.png", "idiom": "mac", "scale": "2x", "size": "512x512" }
  ]
}
""",
        "docs/assets/sciplot-app-icon.svg": "<svg />\n",
        "docs/macos-frontend-design.md": """
# macOS Frontend Design Handoff

Liquid Glass
Pro workspace
Launcher
Plot
Data Studio
Composer
Code Console
App Icon
""",
        "app/macos/Sources/Features/Plot/PlotDataWorkbookSheet.swift": (
            "struct PlotDataWorkbookSheet { let dataPipelineSummary = \"\" }\n"
        ),
        "app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift": (
            "DataStudioPreparationInspectorView\n"
            "InspectorSection(title: \"Actions\")\nInspectorSection(title: \"Figure\")\n"
            "Button(\"Open in Plot\")\nButton(\"Analysis\")\n"
        ),
        "app/macos/Sources/Features/DataStudio/DataStudioAnalysisSheet.swift": (
            "FitModelGrid(\n"
            "session.updateAnalysisFitModel(option.id)\n"
            "analysisFitSummaryRows\n"
        ),
        "app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift": (
            "let isInspectorPresented = true\n"
            "DataStudioPreparationInspectorView(session: session)\n"
            "DataStudioGroupRailView(session: session)\n"
            "DataStudioPreviewWorkspaceView(session: session)\n"
            "DataStudioAnalysisSheet(session: session)\n"
            "@Environment(\\.proWorkspaceTheme) private var theme\n"
        ),
        "app/macos/Sources/Features/DataStudio/DataStudioGroupRailView.swift": (
            "WorkbenchRailTitle(title: \"Workbook Groups\")\n"
            "DataStudioFigureRailSection(session: session)\n"
            "DataStudioFigureRailRow\n"
            "let figureFamilyBinding = Binding<String?>.constant(nil)\n"
            "proGlassPanel(theme: theme)\n"
        ),
        "app/macos/Sources/Features/DataStudio/DataStudioPreviewWorkspaceView.swift": (
            "PlotRefineView(session: session.plotSession)\n"
            "DataStudioFocusedWorkbookStrip\n"
            "DataStudioInlinePreviewBanner\n"
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
        "app/macos/Sources/Features/Composer/ComposerWorkbenchView.swift": (
            "ComposerProWorkspace\n"
            "ComposerAssetBrowserView(session: session)\n"
            "ComposerCanvasView(session: session)\n"
            "ComposerInspectorView(session: session)\n"
            ".proGlassPanel(theme: theme)\n"
            "@Environment(\\.proWorkspaceTheme) private var theme\n"
        ),
        "app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift": (
            "CodeConsoleProWorkspace\n"
            "CodeConsoleSourceRailView(session: session)\nCodeConsoleOutputsView()\n"
            "CodeConsoleRunWorkspaceView(session: session)\n"
            "CodeConsoleContextView(session: session)\n"
            "Picker(\"Sheet\", selection: selectedSheetSelection)\n"
            ".proGlassPanel(theme: theme)\n"
            ".padding(.top, 54)\n"
            "@Environment(\\.proWorkspaceTheme) private var theme\n"
        ),
        "app/macos/Sources/Features/CodeConsole/CodeConsoleEditorView.swift": (
            ".frame(minHeight: 96, idealHeight: 126, maxHeight: 150)\n"
            ".frame(minHeight: 210, idealHeight: 260, maxHeight: .infinity)\n"
            "private func promptHeader\n"
            ".layoutPriority(1)\n"
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
        "docs/ui-ux-audit-2026-04-29.md": (
            "# SciPlot UI/UX Audit\n"
            "Pixelmator Pro\nDataGraph\nOrigin\nPrism\nFigma\nKeynote\nVS Code\nJupyter\n"
            "Reasonable\nNeeds attention\n"
        ),
    }
    if overrides:
        sources.update(overrides)

    for relative_path, content in sources.items():
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    icon_dir = root / "app/macos/Assets.xcassets/AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    for filename in (
        "AppIcon-16.png",
        "AppIcon-32.png",
        "AppIcon-64.png",
        "AppIcon-128.png",
        "AppIcon-256.png",
        "AppIcon-512.png",
        "AppIcon-1024.png",
    ):
        (icon_dir / filename).write_bytes(b"png")


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


def test_gui_presentation_checks_reject_launcher_outer_window_chrome(tmp_path: Path) -> None:
    _write_sources(
        tmp_path,
        {
            "app/macos/Sources/App/SciPlotApp.swift": """
import SwiftUI
@main
struct SciPlotApp: App {
    @State private var model = SciPlotAppState.model
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceModeRawValue = AppAppearanceMode.system.rawValue
    var appearanceMode: AppAppearanceMode { .system }
    var body: some Scene {
        WindowGroup("SciPlot", id: "launcher") { LauncherWindowRoot(model: model) }
            .defaultSize(width: 760, height: 460)
            .windowResizability(.contentSize)
            .defaultLaunchBehavior(.presented)
            .restorationBehavior(.disabled)
            .commands { AppCommands(model: model, appearanceModeRawValue: appearanceModeRawValueBinding) }
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
private enum SciPlotAppState { static let model = AppModel() }
enum AppAppearanceMode {
    static let storageKey = "appAppearanceMode"
    static let system = AppAppearanceMode()
    var rawValue: String { "system" }
    var preferredColorScheme: ColorScheme? { nil }
}
final class AppWindowManager {
    func openLauncherAfterSceneAttempt() {}
    func applicationShouldHandleReopen() {}
    func hasVisibleWindow(id: String) -> Bool { false }
    func configureLauncherWindow(_ window: NSWindow) {
        window.styleMask = [.titled, .closable]
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
    }
}
final class BorderlessLauncherWindow {}
"""
        },
    )

    issues = check_macos_gui_presentation.run_checks(tmp_path)

    assert any("borderless transparent launcher" in issue for issue in issues)


def test_gui_presentation_checks_reject_central_stage_backdrops(tmp_path: Path) -> None:
    _write_sources(
        tmp_path,
        {
            "app/macos/Sources/Features/Plot/PlotRefineView.swift": """
PlotPreviewStage(session: session)
PlotInteractivePreviewSurface(session: session, preview: preview)
ProgressView()
theme.stageBackground
previewSurface
struct PlotStageDiagnosticBanner {
    let shape = RoundedRectangle(cornerRadius: 14)
}
private struct PlotEmptyPreviewPage {
    let shape = RoundedRectangle(cornerRadius: 8)
}
"""
        },
    )

    issues = check_macos_gui_presentation.run_checks(tmp_path)

    assert any("central stage must not draw a rectangular backdrop" in issue for issue in issues)


def test_gui_presentation_checks_reject_button_like_text_overlay_marker(tmp_path: Path) -> None:
    _write_sources(
        tmp_path,
        {
            "app/macos/Sources/Features/Plot/PlotInteractivePreviewOverlay.swift": """
PlotInteractivePreviewSurface(session: session, preview: preview)
InteractivePlotOverlay(session: session, mapper: mapper)
PlotPreviewCoordinateMapper(metadata: metadata, viewportSize: size)
Base64PreviewImageView(base64PNG: previewPNG)
Base64PDFPreviewView(base64PDF: preview.pdfBase64)
commitCanvasDraft(.text(point: point, displayStyle: "plain", connectorTarget: nil))
drawTextSelection(at: point, in: &context)
drawTargetTick(at: point, in: &context)
drawRoundedSquareHandles(for: annotation, rect: rect, in: &context)
context.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(accent), lineWidth: 2)
""",
        },
    )

    issues = check_macos_gui_presentation.run_checks(tmp_path)

    assert any("button-like text markers" in issue for issue in issues)


def test_gui_presentation_checks_reject_duplicate_app_commands(tmp_path: Path) -> None:
    _write_sources(
        tmp_path,
        {
            "app/macos/Sources/App/SciPlotApp.swift": """
import SwiftUI
@main
struct SciPlotApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup("SciPlot", id: "launcher") { LauncherWindowRoot(model: model) }
            .defaultSize(width: 1520, height: 900)
            .windowResizability(.contentMinSize)
            .defaultLaunchBehavior(.presented)
            .restorationBehavior(.disabled)
            .commands { AppCommands(model: model, appearanceModeRawValue: appearanceModeRawValueBinding) }
        Window("Plot", id: Workbench.plot.windowSceneID) {
            WorkbenchWindowRoot(workbench: .plot, model: model)
        }
            .commands { AppCommands(model: model, appearanceModeRawValue: appearanceModeRawValueBinding) }
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
