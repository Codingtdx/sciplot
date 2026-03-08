from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pandas as pd

ENCODINGS_TO_TRY = (
    "utf-8",
    "utf-8-sig",
    "utf-16",
    "utf-16-le",
    "utf-16-be",
    "gb18030",
    "latin-1",
)


@dataclass
class CurveSeries:
    sample: str
    x_label: str
    y_label: str
    x_unit: str
    y_unit: str
    data: pd.DataFrame


@dataclass
class ReplicateGroup:
    group: str
    value_label: str
    value_unit: str
    data: pd.Series


def _normalize_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and pd.isna(value):
        return ""
    return str(value).strip()


def _read_delimited(path: Path, **kwargs: Any) -> pd.DataFrame:
    last_error: Exception | None = None
    for encoding in ENCODINGS_TO_TRY:
        try:
            return pd.read_csv(path, encoding=encoding, **kwargs)
        except UnicodeError as exc:
            last_error = exc
        except pd.errors.ParserError as exc:
            last_error = exc
    raise ValueError(f"Failed to decode or parse {path}") from last_error


def read_raw_table(path: str | Path, sheet_name: str | int = 0) -> pd.DataFrame:
    """Read CSV/TSV/TXT/XLSX without assigning a header row."""
    table_path = Path(path)
    suffix = table_path.suffix.lower()
    if suffix in {".xlsx", ".xlsm"}:
        return pd.read_excel(table_path, header=None, sheet_name=sheet_name)
    if suffix == ".csv":
        return _read_delimited(table_path, header=None)
    if suffix in {".tsv", ".txt"}:
        return _read_delimited(table_path, header=None, sep=None, engine="python")
    raise ValueError(f"Unsupported file format: {suffix}")


def load_curve_table(
    path: str | Path,
    *,
    start_row: int = 3,
    sheet_name: str | int = 0,
) -> list[CurveSeries]:
    """
    Load an Origin-style curve table.

    Row 1: axis labels in X/Y pairs
    Row 2: units
    Row 3: sample names repeated twice per series
    Row 4+: numeric data
    """
    raw = read_raw_table(path, sheet_name=sheet_name)
    if raw.shape[0] < start_row + 1:
        raise ValueError("Curve table must include at least 4 rows.")
    if raw.shape[1] % 2 != 0:
        raise ValueError("Curve table must contain an even number of columns in X/Y pairs.")

    axis_row = raw.iloc[0]
    unit_row = raw.iloc[1]
    sample_row = raw.iloc[2]
    data_rows = raw.iloc[start_row:].reset_index(drop=True)

    series_list: list[CurveSeries] = []
    for col in range(0, raw.shape[1], 2):
        x_label = _normalize_text(axis_row.iloc[col])
        y_label = _normalize_text(axis_row.iloc[col + 1])
        x_unit = _normalize_text(unit_row.iloc[col])
        y_unit = _normalize_text(unit_row.iloc[col + 1])
        sample_x = _normalize_text(sample_row.iloc[col])
        sample_y = _normalize_text(sample_row.iloc[col + 1])

        if sample_x and sample_y and sample_x != sample_y:
            raise ValueError(
                f"Sample names in columns {col + 1} and {col + 2} must match, got {sample_x!r} and {sample_y!r}."
            )

        sample_name = sample_x or sample_y or f"Sample_{col // 2 + 1}"
        pair = data_rows.iloc[:, [col, col + 1]].copy()
        pair.columns = ["x", "y"]
        pair = pair.apply(pd.to_numeric, errors="coerce").dropna(how="all")
        pair = pair.dropna(subset=["x", "y"])
        if pair.empty:
            continue

        series_list.append(
            CurveSeries(
                sample=sample_name,
                x_label=x_label or "X",
                y_label=y_label or "Y",
                x_unit=x_unit,
                y_unit=y_unit,
                data=pair.reset_index(drop=True),
            )
        )

    if not series_list:
        raise ValueError("No valid X/Y series found in the curve table.")
    return series_list


def load_replicate_table(
    path: str | Path,
    *,
    start_row: int = 3,
    sheet_name: str | int = 0,
) -> list[ReplicateGroup]:
    """
    Load a wide replicate table for boxplots or bar charts.

    Row 1: value label per column
    Row 2: value unit per column
    Row 3: group or sample name per column
    Row 4+: replicate values
    """
    raw = read_raw_table(path, sheet_name=sheet_name)
    if raw.shape[0] < start_row + 1:
        raise ValueError("Replicate table must include at least 4 rows.")

    value_row = raw.iloc[0]
    unit_row = raw.iloc[1]
    group_row = raw.iloc[2]
    data_rows = raw.iloc[start_row:].reset_index(drop=True)

    groups: list[ReplicateGroup] = []
    for col in range(raw.shape[1]):
        group = _normalize_text(group_row.iloc[col]) or f"Group_{col + 1}"
        value_label = _normalize_text(value_row.iloc[col]) or "Value"
        value_unit = _normalize_text(unit_row.iloc[col])

        values = pd.to_numeric(data_rows.iloc[:, col], errors="coerce").dropna().reset_index(drop=True)
        if values.empty:
            continue

        groups.append(
            ReplicateGroup(
                group=group,
                value_label=value_label,
                value_unit=value_unit,
                data=values,
            )
        )

    if not groups:
        raise ValueError("No valid replicate columns found in the table.")
    return groups
