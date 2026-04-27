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
        label="app scene remains a single native main window",
        path="app/macos/Sources/App/SciPlotGodApp.swift",
        required=(
            'WindowGroup("SciPlot God")',
            ".defaultLaunchBehavior(.presented)",
            ".restorationBehavior(.disabled)",
            "@State private var model = AppModel()",
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
        label="RootSplitView keeps sidebar as navigation chrome",
        path="app/macos/Sources/App/RootSplitView.swift",
        required=("WorkbenchSidebarRail(", "WorkbenchToolbarContent("),
        forbidden=('Text("SciPlot God")',),
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
        label="Plot inspector uses shared plain sections",
        path="app/macos/Sources/Features/Plot/PlotInspectorView.swift",
        required=(
            'InspectorSection(title: "Actions")',
            'InspectorSection(title: "Axis")',
            'InspectorSection(title: "Advanced Plot")',
        ),
        forbidden=(
            "Form {",
            "Section(styleSectionTitle)",
            'Section("Actions")',
            'Section("Axis")',
            'Section("Advanced Plot")',
            'InspectorEmptyState(message: "No figure controls")',
            ".formStyle(",
        ),
    ),
    SourceCheck(
        label="Plot preview empty state is not a hero card",
        path="app/macos/Sources/Features/Plot/PlotRefineView.swift",
        forbidden=('EmptyStateCard(title: "No Preview")',),
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
        required=('WorkbenchRailTitle(title: "Workbook Groups"',),
        forbidden=('EmptyStateCard(title: "No groups")',),
    ),
    SourceCheck(
        label="Data Studio inspector uses shared plain sections",
        path="app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift",
        required=('InspectorSection(title: "Actions")', 'InspectorSection(title: "Figure")'),
        forbidden=('Section("Figure")', 'Section("Actions")', 'InspectorEmptyState(message: "No figure controls")'),
    ),
    SourceCheck(
        label="Composer asset rail avoids hero imported-panel empty state",
        path="app/macos/Sources/Features/Composer/ComposerAssetBrowserView.swift",
        forbidden=('EmptyStateCard(title: "No imported panels")',),
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
        required=("ComposerInspectorPreviewContent",),
        forbidden=('Section("Preview")',),
    ),
    SourceCheck(
        label="Code Console root avoids hero card empty state",
        path="app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift",
        forbidden=("EmptyStateCard(",),
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
        required=("InspectorSection(",),
        forbidden=(".formStyle(.grouped)",),
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
