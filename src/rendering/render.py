from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

from src import (
    mpl_backend,  # noqa: F401
    plot_style,
)
from src.plot_contract import qa_profile
from src.plot_style import save_pdf
from src.plotting import _place_series_edge_labels
from src.plotting_families.curve_family import plot_curves, plot_scatter
from src.plotting_families.heatmap_family import plot_heatmap
from src.plotting_families.layout_helpers import compute_shared_curve_x_layout
from src.plotting_families.spectral_family import plot_wide_nmr
from src.plotting_families.stats_family import plot_bar, plot_box, plot_violin
from src.rendering.cache import (
    load_curve_table_cached,
    load_heatmap_table_cached,
    load_replicate_table_cached,
)
from src.rendering.common import (
    load_rheology_bundle_series,
    load_segmented_config,
    looks_like_tensile_curve,
    predict_bar_box_slug,
    rheology_output_filenames,
    validate_series_scales,
)
from src.rendering.models import RenderedPlot, RenderOptions, TemplateName, TemplateRenderer
from src.rendering.options import resolve_render_options, validate_template_name
from src.rendering.qa import (
    CurveAutofix,
    analyze_rendered_figure,
    apply_curve_autofix,
    recommend_curve_autofix,
)
from src.rendering.recommendation import detect_point_line_bundle


@dataclass(frozen=True)
class StatsRenderProfile:
    bar_width: float
    box_width: float
    violin_width: float
    spacing_scale: float
    show_raw_points: bool
    raw_point_size: float
    raw_point_alpha: float
    capsize: float


@dataclass(frozen=True)
class HeatmapEditorialLayout:
    colorbar_x_offset_fraction: float
    colorbar_width_fraction: float
    colorbar_y_offset_fraction: float
    colorbar_height_fraction: float
    colorbar_tick_count: int
    label_gap_pt: float


def _rendered_plot_with_qa(
    *,
    filename: str,
    figure: plt.Figure,
    template: str,
    options: RenderOptions,
    autofixes_applied: tuple[str, ...] = (),
) -> RenderedPlot:
    return RenderedPlot(
        filename=filename,
        figure=figure,
        qa_report=analyze_rendered_figure(
            figure,
            template=template,
            options=options,
            palette_preset=options.palette_preset,
            autofixes_applied=autofixes_applied,
        ),
    )


def _prefer_direct_labels(options: RenderOptions, series_count: int) -> bool:
    profile = qa_profile("curve")
    return bool(
        series_count <= int(profile.get("direct_label_max_series", 4))
        and np.isclose(options.width_mm, float(profile.get("small_panel_width_mm", options.width_mm)), atol=0.05)
        and np.isclose(options.height_mm, float(profile.get("small_panel_height_mm", options.height_mm)), atol=0.05)
    )


def _float_plot_kw(base_kwargs: dict[str, object], key: str, default: float) -> float:
    value = base_kwargs.get(key)
    return float(value) if isinstance(value, (int, float)) else default


def _curve_dense_fix(
    series_list,
    *,
    show_markers: bool,
    scatter: bool,
) -> CurveAutofix:
    total_points = max((len(series.data.index) for series in series_list), default=0)
    return recommend_curve_autofix(
        total_points=total_points,
        has_markers=show_markers,
        has_scatter=scatter,
    )


def _post_curve_fix(dense_fix: CurveAutofix, *, include_line_scale: bool) -> CurveAutofix:
    return CurveAutofix(
        tick_width_scale=dense_fix.tick_width_scale,
        tick_length_scale=dense_fix.tick_length_scale,
        line_width_scale=dense_fix.line_width_scale if include_line_scale else 1.0,
        collection_size_scale=dense_fix.collection_size_scale,
        autofixes_applied=dense_fix.autofixes_applied,
    )


def _curve_candidate_key(candidate: tuple[RenderedPlot, str]) -> tuple[float, int, int]:
    rendered, strategy = candidate
    qa = rendered.qa_report
    if qa is None:
        return (0.0, 0, 0)
    unsafe_issue_ids = {"series_identification", "label_out_of_bounds"}
    if any(issue.id in unsafe_issue_ids for issue in qa.issues):
        return (-1.0, -999, 0)
    critical_count = sum(1 for issue in qa.issues if issue.severity == "critical")
    direct_bonus = 1 if strategy.startswith("direct") else 0
    return (qa.score, -critical_count, direct_bonus)


def _render_curve_candidate(
    *,
    filename: str,
    template: str,
    series_list,
    options: RenderOptions,
    show_markers: bool,
    scatter: bool,
    direct_label_side: str | None,
    base_kwargs: dict[str, object],
) -> tuple[RenderedPlot, str]:
    dense_fix = _curve_dense_fix(series_list, show_markers=show_markers, scatter=scatter)
    strategy = "legend" if direct_label_side is None else f"direct_{direct_label_side}"
    autofixes = list(dense_fix.autofixes_applied)
    if direct_label_side is not None:
        autofixes.append("direct_series_labels")

    if scatter:
        fig, ax = plot_scatter(
            series_list,
            axis_mode=str(base_kwargs.get("axis_mode", "auto")),
            xscale=options.xscale,
            yscale=options.yscale,
            width_mm=options.width_mm,
            height_mm=options.height_mm,
            reverse_x=options.reverse_x,
            legend_mode="none" if direct_label_side is not None else "inside_best",
            legend_expand_axes=str(base_kwargs.get("legend_expand_axes", "xy")),
            marker_size=14.0 * (dense_fix.collection_size_scale if dense_fix.collection_size_scale != 1.0 else 1.0),
            visible_xticks=base_kwargs.get("visible_xticks"),
            xlim=base_kwargs.get("xlim"),
            y_padding_top=_float_plot_kw(base_kwargs, "y_padding_top", 0.12),
            y_padding_bottom=_float_plot_kw(base_kwargs, "y_padding_bottom", 0.06),
        )
        if direct_label_side is not None and len(series_list) > 1:
            palette = plot_style.get_categorical_palette(n_colors=len(series_list))
            _place_series_edge_labels(
                ax,
                series_list,
                palette,
                reverse_x=options.reverse_x,
                side=direct_label_side,
                inset_fraction=0.06,
                label_offset_pt=5.0,
                search_band_fraction=0.08,
                fontsize=6.0,
            )
        applied = apply_curve_autofix(ax, _post_curve_fix(dense_fix, include_line_scale=False))
    else:
        marker_size = None
        if show_markers:
            marker_size = plot_style.current_stroke().marker_size_pt * dense_fix.marker_size_scale
        fig, ax = plot_curves(
            series_list,
            show_markers=show_markers,
            axis_mode=str(base_kwargs.get("axis_mode", "auto")),
            xscale=options.xscale,
            yscale=options.yscale,
            width_mm=options.width_mm,
            height_mm=options.height_mm,
            reverse_x=options.reverse_x,
            marker_every=dense_fix.marker_every if show_markers else None,
            marker_size=marker_size,
            legend_mode="none" if direct_label_side is not None else str(base_kwargs.get("legend_mode", "inside_best")),
            legend_expand_axes=str(base_kwargs.get("legend_expand_axes", "xy")),
            series_label_mode=(
                "edge"
                if direct_label_side is not None
                else str(base_kwargs.get("series_label_mode", "legend"))
            ),
            series_label_side=direct_label_side or str(base_kwargs.get("series_label_side", "auto")),
            visible_xticks=base_kwargs.get("visible_xticks"),
            xlim=base_kwargs.get("xlim"),
            y_padding_top=_float_plot_kw(base_kwargs, "y_padding_top", 0.18),
            y_padding_bottom=_float_plot_kw(base_kwargs, "y_padding_bottom", 0.06),
        )
        applied = apply_curve_autofix(ax, _post_curve_fix(dense_fix, include_line_scale=show_markers))

    rendered = _rendered_plot_with_qa(
        filename=filename,
        figure=fig,
        template=template,
        options=options,
        autofixes_applied=tuple(dict.fromkeys([*autofixes, *applied])),
    )
    return rendered, strategy


def _render_curve_like_plot(
    *,
    filename: str,
    template: str,
    series_list,
    options: RenderOptions,
    show_markers: bool,
    scatter: bool = False,
    base_kwargs: dict[str, object] | None = None,
) -> RenderedPlot:
    resolved_kwargs = dict(base_kwargs or {})
    candidates = [
        _render_curve_candidate(
            filename=filename,
            template=template,
            series_list=series_list,
            options=options,
            show_markers=show_markers,
            scatter=scatter,
            direct_label_side=None,
            base_kwargs=resolved_kwargs,
        )
    ]
    if _prefer_direct_labels(options, len(series_list)) and len(series_list) > 1:
        for side in ("left", "right"):
            candidates.append(
                _render_curve_candidate(
                    filename=filename,
                    template=template,
                    series_list=series_list,
                    options=options,
                    show_markers=show_markers,
                    scatter=scatter,
                    direct_label_side=side,
                    base_kwargs=resolved_kwargs,
                )
            )

    best_rendered, best_strategy = max(candidates, key=_curve_candidate_key)
    for rendered, strategy in candidates:
        if rendered is best_rendered and strategy == best_strategy:
            continue
        plt.close(rendered.figure)
    return best_rendered


def _stats_profile(groups) -> StatsRenderProfile:
    profile = qa_profile("stats")
    group_count = max(len(groups), 1)
    replicate_count = max((len(group.data) for group in groups), default=0)
    min_bar_width = float(profile.get("min_bar_width", 0.28))
    max_bar_width = float(profile.get("max_bar_width", 0.42))
    min_spacing = float(profile.get("min_spacing_scale", 1.0))
    max_spacing = float(profile.get("max_spacing_scale", 1.18))
    density = min(max((group_count - 2) / 4.0, 0.0), 1.0)
    bar_width = max_bar_width - (max_bar_width - min_bar_width) * density
    spacing_scale = min_spacing + (max_spacing - min_spacing) * min(max((group_count - 1) / 5.0, 0.0), 1.0)
    show_raw_points = (
        group_count <= int(profile.get("raw_point_max_groups", 6))
        and replicate_count <= int(profile.get("raw_point_max_replicates", 10))
    )
    return StatsRenderProfile(
        bar_width=bar_width,
        box_width=max(min(bar_width, 0.4), min_bar_width),
        violin_width=min(bar_width + 0.05, 0.48),
        spacing_scale=spacing_scale,
        show_raw_points=show_raw_points,
        raw_point_size=float(profile.get("raw_point_size", 11.0)),
        raw_point_alpha=float(profile.get("raw_point_alpha", 0.75)),
        capsize=max(2.0, min(4.0, 2.0 + bar_width * 4.5)),
    )


def _heatmap_editorial_layout() -> HeatmapEditorialLayout:
    profile = qa_profile("heatmap")
    return HeatmapEditorialLayout(
        colorbar_x_offset_fraction=float(profile.get("colorbar_x_offset_fraction", 0.29)),
        colorbar_width_fraction=float(profile.get("colorbar_width_fraction", 0.56)),
        colorbar_y_offset_fraction=float(profile.get("colorbar_y_offset_fraction", 0.2)),
        colorbar_height_fraction=float(profile.get("colorbar_height_fraction", 0.1)),
        colorbar_tick_count=int(profile.get("colorbar_tick_count", 4)),
        label_gap_pt=float(profile.get("label_gap_pt", 6.0)),
    )


def _render_rheology_bundle(
    bundle: str,
    template: TemplateName,
    input_path: Path,
    sheet: str | int,
    options: RenderOptions,
) -> list[RenderedPlot]:
    metric_series = load_rheology_bundle_series(bundle, input_path, sheet)
    output_filenames = rheology_output_filenames(bundle, template)
    show_markers = template == "point_line"

    shared_x_layout = None
    if bundle in {"frequency_sweep", "temperature_sweep"}:
        all_x_values = [
            series.data["x"].to_numpy(dtype=float)
            for metric_name in output_filenames
            for series in metric_series.get(metric_name, [])
        ]
        shared_x_layout = compute_shared_curve_x_layout(all_x_values, xscale=options.xscale)

    outputs: list[RenderedPlot] = []
    for metric_name, filename in output_filenames.items():
        series_list = metric_series.get(metric_name, [])
        if not series_list:
            raise ValueError(f"Missing data for {bundle} metric: {metric_name}")

        plot_kwargs: dict[str, object] = {
            "show_markers": show_markers,
            "xscale": options.xscale,
            "yscale": options.yscale,
            "width_mm": options.width_mm,
            "height_mm": options.height_mm,
            "reverse_x": options.reverse_x,
        }
        if shared_x_layout is not None:
            plot_kwargs["xlim"] = shared_x_layout.display_bounds
            plot_kwargs["visible_xticks"] = shared_x_layout.visible_ticks
            plot_kwargs["legend_expand_axes"] = "y"
        if bundle == "stress_relaxation":
            plot_kwargs["y_padding_top"] = 0.12
            plot_kwargs["y_padding_bottom"] = 0.04

        outputs.append(
            _render_curve_like_plot(
                filename=filename,
                template=template,
                series_list=series_list,
                options=options,
                show_markers=show_markers,
                base_kwargs=plot_kwargs,
            )
        )
    return outputs


def _render_curve(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    bundle = detect_point_line_bundle(input_path, sheet)
    if bundle in {"frequency_sweep", "temperature_sweep", "stress_relaxation"}:
        return _render_rheology_bundle(bundle, "curve", input_path, sheet, options)
    series_list = load_curve_table_cached(input_path, sheet)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
    axis_mode = "auto_positive" if looks_like_tensile_curve(series_list) else "auto"
    return [
        _render_curve_like_plot(
            filename=f"{input_path.stem}_curve.pdf",
            template="curve",
            series_list=series_list,
            options=options,
            show_markers=False,
            base_kwargs={"axis_mode": axis_mode},
        )
    ]


def _render_point_line(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    bundle = detect_point_line_bundle(input_path, sheet)
    if bundle in {"frequency_sweep", "temperature_sweep", "stress_relaxation"}:
        return _render_rheology_bundle(bundle, "point_line", input_path, sheet, options)

    series_list = load_curve_table_cached(input_path, sheet)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
    axis_mode = "auto_positive" if looks_like_tensile_curve(series_list) else "auto"
    return [
        _render_curve_like_plot(
            filename=f"{input_path.stem}_point_line.pdf",
            template="point_line",
            series_list=series_list,
            options=options,
            show_markers=True,
            base_kwargs={"axis_mode": axis_mode},
        )
    ]


def _render_stacked_curve(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    series_list = load_curve_table_cached(input_path, sheet)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
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
    return [
        _rendered_plot_with_qa(
            filename=f"{input_path.stem}_stacked_curve.pdf",
            figure=fig,
            template="stacked_curve",
            options=options,
        )
    ]


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
    return [
        _rendered_plot_with_qa(
            filename=f"{input_path.stem}_segmented_stacked_curve.pdf",
            figure=fig,
            template="segmented_stacked_curve",
            options=options,
        )
    ]


def _render_bar(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table_cached(input_path, sheet)
    stats_profile = _stats_profile(groups)
    fig, _ = plot_bar(
        groups,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        bar_width=stats_profile.bar_width,
        spacing_scale=stats_profile.spacing_scale,
        capsize=stats_profile.capsize,
        show_raw_points=stats_profile.show_raw_points,
        raw_point_size=stats_profile.raw_point_size,
        raw_point_alpha=stats_profile.raw_point_alpha,
    )
    return [
        _rendered_plot_with_qa(
            filename=f"{predict_bar_box_slug(groups)}_bar.pdf",
            figure=fig,
            template="bar",
            options=options,
            autofixes_applied=("stats_spacing_profile", "bar_capsize_profile")
            + (("bar_raw_points_overlay",) if stats_profile.show_raw_points else ()),
        )
    ]


def _render_box(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table_cached(input_path, sheet)
    stats_profile = _stats_profile(groups)
    fig, _ = plot_box(
        groups,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        box_width=stats_profile.box_width,
        spacing_scale=stats_profile.spacing_scale,
    )
    return [
        _rendered_plot_with_qa(
            filename=f"{predict_bar_box_slug(groups)}_box.pdf",
            figure=fig,
            template="box",
            options=options,
            autofixes_applied=("stats_spacing_profile",),
        )
    ]


def _render_violin(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table_cached(input_path, sheet)
    stats_profile = _stats_profile(groups)
    fig, _ = plot_violin(
        groups,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        violin_width=stats_profile.violin_width,
        spacing_scale=stats_profile.spacing_scale,
    )
    return [
        _rendered_plot_with_qa(
            filename=f"{predict_bar_box_slug(groups)}_violin.pdf",
            figure=fig,
            template="violin",
            options=options,
            autofixes_applied=("stats_spacing_profile",),
        )
    ]


def _render_scatter(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    series_list = load_curve_table_cached(input_path, sheet)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
    axis_mode = "auto_positive" if looks_like_tensile_curve(series_list) else "auto"
    return [
        _render_curve_like_plot(
            filename=f"{input_path.stem}_scatter.pdf",
            template="scatter",
            series_list=series_list,
            options=options,
            show_markers=False,
            scatter=True,
            base_kwargs={"axis_mode": axis_mode},
        )
    ]


def _render_heatmap(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    table = load_heatmap_table_cached(input_path, sheet)
    layout = _heatmap_editorial_layout()
    fig, _ = plot_heatmap(
        table,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        show_colorbar=options.show_colorbar,
        palette_preset=options.palette_preset,
        colorbar_layout={
            "colorbar_x_offset_fraction": layout.colorbar_x_offset_fraction,
            "colorbar_width_fraction": layout.colorbar_width_fraction,
            "colorbar_y_offset_fraction": layout.colorbar_y_offset_fraction,
            "colorbar_height_fraction": layout.colorbar_height_fraction,
        },
        colorbar_tick_count=layout.colorbar_tick_count,
        colorbar_label_gap_pt=layout.label_gap_pt,
    )
    autofixes = ("heatmap_colorbar_tuned",) if options.show_colorbar else ()
    return [
        _rendered_plot_with_qa(
            filename=f"{input_path.stem}_heatmap.pdf",
            figure=fig,
            template="heatmap",
            options=options,
            autofixes_applied=autofixes,
        )
    ]


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
