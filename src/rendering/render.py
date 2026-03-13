from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt

from src import (
    mpl_backend,  # noqa: F401
    plot_style,
)
from src.plot_style import save_pdf
from src.plotting_families.curve_family import plot_curves, plot_scatter
from src.plotting_families.heatmap_family import plot_heatmap
from src.plotting_families.layout_helpers import compute_shared_curve_x_layout
from src.plotting_families.spectral_family import plot_wide_nmr
from src.plotting_families.stats_family import plot_bar, plot_box, plot_violin
from src.rendering.cache import (
    load_curve_table_cached,
    load_frequency_sweep_metrics_cached,
    load_heatmap_table_cached,
    load_replicate_table_cached,
    load_stress_relaxation_metric_cached,
    load_temperature_sweep_metrics_cached,
)
from src.rendering.common import load_segmented_config, predict_bar_box_slug, to_curve_series
from src.rendering.constants import FREQUENCY_OUTPUTS, TEMPERATURE_OUTPUTS
from src.rendering.models import RenderedPlot, RenderOptions, TemplateName, TemplateRenderer
from src.rendering.options import resolve_render_options, validate_template_name
from src.rendering.recommendation import detect_point_line_bundle


def _render_point_line_frequency(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    metric_series = load_frequency_sweep_metrics_cached(input_path, sheet)
    curve_metrics = {
        metric_name: to_curve_series(series_list)
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
    metric_series = load_temperature_sweep_metrics_cached(input_path, sheet)
    all_x_values = [
        series.data["x"].to_numpy(dtype=float)
        for metric_name in TEMPERATURE_OUTPUTS
        for series in metric_series.get(metric_name, [])
    ]
    shared_x_layout = compute_shared_curve_x_layout(all_x_values, xscale=options.xscale)
    outputs: list[RenderedPlot] = []
    for metric_name, filename in TEMPERATURE_OUTPUTS.items():
        series_list = to_curve_series(metric_series.get(metric_name, []))
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
    series_list = to_curve_series(load_stress_relaxation_metric_cached(input_path, "σ/σ₀", sheet))
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
    series_list = load_curve_table_cached(input_path, sheet)
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
    bundle = detect_point_line_bundle(input_path, sheet)
    if bundle == "frequency_sweep":
        return _render_point_line_frequency(input_path, sheet, options)
    if bundle == "temperature_sweep":
        return _render_point_line_temperature(input_path, sheet, options)
    if bundle == "stress_relaxation":
        return _render_point_line_relaxation(input_path, sheet, options)

    series_list = load_curve_table_cached(input_path, sheet)
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
    series_list = load_curve_table_cached(input_path, sheet)
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
    series_list = load_curve_table_cached(input_path, sheet)
    config = load_segmented_config(input_path, series_list, use_sidecar=options.use_sidecar)
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
    groups = load_replicate_table_cached(input_path, sheet)
    fig, _ = plot_bar(groups, width_mm=options.width_mm, height_mm=options.height_mm)
    return [RenderedPlot(filename=f"{predict_bar_box_slug(groups)}_bar.pdf", figure=fig)]


def _render_box(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table_cached(input_path, sheet)
    fig, _ = plot_box(groups, width_mm=options.width_mm, height_mm=options.height_mm)
    return [RenderedPlot(filename=f"{predict_bar_box_slug(groups)}_box.pdf", figure=fig)]


def _render_violin(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table_cached(input_path, sheet)
    fig, _ = plot_violin(groups, width_mm=options.width_mm, height_mm=options.height_mm)
    return [RenderedPlot(filename=f"{predict_bar_box_slug(groups)}_violin.pdf", figure=fig)]


def _render_scatter(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    series_list = load_curve_table_cached(input_path, sheet)
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
    table = load_heatmap_table_cached(input_path, sheet)
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
    validated_template = validate_template_name(template)
    options = resolve_render_options(
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


__all__ = [
    "TEMPLATE_RENDERERS",
    "build_rendered_plots",
    "close_rendered_plots",
    "export_rendered_plots",
    "render_template",
]
