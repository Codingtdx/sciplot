from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
from fastapi.testclient import TestClient

from app.sidecar.schemas import (
    AnalysisOperationRequest,
    AnalysisOperationResponse,
    ImportPreviewResponse,
    PlotEditCommandNormalizeRequest,
    PlotEditCommandNormalizeResponse,
)
from app.sidecar.server import app
from src.rendering.capability_registry import capability_catalog_payload

client = TestClient(app)


def _curve_csv(path: Path) -> None:
    pd.DataFrame(
        [
            ["x", "signal"],
            ["s", "mV"],
            [0.0, 0.0],
            [1.0, 1.0],
            [2.0, 4.0],
            [3.0, 9.0],
            [4.0, 16.0],
        ]
    ).to_csv(path, header=False, index=False)


def test_capability_registry_is_runtime_source_of_truth() -> None:
    catalogs = {group["id"]: group for group in capability_catalog_payload()}
    analysis = {item["id"]: item for item in catalogs["analysis_operations"]["capabilities"]}
    imports = {item["id"]: item for item in catalogs["import_filters"]["capabilities"]}

    assert analysis["analysis.smoothing"]["status"] == "enabled"
    assert analysis["analysis.integration"]["status"] == "enabled"
    assert analysis["analysis.fft"]["status"] == "enabled"
    assert imports["import.json"]["status"] == "enabled"
    assert imports["import.hdf5"]["status"] == "disabled"
    assert imports["import.origin_scidavis_eval"]["status"] == "disabled"


def test_analysis_operation_models_validate_runtime_request() -> None:
    request = AnalysisOperationRequest.model_validate(
        {
            "operation_id": "analysis.smoothing",
            "input_path": "/tmp/curve.csv",
            "sheet": 0,
            "x_column": "x",
            "y_column": "signal",
            "parameters": {"method": "rolling_mean", "window": 3},
        }
    )

    assert request.operation_id == "analysis.smoothing"
    assert request.parameters["window"] == 3


def test_analysis_operation_smoothing_and_integration_runtime(tmp_path: Path) -> None:
    input_path = tmp_path / "curve.csv"
    _curve_csv(input_path)

    smoothing = client.post(
        "/analysis-operation",
        json={
            "operation_id": "analysis.smoothing",
            "input_path": str(input_path),
            "sheet": 0,
            "x_column": "x",
            "y_column": "signal",
            "parameters": {"method": "rolling_mean", "window": 3},
        },
    )
    assert smoothing.status_code == 200, smoothing.text
    smoothing_payload = AnalysisOperationResponse.model_validate(smoothing.json())
    assert smoothing_payload.operation_result.operation_id == "analysis.smoothing"
    assert smoothing_payload.operation_result.valid is True
    assert smoothing_payload.operation_result.data_containers[0].kind == "transformed_view"
    assert smoothing_payload.operation_result.tables[0]["row_count"] == 5

    integration = client.post(
        "/analysis-operation",
        json={
            "operation_id": "analysis.integration",
            "input_path": str(input_path),
            "sheet": 0,
            "x_column": "x",
            "y_column": "signal",
        },
    )
    assert integration.status_code == 200, integration.text
    integration_payload = AnalysisOperationResponse.model_validate(integration.json())
    assert integration_payload.operation_result.metrics["total_area"] == 22.0


def test_analysis_operation_fft_and_peak_detection_runtime(tmp_path: Path) -> None:
    input_path = tmp_path / "wave.csv"
    xs = np.arange(8, dtype=float)
    ys = np.sin(2 * np.pi * xs / 4)
    pd.DataFrame([["x", "signal"], ["s", "mV"], *zip(xs, ys, strict=True)]).to_csv(
        input_path,
        header=False,
        index=False,
    )

    fft = client.post(
        "/analysis-operation",
        json={
            "operation_id": "analysis.fft",
            "input_path": str(input_path),
            "sheet": 0,
            "x_column": "x",
            "y_column": "signal",
        },
    )
    assert fft.status_code == 200, fft.text
    fft_payload = AnalysisOperationResponse.model_validate(fft.json())
    assert fft_payload.operation_result.metrics["dominant_frequency"] == 0.25

    peaks = client.post(
        "/analysis-operation",
        json={
            "operation_id": "analysis.peak_detection",
            "input_path": str(input_path),
            "sheet": 0,
            "x_column": "x",
            "y_column": "signal",
            "parameters": {"height": 0.5},
        },
    )
    assert peaks.status_code == 200, peaks.text
    peak_payload = AnalysisOperationResponse.model_validate(peaks.json())
    assert peak_payload.operation_result.metrics["peak_count"] >= 1
    assert peak_payload.operation_result.overlays[0]["kind"] == "peak_markers"


def test_import_preview_json_and_binary_runtime(tmp_path: Path) -> None:
    json_path = tmp_path / "records.json"
    json_path.write_text(json.dumps([{"x": 0, "y": 1}, {"x": 1, "y": 3}]), encoding="utf-8")

    json_preview = client.post("/import-preview", json={"input_path": str(json_path), "filter_id": "import.json"})
    assert json_preview.status_code == 200, json_preview.text
    json_payload = ImportPreviewResponse.model_validate(json_preview.json())
    assert json_payload.filter_id == "import.json"
    assert json_payload.data_containers[0].kind == "table"
    assert json_payload.status == "enabled"

    raw_path = tmp_path / "field.raw"
    np.asarray([[1, 2], [3, 4]], dtype=np.float32).tofile(raw_path)
    raw_preview = client.post(
        "/import-preview",
        json={
            "input_path": str(raw_path),
            "filter_id": "import.binary_raw",
            "options": {"dtype": "float32", "shape": [2, 2]},
        },
    )
    assert raw_preview.status_code == 200, raw_preview.text
    raw_payload = ImportPreviewResponse.model_validate(raw_preview.json())
    assert raw_payload.data_containers[0].kind == "matrix"
    assert raw_payload.data_containers[0].dimensions == {"rows": 2, "columns": 2}


def test_import_preview_unavailable_filter_is_structured(tmp_path: Path) -> None:
    path = tmp_path / "sample.h5"
    path.write_bytes(b"not-hdf5")

    response = client.post("/import-preview", json={"input_path": str(path), "filter_id": "import.hdf5"})

    assert response.status_code == 200, response.text
    payload = ImportPreviewResponse.model_validate(response.json())
    assert payload.status == "disabled"
    assert payload.data_containers == []
    assert payload.diagnostics[0]["status_code"] == "filter_unavailable"


def test_plot_edit_command_normalize_runtime() -> None:
    request = PlotEditCommandNormalizeRequest.model_validate(
        {
            "command": {
                "command_id": "cmd-visible",
                "kind": "visibility",
                "target_object_id": "plot:guide:target",
                "before": {"visible": True},
                "after": {"visible": False},
            }
        }
    )
    assert request.command.kind == "visibility"

    response = client.post("/plot-edit-command/normalize", json=request.model_dump(mode="json"))

    assert response.status_code == 200, response.text
    payload = PlotEditCommandNormalizeResponse.model_validate(response.json())
    assert payload.command.kind == "visibility"
    assert payload.command.reversible is True
    assert payload.command.graph_patch["target_object_id"] == "plot:guide:target"
    assert payload.diagnostics == []
