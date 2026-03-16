from __future__ import annotations

from pathlib import Path

from src.data_loader import CurveSeries, ReplicateGroup
from src.plot_contract import validation_rule
from src.rendering.cache import (
    load_frequency_sweep_metrics_cached,
    load_replicate_table_cached,
    load_stress_relaxation_metric_cached,
    load_temperature_sweep_metrics_cached,
)
from src.rendering.constants import (
    FREQUENCY_CURVE_OUTPUTS,
    FREQUENCY_OUTPUTS,
    STRESS_RELAXATION_CURVE_OUTPUT,
    STRESS_RELAXATION_OUTPUT,
    TEMPERATURE_CURVE_OUTPUTS,
    TEMPERATURE_OUTPUTS,
)
from src.rendering.models import RenderOptions, TemplateName
from src.rheology_loader import RheologySeries
from src.text_normalization import canonicalize_token, normalize_label, slugify_label
from src.wide_nmr import WideNMRConfig, WideNMRSegment, load_wide_nmr_config, wide_nmr_sidecar_path

TENSILE_LINEAR_SCALE_ERROR = "拉伸曲线必须使用线性坐标轴，不支持 log x / y。"


def humanize_preflight_exception(exc: Exception) -> str:
    message = str(exc)

    if "Missing segmented_stacked_curve sidecar config" in message:
        return "当前图类型需要同目录 sidecar 配置文件（用于断轴、高亮和编号），但程序没有找到它。"
    if "must include at least" in message:
        return "表格行数不够。请至少保留名称行、单位行、样品名行，以及一行数据。"
    if "axis label row" in message:
        return "第 1 行缺少名称行。请在这一行写 X/Y 名称。"
    if "unit row" in message:
        return "第 2 行缺少单位行。请在这一行写单位。"
    if "sample row" in message:
        return "第 3 行缺少样品名行。请在这一行写样品名。"
    if "group row" in message:
        return "第 2 行缺少分组名。请在这一行写各组名称。"
    if "Curve table must contain an even number of columns arranged in X/Y pairs." in message or "X/Y pairs" in message:
        return "曲线表的列数不是成对的。请按 X/Y、X/Y 的方式整理列。"
    if "matching X/Y numeric data" in message:
        return "某一组 X/Y 列只有一边是有效数字。请检查这两列是否成对、是否都填了数值。"
    if "contains incomplete X/Y rows" in message:
        return "某一组 X/Y 数据里有不完整的行。请删掉空半行，或把这一组补完整。"
    if "contains non-numeric values in the data region" in message:
        return "数据区里有非数字内容。请把说明文字移出数据区，只保留数值。"
    if "Sample names in columns" in message:
        return "同一组 X/Y 两列的样品名不一致。请让这一对列的样品名完全相同。"
    if "contains non-positive x values" in message:
        return "当前选择了 log x 轴，但数据里有小于等于 0 的 x 值。请改用 linear，或先清理这些值。"
    if "contains non-positive y values" in message:
        return "当前选择了 log y 轴，但数据里有小于等于 0 的 y 值。请改用 linear，或先清理这些值。"
    if "contains no numeric replicate values" in message:
        return "某一列没有可用的重复值数字。请删掉空列，或把这一列补成纯数值。"
    if "No valid replicate columns found" in message:
        return "没有找到有效的重复值列。请确认第 4 行起确实是数值。"
    if "No valid X/Y series found" in message:
        return "没有找到有效的 X/Y 曲线。请确认第 4 行起至少有一组完整数值。"
    if "Heatmap table must contain exactly three columns: X, Y, Z." in message:
        return "热图表必须正好有三列，并且分别对应 X、Y、Z。"
    if "Heatmap table role row must contain exactly X, Y and Z." in message:
        return "热图表第 1 行必须明确写出 X、Y、Z 三个角色列。"
    if "does not contain any numeric Z values" in message:
        return "热图表的 Z 列没有读到有效数字。请检查第 4 行起的数据。"
    if "does not contain any valid X/Y coordinates" in message:
        return "热图表的 X/Y 坐标列为空或无效。请检查第 4 行起的数据。"
    if "频率扫描缺少指标数据" in message:
        return f"{message} 请确认这一组导出列是否完整。"
    if "温度扫描缺少指标数据" in message:
        return f"{message} 请确认这一组导出列是否完整。"
    if "应力松弛表中没有读到 σ/σ₀ 曲线" in message:
        return "应力松弛表里没有读到 σ/σ₀ 曲线。请确认导出文件包含这一列。"
    if "统计表没有有效分组" in message:
        return "统计表没有读到有效分组。请确认第 2 行是组名，第 4 行起是重复值。"
    return message


def style_preflight_warnings(options: RenderOptions) -> tuple[str, ...]:
    if options.style_preset == "nature":
        return ("当前使用的是 Nature 风格 preset：它优先遵循官方图像约束。",)
    return ()


def to_curve_series(series_list: list[RheologySeries]) -> list[CurveSeries]:
    return [
        CurveSeries(
            sample=series.sample,
            x_label=series.x_label,
            y_label=series.y_label,
            x_unit=series.x_unit,
            y_unit=series.y_unit,
            data=series.data,
        )
        for series in series_list
    ]


def validate_series_scales(series_list: list[CurveSeries], *, xscale: str, yscale: str) -> None:
    if looks_like_tensile_curve(series_list) and (xscale != "linear" or yscale != "linear"):
        raise ValueError(TENSILE_LINEAR_SCALE_ERROR)
    if xscale == "log":
        for series in series_list:
            if (series.data["x"] <= 0).any():
                raise ValueError(f"Series {series.sample!r} contains non-positive x values and cannot use log x-axis.")
    if yscale == "log":
        for series in series_list:
            if (series.data["y"] <= 0).any():
                raise ValueError(f"Series {series.sample!r} contains non-positive y values and cannot use log y-axis.")


def looks_like_tensile_curve(series_list: list[CurveSeries]) -> bool:
    if not series_list:
        return False
    first = series_list[0]
    x_label = canonicalize_token(normalize_label(first.x_label))
    y_label = canonicalize_token(normalize_label(first.y_label))
    x_unit = canonicalize_token(first.x_unit)
    y_unit = canonicalize_token(first.y_unit)

    x_label_match = x_label in {"strain", "elongation"} or "strain" in x_label or "elongation" in x_label
    y_label_match = y_label in {"stress", "σ"} or "stress" in y_label
    x_unit_match = x_unit in {"%", "percent"}
    y_unit_match = y_unit in {"pa", "kpa", "mpa", "gpa"}
    return x_label_match and y_label_match and (x_unit_match or y_unit_match)


def load_rheology_bundle_series(
    bundle: str,
    input_path: Path,
    sheet: str | int,
) -> dict[str, list[CurveSeries]]:
    if bundle == "frequency_sweep":
        return {
            metric_name: to_curve_series(series_list)
            for metric_name, series_list in load_frequency_sweep_metrics_cached(input_path, sheet).items()
        }
    if bundle == "temperature_sweep":
        return {
            metric_name: to_curve_series(series_list)
            for metric_name, series_list in load_temperature_sweep_metrics_cached(input_path, sheet).items()
        }
    if bundle == "stress_relaxation":
        return {
            "sigma_over_sigma0": to_curve_series(
                load_stress_relaxation_metric_cached(input_path, "σ/σ₀", sheet)
            ),
        }
    raise ValueError(f"Unsupported rheology bundle: {bundle}")


def rheology_output_filenames(
    bundle: str,
    template: TemplateName,
) -> dict[str, str]:
    if template == "point_line":
        if bundle == "frequency_sweep":
            return FREQUENCY_OUTPUTS
        if bundle == "temperature_sweep":
            return TEMPERATURE_OUTPUTS
        if bundle == "stress_relaxation":
            return {"sigma_over_sigma0": STRESS_RELAXATION_OUTPUT}
    if template == "curve":
        if bundle == "frequency_sweep":
            return FREQUENCY_CURVE_OUTPUTS
        if bundle == "temperature_sweep":
            return TEMPERATURE_CURVE_OUTPUTS
        if bundle == "stress_relaxation":
            return {"sigma_over_sigma0": STRESS_RELAXATION_CURVE_OUTPUT}
    raise ValueError(f"Unsupported bundle/template combination: {bundle} / {template}")


def validate_rheology_bundle_scales(
    bundle: str,
    input_path: Path,
    sheet: str | int,
    *,
    xscale: str,
    yscale: str,
) -> dict[str, list[CurveSeries]]:
    metric_series = load_rheology_bundle_series(bundle, input_path, sheet)
    bundle_label = {
        "frequency_sweep": "频率扫描",
        "temperature_sweep": "温度扫描",
        "stress_relaxation": "应力松弛",
    }.get(bundle, bundle)
    for metric_name, series_list in metric_series.items():
        if not series_list:
            if bundle == "stress_relaxation":
                raise ValueError("应力松弛表中没有读到 σ/σ₀ 曲线。")
            raise ValueError(f"{bundle_label}缺少指标数据：{metric_name}")
        validate_series_scales(series_list, xscale=xscale, yscale=yscale)
    return metric_series


def predict_bar_box_slug(groups: list[ReplicateGroup]) -> str:
    return slugify_label(groups[0].value_label if groups else "value")


def preview_output_filenames(
    template: TemplateName,
    input_path: Path,
    sheet: str | int,
    bundle: str | None,
) -> tuple[str, ...]:
    if template in {"point_line", "curve"} and bundle in {
        "frequency_sweep",
        "temperature_sweep",
        "stress_relaxation",
    }:
        return tuple(rheology_output_filenames(bundle, template).values())
    if template == "point_line":
        return (f"{input_path.stem}_point_line.pdf",)
    if template == "curve":
        return (f"{input_path.stem}_curve.pdf",)
    if template == "stacked_curve":
        return (f"{input_path.stem}_stacked_curve.pdf",)
    if template == "segmented_stacked_curve":
        return (f"{input_path.stem}_segmented_stacked_curve.pdf",)
    if template == "scatter":
        return (f"{input_path.stem}_scatter.pdf",)
    if template == "heatmap":
        return (f"{input_path.stem}_heatmap.pdf",)
    if template in {"bar", "box", "violin"}:
        groups = load_replicate_table_cached(input_path, sheet)
        slug = predict_bar_box_slug(groups)
        return (f"{slug}_{template}.pdf",)
    return ()


def build_default_segmented_config(series_list: list[CurveSeries]) -> WideNMRConfig:
    x_min = min(float(series.data["x"].min()) for series in series_list)
    x_max = max(float(series.data["x"].max()) for series in series_list)
    return WideNMRConfig(
        segments=(WideNMRSegment(x_min=x_min, x_max=x_max),),
        series_order=tuple(series.sample for series in series_list),
    )


def load_segmented_config(
    input_path: Path,
    series_list: list[CurveSeries],
    *,
    use_sidecar: bool | None,
) -> WideNMRConfig:
    sidecar_path = wide_nmr_sidecar_path(input_path)
    if use_sidecar is False:
        return build_default_segmented_config(series_list)
    if sidecar_path.exists():
        return load_wide_nmr_config(input_path)
    if use_sidecar:
        raise FileNotFoundError(f"Missing segmented_stacked_curve sidecar config: {sidecar_path}")
    return build_default_segmented_config(series_list)


def append_multi_output_warning(warnings: list[str], preview_names: tuple[str, ...]) -> None:
    if len(preview_names) > 1:
        warnings.append(
            f"{validation_rule('multi_output_bundle_notice').description} 当前会导出 {len(preview_names)} 张 PDF。"
        )


__all__ = [
    "append_multi_output_warning",
    "humanize_preflight_exception",
    "load_segmented_config",
    "load_rheology_bundle_series",
    "looks_like_tensile_curve",
    "predict_bar_box_slug",
    "preview_output_filenames",
    "rheology_output_filenames",
    "style_preflight_warnings",
    "TENSILE_LINEAR_SCALE_ERROR",
    "to_curve_series",
    "validate_rheology_bundle_scales",
    "validate_series_scales",
]
