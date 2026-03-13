from __future__ import annotations

from contextlib import suppress
from pathlib import Path

import pandas as pd

from src.data_loader import CurveSeries
from src.plot_contract import default_options_for_template, default_size_for_template
from src.rendering.cache import (
    load_curve_table_cached,
    load_heatmap_table_cached,
    load_replicate_table_cached,
    read_raw_table_cached,
)
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
        return InputInspection(
            model=bundle,
            model_label=model_label(bundle),
            recommendation=recommendation(
                "point_line",
                "识别到应力松弛的 4 列一组导出表。",
                xscale="log",
                yscale="linear",
                reverse_x=False,
            ),
            signals=point_line_bundle_signals(bundle),
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
    return InputInspection(
        model="curve_table",
        model_label=model_label("curve_table"),
        recommendation=recommendation(
            "curve",
            "识别到普通成对曲线表，默认推荐普通曲线图。",
        ),
        signals=(
            "检测到标准成对曲线表。",
            "当前标签和单位不明显属于谱图或流变导出表。",
            "默认先按普通曲线图处理。",
        ),
    )
