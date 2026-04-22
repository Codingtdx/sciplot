from __future__ import annotations

from dataclasses import replace
from pathlib import Path

import matplotlib.pyplot as plt

from src import plot_style
from src.plot_style import save_pdf
from src.rendering.fit_analysis import fit_options_from_payload
from src.rendering.models import RenderedPlot, TemplateName
from src.rendering.options import resolve_render_options, validate_template_name
from src.rendering.render_registry import TEMPLATE_RENDERERS
from src.rendering.style_composer import DEFAULT_STYLE_COMPOSER
from src.rendering.template_lifecycle import resolve_template_id


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
    reverse_x: bool | None = None,
    x_min: float | None = None,
    x_max: float | None = None,
    y_min: float | None = None,
    y_max: float | None = None,
    x_tick_density: str | None = None,
    y_tick_density: str | None = None,
    x_tick_edge_labels: str | None = None,
    y_tick_edge_labels: str | None = None,
    series_order: list[str] | tuple[str, ...] | None = None,
    x_label_override: str | None = None,
    y_label_override: str | None = None,
    baseline: str | None = None,
    show_colorbar: bool | None = None,
    style_preset: str | None = None,
    palette_preset: str | None = None,
    use_sidecar: bool | None = None,
    visual_theme_id: str | None = None,
    fit_options: dict[str, object] | None = None,
) -> list[RenderedPlot]:
    requested_template = validate_template_name(template)
    resolved_template = resolve_template_id(requested_template, input_path=input_path, sheet=sheet)
    options = resolve_render_options(
        template=requested_template,
        size=size,
        xscale=xscale,
        yscale=yscale,
        reverse_x=reverse_x,
        x_min=x_min,
        x_max=x_max,
        y_min=y_min,
        y_max=y_max,
        x_tick_density=x_tick_density,
        y_tick_density=y_tick_density,
        x_tick_edge_labels=x_tick_edge_labels,
        y_tick_edge_labels=y_tick_edge_labels,
        series_order=series_order,
        x_label_override=x_label_override,
        y_label_override=y_label_override,
        baseline=baseline,
        show_colorbar=show_colorbar,
        style_preset=style_preset,
        palette_preset=palette_preset,
        use_sidecar=use_sidecar,
        visual_theme_id=visual_theme_id,
        resolved_template_id=resolved_template,
    )
    options = replace(options, fit_options=fit_options_from_payload(fit_options).__dict__)
    style_bundle = DEFAULT_STYLE_COMPOSER.compose(options.style_preset, options.visual_theme_id)
    plot_style.apply_style(
        style_bundle.publication_profile_id,
        options.palette_preset,
        soft_overrides=style_bundle.resolved_soft,
    )
    renderer = TEMPLATE_RENDERERS[resolved_template]
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
    reverse_x: bool | None = None,
    x_min: float | None = None,
    x_max: float | None = None,
    y_min: float | None = None,
    y_max: float | None = None,
    x_tick_density: str | None = None,
    y_tick_density: str | None = None,
    x_tick_edge_labels: str | None = None,
    y_tick_edge_labels: str | None = None,
    series_order: list[str] | tuple[str, ...] | None = None,
    x_label_override: str | None = None,
    y_label_override: str | None = None,
    baseline: str | None = None,
    show_colorbar: bool | None = None,
    style_preset: str | None = None,
    palette_preset: str | None = None,
    use_sidecar: bool | None = None,
    visual_theme_id: str | None = None,
    fit_options: dict[str, object] | None = None,
) -> list[Path]:
    rendered_plots = build_rendered_plots(
        template,
        input_path,
        sheet,
        size=size,
        xscale=xscale,
        yscale=yscale,
        reverse_x=reverse_x,
        x_min=x_min,
        x_max=x_max,
        y_min=y_min,
        y_max=y_max,
        x_tick_density=x_tick_density,
        y_tick_density=y_tick_density,
        x_tick_edge_labels=x_tick_edge_labels,
        y_tick_edge_labels=y_tick_edge_labels,
        series_order=series_order,
        x_label_override=x_label_override,
        y_label_override=y_label_override,
        baseline=baseline,
        show_colorbar=show_colorbar,
        style_preset=style_preset,
        palette_preset=palette_preset,
        use_sidecar=use_sidecar,
        visual_theme_id=visual_theme_id,
        fit_options=fit_options,
    )
    return export_rendered_plots(rendered_plots, output_dir, close=True)


__all__ = [
    "TEMPLATE_RENDERERS",
    "build_rendered_plots",
    "close_rendered_plots",
    "export_rendered_plots",
    "render_template",
]
