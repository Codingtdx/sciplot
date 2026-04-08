from __future__ import annotations

import textwrap
from collections.abc import Sequence
from dataclasses import dataclass

import matplotlib.pyplot as plt
import numpy as np
from matplotlib import transforms
from matplotlib.ticker import FixedLocator

from src import mpl_backend, plot_style  # noqa: F401
from src.data_loader import ReplicateGroup
from src.plot_contract import load_plot_contract
from src.text_normalization import _clean_text, canonicalize_token, normalize_label, normalize_unit

LegendMode = str

AxisMode = str

MAX_VISIBLE_Y_MAJOR_TICKS = 7

_PLOT_CONTRACT = load_plot_contract()

_HEATMAP_LAYOUT = _PLOT_CONTRACT.special_layouts["heatmap"]

_AXIS_POLICY = _PLOT_CONTRACT.axis_policy

_LINEAR_NICE_STEPS = tuple(float(value) for value in _AXIS_POLICY.linear_nice_steps)

_LOG_DISPLAY_STEPS = tuple(float(value) for value in _AXIS_POLICY.log_display_steps)

_LINEAR_OUTER_PADDING_FRACTION = float(_AXIS_POLICY.linear_outer_padding_fraction)

_FORCE_VISIBLE_LABELED_ENDPOINTS = bool(_AXIS_POLICY.linear_force_visible_labeled_endpoints)

_BAR_ZERO_BASELINE_NO_LOWER_PADDING = bool(_AXIS_POLICY.bar_zero_baseline_no_lower_padding)

_TENSILE_Y_INCLUDE_ZERO = bool(_AXIS_POLICY.tensile_y_include_zero)

_STACKED_X_USE_STANDARD_ENDPOINT_POLICY = bool(_AXIS_POLICY.stacked_x_use_standard_endpoint_policy)

@dataclass
class AxisLimits:
    xlim: tuple[float, float]
    ylim: tuple[float, float]
    raw_xlim: tuple[float, float] | None = None
    raw_ylim: tuple[float, float] | None = None
    x_tick_policy: AxisTickPolicy | None = None
    y_tick_policy: AxisTickPolicy | None = None

@dataclass(frozen=True)
class AxisTickPolicy:
    display_bounds: tuple[float, float]
    labeled_bounds: tuple[float, float]
    major_ticks: tuple[float, ...]

@dataclass(frozen=True)
class SharedAxisLayout:
    display_bounds: tuple[float, float]
    labeled_bounds: tuple[float, float]
    raw_bounds: tuple[float, float]
    visible_ticks: tuple[float, ...]

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

def _resolved_panel_geometry(
    *,
    width_mm: float | None,
    height_mm: float | None,
    left_margin_mm: float | None,
    right_margin_mm: float | None,
    bottom_margin_mm: float | None,
    top_margin_mm: float | None,
) -> tuple[float, float, float | None, float | None, float | None, float | None]:
    spacing = plot_style.current_spacing()
    return (
        spacing.panel_width_mm if width_mm is None else width_mm,
        spacing.panel_height_mm if height_mm is None else height_mm,
        spacing.left_margin_mm if left_margin_mm is None else left_margin_mm,
        spacing.right_margin_mm if right_margin_mm is None else right_margin_mm,
        spacing.bottom_margin_mm if bottom_margin_mm is None else bottom_margin_mm,
        spacing.top_margin_mm if top_margin_mm is None else top_margin_mm,
    )

def _format_axis_label(
    label: str,
    unit: str,
    *,
    preserve_stress_label: bool = False,
    override_label: str | None = None,
) -> str:
    display_label = _clean_text(override_label) if override_label else normalize_label(label)
    if preserve_stress_label and canonicalize_token(display_label) in {"σ", "sigma"}:
        display_label = "Stress"
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

def _nice_step_ge(value: float) -> float:
    if not np.isfinite(value) or value <= 0:
        return 1.0
    exponent = float(np.floor(np.log10(value)))
    base = 10 ** exponent
    scaled = value / base
    for step in _LINEAR_NICE_STEPS:
        if scaled <= step:
            return float(step * base)
    return float(10.0 * base)

def _linear_target_major_step(span: float) -> float:
    baseline = span if span > 0 else 1.0
    return _nice_step_ge(baseline / 5.0)

def _build_linear_ticks(labeled_min: float, labeled_max: float, step: float) -> tuple[float, ...]:
    tick_count = int(np.floor((labeled_max - labeled_min) / step)) + 1
    ticks = labeled_min + np.arange(max(tick_count, 1), dtype=float) * step
    ticks = ticks[np.isfinite(ticks)]
    if ticks.size == 0:
        ticks = np.asarray([labeled_min, labeled_max], dtype=float)
    if not np.isclose(ticks[0], labeled_min):
        ticks = np.concatenate(([labeled_min], ticks))
    if not np.isclose(ticks[-1], labeled_max):
        ticks = np.concatenate((ticks, [labeled_max]))
    return tuple(float(tick) for tick in np.unique(np.round(ticks, decimals=12)))

def _solve_linear_axis_policy(
    data_min: float,
    data_max: float,
    *,
    force_zero_min: bool = False,
    lower_display_padding_fraction: float | None = _LINEAR_OUTER_PADDING_FRACTION,
    upper_display_padding_fraction: float | None = _LINEAR_OUTER_PADDING_FRACTION,
) -> AxisTickPolicy:
    effective_min = float(data_min)
    effective_max = float(data_max)
    if force_zero_min and effective_min >= 0:
        effective_min = 0.0

    if np.isclose(effective_min, effective_max):
        baseline = max(abs(effective_min), abs(effective_max), 1.0)
        step = _nice_step_ge(baseline)
        labeled_min = effective_min - step
        labeled_max = effective_max + step
        if force_zero_min and data_min >= 0:
            labeled_min = 0.0
    else:
        step = _linear_target_major_step(effective_max - effective_min)
        labeled_min = np.floor(effective_min / step) * step
        labeled_max = np.ceil(effective_max / step) * step
        if force_zero_min and data_min >= 0:
            labeled_min = 0.0
        if np.isclose(labeled_min, labeled_max):
            labeled_max = labeled_min + step

    labeled_span = float(labeled_max - labeled_min)
    if labeled_span <= 0:
        labeled_span = max(abs(labeled_max), 1.0)
    lower_padding = labeled_span * float(lower_display_padding_fraction or 0.0)
    upper_padding = labeled_span * float(upper_display_padding_fraction or 0.0)
    display_min = float(labeled_min - lower_padding)
    display_max = float(labeled_max + upper_padding)
    return AxisTickPolicy(
        display_bounds=(display_min, display_max),
        labeled_bounds=(float(labeled_min), float(labeled_max)),
        major_ticks=_build_linear_ticks(float(labeled_min), float(labeled_max), float(step)),
    )

def _snap_log_display_bound(value: float, *, direction: str) -> float:
    if not np.isfinite(value) or value <= 0:
        raise ValueError("Log-scale display bounds require strictly positive values.")
    exponent = int(np.floor(np.log10(value)))
    base = 10**exponent
    scaled = value / base

    if direction == "upper":
        for step in _LOG_DISPLAY_STEPS:
            if scaled <= step:
                return float(step * base)
        return float(10.0 * base)

    for step in reversed(_LOG_DISPLAY_STEPS):
        if scaled >= step:
            return float(step * base)
    return float(_LOG_DISPLAY_STEPS[-1] * (10 ** (exponent - 1)))

def _build_decade_ticks(display_min: float, display_max: float) -> tuple[float, ...]:
    low_exp = int(np.ceil(np.log10(display_min)))
    high_exp = int(np.floor(np.log10(display_max)))
    if high_exp < low_exp:
        candidate = 10 ** round((np.log10(display_min) + np.log10(display_max)) / 2.0)
        return (float(candidate),)
    ticks = tuple(float(10**exponent) for exponent in range(low_exp, high_exp + 1))
    return ticks

def _solve_log_axis_policy(
    data_min: float,
    data_max: float,
    *,
    lower_padding: float,
    upper_padding: float,
) -> AxisTickPolicy:
    padded_min, padded_max = _pad_limits_log_curve(
        data_min,
        data_max,
        lower_padding=lower_padding,
        upper_padding=upper_padding,
    )
    display_min = _snap_log_display_bound(padded_min, direction="lower")
    display_max = _snap_log_display_bound(padded_max, direction="upper")
    major_ticks = _build_decade_ticks(data_min, data_max)
    return AxisTickPolicy(
        display_bounds=(display_min, display_max),
        labeled_bounds=(float(major_ticks[0]), float(major_ticks[-1])),
        major_ticks=major_ticks,
    )

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
    """Compute display bounds and tick policies for standard numeric axes."""
    y_arrays = _validate_scale_values(values, scale=yscale, axis_name="Y")

    y_min = min(float(arr.min()) for arr in y_arrays)
    y_max = max(float(arr.max()) for arr in y_arrays)
    effective_y_max = y_max
    if headroom_factor is not None and y_max > 0 and yscale == "linear":
        effective_y_max = max(y_max, y_max * headroom_factor)

    if yscale == "log":
        y_policy = _solve_log_axis_policy(
            y_min,
            effective_y_max,
            lower_padding=max(y_padding_bottom, _LINEAR_OUTER_PADDING_FRACTION),
            upper_padding=max(y_padding_top, _LINEAR_OUTER_PADDING_FRACTION),
        )
    else:
        is_bar = kind == "bar" and axis_mode != "manual" and y_min >= 0 and _BAR_ZERO_BASELINE_NO_LOWER_PADDING
        force_zero_min = axis_mode == "auto_positive" and y_min >= 0
        if is_bar:
            y_policy = _solve_linear_axis_policy(
                0.0,
                effective_y_max,
                force_zero_min=True,
                lower_display_padding_fraction=0.0,
                upper_display_padding_fraction=0.0,
            )
        else:
            y_policy = _solve_linear_axis_policy(
                y_min,
                effective_y_max,
                force_zero_min=force_zero_min,
                lower_display_padding_fraction=_LINEAR_OUTER_PADDING_FRACTION,
                upper_display_padding_fraction=_LINEAR_OUTER_PADDING_FRACTION,
            )

    if x_values is None:
        return AxisLimits(
            xlim=(0.0, 1.0),
            ylim=y_policy.display_bounds,
            raw_ylim=(y_min, y_max),
            y_tick_policy=y_policy,
        )

    x_arrays = _validate_scale_values(x_values, scale=xscale, axis_name="X")

    x_min = min(float(arr.min()) for arr in x_arrays)
    x_max = max(float(arr.max()) for arr in x_arrays)
    if xscale == "log":
        x_policy = _solve_log_axis_policy(
            x_min,
            x_max,
            lower_padding=max(x_padding, _LINEAR_OUTER_PADDING_FRACTION),
            upper_padding=max(x_padding, _LINEAR_OUTER_PADDING_FRACTION),
        )
    else:
        x_policy = _solve_linear_axis_policy(
            x_min,
            x_max,
            lower_display_padding_fraction=_LINEAR_OUTER_PADDING_FRACTION,
            upper_display_padding_fraction=_LINEAR_OUTER_PADDING_FRACTION,
        )
    return AxisLimits(
        xlim=x_policy.display_bounds,
        ylim=y_policy.display_bounds,
        raw_xlim=(x_min, x_max),
        raw_ylim=(y_min, y_max),
        x_tick_policy=x_policy,
        y_tick_policy=y_policy,
    )

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
    fontsize = plot_style.current_typography().font_size_pt
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
    if ticks.size <= max_major_ticks:
        return ticks
    if ticks.size <= 2:
        return ticks
    first = ticks[0]
    last = ticks[-1]
    middle = ticks[1:-1]
    keep_middle = max(max_major_ticks - 2, 0)
    if keep_middle <= 0:
        return np.asarray([first, last], dtype=float)
    step = max(int(np.ceil(middle.size / keep_middle)), 1)
    trimmed = middle[::step][:keep_middle]
    return np.concatenate(([first], trimmed, [last]))

def _validate_group_input(groups: Sequence[ReplicateGroup], *, chart_name: str) -> None:
    if not groups:
        raise ValueError(f"No replicate groups were provided for {chart_name}.")
    for index, group in enumerate(groups, start=1):
        if group.data.empty:
            raise ValueError(f"{chart_name} group {index} ({group.group!r}) does not contain any replicate values.")

def _set_axis_locator_from_filtered_ticks(axis, ticks: np.ndarray, *, which: str) -> None:
    if ticks.size == 0:
        return
    locator = FixedLocator(ticks.tolist())
    if which == "major":
        axis.set_major_locator(locator)
    else:
        axis.set_minor_locator(locator)

def _apply_explicit_major_ticks(axis, ticks: Sequence[float], *, max_major_ticks: int | None = None) -> None:
    values = np.asarray(ticks, dtype=float)
    values = values[np.isfinite(values)]
    if values.size == 0:
        return
    if max_major_ticks is not None:
        values = _cap_visible_major_ticks(values, scale="linear", max_major_ticks=max_major_ticks)
    axis.set_major_locator(FixedLocator(values.tolist()))

def _resolved_major_ticks_with_override(
    *,
    policy_ticks: Sequence[float] | None,
    override: tuple[float | None, float | None] | None,
    scale: str,
    max_major_ticks: int | None = None,
) -> np.ndarray:
    values = (
        np.asarray(policy_ticks, dtype=float)
        if policy_ticks is not None
        else np.array([], dtype=float)
    )
    values = values[np.isfinite(values)]

    if scale == "linear" and override is not None:
        endpoint_candidates = np.asarray(
            [bound for bound in override if bound is not None and np.isfinite(bound)],
            dtype=float,
        )
        if endpoint_candidates.size:
            values = np.concatenate((values, endpoint_candidates))

    if values.size == 0:
        return values
    values = np.unique(np.round(values, decimals=12))
    if max_major_ticks is not None:
        values = _cap_visible_major_ticks(values, scale=scale, max_major_ticks=max_major_ticks)
    return values

def _apply_major_ticks_with_override(
    axis,
    *,
    policy_ticks: Sequence[float] | None,
    override: tuple[float | None, float | None] | None,
    scale: str,
    max_major_ticks: int | None = None,
) -> None:
    values = _resolved_major_ticks_with_override(
        policy_ticks=policy_ticks,
        override=override,
        scale=scale,
        max_major_ticks=max_major_ticks,
    )
    if values.size == 0:
        return
    axis.set_major_locator(FixedLocator(values.tolist()))

def _uses_positive_zero_origin(
    *,
    axis_mode: AxisMode,
    scale: str,
    raw_bounds: tuple[float, float] | None,
) -> bool:
    return (
        axis_mode == "auto_positive"
        and scale == "linear"
        and raw_bounds is not None
        and float(raw_bounds[0]) >= 0
    )

def _tick_bounds_with_zero_origin(
    raw_bounds: tuple[float, float] | None,
    *,
    axis_mode: AxisMode,
    scale: str,
) -> tuple[float, float] | None:
    if not _uses_positive_zero_origin(axis_mode=axis_mode, scale=scale, raw_bounds=raw_bounds):
        return raw_bounds
    assert raw_bounds is not None
    return (0.0, float(raw_bounds[1]))

def _pin_positive_zero_origin(
    ax: plt.Axes,
    *,
    axis_mode: AxisMode,
    scale: str,
    raw_bounds: tuple[float, float] | None,
) -> None:
    if not _uses_positive_zero_origin(axis_mode=axis_mode, scale=scale, raw_bounds=raw_bounds):
        return
    assert raw_bounds is not None
    y_low, y_high = ax.get_ylim()
    upper = max(float(raw_bounds[1]), float(max(y_low, y_high)))
    if y_low <= y_high:
        ax.set_ylim(0.0, upper)
    else:
        ax.set_ylim(upper, 0.0)

def _ensure_visible_linear_lower_tick(
    ax: plt.Axes,
    *,
    max_major_ticks: int = MAX_VISIBLE_Y_MAJOR_TICKS,
) -> None:
    y_low, y_high = ax.get_ylim()
    lower = float(min(y_low, y_high))
    upper = float(max(y_low, y_high))
    ticks = np.asarray(ax.get_yticks(), dtype=float)
    ticks = ticks[np.isfinite(ticks)]
    visible = ticks[(ticks >= lower) & (ticks <= upper)]
    if np.any(np.isclose(visible, lower)):
        return

    if visible.size == 0:
        combined = np.asarray([lower], dtype=float)
    else:
        combined = np.unique(np.concatenate(([lower], visible)))
        if combined.size > max_major_ticks:
            tail = combined[1:]
            keep_tail = max_major_ticks - 1
            if keep_tail <= 0:
                combined = np.asarray([lower], dtype=float)
            else:
                step = max(int(np.ceil(tail.size / keep_tail)), 1)
                tail = tail[::step][:keep_tail]
                combined = np.concatenate(([lower], tail))
    ax.yaxis.set_major_locator(FixedLocator(combined))

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
        bounds_for_ticks: tuple[float, float] = (
            (float(min(display_bounds)), float(max(display_bounds)))
            if scale == "log"
            else raw_bounds
        )
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

def _compute_heatmap_cax_geometry(
    position: transforms.Bbox,
    *,
    layout_overrides: dict[str, float] | None = None,
) -> tuple[list[float], list[float]]:
    layout = dict(_HEATMAP_LAYOUT)
    if layout_overrides:
        layout.update(layout_overrides)
    available_height = max(1.0 - position.y1, 1e-6)
    cbar_y0 = position.y1 + min(
        max(
            available_height * float(layout["colorbar_y_offset_fraction"]),
            float(layout["colorbar_y_offset_min"]),
        ),
        available_height * float(layout["colorbar_y_offset_max_fraction"]),
    )
    cbar_height = min(
        max(
            available_height * float(layout["colorbar_height_fraction"]),
            float(layout["colorbar_height_min"]),
        ),
        max(
            available_height
            - (cbar_y0 - position.y1)
            - float(layout["colorbar_bottom_gap"]),
            0.010,
        ),
    )
    cbar_x0 = position.x0 + position.width * float(layout["colorbar_x_offset_fraction"])
    cbar_width = position.width * float(layout["colorbar_width_fraction"])
    heatmap_rect = [position.x0, position.y0, position.width, position.height]
    cax_rect = [
        cbar_x0,
        cbar_y0,
        cbar_width,
        cbar_height,
    ]
    return heatmap_rect, cax_rect
