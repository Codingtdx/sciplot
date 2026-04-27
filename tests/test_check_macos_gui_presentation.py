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
            .defaultLaunchBehavior(.presented)
            .restorationBehavior(.disabled)
            .commands { AppCommands(model: model) }
    }
}
""",
        "app/macos/Sources/App/RootSplitView.swift": """
struct RootSplitView {
    var body: some View {
        WorkbenchSidebarRail()
        WorkbenchToolbarContent()
    }
}
""",
        "app/macos/Sources/Features/Plot/PlotTemplateView.swift": "PlotTemplateRow()\n",
        "app/macos/Sources/Features/Plot/PlotRefineView.swift": "SubtleStageHint(title: \"Preview\")\n",
        "app/macos/Sources/Features/Plot/PlotWorkbenchView.swift": "PlotTemplateView()\n",
        "app/macos/Sources/Features/Plot/PlotDataWorkbookSheet.swift": (
            "struct PlotDataWorkbookSheet { let dataPipelineSummary = \"\" }\n"
        ),
        "app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift": (
            "WorkbenchRailTitle(title: \"Workbook Groups\")\n"
        ),
        "app/macos/Sources/Features/Composer/ComposerAssetBrowserView.swift": "SubtleStageHint(title: \"Import\")\n",
        "app/macos/Sources/Features/Composer/ComposerCanvasView.swift": (
            "RoundedRectangle(cornerRadius: 22)\n"
        ),
        "app/macos/Sources/Features/Composer/ComposerInspectorView.swift": (
            "ComposerInspectorPreviewContent()\n"
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
