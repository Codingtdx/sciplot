from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt

from src import plot_style
from src.plot_style import save_pdf
from src.rendering.models import RenderedPlot, TemplateName
from src.rendering.options import resolve_render_options, validate_template_name
from src.rendering.render_registry import TEMPLATE_RENDERERS
from src.rendering.style_composer import DEFAULT_STYLE_COMPOSER


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
    series_order: list[str] | tuple[str, ...] | None = None,
    x_label_override: str | None = None,
    y_label_override: str | None = None,
    baseline: str | None = None,
    show_colorbar: bool | None = None,
    style_preset: str = plot_style.DEFAULT_STYLE_PRESET,
    palette_preset: str = plot_style.DEFAULT_PALETTE_PRESET,
    use_sidecar: bool | None = None,
    visual_theme_id: str | None = None,
) -> list[RenderedPlot]:
    validated_template = validate_template_name(template)
    options = resolve_render_options(
        template=validated_template,
        size=size,
        xscale=xscale,
        yscale=yscale,
        reverse_x=reverse_x,
        x_min=x_min,
        x_max=x_max,
        y_min=y_min,
        y_max=y_max,
        series_order=series_order,
        x_label_override=x_label_override,
        y_label_override=y_label_override,
        baseline=baseline,
        show_colorbar=show_colorbar,
        style_preset=style_preset,
        palette_preset=palette_preset,
        use_sidecar=use_sidecar,
        visual_theme_id=visual_theme_id,
    )
    style_bundle = DEFAULT_STYLE_COMPOSER.compose(options.style_preset, options.visual_theme_id)
    plot_style.apply_style(
        style_bundle.publication_profile_id,
        options.palette_preset,
        soft_overrides=style_bundle.resolved_soft,
    )
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
    reverse_x: bool | None = None,
    x_min: float | None = None,
    x_max: float | None = None,
    y_min: float | None = None,
    y_max: float | None = None,
    series_order: list[str] | tuple[str, ...] | None = None,
    x_label_override: str | None = None,
    y_label_override: str | None = None,
    baseline: str | None = None,
    show_colorbar: bool | None = None,
    style_preset: str = plot_style.DEFAULT_STYLE_PRESET,
    palette_preset: str = plot_style.DEFAULT_PALETTE_PRESET,
    use_sidecar: bool | None = None,
    visual_theme_id: str | None = None,
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
        series_order=series_order,
        x_label_override=x_label_override,
        y_label_override=y_label_override,
        baseline=baseline,
        show_colorbar=show_colorbar,
        style_preset=style_preset,
        palette_preset=palette_preset,
        use_sidecar=use_sidecar,
        visual_theme_id=visual_theme_id,
    )
    return export_rendered_plots(rendered_plots, output_dir, close=True)


__all__ = [
    "TEMPLATE_RENDERERS",
    "build_rendered_plots",
    "close_rendered_plots",
    "export_rendered_plots",
    "render_template",
]
