from __future__ import annotations

from pathlib import Path

import pandas as pd
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

from app.sidecar.server import CRITICAL_SIDECAR_ROUTES, app
from src.rendering.preview_scene import build_preview_scene

client = TestClient(app)


def _curve_csv(path: Path) -> None:
    pd.DataFrame(
        [
            ["x", "signal", "group"],
            ["s", "mV", ""],
            [0.0, 0.0, "A"],
            [1.0, 1.0, "A"],
            [2.0, 4.0, "A"],
            [3.0, 9.0, "A"],
        ]
    ).to_csv(path, header=False, index=False)


def _route_signatures() -> set[tuple[str, str]]:
    signatures: set[tuple[str, str]] = set()
    for route in app.routes:
        if not isinstance(route, APIRoute):
            continue
        for method in route.methods or ():
            signatures.add((method, route.path))
    return signatures


def test_nextgen_sidecar_routes_are_registered_and_critical() -> None:
    signatures = _route_signatures()

    assert ("POST", "/preview-scene") in signatures
    assert ("POST", "/command/normalize") in signatures
    assert ("POST", "/command/apply-preview") in signatures
    assert ("POST", "/live-source/update-now") in signatures
    assert ("POST", "/preview-scene") in set(CRITICAL_SIDECAR_ROUTES)
    assert ("POST", "/command/normalize") in set(CRITICAL_SIDECAR_ROUTES)
    assert ("POST", "/command/apply-preview") in set(CRITICAL_SIDECAR_ROUTES)
    assert ("POST", "/live-source/update-now") in set(CRITICAL_SIDECAR_ROUTES)


def test_meta_exposes_nextgen_runtime_capabilities() -> None:
    response = client.get("/meta")

    assert response.status_code == 200
    catalogs = {
        group["id"]: {item["id"]: item for item in group["capabilities"]}
        for group in response.json()["capability_catalogs"]
    }
    assert catalogs["native_preview_features"]["native_preview.preview_scene"]["status"] == "enabled"
    assert catalogs["command_engine"]["command.cross_module_normalize"]["status"] == "enabled"
    assert catalogs["data_containers"]["data.column_model"]["status"] == "enabled"
    assert catalogs["live_sources"]["live.file_tail"]["status"] == "enabled"
    assert catalogs["live_sources"]["live.mqtt"]["status"] == "disabled"


def test_source_table_containers_include_column_semantics_and_lifecycle(tmp_path: Path) -> None:
    path = tmp_path / "curve.csv"
    _curve_csv(path)

    response = client.post("/source-table-preview", json={"input_path": str(path), "sheet": 0})

    assert response.status_code == 200, response.text
    container = response.json()["data_containers"][0]
    first_column = container["columns"][0]
    assert first_column["mode"] == "numeric"
    assert first_column["readonly"] is True
    assert first_column["missing_policy"] == "preserve"
    assert first_column["lineage"]["source_container_id"] == container["id"]
    assert first_column["lifecycle_events"] == ["data_about_to_change", "data_changed", "mode_changed", "role_changed"]
    assert container["column_ids"] == [column["id"] for column in container["columns"]]


def test_import_dependency_diagnostics_distinguish_missing_dependency(tmp_path: Path) -> None:
    path = tmp_path / "sample.h5"
    path.write_bytes(b"not a real hdf5 file")

    response = client.post("/import-preview", json={"input_path": str(path), "filter_id": "import.hdf5"})

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["status"] == "disabled"
    assert payload["diagnostics"][0]["status_code"] == "dependency_missing"
    assert payload["diagnostics"][0]["dependency"] == "h5py"
    assert payload["diagnostics"][0]["help_action"] == (
        "Install the optional dependency and enable fixtures before exposing this filter."
    )


def test_analysis_operation_result_has_lifecycle_metadata(tmp_path: Path) -> None:
    path = tmp_path / "curve.csv"
    _curve_csv(path)

    response = client.post(
        "/analysis-operation",
        json={
            "operation_id": "analysis.smoothing",
            "input_path": str(path),
            "sheet": 0,
            "x_column": "x",
            "y_column": "signal",
            "parameters": {"method": "rolling_mean", "window": 3},
        },
    )

    assert response.status_code == 200, response.text
    result = response.json()["operation_result"]
    assert result["settings"]["method"] == "rolling_mean"
    assert result["source_binding"]["x_column_id"] == "col-0"
    assert result["source_binding"]["y_column_id"] == "col-1"
    assert result["prepared_arrays"]["input_points"] == 4
    assert result["elapsed_ms"] >= 0
    assert result["lineage"]["invalidates_on"] == ["source_revision", "settings_revision"]
    assert result["artifact_refs"] == []


def test_cross_module_command_normalize_and_apply_preview() -> None:
    command = {
        "command_id": "cmd-copy-style",
        "kind": "copy_settings",
        "module": "plot",
        "target_object_id": "plot:legend:main",
        "source_object_id": "plot:series:a",
        "before": {"visible": True},
        "after": {"visible": True, "copied_style_ref": "plot:series:a"},
    }

    normalize = client.post("/command/normalize", json={"command": command, "objects": []})

    assert normalize.status_code == 200, normalize.text
    normalized = normalize.json()["command"]
    assert normalized["module"] == "plot"
    assert normalized["graph_patch"]["revision_delta"] == 1
    assert normalized["graph_patch"]["target_object_id"] == "plot:legend:main"
    assert normalize.json()["diagnostics"] == []

    apply_preview = client.post(
        "/command/apply-preview",
        json={"command": normalized, "document_graph": {"schema_version": 2, "revision": 4}},
    )

    assert apply_preview.status_code == 200, apply_preview.text
    payload = apply_preview.json()
    assert payload["graph_revision"] == 5
    assert payload["render_invalidation"]["reason"] == "command_applied"
    assert payload["diagnostics"] == []


def test_preview_scene_returns_native_scene_or_explicit_fallback(tmp_path: Path) -> None:
    path = tmp_path / "curve.csv"
    _curve_csv(path)

    response = client.post(
        "/preview-scene",
        json={
            "input_path": str(path),
            "sheet": 0,
            "template": "curve",
            "options": {"style_preset": "nature"},
            "preview_config": {"pixel_width": 800, "pixel_height": 600, "scale": 2.0},
        },
    )

    assert response.status_code == 200, response.text
    scene = response.json()
    assert scene["template"] == "curve"
    assert scene["native_supported"] is True
    assert scene["fallback_reason"] is None
    assert scene["graph_revision"] >= 1
    assert scene["figure"] == {"pixel_width": 800, "pixel_height": 600, "scale": 2.0}
    assert scene["plot_area"]["width"] > 0
    assert scene["axes"][0]["x_scale"] == "linear"
    assert scene["axes"][0]["bbox_pixels"] == scene["plot_area"]
    assert scene["series"][0]["column_refs"] == {"x": "col-0", "y": "col-1"}
    assert scene["budgets"]["native_scene_samples"] >= len(scene["series"][0]["samples"])
    scene_object = scene["objects"][0]
    assert scene_object["kind"] == "series_line"
    assert scene_object["payload_ref"] == {"type": "series", "id": "plot:series:0"}
    assert scene_object["bbox_pixels"]["width"] > 0
    assert scene_object["points"][0] == [
        scene["plot_area"]["x"],
        scene["plot_area"]["y"] + scene["plot_area"]["height"],
    ]
    assert {"select", "quick_edit", "drag_offset", "copy_settings"}.issubset(set(scene_object["operations"]))


def test_preview_scene_unsupported_template_falls_back_explicitly(tmp_path: Path) -> None:
    path = tmp_path / "curve.csv"
    _curve_csv(path)

    response = client.post(
        "/preview-scene",
        json={
            "input_path": str(path),
            "sheet": 0,
            "template": "heatmap",
            "options": {"style_preset": "nature"},
        },
    )

    assert response.status_code == 200, response.text
    scene = response.json()
    assert scene["native_supported"] is False
    assert scene["fallback_reason"] == "unsupported_template"
    assert scene["objects"] == []
    assert scene["diagnostics"][0]["status_code"] == "native_preview_fallback"
    assert scene["diagnostics"][0]["fallback_reason"] == "unsupported_template"


def test_preview_scene_sample_budget_fallback_is_specific(tmp_path: Path) -> None:
    path = tmp_path / "curve.csv"
    _curve_csv(path)

    scene = build_preview_scene(
        input_path=path,
        sheet=0,
        template="curve",
        options={"style_preset": "nature"},
        preview_config={"pixel_width": 800, "pixel_height": 600, "native_scene_sample_budget": 2},
    )

    assert scene["native_supported"] is False
    assert scene["fallback_reason"] == "sample_budget_exceeded"
    assert scene["budgets"]["native_scene_samples"] == 2
    assert scene["diagnostics"][0]["status_code"] == "native_preview_fallback"
    assert scene["diagnostics"][0]["fallback_reason"] == "sample_budget_exceeded"


def test_live_source_update_now_returns_revisioned_containers(tmp_path: Path) -> None:
    path = tmp_path / "live.csv"
    _curve_csv(path)

    response = client.post(
        "/live-source/update-now",
        json={
            "live_source": {
                "id": "live:file-tail:live",
                "kind": "periodic_csv",
                "status": "enabled",
                "poll_interval_ms": 1000,
                "sample_window": 200,
                "append_policy": "replace",
                "paused": False,
                "help": "Periodic CSV refresh for local files.",
            },
            "input_path": str(path),
            "sheet": 0,
        },
    )

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["live_source"]["last_update_diagnostic"]["status_code"] == "live_source_updated"
    assert payload["data_revision"] >= 1
    assert payload["data_containers"][0]["kind"] == "table"
    assert payload["render_invalidation"]["reason"] == "live_source_updated"
