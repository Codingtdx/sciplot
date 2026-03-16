from __future__ import annotations

import math
from contextlib import suppress
from pathlib import Path

import pandas as pd

from src.data_loader import CurveSeries
from src.plot_contract import default_options_for_template, default_size_for_template
from src.rendering.cache import (
    load_curve_table_cached,
    load_heatmap_table_cached,
    load_replicate_table_cached,
    load_stress_relaxation_metric_cached,
    read_raw_table_cached,
)
from src.rendering.common import looks_like_tensile_curve, to_curve_series
from src.rendering.models import InputInspection, Recommendation, TemplateName
from src.text_normalization import canonicalize_token, normalize_label
from src.wide_nmr import wide_nmr_sidecar_path


def clean_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and pd.isna(value):
        return ""
    return str(value).strip()


def model_label(model: str) -> str:
    labels = {
        "curve_table": "成对曲线表 (curve_table)",
        "tensile_curve": "拉伸应力-应变曲线 (tensile_curve)",
        "replicate_table": "重复值宽表 (replicate_table)",
        "heatmap_table": "热图长表 (xyz_long_table)",
        "frequency_sweep": "频率扫描导出表",
        "temperature_sweep": "温度扫描导出表",
        "stress_relaxation": "应力松弛导出表",
    }
    return labels.get(model, model)


def point_line_bundle_signals(bundle: str) -> tuple[str, ...]:
    if bundle == "frequency_sweep":
        return (
            "检测到 5 列一组的流变导出结构。",
            "首个横轴字段是 Angular Frequency / ω。",
            "同组包含 Storage/Loss Modulus、Loss Factor、Complex Viscosity。",
        )
    if bundle == "temperature_sweep":
        return (
            "检测到 5 列一组的流变导出结构。",
            "首个横轴字段是 Temperature。",
            "同组包含 Storage/Loss Modulus、Loss Factor、Complex Viscosity。",
        )
    if bundle == "stress_relaxation":
        return (
            "检测到 4 列一组的应力松弛导出结构。",
            "首个横轴字段是 Time。",
            "同组包含 σ/σ₀ 指标。",
        )
    return ()


def axis_dynamic_range(
    series_list: list[CurveSeries],
    axis: str,
) -> tuple[float, float, bool] | None:
    positive_min: float | None = None
    positive_max: float | None = None
    all_positive = True

    for series in series_list:
        values = pd.to_numeric(series.data[axis], errors="coerce").dropna()
        if values.empty:
            continue
        positive = values[values > 0]
        if positive.empty:
            all_positive = False
            continue
        if len(positive) != len(values):
            all_positive = False
        current_min = float(positive.min())
        current_max = float(positive.max())
        positive_min = current_min if positive_min is None else min(positive_min, current_min)
        positive_max = current_max if positive_max is None else max(positive_max, current_max)

    if positive_min is None or positive_max is None or positive_max <= 0:
        return None

    ratio = positive_max / positive_min if positive_min > 0 else 0.0
    orders = math.log10(ratio) if ratio > 0 else 0.0
    return ratio, orders, all_positive


def recommend_axis_scale(
    series_list: list[CurveSeries],
    axis: str,
    *,
    label: str,
    min_orders: float,
) -> tuple[str, str]:
    summary = axis_dynamic_range(series_list, axis)
    if summary is None:
        return "linear", f"{label} 没有稳定的正值跨度，保留 linear。"

    _, orders, all_positive = summary
    if all_positive and orders >= min_orders:
        return "log", f"{label} 跨度约 {orders:.1f} 个数量级，默认改为 log。"
    if not all_positive:
        return "linear", f"{label} 含非正值或贴近 0 的区段，保留 linear。"
    return "linear", f"{label} 变化约 {orders:.1f} 个数量级，保留 linear 更易读。"


def recommend_curve_scales(series_list: list[CurveSeries]) -> tuple[str, str, tuple[str, ...]]:
    xscale, xsignal = recommend_axis_scale(
        series_list,
        "x",
        label="横轴",
        min_orders=2.0,
    )
    yscale, ysignal = recommend_axis_scale(
        series_list,
        "y",
        label="纵轴",
        min_orders=2.3,
    )
    return xscale, yscale, (xsignal, ysignal)


def recommendation(template: TemplateName, reason: str, **overrides: object) -> Recommendation:
    defaults = default_options_for_template(template)
    payload = {
        "template": template,
        "reason": reason,
        "size": defaults.get("size", default_size_for_template(template)),
        "xscale": defaults.get("xscale"),
        "yscale": defaults.get("yscale"),
        "reverse_x": defaults.get("reverse_x"),
        "baseline": defaults.get("baseline"),
        "show_colorbar": defaults.get("show_colorbar"),
        "style_preset": defaults.get("style_preset"),
        "palette_preset": defaults.get("palette_preset"),
        "use_sidecar": defaults.get("use_sidecar"),
    }
    payload.update(overrides)
    return Recommendation(**payload)


def detect_point_line_bundle(input_path: Path, sheet: str | int) -> str | None:
    try:
        raw = read_raw_table_cached(input_path, sheet).dropna(axis=1, how="all")
    except Exception:
        return None

    if raw.shape[0] < 3 or raw.shape[1] == 0:
        return None

    labels = [canonicalize_token(clean_text(value)) for value in raw.iloc[0].tolist()]
    normalized_labels = [normalize_label(clean_text(value)) for value in raw.iloc[0].tolist()]
    first_label = labels[0]

    if raw.shape[1] % 5 == 0 and {
        "storage modulus",
        "loss modulus",
        "loss factor",
        "complex viscosity",
    }.issubset(set(labels)):
        if first_label == "temperature":
            return "temperature_sweep"
        if first_label in {"angular frequency", "frequency", "ω"}:
            return "frequency_sweep"

    if raw.shape[1] % 4 == 0 and first_label == "time":
        if r"$\sigma/\sigma_0$" in normalized_labels:
            return "stress_relaxation"

    return None


def looks_like_nmr(series_list: list[CurveSeries]) -> bool:
    first = series_list[0]
    x_label = canonicalize_token(first.x_label)
    x_unit = clean_text(first.x_unit).lower()
    return x_label == "chemical shift" or "ppm" in x_unit


def looks_like_ftir(series_list: list[CurveSeries]) -> bool:
    first = series_list[0]
    x_label = canonicalize_token(first.x_label)
    x_unit = clean_text(first.x_unit).lower()
    return x_label == "wavenumber" or ("cm" in x_unit and ("-1" in x_unit or "^{-1}" in x_unit))


def looks_like_xrd(series_list: list[CurveSeries]) -> bool:
    first = series_list[0]
    x_label = canonicalize_token(first.x_label)
    y_label = canonicalize_token(first.y_label)
    y_unit = clean_text(first.y_unit).lower()
    return x_label in {"2theta", "2θ"} or ("count" in y_unit) or (x_label == "2 theta" and y_label == "intensity")


def looks_like_dsc(series_list: list[CurveSeries]) -> bool:
    first = series_list[0]
    y_label = canonicalize_token(first.y_label)
    return y_label == "heat flow"


def inspect_input_file(input_path: Path, sheet: str | int = 0) -> InputInspection:
    bundle = detect_point_line_bundle(input_path, sheet)
    if bundle == "frequency_sweep":
        return InputInspection(
            model=bundle,
            model_label=model_label(bundle),
            recommendation=recommendation(
                "point_line",
                "识别到频率扫描的 5 列一组流变导出表。",
                xscale="log",
                yscale="log",
                reverse_x=False,
            ),
            warnings=("将导出 4 张 PDF。",),
            signals=point_line_bundle_signals(bundle),
        )
    if bundle == "temperature_sweep":
        return InputInspection(
            model=bundle,
            model_label=model_label(bundle),
            recommendation=recommendation(
                "point_line",
                "识别到温度扫描的 5 列一组流变导出表。",
                size="120x55",
                xscale="linear",
                yscale="log",
                reverse_x=False,
            ),
            warnings=("将导出 2 张 PDF。",),
            signals=point_line_bundle_signals(bundle),
        )
    if bundle == "stress_relaxation":
        relaxation_series = to_curve_series(
            load_stress_relaxation_metric_cached(input_path, "σ/σ₀", sheet)
        )
        xscale, yscale, range_signals = recommend_curve_scales(relaxation_series)
        return InputInspection(
            model=bundle,
            model_label=model_label(bundle),
            recommendation=recommendation(
                "point_line",
                "识别到应力松弛的 4 列一组导出表。",
                xscale=xscale,
                yscale=yscale,
                reverse_x=False,
            ),
            signals=point_line_bundle_signals(bundle) + range_signals,
        )

    with suppress(Exception):
        load_heatmap_table_cached(input_path, sheet)
        return InputInspection(
            model="heatmap_table",
            model_label=model_label("heatmap_table"),
            recommendation=recommendation(
                "heatmap",
                "识别到 X / Y / Z 角色列的热图长表。",
                show_colorbar=True,
            ),
            signals=(
                "检测到 3 列输入结构。",
                "第 1 行明确写出了 X、Y、Z 角色列。",
                "这类数据最适合直接转成热图矩阵。",
            ),
        )

    try:
        series_list = load_curve_table_cached(input_path, sheet)
    except Exception as exc:
        try:
            groups = load_replicate_table_cached(input_path, sheet)
        except Exception:
            raise ValueError(
                "无法识别当前文件。请整理成 curve_table、replicate_table、"
                "heatmap xyz_long_table，或使用当前支持的流变导出表。"
            ) from exc
        warnings: list[str] = []
        if len(groups) >= 6:
            warnings.append("组数较多，横轴标签可能会自动换行或缩小字号。")
        return InputInspection(
            model="replicate_table",
            model_label=model_label("replicate_table"),
            recommendation=recommendation(
                "box",
                "识别到共享 y 轴名 + 样品名 + 单位 + 重复值的统计表。",
            ),
            warnings=tuple(warnings),
            signals=(
                "A1 提供了共享 y 轴名。",
                "第 2 行是分组名，第 3 行是单位。",
                "第 4 行起是重复值，适合统计图。",
            ),
        )

    if wide_nmr_sidecar_path(input_path).exists():
        return InputInspection(
            model="curve_table",
            model_label=model_label("curve_table"),
            recommendation=recommendation(
                "segmented_stacked_curve",
                "识别到普通曲线表，并在同目录发现 wide_nmr sidecar。",
                reverse_x=True,
                baseline="linear_endpoints",
                use_sidecar=True,
            ),
            signals=(
                "检测到标准成对曲线表。",
                "同目录存在 .wide_nmr.toml sidecar。",
                "这类输入更适合分段堆积曲线图。",
            ),
        )
    if looks_like_nmr(series_list):
        return InputInspection(
            model="curve_table",
            model_label=model_label("curve_table"),
            recommendation=recommendation(
                "stacked_curve",
                "根据 Chemical shift / ppm 判断为 NMR 风格谱图。",
                reverse_x=True,
                baseline="linear_endpoints",
            ),
            signals=(
                "横轴名称或单位命中了 Chemical shift / ppm。",
                "多条样品曲线更适合堆积展示。",
                "推荐反向 x 轴和轻量基线修正。",
            ),
        )
    if looks_like_ftir(series_list):
        return InputInspection(
            model="curve_table",
            model_label=model_label("curve_table"),
            recommendation=recommendation(
                "stacked_curve",
                "根据 Wavenumber / cm^-1 判断为 FTIR 风格谱图。",
                reverse_x=True,
                baseline="none",
            ),
            signals=(
                "横轴名称或单位命中了 Wavenumber / cm⁻¹。",
                "多条样品曲线更适合堆积展示。",
                "推荐反向 x 轴，不强行做基线修正。",
            ),
        )
    if looks_like_dsc(series_list):
        return InputInspection(
            model="curve_table",
            model_label=model_label("curve_table"),
            recommendation=recommendation(
                "stacked_curve",
                "根据 Heat flow 标签判断为 DSC 风格堆积图。",
                reverse_x=False,
                baseline="linear_endpoints",
            ),
            signals=(
                "y 轴名称命中了 Heat flow。",
                "这类热分析曲线更适合堆积展示。",
                "推荐线性端点基线修正。",
            ),
        )
    if looks_like_xrd(series_list):
        return InputInspection(
            model="curve_table",
            model_label=model_label("curve_table"),
            recommendation=recommendation(
                "stacked_curve",
                "根据 2theta / counts / intensity 判断为 XRD 风格谱图。",
                reverse_x=False,
                baseline="none",
            ),
            signals=(
                "横轴或单位命中了 2theta / counts / intensity。",
                "多条样品曲线更适合堆积展示。",
                "推荐保持正向 x 轴。",
            ),
        )
    if looks_like_tensile_curve(series_list):
        return InputInspection(
            model="tensile_curve",
            model_label=model_label("tensile_curve"),
            recommendation=recommendation(
                "curve",
                "根据应变/伸长率横轴和应力纵轴判断为拉伸曲线。",
                size="60x55",
                xscale="linear",
                yscale="linear",
                reverse_x=False,
            ),
            signals=(
                "横轴标签或单位命中了 strain / elongation / %。",
                "纵轴标签或单位命中了 stress / MPa。",
                "拉伸曲线默认固定使用线性 x/y 坐标。",
            ),
        )
    xscale, yscale, range_signals = recommend_curve_scales(series_list)
    return InputInspection(
        model="curve_table",
        model_label=model_label("curve_table"),
        recommendation=recommendation(
            "curve",
            "识别到普通成对曲线表，默认推荐普通曲线图。",
            xscale=xscale,
            yscale=yscale,
        ),
        signals=(
            "检测到标准成对曲线表。",
            "当前标签和单位不明显属于谱图或流变导出表。",
            "默认先按普通曲线图处理。",
            *range_signals,
        ),
    )
