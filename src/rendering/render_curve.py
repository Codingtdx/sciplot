from __future__ import annotations

from dataclasses import replace
from pathlib import Path
from typing import cast

import matplotlib.pyplot as plt
import numpy as np

from src import plot_style
from src.plotting_curve_support import compute_shared_curve_x_layout
from src.plotting_families.curve_family import plot_curves, plot_scatter
from src.plotting_families.spectral_family import plot_wide_nmr
from src.plotting_primitives import _format_axis_label
from src.rendering.cache import load_curve_table_cached
from src.rendering.common import (
    aligned_replicate_band,
    load_rheology_bundle_series,
    load_segmented_config,
    looks_like_tensile_curve,
    manual_axis_overrides,
    merge_axis_override_bounds,
    rheology_output_filenames,
    validate_manual_axis_overrides,
    validate_series_scales,
)
from src.rendering.dataset_models import build_normalized_dataset
from src.rendering.models import RenderedPlot, RenderOptions, TemplateName
from src.rendering.qa import apply_curve_autofix
from src.rendering.render_curve_support import (
    _apply_compact_inside_legend,
    _compact_curve_fix,
    _curve_candidate_key,
    _curve_dense_fix,
    _ensure_direct_labels,
    _float_plot_kw,
    _merge_curve_fixes,
    _post_curve_fix,
    _prefer_compact_legend,
    _prefer_direct_labels,
)
from src.rendering.render_support import _rendered_plot_with_qa
from src.rendering.series_order import reorder_curve_series, unknown_series_order_labels


def _apply_curve_axis_labels(ax, first, options: RenderOptions, *, preserve_stress_label: bool) -> None:
    ax.set_xlabel(
        _format_axis_label(
            first.x_label,
            first.x_unit,
            override_label=options.x_label_override,
        )
    )
    ax.set_ylabel(
        _format_axis_label(
            first.y_label,
            first.y_unit,
            preserve_stress_label=preserve_stress_label,
            override_label=options.y_label_override,
        )
    )


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
            x_tick_density=options.x_tick_density,
            y_tick_density=options.y_tick_density,
            x_tick_edge_labels=options.x_tick_edge_labels,
            y_tick_edge_labels=options.y_tick_edge_labels,
            xlim=base_kwargs.get("xlim"),
            ylim=base_kwargs.get("ylim"),
            preserve_stress_label=bool(base_kwargs.get("preserve_stress_label", False)),
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
            _apply_compact_inside_legend(
                ax,
                series_count=len(series_list),
                preserve_stress_label=bool(base_kwargs.get("preserve_stress_label", False)),
            )
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
            preserve_stress_label=bool(base_kwargs.get("preserve_stress_label", False)),
            series_label_mode=(
                "edge"
                if direct_label_side is not None
                else str(base_kwargs.get("series_label_mode", "legend"))
            ),
            series_label_side=direct_label_side or str(base_kwargs.get("series_label_side", "auto")),
            visible_xticks=base_kwargs.get("visible_xticks"),
            x_tick_density=options.x_tick_density,
            y_tick_density=options.y_tick_density,
            x_tick_edge_labels=options.x_tick_edge_labels,
            y_tick_edge_labels=options.y_tick_edge_labels,
            xlim=base_kwargs.get("xlim"),
            ylim=base_kwargs.get("ylim"),
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
            _apply_compact_inside_legend(
                ax,
                series_count=len(series_list),
                preserve_stress_label=bool(base_kwargs.get("preserve_stress_label", False)),
            )
        applied = apply_curve_autofix(ax, _post_curve_fix(combined_fix, include_line_scale=show_markers))

    rendered = _rendered_plot_with_qa(
        filename=filename,
        figure=fig,
        template=template,
        options=options,
        autofixes_applied=tuple(dict.fromkeys([*autofixes, *applied])),
    )
    if rendered.figure.axes:
        _apply_curve_axis_labels(
            rendered.figure.axes[0],
            series_list[0],
            options,
            preserve_stress_label=bool(base_kwargs.get("preserve_stress_label", False)),
        )
    return rendered, strategy


def _with_manual_axis_overrides(
    base_kwargs: dict[str, object],
    options: RenderOptions,
) -> dict[str, object]:
    resolved = dict(base_kwargs)
    x_override, y_override = manual_axis_overrides(options)
    if x_override is not None:
        resolved["xlim"] = merge_axis_override_bounds(
            cast(tuple[float | None, float | None] | None, resolved.get("xlim")),
            x_override,
        )
        if "visible_xticks" in resolved:
            resolved["visible_xticks"] = None
    if y_override is not None:
        resolved["ylim"] = merge_axis_override_bounds(
            cast(tuple[float | None, float | None] | None, resolved.get("ylim")),
            y_override,
        )
    return resolved


def _ensure_known_series_order(series_list, series_order) -> None:
    unknown = unknown_series_order_labels([series.sample for series in series_list], series_order)
    if unknown:
        raise ValueError("series_order contains unknown series labels: " + ", ".join(unknown))


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
    resolved_kwargs = _with_manual_axis_overrides(dict(base_kwargs or {}), options)
    preserve_stress_label = bool(resolved_kwargs.get("preserve_stress_label", False))
    supports_direct_labels = not (preserve_stress_label and len(series_list) >= 4)
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
    if supports_direct_labels and _prefer_direct_labels(options, len(series_list)) and len(series_list) > 1:
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

def _render_rheology_bundle(
    bundle: str,
    template: TemplateName,
    input_path: Path,
    sheet: str | int,
    options: RenderOptions,
) -> list[RenderedPlot]:
    metric_series = load_rheology_bundle_series(bundle, input_path, sheet)
    validate_manual_axis_overrides(options, template=template)
    metric_series = {
        metric_name: reorder_curve_series(series_list, options.series_order)
        for metric_name, series_list in metric_series.items()
    }
    for series_list in metric_series.values():
        _ensure_known_series_order(series_list, options.series_order)
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
    series_list = reorder_curve_series(load_curve_table_cached(input_path, sheet), options.series_order)
    _ensure_known_series_order(series_list, options.series_order)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
    is_tensile_curve = looks_like_tensile_curve(series_list)
    validate_manual_axis_overrides(options, template="curve", is_tensile_curve=is_tensile_curve)
    axis_mode = "auto_positive" if is_tensile_curve else "auto"
    return [
        _render_curve_like_plot(
            filename=f"{input_path.stem}_curve.pdf",
            template="curve",
            series_list=series_list,
            options=options,
            show_markers=False,
            base_kwargs={
                "axis_mode": axis_mode,
                "preserve_stress_label": is_tensile_curve,
            },
        )
    ]

def _render_point_line(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    normalized_dataset = build_normalized_dataset(input_path, sheet)
    if normalized_dataset.model in {"frequency_sweep", "temperature_sweep", "stress_relaxation"}:
        return _render_rheology_bundle(normalized_dataset.model, "point_line", input_path, sheet, options)

    series_list = reorder_curve_series(load_curve_table_cached(input_path, sheet), options.series_order)
    _ensure_known_series_order(series_list, options.series_order)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
    is_tensile_curve = looks_like_tensile_curve(series_list)
    validate_manual_axis_overrides(options, template="point_line", is_tensile_curve=is_tensile_curve)
    axis_mode = "auto_positive" if is_tensile_curve else "auto"
    return [
        _render_curve_like_plot(
            filename=f"{input_path.stem}_point_line.pdf",
            template="point_line",
            series_list=series_list,
            options=options,
            show_markers=True,
            base_kwargs={
                "axis_mode": axis_mode,
                "preserve_stress_label": is_tensile_curve,
            },
        )
    ]

def _render_stacked_curve(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    series_list = reorder_curve_series(load_curve_table_cached(input_path, sheet), options.series_order)
    _ensure_known_series_order(series_list, options.series_order)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
    validate_manual_axis_overrides(options, template="stacked_curve")
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
    series_list = reorder_curve_series(load_curve_table_cached(input_path, sheet), options.series_order)
    _ensure_known_series_order(series_list, options.series_order)
    validate_manual_axis_overrides(options, template="segmented_stacked_curve")
    config = load_segmented_config(input_path, series_list, use_sidecar=options.use_sidecar)
    if options.series_order:
        config = replace(config, series_order=tuple(series.sample for series in series_list))
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

def _render_scatter(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    series_list = reorder_curve_series(load_curve_table_cached(input_path, sheet), options.series_order)
    _ensure_known_series_order(series_list, options.series_order)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
    is_tensile_curve = looks_like_tensile_curve(series_list)
    validate_manual_axis_overrides(options, template="scatter", is_tensile_curve=is_tensile_curve)
    axis_mode = "auto_positive" if is_tensile_curve else "auto"
    return [
        _render_curve_like_plot(
            filename=f"{input_path.stem}_scatter.pdf",
            template="scatter",
            series_list=series_list,
            options=options,
            show_markers=False,
            scatter=True,
            base_kwargs={
                "axis_mode": axis_mode,
                "preserve_stress_label": is_tensile_curve,
            },
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
    series_list = reorder_curve_series(load_curve_table_cached(input_path, sheet), options.series_order)
    _ensure_known_series_order(series_list, options.series_order)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
    is_tensile_curve = looks_like_tensile_curve(series_list)
    validate_manual_axis_overrides(options, template="bubble_scatter", is_tensile_curve=is_tensile_curve)
    axis_mode = "auto_positive" if is_tensile_curve else "auto"
    rendered = _render_curve_like_plot(
        filename=f"{input_path.stem}_bubble_scatter.pdf",
        template="bubble_scatter",
        series_list=series_list,
        options=options,
        show_markers=False,
        scatter=True,
        base_kwargs={
            "axis_mode": axis_mode,
            "preserve_stress_label": is_tensile_curve,
        },
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
    series_list = reorder_curve_series(load_curve_table_cached(input_path, sheet), options.series_order)
    _ensure_known_series_order(series_list, options.series_order)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
    is_tensile_curve = looks_like_tensile_curve(series_list)
    validate_manual_axis_overrides(options, template=template, is_tensile_curve=is_tensile_curve)
    axis_mode = "auto_positive" if is_tensile_curve else "auto"
    rendered = _render_curve_like_plot(
        filename=f"{input_path.stem}_{filename_suffix}.pdf",
        template=template,
        series_list=series_list,
        options=options,
        show_markers=False,
        scatter=True,
        base_kwargs={
            "axis_mode": axis_mode,
            "preserve_stress_label": is_tensile_curve,
        },
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

    series_list = reorder_curve_series(load_curve_table_cached(input_path, sheet), options.series_order)
    _ensure_known_series_order(series_list, options.series_order)
    validate_series_scales(series_list, xscale=options.xscale, yscale=options.yscale)
    is_tensile_curve = looks_like_tensile_curve(series_list)
    validate_manual_axis_overrides(options, template=template, is_tensile_curve=is_tensile_curve)
    axis_mode = "auto_positive" if is_tensile_curve else "auto"
    rendered = _render_curve_like_plot(
        filename=f"{input_path.stem}_{filename_suffix}.pdf",
        template=template,
        series_list=series_list,
        options=options,
        show_markers=False,
        base_kwargs={
            "axis_mode": axis_mode,
            "preserve_stress_label": is_tensile_curve,
        },
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

def _render_mean_band(input_path: Path, sheet: str | int, options: RenderOptions) -> list[RenderedPlot]:
    return _render_replicate_band_like(
        input_path,
        sheet,
        options,
        template="mean_band",
        filename_suffix="mean_band",
    )
