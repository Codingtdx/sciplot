from __future__ import annotations

from collections.abc import Sequence

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import to_rgba
from matplotlib.legend import Legend
from matplotlib.ticker import FixedLocator

from src import plot_style
from src.data_loader import CurveSeries
from src.layout_policy import (
    LayoutCandidate,
    LayoutScore,
    choose_layout_candidate,
    flag_margin_fallback,
    record_layout_decision,
)
from src.layout_scoring import score_points_against_bbox
from src.plotting_curve_support import (
    CURVE_TEMPLATES,
    HIDDEN_Y_LABEL_X,
    INSIDE_LEGEND_INSET_FRACTION,
    MARKER_STYLE_CYCLE,
    _baseline_correct_series,
    _compute_stacked_axis_limits,
    _current_legend_inset,
    _infer_markevery,
    _legend_kwargs,
    _place_series_edge_labels,
    _prepare_stacked_layout,
    _stack_retry_scales,
    _validate_curve_series_input,
)
from src.plotting_primitives import (
    MAX_VISIBLE_Y_MAJOR_TICKS,
    AxisLimits,
    AxisMode,
    LegendMode,
    _apply_explicit_major_ticks,
    _format_axis_label,
    _merge_limits,
    _override_complete,
    _resolved_panel_geometry,
    compute_axis_limits,
)


def _legend_candidates(
    inset_fraction: float = INSIDE_LEGEND_INSET_FRACTION,
) -> list[tuple[str, tuple[float, float], str]]:
    inset = inset_fraction
    return [
        ("upper left", (inset, 1 - inset), "left"),
        ("lower left", (inset, inset), "left"),
        ("upper right", (1 - inset, 1 - inset), "right"),
        ("lower right", (1 - inset, inset), "right"),
    ]


def _legend_policy_candidates(
    inset_fraction: float = INSIDE_LEGEND_INSET_FRACTION,
) -> list[LayoutCandidate]:
    policy_candidates: list[LayoutCandidate] = []
    for loc, anchor, align in _legend_candidates(inset_fraction):
        candidate_id = loc.replace(" ", "_")
        policy_candidates.append(
            LayoutCandidate(
                candidate_id=candidate_id,
                anchor=anchor,
                payload={"loc": loc, "alignment": align},
                notes="inside corner candidate",
            )
        )
    return policy_candidates


def _place_legend_candidate(
    ax: plt.Axes,
    candidate: LayoutCandidate | tuple[str, tuple[float, float], str],
) -> Legend:
    if isinstance(candidate, tuple):
        loc, anchor, align = candidate
    else:
        payload = candidate.payload if isinstance(candidate.payload, dict) else {}
        loc = str(payload.get("loc", "upper right"))
        align = str(payload.get("alignment", "right"))
        anchor = candidate.anchor if candidate.anchor is not None else (1.0, 1.0)
    legend = ax.legend(
        loc=loc,
        bbox_to_anchor=anchor,
        bbox_transform=ax.transAxes,
        borderaxespad=0.0,
        alignment=align,
    )
    return legend


def _score_legend_bbox(ax: plt.Axes, legend: Legend, series_list: Sequence[CurveSeries]) -> float:
    fig = ax.figure
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    bbox = legend.get_window_extent(renderer=renderer)
    score = 0.0

    for series in series_list:
        x = series.data["x"].to_numpy(dtype=float)
        y = series.data["y"].to_numpy(dtype=float)
        valid = np.isfinite(x) & np.isfinite(y)
        x = x[valid]
        y = y[valid]
        if len(x) == 0:
            continue

        points = ax.transData.transform(np.column_stack([x, y]))
        metrics = score_points_against_bbox(
            points,
            bbox,
            inside_weight=10.0,
            near_radius=12.0,
            near_weight=1.0,
            normalize_near=True,
        )
        score += metrics.total

    return score


def _legend_kwargs_from_candidate(
    ax: plt.Axes,
    candidate: LayoutCandidate,
) -> dict[str, object]:
    payload = candidate.payload if isinstance(candidate.payload, dict) else {}
    loc = str(payload.get("loc", "upper right"))
    align = str(payload.get("alignment", "right"))
    anchor = candidate.anchor if candidate.anchor is not None else (1.0, 1.0)
    return {
        "loc": loc,
        "bbox_to_anchor": anchor,
        "bbox_transform": ax.transAxes,
        "borderaxespad": 0.0,
        "alignment": align,
    }


def choose_legend_corner_with_policy(
    ax: plt.Axes,
    series_list: Sequence[CurveSeries],
    inset_fraction: float = INSIDE_LEGEND_INSET_FRACTION,
) -> tuple[dict[str, object], float, object]:
    candidates = _legend_policy_candidates(inset_fraction)

    def _score(candidate: LayoutCandidate) -> LayoutScore:
        legend = _place_legend_candidate(ax, candidate)
        try:
            score = _score_legend_bbox(ax, legend, series_list)
            return LayoutScore(score=score, blocked=False, reason=f"curve_overlap={score:.4f}")
        finally:
            legend.remove()

    decision = choose_layout_candidate(
        object_kind="legend",
        candidates=candidates,
        score_hook=_score,
    )
    chosen = decision.chosen_candidate or candidates[0]
    score = float(decision.chosen_score) if decision.chosen_score is not None else float("inf")
    return _legend_kwargs_from_candidate(ax, chosen), score, decision


def choose_legend_corner(
    ax: plt.Axes,
    series_list: Sequence[CurveSeries],
    inset_fraction: float = INSIDE_LEGEND_INSET_FRACTION,
) -> tuple[dict[str, object], float]:
    kwargs, score, _decision = choose_legend_corner_with_policy(
        ax,
        series_list,
        inset_fraction=inset_fraction,
    )
    return kwargs, score


def _expand_linear_limit(low: float, high: float, *, expand_low: bool, fraction: float) -> tuple[float, float]:
    span = high - low
    if span <= 0:
        span = max(abs(high), 1.0)
    delta = span * fraction
    return (low - delta, high) if expand_low else (low, high + delta)


def _expand_log_limit(low: float, high: float, *, expand_low: bool, fraction: float) -> tuple[float, float]:
    log_low = np.log10(low)
    log_high = np.log10(high)
    span = log_high - log_low
    if span <= 0:
        span = 0.5
    delta = span * fraction
    return (10 ** (log_low - delta), high) if expand_low else (low, 10 ** (log_high + delta))


def _nudge_limits_for_legend(
    ax: plt.Axes,
    legend_kwargs: dict[str, object],
    overlap_score: float,
    *,
    xscale: str,
    yscale: str,
    expand_axes: str = "xy",
) -> None:
    if overlap_score <= 0:
        return

    loc = str(legend_kwargs["loc"])
    x_low, x_high = ax.get_xlim()
    y_low, y_high = ax.get_ylim()
    allow_expand_x = "x" in expand_axes
    allow_expand_y = "y" in expand_axes

    if allow_expand_y:
        if loc.startswith("upper"):
            if yscale == "log":
                y_low, y_high = _expand_log_limit(y_low, y_high, expand_low=False, fraction=0.14)
            else:
                y_low, y_high = _expand_linear_limit(y_low, y_high, expand_low=False, fraction=0.12)
        else:
            if yscale == "log":
                y_low, y_high = _expand_log_limit(y_low, y_high, expand_low=True, fraction=0.12)
            else:
                y_low, y_high = _expand_linear_limit(y_low, y_high, expand_low=True, fraction=0.10)

    if allow_expand_x:
        if loc.endswith("left"):
            if xscale == "log":
                x_low, x_high = _expand_log_limit(x_low, x_high, expand_low=True, fraction=0.08)
            else:
                x_low, x_high = _expand_linear_limit(x_low, x_high, expand_low=True, fraction=0.06)
        else:
            if xscale == "log":
                x_low, x_high = _expand_log_limit(x_low, x_high, expand_low=False, fraction=0.08)
            else:
                x_low, x_high = _expand_linear_limit(x_low, x_high, expand_low=False, fraction=0.06)

    ax.set_xlim(x_low, x_high)
    ax.set_ylim(y_low, y_high)


def _legend_margin_modes(expand_axes: str) -> list[str]:
    requested = expand_axes if expand_axes in {"x", "y", "xy"} else "xy"
    if requested == "x":
        return ["none", "x"]
    if requested == "y":
        return ["none", "y"]
    return ["none", "y", "x", "xy"]


def _legend_expand_cost(
    original_xlim: tuple[float, float],
    original_ylim: tuple[float, float],
    updated_xlim: tuple[float, float],
    updated_ylim: tuple[float, float],
) -> float:
    original_x_span = max(abs(float(original_xlim[1] - original_xlim[0])), 1e-9)
    original_y_span = max(abs(float(original_ylim[1] - original_ylim[0])), 1e-9)
    updated_x_span = abs(float(updated_xlim[1] - updated_xlim[0]))
    updated_y_span = abs(float(updated_ylim[1] - updated_ylim[0]))
    x_growth = max((updated_x_span - original_x_span) / original_x_span, 0.0)
    y_growth = max((updated_y_span - original_y_span) / original_y_span, 0.0)
    return x_growth * 22.0 + y_growth * 28.0


def _apply_legend_margin_fallback_policy(
    ax: plt.Axes,
    *,
    series_list: Sequence[CurveSeries],
    legend_loc: str,
    overlap_score: float,
    xscale: str,
    yscale: str,
    expand_axes: str,
    inset_fraction: float,
) -> tuple[dict[str, object], object]:
    if overlap_score <= 0:
        legend_kwargs, _, _legend_decision = choose_legend_corner_with_policy(
            ax,
            series_list,
            inset_fraction=inset_fraction,
        )
        margin_decision = choose_layout_candidate(
            object_kind="legend_margin_fallback",
            candidates=[LayoutCandidate(candidate_id="none", payload={"mode": "none"}, notes="no overlap; no expand")],
            score_hook=lambda _candidate: LayoutScore(score=0.0, blocked=False, reason="overlap<=0"),
        )
        return legend_kwargs, flag_margin_fallback(
            margin_decision,
            action="none",
            reason=f"legend overlap score {overlap_score:.4f}",
        )

    mode_candidates = [
        LayoutCandidate(
            candidate_id=f"expand_{mode}",
            payload={"mode": mode, "bias": 0.0 if mode == "none" else 0.25},
            notes="legend axis expansion mode candidate",
        )
        for mode in _legend_margin_modes(expand_axes)
    ]
    original_xlim = tuple(float(value) for value in ax.get_xlim())
    original_ylim = tuple(float(value) for value in ax.get_ylim())

    def _score_mode(candidate: LayoutCandidate) -> LayoutScore:
        payload = candidate.payload if isinstance(candidate.payload, dict) else {}
        mode = str(payload.get("mode", "none"))
        bias = float(payload.get("bias", 0.0))
        ax.set_xlim(*original_xlim)
        ax.set_ylim(*original_ylim)
        if mode != "none":
            _nudge_limits_for_legend(
                ax,
                {"loc": legend_loc},
                overlap_score,
                xscale=xscale,
                yscale=yscale,
                expand_axes=mode,
            )
        _legend_kwargs, candidate_overlap, _legend_decision = choose_legend_corner_with_policy(
            ax,
            series_list,
            inset_fraction=inset_fraction,
        )
        expand_cost = _legend_expand_cost(
            original_xlim,
            original_ylim,
            tuple(float(value) for value in ax.get_xlim()),
            tuple(float(value) for value in ax.get_ylim()),
        )
        score = candidate_overlap + expand_cost + bias
        return LayoutScore(
            score=score,
            blocked=False,
            reason=(
                f"mode={mode}; overlap={candidate_overlap:.4f}; "
                f"expand_cost={expand_cost:.4f}; bias={bias:.3f}"
            ),
        )

    decision = choose_layout_candidate(
        object_kind="legend_margin_fallback",
        candidates=mode_candidates,
        score_hook=_score_mode,
    )

    ax.set_xlim(*original_xlim)
    ax.set_ylim(*original_ylim)
    chosen_mode = "none"
    if decision.chosen_candidate and isinstance(decision.chosen_candidate.payload, dict):
        chosen_mode = str(decision.chosen_candidate.payload.get("mode", "none"))
    if chosen_mode != "none":
        _nudge_limits_for_legend(
            ax,
            {"loc": legend_loc},
            overlap_score,
            xscale=xscale,
            yscale=yscale,
            expand_axes=chosen_mode,
        )
        decision = flag_margin_fallback(
            decision,
            action=f"expand_axes:{chosen_mode}",
            reason=f"legend overlap score {overlap_score:.4f}",
        )
    else:
        decision = flag_margin_fallback(
            decision,
            action="none",
            reason=f"legend overlap score {overlap_score:.4f}",
        )
    legend_kwargs, _, _legend_decision = choose_legend_corner_with_policy(
        ax,
        series_list,
        inset_fraction=inset_fraction,
    )
    return legend_kwargs, decision


def plot_curves(
    series_list: Sequence[CurveSeries],
    *,
    legend_mode: LegendMode = "inside_best",
    axis_mode: AxisMode = "auto",
    xscale: str = "linear",
    yscale: str = "linear",
    width_mm: float | None = None,
    height_mm: float | None = None,
    left_margin_mm: float | None = None,
    right_margin_mm: float | None = None,
    bottom_margin_mm: float | None = None,
    top_margin_mm: float | None = None,
    xlim: tuple[float | None, float | None] | None = None,
    ylim: tuple[float | None, float | None] | None = None,
    headroom_factor: float | None = None,
    y_padding_top: float = 0.18,
    y_padding_bottom: float = 0.06,
    show_markers: bool = True,
    marker_style_cycle: Sequence[str] | None = None,
    marker_size: float | None = None,
    marker_every: int | None = None,
    visible_xticks: Sequence[float] | None = None,
    reverse_x: bool = False,
    stack_mode: str = "none",
    stack_floor_fraction: float = 0.22,
    stack_gap_fraction: float = 0.22,
    series_label_mode: str = "legend",
    series_label_side: str = "auto",
    label_track_inset_fraction: float = 0.06,
    label_offset_pt: float = 5.0,
    baseline_mode: str = "none",
    show_y_ticks: bool = True,
    legend_expand_axes: str = "xy",
    legend_inset_fraction: float | None = None,
) -> tuple[plt.Figure, plt.Axes]:
    _validate_curve_series_input(series_list)
    stroke = plot_style.current_stroke()
    (
        resolved_width_mm,
        resolved_height_mm,
        resolved_left_margin_mm,
        resolved_right_margin_mm,
        resolved_bottom_margin_mm,
        resolved_top_margin_mm,
    ) = _resolved_panel_geometry(
        width_mm=width_mm,
        height_mm=height_mm,
        left_margin_mm=left_margin_mm,
        right_margin_mm=right_margin_mm,
        bottom_margin_mm=bottom_margin_mm,
        top_margin_mm=top_margin_mm,
    )
    fig, ax = plot_style.create_panel_figure(
        width_mm=resolved_width_mm,
        height_mm=resolved_height_mm,
        left_margin_mm=resolved_left_margin_mm,
        right_margin_mm=resolved_right_margin_mm,
        bottom_margin_mm=resolved_bottom_margin_mm,
        top_margin_mm=resolved_top_margin_mm,
    )
    palette = plot_style.get_categorical_palette(n_colors=len(series_list))
    markers = marker_style_cycle or MARKER_STYLE_CYCLE
    resolved_marker_size = stroke.marker_size_pt if marker_size is None else marker_size
    normalized_series = _baseline_correct_series(series_list, baseline_mode=baseline_mode)
    stacked_mode_enabled = stack_mode != "none" and len(series_list) > 1
    plotted_series = list(normalized_series)
    limits: AxisLimits
    label_success = True
    retry_scales = _stack_retry_scales() if stacked_mode_enabled and series_label_mode == "edge" else (1.0,)

    for step_scale in retry_scales:
        ax.cla()
        stacked_layout = (
            _prepare_stacked_layout(
                normalized_series,
                stack_floor_fraction=stack_floor_fraction,
                stack_gap_fraction=stack_gap_fraction,
                step_scale=step_scale,
            )
            if stacked_mode_enabled
            else None
        )
        plotted_series = stacked_layout.series_list if stacked_layout is not None else list(normalized_series)

        for idx, (color, series) in enumerate(zip(palette, plotted_series, strict=True)):
            markevery = marker_every if marker_every is not None else _infer_markevery(len(series.data))
            line_color = to_rgba(color, stroke.line_alpha)
            ax.plot(
                series.data["x"],
                series.data["y"],
                label=series.sample,
                color=line_color,
                linewidth=stroke.line_width_pt,
                marker=markers[idx % len(markers)] if show_markers else None,
                markersize=resolved_marker_size,
                markerfacecolor=color,
                markeredgecolor=color,
                markeredgewidth=0.5,
                markevery=markevery,
            )

        if stacked_layout is not None:
            limits = _compute_stacked_axis_limits(
                stacked_layout,
                xscale=xscale,
                y_padding_top=y_padding_top,
            )
        else:
            limits = compute_axis_limits(
                [series.data["y"].to_numpy() for series in plotted_series],
                kind="line",
                axis_mode=axis_mode,
                legend_mode=legend_mode,
                x_values=[series.data["x"].to_numpy() for series in plotted_series],
                xscale=xscale,
                yscale=yscale,
                headroom_factor=headroom_factor,
                y_padding_top=y_padding_top,
                y_padding_bottom=y_padding_bottom,
            )
        ax.set_xlim(*_merge_limits(limits.xlim, xlim))
        ax.set_ylim(*_merge_limits(limits.ylim, ylim))
        ax.set_xscale(xscale)
        ax.set_yscale(yscale)
        if reverse_x:
            ax.invert_xaxis()

        first = series_list[0]
        ax.set_xlabel(_format_axis_label(first.x_label, first.x_unit))
        ax.set_ylabel(_format_axis_label(first.y_label, first.y_unit))
        if not show_y_ticks:
            ax.tick_params(axis="y", left=False, labelleft=False, which="both")
            ax.spines["left"].set_visible(True)
            ax.yaxis.set_label_coords(HIDDEN_Y_LABEL_X, 0.5)
        if series_label_mode == "edge" and len(plotted_series) > 1:
            label_success = _place_series_edge_labels(
                ax,
                plotted_series,
                palette,
                reverse_x=reverse_x,
                side=series_label_side,
                inset_fraction=label_track_inset_fraction,
                label_offset_pt=label_offset_pt,
                search_band_fraction=0.24 if stacked_mode_enabled else 0.08,
                fontsize=6.2 if stacked_mode_enabled else 6.0,
            )
        else:
            label_success = True
        if label_success:
            break

    if series_label_mode != "edge" and legend_mode == "inside_best":
        legend_kwargs, overlap_score, legend_corner_decision = choose_legend_corner_with_policy(
            ax,
            plotted_series,
            inset_fraction=_current_legend_inset(legend_inset_fraction),
        )
        record_layout_decision(
            fig,
            legend_corner_decision,
            context={"path": "plot_curves", "phase": "legend_corner_initial"},
        )
        legend_kwargs, margin_decision = _apply_legend_margin_fallback_policy(
            ax,
            series_list=plotted_series,
            legend_loc=str(legend_kwargs.get("loc", "upper right")),
            overlap_score=overlap_score,
            xscale=xscale,
            yscale=yscale,
            expand_axes=legend_expand_axes,
            inset_fraction=_current_legend_inset(legend_inset_fraction),
        )
        record_layout_decision(
            fig,
            margin_decision,
            context={"path": "plot_curves", "phase": "legend_margin_fallback"},
        )
        ax.legend(**legend_kwargs)
    elif series_label_mode != "edge" and legend_mode != "none":
        ax.legend(**_legend_kwargs(legend_mode))

    if visible_xticks is not None:
        ax.xaxis.set_major_locator(FixedLocator(np.asarray(visible_xticks, dtype=float)))
    elif not _override_complete(xlim) and limits.x_tick_policy is not None:
        _apply_explicit_major_ticks(ax.xaxis, limits.x_tick_policy.major_ticks)
    if show_y_ticks and not _override_complete(ylim) and limits.y_tick_policy is not None:
        _apply_explicit_major_ticks(
            ax.yaxis,
            limits.y_tick_policy.major_ticks,
            max_major_ticks=MAX_VISIBLE_Y_MAJOR_TICKS,
        )
    return fig, ax


def plot_scatter(
    series_list: Sequence[CurveSeries],
    *,
    legend_mode: LegendMode = "inside_best",
    axis_mode: AxisMode = "auto",
    xscale: str = "linear",
    yscale: str = "linear",
    width_mm: float | None = None,
    height_mm: float | None = None,
    left_margin_mm: float | None = None,
    right_margin_mm: float | None = None,
    bottom_margin_mm: float | None = None,
    top_margin_mm: float | None = None,
    xlim: tuple[float | None, float | None] | None = None,
    ylim: tuple[float | None, float | None] | None = None,
    headroom_factor: float | None = None,
    y_padding_top: float = 0.12,
    y_padding_bottom: float = 0.06,
    marker_size: float = 14.0,
    visible_xticks: Sequence[float] | None = None,
    reverse_x: bool = False,
    legend_expand_axes: str = "xy",
    legend_inset_fraction: float | None = None,
) -> tuple[plt.Figure, plt.Axes]:
    _validate_curve_series_input(series_list)
    stroke = plot_style.current_stroke()
    (
        resolved_width_mm,
        resolved_height_mm,
        resolved_left_margin_mm,
        resolved_right_margin_mm,
        resolved_bottom_margin_mm,
        resolved_top_margin_mm,
    ) = _resolved_panel_geometry(
        width_mm=width_mm,
        height_mm=height_mm,
        left_margin_mm=left_margin_mm,
        right_margin_mm=right_margin_mm,
        bottom_margin_mm=bottom_margin_mm,
        top_margin_mm=top_margin_mm,
    )
    fig, ax = plot_style.create_panel_figure(
        width_mm=resolved_width_mm,
        height_mm=resolved_height_mm,
        left_margin_mm=resolved_left_margin_mm,
        right_margin_mm=resolved_right_margin_mm,
        bottom_margin_mm=resolved_bottom_margin_mm,
        top_margin_mm=resolved_top_margin_mm,
    )
    palette = plot_style.get_categorical_palette(n_colors=len(series_list))

    for color, series in zip(palette, series_list, strict=True):
        ax.scatter(
            series.data["x"],
            series.data["y"],
            label=series.sample,
            color=color,
            s=marker_size,
            alpha=stroke.marker_alpha,
            linewidths=0.0,
            zorder=2.5,
        )

    limits = compute_axis_limits(
        [series.data["y"].to_numpy() for series in series_list],
        kind="line",
        axis_mode=axis_mode,
        legend_mode=legend_mode,
        x_values=[series.data["x"].to_numpy() for series in series_list],
        xscale=xscale,
        yscale=yscale,
        headroom_factor=headroom_factor,
        y_padding_top=y_padding_top,
        y_padding_bottom=y_padding_bottom,
    )
    ax.set_xlim(*_merge_limits(limits.xlim, xlim))
    ax.set_ylim(*_merge_limits(limits.ylim, ylim))
    ax.set_xscale(xscale)
    ax.set_yscale(yscale)
    if reverse_x:
        ax.invert_xaxis()

    first = series_list[0]
    ax.set_xlabel(_format_axis_label(first.x_label, first.x_unit))
    ax.set_ylabel(_format_axis_label(first.y_label, first.y_unit))

    if legend_mode == "inside_best":
        legend_kwargs, overlap_score, legend_corner_decision = choose_legend_corner_with_policy(
            ax,
            series_list,
            inset_fraction=_current_legend_inset(legend_inset_fraction),
        )
        record_layout_decision(
            fig,
            legend_corner_decision,
            context={"path": "plot_scatter", "phase": "legend_corner_initial"},
        )
        legend_kwargs, margin_decision = _apply_legend_margin_fallback_policy(
            ax,
            series_list=series_list,
            legend_loc=str(legend_kwargs.get("loc", "upper right")),
            overlap_score=overlap_score,
            xscale=xscale,
            yscale=yscale,
            expand_axes=legend_expand_axes,
            inset_fraction=_current_legend_inset(legend_inset_fraction),
        )
        record_layout_decision(
            fig,
            margin_decision,
            context={"path": "plot_scatter", "phase": "legend_margin_fallback"},
        )
        ax.legend(**legend_kwargs)
    elif legend_mode != "none":
        ax.legend(**_legend_kwargs(legend_mode))

    if visible_xticks is not None:
        ax.xaxis.set_major_locator(FixedLocator(np.asarray(visible_xticks, dtype=float)))
    elif not _override_complete(xlim) and limits.x_tick_policy is not None:
        _apply_explicit_major_ticks(ax.xaxis, limits.x_tick_policy.major_ticks)
    if not _override_complete(ylim) and limits.y_tick_policy is not None:
        _apply_explicit_major_ticks(
            ax.yaxis,
            limits.y_tick_policy.major_ticks,
            max_major_ticks=MAX_VISIBLE_Y_MAJOR_TICKS,
        )
    return fig, ax


def plot_curve_template(
    template_name: str,
    series_list: Sequence[CurveSeries],
    **overrides: object,
) -> tuple[plt.Figure, plt.Axes]:
    try:
        template = CURVE_TEMPLATES[template_name]
    except KeyError as exc:
        raise ValueError(f"Unknown curve template: {template_name}") from exc

    params: dict[str, object] = {
        "xscale": template.xscale,
        "yscale": template.yscale,
        "width_mm": template.width_mm,
        "height_mm": template.height_mm,
        "left_margin_mm": template.left_margin_mm,
        "right_margin_mm": template.right_margin_mm,
        "bottom_margin_mm": template.bottom_margin_mm,
        "top_margin_mm": template.top_margin_mm,
        "legend_mode": template.legend_mode,
        "axis_mode": template.axis_mode,
        "y_padding_top": template.y_padding_top,
        "y_padding_bottom": template.y_padding_bottom,
        "reverse_x": template.reverse_x,
        "show_markers": template.show_markers,
        "stack_mode": template.stack_mode,
        "stack_floor_fraction": template.stack_floor_fraction,
        "stack_gap_fraction": template.stack_gap_fraction,
        "series_label_mode": template.series_label_mode,
        "series_label_side": template.series_label_side,
        "label_track_inset_fraction": template.label_track_inset_fraction,
        "label_offset_pt": template.label_offset_pt,
        "baseline_mode": template.baseline_mode,
        "show_y_ticks": template.show_y_ticks,
    }
    params.update(overrides)
    return plot_curves(series_list, **params)  # type: ignore[arg-type]


def plot_frequency_sweep(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("frequency_sweep", series_list, **overrides)


def plot_temperature_sweep(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("temperature_sweep", series_list, **overrides)


def plot_stress_relaxation(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("stress_relaxation", series_list, **overrides)


def plot_tensile_curve(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("tensile_curve", series_list, **overrides)


def plot_ftir(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("ftir", series_list, **overrides)


def plot_nmr(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("nmr", series_list, **overrides)


def plot_xrd(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("xrd", series_list, **overrides)


def plot_dsc(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("dsc", series_list, **overrides)


def plot_tga(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("tga", series_list, **overrides)


def plot_dma(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("dma", series_list, **overrides)
