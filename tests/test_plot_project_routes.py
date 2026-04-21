from __future__ import annotations

import json
import zipfile
from pathlib import Path

import pandas as pd
from fastapi.testclient import TestClient

from app.sidecar.server import app
from src.core.application.render import build_rendered_plots, close_rendered_plots

client = TestClient(app)


def _curve_csv(path: Path) -> None:
    pd.DataFrame(
        [
            ["X", "Y"],
            ["s", "MPa"],
            ["Sample A", "Sample A"],
            [0.0, 1.0],
            [1.0, 3.0],
            [2.0, 5.0],
            [3.0, 7.0],
        ]
    ).to_csv(path, header=False, index=False)


def _project_payload(source_path: Path) -> dict[str, object]:
    return {
        "version": 1,
        "selected_workbench": "plot",
        "plot": {
            "session_kind": "plot",
            "source_filename": source_path.name,
            "source_media_type": "text/csv",
            "embedded_source_relpath": f"sources/primary/{source_path.name}",
            "source_sha256": "",
            "sheet": 0,
            "selected_template_id": "scatter_with_fit",
            "render_options": {
                "style_preset": "default",
                "palette_preset": "roma",
                "visual_theme_id": "roma",
            },
            "project_display_name": "Curve Study",
            "source_provenance": {
                "original_input_path": str(source_path),
            },
        },
        "data_studio": None,
        "composer": None,
        "code_console": None,
        "artifacts": {},
    }


def test_source_table_preview_returns_headers_and_rows(tmp_path: Path) -> None:
    source_path = tmp_path / "curve.csv"
    _curve_csv(source_path)

    response = client.post(
        "/source-table-preview",
        json={
            "input_path": str(source_path),
            "sheet": 0,
            "offset": 3,
            "limit": 2,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["total_rows"] == 7
    assert payload["total_cols"] == 2
    assert payload["column_headers"] == ["X | s | Sample A", "Y | MPa | Sample A"]
    assert payload["rows"] == [["0.0", "1.0"], ["1.0", "3.0"]]
    assert payload["candidate_roles"]["x"]
    assert payload["candidate_roles"]["y"]


def test_save_open_project_roundtrip_embeds_source_and_restores_after_source_delete(tmp_path: Path) -> None:
    source_path = tmp_path / "curve.csv"
    project_path = tmp_path / "curve.sciplotgod"
    _curve_csv(source_path)
    original_bytes = source_path.read_bytes()

    save_response = client.post(
        "/save-project",
        json={
            "project_path": str(project_path),
            "source_path": str(source_path),
            "payload": _project_payload(source_path),
        },
    )

    assert save_response.status_code == 200
    assert project_path.exists()
    with zipfile.ZipFile(project_path) as archive:
        names = set(archive.namelist())
        assert "project.json" in names
        assert "artifacts/manifest.json" in names
        assert f"sources/primary/{source_path.name}" in names

    source_path.unlink()

    open_response = client.post("/open-project", json={"project_path": str(project_path)})

    assert open_response.status_code == 200
    payload = open_response.json()
    assert payload["payload"]["plot"]["selected_template_id"] == "scatter_fit"
    assert payload["payload"]["plot"]["render_options"]["style_preset"] == "nature"
    restored_source_path = Path(payload["restored_source_path"])
    assert restored_source_path.exists()
    assert restored_source_path.read_bytes() == original_bytes


def test_open_project_reports_checksum_mismatch(tmp_path: Path) -> None:
    source_path = tmp_path / "curve.csv"
    project_path = tmp_path / "curve.sciplotgod"
    _curve_csv(source_path)

    save_response = client.post(
        "/save-project",
        json={
            "project_path": str(project_path),
            "source_path": str(source_path),
            "payload": _project_payload(source_path),
        },
    )
    assert save_response.status_code == 200

    with zipfile.ZipFile(project_path) as archive:
        project_json = json.loads(archive.read("project.json").decode("utf-8"))
        source_bytes = archive.read(f"sources/primary/{source_path.name}")
        manifest_bytes = archive.read("artifacts/manifest.json")

    project_json["plot"]["source_sha256"] = "deadbeef"
    with zipfile.ZipFile(project_path, mode="w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("project.json", json.dumps(project_json, ensure_ascii=False, indent=2))
        archive.writestr(f"sources/primary/{source_path.name}", source_bytes)
        archive.writestr("artifacts/manifest.json", manifest_bytes)

    response = client.post("/open-project", json={"project_path": str(project_path)})

    assert response.status_code == 400
    assert "checksum" in response.json()["detail"].lower()


def test_fit_analysis_matches_scatter_fit_equation_label(tmp_path: Path) -> None:
    source_path = tmp_path / "curve.csv"
    _curve_csv(source_path)

    response = client.post(
        "/fit-analysis",
        json={
            "input_path": str(source_path),
            "sheet": 0,
            "model_id": "linear",
            "offset": 0,
            "limit": 10,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["point_count"] == 4
    equation_display = payload["equation_display"]

    rendered_plots = build_rendered_plots(
        "scatter_fit",
        source_path,
        0,
        style_preset="nature",
        palette_preset="roma",
        visual_theme_id="roma",
    )
    try:
        labels = [
            line.get_label()
            for line in rendered_plots[0].figure.axes[0].lines
            if isinstance(line.get_label(), str)
        ]
    finally:
        close_rendered_plots(rendered_plots)

    assert f"fit: {equation_display}" in labels
