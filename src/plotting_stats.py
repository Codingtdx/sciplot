from __future__ import annotations

from collections.abc import Sequence

import matplotlib.pyplot as plt
import numpy as np

from src import plot_style
from src.data_loader import ReplicateGroup
from src.plotting import (
    MAX_VISIBLE_Y_MAJOR_TICKS,
    AxisLimits,
    AxisMode,
    LegendMode,
    _apply_explicit_major_ticks,
    _format_axis_label,
    _resolved_panel_geometry,
    _style_categorical_ticklabels,
    _validate_group_input,
    compute_axis_limits,
    compute_group_positions,
)


def _compute_distribution_axis_limits(
    values: Sequence[np.ndarray] | Sequence[Sequence[float]],
    *,
    axis_mode: AxisMode,
    legend_mode: LegendMode,
    headroom_factor: float | None,
    y_padding_top: float,
    y_padding_bottom: float,
) -> AxisLimits:
    return compute_axis_limits(
        values,
        kind="box",
        axis_mode=axis_mode,
        legend_mode=legend_mode,
        headroom_factor=headroom_factor,
        y_padding_top=y_padding_top,
        y_padding_bottom=y_padding_bottom,
    )


def plot_box(
    groups: Sequence[ReplicateGroup],
    *,
    legend_mode: LegendMode = "outside",
    axis_mode: AxisMode = "auto",
    width_mm: float | None = None,
    height_mm: float | None = None,
    left_margin_mm: float | None = None,
    right_margin_mm: float | None = None,
    bottom_margin_mm: float | None = None,
    top_margin_mm: float | None = None,
    box_width: float = 0.35,
    spacing_scale: float = 1.0,
    ylim: tuple[float, float] | None = None,
    headroom_factor: float | None = None,
    y_padding_top: float = 0.12,
    y_padding_bottom: float = 0.06,
) -> tuple[plt.Figure, plt.Axes]:
    _validate_group_input(groups, chart_name="box plot")
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
        left_margin_mm=left_margin_mm,
        height_mm=height_mm,
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
    palette = plot_style.get_categorical_palette(n_colors=len(groups))
    values = [group.data.to_numpy() for group in groups]
    positions = compute_group_positions(len(groups), box_width, spacing_scale=spacing_scale)
    box = ax.boxplot(
        values,
        tick_labels=[group.group for group in groups],
        positions=positions,
        patch_artist=True,
        widths=box_width,
        medianprops={"color": "black", "linewidth": stroke.line_width_pt},
        whiskerprops={"linewidth": 1.0},
        capprops={"linewidth": 1.0},
        boxprops={"linewidth": 1.0},
    )
    for patch, color in zip(box["boxes"], palette, strict=True):
        patch.set_facecolor(color)
        patch.set_alpha(min(stroke.fill_alpha, stroke.max_fill_alpha))
        patch.set_edgecolor(color)

    for pos, group, color in zip(positions, groups, palette, strict=True):
        jitter_half_span = min(0.06, box_width * 0.18)
        jitter = (
            np.linspace(-jitter_half_span, jitter_half_span, len(group.data))
            if len(group.data) > 1
            else np.array([0.0])
        )
        ax.scatter(
            np.full(len(group.data), pos, dtype=float) + jitter,
            group.data,
            color=color,
            alpha=stroke.marker_alpha,
            s=10,
            zorder=3,
        )

    limits = _compute_distribution_axis_limits(
        values,
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
    _style_categorical_ticklabels(ax, [group.group for group in groups])
    if limits.y_tick_policy is not None:
        _apply_explicit_major_ticks(
            ax.yaxis,
            limits.y_tick_policy.major_ticks,
            max_major_ticks=MAX_VISIBLE_Y_MAJOR_TICKS,
        )

    first = groups[0]
    ax.set_ylabel(_format_axis_label(first.value_label, first.value_unit))
    return fig, ax


def plot_bar(
    groups: Sequence[ReplicateGroup],
    *,
    legend_mode: LegendMode = "outside",
    axis_mode: AxisMode = "auto_positive",
    width_mm: float | None = None,
    height_mm: float | None = None,
    left_margin_mm: float | None = None,
    right_margin_mm: float | None = None,
    bottom_margin_mm: float | None = None,
    top_margin_mm: float | None = None,
    bar_width: float = 0.35,
    spacing_scale: float = 1.0,
    capsize: float = 2.5,
    show_raw_points: bool = False,
    raw_point_size: float = 10.0,
    raw_point_alpha: float | None = None,
    raw_point_jitter_fraction: float = 0.18,
    ylim: tuple[float, float] | None = None,
    headroom_factor: float | None = None,
    y_padding_top: float = 0.15,
    y_padding_bottom: float = 0.02,
) -> tuple[plt.Figure, plt.Axes]:
    _validate_group_input(groups, chart_name="bar plot")
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
    palette = plot_style.get_categorical_palette(n_colors=len(groups))

    means = np.array([group.data.mean() for group in groups], dtype=float)
    stds = np.array(
        [group.data.std(ddof=1) if len(group.data) > 1 else 0.0 for group in groups],
        dtype=float,
    )
    positions = compute_group_positions(len(groups), bar_width, spacing_scale=spacing_scale)

    bars = ax.bar(
        positions,
        means,
        yerr=stds,
        capsize=capsize,
        width=bar_width,
        color=palette,
        edgecolor=palette,
        linewidth=1.0,
        alpha=min(stroke.fill_alpha, stroke.max_fill_alpha),
    )
    for bar, color in zip(bars, palette, strict=True):
        bar.set_edgecolor(color)

    if show_raw_points:
        for pos, group, color in zip(positions, groups, palette, strict=True):
            jitter_half_span = min(0.075, max(bar_width * raw_point_jitter_fraction, 0.03))
            jitter = (
                np.linspace(-jitter_half_span, jitter_half_span, len(group.data))
                if len(group.data) > 1
                else np.array([0.0])
            )
            ax.scatter(
                np.full(len(group.data), pos, dtype=float) + jitter,
                group.data,
                color=color,
                alpha=stroke.marker_alpha if raw_point_alpha is None else raw_point_alpha,
                s=raw_point_size,
                zorder=3,
                linewidths=0.0,
            )

    values = [
        np.concatenate([group.data.to_numpy(), [mean + std]])
        for group, mean, std in zip(groups, means, stds, strict=True)
    ]
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
    _style_categorical_ticklabels(ax, [group.group for group in groups])
    if len(positions):
        side_padding = max(0.28, bar_width * 0.9)
        ax.set_xlim(positions[0] - side_padding, positions[-1] + side_padding)
    if limits.y_tick_policy is not None:
        _apply_explicit_major_ticks(
            ax.yaxis,
            limits.y_tick_policy.major_ticks,
            max_major_ticks=MAX_VISIBLE_Y_MAJOR_TICKS,
        )

    first = groups[0]
    ax.set_ylabel(_format_axis_label(first.value_label, first.value_unit))
    return fig, ax


def plot_violin(
    groups: Sequence[ReplicateGroup],
    *,
    legend_mode: LegendMode = "outside",
    axis_mode: AxisMode = "auto",
    width_mm: float | None = None,
    height_mm: float | None = None,
    left_margin_mm: float | None = None,
    right_margin_mm: float | None = None,
    bottom_margin_mm: float | None = None,
    top_margin_mm: float | None = None,
    violin_width: float = 0.42,
    spacing_scale: float = 1.0,
    ylim: tuple[float, float] | None = None,
    headroom_factor: float | None = None,
    y_padding_top: float = 0.12,
    y_padding_bottom: float = 0.06,
) -> tuple[plt.Figure, plt.Axes]:
    _validate_group_input(groups, chart_name="violin plot")
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
    palette = plot_style.get_categorical_palette(n_colors=len(groups))
    values = [group.data.to_numpy(dtype=float) for group in groups]
    positions = compute_group_positions(len(groups), violin_width, spacing_scale=spacing_scale)
    violin = ax.violinplot(
        values,
        positions=positions,
        widths=violin_width,
        showmeans=False,
        showmedians=True,
        showextrema=False,
    )
    for body, color in zip(violin["bodies"], palette, strict=True):
        body.set_facecolor(color)
        body.set_edgecolor(color)
        body.set_alpha(min(stroke.fill_alpha, stroke.max_fill_alpha))
        body.set_linewidth(1.0)
    if "cmedians" in violin:
        violin["cmedians"].set_color("black")
        violin["cmedians"].set_linewidth(stroke.line_width_pt)

    limits = _compute_distribution_axis_limits(
        values,
        axis_mode=axis_mode,
        legend_mode=legend_mode,
        headroom_factor=headroom_factor,
        y_padding_top=y_padding_top,
        y_padding_bottom=y_padding_bottom,
    )
    ax.set_ylim(*(ylim or limits.ylim))
    ax.set_xticks(positions)
    if len(positions):
        side_padding = max(0.28, violin_width * 0.9)
        ax.set_xlim(positions[0] - side_padding, positions[-1] + side_padding)
    _style_categorical_ticklabels(ax, [group.group for group in groups])
    if limits.y_tick_policy is not None:
        _apply_explicit_major_ticks(
            ax.yaxis,
            limits.y_tick_policy.major_ticks,
            max_major_ticks=MAX_VISIBLE_Y_MAJOR_TICKS,
        )

    first = groups[0]
    ax.set_ylabel(_format_axis_label(first.value_label, first.value_unit))
    return fig, ax


def plot_box_bar_plots(
    groups: Sequence[ReplicateGroup],
    *,
    box_width: float = 0.35,
    bar_width: float = 0.35,
    spacing_scale: float = 1.0,
) -> dict[str, tuple[plt.Figure, plt.Axes]]:
    return {
        "box": plot_box(groups, box_width=box_width, spacing_scale=spacing_scale),
        "bar": plot_bar(groups, bar_width=bar_width, spacing_scale=spacing_scale),
    }
