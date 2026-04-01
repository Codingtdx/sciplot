from __future__ import annotations

from pathlib import Path

from fastapi.testclient import TestClient

from app.sidecar.server import app

client = TestClient(app)

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "tests" / "fixtures" / "tensile_raw"


def _build_workbook(tmp_path: Path, name: str) -> Path:
    output_path = tmp_path / f"{name}.xlsx"
    response = client.post(
        "/data-studio/build-workbook",
        json={
            "file_paths": [
                str(FIXTURE_DIR / "BlendSet_A.csv"),
                str(FIXTURE_DIR / "BlendSet_B.csv"),
                str(FIXTURE_DIR / "BlendSet_bad.csv"),
            ],
            "output_path": str(output_path),
            "template_id": "builtin/tensile",
            "group_name": name,
        },
    )
    assert response.status_code == 200, response.text
    assert output_path.exists()
    return output_path


def test_data_studio_template_routes_and_source_preview_stay_live(tmp_path: Path) -> None:
    templates = client.get("/data-studio/templates")
    assert templates.status_code == 200
    template_payload = templates.json()
    assert any(item["id"] == "builtin/tensile" for item in template_payload["templates"])

    source_preview = client.post(
        "/data-studio/source-preview",
        json={"input_path": str(FIXTURE_DIR / "BlendSet_A.csv")},
    )
    assert source_preview.status_code == 200, source_preview.text
    payload = source_preview.json()
    assert payload["preview"]["file_type"] == "csv"
    assert any(candidate["kind"] == "curve_x" for candidate in payload["preview"]["field_candidates"])
    assert payload["matches"][0]["template_id"] == "builtin/tensile"

    normalize = client.post(
        "/data-studio/session/normalize",
        json={
            "payload": {
                "selected_template_id": "builtin/tensile",
                "workbook_paths": [str(tmp_path / "a.xlsx")],
                "comparison_recipe_ids": ["representative_curve"],
                "imported_paths": [str(FIXTURE_DIR / "BlendSet_A.csv")],
            }
        },
    )
    assert normalize.status_code == 200, normalize.text
    assert normalize.json()["selected_template_id"] == "builtin/tensile"


def test_data_studio_workbook_import_preview_and_export_routes_work_end_to_end(tmp_path: Path) -> None:
    left = _build_workbook(tmp_path, "Left Group")
    right = _build_workbook(tmp_path, "Right Group")

    imported = client.post("/data-studio/import-workbook", json={"workbook_path": str(left)})
    assert imported.status_code == 200, imported.text
    assert imported.json()["label"] == "Left Group"

    preview = client.post(
        "/data-studio/comparison-preview",
        json={
            "workbook_paths": [str(left), str(right)],
            "recipe_id": "representative_curve",
        },
    )
    assert preview.status_code == 200, preview.text
    preview_payload = preview.json()
    assert preview_payload["recipe"]["id"] == "representative_curve"
    assert preview_payload["preview"]["pdf_base64"]

    export_dir = tmp_path / "exports"
    exported = client.post(
        "/data-studio/comparison-export",
        json={
            "workbook_paths": [str(left), str(right)],
            "output_dir": str(export_dir),
            "selected_recipe_ids": ["representative_curve", "strength_box"],
        },
    )
    assert exported.status_code == 200, exported.text
    exported_payload = exported.json()
    assert exported_payload["comparison_set"]["comparison_workbook_path"]
    assert {item["recipe_id"] for item in exported_payload["figure_outputs"]} == {
        "representative_curve",
        "strength_box",
    }
