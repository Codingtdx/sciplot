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
from src.rendering.dataset_models import build_normalized_dataset
from src.rendering.models import RenderedPlot, RenderOptions, TemplateName, TemplateRenderer
from src.rendering.options import resolve_render_options, validate_template_name
from src.rendering.qa import (
    CurveAutofix,
    analyze_rendered_figure,
    apply_curve_autofix,
    recommend_curve_autofix,
)


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


@dataclass(frozen=True)
class CompactCurveEditorialProfile:
    direct_label_inset_fraction: float
    direct_label_offset_pt: float
    direct_label_search_band_fraction: float
    tick_width_scale: float
    tick_length_scale: float
    legend_max_series: int
    legend_columns: int
    legend_font_scale: float
    legend_handlelength: float
    legend_handletextpad: float
    legend_columnspacing: float
    legend_borderpad: float


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


def _compact_curve_editorial_profile() -> CompactCurveEditorialProfile:
    profile = qa_profile("curve")
    return CompactCurveEditorialProfile(
        direct_label_inset_fraction=float(profile.get("compact_direct_label_inset_fraction", 0.04)),
        direct_label_offset_pt=float(profile.get("compact_direct_label_offset_pt", 4.0)),
        direct_label_search_band_fraction=float(profile.get("compact_direct_label_search_band_fraction", 0.12)),
        tick_width_scale=float(profile.get("compact_tick_width_scale", 0.82)),
        tick_length_scale=float(profile.get("compact_tick_length_scale", 0.88)),
        legend_max_series=int(profile.get("compact_legend_max_series", 3)),
        legend_columns=int(profile.get("compact_legend_columns", 2)),
        legend_font_scale=float(profile.get("compact_legend_font_scale", 0.92)),
        legend_handlelength=float(profile.get("compact_legend_handlelength", 1.35)),
        legend_handletextpad=float(profile.get("compact_legend_handletextpad", 0.35)),
        legend_columnspacing=float(profile.get("compact_legend_columnspacing", 0.8)),
        legend_borderpad=float(profile.get("compact_legend_borderpad", 0.15)),
    )


def _is_compact_curve_panel(options: RenderOptions) -> bool:
    profile = qa_profile("curve")
    return bool(
        np.isclose(options.width_mm, float(profile.get("small_panel_width_mm", options.width_mm)), atol=0.05)
        and np.isclose(options.height_mm, float(profile.get("small_panel_height_mm", options.height_mm)), atol=0.05)
    )


def _prefer_compact_legend(options: RenderOptions, series_count: int) -> bool:
    profile = _compact_curve_editorial_profile()
    return _is_compact_curve_panel(options) and 1 < series_count <= profile.legend_max_series


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


def _compact_curve_fix(options: RenderOptions) -> CurveAutofix:
    if not _is_compact_curve_panel(options):
        return CurveAutofix()
    profile = _compact_curve_editorial_profile()
    return CurveAutofix(
        tick_width_scale=profile.tick_width_scale,
        tick_length_scale=profile.tick_length_scale,
        autofixes_applied=("compact_tick_hierarchy",),
    )


def _merge_curve_fixes(*fixes: CurveAutofix) -> CurveAutofix:
    marker_every = None
    marker_size_scale = 1.0
    tick_width_scale = 1.0
    tick_length_scale = 1.0
    line_width_scale = 1.0
    collection_size_scale = 1.0
    autofixes: list[str] = []
    for fix in fixes:
        if fix.marker_every is not None:
            marker_every = max(marker_every or fix.marker_every, fix.marker_every)
        marker_size_scale *= fix.marker_size_scale
        tick_width_scale *= fix.tick_width_scale
        tick_length_scale *= fix.tick_length_scale
        line_width_scale *= fix.line_width_scale
        collection_size_scale *= fix.collection_size_scale
        autofixes.extend(fix.autofixes_applied)
    return CurveAutofix(
        marker_every=marker_every,
        marker_size_scale=marker_size_scale,
        tick_width_scale=tick_width_scale,
        tick_length_scale=tick_length_scale,
        line_width_scale=line_width_scale,
        collection_size_scale=collection_size_scale,
        autofixes_applied=tuple(dict.fromkeys(autofixes)),
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
    unsafe_issue_ids = {"series_identification", "label_out_of_bounds", "label_collision"}
    if any(issue.id in unsafe_issue_ids for issue in qa.issues):
        return (-1.0, -999, 0)
    critical_count = sum(1 for issue in qa.issues if issue.severity == "critical")
    direct_bonus = 2 if strategy.startswith("direct") else 1 if strategy == "compact_legend" else 0
    return (qa.score, -critical_count, direct_bonus)


def _resolve_visual_edge_target(
    x_values: np.ndarray,
    *,
    reverse_x: bool,
    side: str,
    inset_fraction: float,
) -> float:
    x_min = float(np.min(x_values))
    x_max = float(np.max(x_values))
    span = x_max - x_min
    if np.isclose(span, 0.0):
        return x_min
    if side == "left":
        return x_max - span * inset_fraction if reverse_x else x_min + span * inset_fraction
    return x_min + span * inset_fraction if reverse_x else x_max - span * inset_fraction


def _display_point_offset(fig: plt.Figure, value_pt: float) -> float:
    return max(value_pt, 0.0) * fig.dpi / 72.0


def _measure_label_bbox(
    ax: plt.Axes,
    renderer,
    *,
    label_text: str,
    color: object,
    fontsize: float,
    horizontal_alignment: str,
) -> tuple[float, float]:
    probe = ax.text(
        0.5,
        0.5,
        label_text,
        fontsize=fontsize,
        color=color,
        ha=horizontal_alignment,
        va="center",
        alpha=0.0,
        transform=ax.transAxes,
    )
    bbox = probe.get_window_extent(renderer=renderer)
    probe.remove()
    return float(bbox.width), float(bbox.height)


def _spread_label_centers(
    desired: np.ndarray,
    heights: np.ndarray,
    *,
    lower: float,
    upper: float,
    gap_px: float,
) -> np.ndarray | None:
    if desired.size == 0:
        return np.array([], dtype=float)
    order = np.argsort(desired)
    ordered_desired = desired[order]
    ordered_heights = heights[order]
    centers = ordered_desired.copy()
    lower_bounds = lower + ordered_heights / 2.0
    upper_bounds = upper - ordered_heights / 2.0
    centers[0] = np.clip(centers[0], lower_bounds[0], upper_bounds[0])
    for idx in range(1, len(centers)):
        required_gap = max(gap_px, (ordered_heights[idx - 1] + ordered_heights[idx]) / 2.0 + 1.0)
        centers[idx] = max(np.clip(centers[idx], lower_bounds[idx], upper_bounds[idx]), centers[idx - 1] + required_gap)
    overflow = max(centers[-1] - upper_bounds[-1], 0.0)
    if overflow > 0:
        centers -= overflow
    for idx in range(len(centers) - 2, -1, -1):
        required_gap = max(gap_px, (ordered_heights[idx] + ordered_heights[idx + 1]) / 2.0 + 1.0)
        centers[idx] = min(centers[idx], centers[idx + 1] - required_gap)
    underflow = max(lower_bounds[0] - centers[0], 0.0)
    if underflow > 0:
        centers += underflow
    for idx in range(1, len(centers)):
        required_gap = max(gap_px, (ordered_heights[idx - 1] + ordered_heights[idx]) / 2.0 + 1.0)
        centers[idx] = max(centers[idx], centers[idx - 1] + required_gap)
    if np.any(centers < lower_bounds - 1e-6) or np.any(centers > upper_bounds + 1e-6):
        return None
    result = np.empty_like(centers)
    result[order] = centers
    return result


def _series_display_colors(ax: plt.Axes, series_count: int) -> list[object]:
    if len(ax.lines) >= series_count:
        return [line.get_color() for line in ax.lines[:series_count]]
    if len(ax.collections) >= series_count:
        colors: list[object] = []
        for collection in ax.collections[:series_count]:
            facecolors = collection.get_facecolors()
            colors.append(tuple(facecolors[0]) if len(facecolors) else "black")
        return colors
    return list(plot_style.get_categorical_palette(n_colors=series_count))


def _place_endpoint_direct_labels(
    ax: plt.Axes,
    series_list,
    *,
    reverse_x: bool,
    side: str,
    inset_fraction: float,
    label_offset_pt: float,
    fontsize: float,
) -> bool:
    fig = ax.figure
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    axes_bbox = ax.get_window_extent(renderer=renderer)
    colors = _series_display_colors(ax, len(series_list))
    offset_px = _display_point_offset(fig, max(label_offset_pt, 3.5))
    gap_px = _display_point_offset(fig, 2.6)
    margin_px = 1.5

    desired_y: list[float] = []
    widths: list[float] = []
    heights: list[float] = []
    anchor_x: list[float] = []
    labels: list[str] = []
    text_colors: list[object] = []

    alignment = "right" if side == "left" else "left"

    for series, color in zip(series_list, colors, strict=True):
        x = series.data["x"].to_numpy(dtype=float)
        y = series.data["y"].to_numpy(dtype=float)
        valid = np.isfinite(x) & np.isfinite(y)
        x = x[valid]
        y = y[valid]
        if len(x) < 2:
            return False
        order = np.argsort(x)
        x = x[order]
        y = y[order]
        target_x = _resolve_visual_edge_target(x, reverse_x=reverse_x, side=side, inset_fraction=inset_fraction)
        target_y = float(np.interp(target_x, x, y))
        curve_px = ax.transData.transform((target_x, target_y))
        label_text = str(series.sample)
        width_px, height_px = _measure_label_bbox(
            ax,
            renderer,
            label_text=label_text,
            color=color,
            fontsize=fontsize,
            horizontal_alignment=alignment,
        )
        if width_px > axes_bbox.width - 2.0 * margin_px:
            return False
        if side == "left":
            anchor = min(curve_px[0] - offset_px, axes_bbox.x1 - margin_px)
            anchor = max(anchor, axes_bbox.x0 + width_px + margin_px)
            if anchor - width_px < axes_bbox.x0 + margin_px - 1e-6:
                return False
        else:
            anchor = max(curve_px[0] + offset_px, axes_bbox.x0 + margin_px)
            anchor = min(anchor, axes_bbox.x1 - width_px - margin_px)
            if anchor + width_px > axes_bbox.x1 - margin_px + 1e-6:
                return False
        desired_y.append(float(curve_px[1]))
        widths.append(width_px)
        heights.append(height_px)
        anchor_x.append(float(anchor))
        labels.append(label_text)
        text_colors.append(color)

    centers = _spread_label_centers(
        np.asarray(desired_y, dtype=float),
        np.asarray(heights, dtype=float),
        lower=float(axes_bbox.y0 + margin_px),
        upper=float(axes_bbox.y1 - margin_px),
        gap_px=gap_px,
    )
    if centers is None:
        return False

    inverse = ax.transData.inverted()
    for x_px, y_px, label_text, color in zip(anchor_x, centers, labels, text_colors, strict=True):
        data_x, data_y = inverse.transform((x_px, y_px))
        ax.text(
            float(data_x),
            float(data_y),
            label_text,
            ha=alignment,
            va="center",
            color=color,
            fontsize=fontsize,
            clip_on=True,
            zorder=4.5,
        )
    return True


def _ensure_direct_labels(
    ax: plt.Axes,
    series_list,
    *,
    options: RenderOptions,
    reverse_x: bool,
    side: str,
    fontsize: float = 6.0,
) -> bool:
    existing = [text for text in ax.texts if text.get_visible() and str(text.get_text()).strip()]
    if len(existing) == len(series_list):
        return True
    for text in tuple(ax.texts):
        text.remove()
    profile = _compact_curve_editorial_profile()
    colors = _series_display_colors(ax, len(series_list))
    if _place_series_edge_labels(
        ax,
        series_list,
        colors,
        reverse_x=reverse_x,
        side=side,
        inset_fraction=profile.direct_label_inset_fraction,
        label_offset_pt=profile.direct_label_offset_pt,
        search_band_fraction=profile.direct_label_search_band_fraction,
        fontsize=fontsize,
    ):
        return True
    if not _is_compact_curve_panel(options):
        return False
    return _place_endpoint_direct_labels(
        ax,
        series_list,
        reverse_x=reverse_x,
        side=side,
        inset_fraction=profile.direct_label_inset_fraction,
        label_offset_pt=profile.direct_label_offset_pt,
        fontsize=fontsize,
    )


def _apply_compact_inside_legend(ax: plt.Axes, *, series_count: int) -> bool:
    if series_count < 2:
        return False
    handles, labels = ax.get_legend_handles_labels()
    visible_labels = [label for label in labels if not str(label).startswith("_")]
    if len(visible_labels) < 2:
        return False
    profile = _compact_curve_editorial_profile()
    inset = plot_style.current_spacing().legend_inset_fraction
    legend = ax.legend(
        handles,
        labels,
        loc="upper center",
        bbox_to_anchor=(0.5, 1.0 - inset),
        bbox_transform=ax.transAxes,
        borderaxespad=0.0,
        frameon=False,
        ncol=min(profile.legend_columns, len(visible_labels)),
        fontsize=plot_style.current_typography().legend_font_size_pt * profile.legend_font_scale,
        handlelength=profile.legend_handlelength,
        handletextpad=profile.legend_handletextpad,
        columnspacing=profile.legend_columnspacing,
        labelspacing=0.25,
        borderpad=profile.legend_borderpad,
    )
    ax.figure.canvas.draw()
    renderer = ax.figure.canvas.get_renderer()
    axes_bbox = ax.get_window_extent(renderer=renderer)
    legend_bbox = legend.get_window_extent(renderer=renderer)
    if (
        legend_bbox.x0 < axes_bbox.x0
        or legend_bbox.x1 > axes_bbox.x1
        or legend_bbox.y0 < axes_bbox.y0
        or legend_bbox.y1 > axes_bbox.y1
    ):
        legend.remove()
        return False
    return True


def _render_curve_candidate(
    *,
    filename: str,
    template: str,
    series_list,
    options: RenderOptions,
    show_markers: bool,
    scatter: bool,
    direct_label_side: str | None,
    legend_variant: str,
    base_kwargs: dict[str, object],
) -> tuple[RenderedPlot, str]:
    combined_fix = _merge_curve_fixes(
        _curve_dense_fix(series_list, show_markers=show_markers, scatter=scatter),
        _compact_curve_fix(options),
    )
    compact_legend = legend_variant == "compact"
    strategy = (
        "compact_legend"
        if compact_legend
        else "legend"
        if direct_label_side is None
        else f"direct_{direct_label_side}"
    )
    autofixes = list(combined_fix.autofixes_applied)
    if direct_label_side is not None:
        autofixes.append("direct_series_labels")
    if compact_legend:
        autofixes.append("compact_inside_legend")

    if scatter:
        fig, ax = plot_scatter(
            series_list,
            axis_mode=str(base_kwargs.get("axis_mode", "auto")),
            xscale=options.xscale,
            yscale=options.yscale,
            width_mm=options.width_mm,
            height_mm=options.height_mm,
            reverse_x=options.reverse_x,
            legend_mode="none" if direct_label_side is not None or compact_legend else "inside_best",
            legend_expand_axes=str(base_kwargs.get("legend_expand_axes", "xy")),
            marker_size=14.0
            * (combined_fix.collection_size_scale if combined_fix.collection_size_scale != 1.0 else 1.0),
            visible_xticks=base_kwargs.get("visible_xticks"),
            xlim=base_kwargs.get("xlim"),
            y_padding_top=(
                _float_plot_kw(base_kwargs, "y_padding_top", 0.12) + 0.04
                if compact_legend
                else _float_plot_kw(base_kwargs, "y_padding_top", 0.12)
            ),
            y_padding_bottom=_float_plot_kw(base_kwargs, "y_padding_bottom", 0.06),
        )
        if direct_label_side is not None and len(series_list) > 1:
            _ensure_direct_labels(
                ax,
                series_list,
                options=options,
                reverse_x=options.reverse_x,
                side=direct_label_side,
            )
        elif compact_legend:
            _apply_compact_inside_legend(ax, series_count=len(series_list))
        applied = apply_curve_autofix(ax, _post_curve_fix(combined_fix, include_line_scale=False))
    else:
        marker_size = None
        if show_markers:
            marker_size = plot_style.current_stroke().marker_size_pt * combined_fix.marker_size_scale
        fig, ax = plot_curves(
            series_list,
            show_markers=show_markers,
            axis_mode=str(base_kwargs.get("axis_mode", "auto")),
            xscale=options.xscale,
            yscale=options.yscale,
            width_mm=options.width_mm,
            height_mm=options.height_mm,
            reverse_x=options.reverse_x,
            marker_every=combined_fix.marker_every if show_markers else None,
            marker_size=marker_size,
            legend_mode=(
                "none"
                if direct_label_side is not None or compact_legend
                else str(base_kwargs.get("legend_mode", "inside_best"))
            ),
            legend_expand_axes=str(base_kwargs.get("legend_expand_axes", "xy")),
            series_label_mode=(
                "edge"
                if direct_label_side is not None
                else str(base_kwargs.get("series_label_mode", "legend"))
            ),
            series_label_side=direct_label_side or str(base_kwargs.get("series_label_side", "auto")),
            visible_xticks=base_kwargs.get("visible_xticks"),
            xlim=base_kwargs.get("xlim"),
            y_padding_top=(
                _float_plot_kw(base_kwargs, "y_padding_top", 0.18) + 0.04
                if compact_legend
                else _float_plot_kw(base_kwargs, "y_padding_top", 0.18)
            ),
            y_padding_bottom=_float_plot_kw(base_kwargs, "y_padding_bottom", 0.06),
        )
        if direct_label_side is not None and len(series_list) > 1:
            _ensure_direct_labels(
                ax,
                series_list,
                options=options,
                reverse_x=options.reverse_x,
                side=direct_label_side,
            )
        elif compact_legend:
            _apply_compact_inside_legend(ax, series_count=len(series_list))
        applied = apply_curve_autofix(ax, _post_curve_fix(combined_fix, include_line_scale=show_markers))

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
            legend_variant="standard",
            base_kwargs=resolved_kwargs,
        )
    ]
    if _prefer_compact_legend(options, len(series_list)):
        candidates.append(
            _render_curve_candidate(
                filename=filename,
                template=template,
                series_list=series_list,
                options=options,
                show_markers=show_markers,
                scatter=scatter,
                direct_label_side=None,
                legend_variant="compact",
                base_kwargs=resolved_kwargs,
            )
        )
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
                    legend_variant="standard",
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
    normalized_dataset = build_normalized_dataset(input_path, sheet)
    if normalized_dataset.model in {"frequency_sweep", "temperature_sweep", "stress_relaxation"}:
        return _render_rheology_bundle(normalized_dataset.model, "curve", input_path, sheet, options)
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
    normalized_dataset = build_normalized_dataset(input_path, sheet)
    if normalized_dataset.model in {"frequency_sweep", "temperature_sweep", "stress_relaxation"}:
        return _render_rheology_bundle(normalized_dataset.model, "point_line", input_path, sheet, options)

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
    reverse_x: bool | None = None,
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
    reverse_x: bool | None = None,
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
