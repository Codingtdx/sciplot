from __future__ import annotations

import json
from pathlib import Path

from scripts import manual_smoke_evidence


def test_init_creates_empty_evidence_bundle(tmp_path: Path) -> None:
    output_path = tmp_path / "manual-smoke.json"

    exit_code = manual_smoke_evidence.main(["init", "--output", str(output_path)])

    assert exit_code == 0
    payload = json.loads(output_path.read_text(encoding="utf-8"))
    assert payload["schema_version"] == 1
    assert payload["checks"] == []
    assert payload["generated_at"]


def test_validate_requires_all_passed_checks_with_existing_evidence_files(tmp_path: Path) -> None:
    bundle_path = tmp_path / "manual-smoke.json"
    bundle_path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "generated_at": "2026-04-26T00:00:00+00:00",
                "checks": [
                    {
                        "id": "plot_import_preview_export",
                        "status": "passed",
                        "notes": ["preview looked correct"],
                        "evidence_files": [str(tmp_path / "plot.png")],
                        "recorded_at": "2026-04-26T00:00:01+00:00",
                    },
                    {
                        "id": "data_studio_import_open_plot",
                        "status": "blocked",
                        "notes": ["save panel blocked automation"],
                        "evidence_files": [],
                        "recorded_at": "2026-04-26T00:00:02+00:00",
                    },
                ],
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    exit_code = manual_smoke_evidence.main(["validate", "--input", str(bundle_path), "--require-all"])

    assert exit_code == 2


def test_validate_passes_when_all_required_checks_are_recorded_with_real_files(tmp_path: Path) -> None:
    bundle_path = tmp_path / "manual-smoke.json"
    evidence_files = []
    for stem in ("plot", "data_studio", "overlay"):
        evidence_path = tmp_path / f"{stem}.png"
        evidence_path.write_text("ok", encoding="utf-8")
        evidence_files.append(str(evidence_path))

    bundle_path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "generated_at": "2026-04-26T00:00:00+00:00",
                "checks": [
                    {
                        "id": "plot_import_preview_export",
                        "status": "passed",
                        "notes": ["plot flow completed"],
                        "evidence_files": [evidence_files[0]],
                        "recorded_at": "2026-04-26T00:00:01+00:00",
                    },
                    {
                        "id": "data_studio_import_open_plot",
                        "status": "passed",
                        "notes": ["data studio flow completed"],
                        "evidence_files": [evidence_files[1]],
                        "recorded_at": "2026-04-26T00:00:02+00:00",
                    },
                    {
                        "id": "overlay_drag_save_reopen",
                        "status": "passed",
                        "notes": ["overlay flow completed"],
                        "evidence_files": [evidence_files[2]],
                        "recorded_at": "2026-04-26T00:00:03+00:00",
                    },
                ],
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    exit_code = manual_smoke_evidence.main(["validate", "--input", str(bundle_path), "--require-all"])

    assert exit_code == 0
