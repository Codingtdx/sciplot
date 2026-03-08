from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
from matplotlib.legend import Legend

from src.data_loader import CurveSeries, ReplicateGroup
from src.plot_style import (
    BOTTOM_MARGIN_MM,
    FILL_ALPHA,
    LEFT_MARGIN_MM,
    LINE_ALPHA,
    LINE_WIDTH_PT,
    MARKER_ALPHA,
    MAX_FILL_ALPHA,
    PANEL_HEIGHT_MM,
    PANEL_WIDTH_MM,
    RIGHT_MARGIN_MM,
    TOP_MARGIN_MM,
    create_panel_figure,
)


LegendMode = str
AxisMode = str
MARKER_STYLE_CYCLE = ("o", "s", "^", "D", "v", "P", "X")


@dataclass
class AxisLimits:
    xlim: tuple[float, float]
    ylim: tuple[float, float]


@dataclass(frozen=True)
class CurveTemplate:
    xscale: str
    yscale: str
    width_mm: float
    height_mm: float
    left_margin_mm: float
    right_margin_mm: float
    bottom_margin_mm: float
    top_margin_mm: float
    legend_mode: LegendMode = "inside_best"
    axis_mode: AxisMode = "auto"
    y_padding_top: float = 0.18
    y_padding_bottom: float = 0.06


CURVE_TEMPLATES: dict[str, CurveTemplate] = {
    "frequency_sweep": CurveTemplate(
        xscale="log",
        yscale="log",
        width_mm=PANEL_WIDTH_MM,
        height_mm=PANEL_HEIGHT_MM,
        left_margin_mm=LEFT_MARGIN_MM,
        right_margin_mm=RIGHT_MARGIN_MM,
        bottom_margin_mm=BOTTOM_MARGIN_MM,
        top_margin_mm=TOP_MARGIN_MM,
    ),
    "temperature_sweep": CurveTemplate(
        xscale="linear",
        yscale="log",
        width_mm=120,
        height_mm=PANEL_HEIGHT_MM,
        left_margin_mm=LEFT_MARGIN_MM,
        right_margin_mm=RIGHT_MARGIN_MM,
        bottom_margin_mm=BOTTOM_MARGIN_MM,
        top_margin_mm=TOP_MARGIN_MM,
    ),
    "stress_relaxation": CurveTemplate(
        xscale="log",
        yscale="linear",
        width_mm=PANEL_WIDTH_MM,
        height_mm=PANEL_HEIGHT_MM,
        left_margin_mm=LEFT_MARGIN_MM,
        right_margin_mm=RIGHT_MARGIN_MM,
        bottom_margin_mm=BOTTOM_MARGIN_MM,
        top_margin_mm=TOP_MARGIN_MM,
    ),
    "tensile_curve": CurveTemplate(
        xscale="linear",
        yscale="linear",
        width_mm=PANEL_WIDTH_MM,
        height_mm=PANEL_HEIGHT_MM,
        left_margin_mm=LEFT_MARGIN_MM,
        right_margin_mm=RIGHT_MARGIN_MM,
        bottom_margin_mm=BOTTOM_MARGIN_MM,
        top_margin_mm=TOP_MARGIN_MM,
    ),
}


def compute_group_positions(
    num_groups: int,
    item_width: float,
    spacing_scale: float = 1.0,
) -> np.ndarray:
    """Compute symmetric group centers with density-aware spacing."""
    if num_groups <= 0:
        raise ValueError("num_groups must be positive.")
    if item_width <= 0:
        raise ValueError("item_width must be positive.")
    if spacing_scale <= 0:
        raise ValueError("spacing_scale must be positive.")

    extra_gap = 0.72 - min(num_groups, 8) * 0.055
    if num_groups <= 4:
        extra_gap += 0.08
    extra_gap = max(0.18, extra_gap)

    center_step = item_width + extra_gap * spacing_scale
    offsets = np.arange(num_groups, dtype=float) - (num_groups - 1) / 2
    return offsets * center_step


def _format_axis_label(label: str, unit: str) -> str:
    return f"{label} ({unit})" if unit else label


def _merge_limits(
    computed: tuple[float, float],
    override: tuple[float | None, float | None] | None,
) -> tuple[float, float]:
    if override is None:
        return computed
    low = computed[0] if override[0] is None else override[0]
    high = computed[1] if override[1] is None else override[1]
    return float(low), float(high)


def _pad_limits_linear(
    data_min: float,
    data_max: float,
    *,
    lower_padding: float,
    upper_padding: float,
    axis_mode: AxisMode,
    allow_below_zero: bool,
) -> tuple[float, float]:
    if np.isclose(data_min, data_max):
        baseline = abs(data_max) if data_max != 0 else 1.0
        pad = baseline * 0.08
        low, high = data_min - pad, data_max + pad
    else:
        span = data_max - data_min
        low = data_min - span * lower_padding
        high = data_max + span * upper_padding

    if axis_mode == "auto_positive" and data_min >= 0:
        low = 0.0
    elif not allow_below_zero and data_min >= 0:
        low = max(0.0, low)

    if np.isclose(low, high):
        high = low + 1.0
    return low, high


def _pad_limits_log(
    data_min: float,
    data_max: float,
    *,
    lower_padding: float,
    upper_padding: float,
) -> tuple[float, float]:
    if data_min <= 0 or data_max <= 0:
        raise ValueError("Log-scale limits require strictly positive values.")

    if np.isclose(data_min, data_max):
        low = data_min / 10**0.08
        high = data_max * 10**0.08
        return low, high

    log_min = np.log10(data_min)
    log_max = np.log10(data_max)
    span = log_max - log_min
    low = 10 ** (log_min - span * lower_padding)
    high = 10 ** (log_max + span * upper_padding)
    return low, high


def _validate_scale_values(
    values: Sequence[np.ndarray] | Sequence[Sequence[float]],
    *,
    scale: str,
    axis_name: str,
) -> list[np.ndarray]:
    arrays = [np.asarray(series, dtype=float) for series in values]
    arrays = [arr[np.isfinite(arr)] for arr in arrays if np.asarray(arr).size]
    if not arrays:
        raise ValueError(f"Cannot compute {axis_name}-axis values for empty data.")

    if scale == "log":
        bad = [arr for arr in arrays if np.any(arr <= 0)]
        if bad:
            raise ValueError(f"{axis_name}-axis uses log scale but contains non-positive values.")
    return arrays


def compute_axis_limits(
    values: Sequence[np.ndarray] | Sequence[Sequence[float]],
    *,
    kind: str,
    axis_mode: AxisMode = "auto",
    legend_mode: LegendMode = "outside",
    x_values: Sequence[np.ndarray] | Sequence[Sequence[float]] | None = None,
    xscale: str = "linear",
    yscale: str = "linear",
    x_padding: float = 0.02,
    y_padding_top: float = 0.12,
    y_padding_bottom: float = 0.06,
    headroom_factor: float | None = None,
) -> AxisLimits:
    """Compute axis limits with small default padding and optional legend headroom."""
    y_arrays = _validate_scale_values(values, scale=yscale, axis_name="Y")

    y_min = min(float(arr.min()) for arr in y_arrays)
    y_max = max(float(arr.max()) for arr in y_arrays)

    allow_below_zero = legend_mode == "inside_forced" and y_min >= 0
    if yscale == "log":
        y_low, y_high = _pad_limits_log(
            y_min,
            y_max,
            lower_padding=y_padding_bottom,
            upper_padding=y_padding_top,
        )
    else:
        y_low, y_high = _pad_limits_linear(
            y_min,
            y_max,
            lower_padding=y_padding_bottom,
            upper_padding=y_padding_top,
            axis_mode=axis_mode,
            allow_below_zero=allow_below_zero,
        )

    if headroom_factor is not None and y_max > 0 and yscale == "linear":
        y_high = max(y_high, y_max * headroom_factor)

    if kind in {"bar", "box"} and axis_mode != "manual" and y_min >= 0:
        y_low = 0.0

    if x_values is None:
        return AxisLimits(xlim=(0.0, 1.0), ylim=(y_low, y_high))

    x_arrays = _validate_scale_values(x_values, scale=xscale, axis_name="X")

    x_min = min(float(arr.min()) for arr in x_arrays)
    x_max = max(float(arr.max()) for arr in x_arrays)
    if xscale == "log":
        x_low, x_high = _pad_limits_log(
            x_min,
            x_max,
            lower_padding=x_padding,
            upper_padding=x_padding,
        )
    else:
        x_low, x_high = _pad_limits_linear(
            x_min,
            x_max,
            lower_padding=x_padding,
            upper_padding=x_padding,
            axis_mode="manual",
            allow_below_zero=True,
        )
    return AxisLimits(xlim=(x_low, x_high), ylim=(y_low, y_high))


def _legend_kwargs(legend_mode: LegendMode) -> dict[str, object]:
    if legend_mode == "outside":
        return {"loc": "upper left", "bbox_to_anchor": (1.02, 1.0), "borderaxespad": 0.0}
    if legend_mode == "inside_forced":
        return {"loc": "upper right"}
    return {"loc": "upper right"}


def _infer_markevery(length: int) -> int | None:
    if length <= 20:
        return None
    return max(2, int(np.ceil(length / 12)))


def _legend_candidates(inset_fraction: float = 0.025) -> list[tuple[str, tuple[float, float], str]]:
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
        inside = (
            (points[:, 0] >= bbox.x0)
            & (points[:, 0] <= bbox.x1)
            & (points[:, 1] >= bbox.y0)
            & (points[:, 1] <= bbox.y1)
        )
        score += float(inside.sum()) * 10.0

        dx = np.where(points[:, 0] < bbox.x0, bbox.x0 - points[:, 0], np.where(points[:, 0] > bbox.x1, points[:, 0] - bbox.x1, 0.0))
        dy = np.where(points[:, 1] < bbox.y0, bbox.y0 - points[:, 1], np.where(points[:, 1] > bbox.y1, points[:, 1] - bbox.y1, 0.0))
        distance = np.hypot(dx, dy)
        near = distance < 12.0
        if np.any(near):
            score += float((12.0 - distance[near]).sum()) / 12.0

    return score


def choose_legend_corner(
    ax: plt.Axes,
    series_list: Sequence[CurveSeries],
    inset_fraction: float = 0.025,
) -> tuple[dict[str, object], float]:
    """Choose the least-overlapping legend corner from four fixed inset positions."""
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
) -> None:
    if overlap_score <= 0:
        return

    loc = str(legend_kwargs["loc"])
    x_low, x_high = ax.get_xlim()
    y_low, y_high = ax.get_ylim()

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
    left_margin_mm: float = LEFT_MARGIN_MM,
    right_margin_mm: float = RIGHT_MARGIN_MM,
    bottom_margin_mm: float = BOTTOM_MARGIN_MM,
    top_margin_mm: float = TOP_MARGIN_MM,
    xlim: tuple[float, float] | None = None,
    ylim: tuple[float, float] | None = None,
    headroom_factor: float | None = None,
    y_padding_top: float = 0.18,
    y_padding_bottom: float = 0.06,
    show_markers: bool = True,
    marker_style_cycle: Sequence[str] | None = None,
    marker_size: float = 3.0,
    marker_every: int | None = None,
) -> tuple[plt.Figure, plt.Axes]:
    fig, ax = create_panel_figure(
        width_mm=width_mm or PANEL_WIDTH_MM,
        height_mm=height_mm or PANEL_HEIGHT_MM,
        left_margin_mm=left_margin_mm,
        right_margin_mm=right_margin_mm,
        bottom_margin_mm=bottom_margin_mm,
        top_margin_mm=top_margin_mm,
    )
    palette = sns.color_palette("colorblind", n_colors=len(series_list))
    markers = marker_style_cycle or MARKER_STYLE_CYCLE

    for idx, (color, series) in enumerate(zip(palette, series_list)):
        markevery = marker_every if marker_every is not None else _infer_markevery(len(series.data))
        ax.plot(
            series.data["x"],
            series.data["y"],
            label=series.sample,
            color=color,
            alpha=LINE_ALPHA,
            linewidth=LINE_WIDTH_PT,
            marker=markers[idx % len(markers)] if show_markers else None,
            markersize=marker_size,
            markerfacecolor=color,
            markeredgecolor=color,
            markeredgewidth=0.5,
            markevery=markevery,
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

    first = series_list[0]
    ax.set_xlabel(_format_axis_label(first.x_label, first.x_unit))
    ax.set_ylabel(_format_axis_label(first.y_label, first.y_unit))
    if legend_mode == "inside_best":
        legend_kwargs, overlap_score = choose_legend_corner(ax, series_list)
        _nudge_limits_for_legend(ax, legend_kwargs, overlap_score, xscale=xscale, yscale=yscale)
        legend_kwargs, _ = choose_legend_corner(ax, series_list)
        ax.legend(**legend_kwargs)
    else:
        ax.legend(**_legend_kwargs(legend_mode))
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
    }
    params.update(overrides)
    return plot_curves(series_list, **params)


def plot_frequency_sweep(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("frequency_sweep", series_list, **overrides)


def plot_temperature_sweep(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("temperature_sweep", series_list, **overrides)


def plot_stress_relaxation(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("stress_relaxation", series_list, **overrides)


def plot_tensile_curve(series_list: Sequence[CurveSeries], **overrides: object) -> tuple[plt.Figure, plt.Axes]:
    return plot_curve_template("tensile_curve", series_list, **overrides)


def plot_box(
    groups: Sequence[ReplicateGroup],
    *,
    legend_mode: LegendMode = "outside",
    axis_mode: AxisMode = "auto",
    box_width: float = 0.35,
    spacing_scale: float = 1.0,
    ylim: tuple[float, float] | None = None,
    headroom_factor: float | None = None,
    y_padding_top: float = 0.12,
    y_padding_bottom: float = 0.06,
) -> tuple[plt.Figure, plt.Axes]:
    fig, ax = create_panel_figure()
    palette = sns.color_palette("colorblind", n_colors=len(groups))
    values = [group.data.to_numpy() for group in groups]
    positions = compute_group_positions(len(groups), box_width, spacing_scale=spacing_scale)
    box = ax.boxplot(
        values,
        tick_labels=[group.group for group in groups],
        positions=positions,
        patch_artist=True,
        widths=box_width,
        medianprops={"color": "black", "linewidth": LINE_WIDTH_PT},
        whiskerprops={"linewidth": 1.0},
        capprops={"linewidth": 1.0},
        boxprops={"linewidth": 1.0},
    )
    for patch, color in zip(box["boxes"], palette):
        patch.set_facecolor(color)
        patch.set_alpha(min(FILL_ALPHA, MAX_FILL_ALPHA))
        patch.set_edgecolor(color)

    for pos, group, color in zip(positions, groups, palette):
        x = np.full(len(group.data), pos, dtype=float)
        jitter_half_span = min(0.06, box_width * 0.18)
        jitter = (
            np.linspace(-jitter_half_span, jitter_half_span, len(group.data))
            if len(group.data) > 1
            else np.array([0.0])
        )
        ax.scatter(x + jitter, group.data, color=color, alpha=MARKER_ALPHA, s=10, zorder=3)

    limits = compute_axis_limits(
        values,
        kind="box",
        axis_mode=axis_mode,
        legend_mode=legend_mode,
        headroom_factor=headroom_factor,
        y_padding_top=y_padding_top,
        y_padding_bottom=y_padding_bottom,
    )
    ax.set_ylim(*(ylim or limits.ylim))
    if len(positions):
        side_padding = max(0.28, box_width * 0.9)
        ax.set_xlim(positions[0] - side_padding, positions[-1] + side_padding)

    first = groups[0]
    ax.set_ylabel(_format_axis_label(first.value_label, first.value_unit))
    return fig, ax


def plot_bar(
    groups: Sequence[ReplicateGroup],
    *,
    legend_mode: LegendMode = "outside",
    axis_mode: AxisMode = "auto_positive",
    bar_width: float = 0.35,
    spacing_scale: float = 1.0,
    ylim: tuple[float, float] | None = None,
    headroom_factor: float | None = None,
    y_padding_top: float = 0.15,
    y_padding_bottom: float = 0.02,
) -> tuple[plt.Figure, plt.Axes]:
    fig, ax = create_panel_figure()
    palette = sns.color_palette("colorblind", n_colors=len(groups))

    means = np.array([group.data.mean() for group in groups], dtype=float)
    stds = np.array([group.data.std(ddof=1) if len(group.data) > 1 else 0.0 for group in groups], dtype=float)
    positions = compute_group_positions(len(groups), bar_width, spacing_scale=spacing_scale)

    bars = ax.bar(
        positions,
        means,
        yerr=stds,
        capsize=2.5,
        width=bar_width,
        color=palette,
        edgecolor=palette,
        linewidth=1.0,
        alpha=min(FILL_ALPHA, MAX_FILL_ALPHA),
    )
    for bar, color in zip(bars, palette):
        bar.set_edgecolor(color)

    for pos, group, color in zip(positions, groups, palette):
        jitter_half_span = min(0.06, bar_width * 0.18)
        jitter = (
            np.linspace(-jitter_half_span, jitter_half_span, len(group.data))
            if len(group.data) > 1
            else np.array([0.0])
        )
        ax.scatter(
            np.full(len(group.data), pos, dtype=float) + jitter,
            group.data,
            color=color,
            alpha=MARKER_ALPHA,
            s=10,
            zorder=3,
        )

    values = [np.concatenate([group.data.to_numpy(), [mean + std]]) for group, mean, std in zip(groups, means, stds)]
    limits = compute_axis_limits(
        values,
        kind="bar",
        axis_mode=axis_mode,
        legend_mode=legend_mode,
        headroom_factor=headroom_factor,
        y_padding_top=y_padding_top,
        y_padding_bottom=y_padding_bottom,
    )
    ax.set_ylim(*(ylim or limits.ylim))
    ax.set_xticks(positions)
    ax.set_xticklabels([group.group for group in groups])
    if len(positions):
        side_padding = max(0.28, bar_width * 0.9)
        ax.set_xlim(positions[0] - side_padding, positions[-1] + side_padding)

    first = groups[0]
    ax.set_ylabel(_format_axis_label(first.value_label, first.value_unit))
    return fig, ax
