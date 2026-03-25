from __future__ import annotations

from collections.abc import Sequence

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import to_rgba
from matplotlib.legend import Legend
from matplotlib.ticker import FixedLocator

from src import plot_style
from src.data_loader import CurveSeries
from src.layout_scoring import score_points_against_bbox
from src.plotting import (
    CURVE_TEMPLATES,
    HIDDEN_Y_LABEL_X,
    INSIDE_LEGEND_INSET_FRACTION,
    MARKER_STYLE_CYCLE,
    MAX_VISIBLE_Y_MAJOR_TICKS,
    AxisLimits,
    AxisMode,
    LegendMode,
    _apply_explicit_major_ticks,
    _baseline_correct_series,
    _compute_stacked_axis_limits,
    _current_legend_inset,
    _format_axis_label,
    _infer_markevery,
    _legend_kwargs,
    _merge_limits,
    _override_complete,
    _place_series_edge_labels,
    _prepare_stacked_layout,
    _resolved_panel_geometry,
    _stack_retry_scales,
    _validate_curve_series_input,
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


def _place_legend_candidate(
    ax: plt.Axes,
    candidate: tuple[str, tuple[float, float], str],
) -> Legend:
    loc, anchor, align = candidate
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


def choose_legend_corner(
    ax: plt.Axes,
    series_list: Sequence[CurveSeries],
    inset_fraction: float = INSIDE_LEGEND_INSET_FRACTION,
) -> tuple[dict[str, object], float]:
    candidates = _legend_candidates(inset_fraction)
    best_score = float("inf")
    best_candidate = candidates[0]

    for candidate in candidates:
        legend = _place_legend_candidate(ax, candidate)
        score = _score_legend_bbox(ax, legend, series_list)
        legend.remove()
        if score < best_score:
            best_score = score
            best_candidate = candidate

    loc, anchor, align = best_candidate
    return (
        {
            "loc": loc,
            "bbox_to_anchor": anchor,
            "bbox_transform": ax.transAxes,
            "borderaxespad": 0.0,
            "alignment": align,
        },
        best_score,
    )


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
        legend_kwargs, overlap_score = choose_legend_corner(
            ax,
            plotted_series,
            inset_fraction=_current_legend_inset(legend_inset_fraction),
        )
        _nudge_limits_for_legend(
            ax,
            legend_kwargs,
            overlap_score,
            xscale=xscale,
            yscale=yscale,
            expand_axes=legend_expand_axes,
        )
        legend_kwargs, _ = choose_legend_corner(
            ax,
            plotted_series,
            inset_fraction=_current_legend_inset(legend_inset_fraction),
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
        legend_kwargs, overlap_score = choose_legend_corner(
            ax,
            series_list,
            inset_fraction=_current_legend_inset(legend_inset_fraction),
        )
        _nudge_limits_for_legend(
            ax,
            legend_kwargs,
            overlap_score,
            xscale=xscale,
            yscale=yscale,
            expand_axes=legend_expand_axes,
        )
        legend_kwargs, _ = choose_legend_corner(
            ax,
            series_list,
            inset_fraction=_current_legend_inset(legend_inset_fraction),
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
