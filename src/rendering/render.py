from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib import transforms

from src import (
    mpl_backend,  # noqa: F401
    plot_style,
)
from src.layout_policy import (
    LayoutCandidate,
    LayoutScore,
    choose_layout_candidate,
    empty_layout_decision,
    flag_margin_fallback,
    record_layout_decision,
)
from src.layout_scoring import score_points_against_bbox
from src.plot_contract import qa_profile
from src.plot_style import save_pdf
from src.plotting import _format_axis_label, _place_series_edge_labels
from src.plotting_families.curve_family import plot_curves, plot_scatter
from src.plotting_families.heatmap_family import plot_heatmap
from src.plotting_families.layout_helpers import compute_shared_curve_x_layout
from src.plotting_families.spectral_family import plot_wide_nmr
from src.plotting_families.stats_family import plot_bar, plot_box, plot_point_error, plot_violin
from src.rendering.cache import (
    load_curve_table_cached,
    load_heatmap_table_cached,
    load_replicate_table_cached,
)
from src.rendering.common import (
    aligned_replicate_band,
    load_rheology_bundle_series,
    load_segmented_config,
    looks_like_tensile_curve,
    predict_bar_box_slug,
    rheology_output_filenames,
    summarize_replicate_distribution,
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
from src.rendering.style_composer import DEFAULT_STYLE_COMPOSER


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


@dataclass(frozen=True)
class HeatmapCellLabelPlacement:
    x: float
    y: float
    text: str
    color: str
    fontsize: float


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


def _plan_endpoint_direct_labels(
    ax: plt.Axes,
    series_list,
    *,
    reverse_x: bool,
    side: str,
    inset_fraction: float,
    label_offset_pt: float,
    fontsize: float,
) -> tuple[list[tuple[float, float, str, object]] | None, float, str]:
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
    curve_anchor_x: list[float] = []

    for series, color in zip(series_list, colors, strict=True):
        x = series.data["x"].to_numpy(dtype=float)
        y = series.data["y"].to_numpy(dtype=float)
        valid = np.isfinite(x) & np.isfinite(y)
        x = x[valid]
        y = y[valid]
        if len(x) < 2:
            return None, float("inf"), "insufficient_points"
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
            return None, float("inf"), "label_too_wide_for_axes"
        if side == "left":
            anchor = min(curve_px[0] - offset_px, axes_bbox.x1 - margin_px)
            anchor = max(anchor, axes_bbox.x0 + width_px + margin_px)
            if anchor - width_px < axes_bbox.x0 + margin_px - 1e-6:
                return None, float("inf"), "left_margin_overflow"
        else:
            anchor = max(curve_px[0] + offset_px, axes_bbox.x0 + margin_px)
            anchor = min(anchor, axes_bbox.x1 - width_px - margin_px)
            if anchor + width_px > axes_bbox.x1 - margin_px + 1e-6:
                return None, float("inf"), "right_margin_overflow"
        desired_y.append(float(curve_px[1]))
        widths.append(width_px)
        heights.append(height_px)
        anchor_x.append(float(anchor))
        curve_anchor_x.append(float(curve_px[0]))
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
        return None, float("inf"), "vertical_spread_failed"

    inverse = ax.transData.inverted()
    planned_labels: list[tuple[float, float, str, object]] = []
    horizontal_offset = 0.0
    for anchor_value, curve_value in zip(anchor_x, curve_anchor_x, strict=True):
        horizontal_offset += abs(anchor_value - curve_value)
    vertical_adjustment = float(np.mean(np.abs(np.asarray(desired_y, dtype=float) - centers)))
    for x_px, y_px, label_text, color in zip(anchor_x, centers, labels, text_colors, strict=True):
        data_x, data_y = inverse.transform((x_px, y_px))
        planned_labels.append(
            (
                float(data_x),
                float(data_y),
                label_text,
                color,
            )
        )
    score = horizontal_offset / max(len(planned_labels), 1) + vertical_adjustment * 0.45
    reason = (
        f"endpoint plan side={side}; horizontal_offset={horizontal_offset:.3f}; "
        f"vertical_adjustment={vertical_adjustment:.3f}"
    )
    return planned_labels, score, reason


def _apply_endpoint_direct_label_plan(
    ax: plt.Axes,
    *,
    planned_labels: list[tuple[float, float, str, object]],
    side: str,
    fontsize: float,
) -> None:
    alignment = "right" if side == "left" else "left"
    for x_pos, y_pos, label_text, color in planned_labels:
        ax.text(
            x_pos,
            y_pos,
            label_text,
            ha=alignment,
            va="center",
            color=color,
            fontsize=fontsize,
            clip_on=True,
            zorder=4.5,
        )


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
        record_layout_decision(
            ax.figure,
            empty_layout_decision("endpoint_direct_labels", reason="not_compact_panel"),
            context={"path": "render_direct_labels", "phase": "fallback_gate"},
        )
        return False
    side_candidates = [side] if side in {"left", "right"} else ["right", "left"]
    if len(side_candidates) == 1:
        alternate = "right" if side_candidates[0] == "left" else "left"
        side_candidates.append(alternate)

    plan_cache: dict[str, tuple[list[tuple[float, float, str, object]] | None, float, str]] = {}
    candidates = [
        LayoutCandidate(
            candidate_id=f"endpoint_{candidate_side}",
            payload={"side": candidate_side, "bias": 0.0 if candidate_side == side_candidates[0] else 22.0},
            standoff_pt=float(profile.direct_label_offset_pt),
            notes="endpoint direct-label fallback candidate",
        )
        for candidate_side in side_candidates
    ]

    def _score(candidate: LayoutCandidate) -> LayoutScore:
        payload = candidate.payload if isinstance(candidate.payload, dict) else {}
        candidate_side = str(payload.get("side", side_candidates[0]))
        bias = float(payload.get("bias", 0.0))
        plan, plan_score, reason = _plan_endpoint_direct_labels(
            ax,
            series_list,
            reverse_x=reverse_x,
            side=candidate_side,
            inset_fraction=profile.direct_label_inset_fraction,
            label_offset_pt=profile.direct_label_offset_pt,
            fontsize=fontsize,
        )
        plan_cache[candidate.candidate_id] = (plan, plan_score, reason)
        if plan is None:
            return LayoutScore(score=1_000_000_000.0, blocked=True, reason=reason)
        return LayoutScore(
            score=float(plan_score + bias),
            blocked=False,
            reason=f"{reason}; bias={bias:.3f}",
        )

    decision = choose_layout_candidate(
        object_kind="endpoint_direct_labels",
        candidates=candidates,
        score_hook=_score,
    )
    chosen = decision.chosen_candidate
    if chosen is None:
        record_layout_decision(
            ax.figure,
            flag_margin_fallback(
                decision,
                action="endpoint_labels_unavailable",
                reason="both sides failed compact endpoint fallback",
            ),
            context={"path": "render_direct_labels", "phase": "endpoint_policy"},
        )
        return False
    chosen_plan, _chosen_score, chosen_reason = plan_cache.get(
        chosen.candidate_id,
        (None, float("inf"), "missing_plan"),
    )
    if chosen_plan is None:
        record_layout_decision(
            ax.figure,
            flag_margin_fallback(
                decision,
                action="endpoint_labels_missing_plan",
                reason=chosen_reason,
            ),
            context={"path": "render_direct_labels", "phase": "endpoint_policy"},
        )
        return False

    chosen_payload = chosen.payload if isinstance(chosen.payload, dict) else {}
    chosen_side = str(chosen_payload.get("side", side_candidates[0]))
    if chosen_side != side_candidates[0]:
        decision = flag_margin_fallback(
            decision,
            action=f"switch_side:{chosen_side}",
            reason=f"preferred side '{side_candidates[0]}' failed endpoint plan",
        )
    record_layout_decision(
        ax.figure,
        decision,
        context={"path": "render_direct_labels", "phase": "endpoint_policy"},
    )
    _apply_endpoint_direct_label_plan(
        ax,
        planned_labels=chosen_plan,
        side=chosen_side,
        fontsize=fontsize,
    )
    return True


def _collect_axis_display_points(ax: plt.Axes, *, max_points: int = 3200) -> np.ndarray:
    point_blocks: list[np.ndarray] = []
    for line in ax.lines:
        x_values = np.asarray(line.get_xdata(), dtype=float)
        y_values = np.asarray(line.get_ydata(), dtype=float)
        valid = np.isfinite(x_values) & np.isfinite(y_values)
        if not np.any(valid):
            continue
        transformed = ax.transData.transform(np.column_stack([x_values[valid], y_values[valid]]))
        if len(transformed) > max_points:
            indices = np.linspace(0, len(transformed) - 1, max_points, dtype=int)
            transformed = transformed[indices]
        point_blocks.append(transformed)
    for collection in ax.collections:
        offsets = np.asarray(collection.get_offsets(), dtype=float)
        if offsets.size == 0:
            continue
        valid = np.isfinite(offsets[:, 0]) & np.isfinite(offsets[:, 1])
        transformed = ax.transData.transform(offsets[valid])
        if len(transformed) > max_points:
            indices = np.linspace(0, len(transformed) - 1, max_points, dtype=int)
            transformed = transformed[indices]
        point_blocks.append(transformed)
    if not point_blocks:
        return np.empty((0, 2), dtype=float)
    stacked = np.vstack(point_blocks)
    if len(stacked) > max_points:
        indices = np.linspace(0, len(stacked) - 1, max_points, dtype=int)
        stacked = stacked[indices]
    return stacked


def _compact_legend_candidates(inset: float) -> list[LayoutCandidate]:
    return [
        LayoutCandidate(
            candidate_id="compact_upper_center",
            anchor=(0.5, 1.0 - inset),
            standoff_pt=inset * 72.0,
            payload={"loc": "upper center", "alignment": "center", "bias": 0.0},
            notes="primary compact legend candidate",
        ),
        LayoutCandidate(
            candidate_id="compact_upper_left",
            anchor=(inset, 1.0 - inset),
            standoff_pt=inset * 72.0,
            payload={"loc": "upper left", "alignment": "left", "bias": 2.4},
            notes="compact legend fallback candidate",
        ),
        LayoutCandidate(
            candidate_id="compact_upper_right",
            anchor=(1.0 - inset, 1.0 - inset),
            standoff_pt=inset * 72.0,
            payload={"loc": "upper right", "alignment": "right", "bias": 2.8},
            notes="compact legend fallback candidate",
        ),
    ]


def _apply_compact_inside_legend(ax: plt.Axes, *, series_count: int) -> bool:
    if series_count < 2:
        record_layout_decision(
            ax.figure,
            empty_layout_decision("compact_legend", reason="series_count<2"),
            context={"path": "render_compact_legend", "phase": "candidate_selection"},
        )
        return False
    handles, labels = ax.get_legend_handles_labels()
    visible_labels = [label for label in labels if not str(label).startswith("_")]
    if len(visible_labels) < 2:
        record_layout_decision(
            ax.figure,
            empty_layout_decision("compact_legend", reason="insufficient_visible_labels"),
            context={"path": "render_compact_legend", "phase": "candidate_selection"},
        )
        return False
    profile = _compact_curve_editorial_profile()
    inset = plot_style.current_spacing().legend_inset_fraction
    candidates = _compact_legend_candidates(inset)
    data_points = _collect_axis_display_points(ax)

    def _score(candidate: LayoutCandidate) -> LayoutScore:
        payload = candidate.payload if isinstance(candidate.payload, dict) else {}
        anchor = candidate.anchor if candidate.anchor is not None else (0.5, 1.0 - inset)
        legend = ax.legend(
            handles,
            labels,
            loc=str(payload.get("loc", "upper center")),
            bbox_to_anchor=anchor,
            bbox_transform=ax.transAxes,
            borderaxespad=0.0,
            alignment=str(payload.get("alignment", "center")),
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
        legend.remove()
        if (
            legend_bbox.x0 < axes_bbox.x0
            or legend_bbox.x1 > axes_bbox.x1
            or legend_bbox.y0 < axes_bbox.y0
            or legend_bbox.y1 > axes_bbox.y1
        ):
            return LayoutScore(score=1_000_000_000.0, blocked=True, reason="legend_out_of_axes")
        overlap_metrics = score_points_against_bbox(
            data_points,
            legend_bbox,
            inside_weight=12.0,
            near_radius=11.0,
            near_weight=1.0,
            normalize_near=True,
        )
        axes_area = max(float(axes_bbox.width) * float(axes_bbox.height), 1.0)
        legend_area = max(float(legend_bbox.width) * float(legend_bbox.height), 0.0)
        footprint = legend_area / axes_area
        bias = float(payload.get("bias", 0.0))
        score = overlap_metrics.total + footprint * 40.0 + bias
        return LayoutScore(
            score=score,
            blocked=False,
            reason=(
                f"compact overlap={overlap_metrics.total:.4f}; footprint={footprint:.4f}; "
                f"bias={bias:.3f}"
            ),
        )

    decision = choose_layout_candidate(
        object_kind="compact_legend",
        candidates=candidates,
        score_hook=_score,
    )
    chosen = decision.chosen_candidate
    if chosen is None:
        record_layout_decision(
            ax.figure,
            flag_margin_fallback(
                decision,
                action="compact_legend_rejected",
                reason="no in-axes compact legend candidate remained viable",
            ),
            context={"path": "render_compact_legend", "phase": "candidate_selection"},
        )
        return False
    chosen_payload = chosen.payload if isinstance(chosen.payload, dict) else {}
    chosen_anchor = chosen.anchor if chosen.anchor is not None else (0.5, 1.0 - inset)
    ax.legend(
        handles,
        labels,
        loc=str(chosen_payload.get("loc", "upper center")),
        bbox_to_anchor=chosen_anchor,
        bbox_transform=ax.transAxes,
        borderaxespad=0.0,
        alignment=str(chosen_payload.get("alignment", "center")),
        frameon=False,
        ncol=min(profile.legend_columns, len(visible_labels)),
        fontsize=plot_style.current_typography().legend_font_size_pt * profile.legend_font_scale,
        handlelength=profile.legend_handlelength,
        handletextpad=profile.legend_handletextpad,
        columnspacing=profile.legend_columnspacing,
        labelspacing=0.25,
        borderpad=profile.legend_borderpad,
    )
    if chosen.candidate_id != "compact_upper_center":
        decision = flag_margin_fallback(
            decision,
            action=f"compact_anchor:{chosen.candidate_id}",
            reason="primary compact anchor downgraded by collision/footprint score",
        )
    record_layout_decision(
        ax.figure,
        decision,
        context={"path": "render_compact_legend", "phase": "candidate_selection"},
    )
    ax.figure.canvas.draw()
    renderer = ax.figure.canvas.get_renderer()
    axes_bbox = ax.get_window_extent(renderer=renderer)
    legend = ax.get_legend()
    if legend is None:
        return False
    legend_bbox = legend.get_window_extent(renderer=renderer)
    if (
        legend_bbox.x0 < axes_bbox.x0
        or legend_bbox.x1 > axes_bbox.x1
        or legend_bbox.y0 < axes_bbox.y0
        or legend_bbox.y1 > axes_bbox.y1
    ):
        legend.remove()
        record_layout_decision(
            ax.figure,
            empty_layout_decision("compact_legend", reason="post_apply_bbox_validation_failed"),
            context={"path": "render_compact_legend", "phase": "post_validation"},
        )
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


def _render_grouped_bar_compare(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    return _render_grouped_bar_error_like(
        input_path,
        sheet,
        options,
        template="grouped_bar_compare",
        filename_suffix="grouped_bar_compare",
        profile_autofix="grouped_bar_compare_profile",
    )


def _render_grouped_bar_error(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    return _render_grouped_bar_error_like(
        input_path,
        sheet,
        options,
        template="grouped_bar_error",
        filename_suffix="grouped_bar_error",
        profile_autofix="grouped_bar_error_profile",
    )


def _render_point_error(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table_cached(input_path, sheet)
    if not groups:
        raise ValueError("No valid groups were found in the replicate table.")
    stats_profile = _stats_profile(groups)
    fig, _ = plot_point_error(
        groups,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        point_spacing_width=max(0.22, stats_profile.bar_width * 0.85),
        spacing_scale=max(1.0, stats_profile.spacing_scale),
        capsize=stats_profile.capsize,
        marker_size_pt=max(4.2, plot_style.current_stroke().marker_size_pt * 0.9),
        show_raw_points=stats_profile.show_raw_points,
        raw_point_size=stats_profile.raw_point_size,
        raw_point_alpha=stats_profile.raw_point_alpha,
    )
    return [
        _rendered_plot_with_qa(
            filename=f"{predict_bar_box_slug(groups)}_point_error.pdf",
            figure=fig,
            template="point_error",
            options=options,
            autofixes_applied=(
                "stats_spacing_profile",
                "point_error_capsize_profile",
                "point_error_profile",
            )
            + (("point_error_raw_points_overlay",) if stats_profile.show_raw_points else ()),
        )
    ]


def _render_lollipop_error(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table_cached(input_path, sheet)
    if not groups:
        raise ValueError("No valid groups were found in the replicate table.")
    stats_profile = _stats_profile(groups)
    fig, ax = plot_point_error(
        groups,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        axis_mode="auto_positive",
        point_spacing_width=max(0.22, stats_profile.bar_width * 0.82),
        spacing_scale=max(1.0, stats_profile.spacing_scale),
        capsize=stats_profile.capsize,
        marker_size_pt=max(4.4, plot_style.current_stroke().marker_size_pt * 0.94),
        show_raw_points=stats_profile.show_raw_points,
        raw_point_size=stats_profile.raw_point_size,
        raw_point_alpha=stats_profile.raw_point_alpha,
    )
    palette = plot_style.get_categorical_palette(n_colors=len(groups))
    means = np.array([float(group.data.mean()) for group in groups], dtype=float)
    positions = np.asarray(ax.get_xticks(), dtype=float)
    if positions.size != len(groups):
        positions = np.arange(len(groups), dtype=float)
    baseline = 0.0 if np.nanmin(means) >= 0.0 else float(ax.get_ylim()[0])
    if baseline < float(ax.get_ylim()[0]):
        ax.set_ylim(bottom=baseline)
    for pos, mean, color in zip(positions, means, palette, strict=True):
        ax.vlines(
            pos,
            baseline,
            mean,
            color=color,
            linewidth=max(0.95, plot_style.current_stroke().line_width_pt * 0.85),
            alpha=min(0.94, plot_style.current_stroke().line_alpha + 0.08),
            zorder=3.0,
        )
    return [
        _rendered_plot_with_qa(
            filename=f"{predict_bar_box_slug(groups)}_lollipop_error.pdf",
            figure=fig,
            template="lollipop_error",
            options=options,
            autofixes_applied=(
                "stats_spacing_profile",
                "point_error_capsize_profile",
                "lollipop_stem_overlay",
                "lollipop_error_profile",
            )
            + (("point_error_raw_points_overlay",) if stats_profile.show_raw_points else ()),
        )
    ]


def _render_grouped_bar_error_like(
    input_path: Path,
    sheet: str | int,
    options: RenderOptions,
    *,
    template: str,
    filename_suffix: str,
    profile_autofix: str,
) -> list[RenderedPlot]:
    groups = load_replicate_table_cached(input_path, sheet)
    if len(groups) < 2:
        raise ValueError(f"{template} requires at least two replicate groups.")
    stats_profile = _stats_profile(groups)
    fig, _ = plot_bar(
        groups,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        bar_width=max(0.2, stats_profile.bar_width * 0.9),
        spacing_scale=max(1.02, stats_profile.spacing_scale),
        capsize=stats_profile.capsize,
        show_raw_points=True,
        raw_point_size=max(stats_profile.raw_point_size, 10.0),
        raw_point_alpha=max(stats_profile.raw_point_alpha, 0.72),
    )
    return [
        _rendered_plot_with_qa(
            filename=f"{predict_bar_box_slug(groups)}_{filename_suffix}.pdf",
            figure=fig,
            template=template,
            options=options,
            autofixes_applied=(
                "stats_spacing_profile",
                "bar_capsize_profile",
                "bar_raw_points_overlay",
                profile_autofix,
            ),
        )
    ]


def _emphasize_strip_point_overlay(
    ax: plt.Axes,
    *,
    min_size: float,
    min_alpha: float,
) -> None:
    for collection in ax.collections:
        sizes = np.asarray(collection.get_sizes(), dtype=float)
        if sizes.size:
            collection.set_sizes(np.maximum(sizes, min_size))
        collection.set_alpha(max(float(collection.get_alpha() or 0.0), min_alpha))


def _overlay_violin_box_summary(
    ax: plt.Axes,
    *,
    groups,
    positions: np.ndarray,
    box_width: float,
) -> None:
    values = [group.data.to_numpy(dtype=float) for group in groups]
    box = ax.boxplot(
        values,
        positions=positions,
        widths=box_width,
        patch_artist=True,
        showfliers=False,
        medianprops={"color": "black", "linewidth": max(1.0, plot_style.current_stroke().line_width_pt)},
        whiskerprops={"linewidth": 0.95, "color": "black"},
        capprops={"linewidth": 0.95, "color": "black"},
        boxprops={"linewidth": 0.95, "color": "black"},
    )
    for patch in box["boxes"]:
        patch.set_facecolor("none")
        patch.set_alpha(1.0)
        patch.set_edgecolor("black")


def _distribution_compare_variant(groups) -> tuple[str, str]:
    group_count = len(groups)
    replicate_counts = [len(group.data) for group in groups]
    min_replicates = min(replicate_counts) if replicate_counts else 0
    if group_count >= 6:
        return ("box", "Many groups default to box for cleaner side-by-side spread comparison.")
    if group_count <= 4 and min_replicates >= 6:
        return ("violin", "Higher replicate density with fewer groups defaults to violin for shape visibility.")
    return ("strip_box", "Moderate group/replicate density defaults to strip+box for balanced spread and readability.")


def _render_distribution_compare(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table_cached(input_path, sheet)
    if len(groups) < 2:
        raise ValueError("distribution_compare requires at least two replicate groups.")
    stats_profile = _stats_profile(groups)
    variant, _ = _distribution_compare_variant(groups)
    autofixes = ["stats_spacing_profile", f"distribution_variant_{variant}"]

    if variant == "violin":
        fig, _ = plot_violin(
            groups,
            width_mm=options.width_mm,
            height_mm=options.height_mm,
            violin_width=stats_profile.violin_width,
            spacing_scale=stats_profile.spacing_scale,
        )
    else:
        fig, ax = plot_box(
            groups,
            width_mm=options.width_mm,
            height_mm=options.height_mm,
            box_width=stats_profile.box_width,
            spacing_scale=stats_profile.spacing_scale,
        )
        if variant == "strip_box":
            _emphasize_strip_point_overlay(
                ax,
                min_size=stats_profile.raw_point_size,
                min_alpha=max(stats_profile.raw_point_alpha, 0.8),
            )
            autofixes.append("strip_point_overlay_emphasis")

    return [
        _rendered_plot_with_qa(
            filename=f"{predict_bar_box_slug(groups)}_distribution_compare.pdf",
            figure=fig,
            template="distribution_compare",
            options=options,
            autofixes_applied=tuple(autofixes),
        )
    ]


def _render_box_strip(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table_cached(input_path, sheet)
    if not groups:
        raise ValueError("No valid groups were found in the replicate table.")
    stats_profile = _stats_profile(groups)
    fig, ax = plot_box(
        groups,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        box_width=stats_profile.box_width,
        spacing_scale=stats_profile.spacing_scale,
    )
    _emphasize_strip_point_overlay(
        ax,
        min_size=max(stats_profile.raw_point_size, 11.0),
        min_alpha=max(stats_profile.raw_point_alpha, 0.82),
    )
    return [
        _rendered_plot_with_qa(
            filename=f"{predict_bar_box_slug(groups)}_box_strip.pdf",
            figure=fig,
            template="box_strip",
            options=options,
            autofixes_applied=(
                "stats_spacing_profile",
                "strip_point_overlay_emphasis",
                "box_strip_profile",
            ),
        )
    ]


def _render_violin_box(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table_cached(input_path, sheet)
    if not groups:
        raise ValueError("No valid groups were found in the replicate table.")
    stats_profile = _stats_profile(groups)
    fig, ax = plot_violin(
        groups,
        width_mm=options.width_mm,
        height_mm=options.height_mm,
        violin_width=stats_profile.violin_width,
        spacing_scale=stats_profile.spacing_scale,
    )
    positions = np.asarray(ax.get_xticks(), dtype=float)
    if positions.size == len(groups):
        _overlay_violin_box_summary(
            ax,
            groups=groups,
            positions=positions,
            box_width=max(0.16, stats_profile.violin_width * 0.42),
        )
    return [
        _rendered_plot_with_qa(
            filename=f"{predict_bar_box_slug(groups)}_violin_box.pdf",
            figure=fig,
            template="violin_box",
            options=options,
            autofixes_applied=(
                "stats_spacing_profile",
                "violin_box_overlay",
                "violin_box_profile",
            ),
        )
    ]


def _gaussian_density(values: np.ndarray, x_grid: np.ndarray) -> np.ndarray:
    if values.size == 0:
        return np.zeros_like(x_grid)
    std = float(np.std(values, ddof=1)) if values.size > 1 else 0.0
    iqr = float(np.subtract(*np.percentile(values, [75, 25]))) if values.size > 1 else 0.0
    robust_scale = min(std, iqr / 1.34) if std > 0 and iqr > 0 else max(std, iqr / 1.34, 0.0)
    if robust_scale <= 0:
        robust_scale = max(abs(float(values.mean())), 1.0) * 0.08
    bandwidth = max(1e-6, 1.06 * robust_scale * (values.size ** (-1.0 / 5.0)))
    z = (x_grid[:, None] - values[None, :]) / bandwidth
    kernel = np.exp(-0.5 * z * z) / np.sqrt(2.0 * np.pi)
    return kernel.mean(axis=1) / bandwidth


def _probe_heatmap_cell_text_bbox(
    ax: plt.Axes,
    *,
    renderer: object,
    x: float,
    y: float,
    text: str,
    fontsize: float,
) -> transforms.Bbox:
    probe = ax.text(
        x,
        y,
        text,
        ha="center",
        va="center",
        fontsize=fontsize,
        alpha=0.0,
        clip_on=True,
        zorder=4.2,
    )
    bbox = probe.get_window_extent(renderer=renderer)
    probe.remove()
    return bbox


def _heatmap_cell_display_bbox(ax: plt.Axes, *, x_idx: int, y_idx: int) -> transforms.Bbox:
    p0 = ax.transData.transform((float(x_idx), float(y_idx)))
    p1 = ax.transData.transform((float(x_idx + 1), float(y_idx + 1)))
    left = min(float(p0[0]), float(p1[0]))
    right = max(float(p0[0]), float(p1[0]))
    bottom = min(float(p0[1]), float(p1[1]))
    top = max(float(p0[1]), float(p1[1]))
    return transforms.Bbox.from_extents(left, bottom, right, top)


def _overflow_against_cell(text_bbox: transforms.Bbox, cell_bbox: transforms.Bbox) -> float:
    overflow = 0.0
    overflow += max(0.0, cell_bbox.x0 - text_bbox.x0)
    overflow += max(0.0, text_bbox.x1 - cell_bbox.x1)
    overflow += max(0.0, cell_bbox.y0 - text_bbox.y0)
    overflow += max(0.0, text_bbox.y1 - cell_bbox.y1)
    norm = max(cell_bbox.width + cell_bbox.height, 1.0)
    return overflow / norm


def _format_heatmap_cell_value(value: float, *, fmt: str) -> str:
    return f"{value:{fmt}}"


def _choose_annotated_heatmap_label_plan(
    *,
    fig: plt.Figure,
    ax: plt.Axes,
    values: np.ndarray,
    mid: float,
) -> tuple[list[HeatmapCellLabelPlacement], str]:
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    finite_cells = [
        (y_idx, x_idx, float(values[y_idx, x_idx]))
        for y_idx in range(values.shape[0])
        for x_idx in range(values.shape[1])
        if np.isfinite(values[y_idx, x_idx])
    ]
    if not finite_cells:
        record_layout_decision(
            fig,
            empty_layout_decision("annotation_textbox", reason="no_finite_heatmap_cells"),
            context={
                "path": "annotated_heatmap_cell_labels",
                "phase": "candidate_selection",
                "annotation_kind": "heatmap_cell_labels",
                "matrix_shape": [int(values.shape[0]), int(values.shape[1])],
                "finite_cells": 0,
            },
        )
        return [], "labels_none"

    candidates = [
        LayoutCandidate(
            candidate_id="labels_full",
            payload={"fmt": ".3g", "fontsize": 5.2, "checkerboard": False, "bias": 0.0},
            notes="full precision per-cell labels",
        ),
        LayoutCandidate(
            candidate_id="labels_compact",
            payload={"fmt": ".2g", "fontsize": 4.8, "checkerboard": False, "bias": 0.8},
            notes="compact precision per-cell labels",
        ),
        LayoutCandidate(
            candidate_id="labels_small",
            payload={"fmt": ".2g", "fontsize": 4.4, "checkerboard": False, "bias": 1.2},
            notes="small-font per-cell labels",
        ),
        LayoutCandidate(
            candidate_id="labels_checkerboard",
            payload={"fmt": ".2g", "fontsize": 4.8, "checkerboard": True, "bias": 2.8},
            notes="checkerboard fallback for dense matrices",
        ),
    ]
    plan_cache: dict[str, list[HeatmapCellLabelPlacement]] = {}

    def _score(candidate: LayoutCandidate) -> LayoutScore:
        payload = candidate.payload if isinstance(candidate.payload, dict) else {}
        fmt = str(payload.get("fmt", ".3g"))
        fontsize = float(payload.get("fontsize", 5.2))
        checkerboard = bool(payload.get("checkerboard", False))
        bias = float(payload.get("bias", 0.0))

        placements: list[HeatmapCellLabelPlacement] = []
        placed_bboxes: list[transforms.Bbox] = []
        overflow_total = 0.0
        overlap_count = 0
        hidden_count = 0

        for y_idx, x_idx, value in finite_cells:
            if checkerboard and ((x_idx + y_idx) % 2 == 1):
                hidden_count += 1
                continue
            text_value = _format_heatmap_cell_value(value, fmt=fmt)
            text_bbox = _probe_heatmap_cell_text_bbox(
                ax,
                renderer=renderer,
                x=float(x_idx + 0.5),
                y=float(y_idx + 0.5),
                text=text_value,
                fontsize=fontsize,
            )
            cell_bbox = _heatmap_cell_display_bbox(ax, x_idx=x_idx, y_idx=y_idx)
            overflow_total += _overflow_against_cell(text_bbox, cell_bbox)
            expanded = text_bbox.expanded(1.03, 1.10)
            if any(expanded.overlaps(other) for other in placed_bboxes):
                overlap_count += 1
            placed_bboxes.append(expanded)
            placements.append(
                HeatmapCellLabelPlacement(
                    x=float(x_idx + 0.5),
                    y=float(y_idx + 0.5),
                    text=text_value,
                    color="white" if value >= mid else "black",
                    fontsize=fontsize,
                )
            )

        if not placements:
            return LayoutScore(score=1_000_000_000.0, blocked=True, reason="no_visible_labels")

        shown = len(placements)
        total = len(finite_cells)
        overlap_ratio = overlap_count / shown
        overflow_ratio = overflow_total / shown
        hidden_ratio = hidden_count / total
        score = overlap_ratio * 260.0 + overflow_ratio * 62.0 + hidden_ratio * 28.0 + bias
        reason = (
            f"shown={shown}/{total}; overlap_ratio={overlap_ratio:.3f}; "
            f"overflow_ratio={overflow_ratio:.3f}; hidden_ratio={hidden_ratio:.3f}; bias={bias:.3f}"
        )
        plan_cache[candidate.candidate_id] = placements
        return LayoutScore(score=float(score), reason=reason)

    decision = choose_layout_candidate(
        object_kind="annotation_textbox",
        candidates=candidates,
        score_hook=_score,
    )
    if decision.chosen_candidate is None:
        record_layout_decision(
            fig,
            empty_layout_decision("annotation_textbox", reason="no_viable_heatmap_label_strategy"),
            context={
                "path": "annotated_heatmap_cell_labels",
                "phase": "candidate_selection",
                "annotation_kind": "heatmap_cell_labels",
                "matrix_shape": [int(values.shape[0]), int(values.shape[1])],
                "finite_cells": int(len(finite_cells)),
            },
        )
        return [], "labels_none"
    strategy_id = decision.chosen_candidate.candidate_id
    if strategy_id != "labels_full":
        decision = flag_margin_fallback(
            decision,
            action=f"heatmap_label_strategy:{strategy_id}",
            reason="default full-label strategy was not optimal for this matrix density",
        )
    record_layout_decision(
        fig,
        decision,
        context={
            "path": "annotated_heatmap_cell_labels",
            "phase": "candidate_selection",
            "annotation_kind": "heatmap_cell_labels",
            "matrix_shape": [int(values.shape[0]), int(values.shape[1])],
            "finite_cells": int(len(finite_cells)),
        },
    )
    return plan_cache.get(strategy_id, []), strategy_id


def _render_histogram_density(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    groups = load_replicate_table_cached(input_path, sheet)
    if not groups:
        raise ValueError("No valid groups were found in the replicate table.")

    summary = summarize_replicate_distribution(groups)
    fig, ax = plot_style.create_panel_figure(width_mm=options.width_mm, height_mm=options.height_mm)
    palette = plot_style.get_categorical_palette(options.palette_preset, n_colors=len(groups))
    all_values: list[np.ndarray] = []
    density_max = 0.0

    for group in groups:
        values = group.data.to_numpy(dtype=float)
        values = values[np.isfinite(values)]
        if values.size:
            all_values.append(values)
    if not all_values:
        raise ValueError("No valid groups were found in the replicate table.")

    pooled = np.concatenate(all_values)
    if summary.pooled_unique_count <= max(6, int(round(summary.total_points * 0.35))):
        bin_count = int(max(4, min(18, summary.pooled_unique_count + 1)))
        discrete_binning = True
    else:
        bin_count = int(min(24, max(8, round(np.sqrt(max(pooled.size, 1))))))
        discrete_binning = False

    for color, group, values in zip(palette, groups, all_values, strict=True):
        ax.hist(
            values,
            bins=bin_count,
            density=True,
            alpha=min(plot_style.current_stroke().fill_alpha, 0.28),
            color=color,
            edgecolor=color,
            linewidth=0.8,
            label=group.group,
        )
        x_min = float(values.min())
        x_max = float(values.max())
        if np.isclose(x_min, x_max):
            span = max(abs(x_min), 1.0) * 0.08
            x_grid = np.linspace(x_min - span, x_max + span, 160)
        else:
            x_grid = np.linspace(x_min, x_max, 160)
        density = _gaussian_density(values, x_grid)
        density_max = max(density_max, float(np.max(density)) if density.size else 0.0)
        ax.plot(
            x_grid,
            density,
            color=color,
            linewidth=max(1.0, plot_style.current_stroke().line_width_pt),
            alpha=min(0.96, plot_style.current_stroke().line_alpha + 0.15),
            zorder=3.4,
        )

    first = groups[0]
    ax.set_xlabel(_format_axis_label(first.value_label, first.value_unit))
    ax.set_ylabel("Density")
    if len(groups) > 1:
        ax.legend(loc="best", frameon=False)
    if density_max > 0:
        ax.set_ylim(bottom=0.0, top=density_max * 1.16)
    else:
        ax.set_ylim(bottom=0.0)

    autofixes = ["histogram_density_overlay"]
    if discrete_binning:
        autofixes.append("histogram_discrete_binning")

    return [
        _rendered_plot_with_qa(
            filename=f"{predict_bar_box_slug(groups)}_histogram_density.pdf",
            figure=fig,
            template="histogram_density",
            options=options,
            autofixes_applied=tuple(autofixes),
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


def _bubble_size_profile(values: np.ndarray) -> np.ndarray:
    finite = values[np.isfinite(values)]
    if finite.size == 0:
        return np.full(values.shape, 46.0, dtype=float)
    magnitude = np.abs(finite)
    low = float(np.percentile(magnitude, 10))
    high = float(np.percentile(magnitude, 90))
    if not np.isfinite(low) or not np.isfinite(high):
        return np.full(values.shape, 46.0, dtype=float)
    if np.isclose(high, low):
        midpoint = float(min(140.0, max(42.0, 46.0 + abs(high) * 0.16)))
        result = np.full(values.shape, midpoint, dtype=float)
        result[~np.isfinite(values)] = midpoint
        return result
    clipped = np.clip(np.abs(values), low, high)
    normalized = (clipped - low) / max(high - low, 1e-9)
    sizes = 34.0 + normalized * (160.0 - 34.0)
    sizes[~np.isfinite(values)] = 34.0
    return sizes


def _render_bubble_scatter(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    series_list = load_curve_table_cached(input_path, sheet)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
    axis_mode = "auto_positive" if looks_like_tensile_curve(series_list) else "auto"
    rendered = _render_curve_like_plot(
        filename=f"{input_path.stem}_bubble_scatter.pdf",
        template="bubble_scatter",
        series_list=series_list,
        options=options,
        show_markers=False,
        scatter=True,
        base_kwargs={"axis_mode": axis_mode},
    )
    ax = rendered.figure.axes[0]
    scatter_collections = [collection for collection in ax.collections if np.asarray(collection.get_offsets()).size]
    for series, collection in zip(series_list, scatter_collections, strict=False):
        y_values = series.data["y"].to_numpy(dtype=float)
        bubble_sizes = _bubble_size_profile(y_values)
        collection.set_sizes(bubble_sizes)
        collection.set_alpha(max(float(collection.get_alpha() or 0.0), 0.72))
    rendered = _rendered_plot_with_qa(
        filename=rendered.filename,
        figure=rendered.figure,
        template="bubble_scatter",
        options=options,
        autofixes_applied=(
            tuple(rendered.qa_report.autofixes_applied) if rendered.qa_report is not None else ()
        )
        + ("bubble_size_encoding",),
    )
    return [rendered]


def _fit_line_xy(series_list) -> tuple[np.ndarray, np.ndarray, str]:
    x_blocks: list[np.ndarray] = []
    y_blocks: list[np.ndarray] = []
    for series in series_list:
        frame = series.data.dropna(subset=["x", "y"])
        if frame.empty:
            continue
        x_values = frame["x"].to_numpy(dtype=float)
        y_values = frame["y"].to_numpy(dtype=float)
        valid = np.isfinite(x_values) & np.isfinite(y_values)
        if np.any(valid):
            x_blocks.append(x_values[valid])
            y_blocks.append(y_values[valid])
    if not x_blocks:
        raise ValueError("No valid X/Y series found.")
    x_all = np.concatenate(x_blocks)
    y_all = np.concatenate(y_blocks)
    if x_all.size < 2:
        raise ValueError("At least two points are required to compute a deterministic linear fit.")
    if np.allclose(x_all, x_all[0]):
        raise ValueError("Linear fit cannot be computed when all x values are identical.")
    slope, intercept = np.polyfit(x_all, y_all, 1)
    x_line = np.linspace(float(np.min(x_all)), float(np.max(x_all)), 120, dtype=float)
    y_line = slope * x_line + intercept
    return x_line, y_line, f"fit: y = {slope:.3g}x + {intercept:.3g}"


def _render_scatter_fit_like(
    input_path: Path,
    sheet: str | int,
    options: RenderOptions,
    *,
    template: str,
    filename_suffix: str,
) -> list[RenderedPlot]:
    series_list = load_curve_table_cached(input_path, sheet)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
    axis_mode = "auto_positive" if looks_like_tensile_curve(series_list) else "auto"
    rendered = _render_curve_like_plot(
        filename=f"{input_path.stem}_{filename_suffix}.pdf",
        template=template,
        series_list=series_list,
        options=options,
        show_markers=False,
        scatter=True,
        base_kwargs={"axis_mode": axis_mode},
    )
    ax = rendered.figure.axes[0]
    x_line, y_line, fit_label = _fit_line_xy(series_list)
    stroke = plot_style.current_stroke()
    ax.plot(
        x_line,
        y_line,
        color="black",
        linewidth=max(0.8, stroke.line_width_pt * 0.95),
        alpha=min(0.9, stroke.line_alpha),
        linestyle="--",
        label=fit_label,
        zorder=3.2,
    )
    if ax.get_legend() is None:
        ax.legend(loc="best", frameon=False)
    rendered = _rendered_plot_with_qa(
        filename=rendered.filename,
        figure=rendered.figure,
        template=template,
        options=options,
        autofixes_applied=(
            tuple(rendered.qa_report.autofixes_applied) if rendered.qa_report is not None else ()
        )
        + ("deterministic_linear_fit_overlay",),
    )
    return [rendered]


def _render_scatter_with_fit(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    return _render_scatter_fit_like(
        input_path,
        sheet,
        options,
        template="scatter_with_fit",
        filename_suffix="scatter_with_fit",
    )


def _render_scatter_fit(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    return _render_scatter_fit_like(
        input_path,
        sheet,
        options,
        template="scatter_fit",
        filename_suffix="scatter_fit",
    )


def _render_replicate_band_like(
    input_path: Path,
    sheet: str | int,
    options: RenderOptions,
    *,
    template: str,
    filename_suffix: str,
) -> list[RenderedPlot]:
    normalized_dataset = build_normalized_dataset(input_path, sheet)
    if normalized_dataset.model in {"frequency_sweep", "temperature_sweep", "stress_relaxation"}:
        raise ValueError(f"{template} is not supported for rheology export bundles.")

    series_list = load_curve_table_cached(input_path, sheet)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
    axis_mode = "auto_positive" if looks_like_tensile_curve(series_list) else "auto"
    rendered = _render_curve_like_plot(
        filename=f"{input_path.stem}_{filename_suffix}.pdf",
        template=template,
        series_list=series_list,
        options=options,
        show_markers=False,
        base_kwargs={"axis_mode": axis_mode},
    )
    ax = rendered.figure.axes[0]
    x_band, mean_band, std_band = aligned_replicate_band(series_list)
    color = plot_style.get_categorical_palette(n_colors=1)[0]
    lower = mean_band - std_band
    upper = mean_band + std_band
    ax.fill_between(
        x_band,
        lower,
        upper,
        color=color,
        alpha=min(0.22, plot_style.current_stroke().max_fill_alpha),
        linewidth=0.0,
        zorder=2.0,
        label="mean ±1σ band",
    )
    ax.plot(
        x_band,
        mean_band,
        color=color,
        linewidth=max(1.0, plot_style.current_stroke().line_width_pt),
        linestyle="-",
        zorder=3.6,
        label="mean curve",
    )
    if ax.get_legend() is None:
        ax.legend(loc="best", frameon=False)
    rendered = _rendered_plot_with_qa(
        filename=rendered.filename,
        figure=rendered.figure,
        template=template,
        options=options,
        autofixes_applied=(
            tuple(rendered.qa_report.autofixes_applied) if rendered.qa_report is not None else ()
        )
        + ("replicate_mean_band_overlay",),
    )
    return [rendered]


def _render_replicate_curves_with_band(
    input_path: Path,
    sheet: str | int,
    options: RenderOptions,
) -> list[RenderedPlot]:
    return _render_replicate_band_like(
        input_path,
        sheet,
        options,
        template="replicate_curves_with_band",
        filename_suffix="replicate_curves_with_band",
    )


def _render_mean_band(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    return _render_replicate_band_like(
        input_path,
        sheet,
        options,
        template="mean_band",
        filename_suffix="mean_band",
    )


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


def _render_annotated_heatmap(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    table = load_heatmap_table_cached(input_path, sheet)
    layout = _heatmap_editorial_layout()
    fig, ax = plot_heatmap(
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
    matrix = table.data.pivot(index="y", columns="x", values="z")
    values = matrix.to_numpy(dtype=float)
    if values.size:
        finite = values[np.isfinite(values)]
        mid = float(np.median(finite)) if finite.size else 0.0
    else:
        mid = 0.0
    placements, strategy_id = _choose_annotated_heatmap_label_plan(
        fig=fig,
        ax=ax,
        values=values,
        mid=mid,
    )
    for placement in placements:
        ax.text(
            placement.x,
            placement.y,
            placement.text,
            ha="center",
            va="center",
            fontsize=placement.fontsize,
            color=placement.color,
            zorder=4.2,
            clip_on=True,
        )
    ax.set_xlabel(_format_axis_label(table.x_label, table.x_unit))
    ax.set_ylabel(_format_axis_label(table.y_label, table.y_unit))
    autofixes = ["annotated_heatmap_labels"]
    if strategy_id != "labels_full":
        autofixes.append("annotated_heatmap_label_layout_policy")
        autofixes.append(f"annotated_heatmap_label_strategy_{strategy_id}")
    if options.show_colorbar:
        autofixes.append("heatmap_colorbar_tuned")
    return [
        _rendered_plot_with_qa(
            filename=f"{input_path.stem}_annotated_heatmap.pdf",
            figure=fig,
            template="annotated_heatmap",
            options=options,
            autofixes_applied=tuple(autofixes),
        )
    ]


TEMPLATE_RENDERERS: dict[TemplateName, TemplateRenderer] = {
    "curve": TemplateRenderer(render=_render_curve),
    "point_line": TemplateRenderer(render=_render_point_line),
    "replicate_curves_with_band": TemplateRenderer(render=_render_replicate_curves_with_band),
    "stacked_curve": TemplateRenderer(render=_render_stacked_curve),
    "segmented_stacked_curve": TemplateRenderer(render=_render_segmented_stacked_curve),
    "bar": TemplateRenderer(render=_render_bar),
    "box": TemplateRenderer(render=_render_box),
    "box_strip": TemplateRenderer(render=_render_box_strip),
    "violin": TemplateRenderer(render=_render_violin),
    "violin_box": TemplateRenderer(render=_render_violin_box),
    "grouped_bar_compare": TemplateRenderer(render=_render_grouped_bar_compare),
    "grouped_bar_error": TemplateRenderer(render=_render_grouped_bar_error),
    "point_error": TemplateRenderer(render=_render_point_error),
    "lollipop_error": TemplateRenderer(render=_render_lollipop_error),
    "distribution_compare": TemplateRenderer(render=_render_distribution_compare),
    "histogram_density": TemplateRenderer(render=_render_histogram_density),
    "scatter": TemplateRenderer(render=_render_scatter),
    "bubble_scatter": TemplateRenderer(render=_render_bubble_scatter),
    "scatter_with_fit": TemplateRenderer(render=_render_scatter_with_fit),
    "scatter_fit": TemplateRenderer(render=_render_scatter_fit),
    "mean_band": TemplateRenderer(render=_render_mean_band),
    "heatmap": TemplateRenderer(render=_render_heatmap),
    "annotated_heatmap": TemplateRenderer(render=_render_annotated_heatmap),
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
    visual_theme_id: str | None = None,
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
