from __future__ import annotations

from pathlib import Path

import pandas as pd
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

from app.sidecar.server import app

client = TestClient(app)


def _route_signatures() -> set[tuple[str, str]]:
    signatures: set[tuple[str, str]] = set()
    for route in app.routes:
        if not isinstance(route, APIRoute):
            continue
        for method in route.methods or ():
            signatures.add((method, route.path))
    return signatures


def test_active_sidecar_routes_keep_retained_core_surface() -> None:
    signatures = _route_signatures()

    assert ("GET", "/health") in signatures
    assert ("GET", "/meta") in signatures
    assert ("GET", "/plot-contract") in signatures
    assert ("POST", "/inspect-file") in signatures
    assert ("POST", "/code-console/context") in signatures
    assert ("POST", "/code-console/run") in signatures
    assert ("POST", "/render-preview") in signatures
    assert ("POST", "/export-render") in signatures
    assert ("POST", "/compose-preview") in signatures
    assert ("POST", "/compose-export") in signatures
    assert ("GET", "/data-studio/templates") in signatures
    assert ("POST", "/data-studio/source-preview") in signatures
    assert ("POST", "/data-studio/build-workbook") in signatures
    assert ("POST", "/data-studio/import-workbook") in signatures
    assert ("POST", "/data-studio/comparison-preview") in signatures
    assert ("POST", "/data-studio/comparison-export") in signatures
    assert ("POST", "/data-studio/session/normalize") in signatures
    assert ("POST", "/preprocess-tensile-replicates") in signatures
    assert ("POST", "/inspect-tensile-workbook") in signatures
    assert ("POST", "/export-tensile-comparison") in signatures


def test_meta_endpoints_stay_live_for_retained_foundation() -> None:
    health = client.get("/health")
    meta = client.get("/meta")
    contract = client.get("/plot-contract")

    assert health.status_code == 200
    assert health.json()["status"] == "ok"
    assert meta.status_code == 200
    assert "templates" in meta.json()
    assert "visual_themes" in meta.json()
    assert contract.status_code == 200
    assert "templates" in contract.json()


def test_render_inspect_endpoint_stays_live_on_active_sidecar(tmp_path: Path) -> None:
    path = tmp_path / "curve.csv"
    pd.DataFrame(
        [
            ["Time", "Stress", "Time", "Stress"],
            ["s", "MPa", "s", "MPa"],
            ["Sample A", "Sample A", "Sample B", "Sample B"],
            [0, 1.0, 0, 2.0],
            [1, 1.3, 1, 2.4],
            [2, 1.5, 2, 2.8],
        ]
    ).to_csv(path, header=False, index=False)

    response = client.post("/inspect-file", json={"input_path": str(path), "sheet": 0})

    assert response.status_code == 200
    payload = response.json()
    assert payload["inspection"]["model"] == "curve_table"
    assert payload["dataset"]["raw_rows"] >= 3
