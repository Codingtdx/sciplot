from __future__ import annotations

import argparse
import subprocess
import time
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

try:
    from scripts import manual_smoke_evidence
except ImportError:
    import manual_smoke_evidence

REPO_ROOT = Path(__file__).resolve().parents[1]
PYTHON = ".venv/bin/python"


@dataclass(frozen=True)
class GateCommand:
    label: str
    command: tuple[str, ...]


AUTOMATED_GATE_COMMANDS: tuple[GateCommand, ...] = (
    GateCommand("clean_repo", (PYTHON, "scripts/clean_repo.py")),
    GateCommand(
        "ruff",
        (PYTHON, "-m", "ruff", "check", "."),
    ),
    GateCommand(
        "mypy",
        (
            PYTHON,
            "-m",
            "mypy",
            "src/composer.py",
            "src/plot_contract.py",
            "src/data_loader.py",
            "src/tensile_replicates.py",
            "src/rendering",
        ),
    ),
    GateCommand("pytest", (PYTHON, "-m", "pytest", "tests")),
    GateCommand("smoke_check", (PYTHON, "scripts/smoke_check.py")),
    GateCommand("macos_gui_presentation", (PYTHON, "scripts/check_macos_gui_presentation.py")),
    GateCommand(
        "xcodebuild build",
        (
            "xcodebuild",
            "-project",
            "app/macos/SciPlotGod.xcodeproj",
            "-scheme",
            "SciPlotGodMac",
            "-destination",
            "platform=macOS,arch=arm64",
            "-derivedDataPath",
            "app/macos/.derivedData",
            "build",
        ),
    ),
    GateCommand(
        "xcodebuild test",
        (
            "xcodebuild",
            "-project",
            "app/macos/SciPlotGod.xcodeproj",
            "-scheme",
            "SciPlotGodMac",
            "-destination",
            "platform=macOS,arch=arm64",
            "-derivedDataPath",
            "app/macos/.derivedData",
            "test",
        ),
    ),
)

MANUAL_CHECKS: tuple[tuple[str, str], ...] = (
    ("plot_import_preview_export", "Plot: Import -> Inspect -> Preview -> Export"),
    ("data_studio_import_open_plot", "Data Studio: Import -> Template -> Workbook -> Open in Plot"),
    ("overlay_drag_save_reopen", "Overlay: add/select/drag(or nudge) -> Save Project -> Reopen -> position consistent"),
)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run blocking gate automation matrix and track manual smoke checklist coverage."
    )
    parser.add_argument(
        "--require-manual",
        action="store_true",
        help="Fail if all manual smoke checks are not explicitly confirmed via --manual-check.",
    )
    parser.add_argument(
        "--manual-check",
        action="append",
        default=[],
        choices=[name for name, _ in MANUAL_CHECKS],
        help="Mark one manual smoke check as completed. Repeat for each completed check.",
    )
    parser.add_argument(
        "--manual-evidence",
        help=(
            "Path to a manual smoke evidence JSON bundle. "
            "Passed checks with real evidence files count toward manual coverage."
        ),
    )
    parser.add_argument(
        "--skip-manual-checklist",
        action="store_true",
        help="Skip manual checklist output and status handling.",
    )
    return parser.parse_args(argv)


def run_gate_command(item: GateCommand) -> None:
    command_text = " ".join(item.command)
    print(f"[gate] running: {item.label}")
    print(f"        {command_text}")
    started = time.monotonic()
    result = subprocess.run(item.command, cwd=REPO_ROOT, check=False)
    elapsed = time.monotonic() - started
    if result.returncode != 0:
        raise RuntimeError(f"{item.label} failed with exit code {result.returncode} after {elapsed:.1f}s")
    print(f"[gate] passed: {item.label} ({elapsed:.1f}s)")


def report_manual_checklist(*, selected: set[str], require_manual: bool) -> int:
    print("[gate] manual smoke checklist")
    for name, description in MANUAL_CHECKS:
        mark = "x" if name in selected else " "
        print(f"  - [{mark}] {name}: {description}")

    pending = [name for name, _ in MANUAL_CHECKS if name not in selected]
    if not pending:
        print("[gate] all manual smoke checks confirmed.")
        return 0

    print("[gate] pending manual checks:", ", ".join(pending))
    if require_manual:
        print("[gate] failing because --require-manual was enabled.")
        return 2
    print("[gate] continuing without manual enforcement (use --require-manual to enforce).")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    selected_manual_checks = set(args.manual_check)
    strict_manual_checks: set[str] | None = None
    try:
        for item in AUTOMATED_GATE_COMMANDS:
            run_gate_command(item)
    except RuntimeError as error:
        print(f"[gate] failed: {error}")
        return 1

    print("[gate] automated matrix passed.")
    if args.skip_manual_checklist:
        return 0
    if args.manual_evidence:
        evidence_checks, evidence_issues = manual_smoke_evidence.completed_checks_from_evidence(
            Path(args.manual_evidence)
        )
        if evidence_checks:
            print("[gate] manual evidence confirms:", ", ".join(sorted(evidence_checks)))
            selected_manual_checks.update(evidence_checks)
        if evidence_issues:
            print("[gate] manual evidence issues:")
            for issue in evidence_issues:
                print(f"  - {issue}")
        if args.require_manual:
            strict_manual_checks = set(evidence_checks)
            selected_manual_checks = set(evidence_checks)
        else:
            selected_manual_checks.update(evidence_checks)
    elif args.require_manual:
        print("[gate] failing because --require-manual now requires --manual-evidence with complete evidence.")
        strict_manual_checks = set()

    return report_manual_checklist(
        selected=strict_manual_checks if strict_manual_checks is not None else selected_manual_checks,
        require_manual=args.require_manual,
    )


if __name__ == "__main__":
    raise SystemExit(main())
