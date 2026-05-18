from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from fastapi.testclient import TestClient

from app.sidecar.schemas import ImportPreviewResponse
from app.sidecar.server import app
from src.rendering.export_targets import artifact_manifest_payload
from src.rendering.import_filters import FILTERS

client = TestClient(app)


def test_import_filter_registry_statuses_are_explicit() -> None:
    assert FILTERS["import.csv"]["status"] == "enabled"
    assert FILTERS["import.json"]["status"] == "enabled"
    assert FILTERS["import.binary_raw"]["status"] == "enabled"
    assert FILTERS["import.hdf5"]["status"] == "disabled"
    assert FILTERS["import.origin_scidavis_eval"]["status"] == "disabled"


def test_json_import_preview_returns_table_container(tmp_path: Path) -> None:
    input_path = tmp_path / "records.json"
    input_path.write_text(json.dumps({"records": [{"x": 1, "y": 2}, {"x": 3, "y": 4}]}), encoding="utf-8")

    response = client.post("/import-preview", json={"input_path": str(input_path), "filter_id": "import.json"})

    assert response.status_code == 200, response.text
    payload = ImportPreviewResponse.model_validate(response.json())
    assert payload.status == "enabled"
    assert payload.data_containers[0].kind == "table"
    assert payload.data_containers[0].row_count == 2
    assert payload.profile.id == "import.json"
    assert payload.profile.preview_supported is True
    assert payload.available_options


def test_binary_import_preview_requires_shape_and_returns_matrix(tmp_path: Path) -> None:
    input_path = tmp_path / "field.raw"
    np.asarray([[1, 2], [3, 4]], dtype=np.float32).tofile(input_path)

    response = client.post(
        "/import-preview",
        json={
            "input_path": str(input_path),
            "filter_id": "import.binary_raw",
            "options": {"dtype": "float32", "shape": [2, 2]},
        },
    )

    assert response.status_code == 200, response.text
    payload = ImportPreviewResponse.model_validate(response.json())
    assert payload.data_containers[0].kind == "matrix"
    assert payload.data_containers[0].dimensions == {"rows": 2, "columns": 2}
    assert payload.profile.options_schema["required"] == ["dtype", "shape"]
    assert {option.id for option in payload.available_options} >= {"dtype", "shape"}


def test_csv_import_preview_returns_filter_profile_and_structured_diagnostics(tmp_path: Path) -> None:
    input_path = tmp_path / "ragged.csv"
    input_path.write_text(
        "Time;Signal;Signal\n"
        "s;mV;mV\n"
        "0;1;2\n"
        "1;3\n"
        "2;4;5\n",
        encoding="utf-8",
    )

    response = client.post("/import-preview", json={"input_path": str(input_path), "filter_id": "import.csv"})

    assert response.status_code == 200, response.text
    payload = ImportPreviewResponse.model_validate(response.json())
    status_codes = {diagnostic.status_code for diagnostic in payload.diagnostics}
    assert payload.profile.id == "import.csv"
    assert payload.profile.extensions == [".csv", ".tsv", ".txt"]
    assert payload.profile.preview_supported is True
    assert payload.profile.read_supported is True
    assert payload.selected_sheet_or_segment == "Sheet1"
    assert {"encoding_detected", "delimiter_detected", "ragged_rows_detected", "duplicate_headers_detected"}.issubset(
        status_codes
    )
    assert {option.id for option in payload.available_options} >= {"encoding", "delimiter", "header_row_index"}


def test_unavailable_import_filter_returns_helpful_diagnostic(tmp_path: Path) -> None:
    input_path = tmp_path / "sample.h5"
    input_path.write_bytes(b"not a real hdf5 fixture")

    response = client.post("/import-preview", json={"input_path": str(input_path), "filter_id": "import.hdf5"})

    assert response.status_code == 200, response.text
    payload = ImportPreviewResponse.model_validate(response.json())
    assert payload.status == "disabled"
    assert payload.data_containers == []
    assert payload.profile.dependency_status == "missing"
    assert payload.diagnostics[0].status_code == "dependency_missing"
    assert payload.diagnostics[0].dependency == "h5py"
    assert payload.help


def test_artifact_manifest_payload_records_export_runtime_outputs(tmp_path: Path) -> None:
    payload = artifact_manifest_payload(
        output_dir=tmp_path,
        artifacts=[
            {"kind": "figure", "path": "figure.pdf"},
            {"kind": "data_workbook", "path": "workbook.xlsx"},
        ],
    )

    assert payload["artifact_kind"] == "manifest"
    assert payload["count"] == 2
    assert payload["output_dir"] == str(tmp_path)
