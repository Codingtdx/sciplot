from __future__ import annotations

import json
from pathlib import Path

from scripts import blocking_gate


def _write_manual_evidence(tmp_path: Path, *, all_passed: bool) -> Path:
    evidence_paths = []
    for stem in ("plot", "data_studio", "overlay"):
        evidence_path = tmp_path / f"{stem}.png"
        evidence_path.write_text("ok", encoding="utf-8")
        evidence_paths.append(str(evidence_path))

    statuses = ["passed", "passed", "passed"] if all_passed else ["passed", "blocked", "passed"]
    bundle_path = tmp_path / "manual-smoke.json"
    bundle_path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "generated_at": "2026-04-26T00:00:00+00:00",
                "checks": [
                    {
                        "id": "plot_import_preview_export",
                        "status": statuses[0],
                        "notes": ["plot"],
                        "evidence_files": [evidence_paths[0]],
                        "recorded_at": "2026-04-26T00:00:01+00:00",
                    },
                    {
                        "id": "data_studio_import_open_plot",
                        "status": statuses[1],
                        "notes": ["data studio"],
                        "evidence_files": [evidence_paths[1]] if statuses[1] == "passed" else [],
                        "recorded_at": "2026-04-26T00:00:02+00:00",
                    },
                    {
                        "id": "overlay_drag_save_reopen",
                        "status": statuses[2],
                        "notes": ["overlay"],
                        "evidence_files": [evidence_paths[2]],
                        "recorded_at": "2026-04-26T00:00:03+00:00",
                    },
                ],
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    return bundle_path


def test_require_manual_accepts_complete_manual_evidence(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(blocking_gate, "AUTOMATED_GATE_COMMANDS", ())
    evidence_path = _write_manual_evidence(tmp_path, all_passed=True)

    exit_code = blocking_gate.main(["--require-manual", "--manual-evidence", str(evidence_path)])

    assert exit_code == 0


def test_require_manual_rejects_incomplete_manual_evidence(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(blocking_gate, "AUTOMATED_GATE_COMMANDS", ())
    evidence_path = _write_manual_evidence(tmp_path, all_passed=False)

    exit_code = blocking_gate.main(["--require-manual", "--manual-evidence", str(evidence_path)])

    assert exit_code == 2


def test_require_manual_rejects_explicit_manual_checks_without_evidence(monkeypatch) -> None:
    monkeypatch.setattr(blocking_gate, "AUTOMATED_GATE_COMMANDS", ())

    exit_code = blocking_gate.main(
        [
            "--require-manual",
            "--manual-check",
            "plot_import_preview_export",
            "--manual-check",
            "data_studio_import_open_plot",
            "--manual-check",
            "overlay_drag_save_reopen",
        ]
    )

    assert exit_code == 2


def test_automated_gate_includes_macos_gui_presentation_check() -> None:
    labels = [item.label for item in blocking_gate.AUTOMATED_GATE_COMMANDS]

    assert "macos_gui_presentation" in labels
