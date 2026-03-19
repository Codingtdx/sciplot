from __future__ import annotations

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

from src import plot_style
from src.data_loader import HeatmapTable
from src.plotting import (
    _HEATMAP_LAYOUT,
    _compute_heatmap_cax_geometry,
    _format_axis_label,
    _resolved_panel_geometry,
)


def plot_heatmap(
    table: HeatmapTable,
    *,
    width_mm: float | None = None,
    height_mm: float | None = None,
    left_margin_mm: float | None = None,
    right_margin_mm: float | None = None,
    bottom_margin_mm: float | None = None,
    top_margin_mm: float | None = None,
    show_colorbar: bool = True,
) -> tuple[plt.Figure, plt.Axes]:
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

    x_is_numeric = pd.api.types.is_numeric_dtype(table.data["x"])
    y_is_numeric = pd.api.types.is_numeric_dtype(table.data["y"])

    if x_is_numeric:
        x_order = sorted(pd.unique(table.data["x"]).tolist())
    else:
        x_order = pd.unique(table.data["x"]).tolist()
    if y_is_numeric:
        y_order = sorted(pd.unique(table.data["y"]).tolist())
    else:
        y_order = pd.unique(table.data["y"]).tolist()

    matrix = table.data.pivot(index="y", columns="x", values="z").reindex(
        index=y_order,
        columns=x_order,
    )

    cax = None
    colorbar_label = None
    if show_colorbar:
        position = ax.get_position()
        heatmap_rect, cax_rect = _compute_heatmap_cax_geometry(position)
        ax.set_position(heatmap_rect)
        cax = fig.add_axes(cax_rect)
        colorbar_label = fig.text(
            position.x0,
            min(
                0.975,
                position.y1
                + (1.0 - position.y1) * float(_HEATMAP_LAYOUT["label_y_fraction"]),
            ),
            _format_axis_label(table.z_label, table.z_unit),
            ha="left",
            va="center",
            fontsize=float(_HEATMAP_LAYOUT["label_font_size_pt"]),
        )

    heatmap = sns.heatmap(
        matrix,
        ax=ax,
        cmap=plot_style.get_sequential_cmap(),
        cbar=False,
        linewidths=0.0,
    )
    ax.set_xlabel(_format_axis_label(table.x_label, table.x_unit))
    ax.set_ylabel(_format_axis_label(table.y_label, table.y_unit))
    ax.tick_params(axis="x", rotation=0)
    ax.tick_params(axis="y", rotation=0)

    for tick in ax.get_xticklabels():
        tick.set_fontsize(6)
    for tick in ax.get_yticklabels():
        tick.set_fontsize(6)

    if show_colorbar and heatmap.collections and cax is not None:
        z_min = float(np.nanmin(matrix.to_numpy(dtype=float)))
        z_max = float(np.nanmax(matrix.to_numpy(dtype=float)))
        colorbar = fig.colorbar(heatmap.collections[0], cax=cax, orientation="horizontal")
        colorbar.set_ticks(np.linspace(z_min, z_max, 3))
        colorbar.ax.tick_params(
            labelsize=float(_HEATMAP_LAYOUT["tick_font_size_pt"]),
            pad=0.2,
            length=float(_HEATMAP_LAYOUT["tick_length_pt"]),
        )
        colorbar.outline.set_linewidth(0.8)
        if colorbar_label is not None:
            colorbar_label.set_fontsize(float(_HEATMAP_LAYOUT["label_font_size_pt"]))
    return fig, ax
