from __future__ import annotations

from pathlib import Path

import fitz
import pandas as pd
import pytest
from fastapi.testclient import TestClient

from app.sidecar import server
from app.sidecar.server import app
from src.tensile_replicates import export_tensile_replicate_workbook

client = TestClient(app)
FIXTURE_DIR = Path(__file__).resolve().parent / "fixtures" / "tensile_raw"


def _write_curve_table(path: Path) -> Path:
    rows = [
        ["Time", "Stress"],
        ["s", "MPa"],
        ["Sample A", "Sample A"],
        [0, 1.0],
        [1, 1.4],
        [2, 1.8],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_dense_curve_table(path: Path) -> Path:
    import numpy as np

    x = np.linspace(0.5, 10.0, 80)
    y_a = np.sin(x / 2.0) + 2.1
    y_b = np.cos(x / 3.0) + 3.2
    rows = [
        ["Strain", "Stress", "Strain", "Stress"],
        ["%", "MPa", "%", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
    ]
    for x_value, y_value_a, y_value_b in zip(x, y_a, y_b, strict=True):
        rows.append([x_value, y_value_a, x_value, y_value_b])
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_pdf(path: Path, width_mm: float, height_mm: float) -> Path:
    document = fitz.open()
    document.new_page(width=width_mm / 25.4 * 72.0, height=height_mm / 25.4 * 72.0)
    document.save(path)
    document.close()
    return path


def _write_tensile_workbook(path: Path, *, group_name: str = "BlendSet") -> Path:
    export_tensile_replicate_workbook(
        [
            FIXTURE_DIR / "BlendSet_A.csv",
            FIXTURE_DIR / "BlendSet_B.csv",
            FIXTURE_DIR / "BlendSet_bad.csv",
        ],
        path,
        group_name=group_name,
    )
    return path


def test_meta_endpoint_returns_contract_backed_payload() -> None:
    response = client.get("/meta")

    assert response.status_code == 200
    payload = response.json()
    assert payload["template_ids"]
    assert payload["size_ids"]
    assert payload["palette_preset_ids"]
    assert len(payload["templates"]) == len(payload["template_ids"])


def test_plot_contract_endpoint_exposes_validation_rules() -> None:
    response = client.get("/plot-contract")

    assert response.status_code == 200
    payload = response.json()
    assert "axis_policy" in payload
    assert "qa_profiles" in payload
    assert "validation_rules" in payload
    assert "templates" in payload
    assert "curve" in payload["templates"]


def test_inspect_file_endpoint_returns_valid_nested_schema(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    response = client.post(
        "/inspect-file",
        json={"input_path": str(input_path), "sheet": 0},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["input_path"] == str(input_path)
    assert payload["inspection"]["model"] == "curve_table"
    assert payload["inspection"]["recommendation"]["template"] == "curve"


def test_save_and_open_project_round_trips_composer_v2_payload(tmp_path: Path) -> None:
    project_path = tmp_path / "composer.plotproject.json"
    payload = {
        "version": 2,
        "mode": "composer",
        "project": {
            "version": 2,
            "mode": "composer",
            "canvas_width_mm": 180,
            "canvas_height_mm": 170,
            "grid_mm": 0.5,
            "layout_grid": {
                "columns": 3,
                "rows": 3,
                "cell_width_mm": 60,
                "cell_height_mm": 55,
                "frame_x_mm": 0,
                "frame_y_mm": 2.5,
                "frame_width_mm": 180,
                "frame_height_mm": 165,
            },
            "regions": [
                {
                    "id": "region-1",
                    "kind": "graph",
                    "col": 0,
                    "row": 0,
                    "col_span": 1,
                    "row_span": 1,
                    "slot_kind": None,
                }
            ],
            "panels": [
                {
                    "id": "panel-1",
                    "file_path": "/tmp/a.pdf",
                    "page_index": 0,
                    "x_mm": 0,
                    "y_mm": 2.5,
                    "w_mm": 60,
                    "h_mm": 55,
                    "hidden": True,
                    "kind": "graph",
                    "z_index": 0,
                    "group_id": None,
                    "region_id": "region-1",
                    "slot_id": None,
                    "crop_rect": {"x": 0, "y": 0, "width": 1, "height": 1},
                }
            ],
            "texts": [
                {
                    "id": "text-1",
                    "text": "Legend",
                    "x_mm": 12,
                    "y_mm": 15,
                    "font_size_pt": 8,
                    "align": "left",
                    "z_index": 1,
                    "locked": True,
                    "hidden": False,
                    "group_id": "group-1",
                    "region_id": None,
                    "slot_id": None,
                }
            ],
            "auto_labels": False,
        },
    }

    save_response = client.post(
        "/save-project",
        json={"project_path": str(project_path), "data": payload},
    )
    assert save_response.status_code == 200

    open_response = client.post(
        "/open-project",
        json={"project_path": str(project_path)},
    )
    assert open_response.status_code == 200
    payload = open_response.json()["data"]
    assert payload["mode"] == "composer"
    assert payload["project"]["version"] == 2
    assert payload["project"]["layout_grid"]["cell_height_mm"] == 55
    assert payload["project"]["regions"][0]["id"] == "region-1"
    assert payload["project"]["panels"][0]["file_path"] == "/tmp/a.pdf"
    assert payload["project"]["panels"][0]["hidden"] is True
    assert payload["project"]["texts"][0]["locked"] is True
    assert payload["project"]["texts"][0]["group_id"] == "group-1"


def test_save_and_open_project_round_trips_wizard_style_preset(tmp_path: Path) -> None:
    project_path = tmp_path / "wizard.plotproject.json"
    payload = {
        "version": 1,
        "mode": "wizard",
        "wizard": {
            "input_path": "/tmp/demo.csv",
            "sheet": "Sheet1",
            "template": "curve",
            "options": {
                "size": "60x55",
                "style_preset": "nature",
                "palette_preset": "colorblind_safe",
            },
            "outputs": ["/tmp/demo_curve.pdf"],
        },
    }

    save_response = client.post(
        "/save-project",
        json={"project_path": str(project_path), "data": payload},
    )
    assert save_response.status_code == 200

    open_response = client.post(
        "/open-project",
        json={"project_path": str(project_path)},
    )
    assert open_response.status_code == 200
    reopened = open_response.json()["data"]
    assert reopened["wizard"]["options"]["style_preset"] == "nature"
    assert reopened["wizard"]["options"]["palette_preset"] == "colorblind_safe"


def test_open_project_rejects_legacy_composer_v1(tmp_path: Path) -> None:
    project_path = tmp_path / "legacy.plotproject.json"
    project_path.write_text(
        """
        {
          "version": 1,
          "mode": "composer",
          "project": {
            "version": 1,
            "mode": "composer",
            "canvas_width_mm": 180,
            "canvas_height_mm": 170,
            "grid_mm": 0.5,
            "panels": [],
            "texts": [],
            "auto_labels": true
          }
        }
        """.strip(),
        encoding="utf-8",
    )

    response = client.post(
        "/open-project",
        json={"project_path": str(project_path)},
    )

    assert response.status_code == 400
    assert "only support version: 2" in response.json()["detail"]


def test_open_project_rejects_invalid_json(tmp_path: Path) -> None:
    project_path = tmp_path / "broken.plotproject.json"
    project_path.write_text("{not-json", encoding="utf-8")

    response = client.post(
        "/open-project",
        json={"project_path": str(project_path)},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "The project file is not valid JSON."


def test_save_project_rejects_unknown_mode(tmp_path: Path) -> None:
    project_path = tmp_path / "unknown.plotproject.json"

    response = client.post(
        "/save-project",
        json={
            "project_path": str(project_path),
            "data": {"version": 1, "mode": "mystery"},
        },
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "This is not a recognizable SciPlot God project file."


def test_preprocess_tensile_replicates_returns_string_output_path(tmp_path: Path) -> None:
    output_path = tmp_path / "BlendSet_plot_wizard_template.xlsx"

    response = client.post(
        "/preprocess-tensile-replicates",
        json={
            "file_paths": [
                str(FIXTURE_DIR / "BlendSet_A.csv"),
                str(FIXTURE_DIR / "BlendSet_B.csv"),
                str(FIXTURE_DIR / "BlendSet_bad.csv"),
            ],
            "output_path": str(output_path),
            "group_name": "BlendSet",
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["output_path"] == str(output_path)
    assert payload["sample_count"] == 2
    assert payload["preferred_sheet"] == "Representative_Curve"
    assert "BlendSet_bad.csv" in payload["warnings"][0]


def test_preflight_render_includes_submission_report_and_style_preset(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    response = client.post(
        "/preflight-render",
        json={
            "input_path": str(input_path),
            "sheet": 0,
            "template": "curve",
            "options": {
                "style_preset": "nature",
                "palette_preset": "colorblind_safe",
            },
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["options"]["style_preset"] == "nature"
    assert payload["preflight"]["submission_report"]["style_preset"] == "nature"
    assert payload["preflight"]["submission_report"]["context"] == "preflight"
    assert payload["preflight"]["submission_report"]["checks"]


def test_render_preview_includes_advisory_qa_payload_and_submission_report(tmp_path: Path) -> None:
    input_path = _write_dense_curve_table(tmp_path / "dense_curve.csv")

    response = client.post(
        "/render-preview",
        json={
            "input_path": str(input_path),
            "sheet": 0,
            "template": "curve",
            "options": {
                "style_preset": "nature",
                "palette_preset": "colorblind_safe",
            },
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["previews"]
    assert payload["submission_report"]["context"] == "preview"
    assert payload["submission_report"]["style_preset"] == "nature"
    qa = payload["previews"][0]["qa"]
    assert qa["grade"] in {"excellent", "solid", "needs_cleanup"}
    assert "direct_series_labels" in qa["autofixes_applied"]


def test_export_render_writes_bundle_artifacts_and_submission_report(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")
    output_dir = tmp_path / "exports"

    response = client.post(
        "/export-render",
        json={
            "input_path": str(input_path),
            "sheet": 0,
            "template": "curve",
            "options": {
                "style_preset": "nature",
                "palette_preset": "colorblind_safe",
            },
            "output_dir": str(output_dir),
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["output_dir"] == str(output_dir)
    assert payload["submission_report"]["context"] == "export"
    assert Path(payload["outputs"][0]).exists()
    assert all(Path(path).exists() for path in payload["preview_outputs"])
    assert all(Path(path).exists() for path in payload["artifact_paths"])
    assert {Path(path).name for path in payload["artifact_paths"]} == {
        "codegod_normalized_options.json",
        "codegod_inspection.json",
        "codegod_preflight.json",
        "codegod_submission_report.json",
        "codegod_manifest.json",
    }
    assert Path(payload["manifest_path"]).exists()


def test_open_path_endpoint_uses_host_launcher(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    target = tmp_path / "exports"
    target.mkdir()
    opened: list[Path] = []

    monkeypatch.setattr(server, "_open_path_with_host", lambda path: opened.append(path))

    response = client.post(
        "/open-path",
        json={"output_path": str(target)},
    )

    assert response.status_code == 200
    assert response.json()["output_path"] == str(target)
    assert opened == [target]


def test_compose_preview_returns_cleanup_patch_without_blocking_export(tmp_path: Path) -> None:
    response = client.post(
        "/compose-preview",
        json={
            "version": 2,
            "mode": "composer",
            "canvas_width_mm": 180,
            "canvas_height_mm": 170,
            "grid_mm": 0.5,
            "layout_grid": {
                "columns": 3,
                "rows": 3,
                "cell_width_mm": 60,
                "cell_height_mm": 55,
                "frame_x_mm": 0,
                "frame_y_mm": 2.5,
                "frame_width_mm": 180,
                "frame_height_mm": 165,
            },
            "regions": [],
            "panels": [],
            "texts": [
                {
                    "id": "text-1",
                    "text": "Hello",
                    "x_mm": 178,
                    "y_mm": 10,
                    "font_size_pt": 5,
                    "align": "left",
                    "z_index": 0,
                    "locked": False,
                    "hidden": False,
                    "group_id": None,
                    "region_id": None,
                    "slot_id": None,
                },
                {
                    "id": "text-2",
                    "text": "World",
                    "x_mm": 178,
                    "y_mm": 10,
                    "font_size_pt": 8,
                    "align": "left",
                    "z_index": 1,
                    "locked": False,
                    "hidden": False,
                    "group_id": None,
                    "region_id": None,
                    "slot_id": None,
                },
            ],
            "auto_labels": True,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["valid"] is True
    assert payload["validation_error"] is None
    assert payload["qa"]["issues"]
    assert payload["submission_report"]["context"] == "composer"
    assert payload["suggested_project_patch"]
    assert payload["suggested_project_patch"][0]["kind"] == "text"


def test_inspect_tensile_workbook_endpoint_returns_summary(tmp_path: Path) -> None:
    workbook_path = _write_tensile_workbook(tmp_path / "solid.xlsx")

    response = client.post(
        "/inspect-tensile-workbook",
        json={"workbook_path": str(workbook_path)},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["workbook_path"] == str(workbook_path)
    assert payload["label"] == "solid"
    assert payload["sample_count"] == 2
    assert payload["sheet_names"][0] == "Representative_Curve"


def test_inspect_file_recognizes_tensile_workbook_curve_sheet(tmp_path: Path) -> None:
    workbook_path = _write_tensile_workbook(tmp_path / "solid.xlsx")

    response = client.post(
        "/inspect-file",
        json={
            "input_path": str(workbook_path),
            "sheet": "Representative_Curve",
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["inspection"]["model"] == "tensile_curve"
    assert payload["inspection"]["recommendation"]["xscale"] == "linear"
    assert payload["inspection"]["recommendation"]["yscale"] == "linear"


def test_export_tensile_comparison_endpoint_returns_bundle_paths(tmp_path: Path) -> None:
    workbook_paths = [
        str(_write_tensile_workbook(tmp_path / "solid.xlsx")),
        str(_write_tensile_workbook(tmp_path / "4 mm.xlsx")),
        str(_write_tensile_workbook(tmp_path / "2 mm.xlsx")),
    ]

    response = client.post(
        "/export-tensile-comparison",
        json={
            "workbook_paths": workbook_paths,
            "output_dir": str(tmp_path / "exports"),
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert Path(payload["bundle_dir"]).exists()
    assert Path(payload["comparison_workbook_path"]).exists()
    assert payload["labels"] == ["solid", "4 mm", "2 mm"]
    assert len(payload["outputs"]) == 7
    assert all(Path(path).exists() for path in payload["outputs"])


def test_save_project_rejects_invalid_wizard_shape(tmp_path: Path) -> None:
    project_path = tmp_path / "wizard.plotproject.json"

    response = client.post(
        "/save-project",
        json={
            "project_path": str(project_path),
            "data": {
                "version": 1,
                "mode": "wizard",
                "wizard": {"input_path": 123},
            },
        },
    )

    assert response.status_code == 400
    assert "Invalid project file field" in response.json()["detail"]


def test_import_panels_returns_full_composer_project(tmp_path: Path) -> None:
    graph_path = _write_pdf(tmp_path / "double-wide.pdf", 120.0, 55.0)

    response = client.post(
        "/composer/import-panels",
        json={
            "project": {
                "version": 2,
                "mode": "composer",
                "canvas_width_mm": 180,
                "canvas_height_mm": 170,
                "grid_mm": 0.5,
                "layout_grid": {
                    "columns": 3,
                    "rows": 3,
                    "cell_width_mm": 60,
                    "cell_height_mm": 55,
                    "frame_x_mm": 0,
                    "frame_y_mm": 2.5,
                    "frame_width_mm": 180,
                    "frame_height_mm": 165,
                },
                "regions": [],
                "panels": [],
                "texts": [],
                "auto_labels": True,
            },
            "file_paths": [str(graph_path)],
            "kind": "graph",
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["version"] == 2
    assert len(payload["regions"]) == 1
    assert payload["regions"][0]["col_span"] == 2
    assert payload["panels"][0]["region_id"] == payload["regions"][0]["id"]
