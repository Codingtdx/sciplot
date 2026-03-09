from __future__ import annotations

import argparse
from dataclasses import dataclass
import re
import sys
from pathlib import Path
from typing import Callable

import matplotlib.pyplot as plt
import pandas as pd

from src.data_loader import (
    CurveSeries,
    load_curve_table,
    load_heatmap_table,
    load_replicate_table,
    read_raw_table,
)
from src.plot_style import PANEL_HEIGHT_MM, PANEL_WIDTH_MM, save_pdf, use_nature_style
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
RenderFn = Callable[[Path, Path, str | int, "RenderOptions"], list[Path]]

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
    use_sidecar: bool | None = None


@dataclass(frozen=True)
class TemplateRenderer:
    render: RenderFn


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
        description="Generate Nature-style research plots from graph-family templates.",
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
        use_sidecar=use_sidecar,
    )


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


def _render_point_line_frequency(input_path: Path, output_dir: Path, sheet: str | int, options: RenderOptions) -> list[Path]:
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
    outputs: list[Path] = []
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
        outputs.append(save_pdf(fig, output_dir / filename))
        plt.close(fig)
    return outputs


def _render_point_line_temperature(input_path: Path, output_dir: Path, sheet: str | int, options: RenderOptions) -> list[Path]:
    metric_series = load_temperature_sweep_metrics(input_path, sheet_name=sheet)
    all_x_values = [
        series.data["x"].to_numpy(dtype=float)
        for metric_name in TEMPERATURE_OUTPUTS
        for series in metric_series.get(metric_name, [])
    ]
    shared_x_layout = compute_shared_curve_x_layout(all_x_values, xscale=options.xscale)
    outputs: list[Path] = []
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
        outputs.append(save_pdf(fig, output_dir / filename))
        plt.close(fig)
    return outputs


def _render_point_line_relaxation(input_path: Path, output_dir: Path, sheet: str | int, options: RenderOptions) -> list[Path]:
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
    output = save_pdf(fig, output_dir / "stress_relaxation_sigma_over_sigma0.pdf")
    plt.close(fig)
    return [output]


def _render_curve(input_path: Path, output_dir: Path, sheet: str | int, options: RenderOptions) -> list[Path]:
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
    output = save_pdf(fig, output_dir / f"{input_path.stem}_curve.pdf")
    plt.close(fig)
    return [output]


def _render_point_line(input_path: Path, output_dir: Path, sheet: str | int, options: RenderOptions) -> list[Path]:
    bundle = _detect_point_line_bundle(input_path, sheet)
    if bundle == "frequency_sweep":
        return _render_point_line_frequency(input_path, output_dir, sheet, options)
    if bundle == "temperature_sweep":
        return _render_point_line_temperature(input_path, output_dir, sheet, options)
    if bundle == "stress_relaxation":
        return _render_point_line_relaxation(input_path, output_dir, sheet, options)

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
    output = save_pdf(fig, output_dir / f"{input_path.stem}_point_line.pdf")
    plt.close(fig)
    return [output]


def _render_stacked_curve(input_path: Path, output_dir: Path, sheet: str | int, options: RenderOptions) -> list[Path]:
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
    output = save_pdf(fig, output_dir / f"{input_path.stem}_stacked_curve.pdf")
    plt.close(fig)
    return [output]


def _render_segmented_stacked_curve(
    input_path: Path,
    output_dir: Path,
    sheet: str | int,
    options: RenderOptions,
) -> list[Path]:
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
    output = save_pdf(fig, output_dir / f"{input_path.stem}_segmented_stacked_curve.pdf")
    plt.close(fig)
    return [output]


def _render_bar(input_path: Path, output_dir: Path, sheet: str | int, options: RenderOptions) -> list[Path]:
    groups = load_replicate_table(input_path, sheet_name=sheet)
    fig, _ = plot_bar(groups, width_mm=options.width_mm, height_mm=options.height_mm)
    slug = slugify_label(groups[0].value_label if groups else "value")
    output = save_pdf(fig, output_dir / f"{slug}_bar.pdf")
    plt.close(fig)
    return [output]


def _render_box(input_path: Path, output_dir: Path, sheet: str | int, options: RenderOptions) -> list[Path]:
    groups = load_replicate_table(input_path, sheet_name=sheet)
    fig, _ = plot_box(groups, width_mm=options.width_mm, height_mm=options.height_mm)
    slug = slugify_label(groups[0].value_label if groups else "value")
    output = save_pdf(fig, output_dir / f"{slug}_box.pdf")
    plt.close(fig)
    return [output]


def _render_violin(input_path: Path, output_dir: Path, sheet: str | int, options: RenderOptions) -> list[Path]:
    groups = load_replicate_table(input_path, sheet_name=sheet)
    fig, _ = plot_violin(groups, width_mm=options.width_mm, height_mm=options.height_mm)
    slug = slugify_label(groups[0].value_label if groups else "value")
    output = save_pdf(fig, output_dir / f"{slug}_violin.pdf")
    plt.close(fig)
    return [output]


def _render_scatter(input_path: Path, output_dir: Path, sheet: str | int, options: RenderOptions) -> list[Path]:
    series_list = load_curve_table(input_path, sheet_name=sheet)
    fig, _ = plot_scatter(
        series_list,
        xscale=options.xscale,
        yscale=options.yscale,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        reverse_x=options.reverse_x,
    )
    output = save_pdf(fig, output_dir / f"{input_path.stem}_scatter.pdf")
    plt.close(fig)
    return [output]


def _render_heatmap(input_path: Path, output_dir: Path, sheet: str | int, options: RenderOptions) -> list[Path]:
    table = load_heatmap_table(input_path, sheet_name=sheet)
    fig, _ = plot_heatmap(
        table,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        show_colorbar=options.show_colorbar,
    )
    output = save_pdf(fig, output_dir / f"{input_path.stem}_heatmap.pdf")
    plt.close(fig)
    return [output]


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
    use_sidecar: bool | None = None,
) -> list[Path]:
    use_nature_style()
    output_dir.mkdir(parents=True, exist_ok=True)
    validated_template = _validate_template_name(template)
    options = _resolve_render_options(
        template=validated_template,
        size=size,
        xscale=xscale,
        yscale=yscale,
        reverse_x=reverse_x,
        baseline=baseline,
        show_colorbar=show_colorbar,
        use_sidecar=use_sidecar,
    )
    renderer = TEMPLATE_RENDERERS[validated_template]
    return renderer.render(input_path, output_dir, sheet, options)


def main() -> int:
    args = _parse_args()

    try:
        validated_template = _validate_template_name(args.template)
        input_path = _ensure_input_path(args.input)
        output_dir = resolve_output_dir(input_path, args.output_dir, args.output_mode)
        sheet = _coerce_sheet(args.sheet)
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
        )
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    for output in outputs:
        print(output.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
