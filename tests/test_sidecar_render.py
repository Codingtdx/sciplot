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
