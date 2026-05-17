from __future__ import annotations

# ruff: noqa: E501
import json
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from src.rendering.data_containers import (
    matrix_container_from_array,
    source_table_data_containers,
    table_container_from_frame,
)
from src.rendering.source_table_preview import source_table_preview

FILTERS: dict[str, dict[str, Any]] = {
    "import.csv": {"label": "CSV/TSV/TXT", "status": "enabled", "extensions": [".csv", ".tsv", ".txt"]},
    "import.excel": {"label": "Excel", "status": "enabled", "extensions": [".xls", ".xlsx", ".xlsm"]},
    "import.json": {"label": "JSON", "status": "enabled", "extensions": [".json"]},
    "import.binary_raw": {"label": "Binary/Raw", "status": "enabled", "extensions": [".raw", ".bin"]},
    "import.hdf5": {"label": "HDF5", "status": "disabled", "extensions": [".h5", ".hdf5"], "dependency": "h5py"},
    "import.netcdf": {"label": "NetCDF", "status": "disabled", "extensions": [".nc", ".netcdf"], "dependency": "netCDF4"},
    "import.fits": {"label": "FITS", "status": "disabled", "extensions": [".fits"], "dependency": "astropy"},
    "import.ods": {"label": "ODS", "status": "disabled", "extensions": [".ods"], "dependency": "odf"},
    "import.readstat": {"label": "SAS/Stata/SPSS", "status": "disabled", "extensions": [".sav", ".dta", ".sas7bdat"], "dependency": "pyreadstat"},
    "import.sql": {"label": "SQL", "status": "disabled", "extensions": [".sqlite", ".db"]},
    "import.origin_scidavis_eval": {"label": "Origin/SciDAVis Evaluation", "status": "disabled", "extensions": [".opju", ".opj"]},
    "import.image_digitizer": {"label": "Image Digitizer", "status": "disabled", "extensions": [".png", ".jpg", ".jpeg", ".tif", ".tiff"]},
}


def _detect_filter(path: Path, requested: str | None) -> str:
    if requested:
        return requested
    suffix = path.suffix.lower()
    for filter_id, spec in FILTERS.items():
        if suffix in spec["extensions"]:
            return filter_id
    return "import.csv"


def _unavailable(path: Path, filter_id: str, spec: dict[str, Any]) -> dict[str, Any]:
    dependency = spec.get("dependency")
    status_code = "dependency_missing" if dependency else "policy_not_implemented"
    return {
        "input_path": str(path),
        "filter_id": filter_id,
        "status": spec["status"],
        "label": spec["label"],
        "data_containers": [],
        "diagnostics": [
            {
                "status_code": status_code,
                "message": f"{spec['label']} is disabled in this runtime.",
                "dependency": dependency,
                "help_action": (
                    "Install the optional dependency and enable fixtures before exposing this filter."
                    if dependency
                    else "Define the safety policy, preview contract, and fixtures before exposing this filter."
                ),
            }
        ],
        "options_schema": {"type": "object"},
        "help": "This filter has an explicit landing point and remains disabled until dependencies, safety policy, and fixtures are added.",
    }


def preview_import(
    *,
    input_path: str | Path,
    filter_id: str | None = None,
    sheet: str | int = 0,
    offset: int = 0,
    limit: int = 50,
    options: dict[str, Any] | None = None,
) -> dict[str, Any]:
    path = Path(input_path).expanduser()
    resolved_filter = _detect_filter(path, filter_id)
    spec = FILTERS.get(resolved_filter)
    if spec is None:
        raise ValueError(f"Unknown import filter `{resolved_filter}`.")
    if spec["status"] == "disabled":
        return _unavailable(path, resolved_filter, spec)
    opts = options or {}
    if resolved_filter in {"import.csv", "import.excel"}:
        preview = source_table_preview(path, sheet=sheet, offset=offset, limit=limit)
        return {
            "input_path": str(path),
            "filter_id": resolved_filter,
            "status": spec["status"],
            "label": spec["label"],
            "data_containers": source_table_data_containers(preview),
            "diagnostics": [],
            "options_schema": {"type": "object"},
            "help": "Preview generated through the existing source table engine.",
        }
    if resolved_filter == "import.json":
        raw = json.loads(path.read_text(encoding=str(opts.get("encoding") or "utf-8")))
        records = raw.get("records") if isinstance(raw, dict) else raw
        if not isinstance(records, list):
            raise ValueError("JSON preview requires a list of records or an object with a `records` list.")
        frame = pd.DataFrame(records)
        return {
            "input_path": str(path),
            "filter_id": resolved_filter,
            "status": "enabled",
            "label": spec["label"],
            "data_containers": [
                table_container_from_frame(
                    frame,
                    input_path=path,
                    container_id=f"import-json:{path.name}",
                    label=f"{path.name} JSON table",
                    status="enabled",
                    help_text="JSON records table generated by import preview.",
                )
            ],
            "diagnostics": [{"status_code": "json_records_loaded", "row_count": int(frame.shape[0])}],
            "options_schema": {"type": "object", "properties": {"encoding": {"type": "string"}}},
            "help": "JSON records preview is enabled for list/object-with-records payloads.",
        }
    dtype = str(opts.get("dtype") or "float32")
    shape = opts.get("shape")
    if not isinstance(shape, list) or len(shape) != 2:
        raise ValueError("Binary/raw preview requires options.shape as [rows, columns].")
    array = np.fromfile(path, dtype=np.dtype(dtype)).reshape((int(shape[0]), int(shape[1])))
    return {
        "input_path": str(path),
        "filter_id": resolved_filter,
        "status": "enabled",
        "label": spec["label"],
        "data_containers": [matrix_container_from_array(array, input_path=path, container_id=f"import-binary:{path.name}")],
        "diagnostics": [{"status_code": "binary_raw_loaded", "dtype": dtype, "shape": shape}],
        "options_schema": {
            "type": "object",
            "required": ["dtype", "shape"],
            "properties": {"dtype": {"type": "string"}, "shape": {"type": "array"}},
        },
        "help": "Binary/raw preview is enabled when explicit dtype and shape are provided.",
    }


__all__ = ["FILTERS", "preview_import"]
