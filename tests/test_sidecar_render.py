from __future__ import annotations

import json
from base64 import b64decode
from pathlib import Path

import pandas as pd
from fastapi.testclient import TestClient

from app.sidecar import routes_render
from app.sidecar.server import app

client = TestClient(app)


def _make_curve_csv(path: Path) -> None:
    pd.DataFrame(
        [
            ["Time", "Stress", "Time", "Stress"],
            ["s", "MPa", "s", "MPa"],
            ["Sample A", "Sample A", "Sample B", "Sample B"],
            [0, 1.0, 0, 2.0],
            [1, 1.2, 1, 2.3],
            [2, 1.5, 2, 2.7],
        ]
    ).to_csv(path, header=False, index=False)


def _make_xyz_csv(path: Path) -> None:
    pd.DataFrame(
        [
            ["X", "Y", "Z"],
            ["Temperature", "Time", "Intensity"],
            ["degC", "min", "a.u."],
            [25.0, 0.0, 0.18],
            [25.0, 5.0, 0.31],
            [40.0, 0.0, 0.46],
            [40.0, 5.0, 0.63],
        ]
    ).to_csv(path, header=False, index=False)


def test_render_preview_uses_cache_and_invalidates_when_options_change(
    tmp_path: Path,
    monkeypatch,
) -> None:
    routes_render._RENDER_PREVIEW_CACHE.clear()  # noqa: SLF001
    input_path = tmp_path / "curve.csv"
    _make_curve_csv(input_path)

    base_request = {
        "input_path": str(input_path),
        "sheet": 0,
        "template": "curve",
    }
    first = client.post("/render-preview", json=base_request)
    assert first.status_code == 200, first.text
    first_payload = first.json()

    def fail_render(*args, **kwargs):
        raise AssertionError("cache hit should skip build_rendered_plots_from_options")

    monkeypatch.setattr("app.sidecar.routes_render.build_rendered_plots_from_options", fail_render)

    cached = client.post("/render-preview", json=base_request)
    assert cached.status_code == 200, cached.text
    assert cached.json()["submission_report"] == first_payload["submission_report"]

    invalidated = client.post(
        "/render-preview",
        json={
            **base_request,
            "options": {"x_tick_edge_labels": "hide_min"},
        },
    )
    assert invalidated.status_code == 400


def test_render_preview_accepts_analytical_function_layers(tmp_path: Path) -> None:
    input_path = tmp_path / "curve.csv"
    _make_curve_csv(input_path)

    response = client.post(
        "/render-preview",
        json={
            "input_path": str(input_path),
            "sheet": 0,
            "template": "function_curve",
            "options": {
                "analytical_layers": [
                    {
                        "id": "overlay",
                        "kind": "function",
                        "expression": "x * 0.5 + 1",
                        "x_start": 0,
                        "x_end": 2,
                        "sample_count": 40,
                        "label": "overlay",
                    }
                ]
            },
        },
    )

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["preview"]["filename"] == "curve_function_curve.pdf"
    assert payload["submission_report"]["template"] == "function_curve"


def test_render_preview_returns_png_live_preview_payload(tmp_path: Path) -> None:
    input_path = tmp_path / "curve.csv"
    _make_curve_csv(input_path)

    response = client.post(
        "/render-preview",
        json={
            "input_path": str(input_path),
            "sheet": 0,
            "template": "curve",
        },
    )

    assert response.status_code == 200, response.text
    preview = response.json()["preview"]
    assert preview["pdf_base64"]
    png_bytes = b64decode(preview["png_base64"])
    assert png_bytes.startswith(b"\x89PNG\r\n\x1a\n")


def test_source_table_preview_marks_xyz_scalar_roles(tmp_path: Path) -> None:
    input_path = tmp_path / "field.csv"
    _make_xyz_csv(input_path)

    response = client.post("/source-table-preview", json={"input_path": str(input_path), "sheet": 0})

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["candidate_roles"]["x"] == ["Temperature"]
    assert payload["candidate_roles"]["y"] == ["Time"]
    assert payload["candidate_roles"]["z"] == ["Intensity"]


def test_source_table_preview_accepts_data_transforms(tmp_path: Path) -> None:
    input_path = tmp_path / "table.csv"
    pd.DataFrame(
        [
            ["x", "y"],
            [3.0, 4.0],
            [5.0, 12.0],
        ]
    ).to_csv(input_path, header=False, index=False)

    response = client.post(
        "/source-table-preview",
        json={
            "input_path": str(input_path),
            "sheet": 0,
            "options": {
                "data_transforms": [
                    {
                        "id": "radius",
                        "kind": "derived_column",
                        "target_column": "radius",
                        "expression": "sqrt(x*x + y*y)",
                    }
                ]
            },
        },
    )

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["column_headers"] == ["x", "y", "radius"]
    assert payload["rows"][1] == ["3.0", "4.0", 5.0]


def test_fit_analysis_accepts_data_transforms(tmp_path: Path) -> None:
    input_path = tmp_path / "curve.csv"
    _make_curve_csv(input_path)

    response = client.post(
        "/fit-analysis",
        json={
            "input_path": str(input_path),
            "sheet": 0,
            "model_id": "linear",
            "options": {
                "data_transforms": [
                    {
                        "id": "window",
                        "kind": "row_filter",
                        "column": "Time",
                        "operator": "between",
                        "lower": 1.0,
                        "upper": 2.0,
                    }
                ]
            },
        },
    )

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["point_count"] == 2


def test_inspect_file_accepts_transform_options_for_recommendation(tmp_path: Path) -> None:
    input_path = tmp_path / "polar_from_xy.csv"
    pd.DataFrame([["x", "y"], [1, 0], [0, 1], [-1, 0]]).to_csv(input_path, header=False, index=False)

    response = client.post(
        "/inspect-file",
        json={
            "input_path": str(input_path),
            "options": {
                "data_transforms": [
                    {
                        "id": "theta",
                        "kind": "derived_column",
                        "target_column": "theta",
                        "expression": "atan2(col('y'), col('x'))",
                    },
                    {
                        "id": "radius",
                        "kind": "derived_column",
                        "target_column": "radius",
                        "expression": "sqrt(col('x')*col('x') + col('y')*col('y'))",
                    },
                ]
            },
        },
    )

    assert response.status_code == 200, response.text
    templates = [item["template_id"] for item in response.json()["inspection"]["recommendations"]]
    assert templates[0] == "polar_curve"


def test_inspect_file_recommends_table_figure_after_aggregate_transform(tmp_path: Path) -> None:
    input_path = tmp_path / "long-summary.csv"
    pd.DataFrame(
        [
            ["group", "value"],
            ["A", 1.0],
            ["A", 3.0],
            ["B", 5.0],
            ["B", 7.0],
        ]
    ).to_csv(input_path, header=False, index=False)

    response = client.post(
        "/inspect-file",
        json={
            "input_path": str(input_path),
            "options": {
                "data_transforms": [
                    {
                        "id": "summary",
                        "kind": "aggregate_summary",
                        "group_by": ["group"],
                        "value_columns": ["value"],
                        "statistics": ["mean", "sd", "count"],
                    }
                ]
            },
        },
    )

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["inspection"]["model"] == "table_summary"
    assert payload["inspection"]["recommendations"][0]["template_id"] == "table_figure"
    assert payload["dataset"]["sample_rows"][0] == ["group", "value_mean", "value_sd", "value_count"]
    assert payload["dataset"]["sample_rows"][1] == ["A", 2.0, 1.4142135623730951, 2]


def test_transform_options_stay_consistent_across_render_routes(tmp_path: Path) -> None:
    input_path = tmp_path / "curve.csv"
    _make_curve_csv(input_path)
    options = {
        "data_variables": [
            {"id": "lower", "kind": "scalar", "value": 1.0},
            {"id": "upper", "kind": "scalar", "value": 2.0},
        ],
        "data_transforms": [
            {
                "id": "analysis-window",
                "kind": "mask_filter",
                "expression": "col('Time') >= var('lower') and col('Time') <= var('upper')",
            }
        ],
    }

    inspect_response = client.post("/inspect-file", json={"input_path": str(input_path), "options": options})
    assert inspect_response.status_code == 200, inspect_response.text
    inspect_payload = inspect_response.json()
    assert inspect_payload["inspection"]["recommendation_summary"] == "Recommendations are based on transformed data."
    assert inspect_payload["dataset"]["sample_rows"] == [
        ["Time", "Stress", "Column 3", "Column 4"],
        ["s", "MPa", "s", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
        ["1", "1.2", "1", "2.3"],
        ["2", "1.5", "2", "2.7"],
    ]

    source_response = client.post(
        "/source-table-preview",
        json={"input_path": str(input_path), "sheet": 0, "options": options},
    )
    assert source_response.status_code == 200, source_response.text
    source_payload = source_response.json()
    assert source_payload["column_headers"] == ["Time", "Stress", "Column 3", "Column 4"]
    assert source_payload["rows"] == [
        ["Time", "Stress", "Column 3", "Column 4"],
        ["s", "MPa", "s", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
        ["1", "1.2", "1", "2.3"],
        ["2", "1.5", "2", "2.7"],
    ]

    fit_response = client.post(
        "/fit-analysis",
        json={"input_path": str(input_path), "sheet": 0, "model_id": "linear", "options": options},
    )
    assert fit_response.status_code == 200, fit_response.text
    assert fit_response.json()["point_count"] == 2

    render_request = {"input_path": str(input_path), "sheet": 0, "template": "curve", "options": options}
    preflight_response = client.post("/preflight-render", json=render_request)
    assert preflight_response.status_code == 200, preflight_response.text
    assert preflight_response.json()["preflight"]["errors"] == []

    preview_response = client.post("/render-preview", json=render_request)
    assert preview_response.status_code == 200, preview_response.text
    assert preview_response.json()["submission_report"]["template"] == "curve"

    export_dir = tmp_path / "export"
    export_response = client.post("/export-render", json={**render_request, "output_dir": str(export_dir)})
    assert export_response.status_code == 200, export_response.text
    inspection_artifact = export_dir / "codegod_inspection.json"
    assert inspection_artifact.exists()
    inspection_artifact_payload = json.loads(inspection_artifact.read_text(encoding="utf-8"))
    assert inspection_artifact_payload["recommendation_summary"] == "Recommendations are based on transformed data."


def test_fit_analysis_supports_expanded_and_custom_models(tmp_path: Path) -> None:
    input_path = tmp_path / "fit.csv"
    pd.DataFrame([["x", "y"], ["s", "a.u."], ["Sample", "Sample"], [0, 2], [1, 5], [2, 8], [3, 11]]).to_csv(
        input_path,
        header=False,
        index=False,
    )

    exponential = client.post(
        "/fit-analysis",
        json={"input_path": str(input_path), "model_id": "exponential"},
    )
    assert exponential.status_code == 200, exponential.text
    assert exponential.json()["model_id"] == "exponential"
    assert exponential.json()["point_count"] == 4

    custom = client.post(
        "/fit-analysis",
        json={
            "input_path": str(input_path),
            "model_id": "custom_function",
            "custom_function": {
                "expression": "a*x + b",
                "parameters": [
                    {"name": "a", "initial": 1.0},
                    {"name": "b", "initial": 0.0},
                ],
            },
        },
    )
    assert custom.status_code == 200, custom.text
    payload = custom.json()
    assert payload["model_id"] == "custom_function"
    assert payload["equation_display"].startswith("y =")
    assert payload["r_squared"] > 0.99

    preview = client.post(
        "/render-preview",
        json={
            "input_path": str(input_path),
            "template": "curve",
            "fit_options": {
                "enabled": True,
                "model_id": "custom_function",
                "custom_function": {
                    "expression": "a*x + b",
                    "parameters": [
                        {"name": "a", "initial": 1.0, "lower": 0.0},
                        {"name": "b", "initial": 0.0},
                    ],
                },
            },
        },
    )
    assert preview.status_code == 200, preview.text
