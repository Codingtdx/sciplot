from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import pandas as pd

from src import plot_style
from src.data_loader import CurveSeries, ReplicateGroup, load_curve_table, load_replicate_table, read_raw_table
from src.plot_style import save_pdf
from src.plotting_families.curve_family import plot_curves
from src.plotting_families.stats_family import plot_bar, plot_box
from src.rendering.io import ensure_input_path, list_sheet_names
from src.tensile_replicates import METRIC_SPECS, REPRESENTATIVE_CURVE_SHEET, SUMMARY_SHEET, TensileMetricSummary
from src.text_normalization import slugify_label

METRIC_NAMES = tuple(label for label, _, _, _ in METRIC_SPECS)
METRIC_UNITS = {label: unit for label, unit, _, _ in METRIC_SPECS}
REQUIRED_TENSILE_WORKBOOK_SHEETS = frozenset(
    {
        REPRESENTATIVE_CURVE_SHEET,
        SUMMARY_SHEET,
        *(f"{label}_Replicates" for label in METRIC_NAMES),
    }
)
COMPARISON_CURVE_FILENAME = "representative_curve_compare.pdf"
SUMMARY_COLUMNS = (
    "Label",
    "Workbook Path",
    "Specimens",
    "Representative File",
    "Strength Mean (MPa)",
    "Strength Std (MPa)",
    "Modulus Mean (MPa)",
    "Modulus Std (MPa)",
    "Elongation Mean (%)",
    "Elongation Std (%)",
)


@dataclass(frozen=True)
class TensileWorkbookSummary:
    workbook_path: Path
    label: str
    sheet_names: tuple[str, ...]
    sample_count: int
    representative_filename: str
    metrics: tuple[TensileMetricSummary, ...]


@dataclass(frozen=True)
class TensileComparisonExport:
    bundle_dir: Path
    comparison_workbook_path: Path
    labels: tuple[str, ...]
    outputs: tuple[Path, ...]


@dataclass(frozen=True)
class _LoadedTensileWorkbook:
    workbook_path: Path
    base_label: str
    sheet_names: tuple[str, ...]
    sample_count: int
    representative_filename: str
    representative_curve: CurveSeries
    metrics: tuple[TensileMetricSummary, ...]
    replicate_groups: dict[str, ReplicateGroup]


def inspect_tensile_workbook(workbook_path: str | Path) -> TensileWorkbookSummary:
    loaded = _load_tensile_workbook(workbook_path)
    return TensileWorkbookSummary(
        workbook_path=loaded.workbook_path,
        label=loaded.base_label,
        sheet_names=loaded.sheet_names,
        sample_count=loaded.sample_count,
        representative_filename=loaded.representative_filename,
        metrics=loaded.metrics,
    )


def export_tensile_comparison_bundle(
    workbook_paths: list[str | Path],
    output_dir: str | Path,
) -> TensileComparisonExport:
    loaded_sources = [_load_tensile_workbook(path) for path in workbook_paths]
    if len(loaded_sources) < 2:
        raise ValueError("拉伸对比至少需要 2 组已整理 workbook。")

    labels = _dedupe_labels(source.base_label for source in loaded_sources)
    _validate_metric_units(loaded_sources)
    _validate_curve_axes(loaded_sources)

    parent_dir = Path(output_dir).expanduser()
    parent_dir.mkdir(parents=True, exist_ok=True)
    bundle_dir = parent_dir / _bundle_dir_name(labels)
    bundle_dir.mkdir(parents=True, exist_ok=True)
    comparison_workbook_path = bundle_dir / f"{bundle_dir.name}.xlsx"

    with pd.ExcelWriter(comparison_workbook_path) as writer:
        _representative_curve_dataframe(loaded_sources, labels).to_excel(
            writer,
            sheet_name=REPRESENTATIVE_CURVE_SHEET,
            header=False,
            index=False,
        )
        for metric_name in METRIC_NAMES:
            _comparison_replicate_dataframe(
                metric_name,
                METRIC_UNITS[metric_name],
                loaded_sources,
                labels,
            ).to_excel(
                writer,
                sheet_name=f"{metric_name}_Replicates",
                header=False,
                index=False,
            )
        _comparison_summary_dataframe(loaded_sources, labels).to_excel(
            writer,
            sheet_name=SUMMARY_SHEET,
            header=False,
            index=False,
        )

    outputs = _export_comparison_figures(
        loaded_sources,
        labels,
        bundle_dir,
    )
    return TensileComparisonExport(
        bundle_dir=bundle_dir,
        comparison_workbook_path=comparison_workbook_path,
        labels=tuple(labels),
        outputs=tuple(outputs),
    )


def _load_tensile_workbook(workbook_path: str | Path) -> _LoadedTensileWorkbook:
    path = ensure_input_path(str(Path(workbook_path).expanduser()))
    sheet_names = tuple(list_sheet_names(path))
    if not sheet_names:
        raise ValueError(f"{path.name} 不是有效的 Excel workbook。")
    missing_sheets = sorted(REQUIRED_TENSILE_WORKBOOK_SHEETS.difference(sheet_names))
    if missing_sheets:
        joined = ", ".join(missing_sheets)
        raise ValueError(f"{path.name} 缺少必需工作表：{joined}")

    representative_curves = load_curve_table(path, sheet_name=REPRESENTATIVE_CURVE_SHEET)
    if len(representative_curves) != 1:
        raise ValueError(f"{path.name} 的 {REPRESENTATIVE_CURVE_SHEET} 必须恰好包含 1 组代表曲线。")

    sample_count, representative_filename = _summary_fields(path)

    metrics: list[TensileMetricSummary] = []
    replicate_groups: dict[str, ReplicateGroup] = {}
    for metric_name in METRIC_NAMES:
        try:
            groups = load_replicate_table(path, sheet_name=f"{metric_name}_Replicates")
        except Exception as exc:
            raise ValueError(f"{path.name} 的 {metric_name}_Replicates 不是有效重复值表：{exc}") from exc
        if len(groups) != 1:
            raise ValueError(f"{path.name} 的 {metric_name}_Replicates 必须恰好包含 1 组重复值。")
        group = groups[0]
        if group.data.empty:
            raise ValueError(f"{path.name} 的 {metric_name}_Replicates 没有有效重复值。")
        replicate_groups[metric_name] = group
        mean_value = group.data.mean()
        std_value = group.data.std(ddof=1)
        metrics.append(
            TensileMetricSummary(
                label=group.value_label or metric_name,
                unit=group.value_unit,
                mean=float(mean_value) if pd.notna(mean_value) else None,
                std=float(std_value) if pd.notna(std_value) else None,
            )
        )

    return _LoadedTensileWorkbook(
        workbook_path=path,
        base_label=_infer_workbook_label(path),
        sheet_names=sheet_names,
        sample_count=sample_count,
        representative_filename=representative_filename,
        representative_curve=representative_curves[0],
        metrics=tuple(metrics),
        replicate_groups=replicate_groups,
    )


def _summary_fields(path: Path) -> tuple[int, str]:
    raw = read_raw_table(path, sheet_name=SUMMARY_SHEET).fillna("")
    representative_filename = ""
    sample_count: int | None = None
    for row_index in range(raw.shape[0]):
        first_cell = _cell_text(raw.iloc[row_index, 0]) if raw.shape[1] > 0 else ""
        if raw.shape[1] > 4 and representative_filename == "":
            candidate = _cell_text(raw.iloc[row_index, 4])
            if candidate and candidate != "Representative File":
                representative_filename = candidate
        if first_cell == "Specimens":
            parsed = _parse_int(raw.iloc[row_index, 1] if raw.shape[1] > 1 else "")
            if parsed is not None:
                sample_count = parsed
    if sample_count is None:
        raise ValueError(f"{path.name} 的 Summary 缺少 Specimens 数量。")
    if representative_filename == "":
        raise ValueError(f"{path.name} 的 Summary 缺少 Representative File。")
    return sample_count, representative_filename


def _representative_curve_dataframe(
    loaded_sources: list[_LoadedTensileWorkbook],
    labels: list[str],
) -> pd.DataFrame:
    axis_row: list[object] = []
    unit_row: list[object] = []
    sample_row: list[object] = []
    max_rows = max(len(source.representative_curve.data.index) for source in loaded_sources)
    for label, source in zip(labels, loaded_sources, strict=True):
        axis_row.extend([source.representative_curve.x_label, source.representative_curve.y_label])
        unit_row.extend([source.representative_curve.x_unit, source.representative_curve.y_unit])
        sample_row.extend([label, label])

    rows: list[list[object]] = [axis_row, unit_row, sample_row]
    for row_index in range(max_rows):
        row: list[object] = []
        for source in loaded_sources:
            dataframe = source.representative_curve.data
            if row_index < len(dataframe.index):
                row.extend(
                    [
                        float(dataframe.iloc[row_index]["x"]),
                        float(dataframe.iloc[row_index]["y"]),
                    ]
                )
            else:
                row.extend(["", ""])
        rows.append(row)
    return pd.DataFrame(rows)


def _comparison_replicate_dataframe(
    metric_name: str,
    metric_unit: str,
    loaded_sources: list[_LoadedTensileWorkbook],
    labels: list[str],
) -> pd.DataFrame:
    max_rows = max(len(source.replicate_groups[metric_name].data.index) for source in loaded_sources)
    metric_header_row: list[object] = [metric_name]
    metric_header_row.extend([""] * max(0, len(loaded_sources) - 1))
    label_row: list[object] = []
    label_row.extend(labels)
    unit_row: list[object] = []
    unit_row.extend([metric_unit] * len(loaded_sources))
    rows: list[list[object]] = [
        metric_header_row,
        label_row,
        unit_row,
    ]
    for row_index in range(max_rows):
        row: list[object] = []
        for source in loaded_sources:
            values = source.replicate_groups[metric_name].data.reset_index(drop=True)
            if row_index < len(values.index):
                row.append(float(values.iloc[row_index]))
            else:
                row.append("")
        rows.append(row)
    return pd.DataFrame(rows)


def _comparison_summary_dataframe(
    loaded_sources: list[_LoadedTensileWorkbook],
    labels: list[str],
) -> pd.DataFrame:
    header_row: list[object] = list(SUMMARY_COLUMNS)
    rows: list[list[object]] = [header_row]
    for label, source in zip(labels, loaded_sources, strict=True):
        metric_map = {metric.label: metric for metric in source.metrics}
        strength = metric_map["Strength"]
        modulus = metric_map["Modulus"]
        elongation = metric_map["Elongation"]
        rows.append(
            [
                label,
                str(source.workbook_path),
                source.sample_count,
                source.representative_filename,
                strength.mean,
                strength.std,
                modulus.mean,
                modulus.std,
                elongation.mean,
                elongation.std,
            ]
        )
    return pd.DataFrame(rows)


def _export_comparison_figures(
    loaded_sources: list[_LoadedTensileWorkbook],
    labels: list[str],
    bundle_dir: Path,
) -> list[Path]:
    plot_style.apply_style(plot_style.DEFAULT_STYLE_PRESET, plot_style.DEFAULT_PALETTE_PRESET)

    outputs: list[Path] = []
    figures = []
    try:
        representative_series = [
            CurveSeries(
                sample=label,
                x_label=source.representative_curve.x_label,
                y_label=source.representative_curve.y_label,
                x_unit=source.representative_curve.x_unit,
                y_unit=source.representative_curve.y_unit,
                data=source.representative_curve.data.copy(deep=True),
            )
            for label, source in zip(labels, loaded_sources, strict=True)
        ]
        representative_figure, _ = plot_curves(
            representative_series,
            show_markers=False,
            axis_mode="auto_positive",
            width_mm=60.0,
            height_mm=55.0,
            xscale="linear",
            yscale="linear",
            reverse_x=False,
        )
        figures.append(representative_figure)
        outputs.append(save_pdf(representative_figure, bundle_dir / COMPARISON_CURVE_FILENAME))

        for metric_name in METRIC_NAMES:
            groups = [
                ReplicateGroup(
                    group=label,
                    value_label=source.replicate_groups[metric_name].value_label,
                    value_unit=source.replicate_groups[metric_name].value_unit,
                    data=source.replicate_groups[metric_name].data.copy(deep=True),
                )
                for label, source in zip(labels, loaded_sources, strict=True)
            ]
            metric_slug = slugify_label(metric_name)
            box_figure, _ = plot_box(
                groups,
                width_mm=60.0,
                height_mm=55.0,
            )
            figures.append(box_figure)
            outputs.append(save_pdf(box_figure, bundle_dir / f"{metric_slug}_box_compare.pdf"))

            bar_figure, _ = plot_bar(groups, width_mm=60.0, height_mm=55.0)
            figures.append(bar_figure)
            outputs.append(save_pdf(bar_figure, bundle_dir / f"{metric_slug}_bar_compare.pdf"))
    finally:
        for figure in figures:
            plt.close(figure)
    return outputs


def _validate_metric_units(loaded_sources: list[_LoadedTensileWorkbook]) -> None:
    for metric_name in METRIC_NAMES:
        expected_label = loaded_sources[0].replicate_groups[metric_name].value_label
        expected_unit = loaded_sources[0].replicate_groups[metric_name].value_unit
        for source in loaded_sources[1:]:
            group = source.replicate_groups[metric_name]
            if group.value_label != expected_label or group.value_unit != expected_unit:
                raise ValueError(
                    f"{metric_name} 的单位或标签不一致："
                    f"{loaded_sources[0].workbook_path.name} 与 {source.workbook_path.name} 无法直接对比。"
                )


def _validate_curve_axes(loaded_sources: list[_LoadedTensileWorkbook]) -> None:
    first_curve = loaded_sources[0].representative_curve
    for source in loaded_sources[1:]:
        curve = source.representative_curve
        if (
            curve.x_label != first_curve.x_label
            or curve.y_label != first_curve.y_label
            or curve.x_unit != first_curve.x_unit
            or curve.y_unit != first_curve.y_unit
        ):
            raise ValueError(
                f"{source.workbook_path.name} 的代表曲线坐标轴标签或单位与 "
                f"{loaded_sources[0].workbook_path.name} 不一致。"
            )


def _infer_workbook_label(path: Path) -> str:
    stem = path.stem.strip()
    if stem:
        return stem
    name = path.name.strip()
    return name or "Tensile Workbook"


def _dedupe_labels(labels: Any) -> list[str]:
    counts: dict[str, int] = {}
    deduped: list[str] = []
    for label in labels:
        text = str(label).strip() or "Tensile Workbook"
        counts[text] = counts.get(text, 0) + 1
        suffix = counts[text]
        deduped.append(text if suffix == 1 else f"{text} ({suffix})")
    return deduped


def _bundle_dir_name(labels: list[str]) -> str:
    slug = "_vs_".join(slugify_label(label) for label in labels) or "tensile_compare"
    base = f"{slug}_tensile_compare"
    if len(base) <= 96:
        return base
    digest = hashlib.sha1(base.encode("utf-8")).hexdigest()[:8]
    return f"{base[:87].rstrip('_')}_{digest}"


def _parse_int(value: object) -> int | None:
    try:
        return int(float(_cell_text(value)))
    except ValueError:
        return None


def _cell_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and pd.isna(value):
        return ""
    return str(value).strip()


__all__ = [
    "COMPARISON_CURVE_FILENAME",
    "TensileComparisonExport",
    "TensileWorkbookSummary",
    "export_tensile_comparison_bundle",
    "inspect_tensile_workbook",
]
