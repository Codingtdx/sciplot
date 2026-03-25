from __future__ import annotations

import json
from pathlib import Path

import fitz
import pandas as pd
import pytest
from fastapi.testclient import TestClient

import src.rendering.data_templates as data_templates_module
from app.sidecar import server
from app.sidecar.server import app
from src.rendering import code_console as code_console_module
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


def _write_replicate_table(path: Path) -> Path:
    rows = [
        ["Tensile modulus", "", ""],
        ["Blend A", "Blend B", "Blend C"],
        ["MPa", "MPa", "MPa"],
        [510.13, 567.91, 544.10],
        [501.10, 501.49, 549.54],
        [549.61, 549.61, 562.07],
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


def _managed_storage_snapshot(base: Path) -> dict[str, object]:
    return {
        "root_path": str(base),
        "data_root": str(base / "data"),
        "cache_root": str(base / "cache"),
        "example_templates_path": str(base / "data" / "templates" / "folders" / "example"),
        "blank_templates_path": str(base / "data" / "templates" / "folders" / "blank"),
        "single_example_templates_path": str(base / "data" / "templates" / "single" / "example"),
        "single_blank_templates_path": str(base / "data" / "templates" / "single" / "blank"),
        "plot_exports_path": str(base / "data" / "plot_exports"),
        "code_console_runs_path": str(base / "cache" / "code_console" / "runs"),
        "example_template_file_count": 4,
        "blank_template_file_count": 4,
        "single_template_file_count": 2,
        "plot_export_dir_count": 3,
        "code_console_run_dir_count": 2,
    }


def _use_managed_template_roots(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    def folder_root(variant: str) -> Path:
        path = tmp_path / "managed_templates" / "folders" / variant
        path.mkdir(parents=True, exist_ok=True)
        return path

    def single_root(variant: str) -> Path:
        path = tmp_path / "managed_templates" / "single" / variant
        path.mkdir(parents=True, exist_ok=True)
        return path

    monkeypatch.setattr(data_templates_module, "managed_template_folder_path", folder_root)
    monkeypatch.setattr(data_templates_module, "managed_single_template_root", single_root)


def _use_managed_run_root(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    counter = {"value": 0}

    def create_run_dir(_session: dict[str, object]) -> Path:
        counter["value"] += 1
        path = tmp_path / "managed_runs" / f"run-{counter['value']}"
        path.mkdir(parents=True, exist_ok=True)
        return path

    monkeypatch.setattr(code_console_module, "create_managed_code_console_run_dir", create_run_dir)


def test_meta_endpoint_returns_contract_backed_payload() -> None:
    response = client.get("/meta")

    assert response.status_code == 200
    payload = response.json()
    assert payload["template_ids"]
    assert payload["size_ids"]
    assert payload["palette_preset_ids"]
    assert payload["visual_themes"]
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


def test_openapi_exposes_required_template_folder_route() -> None:
    response = client.get("/openapi.json")

    assert response.status_code == 200
    payload = response.json()
    assert "get" in payload["paths"]["/meta"]
    assert "get" in payload["paths"]["/plot-contract"]
    assert "post" in payload["paths"]["/data-templates/folder"]


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
    assert len(payload["inspection"]["recommendations"]) == 5
    assert payload["inspection"]["recommendations"][0]["template_id"] == "curve"
    assert payload["inspection"]["recommendations"][0]["rank"] == 1
    assert payload["inspection"]["recommendations"][0]["reason"]
    assert payload["inspection"]["recommendations"][0]["suitability_hint"]
    assert payload["inspection"]["recommendations"][0]["score_gap_to_top"] == 0.0
    assert payload["inspection"]["recommendations"][1]["template_id"] == "point_line"
    assert payload["inspection"]["recommendation_confidence"] >= payload["inspection"]["recommendations"][0]["score"]
    assert "curve" in payload["inspection"]["recommendation_summary"]


def test_inspect_file_replicate_model_keeps_legacy_recommendation_field(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicate.csv")

    response = client.post(
        "/inspect-file",
        json={"input_path": str(input_path), "sheet": 0},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["inspection"]["model"] == "replicate_table"
    assert payload["inspection"]["recommendation"]["template"] == "box"
    template_ids = [item["template_id"] for item in payload["inspection"]["recommendations"]]
    assert template_ids[0] == "box"
    assert "distribution_compare" in template_ids
    assert "grouped_bar_compare" in template_ids


def test_code_console_generate_returns_lightweight_context_without_bound_data() -> None:
    response = client.post(
        "/code-console/generate",
        json={
            "intent": "custom_plot",
            "brief": "实现一个带 broken axis 的特殊曲线图。",
            "base_template": "curve",
            "size": "60x55",
            "style_preset": "default",
            "palette_preset": "colorblind_safe",
            "target_path": "src/rendering/custom_curve_helper.py",
            "include_data_context": True,
            "include_inspection_summary": True,
            "include_project_context": False,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["session"]["input_path"] is None
    assert payload["data_context"]["available"] is False
    assert payload["lightweight_bundle"]["includes_full_data"] is False
    assert "not a standalone matplotlib demo" in payload["prompt_text"]
    assert any(
        source["id"] == "plot_contract" and "canonical plotting contract" in source["reason"]
        for source in payload["truth_sources"]
    )


def test_code_console_export_bundle_writes_manifest_and_full_data_artifacts(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")
    project_path = tmp_path / "wizard.plotproject.json"
    project_payload = {
        "version": 1,
        "mode": "wizard",
        "wizard": {
            "input_path": str(input_path),
            "sheet": 0,
            "template": "curve",
            "options": {
                "size": "60x55",
                "style_preset": "default",
                "palette_preset": "colorblind_safe",
            },
            "outputs": [],
        },
    }
    project_path.write_text(
        json.dumps(project_payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    response = client.post(
        "/code-console/export-bundle",
        json={
            "intent": "custom_plot",
            "brief": "实现一个 repo-native 的特殊曲线图 helper。",
            "base_template": "curve",
            "size": "60x55",
            "style_preset": "default",
            "palette_preset": "colorblind_safe",
            "target_path": "src/rendering/custom_curve_helper.py",
            "input_path": str(input_path),
            "sheet": 0,
            "project_path": str(project_path),
            "include_data_context": True,
            "include_inspection_summary": True,
            "include_project_context": True,
            "output_dir": str(tmp_path / "ai-bundles"),
            "include_full_data": True,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    bundle_dir = Path(payload["bundle_dir"])
    manifest_path = Path(payload["manifest_path"])
    zip_path = Path(payload["zip_path"])

    assert payload["includes_full_data"] is True
    assert bundle_dir.exists()
    assert manifest_path.exists()
    assert zip_path.exists()
    assert (bundle_dir / "normalized_full_data.csv").exists()
    assert (bundle_dir / "normalized_full_data.json").exists()
    assert (bundle_dir / "data_sample.csv").exists()
    assert (bundle_dir / "ai_prompt.txt").exists()
    assert (bundle_dir / "starter_scaffold.py").exists()

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    assert manifest["bundle_version"] == 1
    assert manifest["generated_at"]
    assert manifest["session"]["id"].startswith("session_")
    assert manifest["project"]["id"].startswith("project_")
    assert manifest["project"]["path"] == str(project_path)
    assert manifest["contract"]["version"] >= 1
    assert len(manifest["contract"]["sha256"]) == 64
    assert manifest["includes_full_data"] is True
    assert any(
        source["id"] == "generated_bundle" and "canonical package" in source["reason"]
        for source in payload["truth_sources"]
    )


def test_data_template_catalog_and_materialize_flow(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _use_managed_template_roots(monkeypatch, tmp_path)
    response = client.get("/data-templates")

    assert response.status_code == 200
    payload = response.json()
    template_ids = {item["chart_type"] for item in payload["templates"]}
    assert {
        "curve",
        "point_line",
        "scatter",
        "stacked_curve",
        "segmented_stacked_curve",
        "bar",
        "boxplot",
        "violin",
        "heatmap",
    }.issubset(template_ids)

    materialized = client.post(
        "/data-templates/materialize",
        json={"template_id": "curve_table", "variant": "blank"},
    )

    assert materialized.status_code == 200
    template_payload = materialized.json()
    template_path = Path(template_payload["file_path"])
    assert template_payload["variant"] == "blank"
    assert template_payload["sheet_name"] == "Template"
    assert template_path.exists()

    workbook = pd.ExcelFile(template_path)
    assert workbook.sheet_names == ["Template", "README"]
    template_sheet = workbook.parse("Template", header=None)
    assert template_sheet.iloc[0, 0] == "X label"
    assert template_sheet.iloc[2, 0] == "Sample 1"


def test_data_template_folder_materializes_chart_type_files(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _use_managed_template_roots(monkeypatch, tmp_path)
    response = client.post(
        "/data-templates/folder",
        json={"variant": "example"},
    )

    assert response.status_code == 200
    payload = response.json()
    folder_path = Path(payload["folder_path"])
    assert payload["variant"] == "example"
    assert folder_path.exists()
    assert folder_path.is_dir()
    filenames = {item["filename"] for item in payload["files"]}
    assert {
        "curve_example.xlsx",
        "point_line_example.xlsx",
        "scatter_example.xlsx",
        "stacked_curve_example.xlsx",
        "segmented_stacked_curve_example.xlsx",
        "bar_example.xlsx",
        "boxplot_example.xlsx",
        "violin_example.xlsx",
        "heatmap_example.xlsx",
    }.issubset(filenames)
    assert all(Path(item["file_path"]).parent == folder_path for item in payload["files"])

    curve_example = next(
        Path(item["file_path"])
        for item in payload["files"]
        if item["filename"] == "curve_example.xlsx"
    )
    workbook = pd.ExcelFile(curve_example)
    assert workbook.sheet_names == ["Template", "README"]
    workbook.close()

    blank_response = client.post(
        "/data-templates/folder",
        json={"variant": "blank"},
    )

    assert blank_response.status_code == 200
    blank_payload = blank_response.json()
    blank_folder_path = Path(blank_payload["folder_path"])
    assert blank_folder_path.exists()
    assert all(Path(item["file_path"]).exists() for item in blank_payload["files"])

    boxplot_blank = next(
        Path(item["file_path"])
        for item in blank_payload["files"]
        if item["filename"] == "boxplot_blank.xlsx"
    )
    blank_workbook = pd.ExcelFile(boxplot_blank)
    assert blank_workbook.sheet_names == ["Template", "README"]
    blank_workbook.close()


def test_data_template_folder_surfaces_materialize_validation_errors(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def broken_materialize(*, variant: str) -> dict[str, object]:
        raise FileNotFoundError(f"Template file generation failed: {variant}")

    monkeypatch.setattr(server, "materialize_data_template_folder", broken_materialize)

    response = client.post(
        "/data-templates/folder",
        json={"variant": "example"},
    )

    assert response.status_code == 400
    assert "Template file generation failed: example" in response.json()["detail"]


def test_code_console_runner_returns_generated_files_and_preview(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _use_managed_run_root(monkeypatch, tmp_path)
    input_path = _write_curve_table(tmp_path / "curve.csv")

    response = client.post(
        "/code-console/run",
        json={
            "code": "\n".join(
                [
                    "from pathlib import Path",
                    "import matplotlib.pyplot as plt",
                    "print(INPUT_PATH.name)",
                    "Path(output_path('notes.txt')).write_text('runner ok', encoding='utf-8')",
                    "fig, ax = plt.subplots()",
                    "ax.plot([0, 1], [0, 1])",
                    "fig.savefig(output_path('runner_preview.png'))",
                    "plt.close(fig)",
                ]
            ),
            "base_template": "curve",
            "options": {
                "size": "60x55",
                "style_preset": "default",
                "palette_preset": "colorblind_safe",
            },
            "input_path": str(input_path),
            "sheet": 0,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["exit_code"] == 0
    assert payload["timed_out"] is False
    assert payload["duration_ms"] >= 0
    assert payload["stdout"].strip() == "curve.csv"
    assert payload["stderr"] == ""
    assert Path(payload["output_dir"]).exists()
    assert all(
        Path(item["path"]).is_relative_to(Path(payload["output_dir"]))
        for item in payload["generated_files"]
    )
    assert {item["filename"] for item in payload["generated_files"]} == {
        "notes.txt",
        "runner_preview.png",
    }
    assert payload["previews"]
    assert payload["previews"][0]["filename"] == "runner_preview.png"


def test_code_console_runner_times_out(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    _use_managed_run_root(monkeypatch, tmp_path)
    input_path = _write_curve_table(tmp_path / "curve.csv")
    monkeypatch.setattr(code_console_module, "CODE_CONSOLE_RUN_TIMEOUT_SECONDS", 1)

    response = client.post(
        "/code-console/run",
        json={
            "code": "import time\ntime.sleep(2)",
            "base_template": "curve",
            "options": {
                "size": "60x55",
                "style_preset": "default",
                "palette_preset": "colorblind_safe",
            },
            "input_path": str(input_path),
            "sheet": 0,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["exit_code"] == 124
    assert payload["timed_out"] is True
    assert "timed out after 1 seconds" in payload["stderr"]
    assert payload["generated_files"] == []


def test_managed_storage_status_endpoint_returns_snapshot(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    snapshot = _managed_storage_snapshot(tmp_path / "managed")
    monkeypatch.setattr(server, "managed_storage_snapshot", lambda: snapshot)

    response = client.get("/managed-storage")

    assert response.status_code == 200
    payload = response.json()
    assert payload["data_root"] == snapshot["data_root"]
    assert payload["plot_export_dir_count"] == 3


def test_managed_storage_cleanup_endpoint_returns_cleanup_summary(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    snapshot = _managed_storage_snapshot(tmp_path / "managed")

    def cleanup(*, strategy: str = "all") -> dict[str, object]:
        return {
            **snapshot,
            "strategy": strategy,
            "removed_files": 7,
            "removed_directories": 2,
        }

    monkeypatch.setattr(server, "cleanup_managed_storage", cleanup)

    response = client.post("/managed-storage/cleanup", json={"strategy": "stale"})

    assert response.status_code == 200
    payload = response.json()
    assert payload["strategy"] == "stale"
    assert payload["removed_files"] == 7
    assert payload["removed_directories"] == 2


def test_export_render_uses_managed_storage_when_output_dir_missing(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")
    managed_output_dir = tmp_path / "managed_exports" / "curve_sheet1"

    monkeypatch.setattr(
        server,
        "prepare_managed_plot_export_dir",
        lambda _input_path, *, sheet, template: managed_output_dir,
    )

    response = client.post(
        "/export-render",
        json={
            "input_path": str(input_path),
            "sheet": 0,
            "template": "curve",
            "options": {
                "size": "60x55",
                "style_preset": "nature",
                "palette_preset": "colorblind_safe",
            },
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["output_dir"] == str(managed_output_dir)
    assert Path(payload["output_dir"]).exists()
    assert all(Path(path).exists() for path in payload["artifact_paths"])


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
                "visual_theme_id": "soft_grid",
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
    assert reopened["wizard"]["options"]["visual_theme_id"] == "soft_grid"


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
    manifest_path = Path(payload["manifest_path"])
    assert manifest_path.exists()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    assert manifest["bundle_version"] == 2
    assert manifest["generated_at"]
    assert manifest["template_layer"]["id"] == "curve"
    assert manifest["mapping_layer"]["selected_template"] == "curve"
    assert manifest["theme_layer"]["style_preset"] == "nature"
    assert manifest["theme_layer"]["palette_preset"] == "colorblind_safe"
    assert manifest["theme_layer"]["publication_profile_id"] == "nature"
    assert manifest["contract_layer"]["version"] >= 1
    assert len(manifest["contract_layer"]["sha256"]) == 64
    reproducibility = manifest["reproducibility"]
    assert len(reproducibility["run_fingerprint"]) == 64
    assert len(reproducibility["input"]["sha256"]) == 64
    assert reproducibility["outputs"]
    assert reproducibility["preview_outputs"]


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
