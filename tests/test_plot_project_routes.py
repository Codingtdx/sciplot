from __future__ import annotations

import json
import zipfile
from pathlib import Path

import pandas as pd
from fastapi.testclient import TestClient

from app.sidecar.server import app
from src.core.application.render import build_rendered_plots, close_rendered_plots
from src.data_studio.builtin import tensile as tensile_builtin

client = TestClient(app)

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "tests" / "fixtures" / "tensile_raw"


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
                "palette_preset": "colorblind_safe",
                "visual_theme_id": "clean_light",
                "extra_x_axis": {
                    "enabled": True,
                    "position": "top",
                    "title": "Gallons",
                    "data_value": 3.78541,
                    "display_value": 1.0,
                },
                "extra_y_axis": {
                    "enabled": True,
                    "position": "right",
                    "title": "Half Stress",
                    "data_value": 2.0,
                    "display_value": 1.0,
                },
                "reference_guides": [
                    {
                        "id": "target-line",
                        "enabled": True,
                        "kind": "line",
                        "axis_target": "y_primary",
                        "value": 2.5,
                        "label": "Target",
                    },
                    {
                        "id": "window-region",
                        "enabled": True,
                        "kind": "band",
                        "axis_target": "x",
                        "start": 0.5,
                        "end": 1.5,
                        "label": "Window",
                    },
                ],
                "text_annotations": [
                    {
                        "id": "note-1",
                        "enabled": True,
                        "text": "Peak",
                        "coordinate_space": "data",
                        "x": 1.5,
                        "y": 3.2,
                        "y_axis_target": "y_primary",
                        "horizontal_alignment": "right",
                        "vertical_alignment": "bottom",
                        "display_style": "callout",
                        "connector_enabled": True,
                        "target_x": 1.0,
                        "target_y": 2.8,
                        "target_y_axis_target": "y_primary",
                    }
                ],
                "shape_annotations": [
                    {
                        "id": "focus-window",
                        "enabled": True,
                        "kind": "rectangle",
                        "bracket_orientation": "horizontal",
                        "x_start": 0.5,
                        "x_end": 1.5,
                        "y_start": 2.2,
                        "y_end": 3.4,
                        "y_axis_target": "y_primary",
                        "label": "Window",
                    }
                ],
            },
            "fit_options": {
                "enabled": True,
                "model_id": "polynomial_2",
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


def _build_data_studio_workbook(tmp_path: Path, name: str) -> tuple[Path, dict[str, object]]:
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
            "template_id": tensile_builtin.TENSILE_TEMPLATE_ID,
            "group_name": name,
        },
    )
    assert response.status_code == 200, response.text
    return output_path, response.json()


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
    assert payload["column_headers"] == ["X", "Y"]
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
        assert f"sources/plot/primary/{source_path.name}" in names

    source_path.unlink()

    open_response = client.post("/open-project", json={"project_path": str(project_path)})

    assert open_response.status_code == 200
    payload = open_response.json()
    assert payload["payload"]["plot"]["selected_template_id"] == "scatter_fit"
    assert payload["payload"]["plot"]["render_options"]["style_preset"] == "nature"
    assert payload["payload"]["plot"]["render_options"]["palette_preset"] == "colorblind_safe"
    assert payload["payload"]["plot"]["render_options"]["visual_theme_id"] == "clean_light"
    assert payload["payload"]["plot"]["render_options"]["extra_x_axis"] == {
        "enabled": True,
        "position": "top",
        "binding_mode": "conversion",
        "series_ids": [],
        "title": "Gallons",
        "display_unit": None,
        "data_value": 3.78541,
        "display_value": 1.0,
    }
    assert payload["payload"]["plot"]["render_options"]["extra_y_axis"] == {
        "enabled": True,
        "position": "right",
        "binding_mode": "conversion",
        "series_ids": [],
        "title": "Half Stress",
        "display_unit": None,
        "data_value": 2.0,
        "display_value": 1.0,
    }
    assert payload["payload"]["plot"]["render_options"]["reference_guides"] == [
        {
            "id": "target-line",
            "enabled": True,
            "kind": "line",
            "axis_target": "y_primary",
            "value": 2.5,
            "start": None,
            "end": None,
            "label": "Target",
        },
        {
            "id": "window-region",
            "enabled": True,
            "kind": "band",
            "axis_target": "x",
            "value": None,
            "start": 0.5,
            "end": 1.5,
            "label": "Window",
        },
    ]
    assert payload["payload"]["plot"]["render_options"]["text_annotations"] == [
        {
            "id": "note-1",
            "enabled": True,
            "text": "Peak",
            "coordinate_space": "data",
            "x": 1.5,
            "y": 3.2,
            "y_axis_target": "y_primary",
            "horizontal_alignment": "right",
            "vertical_alignment": "bottom",
            "display_style": "callout",
            "connector_enabled": True,
            "target_x": 1.0,
            "target_y": 2.8,
            "target_y_axis_target": "y_primary",
        }
    ]
    assert payload["payload"]["plot"]["render_options"]["shape_annotations"] == [
        {
            "id": "focus-window",
            "enabled": True,
            "kind": "rectangle",
            "bracket_orientation": "horizontal",
            "x_start": 0.5,
            "x_end": 1.5,
            "y_start": 2.2,
            "y_end": 3.4,
            "y_axis_target": "y_primary",
            "label": "Window",
        }
    ]
    assert payload["payload"]["plot"]["render_options"]["analytical_layers"] is None
    assert payload["payload"]["plot"]["render_options"]["data_transforms"] is None
    assert payload["payload"]["plot"]["fit_options"]["enabled"] is True
    assert payload["payload"]["plot"]["fit_options"]["model_id"] == "polynomial_2"
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
        source_bytes = archive.read(f"sources/plot/primary/{source_path.name}")
        manifest_bytes = archive.read("artifacts/manifest.json")

    project_json["plot"]["source_sha256"] = "deadbeef"
    with zipfile.ZipFile(project_path, mode="w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("project.json", json.dumps(project_json, ensure_ascii=False, indent=2))
        archive.writestr(f"sources/plot/primary/{source_path.name}", source_bytes)
        archive.writestr("artifacts/manifest.json", manifest_bytes)

    response = client.post("/open-project", json={"project_path": str(project_path)})

    assert response.status_code == 400
    assert "checksum" in response.json()["detail"].lower()


def test_save_open_project_roundtrip_preserves_extra_y_series_assignment(tmp_path: Path) -> None:
    source_path = tmp_path / "curve.csv"
    project_path = tmp_path / "curve-series-axis.sciplotgod"
    _curve_csv(source_path)

    payload = _project_payload(source_path)
    assert payload["plot"] is not None
    plot_payload = payload["plot"]
    assert isinstance(plot_payload, dict)
    plot_payload["selected_template_id"] = "scatter"
    render_options = plot_payload["render_options"]
    assert isinstance(render_options, dict)
    render_options["extra_y_axis"] = {
        "enabled": True,
        "position": "right",
        "binding_mode": "series_assignment",
        "series_ids": ["Sample B"],
        "title": "Secondary Stress",
        "data_value": 1.0,
        "display_value": 1.0,
    }

    save_response = client.post(
        "/save-project",
        json={
            "project_path": str(project_path),
            "source_path": str(source_path),
            "payload": payload,
        },
    )
    assert save_response.status_code == 200

    open_response = client.post("/open-project", json={"project_path": str(project_path)})
    assert open_response.status_code == 200
    restored_axis = open_response.json()["payload"]["plot"]["render_options"]["extra_y_axis"]
    assert restored_axis == {
        "enabled": True,
        "position": "right",
        "binding_mode": "series_assignment",
        "series_ids": ["Sample B"],
        "title": "Secondary Stress",
        "display_unit": None,
        "data_value": 1.0,
        "display_value": 1.0,
    }


def test_save_open_project_roundtrip_preserves_axis_breaks(tmp_path: Path) -> None:
    source_path = tmp_path / "curve.csv"
    project_path = tmp_path / "curve-axis-breaks.sciplotgod"
    _curve_csv(source_path)

    payload = _project_payload(source_path)
    assert payload["plot"] is not None
    plot_payload = payload["plot"]
    assert isinstance(plot_payload, dict)
    plot_payload["selected_template_id"] = "curve"
    render_options = plot_payload["render_options"]
    assert isinstance(render_options, dict)
    render_options.pop("extra_x_axis", None)
    render_options.pop("extra_y_axis", None)
    render_options["x_axis_breaks"] = [
        {
            "id": "x-gap",
            "enabled": True,
            "start": 0.8,
            "end": 1.2,
            "display_mode": "split",
        }
    ]
    render_options["y_axis_breaks"] = [
        {
            "id": "y-gap",
            "enabled": False,
            "start": 1.4,
            "end": 2.2,
            "display_mode": "compress",
        }
    ]

    save_response = client.post(
        "/save-project",
        json={
            "project_path": str(project_path),
            "source_path": str(source_path),
            "payload": payload,
        },
    )
    assert save_response.status_code == 200

    open_response = client.post("/open-project", json={"project_path": str(project_path)})
    assert open_response.status_code == 200
    render_options_payload = open_response.json()["payload"]["plot"]["render_options"]
    assert render_options_payload["x_axis_breaks"] == [
        {
            "id": "x-gap",
            "enabled": True,
            "start": 0.8,
            "end": 1.2,
            "display_mode": "split",
        }
    ]
    assert render_options_payload["y_axis_breaks"] == [
        {
            "id": "y-gap",
            "enabled": False,
            "start": 1.4,
            "end": 2.2,
            "display_mode": "compress",
        }
    ]


def test_save_open_project_roundtrip_preserves_analytical_layers(tmp_path: Path) -> None:
    source_path = tmp_path / "curve.csv"
    project_path = tmp_path / "curve-function.sciplotgod"
    _curve_csv(source_path)

    payload = _project_payload(source_path)
    plot_payload = payload["plot"]
    assert isinstance(plot_payload, dict)
    plot_payload["selected_template_id"] = "function_curve"
    render_options = plot_payload["render_options"]
    assert isinstance(render_options, dict)
    render_options["analytical_layers"] = [
        {
            "id": "function-1",
            "enabled": True,
            "kind": "function",
            "expression": "sin(x) + 1",
            "x_start": 0,
            "x_end": 3,
            "sample_count": 120,
            "y_axis_target": "y_primary",
            "label": "Model",
        }
    ]

    save_response = client.post(
        "/save-project",
        json={
            "project_path": str(project_path),
            "source_path": str(source_path),
            "payload": payload,
        },
    )
    assert save_response.status_code == 200

    open_response = client.post("/open-project", json={"project_path": str(project_path)})
    assert open_response.status_code == 200
    assert open_response.json()["payload"]["plot"]["render_options"]["analytical_layers"] == [
        {
            "id": "function-1",
            "enabled": True,
            "kind": "function",
            "expression": "sin(x) + 1",
            "x_start": 0.0,
            "x_end": 3.0,
            "sample_count": 120,
            "y_axis_target": "y_primary",
            "label": "Model",
        }
    ]


def test_save_open_project_roundtrip_preserves_data_transforms(tmp_path: Path) -> None:
    source_path = tmp_path / "curve.csv"
    project_path = tmp_path / "curve-transform.sciplotgod"
    _curve_csv(source_path)

    payload = _project_payload(source_path)
    plot_payload = payload["plot"]
    assert isinstance(plot_payload, dict)
    render_options = plot_payload["render_options"]
    assert isinstance(render_options, dict)
    render_options["data_transforms"] = [
        {
            "id": "filter-window",
            "enabled": True,
            "kind": "row_filter",
            "label": "Window",
            "column": "X",
            "operator": "between",
            "lower": 1.0,
            "upper": 2.0,
        },
        {
            "id": "double-y",
            "enabled": True,
            "kind": "derived_column",
            "target_column": "Y",
            "expression": "Y * 2",
        },
    ]

    save_response = client.post(
        "/save-project",
        json={
            "project_path": str(project_path),
            "source_path": str(source_path),
            "payload": payload,
        },
    )
    assert save_response.status_code == 200

    open_response = client.post("/open-project", json={"project_path": str(project_path)})
    assert open_response.status_code == 200
    assert open_response.json()["payload"]["plot"]["render_options"]["data_transforms"] == [
        {
            "id": "filter-window",
            "enabled": True,
            "kind": "row_filter",
            "label": "Window",
            "target_column": None,
            "expression": None,
            "column": "X",
            "operator": "between",
            "value": None,
            "lower": 1.0,
            "upper": 2.0,
            "x_column": None,
            "y_column": None,
            "z_column": None,
            "output_mode": "xyz_long",
        },
        {
            "id": "double-y",
            "enabled": True,
            "kind": "derived_column",
            "label": None,
            "target_column": "Y",
            "expression": "Y * 2",
            "column": None,
            "operator": "eq",
            "value": None,
            "lower": None,
            "upper": None,
            "x_column": None,
            "y_column": None,
            "z_column": None,
            "output_mode": "xyz_long",
        },
    ]


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


def test_save_open_data_studio_project_roundtrip_restores_embedded_workbook(tmp_path: Path) -> None:
    workbook_path, workbook_payload = _build_data_studio_workbook(tmp_path, "Roundtrip Group")
    imported_source = FIXTURE_DIR / "BlendSet_A.csv"
    project_path = tmp_path / "roundtrip-data-studio.sciplotgod"

    save_response = client.post(
        "/save-project",
        json={
            "project_path": str(project_path),
            "source_path": None,
            "payload": {
                "version": 1,
                "selected_workbench": "data_studio",
                "plot": None,
                "data_studio": {
                    "session_kind": "data_studio",
                    "version": 1,
                    "selected_template_id": tensile_builtin.TENSILE_TEMPLATE_ID,
                    "workbook_paths": [str(workbook_path)],
                    "selected_workbook_id": workbook_payload["workbook_id"],
                    "primary_workbook_id": workbook_payload["workbook_id"],
                    "selected_recipe_id": "representative_scatter",
                    "comparison_recipe_ids": ["representative_curve", "representative_scatter"],
                    "selected_figure_family_id": "representative_curve",
                    "selected_figure_template_id": "scatter",
                    "group_states": [
                        {
                            "workbook_path": str(workbook_path),
                            "display_name": "Roundtrip Group",
                            "include_in_compare": True,
                            "sort_order": 0,
                        }
                    ],
                    "specimen_states": [],
                    "figure_preferences": [
                        {
                            "family_id": "representative_curve",
                            "selected_template_id": "scatter",
                            "options_by_template": {
                                "scatter": {
                                    "style_preset": "nature",
                                    "palette_preset": "colorblind_safe",
                                    "visual_theme_id": "clean_light",
                                }
                            },
                            "fit_options_by_template": {
                                "scatter": {
                                    "enabled": True,
                                    "model_id": "polynomial_2",
                                }
                            },
                        }
                    ],
                    "imported_paths": [str(imported_source)],
                    "template_draft_path": str(imported_source),
                    "embedded_workbooks": [],
                    "project_display_name": "Roundtrip Data Studio",
                    "source_provenance": {},
                },
                "composer": None,
                "code_console": None,
                "artifacts": {},
            },
        },
    )

    assert save_response.status_code == 200, save_response.text
    workbook_path.unlink()

    open_response = client.post("/open-project", json={"project_path": str(project_path)})

    assert open_response.status_code == 200, open_response.text
    payload = open_response.json()
    assert payload["payload"]["selected_workbench"] == "data_studio"
    restored_workbook_path = Path(payload["restored_workbook_paths"][0])
    assert restored_workbook_path.exists()
    assert payload["payload"]["data_studio"]["workbook_paths"] == [str(restored_workbook_path)]
    assert payload["payload"]["data_studio"]["selected_recipe_id"] == "representative_scatter"
    figure_preference = payload["payload"]["data_studio"]["figure_preferences"][0]
    assert figure_preference["selected_template_id"] == "scatter"
    assert figure_preference["fit_options_by_template"]["scatter"]["model_id"] == "polynomial_2"
