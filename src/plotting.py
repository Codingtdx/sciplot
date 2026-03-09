from __future__ import annotations

from dataclasses import dataclass
import textwrap
from typing import Sequence

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
from matplotlib import transforms
from matplotlib.colors import to_rgba
from matplotlib.legend import Legend
from matplotlib.patches import Rectangle
from matplotlib.ticker import FixedLocator, LogLocator

from src.data_loader import CurveSeries, HeatmapTable, ReplicateGroup
from src.plot_style import (
    BOTTOM_MARGIN_MM,
    FILL_ALPHA,
    FONT_SIZE_PT,
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
    mm_to_inch,
)
from src.text_normalization import normalize_label, normalize_unit
from src.wide_nmr import (
    WIDE_NMR_SPECTRUM_HEIGHT_MM,
    WIDE_NMR_STRUCTURE_RESERVED_MM,
    WIDE_NMR_TOTAL_HEIGHT_MM,
    WIDE_NMR_WIDTH_MM,
    WideNMRConfig,
    WideNMRHighlightRegion,
    WideNMRSegment,
)


LegendMode = str
AxisMode = str
MARKER_STYLE_CYCLE = ("o", "s", "^", "D", "v", "P", "X")
HIDDEN_Y_LABEL_X = -0.167
INSIDE_LEGEND_INSET_FRACTION = 0.025
MAX_VISIBLE_Y_MAJOR_TICKS = 7


@dataclass
class AxisLimits:
    xlim: tuple[float, float]
    ylim: tuple[float, float]
    raw_xlim: tuple[float, float] | None = None
    raw_ylim: tuple[float, float] | None = None


@dataclass(frozen=True)
class SharedAxisLayout:
    display_bounds: tuple[float, float]
    raw_bounds: tuple[float, float]
    visible_ticks: tuple[float, ...]


@dataclass(frozen=True)
class StackedLayout:
    series_list: list[CurveSeries]
    floor: float
    step: float
    max_span: float


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
    reverse_x: bool = False
    show_markers: bool = True
    stack_mode: str = "none"
    stack_floor_fraction: float = 0.22
    stack_gap_fraction: float = 0.22
    series_label_mode: str = "legend"
    series_label_side: str = "auto"
    label_track_inset_fraction: float = 0.06
    label_offset_pt: float = 5.0
    baseline_mode: str = "none"
    show_y_ticks: bool = True


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
    "ftir": CurveTemplate(
        xscale="linear",
        yscale="linear",
        width_mm=PANEL_WIDTH_MM,
        height_mm=PANEL_HEIGHT_MM,
        left_margin_mm=LEFT_MARGIN_MM,
        right_margin_mm=RIGHT_MARGIN_MM,
        bottom_margin_mm=BOTTOM_MARGIN_MM,
        top_margin_mm=TOP_MARGIN_MM,
        y_padding_top=0.08,
        y_padding_bottom=0.04,
        legend_mode="none",
        reverse_x=True,
        show_markers=False,
        stack_mode="auto_vertical",
        series_label_mode="edge",
        show_y_ticks=False,
    ),
    "nmr": CurveTemplate(
        xscale="linear",
        yscale="linear",
        width_mm=PANEL_WIDTH_MM,
        height_mm=PANEL_HEIGHT_MM,
        left_margin_mm=LEFT_MARGIN_MM,
        right_margin_mm=RIGHT_MARGIN_MM,
        bottom_margin_mm=BOTTOM_MARGIN_MM,
        top_margin_mm=TOP_MARGIN_MM,
        y_padding_top=0.08,
        y_padding_bottom=0.04,
        legend_mode="none",
        reverse_x=True,
        show_markers=False,
        stack_mode="auto_vertical",
        series_label_mode="edge",
        baseline_mode="linear_endpoints",
        show_y_ticks=False,
    ),
    "xrd": CurveTemplate(
        xscale="linear",
        yscale="linear",
        width_mm=PANEL_WIDTH_MM,
        height_mm=PANEL_HEIGHT_MM,
        left_margin_mm=LEFT_MARGIN_MM,
        right_margin_mm=RIGHT_MARGIN_MM,
        bottom_margin_mm=BOTTOM_MARGIN_MM,
        top_margin_mm=TOP_MARGIN_MM,
        y_padding_top=0.08,
        y_padding_bottom=0.04,
        legend_mode="none",
        show_markers=False,
        stack_mode="auto_vertical",
        series_label_mode="edge",
        show_y_ticks=False,
    ),
    "dsc": CurveTemplate(
        xscale="linear",
        yscale="linear",
        width_mm=PANEL_WIDTH_MM,
        height_mm=PANEL_HEIGHT_MM,
        left_margin_mm=LEFT_MARGIN_MM,
        right_margin_mm=RIGHT_MARGIN_MM,
        bottom_margin_mm=BOTTOM_MARGIN_MM,
        top_margin_mm=TOP_MARGIN_MM,
        y_padding_top=0.08,
        y_padding_bottom=0.04,
        legend_mode="none",
        show_markers=False,
        stack_mode="auto_vertical",
        series_label_mode="edge",
        baseline_mode="linear_endpoints",
        show_y_ticks=False,
    ),
    "tga": CurveTemplate(
        xscale="linear",
        yscale="linear",
        width_mm=PANEL_WIDTH_MM,
        height_mm=PANEL_HEIGHT_MM,
        left_margin_mm=LEFT_MARGIN_MM,
        right_margin_mm=RIGHT_MARGIN_MM,
        bottom_margin_mm=BOTTOM_MARGIN_MM,
        top_margin_mm=TOP_MARGIN_MM,
        show_markers=False,
    ),
    "dma": CurveTemplate(
        xscale="linear",
        yscale="linear",
        width_mm=PANEL_WIDTH_MM,
        height_mm=PANEL_HEIGHT_MM,
        left_margin_mm=LEFT_MARGIN_MM,
        right_margin_mm=RIGHT_MARGIN_MM,
        bottom_margin_mm=BOTTOM_MARGIN_MM,
        top_margin_mm=TOP_MARGIN_MM,
        show_markers=False,
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
    display_label = normalize_label(label)
    display_unit = normalize_unit(unit)
    return f"{display_label} ({display_unit})" if display_unit else display_label


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


def _nice_linear_padding(value: float) -> float:
    if not np.isfinite(value) or value <= 0:
        return 1.0
    exponent = float(np.floor(np.log10(value)))
    base = 10 ** exponent
    scaled = value / base
    if scaled <= 1:
        nice = 1
    elif scaled <= 2:
        nice = 2
    elif scaled <= 5:
        nice = 5
    else:
        nice = 10
    return float(nice * base)


def _pad_limits_linear_curve(
    data_min: float,
    data_max: float,
    *,
    padding_fraction: float = 0.05,
) -> tuple[float, float]:
    span = data_max - data_min
    baseline = span if span > 0 else max(abs(data_min), abs(data_max), 1.0)
    padding = _nice_linear_padding(baseline * padding_fraction)
    low = data_min - padding
    high = data_max + padding
    if np.isclose(low, high):
        high = low + padding * 2
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


def _pad_limits_log_curve(
    data_min: float,
    data_max: float,
    *,
    lower_padding: float,
    upper_padding: float,
) -> tuple[float, float]:
    return _pad_limits_log(
        data_min,
        data_max,
        lower_padding=max(lower_padding, 0.05),
        upper_padding=max(upper_padding, 0.08),
    )


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
    """Compute display bounds and keep raw data bounds for tick filtering."""
    y_arrays = _validate_scale_values(values, scale=yscale, axis_name="Y")

    y_min = min(float(arr.min()) for arr in y_arrays)
    y_max = max(float(arr.max()) for arr in y_arrays)

    allow_below_zero = legend_mode == "inside_forced" and y_min >= 0
    if yscale == "log":
        y_low, y_high = _pad_limits_log_curve(
            y_min,
            y_max,
            lower_padding=y_padding_bottom,
            upper_padding=y_padding_top,
        )
    elif kind == "line":
        y_low, y_high = _pad_limits_linear_curve(
            y_min,
            y_max,
            padding_fraction=max(y_padding_top, y_padding_bottom, 0.05),
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

    if kind == "bar" and axis_mode != "manual" and y_min >= 0:
        y_low = 0.0

    if x_values is None:
        return AxisLimits(xlim=(0.0, 1.0), ylim=(y_low, y_high), raw_ylim=(y_min, y_max))

    x_arrays = _validate_scale_values(x_values, scale=xscale, axis_name="X")

    x_min = min(float(arr.min()) for arr in x_arrays)
    x_max = max(float(arr.max()) for arr in x_arrays)
    if xscale == "log":
        x_low, x_high = _pad_limits_log_curve(
            x_min,
            x_max,
            lower_padding=x_padding,
            upper_padding=x_padding,
        )
    elif kind == "line":
        x_low, x_high = _pad_limits_linear_curve(
            x_min,
            x_max,
            padding_fraction=max(x_padding, 0.05),
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
    return AxisLimits(
        xlim=(x_low, x_high),
        ylim=(y_low, y_high),
        raw_xlim=(x_min, x_max),
        raw_ylim=(y_min, y_max),
    )


def _legend_kwargs(legend_mode: LegendMode) -> dict[str, object]:
    if legend_mode == "none":
        return {}
    if legend_mode == "outside":
        return {"loc": "upper left", "bbox_to_anchor": (1.02, 1.0), "borderaxespad": 0.0}
    if legend_mode == "inside_forced":
        return {"loc": "upper right"}
    return {"loc": "upper right"}


def _infer_markevery(length: int) -> int | None:
    if length <= 20:
        return None
    return max(2, int(np.ceil(length / 12)))


def _clone_curve_series(series: CurveSeries, data: pd.DataFrame) -> CurveSeries:
    return CurveSeries(
        sample=series.sample,
        x_label=series.x_label,
        y_label=series.y_label,
        x_unit=series.x_unit,
        y_unit=series.y_unit,
        data=data,
    )


def _baseline_correct_series(
    series_list: Sequence[CurveSeries],
    *,
    baseline_mode: str = "none",
) -> list[CurveSeries]:
    if baseline_mode == "none":
        return list(series_list)

    corrected: list[CurveSeries] = []
    for series in series_list:
        x = series.data["x"].to_numpy(dtype=float)
        y = series.data["y"].to_numpy(dtype=float)
        valid = np.isfinite(x) & np.isfinite(y)
        if valid.sum() < 3:
            corrected.append(_clone_curve_series(series, series.data.copy()))
            continue

        x_valid = x[valid]
        y_valid = y[valid]
        n_edge = max(3, min(len(x_valid) // 12, 30))
        x_start = float(np.mean(x_valid[:n_edge]))
        y_start = float(np.mean(y_valid[:n_edge]))
        x_end = float(np.mean(x_valid[-n_edge:]))
        y_end = float(np.mean(y_valid[-n_edge:]))

        if np.isclose(x_start, x_end):
            baseline = np.full_like(y, y_start, dtype=float)
        else:
            slope = (y_end - y_start) / (x_end - x_start)
            baseline = y_start + slope * (x - x_start)

        shifted = series.data.copy()
        shifted["y"] = shifted["y"] - baseline
        corrected.append(_clone_curve_series(series, shifted))

    return corrected


def _robust_span(values: np.ndarray) -> float:
    finite = values[np.isfinite(values)]
    if finite.size == 0:
        return 1.0
    q05, q95 = np.quantile(finite, [0.05, 0.95])
    span = float(q95 - q05)
    if np.isclose(span, 0.0):
        span = float(finite.max() - finite.min())
    if np.isclose(span, 0.0):
        span = max(abs(float(finite.max())), 1.0) * 0.15
    return span


def _prepare_stacked_layout(
    series_list: Sequence[CurveSeries],
    *,
    stack_floor_fraction: float,
    stack_gap_fraction: float,
) -> StackedLayout:
    if len(series_list) <= 1:
        spans = [
            _robust_span(series.data["y"].to_numpy(dtype=float))
            for series in series_list
        ]
        max_span = max(spans) if spans else 1.0
        return StackedLayout(list(series_list), 0.0, max_span, max_span)

    prepared: list[tuple[CurveSeries, pd.DataFrame, float]] = []
    spans: list[float] = []
    for series in series_list:
        y = series.data["y"].to_numpy(dtype=float)
        finite = y[np.isfinite(y)]
        shifted = series.data.copy()
        if finite.size:
            shifted["y"] = shifted["y"] - float(finite.min())
        span = _robust_span(shifted["y"].to_numpy(dtype=float))
        prepared.append((series, shifted, span))
        spans.append(span)

    max_span = max(spans) if spans else 1.0
    floor = max_span * stack_floor_fraction
    step = max_span * (1.0 + stack_gap_fraction)

    stacked: list[CurveSeries] = []
    for idx, (series, shifted, _) in enumerate(prepared):
        final = shifted.copy()
        final["y"] = final["y"] + floor + idx * step
        stacked.append(_clone_curve_series(series, final))

    return StackedLayout(stacked, floor, step, max_span)


def _compute_x_limits(
    x_values: Sequence[np.ndarray] | Sequence[Sequence[float]],
    *,
    xscale: str,
    x_padding: float = 0.02,
) -> tuple[tuple[float, float], tuple[float, float]]:
    x_arrays = _validate_scale_values(x_values, scale=xscale, axis_name="X")
    x_min = min(float(arr.min()) for arr in x_arrays)
    x_max = max(float(arr.max()) for arr in x_arrays)
    if xscale == "log":
        display = _pad_limits_log_curve(
            x_min,
            x_max,
            lower_padding=x_padding,
            upper_padding=x_padding,
        )
    else:
        display = _pad_limits_linear_curve(
            x_min,
            x_max,
            padding_fraction=max(x_padding, 0.05),
        )
    return display, (x_min, x_max)


def _compute_visible_ticks(
    *,
    scale: str,
    display_bounds: tuple[float, float],
    raw_bounds: tuple[float, float],
) -> tuple[float, ...]:
    fig, ax = plt.subplots()
    try:
        if scale == "log":
            ax.set_xscale("log")
        ax.set_xlim(*display_bounds)
        try:
            ticks = ax.xaxis.get_major_locator().tick_values(*display_bounds)
        except Exception:
            ticks = np.asarray(ax.get_xticks(), dtype=float)
    finally:
        plt.close(fig)
    bounds_for_ticks = tuple(sorted(display_bounds)) if scale == "log" else raw_bounds
    filtered = _filter_ticks_to_raw_bounds(np.asarray(ticks, dtype=float), bounds_for_ticks, scale=scale)
    return tuple(float(tick) for tick in filtered)


def compute_shared_curve_x_layout(
    x_values: Sequence[np.ndarray] | Sequence[Sequence[float]],
    *,
    xscale: str,
    x_padding: float = 0.02,
) -> SharedAxisLayout:
    display_bounds, raw_bounds = _compute_x_limits(
        x_values,
        xscale=xscale,
        x_padding=x_padding,
    )
    visible_ticks = _compute_visible_ticks(
        scale=xscale,
        display_bounds=display_bounds,
        raw_bounds=raw_bounds,
    )
    return SharedAxisLayout(
        display_bounds=display_bounds,
        raw_bounds=raw_bounds,
        visible_ticks=visible_ticks,
    )


def _compute_stacked_axis_limits(
    layout: StackedLayout,
    *,
    xscale: str,
    y_padding_top: float,
) -> AxisLimits:
    xlim, raw_xlim = _compute_x_limits(
        [series.data["x"].to_numpy(dtype=float) for series in layout.series_list],
        xscale=xscale,
    )
    y_arrays = _validate_scale_values(
        [series.data["y"].to_numpy(dtype=float) for series in layout.series_list],
        scale="linear",
        axis_name="Y",
    )
    y_min = min(float(arr.min()) for arr in y_arrays)
    y_max = max(float(arr.max()) for arr in y_arrays)
    y_high = y_max + layout.max_span * max(y_padding_top, 0.08)
    return AxisLimits(
        xlim=xlim,
        ylim=(0.0, y_high),
        raw_xlim=raw_xlim,
        raw_ylim=(y_min, y_max),
    )


def _resolve_visual_edge_target(x: np.ndarray, reverse_x: bool, side: str, inset_fraction: float = 0.06) -> float:
    x_min = float(np.min(x))
    x_max = float(np.max(x))
    span = x_max - x_min
    if np.isclose(span, 0.0):
        return x_min
    if side == "left":
        return x_max - span * inset_fraction if reverse_x else x_min + span * inset_fraction
    return x_min + span * inset_fraction if reverse_x else x_max - span * inset_fraction


def _score_series_label_side(
    series_list: Sequence[CurveSeries],
    reverse_x: bool,
    side: str,
    *,
    inset_fraction: float,
) -> float:
    score = 0.0
    for series in series_list:
        x = series.data["x"].to_numpy(dtype=float)
        y = series.data["y"].to_numpy(dtype=float)
        valid = np.isfinite(x) & np.isfinite(y)
        x = x[valid]
        y = y[valid]
        if len(x) < 4:
            continue
        order = np.argsort(x)
        x = x[order]
        y = y[order]
        target_x = _resolve_visual_edge_target(x, reverse_x, side, inset_fraction=inset_fraction)
        window = max((x.max() - x.min()) * 0.08, 1e-9)
        mask = np.abs(x - target_x) <= window
        if mask.sum() < 4:
            idx = int(np.argmin(np.abs(x - target_x)))
            lo = max(0, idx - 2)
            hi = min(len(x), idx + 3)
            local_y = y[lo:hi]
        else:
            local_y = y[mask]
        if len(local_y) < 2:
            continue
        score += _robust_span(local_y)
        score += abs(float(local_y[-1] - local_y[0])) * 0.35
        score += float(np.mean(np.abs(np.diff(local_y)))) * 0.45
    return score


def _resolve_series_label_side(
    series_list: Sequence[CurveSeries],
    reverse_x: bool,
    series_label_side: str,
    *,
    inset_fraction: float,
) -> str:
    if series_label_side in {"left", "right"}:
        return series_label_side
    left_score = _score_series_label_side(series_list, reverse_x, "left", inset_fraction=inset_fraction)
    right_score = _score_series_label_side(series_list, reverse_x, "right", inset_fraction=inset_fraction)
    if np.isclose(left_score, right_score):
        return "left" if reverse_x else "right"
    return "left" if left_score < right_score else "right"


def _wrap_tick_label(text: str, width: int = 10) -> str:
    cleaned = str(text).strip()
    if not cleaned:
        return cleaned
    return "\n".join(textwrap.wrap(cleaned, width=width, break_long_words=False, break_on_hyphens=False))


def _style_categorical_ticklabels(ax: plt.Axes, labels: Sequence[str]) -> None:
    wrapped = [_wrap_tick_label(label) for label in labels]
    ax.set_xticklabels(wrapped)

    max_line = max(
        (max((len(line) for line in label.split("\n")), default=0) for label in wrapped),
        default=0,
    )
    has_unbreakable = any(" " not in label and len(label) > 12 for label in labels)
    fontsize = FONT_SIZE_PT
    rotation = 0
    ha = "center"

    if has_unbreakable or max_line > 10:
        fontsize = 6
    if max_line > 14 or any(" " not in label and len(label) > 16 for label in labels):
        rotation = 15
        ha = "right"

    for tick in ax.get_xticklabels():
        tick.set_fontsize(fontsize)
        tick.set_rotation(rotation)
        tick.set_rotation_mode("anchor")
        tick.set_ha(ha)
        tick.set_va("top")


def _display_points_for_series(ax: plt.Axes, series_list: Sequence[CurveSeries]) -> list[np.ndarray]:
    display_points: list[np.ndarray] = []
    for series in series_list:
        x = series.data["x"].to_numpy(dtype=float)
        y = series.data["y"].to_numpy(dtype=float)
        valid = np.isfinite(x) & np.isfinite(y)
        if valid.sum() == 0:
            display_points.append(np.empty((0, 2)))
            continue
        display_points.append(ax.transData.transform(np.column_stack([x[valid], y[valid]])))
    return display_points


def _point_to_display_pixels(fig: plt.Figure, points: float) -> float:
    return points * fig.dpi / 72.0


def _override_complete(bounds: tuple[float | None, float | None] | None) -> bool:
    return bool(bounds is not None and bounds[0] is not None and bounds[1] is not None)


def _filter_ticks_to_raw_bounds(
    ticks: np.ndarray,
    raw_bounds: tuple[float, float],
    *,
    scale: str,
) -> np.ndarray:
    ticks = np.asarray(ticks, dtype=float)
    ticks = ticks[np.isfinite(ticks)]
    if ticks.size == 0:
        return ticks

    low, high = raw_bounds
    if scale == "log":
        mask = (ticks >= low * (1 - 1e-9)) & (ticks <= high * (1 + 1e-9))
    else:
        tol = max(abs(low), abs(high), abs(high - low), 1.0) * 1e-9
        mask = (ticks >= low - tol) & (ticks <= high + tol)
    filtered = ticks[mask]
    if filtered.size == 0:
        return filtered
    return np.unique(filtered)


def _cap_visible_major_ticks(
    ticks: np.ndarray,
    *,
    scale: str,
    max_major_ticks: int = 7,
) -> np.ndarray:
    ticks = np.asarray(ticks, dtype=float)
    ticks = ticks[np.isfinite(ticks)]
    if ticks.size < max_major_ticks:
        return ticks
    return ticks[::2]


def _validate_curve_series_input(series_list: Sequence[CurveSeries]) -> None:
    if not series_list:
        raise ValueError("No curve series were provided for plotting.")
    for index, series in enumerate(series_list, start=1):
        if not {"x", "y"}.issubset(series.data.columns):
            raise ValueError(f"Curve series {index} is missing required x/y columns.")
        if series.data.empty:
            raise ValueError(f"Curve series {index} ({series.sample!r}) does not contain any data.")
        numeric = series.data[["x", "y"]].apply(pd.to_numeric, errors="coerce")
        if numeric.dropna(how="all").empty:
            raise ValueError(f"Curve series {index} ({series.sample!r}) does not contain numeric x/y data.")


def _validate_group_input(groups: Sequence[ReplicateGroup], *, chart_name: str) -> None:
    if not groups:
        raise ValueError(f"No replicate groups were provided for {chart_name}.")
    for index, group in enumerate(groups, start=1):
        if group.data.empty:
            raise ValueError(f"{chart_name} group {index} ({group.group!r}) does not contain any replicate values.")


def _set_axis_locator_from_filtered_ticks(axis, ticks: np.ndarray, *, which: str) -> None:
    if ticks.size == 0:
        return
    locator = FixedLocator(ticks)
    if which == "major":
        axis.set_major_locator(locator)
    else:
        axis.set_minor_locator(locator)


def _apply_axis_tick_filter(
    axis,
    *,
    raw_bounds: tuple[float, float] | None,
    display_bounds: tuple[float, float],
    scale: str,
    include_minor: bool = True,
    max_major_ticks: int | None = None,
) -> None:
    if raw_bounds is None:
        return

    for which, locator_getter in (("major", axis.get_major_locator), ("minor", axis.get_minor_locator)):
        if which == "minor" and not include_minor:
            continue
        try:
            ticks = locator_getter().tick_values(*display_bounds)
        except Exception:
            continue
        bounds_for_ticks = tuple(sorted(display_bounds)) if scale == "log" else raw_bounds
        filtered = _filter_ticks_to_raw_bounds(ticks, bounds_for_ticks, scale=scale)
        if which == "major" and scale == "log" and raw_bounds is not None and filtered.size > 1:
            raw_low = float(min(raw_bounds))
            if filtered[0] < raw_low:
                filtered = filtered[1:]
        if which == "major" and max_major_ticks is not None:
            filtered = _cap_visible_major_ticks(filtered, scale=scale, max_major_ticks=max_major_ticks)
        _set_axis_locator_from_filtered_ticks(axis, filtered, which=which)


def _apply_visible_y_tick_policy(
    ax: plt.Axes,
    *,
    scale: str,
    raw_bounds: tuple[float, float] | None,
) -> None:
    bounds = tuple(sorted(ax.get_ylim()))
    display_bounds = ax.get_ylim()
    effective_raw_bounds = raw_bounds if raw_bounds is not None else bounds
    tick_raw_bounds = effective_raw_bounds

    try:
        major_ticks = ax.yaxis.get_major_locator().tick_values(*display_bounds)
    except Exception:
        major_ticks = np.array([], dtype=float)

    bounds_for_ticks = tuple(sorted(display_bounds)) if scale == "log" else effective_raw_bounds
    filtered_major = _filter_ticks_to_raw_bounds(major_ticks, bounds_for_ticks, scale=scale)

    if (
        raw_bounds is not None
        and filtered_major.size <= 3
        and filtered_major.size > 0
        and float(filtered_major.max()) < float(raw_bounds[1])
    ):
        y_low, y_high = ax.get_ylim()
        if scale == "log" and bounds[0] > 0 and bounds[1] > 0:
            expanded_upper = 10 ** np.ceil(np.log10(bounds[1]))
            if expanded_upper <= bounds[1]:
                expanded_upper *= 10
        else:
            if filtered_major.size >= 2:
                step = float(np.median(np.diff(filtered_major)))
            else:
                step = max(abs(float(bounds[1] - bounds[0])) * 0.2, 1.0)
            expanded_upper = max(float(bounds[1]), float(filtered_major.max()) + step)
            tick_raw_bounds = (effective_raw_bounds[0], expanded_upper)

        if y_low <= y_high:
            ax.set_ylim(y_low, expanded_upper)
        else:
            ax.set_ylim(expanded_upper, y_high)
        display_bounds = ax.get_ylim()

    _apply_axis_tick_filter(
        ax.yaxis,
        raw_bounds=tick_raw_bounds,
        display_bounds=display_bounds,
        scale=scale,
        max_major_ticks=MAX_VISIBLE_Y_MAJOR_TICKS,
    )


def _place_series_edge_labels(
    ax: plt.Axes,
    series_list: Sequence[CurveSeries],
    colors: Sequence[tuple[float, float, float] | str],
    *,
    reverse_x: bool,
    side: str,
    inset_fraction: float,
    label_offset_pt: float,
    labels: Sequence[str] | None = None,
    search_band_fraction: float = 0.06,
    fontsize: float = 6.0,
) -> None:
    visual_side = _resolve_series_label_side(
        series_list,
        reverse_x,
        side,
        inset_fraction=inset_fraction,
    )
    fig = ax.figure
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    display_points = _display_points_for_series(ax, series_list)
    axes_bbox = ax.get_window_extent(renderer=renderer)
    label_gap = _point_to_display_pixels(fig, 2.5)
    pixel_offset = _point_to_display_pixels(fig, label_offset_pt)
    all_points = [points for points in display_points if points.size]
    if not all_points:
        return
    all_curve_points = np.vstack(all_points)
    placed_bboxes = []
    label_texts = list(labels) if labels is not None else [series.sample for series in series_list]
    candidate_offsets = inset_fraction + np.linspace(0.0, search_band_fraction, 7)

    def _measure_text_bbox(label_text: str, color: tuple[float, float, float] | str):
        text = ax.text(
            0.5,
            0.5,
            label_text,
            ha="left" if visual_side == "left" else "right",
            va="bottom",
            color=color,
            fontsize=fontsize,
            alpha=0.0,
            transform=ax.transAxes,
        )
        fig.canvas.draw()
        bbox = text.get_window_extent(renderer=renderer)
        text.remove()
        return bbox

    def _candidate_x_positions(x: np.ndarray) -> list[tuple[float, float]]:
        x_min = float(np.min(x))
        x_max = float(np.max(x))
        span = max(x_max - x_min, 1e-9)
        positions: list[tuple[float, float]] = []
        for offset in candidate_offsets:
            if visual_side == "left":
                value = x_max - span * offset if reverse_x else x_min + span * offset
            else:
                value = x_min + span * offset if reverse_x else x_max - span * offset
            positions.append((value, offset))
        return positions

    def _series_local_display_top(
        x: np.ndarray,
        y: np.ndarray,
        candidate_x: float,
        bbox_width_px: float,
    ) -> float:
        candidate_display_x = float(ax.transData.transform((candidate_x, 0.0))[0])
        left_data_x = float(ax.transData.inverted().transform((candidate_display_x - bbox_width_px / 2, axes_bbox.y0))[0])
        right_data_x = float(ax.transData.inverted().transform((candidate_display_x + bbox_width_px / 2, axes_bbox.y0))[0])
        x_low, x_high = sorted((left_data_x, right_data_x))
        mask = (x >= x_low) & (x <= x_high)
        if mask.sum() == 0:
            idx = int(np.argmin(np.abs(x - candidate_x)))
            top_y = float(y[idx])
        else:
            top_y = float(np.max(y[mask]))
        return float(ax.transData.transform((candidate_x, top_y))[1])

    def _score_label_bbox(bbox, desired_bottom: float, candidate_offset: float) -> float:
        score = 0.0
        if bbox.x0 < axes_bbox.x0 or bbox.x1 > axes_bbox.x1 or bbox.y0 < axes_bbox.y0 or bbox.y1 > axes_bbox.y1:
            overflow = (
                max(axes_bbox.x0 - bbox.x0, 0.0)
                + max(bbox.x1 - axes_bbox.x1, 0.0)
                + max(axes_bbox.y0 - bbox.y0, 0.0)
                + max(bbox.y1 - axes_bbox.y1, 0.0)
            )
            score += 1_000_000 + overflow * 100

        expanded = bbox.expanded(1.03, 1.10)
        dx = np.where(
            all_curve_points[:, 0] < expanded.x0,
            expanded.x0 - all_curve_points[:, 0],
            np.where(all_curve_points[:, 0] > expanded.x1, all_curve_points[:, 0] - expanded.x1, 0.0),
        )
        dy = np.where(
            all_curve_points[:, 1] < expanded.y0,
            expanded.y0 - all_curve_points[:, 1],
            np.where(all_curve_points[:, 1] > expanded.y1, all_curve_points[:, 1] - expanded.y1, 0.0),
        )
        distance = np.hypot(dx, dy)
        inside = distance == 0
        if np.any(inside):
            score += float(inside.sum()) * 400.0
        near = distance < 7.0
        if np.any(near):
            score += float((7.0 - distance[near]).sum()) * 8.0

        for placed_bbox in placed_bboxes:
            if expanded.overlaps(placed_bbox):
                overlap_x = min(expanded.x1, placed_bbox.x1) - max(expanded.x0, placed_bbox.x0)
                overlap_y = min(expanded.y1, placed_bbox.y1) - max(expanded.y0, placed_bbox.y0)
                score += 1_000_000 + max(overlap_x, 0.0) * max(overlap_y, 0.0)

        score += abs(bbox.y0 - desired_bottom) * 0.25
        score += max(candidate_offset - inset_fraction, 0.0) * 100.0
        return score

    label_records: list[tuple[float, str, CurveSeries, tuple[float, float, float] | str, np.ndarray, np.ndarray, object]] = []
    for series, color, label_text in zip(series_list, colors, label_texts):
        x = series.data["x"].to_numpy(dtype=float)
        y = series.data["y"].to_numpy(dtype=float)
        valid = np.isfinite(x) & np.isfinite(y)
        x = x[valid]
        y = y[valid]
        if len(x) == 0:
            continue

        order = np.argsort(x)
        x = x[order]
        y = y[order]
        candidate_x = _candidate_x_positions(x)[0][0]
        text_bbox = _measure_text_bbox(label_text, color)
        display_y = _series_local_display_top(x, y, candidate_x, text_bbox.width)
        label_records.append((display_y, label_text, series, color, x, y, text_bbox))

    label_records.sort(key=lambda item: item[0], reverse=True)

    for _, label_text, series, color, x, y, text_bbox in label_records:
        best_choice: tuple[float, float, float, object] | None = None
        bbox_width = text_bbox.width
        bbox_height = text_bbox.height
        for candidate_x, candidate_offset in _candidate_x_positions(x):
            local_top = _series_local_display_top(x, y, candidate_x, bbox_width)
            base_bottom = max(local_top + pixel_offset, axes_bbox.y0 + label_gap)
            for step in range(10):
                candidate_bottom = base_bottom + step * (bbox_height * 0.55 + label_gap)
                max_bottom = axes_bbox.y1 - label_gap - bbox_height
                candidate_bottom = min(candidate_bottom, max_bottom)
                if candidate_bottom < axes_bbox.y0 + label_gap:
                    continue
                data_y = float(ax.transData.inverted().transform((ax.transData.transform((candidate_x, 0))[0], candidate_bottom))[1])
                text = ax.text(
                    candidate_x,
                    data_y,
                    label_text,
                    ha="left" if visual_side == "left" else "right",
                    va="bottom",
                    color=color,
                    fontsize=fontsize,
                    clip_on=True,
                    transform=ax.transData,
                )
                fig.canvas.draw()
                bbox = text.get_window_extent(renderer=renderer)
                score = _score_label_bbox(bbox, base_bottom, candidate_offset)
                text.remove()
                if best_choice is None or score < best_choice[0]:
                    best_choice = (score, candidate_x, data_y, bbox)

        if best_choice is None:
            continue
        _, best_x, best_y, final_bbox = best_choice
        final_text = ax.text(
            best_x,
            best_y,
            label_text,
            ha="left" if visual_side == "left" else "right",
            va="bottom",
            color=color,
            fontsize=fontsize,
            clip_on=True,
            transform=ax.transData,
        )
        fig.canvas.draw()
        placed_bboxes.append(final_text.get_window_extent(renderer=renderer).expanded(1.02, 1.06))


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
    inset_fraction: float = INSIDE_LEGEND_INSET_FRACTION,
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
    left_margin_mm: float = LEFT_MARGIN_MM,
    right_margin_mm: float = RIGHT_MARGIN_MM,
    bottom_margin_mm: float = BOTTOM_MARGIN_MM,
    top_margin_mm: float = TOP_MARGIN_MM,
    xlim: tuple[float | None, float | None] | None = None,
    ylim: tuple[float | None, float | None] | None = None,
    headroom_factor: float | None = None,
    y_padding_top: float = 0.18,
    y_padding_bottom: float = 0.06,
    show_markers: bool = True,
    marker_style_cycle: Sequence[str] | None = None,
    marker_size: float = 3.0,
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
    legend_inset_fraction: float = INSIDE_LEGEND_INSET_FRACTION,
) -> tuple[plt.Figure, plt.Axes]:
    _validate_curve_series_input(series_list)
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
    normalized_series = _baseline_correct_series(series_list, baseline_mode=baseline_mode)
    stacked_layout = (
        _prepare_stacked_layout(
            normalized_series,
            stack_floor_fraction=stack_floor_fraction,
            stack_gap_fraction=stack_gap_fraction,
        )
        if stack_mode != "none" and len(series_list) > 1
        else None
    )
    plotted_series = stacked_layout.series_list if stacked_layout is not None else normalized_series

    for idx, (color, series) in enumerate(zip(palette, plotted_series)):
        markevery = marker_every if marker_every is not None else _infer_markevery(len(series.data))
        line_color = to_rgba(color, LINE_ALPHA)
        ax.plot(
            series.data["x"],
            series.data["y"],
            label=series.sample,
            color=line_color,
            linewidth=LINE_WIDTH_PT,
            marker=markers[idx % len(markers)] if show_markers else None,
            markersize=marker_size,
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
    if yscale == "log":
        ax.yaxis.set_major_locator(LogLocator(base=10, subs=(1.0,), numticks=12))
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
        _place_series_edge_labels(
            ax,
            plotted_series,
            palette,
            reverse_x=reverse_x,
            side=series_label_side,
            inset_fraction=label_track_inset_fraction,
            label_offset_pt=label_offset_pt,
        )
    elif legend_mode == "inside_best":
        legend_kwargs, overlap_score = choose_legend_corner(
            ax,
            plotted_series,
            inset_fraction=legend_inset_fraction,
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
            inset_fraction=legend_inset_fraction,
        )
        ax.legend(**legend_kwargs)
    elif legend_mode != "none":
        ax.legend(**_legend_kwargs(legend_mode))

    if visible_xticks is not None:
        ax.xaxis.set_major_locator(FixedLocator(np.asarray(visible_xticks, dtype=float)))
    elif not _override_complete(xlim):
        _apply_axis_tick_filter(
            ax.xaxis,
            raw_bounds=limits.raw_xlim,
            display_bounds=ax.get_xlim(),
            scale=xscale,
        )
    if show_y_ticks:
        _apply_visible_y_tick_policy(
            ax,
            scale=yscale,
            raw_bounds=None if _override_complete(ylim) else limits.raw_ylim,
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
    left_margin_mm: float = LEFT_MARGIN_MM,
    right_margin_mm: float = RIGHT_MARGIN_MM,
    bottom_margin_mm: float = BOTTOM_MARGIN_MM,
    top_margin_mm: float = TOP_MARGIN_MM,
    xlim: tuple[float | None, float | None] | None = None,
    ylim: tuple[float | None, float | None] | None = None,
    headroom_factor: float | None = None,
    y_padding_top: float = 0.12,
    y_padding_bottom: float = 0.06,
    marker_size: float = 14.0,
    visible_xticks: Sequence[float] | None = None,
    reverse_x: bool = False,
    legend_expand_axes: str = "xy",
    legend_inset_fraction: float = INSIDE_LEGEND_INSET_FRACTION,
) -> tuple[plt.Figure, plt.Axes]:
    _validate_curve_series_input(series_list)
    fig, ax = create_panel_figure(
        width_mm=width_mm or PANEL_WIDTH_MM,
        height_mm=height_mm or PANEL_HEIGHT_MM,
        left_margin_mm=left_margin_mm,
        right_margin_mm=right_margin_mm,
        bottom_margin_mm=bottom_margin_mm,
        top_margin_mm=top_margin_mm,
    )
    palette = sns.color_palette("colorblind", n_colors=len(series_list))

    for color, series in zip(palette, series_list):
        ax.scatter(
            series.data["x"],
            series.data["y"],
            label=series.sample,
            color=color,
            s=marker_size,
            alpha=MARKER_ALPHA,
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
    if yscale == "log":
        ax.yaxis.set_major_locator(LogLocator(base=10, subs=(1.0,), numticks=12))
    if reverse_x:
        ax.invert_xaxis()

    first = series_list[0]
    ax.set_xlabel(_format_axis_label(first.x_label, first.x_unit))
    ax.set_ylabel(_format_axis_label(first.y_label, first.y_unit))

    if legend_mode == "inside_best":
        legend_kwargs, overlap_score = choose_legend_corner(
            ax,
            series_list,
            inset_fraction=legend_inset_fraction,
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
            inset_fraction=legend_inset_fraction,
        )
        ax.legend(**legend_kwargs)
    elif legend_mode != "none":
        ax.legend(**_legend_kwargs(legend_mode))

    if visible_xticks is not None:
        ax.xaxis.set_major_locator(FixedLocator(np.asarray(visible_xticks, dtype=float)))
    elif not _override_complete(xlim):
        _apply_axis_tick_filter(
            ax.xaxis,
            raw_bounds=limits.raw_xlim,
            display_bounds=ax.get_xlim(),
            scale=xscale,
        )
    _apply_visible_y_tick_policy(
        ax,
        scale=yscale,
        raw_bounds=None if _override_complete(ylim) else limits.raw_ylim,
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
    return plot_curves(series_list, **params)


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


def _clone_with_sample_name(series: CurveSeries, sample_name: str) -> CurveSeries:
    return CurveSeries(
        sample=sample_name,
        x_label=series.x_label,
        y_label=series.y_label,
        x_unit=series.x_unit,
        y_unit=series.y_unit,
        data=series.data.copy(),
    )


def _prepare_wide_nmr_series(
    series_list: Sequence[CurveSeries],
    config: WideNMRConfig,
) -> tuple[list[str], list[str], list[CurveSeries]]:
    by_sample = {series.sample: series for series in series_list}
    ordered_keys: list[str] = []
    if config.series_order:
        for key in config.series_order:
            if key not in by_sample:
                raise ValueError(f"wide_nmr config references unknown sample {key!r}.")
            ordered_keys.append(key)
    for series in series_list:
        if series.sample not in ordered_keys:
            ordered_keys.append(series.sample)

    display_names = [config.series_labels.get(key, key) for key in ordered_keys]
    ordered_series = [_clone_with_sample_name(by_sample[key], display_name) for key, display_name in zip(ordered_keys, display_names)]
    return ordered_keys, display_names, ordered_series


def _wide_nmr_segment_width_ratios(segments: Sequence[WideNMRSegment]) -> list[float]:
    ratios: list[float] = []
    for segment in segments:
        if segment.width_ratio is not None:
            ratios.append(float(segment.width_ratio))
        else:
            ratios.append(max(abs(segment.x_max - segment.x_min), 0.1))
    return ratios


def _wide_nmr_local_edge_score(
    series_list: Sequence[CurveSeries],
    segment: WideNMRSegment,
    *,
    side: str,
    inset_fraction: float,
) -> float:
    score = 0.0
    seg_low = min(segment.x_min, segment.x_max)
    seg_high = max(segment.x_min, segment.x_max)
    seg_span = max(seg_high - seg_low, 1e-9)
    target_x = segment.x_max - seg_span * inset_fraction if side == "left" else segment.x_min + seg_span * inset_fraction
    window = max(seg_span * 0.08, 1e-9)

    for series in series_list:
        x = series.data["x"].to_numpy(dtype=float)
        y = series.data["y"].to_numpy(dtype=float)
        valid = np.isfinite(x) & np.isfinite(y) & (x >= seg_low) & (x <= seg_high)
        if valid.sum() < 4:
            continue
        local_x = x[valid]
        local_y = y[valid]
        mask = np.abs(local_x - target_x) <= window
        if mask.sum() < 4:
            idx = int(np.argmin(np.abs(local_x - target_x)))
            lo = max(0, idx - 2)
            hi = min(len(local_x), idx + 3)
            sample_y = local_y[lo:hi]
        else:
            sample_y = local_y[mask]
        if len(sample_y) < 2:
            continue
        score += _robust_span(sample_y)
        score += abs(float(sample_y[-1] - sample_y[0])) * 0.35
        score += float(np.mean(np.abs(np.diff(sample_y)))) * 0.45
    return score


def _resolve_wide_nmr_label_side(
    series_list: Sequence[CurveSeries],
    config: WideNMRConfig,
) -> str:
    if config.label_side in {"left", "right"}:
        return config.label_side
    left_score = _wide_nmr_local_edge_score(
        series_list,
        config.segments[0],
        side="left",
        inset_fraction=config.label_inset_fraction,
    )
    right_score = _wide_nmr_local_edge_score(
        series_list,
        config.segments[-1],
        side="right",
        inset_fraction=config.label_inset_fraction,
    )
    if np.isclose(left_score, right_score):
        return "left"
    return "left" if left_score < right_score else "right"


def _pick_segment_axis_for_region(
    axes: Sequence[plt.Axes],
    segments: Sequence[WideNMRSegment],
    region: WideNMRHighlightRegion,
) -> tuple[plt.Axes, WideNMRSegment]:
    region_mid = (region.x_min + region.x_max) / 2
    for axis, segment in zip(axes, segments):
        seg_low = min(segment.x_min, segment.x_max)
        seg_high = max(segment.x_min, segment.x_max)
        if seg_low <= region_mid <= seg_high:
            return axis, segment
    best_idx = 0
    best_overlap = -1.0
    region_low = min(region.x_min, region.x_max)
    region_high = max(region.x_min, region.x_max)
    for idx, segment in enumerate(segments):
        seg_low = min(segment.x_min, segment.x_max)
        seg_high = max(segment.x_min, segment.x_max)
        overlap = max(0.0, min(seg_high, region_high) - max(seg_low, region_low))
        if overlap > best_overlap:
            best_idx = idx
            best_overlap = overlap
    return axes[best_idx], segments[best_idx]


def _wide_nmr_region_matches_series(
    region: WideNMRHighlightRegion,
    raw_name: str,
    display_name: str,
) -> bool:
    if not region.series:
        return True
    return raw_name in region.series or display_name in region.series


def _add_wide_nmr_highlights(
    axes: Sequence[plt.Axes],
    segments: Sequence[WideNMRSegment],
    layout: StackedLayout,
    raw_names: Sequence[str],
    display_names: Sequence[str],
    config: WideNMRConfig,
) -> None:
    for region in config.highlight_regions:
        label_axis, _ = _pick_segment_axis_for_region(axes, segments, region)
        region_label_drawn = False
        for axis, segment in zip(axes, segments):
            seg_low = min(segment.x_min, segment.x_max)
            seg_high = max(segment.x_min, segment.x_max)
            overlap_low = max(seg_low, min(region.x_min, region.x_max))
            overlap_high = min(seg_high, max(region.x_min, region.x_max))
            if overlap_high <= overlap_low:
                continue

            y_lows: list[float] = []
            y_highs: list[float] = []
            for raw_name, display_name, series in zip(raw_names, display_names, layout.series_list):
                if not _wide_nmr_region_matches_series(region, raw_name, display_name):
                    continue
                x = series.data["x"].to_numpy(dtype=float)
                y = series.data["y"].to_numpy(dtype=float)
                mask = np.isfinite(x) & np.isfinite(y) & (x >= overlap_low) & (x <= overlap_high)
                if mask.sum() == 0:
                    continue
                local_y = y[mask]
                y_low = float(np.min(local_y) - layout.step * 0.08)
                y_high = float(np.max(local_y) + layout.step * 0.08)
                axis.add_patch(
                    Rectangle(
                        (overlap_low, y_low),
                        overlap_high - overlap_low,
                        y_high - y_low,
                        facecolor=region.color,
                        edgecolor="none",
                        alpha=min(region.alpha, MAX_FILL_ALPHA),
                        zorder=0.2,
                    )
                )
                y_lows.append(y_low)
                y_highs.append(y_high)

            if region.label and y_lows and axis is label_axis and not region_label_drawn:
                region_mid = (overlap_low + overlap_high) / 2
                if region.label_position == "bottom":
                    label_y = min(y_lows) - layout.step * 0.04
                    va = "top"
                else:
                    label_y = max(y_highs) + layout.step * 0.04
                    va = "bottom"
                axis.text(
                    region_mid,
                    label_y,
                    region.label,
                    color=region.color,
                    ha="center",
                    va=va,
                    fontsize=7,
                    clip_on=False,
                    zorder=3,
                )
                region_label_drawn = True


def _draw_wide_nmr_break_marks(left_ax: plt.Axes, right_ax: plt.Axes) -> None:
    d = 0.015
    kwargs_left = dict(transform=left_ax.transAxes, color="black", clip_on=False, linewidth=1.0)
    kwargs_right = dict(transform=right_ax.transAxes, color="black", clip_on=False, linewidth=1.0)
    left_ax.plot((1 - d, 1 + d), (-d, +d), **kwargs_left)
    left_ax.plot((1 - d, 1 + d), (-3 * d, -d), **kwargs_left)
    right_ax.plot((-d, +d), (-d, +d), **kwargs_right)
    right_ax.plot((-d, +d), (-3 * d, -d), **kwargs_right)


def plot_wide_nmr(
    series_list: Sequence[CurveSeries],
    config: WideNMRConfig,
    *,
    width_mm: float = WIDE_NMR_WIDTH_MM,
    height_mm: float = WIDE_NMR_TOTAL_HEIGHT_MM,
    left_margin_mm: float = LEFT_MARGIN_MM,
    right_margin_mm: float = RIGHT_MARGIN_MM,
    bottom_margin_mm: float = BOTTOM_MARGIN_MM,
    top_margin_mm: float = 0.0,
    structure_reserved_mm: float = WIDE_NMR_STRUCTURE_RESERVED_MM,
    reverse_x: bool = True,
    baseline_mode: str = "linear_endpoints",
) -> tuple[plt.Figure, plt.Axes]:
    raw_names, display_names, ordered_series = _prepare_wide_nmr_series(series_list, config)
    corrected_series = _baseline_correct_series(ordered_series, baseline_mode=baseline_mode)
    stacked_layout = _prepare_stacked_layout(
        corrected_series,
        stack_floor_fraction=config.stack_floor_fraction,
        stack_gap_fraction=config.stack_gap_fraction,
    )
    y_arrays = [series.data["y"].to_numpy(dtype=float) for series in stacked_layout.series_list]
    y_max = max(float(np.nanmax(values)) for values in y_arrays)
    y_high = y_max + stacked_layout.max_span * 0.18

    fig = plt.figure(figsize=(mm_to_inch(width_mm), mm_to_inch(height_mm)), constrained_layout=False)
    reserved_top_mm = structure_reserved_mm + top_margin_mm
    plot_body_height_mm = max(height_mm - bottom_margin_mm - reserved_top_mm, 1e-9)
    root_grid = fig.add_gridspec(
        2,
        1,
        left=left_margin_mm / width_mm,
        right=1 - right_margin_mm / width_mm,
        bottom=bottom_margin_mm / height_mm,
        top=1.0,
        height_ratios=[reserved_top_mm, plot_body_height_mm],
        hspace=0.0,
    )
    spectrum_grid = root_grid[1].subgridspec(
        1,
        len(config.segments),
        width_ratios=_wide_nmr_segment_width_ratios(config.segments),
        wspace=config.segment_gap,
    )

    axes: list[plt.Axes] = []
    for idx, segment in enumerate(config.segments):
        axis = fig.add_subplot(spectrum_grid[0, idx], sharey=axes[0] if axes else None)
        axes.append(axis)
        for series in stacked_layout.series_list:
            axis.plot(
                series.data["x"],
                series.data["y"],
                color="black",
                linewidth=LINE_WIDTH_PT,
                zorder=2,
            )

        if reverse_x:
            axis.set_xlim(segment.x_max, segment.x_min)
        else:
            axis.set_xlim(segment.x_min, segment.x_max)
        axis.set_ylim(0.0, y_high)
        axis.tick_params(axis="y", left=False, labelleft=False, which="both")
        axis.spines["left"].set_visible(False)
        axis.spines["top"].set_visible(False)
        axis.spines["right"].set_visible(False)
        seg_low = min(segment.x_min, segment.x_max)
        seg_high = max(segment.x_min, segment.x_max)
        _apply_axis_tick_filter(
            axis.xaxis,
            raw_bounds=(seg_low, seg_high),
            display_bounds=(seg_low, seg_high),
            scale="linear",
            include_minor=False,
        )

    _add_wide_nmr_highlights(
        axes,
        config.segments,
        stacked_layout,
        raw_names,
        display_names,
        config,
    )

    label_side = _resolve_wide_nmr_label_side(stacked_layout.series_list, config)
    target_axis = axes[0] if label_side == "left" else axes[-1]
    _place_series_edge_labels(
        target_axis,
        stacked_layout.series_list,
        ["black"] * len(stacked_layout.series_list),
        reverse_x=reverse_x,
        side=label_side,
        inset_fraction=config.label_inset_fraction,
        label_offset_pt=config.label_offset_pt,
        labels=display_names,
        search_band_fraction=0.08,
        fontsize=7.0,
    )

    for left_axis, right_axis in zip(axes[:-1], axes[1:]):
        _draw_wide_nmr_break_marks(left_axis, right_axis)

    first = series_list[0]
    fig.supxlabel(_format_axis_label(first.x_label, first.x_unit), x=0.985, ha="right")
    if config.panel_label:
        fig.text(0.01, 0.98, config.panel_label, ha="left", va="top", fontsize=10)

    return fig, axes[0]


def _compute_distribution_axis_limits(
    values: Sequence[np.ndarray] | Sequence[Sequence[float]],
    *,
    legend_mode: LegendMode,
    headroom_factor: float | None,
    y_padding_top: float,
    y_padding_bottom: float,
) -> AxisLimits:
    return compute_axis_limits(
        values,
        kind="box",
        axis_mode="auto",
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
    width_mm: float = PANEL_WIDTH_MM,
    height_mm: float = PANEL_HEIGHT_MM,
    left_margin_mm: float = LEFT_MARGIN_MM,
    right_margin_mm: float = RIGHT_MARGIN_MM,
    bottom_margin_mm: float = BOTTOM_MARGIN_MM,
    top_margin_mm: float = TOP_MARGIN_MM,
    box_width: float = 0.35,
    spacing_scale: float = 1.0,
    ylim: tuple[float, float] | None = None,
    headroom_factor: float | None = None,
    y_padding_top: float = 0.12,
    y_padding_bottom: float = 0.06,
) -> tuple[plt.Figure, plt.Axes]:
    _validate_group_input(groups, chart_name="box plot")
    fig, ax = create_panel_figure(
        width_mm=width_mm,
        height_mm=height_mm,
        left_margin_mm=left_margin_mm,
        right_margin_mm=right_margin_mm,
        bottom_margin_mm=bottom_margin_mm,
        top_margin_mm=top_margin_mm,
    )
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

    limits = _compute_distribution_axis_limits(
        values,
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
    _apply_visible_y_tick_policy(ax, scale="linear", raw_bounds=limits.raw_ylim)

    first = groups[0]
    ax.set_ylabel(_format_axis_label(first.value_label, first.value_unit))
    return fig, ax


def plot_bar(
    groups: Sequence[ReplicateGroup],
    *,
    legend_mode: LegendMode = "outside",
    axis_mode: AxisMode = "auto_positive",
    width_mm: float = PANEL_WIDTH_MM,
    height_mm: float = PANEL_HEIGHT_MM,
    left_margin_mm: float = LEFT_MARGIN_MM,
    right_margin_mm: float = RIGHT_MARGIN_MM,
    bottom_margin_mm: float = BOTTOM_MARGIN_MM,
    top_margin_mm: float = TOP_MARGIN_MM,
    bar_width: float = 0.35,
    spacing_scale: float = 1.0,
    ylim: tuple[float, float] | None = None,
    headroom_factor: float | None = None,
    y_padding_top: float = 0.15,
    y_padding_bottom: float = 0.02,
) -> tuple[plt.Figure, plt.Axes]:
    _validate_group_input(groups, chart_name="bar plot")
    fig, ax = create_panel_figure(
        width_mm=width_mm,
        height_mm=height_mm,
        left_margin_mm=left_margin_mm,
        right_margin_mm=right_margin_mm,
        bottom_margin_mm=bottom_margin_mm,
        top_margin_mm=top_margin_mm,
    )
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
    _style_categorical_ticklabels(ax, [group.group for group in groups])
    if len(positions):
        side_padding = max(0.28, bar_width * 0.9)
        ax.set_xlim(positions[0] - side_padding, positions[-1] + side_padding)
    tick_bounds = None
    if limits.raw_ylim is not None:
        tick_bounds = (0.0, limits.raw_ylim[1])
    _apply_visible_y_tick_policy(ax, scale="linear", raw_bounds=tick_bounds)

    first = groups[0]
    ax.set_ylabel(_format_axis_label(first.value_label, first.value_unit))
    return fig, ax


def plot_violin(
    groups: Sequence[ReplicateGroup],
    *,
    legend_mode: LegendMode = "outside",
    axis_mode: AxisMode = "auto",
    width_mm: float = PANEL_WIDTH_MM,
    height_mm: float = PANEL_HEIGHT_MM,
    left_margin_mm: float = LEFT_MARGIN_MM,
    right_margin_mm: float = RIGHT_MARGIN_MM,
    bottom_margin_mm: float = BOTTOM_MARGIN_MM,
    top_margin_mm: float = TOP_MARGIN_MM,
    violin_width: float = 0.42,
    spacing_scale: float = 1.0,
    ylim: tuple[float, float] | None = None,
    headroom_factor: float | None = None,
    y_padding_top: float = 0.12,
    y_padding_bottom: float = 0.06,
) -> tuple[plt.Figure, plt.Axes]:
    _validate_group_input(groups, chart_name="violin plot")
    fig, ax = create_panel_figure(
        width_mm=width_mm,
        height_mm=height_mm,
        left_margin_mm=left_margin_mm,
        right_margin_mm=right_margin_mm,
        bottom_margin_mm=bottom_margin_mm,
        top_margin_mm=top_margin_mm,
    )
    palette = sns.color_palette("colorblind", n_colors=len(groups))
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
    for body, color in zip(violin["bodies"], palette):
        body.set_facecolor(color)
        body.set_edgecolor(color)
        body.set_alpha(min(FILL_ALPHA, MAX_FILL_ALPHA))
        body.set_linewidth(1.0)
    if "cmedians" in violin:
        violin["cmedians"].set_color("black")
        violin["cmedians"].set_linewidth(LINE_WIDTH_PT)

    limits = _compute_distribution_axis_limits(
        values,
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
    _apply_visible_y_tick_policy(ax, scale="linear", raw_bounds=limits.raw_ylim)

    first = groups[0]
    ax.set_ylabel(_format_axis_label(first.value_label, first.value_unit))
    return fig, ax


def plot_heatmap(
    table: HeatmapTable,
    *,
    width_mm: float = PANEL_WIDTH_MM,
    height_mm: float = PANEL_HEIGHT_MM,
    left_margin_mm: float = LEFT_MARGIN_MM,
    right_margin_mm: float = RIGHT_MARGIN_MM,
    bottom_margin_mm: float = BOTTOM_MARGIN_MM,
    top_margin_mm: float = TOP_MARGIN_MM,
    show_colorbar: bool = True,
) -> tuple[plt.Figure, plt.Axes]:
    fig, ax = create_panel_figure(
        width_mm=width_mm,
        height_mm=height_mm,
        left_margin_mm=left_margin_mm,
        right_margin_mm=right_margin_mm,
        bottom_margin_mm=bottom_margin_mm,
        top_margin_mm=top_margin_mm,
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

    matrix = (
        table.data
        .pivot(index="y", columns="x", values="z")
        .reindex(index=y_order, columns=x_order)
    )

    heatmap = sns.heatmap(
        matrix,
        ax=ax,
        cmap="crest",
        cbar=show_colorbar,
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

    if show_colorbar and heatmap.collections:
        colorbar = heatmap.collections[0].colorbar
        if colorbar is not None:
            colorbar.set_label(_format_axis_label(table.z_label, table.z_unit), fontsize=FONT_SIZE_PT)
            colorbar.ax.tick_params(labelsize=6)
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
