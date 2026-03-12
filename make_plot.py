from __future__ import annotations

import argparse
from contextlib import suppress
from dataclasses import dataclass
import re
import sys
from pathlib import Path
from typing import Callable

from src import mpl_backend  # noqa: F401
import matplotlib.pyplot as plt
import pandas as pd

from src.data_loader import (
    CurveSeries,
    load_curve_table,
    load_heatmap_table,
    load_replicate_table,
    read_raw_table,
)
from src import plot_style
from src.plot_style import save_pdf
from src.plotting import (
    compute_shared_curve_x_layout,
    plot_bar,
    plot_box,
    plot_curves,
    plot_heatmap,
    plot_scatter,
    plot_violin,
    plot_wide_nmr,
)
from src.rheology_loader import (
    RheologySeries,
    load_frequency_sweep_metrics,
    load_stress_relaxation_metric,
    load_temperature_sweep_metrics,
)
from src.text_normalization import canonicalize_token, normalize_label, slugify_label
from src.wide_nmr import WideNMRConfig, WideNMRSegment, load_wide_nmr_config, wide_nmr_sidecar_path


TemplateName = str
OutputMode = str
RenderFn = Callable[[Path, str | int, "RenderOptions"], list["RenderedPlot"]]

WORKSPACE_OUTPUT_DIR = Path("figures") / "debug_outputs"

TEMPLATE_CHOICES = (
    "curve",
    "point_line",
    "stacked_curve",
    "segmented_stacked_curve",
    "bar",
    "box",
    "violin",
    "scatter",
    "heatmap",
)
SIZE_CHOICES = ("60x55", "120x55", "60x110")
STYLE_PRESET_CHOICES = plot_style.list_public_style_presets()
PALETTE_PRESET_CHOICES = plot_style.list_palette_presets()
SIZE_PRESETS: dict[str, tuple[float, float]] = {
    "60x55": (60.0, 55.0),
    "120x55": (120.0, 55.0),
    "60x110": (60.0, 110.0),
}
DEFAULT_SIZE_BY_TEMPLATE: dict[str, str] = {
    "curve": "60x55",
    "point_line": "60x55",
    "stacked_curve": "60x55",
    "segmented_stacked_curve": "60x110",
    "bar": "60x55",
    "box": "60x55",
    "violin": "60x55",
    "scatter": "60x55",
    "heatmap": "60x55",
}
LEGACY_TEMPLATE_HINTS = {
    "box_bar_plots": "请改用 `bar` 或 `box`，需要时再用 `violin`。",
    "frequency_sweep": "请改用 `point_line`。",
    "temperature_sweep": "请改用 `point_line`。",
    "stress_relaxation": "请改用 `point_line`。",
    "tensile_curve": "请改用 `curve` 或 `point_line`。",
    "ftir": "请改用 `stacked_curve`。",
    "nmr": "请改用 `stacked_curve`。",
    "wide_nmr": "请改用 `segmented_stacked_curve`。",
    "xrd": "请改用 `stacked_curve`。",
    "dsc": "请改用 `stacked_curve`。",
    "tga": "请改用 `curve`。",
    "dma": "请改用 `curve`。",
}

FREQUENCY_OUTPUTS = {
    "storage_modulus": "freq_storage_modulus.pdf",
    "loss_modulus": "freq_loss_modulus.pdf",
    "loss_factor": "freq_loss_factor.pdf",
    "complex_viscosity": "freq_complex_viscosity.pdf",
}
TEMPERATURE_OUTPUTS = {
    "storage_modulus": "temp_storage_modulus.pdf",
    "complex_viscosity": "temp_complex_viscosity.pdf",
}


@dataclass(frozen=True)
class RenderOptions:
    width_mm: float
    height_mm: float
    xscale: str
    yscale: str
    reverse_x: bool
    baseline: str
    show_colorbar: bool
    style_preset: str
    palette_preset: str
    use_sidecar: bool | None = None


@dataclass(frozen=True)
class TemplateRenderer:
    render: RenderFn


@dataclass(frozen=True)
class RenderedPlot:
    filename: str
    figure: plt.Figure


@dataclass(frozen=True)
class Recommendation:
    template: TemplateName
    reason: str
    size: str | None = None
    xscale: str | None = None
    yscale: str | None = None
    reverse_x: bool | None = None
    baseline: str | None = None
    show_colorbar: bool | None = None
    style_preset: str | None = None
    palette_preset: str | None = None
    use_sidecar: bool | None = None


@dataclass(frozen=True)
class InputInspection:
    model: str
    model_label: str
    recommendation: Recommendation
    warnings: tuple[str, ...] = ()
    signals: tuple[str, ...] = ()


@dataclass(frozen=True)
class PreflightResult:
    template: TemplateName
    warnings: tuple[str, ...]
    errors: tuple[str, ...]
    output_filenames: tuple[str, ...]


def _to_curve_series(series_list: list[RheologySeries]) -> list[CurveSeries]:
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


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate research plots from graph-family templates.",
    )
    parser.add_argument(
        "--template",
        required=True,
        help="Graph-family template to use.",
    )
    parser.add_argument(
        "--input",
        required=True,
        help="Path to the input data file.",
    )
    parser.add_argument(
        "--output-dir",
        help="Directory for generated PDF files. Overrides --output-mode when given.",
    )
    parser.add_argument(
        "--output-mode",
        choices=("workspace", "data_dir"),
        default="workspace",
        help="Default output location when --output-dir is not given. Default: workspace",
    )
    parser.add_argument(
        "--sheet",
        default="0",
        help="Excel sheet index or sheet name. Default: 0",
    )
    parser.add_argument(
        "--size",
        help="Panel size preset: 60x55, 120x55, or 60x110.",
    )
    parser.add_argument(
        "--xscale",
        choices=("linear", "log"),
        help="X-axis scale for curve-like plots.",
    )
    parser.add_argument(
        "--yscale",
        choices=("linear", "log"),
        help="Y-axis scale for curve-like plots.",
    )
    parser.add_argument(
        "--reverse-x",
        action="store_true",
        help="Reverse the x axis.",
    )
    parser.add_argument(
        "--baseline",
        choices=("none", "linear_endpoints"),
        help="Baseline mode for stacked curves.",
    )
    parser.add_argument(
        "--show-colorbar",
        dest="show_colorbar",
        action="store_true",
        help="Force colorbar on for heatmaps.",
    )
    parser.add_argument(
        "--hide-colorbar",
        dest="show_colorbar",
        action="store_false",
        help="Hide the colorbar for heatmaps.",
    )
    parser.add_argument(
        "--style-preset",
        default=plot_style.DEFAULT_STYLE_PRESET,
        help="Style preset. Default: default",
    )
    parser.add_argument(
        "--palette-preset",
        choices=PALETTE_PRESET_CHOICES,
        default=plot_style.DEFAULT_PALETTE_PRESET,
        help="Color palette preset. Default: colorblind_safe",
    )
    parser.set_defaults(show_colorbar=None)
    return parser.parse_args()


def _coerce_sheet(sheet: str) -> str | int:
    return int(sheet) if sheet.isdigit() else sheet


def _ensure_input_path(path_text: str) -> Path:
    path = Path(path_text).expanduser()
    if not path.exists():
        raise FileNotFoundError(f"Input file does not exist: {path}")
    if not path.is_file():
        raise FileNotFoundError(f"Input path is not a file: {path}")
    return path


def normalize_input_path_text(path_text: str) -> str:
    cleaned = path_text.strip()
    if cleaned.startswith(("'", '"')) and cleaned.endswith(("'", '"')) and len(cleaned) >= 2:
        cleaned = cleaned[1:-1]
    return re.sub(r"\\(.)", r"\1", cleaned)


def default_output_dir(input_path: Path) -> Path:
    return input_path.parent / "plots"


def resolve_output_dir(input_path: Path, output_dir: str | None, output_mode: OutputMode) -> Path:
    if output_dir:
        return Path(output_dir).expanduser()
    if output_mode == "data_dir":
        return default_output_dir(input_path)
    return WORKSPACE_OUTPUT_DIR


def _clean_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and pd.isna(value):
        return ""
    return str(value).strip()


def list_sheet_names(input_path: Path) -> list[str]:
    if input_path.suffix.lower() not in {".xlsx", ".xlsm"}:
        return []
    with pd.ExcelFile(input_path) as workbook:
        return list(workbook.sheet_names)


def _model_label(model: str) -> str:
    labels = {
        "curve_table": "成对曲线表 (curve_table)",
        "replicate_table": "重复值宽表 (replicate_table)",
        "heatmap_table": "热图长表 (xyz_long_table)",
        "frequency_sweep": "频率扫描导出表",
        "temperature_sweep": "温度扫描导出表",
        "stress_relaxation": "应力松弛导出表",
    }
    return labels.get(model, model)


def _point_line_bundle_signals(bundle: str) -> tuple[str, ...]:
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


def _humanize_preflight_exception(exc: Exception) -> str:
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


def _looks_like_nmr(series_list: list[CurveSeries]) -> bool:
    first = series_list[0]
    x_label = canonicalize_token(first.x_label)
    x_unit = _clean_text(first.x_unit).lower()
    return x_label == "chemical shift" or "ppm" in x_unit


def _looks_like_ftir(series_list: list[CurveSeries]) -> bool:
    first = series_list[0]
    x_label = canonicalize_token(first.x_label)
    x_unit = _clean_text(first.x_unit).lower()
    return x_label == "wavenumber" or ("cm" in x_unit and ("-1" in x_unit or "^{-1}" in x_unit))


def _looks_like_xrd(series_list: list[CurveSeries]) -> bool:
    first = series_list[0]
    x_label = canonicalize_token(first.x_label)
    y_label = canonicalize_token(first.y_label)
    y_unit = _clean_text(first.y_unit).lower()
    return x_label in {"2theta", "2θ"} or ("count" in y_unit) or (x_label == "2 theta" and y_label == "intensity")


def _looks_like_dsc(series_list: list[CurveSeries]) -> bool:
    first = series_list[0]
    y_label = canonicalize_token(first.y_label)
    return y_label == "heat flow"


def _validate_series_scales(series_list: list[CurveSeries], *, xscale: str, yscale: str) -> None:
    if xscale == "log":
        for series in series_list:
            if (series.data["x"] <= 0).any():
                raise ValueError(f"Series {series.sample!r} contains non-positive x values and cannot use log x-axis.")
    if yscale == "log":
        for series in series_list:
            if (series.data["y"] <= 0).any():
                raise ValueError(f"Series {series.sample!r} contains non-positive y values and cannot use log y-axis.")


def _predict_bar_box_slug(groups) -> str:
    return slugify_label(groups[0].value_label if groups else "value")


def _validate_template_name(template: str) -> str:
    if template in LEGACY_TEMPLATE_HINTS:
        raise ValueError(f"旧模板名 `{template}` 已停用。{LEGACY_TEMPLATE_HINTS[template]}")
    if template not in TEMPLATE_CHOICES:
        raise ValueError(f"Unknown template: {template}. Supported templates: {', '.join(TEMPLATE_CHOICES)}")
    return template


def _resolve_size(size_text: str | None, template: str) -> tuple[float, float]:
    chosen = size_text or DEFAULT_SIZE_BY_TEMPLATE[template]
    try:
        return SIZE_PRESETS[chosen]
    except KeyError as exc:
        raise ValueError(f"Invalid size preset: {chosen}. Supported sizes: {', '.join(SIZE_CHOICES)}") from exc


def _resolve_render_options(
    *,
    template: str,
    size: str | None = None,
    xscale: str | None = None,
    yscale: str | None = None,
    reverse_x: bool = False,
    baseline: str | None = None,
    show_colorbar: bool | None = None,
    style_preset: str = plot_style.DEFAULT_STYLE_PRESET,
    palette_preset: str = plot_style.DEFAULT_PALETTE_PRESET,
    use_sidecar: bool | None = None,
) -> RenderOptions:
    width_mm, height_mm = _resolve_size(size, template)
    return RenderOptions(
        width_mm=width_mm,
        height_mm=height_mm,
        xscale=xscale or "linear",
        yscale=yscale or "linear",
        reverse_x=reverse_x,
        baseline=baseline or "none",
        show_colorbar=True if show_colorbar is None else show_colorbar,
        style_preset=plot_style.normalize_style_preset(style_preset),
        palette_preset=palette_preset,
        use_sidecar=use_sidecar,
    )


def _style_preflight_warnings(options: RenderOptions) -> tuple[str, ...]:
    if options.style_preset == "nature":
        return ("当前使用的是 Nature 风格 preset：它优先遵循官方图像约束。",)
    return ()


def _detect_point_line_bundle(input_path: Path, sheet: str | int) -> str | None:
    try:
        raw = read_raw_table(input_path, sheet_name=sheet).dropna(axis=1, how="all")
    except Exception:
        return None

    if raw.shape[0] < 3 or raw.shape[1] == 0:
        return None

    labels = [canonicalize_token(_clean_text(value)) for value in raw.iloc[0].tolist()]
    normalized_labels = [normalize_label(_clean_text(value)) for value in raw.iloc[0].tolist()]
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


def inspect_input_file(input_path: Path, sheet: str | int = 0) -> InputInspection:
    bundle = _detect_point_line_bundle(input_path, sheet)
    if bundle == "frequency_sweep":
        return InputInspection(
            model=bundle,
            model_label=_model_label(bundle),
            recommendation=Recommendation(
                template="point_line",
                reason="识别到频率扫描的 5 列一组流变导出表。",
                size="60x55",
                xscale="log",
                yscale="log",
                reverse_x=False,
            ),
            warnings=("将导出 4 张 PDF。",),
            signals=_point_line_bundle_signals(bundle),
        )
    if bundle == "temperature_sweep":
        return InputInspection(
            model=bundle,
            model_label=_model_label(bundle),
            recommendation=Recommendation(
                template="point_line",
                reason="识别到温度扫描的 5 列一组流变导出表。",
                size="120x55",
                xscale="linear",
                yscale="log",
                reverse_x=False,
            ),
            warnings=("将导出 2 张 PDF。",),
            signals=_point_line_bundle_signals(bundle),
        )
    if bundle == "stress_relaxation":
        return InputInspection(
            model=bundle,
            model_label=_model_label(bundle),
            recommendation=Recommendation(
                template="point_line",
                reason="识别到应力松弛的 4 列一组导出表。",
                size="60x55",
                xscale="log",
                yscale="linear",
                reverse_x=False,
            ),
            signals=_point_line_bundle_signals(bundle),
        )

    with suppress(Exception):
        load_heatmap_table(input_path, sheet_name=sheet)
        return InputInspection(
            model="heatmap_table",
            model_label=_model_label("heatmap_table"),
            recommendation=Recommendation(
                template="heatmap",
                reason="识别到 X / Y / Z 角色列的热图长表。",
                size="60x55",
                show_colorbar=True,
            ),
            signals=(
                "检测到 3 列输入结构。",
                "第 1 行明确写出了 X、Y、Z 角色列。",
                "这类数据最适合直接转成热图矩阵。",
            ),
        )

    try:
        series_list = load_curve_table(input_path, sheet_name=sheet)
    except Exception as exc:
        try:
            groups = load_replicate_table(input_path, sheet_name=sheet)
        except Exception:
            raise ValueError(
                "无法识别当前文件。请整理成 curve_table、replicate_table、heatmap xyz_long_table，或使用当前支持的流变导出表。"
            ) from exc
        warnings: list[str] = []
        if len(groups) >= 6:
            warnings.append("组数较多，横轴标签可能会自动换行或缩小字号。")
        return InputInspection(
            model="replicate_table",
            model_label=_model_label("replicate_table"),
            recommendation=Recommendation(
                template="box",
                reason="识别到共享 y 轴名 + 样品名 + 单位 + 重复值的统计表。",
                size="60x55",
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
            model_label=_model_label("curve_table"),
            recommendation=Recommendation(
                template="segmented_stacked_curve",
                reason="识别到普通曲线表，并在同目录发现 wide_nmr sidecar。",
                size="60x110",
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
    if _looks_like_nmr(series_list):
        return InputInspection(
            model="curve_table",
            model_label=_model_label("curve_table"),
            recommendation=Recommendation(
                template="stacked_curve",
                reason="根据 Chemical shift / ppm 判断为 NMR 风格谱图。",
                size="60x55",
                reverse_x=True,
                baseline="linear_endpoints",
            ),
            signals=(
                "横轴名称或单位命中了 Chemical shift / ppm。",
                "多条样品曲线更适合堆积展示。",
                "推荐反向 x 轴和轻量基线修正。",
            ),
        )
    if _looks_like_ftir(series_list):
        return InputInspection(
            model="curve_table",
            model_label=_model_label("curve_table"),
            recommendation=Recommendation(
                template="stacked_curve",
                reason="根据 Wavenumber / cm^-1 判断为 FTIR 风格谱图。",
                size="60x55",
                reverse_x=True,
                baseline="none",
            ),
            signals=(
                "横轴名称或单位命中了 Wavenumber / cm⁻¹。",
                "多条样品曲线更适合堆积展示。",
                "推荐反向 x 轴，不强行做基线修正。",
            ),
        )
    if _looks_like_dsc(series_list):
        return InputInspection(
            model="curve_table",
            model_label=_model_label("curve_table"),
            recommendation=Recommendation(
                template="stacked_curve",
                reason="根据 Heat flow 标签判断为 DSC 风格堆积图。",
                size="60x55",
                reverse_x=False,
                baseline="linear_endpoints",
            ),
            signals=(
                "y 轴名称命中了 Heat flow。",
                "这类热分析曲线更适合堆积展示。",
                "推荐线性端点基线修正。",
            ),
        )
    if _looks_like_xrd(series_list):
        return InputInspection(
            model="curve_table",
            model_label=_model_label("curve_table"),
            recommendation=Recommendation(
                template="stacked_curve",
                reason="根据 2theta / counts / intensity 判断为 XRD 风格谱图。",
                size="60x55",
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
        model_label=_model_label("curve_table"),
        recommendation=Recommendation(
            template="curve",
            reason="识别到普通成对曲线表，默认推荐普通曲线图。",
            size="60x55",
            xscale="linear",
            yscale="linear",
            reverse_x=False,
        ),
        signals=(
            "检测到标准成对曲线表。",
            "当前标签和单位不明显属于谱图或流变导出表。",
            "默认先按普通曲线图处理。",
        ),
    )


def _preview_output_filenames(
    template: TemplateName,
    input_path: Path,
    sheet: str | int,
    options: RenderOptions,
) -> tuple[str, ...]:
    if template == "point_line":
        bundle = _detect_point_line_bundle(input_path, sheet)
        if bundle == "frequency_sweep":
            return tuple(FREQUENCY_OUTPUTS.values())
        if bundle == "temperature_sweep":
            return tuple(TEMPERATURE_OUTPUTS.values())
        if bundle == "stress_relaxation":
            return ("stress_relaxation_sigma_over_sigma0.pdf",)
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
        groups = load_replicate_table(input_path, sheet_name=sheet)
        slug = _predict_bar_box_slug(groups)
        return (f"{slug}_{template}.pdf",)
    return ()


def preflight_render_request(
    template: TemplateName,
    input_path: Path,
    sheet: str | int,
    options: RenderOptions,
) -> PreflightResult:
    warnings: list[str] = list(_style_preflight_warnings(options))
    errors: list[str] = []

    try:
        if template == "point_line":
            bundle = _detect_point_line_bundle(input_path, sheet)
            if bundle == "frequency_sweep":
                metric_series = load_frequency_sweep_metrics(input_path, sheet_name=sheet)
                for metric_name, series_list in metric_series.items():
                    if not series_list:
                        raise ValueError(f"频率扫描缺少指标数据：{metric_name}")
                    _validate_series_scales(_to_curve_series(series_list), xscale=options.xscale, yscale=options.yscale)
            elif bundle == "temperature_sweep":
                metric_series = load_temperature_sweep_metrics(input_path, sheet_name=sheet)
                for metric_name, series_list in metric_series.items():
                    if not series_list:
                        raise ValueError(f"温度扫描缺少指标数据：{metric_name}")
                    _validate_series_scales(_to_curve_series(series_list), xscale=options.xscale, yscale=options.yscale)
            elif bundle == "stress_relaxation":
                series_list = _to_curve_series(
                    load_stress_relaxation_metric(input_path, metric_name="σ/σ₀", sheet_name=sheet)
                )
                if not series_list:
                    raise ValueError("应力松弛表中没有读到 σ/σ₀ 曲线。")
                _validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
            else:
                series_list = load_curve_table(input_path, sheet_name=sheet)
                _validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
        elif template == "curve":
            series_list = load_curve_table(input_path, sheet_name=sheet)
            _validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
        elif template == "stacked_curve":
            load_curve_table(input_path, sheet_name=sheet)
        elif template == "segmented_stacked_curve":
            series_list = load_curve_table(input_path, sheet_name=sheet)
            _load_segmented_config(input_path, series_list, use_sidecar=True if options.use_sidecar is None else options.use_sidecar)
        elif template == "scatter":
            series_list = load_curve_table(input_path, sheet_name=sheet)
            _validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
        elif template in {"bar", "box", "violin"}:
            groups = load_replicate_table(input_path, sheet_name=sheet)
            if not groups:
                raise ValueError("统计表没有有效分组。")
            if len(groups) >= 6:
                warnings.append("分组较多，横轴标签可能会自动换行或缩小字号。")
        elif template == "heatmap":
            load_heatmap_table(input_path, sheet_name=sheet)
        else:
            raise ValueError(f"Unsupported template in preflight: {template}")
    except Exception as exc:
        errors.append(_humanize_preflight_exception(exc))

    if not errors:
        preview_names = _preview_output_filenames(template, input_path, sheet, options)
        if len(preview_names) > 1:
            warnings.append(f"这次会导出 {len(preview_names)} 张 PDF。")
    else:
        preview_names = ()

    return PreflightResult(
        template=template,
        warnings=tuple(warnings),
        errors=tuple(errors),
        output_filenames=preview_names,
    )


def _build_default_segmented_config(series_list: list[CurveSeries]) -> WideNMRConfig:
    x_min = min(float(series.data["x"].min()) for series in series_list)
    x_max = max(float(series.data["x"].max()) for series in series_list)
    return WideNMRConfig(
        segments=(WideNMRSegment(x_min=x_min, x_max=x_max),),
        series_order=tuple(series.sample for series in series_list),
    )


def _load_segmented_config(input_path: Path, series_list: list[CurveSeries], *, use_sidecar: bool | None) -> WideNMRConfig:
    sidecar_path = wide_nmr_sidecar_path(input_path)
    if use_sidecar is False:
        return _build_default_segmented_config(series_list)
    if sidecar_path.exists():
        return load_wide_nmr_config(input_path)
    if use_sidecar:
        raise FileNotFoundError(f"Missing segmented_stacked_curve sidecar config: {sidecar_path}")
    return _build_default_segmented_config(series_list)


def _render_point_line_frequency(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    metric_series = load_frequency_sweep_metrics(input_path, sheet_name=sheet)
    curve_metrics = {
        metric_name: _to_curve_series(series_list)
        for metric_name, series_list in metric_series.items()
    }
    all_x_values = [
        series.data["x"].to_numpy(dtype=float)
        for metric_name in FREQUENCY_OUTPUTS
        for series in curve_metrics.get(metric_name, [])
    ]
    shared_x_layout = compute_shared_curve_x_layout(all_x_values, xscale=options.xscale)
    outputs: list[RenderedPlot] = []
    for metric_name, filename in FREQUENCY_OUTPUTS.items():
        series_list = curve_metrics.get(metric_name, [])
        if not series_list:
            raise ValueError(f"Missing data for frequency sweep metric: {metric_name}")
        fig, _ = plot_curves(
            series_list,
            show_markers=True,
            xscale=options.xscale,
            yscale=options.yscale,
            width_mm=options.width_mm,
            height_mm=options.height_mm,
            reverse_x=options.reverse_x,
            xlim=shared_x_layout.display_bounds,
            visible_xticks=shared_x_layout.visible_ticks,
            legend_expand_axes="y",
        )
        outputs.append(RenderedPlot(filename=filename, figure=fig))
    return outputs


def _render_point_line_temperature(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    metric_series = load_temperature_sweep_metrics(input_path, sheet_name=sheet)
    all_x_values = [
        series.data["x"].to_numpy(dtype=float)
        for metric_name in TEMPERATURE_OUTPUTS
        for series in metric_series.get(metric_name, [])
    ]
    shared_x_layout = compute_shared_curve_x_layout(all_x_values, xscale=options.xscale)
    outputs: list[RenderedPlot] = []
    for metric_name, filename in TEMPERATURE_OUTPUTS.items():
        series_list = _to_curve_series(metric_series.get(metric_name, []))
        if not series_list:
            raise ValueError(f"Missing data for temperature sweep metric: {metric_name}")
        fig, _ = plot_curves(
            series_list,
            show_markers=True,
            xscale=options.xscale,
            yscale=options.yscale,
            width_mm=options.width_mm,
            height_mm=options.height_mm,
            reverse_x=options.reverse_x,
            xlim=shared_x_layout.display_bounds,
            visible_xticks=shared_x_layout.visible_ticks,
            legend_expand_axes="y",
        )
        outputs.append(RenderedPlot(filename=filename, figure=fig))
    return outputs


def _render_point_line_relaxation(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    series_list = _to_curve_series(load_stress_relaxation_metric(input_path, metric_name="σ/σ₀", sheet_name=sheet))
    if not series_list:
        raise ValueError("No stress relaxation series found for σ/σ₀.")
    fig, _ = plot_curves(
        series_list,
        show_markers=True,
        xscale=options.xscale,
        yscale=options.yscale,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        reverse_x=options.reverse_x,
        y_padding_top=0.12,
        y_padding_bottom=0.04,
    )
    return [RenderedPlot(filename="stress_relaxation_sigma_over_sigma0.pdf", figure=fig)]


def _render_curve(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    series_list = load_curve_table(input_path, sheet_name=sheet)
    fig, _ = plot_curves(
        series_list,
        show_markers=False,
        xscale=options.xscale,
        yscale=options.yscale,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        reverse_x=options.reverse_x,
    )
    return [RenderedPlot(filename=f"{input_path.stem}_curve.pdf", figure=fig)]


def _render_point_line(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    bundle = _detect_point_line_bundle(input_path, sheet)
    if bundle == "frequency_sweep":
        return _render_point_line_frequency(input_path, sheet, options)
    if bundle == "temperature_sweep":
        return _render_point_line_temperature(input_path, sheet, options)
    if bundle == "stress_relaxation":
        return _render_point_line_relaxation(input_path, sheet, options)

    series_list = load_curve_table(input_path, sheet_name=sheet)
    fig, _ = plot_curves(
        series_list,
        show_markers=True,
        xscale=options.xscale,
        yscale=options.yscale,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        reverse_x=options.reverse_x,
    )
    return [RenderedPlot(filename=f"{input_path.stem}_point_line.pdf", figure=fig)]


def _render_stacked_curve(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    series_list = load_curve_table(input_path, sheet_name=sheet)
    fig, _ = plot_curves(
        series_list,
        show_markers=False,
        legend_mode="none",
        xscale=options.xscale,
        yscale=options.yscale,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        reverse_x=options.reverse_x,
        stack_mode="auto_vertical",
        series_label_mode="edge",
        baseline_mode=options.baseline,
        show_y_ticks=False,
        y_padding_top=0.08,
        y_padding_bottom=0.04,
    )
    return [RenderedPlot(filename=f"{input_path.stem}_stacked_curve.pdf", figure=fig)]


def _render_segmented_stacked_curve(
    input_path: Path,
    sheet: str | int,
    options: RenderOptions,
) -> list[RenderedPlot]:
    series_list = load_curve_table(input_path, sheet_name=sheet)
    config = _load_segmented_config(input_path, series_list, use_sidecar=options.use_sidecar)
    fig, _ = plot_wide_nmr(
        series_list,
        config,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        reverse_x=options.reverse_x,
        baseline_mode=options.baseline,
    )
    return [RenderedPlot(filename=f"{input_path.stem}_segmented_stacked_curve.pdf", figure=fig)]


def _render_bar(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table(input_path, sheet_name=sheet)
    fig, _ = plot_bar(groups, width_mm=options.width_mm, height_mm=options.height_mm)
    slug = slugify_label(groups[0].value_label if groups else "value")
    return [RenderedPlot(filename=f"{slug}_bar.pdf", figure=fig)]


def _render_box(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table(input_path, sheet_name=sheet)
    fig, _ = plot_box(groups, width_mm=options.width_mm, height_mm=options.height_mm)
    slug = slugify_label(groups[0].value_label if groups else "value")
    return [RenderedPlot(filename=f"{slug}_box.pdf", figure=fig)]


def _render_violin(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table(input_path, sheet_name=sheet)
    fig, _ = plot_violin(groups, width_mm=options.width_mm, height_mm=options.height_mm)
    slug = slugify_label(groups[0].value_label if groups else "value")
    return [RenderedPlot(filename=f"{slug}_violin.pdf", figure=fig)]


def _render_scatter(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    series_list = load_curve_table(input_path, sheet_name=sheet)
    fig, _ = plot_scatter(
        series_list,
        xscale=options.xscale,
        yscale=options.yscale,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        reverse_x=options.reverse_x,
    )
    return [RenderedPlot(filename=f"{input_path.stem}_scatter.pdf", figure=fig)]


def _render_heatmap(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    table = load_heatmap_table(input_path, sheet_name=sheet)
    fig, _ = plot_heatmap(
        table,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        show_colorbar=options.show_colorbar,
    )
    return [RenderedPlot(filename=f"{input_path.stem}_heatmap.pdf", figure=fig)]


TEMPLATE_RENDERERS: dict[TemplateName, TemplateRenderer] = {
    "curve": TemplateRenderer(render=_render_curve),
    "point_line": TemplateRenderer(render=_render_point_line),
    "stacked_curve": TemplateRenderer(render=_render_stacked_curve),
    "segmented_stacked_curve": TemplateRenderer(render=_render_segmented_stacked_curve),
    "bar": TemplateRenderer(render=_render_bar),
    "box": TemplateRenderer(render=_render_box),
    "violin": TemplateRenderer(render=_render_violin),
    "scatter": TemplateRenderer(render=_render_scatter),
    "heatmap": TemplateRenderer(render=_render_heatmap),
}


def close_rendered_plots(rendered_plots: list[RenderedPlot]) -> None:
    for rendered in rendered_plots:
        plt.close(rendered.figure)


def export_rendered_plots(
    rendered_plots: list[RenderedPlot],
    output_dir: Path,
    *,
    close: bool = False,
) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs = [save_pdf(rendered.figure, output_dir / rendered.filename) for rendered in rendered_plots]
    if close:
        close_rendered_plots(rendered_plots)
    return outputs


def build_rendered_plots(
    template: TemplateName,
    input_path: Path,
    sheet: str | int = 0,
    *,
    size: str | None = None,
    xscale: str | None = None,
    yscale: str | None = None,
    reverse_x: bool = False,
    baseline: str | None = None,
    show_colorbar: bool | None = None,
    style_preset: str = plot_style.DEFAULT_STYLE_PRESET,
    palette_preset: str = plot_style.DEFAULT_PALETTE_PRESET,
    use_sidecar: bool | None = None,
) -> list[RenderedPlot]:
    validated_template = _validate_template_name(template)
    options = _resolve_render_options(
        template=validated_template,
        size=size,
        xscale=xscale,
        yscale=yscale,
        reverse_x=reverse_x,
        baseline=baseline,
        show_colorbar=show_colorbar,
        style_preset=style_preset,
        palette_preset=palette_preset,
        use_sidecar=use_sidecar,
    )
    plot_style.apply_style(options.style_preset, options.palette_preset)
    renderer = TEMPLATE_RENDERERS[validated_template]
    return renderer.render(input_path, sheet, options)


def render_template(
    template: TemplateName,
    input_path: Path,
    output_dir: Path,
    sheet: str | int = 0,
    *,
    size: str | None = None,
    xscale: str | None = None,
    yscale: str | None = None,
    reverse_x: bool = False,
    baseline: str | None = None,
    show_colorbar: bool | None = None,
    style_preset: str = plot_style.DEFAULT_STYLE_PRESET,
    palette_preset: str = plot_style.DEFAULT_PALETTE_PRESET,
    use_sidecar: bool | None = None,
) -> list[Path]:
    rendered_plots = build_rendered_plots(
        template,
        input_path,
        sheet,
        size=size,
        xscale=xscale,
        yscale=yscale,
        reverse_x=reverse_x,
        baseline=baseline,
        show_colorbar=show_colorbar,
        style_preset=style_preset,
        palette_preset=palette_preset,
        use_sidecar=use_sidecar,
    )
    return export_rendered_plots(rendered_plots, output_dir, close=True)


def main() -> int:
    args = _parse_args()

    try:
        validated_template = _validate_template_name(args.template)
        input_path = _ensure_input_path(args.input)
        output_dir = resolve_output_dir(input_path, args.output_dir, args.output_mode)
        sheet = _coerce_sheet(args.sheet)
        options = _resolve_render_options(
            template=validated_template,
            size=args.size,
            xscale=args.xscale,
            yscale=args.yscale,
            reverse_x=args.reverse_x,
            baseline=args.baseline,
            show_colorbar=args.show_colorbar,
            style_preset=args.style_preset,
            palette_preset=args.palette_preset,
        )
        preflight = preflight_render_request(validated_template, input_path, sheet, options)
        if preflight.errors:
            raise ValueError(preflight.errors[0])
        for warning in preflight.warnings:
            print(f"Warning: {warning}", file=sys.stderr)
        outputs = render_template(
            validated_template,
            input_path,
            output_dir,
            sheet,
            size=args.size,
            xscale=args.xscale,
            yscale=args.yscale,
            reverse_x=args.reverse_x,
            baseline=args.baseline,
            show_colorbar=args.show_colorbar,
            style_preset=args.style_preset,
            palette_preset=args.palette_preset,
        )
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    for output in outputs:
        print(output.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
