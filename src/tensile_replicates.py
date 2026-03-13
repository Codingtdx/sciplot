from __future__ import annotations

import csv
import os
import re
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd

RAW_CSV_ENCODINGS = (
    "gb18030",
    "gbk",
    "utf-8",
    "utf-8-sig",
    "utf-16",
    "latin-1",
)
REPRESENTATIVE_CURVE_SHEET = "Representative_Curve"
ALL_CURVES_SHEET = "All_Curves"
SUMMARY_SHEET = "Summary"
ALL_SPECIMENS_SHEET = "All_Specimens"
METRIC_SPECS = (
    ("Strength", "MPa", ("拉伸应力", "最大值", "力"), ("最大应力",)),
    ("Modulus", "MPa", ("模量",), ("modulus",)),
    ("Elongation", "%", ("拉伸应变", "断裂"), ("断裂应变", "break strain")),
)


@dataclass(frozen=True)
class TensileMetricSummary:
    label: str
    unit: str
    mean: float | None
    std: float | None


@dataclass(frozen=True)
class TensileRawSample:
    source_path: Path
    filename: str
    strength: float | None
    modulus: float | None
    elongation: float | None
    curve: pd.DataFrame


@dataclass(frozen=True)
class TensileReplicateWorkbook:
    output_path: Path
    group_name: str
    preferred_sheet: str
    sheet_names: tuple[str, ...]
    sample_count: int
    representative_filename: str
    metrics: tuple[TensileMetricSummary, ...]
    warnings: tuple[str, ...]


def infer_group_name(file_paths: Iterable[str | Path]) -> str:
    paths = [Path(path) for path in file_paths]
    stems = [path.stem for path in paths if path.stem]
    if not stems:
        return "Tensile_Group"
    prefix = os.path.commonprefix(stems).strip()
    prefix = re.sub(r"[_\-\s]+$", "", prefix)
    if prefix:
        return prefix
    parent_name = paths[0].parent.name.strip()
    if parent_name:
        return parent_name
    return stems[0]


def export_tensile_replicate_workbook(
    file_paths: Iterable[str | Path],
    output_path: str | Path,
    *,
    group_name: str | None = None,
) -> TensileReplicateWorkbook:
    paths = [Path(path).expanduser() for path in file_paths]
    if not paths:
        raise ValueError("请至少选择一个原始拉伸 CSV 文件。")

    parsed_samples: list[TensileRawSample] = []
    warnings: list[str] = []

    for path in paths:
        try:
            parsed_samples.append(parse_tensile_csv(path))
        except Exception as exc:
            warnings.append(f"已跳过 {path.name}: {exc}")

    if not parsed_samples:
        raise ValueError("没有成功解析任何拉伸 CSV。请确认文件来自同一类拉伸导出格式。")

    resolved_group_name = (group_name or infer_group_name(paths)).strip() or "Tensile_Group"
    summary_df = _build_summary_dataframe(parsed_samples)
    representative_index = _representative_index(summary_df)
    representative_sample = parsed_samples[representative_index]

    workbook_path = Path(output_path).expanduser()
    if workbook_path.suffix.lower() != ".xlsx":
        workbook_path = workbook_path.with_suffix(".xlsx")
    workbook_path.parent.mkdir(parents=True, exist_ok=True)

    metrics = _metric_summaries(summary_df)
    sheets = _workbook_sheets(parsed_samples, summary_df, representative_sample, resolved_group_name, metrics)
    with pd.ExcelWriter(workbook_path) as writer:
        for sheet_name, dataframe in sheets:
            dataframe.to_excel(writer, sheet_name=sheet_name, header=False, index=False)

    return TensileReplicateWorkbook(
        output_path=workbook_path,
        group_name=resolved_group_name,
        preferred_sheet=REPRESENTATIVE_CURVE_SHEET,
        sheet_names=tuple(sheet_name for sheet_name, _ in sheets),
        sample_count=len(parsed_samples),
        representative_filename=representative_sample.filename,
        metrics=metrics,
        warnings=tuple(warnings),
    )


def parse_tensile_csv(path: str | Path) -> TensileRawSample:
    file_path = Path(path).expanduser()
    rows = _read_csv_rows(file_path)
    scalar_header_index = _find_scalar_header_index(rows)
    if scalar_header_index is None:
        raise ValueError("没有找到结果表格 1 中的标量表头。")

    scalar_headers = rows[scalar_header_index]
    scalar_values = _find_scalar_value_row(rows, scalar_header_index)
    if scalar_values is None:
        raise ValueError("没有找到结果表格 1 的有效数值行。")

    metric_values = {
        "strength": _extract_scalar_value(
            scalar_headers,
            scalar_values,
            primary_keywords=("拉伸应力", "最大值", "力"),
            fallback_keywords=(("最大应力",), ("tensile stress", "maximum"), ("max stress",)),
        ),
        "modulus": _extract_scalar_value(
            scalar_headers,
            scalar_values,
            primary_keywords=("模量",),
            fallback_keywords=(("modulus",),),
        ),
        "elongation": _extract_scalar_value(
            scalar_headers,
            scalar_values,
            primary_keywords=("拉伸应变", "断裂"),
            fallback_keywords=(("断裂应变",), ("break strain",), ("tensile strain", "break")),
        ),
    }

    curve = _extract_curve_dataframe(rows, start_index=scalar_header_index)
    if curve.empty:
        raise ValueError("没有找到结果表格 2 中的应力-应变曲线。")

    return TensileRawSample(
        source_path=file_path,
        filename=file_path.name,
        strength=metric_values["strength"],
        modulus=metric_values["modulus"],
        elongation=metric_values["elongation"],
        curve=curve,
    )


def _read_csv_rows(path: Path) -> list[list[str]]:
    raw_bytes = path.read_bytes()
    for encoding in RAW_CSV_ENCODINGS:
        try:
            text = raw_bytes.decode(encoding)
        except UnicodeDecodeError:
            continue
        if _looks_like_tensile_text(text):
            return list(csv.reader(text.splitlines()))
    raise ValueError("无法用常见编码读出拉伸导出表。")


def _looks_like_tensile_text(text: str) -> bool:
    lowered = text.lower()
    return any(
        marker in text or marker in lowered
        for marker in ("结果表格", "拉伸应力", "result table", "tensile stress")
    )


def _find_scalar_header_index(rows: list[list[str]]) -> int | None:
    for index, row in enumerate(rows):
        joined = ",".join(_clean_cell(cell) for cell in row)
        lowered = joined.lower()
        if ("拉伸应力" in joined and "最大值" in joined) or ("tensile stress" in lowered and "modulus" in lowered):
            return index
    return None


def _find_scalar_value_row(rows: list[list[str]], scalar_header_index: int) -> list[str] | None:
    for index in range(scalar_header_index + 1, min(len(rows), scalar_header_index + 6)):
        row = rows[index]
        numeric_count = sum(_parse_float(cell) is not None for cell in row)
        if numeric_count >= 4:
            return row
    return None


def _extract_scalar_value(
    headers: list[str],
    values: list[str],
    *,
    primary_keywords: tuple[str, ...],
    fallback_keywords: tuple[tuple[str, ...], ...],
) -> float | None:
    keyword_sets = (primary_keywords,) + fallback_keywords
    for keywords in keyword_sets:
        for index, header in enumerate(headers):
            if _cell_contains_all(header, keywords):
                if index < len(values):
                    return _parse_float(values[index])
    return None


def _extract_curve_dataframe(rows: list[list[str]], *, start_index: int) -> pd.DataFrame:
    curve_header_index = _find_curve_header_index(rows, start_index)
    if curve_header_index is None:
        return pd.DataFrame(columns=["x", "y"])

    header_row = rows[curve_header_index]
    strain_index = _find_curve_column_index(
        header_row,
        required_keywords=(("拉伸应变", "位移"), ("tensile strain",), ("strain",)),
        forbidden_keywords=("断裂", "break"),
    )
    stress_index = _find_curve_column_index(
        header_row,
        required_keywords=(("拉伸应力",), ("tensile stress",), ("stress",)),
        forbidden_keywords=("断裂", "break"),
    )
    if strain_index is None or stress_index is None:
        return pd.DataFrame(columns=["x", "y"])

    strain_values: list[float] = []
    stress_values: list[float] = []
    for row in rows[curve_header_index + 2 :]:
        if max(strain_index, stress_index) >= len(row):
            continue
        strain = _parse_float(row[strain_index])
        stress = _parse_float(row[stress_index])
        if strain is None or stress is None:
            continue
        strain_values.append(strain)
        stress_values.append(stress)

    if not strain_values:
        return pd.DataFrame(columns=["x", "y"])

    curve = pd.DataFrame({"x": strain_values, "y": stress_values})
    curve = curve.dropna(subset=["x", "y"]).sort_values("x")
    return curve.reset_index(drop=True)


def _find_curve_header_index(rows: list[list[str]], start_index: int) -> int | None:
    for index in range(start_index, len(rows)):
        joined = ",".join(_clean_cell(cell) for cell in rows[index])
        lowered = joined.lower()
        has_curve_axes = ("拉伸应变" in joined and "拉伸应力" in joined) or (
            "tensile strain" in lowered and "stress" in lowered
        )
        has_curve_context = any(
            marker in joined or marker in lowered
            for marker in ("位移", "时间", "displacement", "time")
        )
        if has_curve_axes and has_curve_context:
            return index
    return None


def _find_curve_column_index(
    header_row: list[str],
    *,
    required_keywords: tuple[tuple[str, ...], ...],
    forbidden_keywords: tuple[str, ...] = (),
) -> int | None:
    for index, cell in enumerate(header_row):
        normalized = _clean_cell(cell)
        lowered = normalized.lower()
        if any(keyword.lower() in lowered for keyword in forbidden_keywords):
            continue
        for keywords in required_keywords:
            if all(keyword.lower() in lowered for keyword in keywords):
                return index
            if all(keyword in normalized for keyword in keywords):
                return index
    return None


def _build_summary_dataframe(samples: list[TensileRawSample]) -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "Filename": sample.filename,
                "Strength (MPa)": sample.strength,
                "Modulus (MPa)": sample.modulus,
                "Elongation (%)": sample.elongation,
            }
            for sample in samples
        ]
    )


def _representative_index(summary_df: pd.DataFrame) -> int:
    if summary_df.empty:
        raise ValueError("没有可用的重复样统计结果。")
    mean_values = summary_df.mean(numeric_only=True)
    std_values = summary_df.std(numeric_only=True)
    scores = pd.Series(0.0, index=summary_df.index, dtype=float)
    numeric_columns = summary_df.select_dtypes(include=[np.number]).columns
    for column in numeric_columns:
        std_value = std_values[column]
        if pd.notna(std_value) and float(std_value) > 0:
            scores += ((summary_df[column] - mean_values[column]) / std_value) ** 2
    representative_index = scores.idxmin()
    return int(representative_index)


def _metric_summaries(summary_df: pd.DataFrame) -> tuple[TensileMetricSummary, ...]:
    mean_values = summary_df.mean(numeric_only=True)
    std_values = summary_df.std(numeric_only=True)
    summaries: list[TensileMetricSummary] = []
    for label, unit, _, _ in METRIC_SPECS:
        column_name = f"{label} ({unit})"
        mean_value = mean_values.get(column_name)
        std_value = std_values.get(column_name)
        summaries.append(
            TensileMetricSummary(
                label=label,
                unit=unit,
                mean=float(mean_value) if pd.notna(mean_value) else None,
                std=float(std_value) if pd.notna(std_value) else None,
            )
        )
    return tuple(summaries)


def _workbook_sheets(
    samples: list[TensileRawSample],
    summary_df: pd.DataFrame,
    representative_sample: TensileRawSample,
    group_name: str,
    metrics: tuple[TensileMetricSummary, ...],
) -> list[tuple[str, pd.DataFrame]]:
    sheets: list[tuple[str, pd.DataFrame]] = [
        (
            REPRESENTATIVE_CURVE_SHEET,
            _curve_table_dataframe(
                (
                    (
                        f"{group_name} representative",
                        representative_sample.curve,
                    ),
                )
            ),
        ),
        (
            ALL_CURVES_SHEET,
            _curve_table_dataframe((_sample_name(sample), sample.curve) for sample in samples),
        ),
        (
            SUMMARY_SHEET,
            _summary_sheet_dataframe(summary_df, representative_sample.filename, metrics),
        ),
        (
            ALL_SPECIMENS_SHEET,
            _plain_table_dataframe(summary_df),
        ),
    ]
    for metric in metrics:
        column_name = f"{metric.label} ({metric.unit})"
        sheets.append(
            (
                f"{metric.label}_Replicates",
                _replicate_table_dataframe(
                    group_name=group_name,
                    value_label=metric.label,
                    value_unit=metric.unit,
                    values=summary_df[column_name].dropna().tolist(),
                ),
            )
        )
    return sheets


def _curve_table_dataframe(series_pairs: Iterable[tuple[str, pd.DataFrame]]) -> pd.DataFrame:
    normalized_pairs = [(sample_name, dataframe.reset_index(drop=True)) for sample_name, dataframe in series_pairs]
    if not normalized_pairs:
        return pd.DataFrame()

    axis_row: list[object] = []
    unit_row: list[object] = []
    sample_row: list[object] = []
    max_rows = max(len(dataframe.index) for _, dataframe in normalized_pairs)
    for sample_name, _ in normalized_pairs:
        axis_row.extend(["Strain", "Stress"])
        unit_row.extend(["%", "MPa"])
        sample_row.extend([sample_name, sample_name])

    rows: list[list[object]] = [axis_row, unit_row, sample_row]
    for row_index in range(max_rows):
        row: list[object] = []
        for _, dataframe in normalized_pairs:
            if row_index < len(dataframe.index):
                x_value = dataframe.iloc[row_index]["x"]
                y_value = dataframe.iloc[row_index]["y"]
                row.extend([float(x_value), float(y_value)])
            else:
                row.extend(["", ""])
        rows.append(row)
    return pd.DataFrame(rows)


def _replicate_table_dataframe(
    *,
    group_name: str,
    value_label: str,
    value_unit: str,
    values: Iterable[float],
) -> pd.DataFrame:
    rows: list[list[object]] = [
        [value_label],
        [group_name],
        [value_unit],
    ]
    rows.extend([[float(value)] for value in values if pd.notna(value)])
    return pd.DataFrame(rows)


def _summary_sheet_dataframe(
    summary_df: pd.DataFrame,
    representative_filename: str,
    metrics: tuple[TensileMetricSummary, ...],
) -> pd.DataFrame:
    rows: list[list[object]] = [
        ["Item", "Unit", "Mean", "Std", "Representative File"],
    ]
    for index, metric in enumerate(metrics):
        rows.append(
            [
                metric.label,
                metric.unit,
                metric.mean,
                metric.std,
                representative_filename if index == 0 else "",
            ]
        )
    rows.append([])
    rows.append(["Specimens", len(summary_df.index), "", "", ""])
    return pd.DataFrame(rows)


def _plain_table_dataframe(dataframe: pd.DataFrame) -> pd.DataFrame:
    rows = [list(dataframe.columns)]
    rows.extend(dataframe.where(pd.notna(dataframe), "").values.tolist())
    return pd.DataFrame(rows)


def _sample_name(sample: TensileRawSample) -> str:
    return sample.source_path.stem


def _cell_contains_all(cell: str, keywords: tuple[str, ...]) -> bool:
    normalized = _clean_cell(cell)
    lowered = normalized.lower()
    return all(keyword.lower() in lowered for keyword in keywords) or all(keyword in normalized for keyword in keywords)


def _clean_cell(cell: object) -> str:
    return str(cell).replace('"', "").strip()


def _parse_float(value: object) -> float | None:
    text = _clean_cell(value)
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None
