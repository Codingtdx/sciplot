from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from scripts import blocking_gate

REPO_ROOT = Path(__file__).resolve().parents[1]
ROADMAP_PATH = REPO_ROOT / "docs" / "labplot-informed-roadmap.md"
PROGRESS_PATH = REPO_ROOT / "docs" / "labplot-roadmap-progress.md"
CODE_STUDY_PATH = REPO_ROOT / "docs" / "labplot-technical-borrowing.md"
ENGINEERING_HANDOFF_PATH = REPO_ROOT / "docs" / "engineering-handoff.md"
SCRIPT_PATH = REPO_ROOT / "scripts" / "check_labplot_cleanroom.py"


def run_guard(root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT_PATH), "--root", str(root)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_labplot_runtime_handoff_records_cleanroom_architecture() -> None:
    text = ENGINEERING_HANDOFF_PATH.read_text(encoding="utf-8")

    required_phrases = (
        "SciPlotDocumentGraph",
        "document_graph",
        "Clean-room policy",
        "Data containers",
        "Analysis operations",
        "Import and export runtime",
        "Plot object commands and UndoManager",
        "Code Console notebook bridge",
        "Launcher plus four singleton module windows",
        "Apache-2.0",
        "GPL source",
        "/meta",
        "UndoManager",
        "Testing policy",
        "No LabPlot C++/Qt/NSL implementation",
    )
    for phrase in required_phrases:
        assert phrase in text


def test_labplot_code_study_records_engineering_translation() -> None:
    text = CODE_STUDY_PATH.read_text(encoding="utf-8")

    required_phrases = (
        "AbstractAspect",
        "aspectcommands",
        "AbstractFileFilter",
        "FilterStatus",
        "XYAnalysisCurve",
        "recalculateSpecific",
        "CartesianPlot",
        "Axis",
        "FitTest",
        "NIST",
        "SciPlot translation",
        "No LabPlot C++ implementation is vendored",
        "typed command ledger",
        "operation result envelope",
        "fixture-driven numerical tests",
    )
    for phrase in required_phrases:
        assert phrase in text


def test_labplot_roadmap_files_are_retired_after_runtime_landing() -> None:
    assert not ROADMAP_PATH.exists()
    assert not PROGRESS_PATH.exists()
    handoff_text = ENGINEERING_HANDOFF_PATH.read_text(encoding="utf-8")

    required_phrases = (
        "LabPlot-scale runtime is product surface, not roadmap",
        "Capability status policy",
        "`enabled` means",
        "disabled",
        "DataContainerPayload",
        "AnalysisOperationResultPayload",
        "Plot durable edits use typed commands",
        "Project graph and Code Console artifacts",
        "scripts/check_labplot_cleanroom.py",
    )
    for phrase in required_phrases:
        assert phrase in handoff_text


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
