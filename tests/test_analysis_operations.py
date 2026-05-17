from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
from fastapi.testclient import TestClient

from app.sidecar.schemas import AnalysisOperationResponse
from app.sidecar.server import app
from src.rendering.analysis_operations import SUPPORTED_OPERATION_IDS, run_analysis_operation

client = TestClient(app)


def _write_curve(path: Path) -> None:
    xs = np.linspace(0.0, 5.0, 6)
    ys = xs * xs
    pd.DataFrame([["x", "signal"], ["s", "a.u."], *zip(xs, ys, strict=True)]).to_csv(
        path,
        header=False,
        index=False,
    )


def test_analysis_registry_covers_labplot_runtime_batch() -> None:
    assert {
        "analysis.smoothing",
        "analysis.interpolation",
        "analysis.differentiation",
        "analysis.integration",
        "analysis.fft",
        "analysis.fourier_filter",
        "analysis.correlation",
        "analysis.convolution",
        "analysis.baseline",
        "analysis.peak_detection",
        "analysis.kde",
        "analysis.statistical_tests",
        "analysis.distribution_fitting",
        "analysis.peak_fitting",
        "analysis.growth_models",
    } <= SUPPORTED_OPERATION_IDS


def test_analysis_operation_endpoint_returns_typed_envelope(tmp_path: Path) -> None:
    input_path = tmp_path / "curve.csv"
    _write_curve(input_path)

    response = client.post(
        "/analysis-operation",
        json={
            "operation_id": "analysis.integration",
            "input_path": str(input_path),
            "sheet": 0,
            "x_column": "x",
            "y_column": "signal",
        },
    )

    assert response.status_code == 200, response.text
    payload = AnalysisOperationResponse.model_validate(response.json())
    result = payload.operation_result
    assert result.operation_id == "analysis.integration"
    assert result.valid is True
    assert result.status_code == "ok"
    assert result.metrics["total_area"] == 42.5
    assert result.data_containers[0].kind == "transformed_view"


def test_analysis_operations_include_numerical_fixture_results(tmp_path: Path) -> None:
    input_path = tmp_path / "wave.csv"
    xs = np.arange(8, dtype=float)
    ys = np.sin(2 * np.pi * xs / 4)
    pd.DataFrame([["x", "signal"], ["s", "a.u."], *zip(xs, ys, strict=True)]).to_csv(
        input_path,
        header=False,
        index=False,
    )

    fft = run_analysis_operation(
        operation_id="analysis.fft",
        input_path=input_path,
        sheet=0,
        x_column="x",
        y_column="signal",
    )
    peaks = run_analysis_operation(
        operation_id="analysis.peak_detection",
        input_path=input_path,
        sheet=0,
        x_column="x",
        y_column="signal",
        parameters={"height": 0.5},
    )

    assert fft["metrics"]["dominant_frequency"] == 0.25
    assert peaks["metrics"]["peak_count"] >= 1
    assert peaks["overlays"][0]["kind"] == "peak_markers"


def test_distribution_and_growth_models_return_experimental_tables(tmp_path: Path) -> None:
    input_path = tmp_path / "growth.csv"
    xs = np.arange(1, 7, dtype=float)
    ys = 2.0 * np.exp(0.25 * xs)
    pd.DataFrame([["x", "signal"], ["s", "a.u."], *zip(xs, ys, strict=True)]).to_csv(
        input_path,
        header=False,
        index=False,
    )

    distribution = run_analysis_operation(
        operation_id="analysis.distribution_fitting",
        input_path=input_path,
        sheet=0,
        x_column="x",
        y_column="signal",
        parameters={"distribution": "normal"},
    )
    growth = run_analysis_operation(
        operation_id="analysis.growth_models",
        input_path=input_path,
        sheet=0,
        x_column="x",
        y_column="signal",
        parameters={"model": "exponential"},
    )

    assert distribution["metrics"]["sigma"] > 0
    assert growth["metrics"]["rate"] > 0
    assert growth["data_containers"][0]["status"] == "experimental"
