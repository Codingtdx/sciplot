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
        raise AssertionError("cache hit should skip build_rendered_plots")

    monkeypatch.setattr("app.sidecar.routes_render.build_rendered_plots", fail_render)

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
