from __future__ import annotations

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
