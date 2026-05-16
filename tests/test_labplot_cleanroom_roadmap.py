from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from scripts import blocking_gate

REPO_ROOT = Path(__file__).resolve().parents[1]
ROADMAP_PATH = REPO_ROOT / "docs" / "labplot-informed-roadmap.md"
SCRIPT_PATH = REPO_ROOT / "scripts" / "check_labplot_cleanroom.py"


def run_guard(root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT_PATH), "--root", str(root)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_labplot_roadmap_records_cleanroom_architecture() -> None:
    text = ROADMAP_PATH.read_text(encoding="utf-8")

    required_phrases = (
        "SciPlotDocumentGraph",
        "module-scoped document graph",
        "Clean-room policy",
        "Spreadsheet/Matrix",
        "Worksheet/CartesianPlot",
        "Axis/Legend/XYCurve",
        "Analysis curves/NSL",
        "Import filters",
        "Launcher plus four singleton module windows",
        "Apache-2.0",
        "GPL-2.0-or-later",
        "/meta",
        "src/plot_contract.json",
        "UndoManager",
    )
    for phrase in required_phrases:
        assert phrase in text


def test_labplot_cleanroom_guard_accepts_repo() -> None:
    result = run_guard(REPO_ROOT)

    assert result.returncode == 0, result.stdout + result.stderr
    assert "no LabPlot GPL source headers found" in result.stdout


def test_labplot_cleanroom_guard_rejects_copied_labplot_source(tmp_path: Path) -> None:
    copied_source = tmp_path / "src" / "backend" / "worksheet" / "XYCurve.h"
    copied_source.parent.mkdir(parents=True)
    copied_source.write_text(
        """/*
    File                 : XYCurve.h
    Project              : LabPlot
    Description          : A xy-curve
    SPDX-License-Identifier: GPL-2.0-or-later
*/
class XYCurve {};
""",
        encoding="utf-8",
    )

    result = run_guard(tmp_path)

    assert result.returncode == 2
    assert "XYCurve.h" in result.stdout
    assert "LabPlot GPL source header" in result.stdout


def test_blocking_gate_includes_labplot_cleanroom_guard() -> None:
    labels = [item.label for item in blocking_gate.AUTOMATED_GATE_COMMANDS]

    assert "labplot_cleanroom" in labels
