from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pytest

from src.data_loader import CurveSeries, HeatmapTable, load_curve_table, load_replicate_table
from src.plotting import plot_bar, plot_box, plot_curves, plot_heatmap, plot_tensile_curve, plot_wide_nmr
from src.wide_nmr import WideNMRConfig, WideNMRHighlightRegion, WideNMRSegment


def _curve_series(
    sample: str,
    x_values: list[float],
    y_values: list[float],
    *,
    x_label: str = "Strain",
    y_label: str = "Stress",
    x_unit: str = "%",
    y_unit: str = "MPa",
) -> CurveSeries:
    return CurveSeries(
        sample=sample,
        x_label=x_label,
        y_label=y_label,
        x_unit=x_unit,
        y_unit=y_unit,
        data=pd.DataFrame({"x": x_values, "y": y_values}),
    )


def _write_tensile_curve_table(path: Path) -> Path:
    rows = [
        ["Strain", "Stress", "Strain", "Stress"],
        ["%", "MPa", "%", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
        [0.1, 12.0, 0.1, 16.0],
        [10.0, 45.0, 12.0, 52.0],
        [20.0, 61.0, 25.0, 68.0],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_replicate_table(path: Path) -> Path:
    rows = [
        ["Strength", "", ""],
        ["solid", "4 mm", "2 mm"],
        ["MPa", "MPa", "MPa"],
        [41.2, 38.4, 35.5],
        [43.8, 39.1, 36.8],
        [44.5, 40.2, 37.9],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def test_plot_tensile_curve_keeps_zero_as_a_labeled_tick_but_leaves_display_padding(tmp_path: Path) -> None:
    input_path = _write_tensile_curve_table(tmp_path / "tensile_curve.csv")
    series_list = load_curve_table(input_path)

    fig, ax = plot_tensile_curve(series_list)
    try:
        y_low, _ = sorted(float(value) for value in ax.get_ylim())
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        y_ticks = y_ticks[np.isfinite(y_ticks)]

        assert y_low < 0.0
        assert np.any(np.isclose(y_ticks, 0.0))
        assert float(y_ticks.min()) == pytest.approx(0.0, abs=1e-9)
    finally:
        plt.close(fig)


def test_plot_curve_keeps_labeled_endpoints_visible_and_display_padding_unlabeled() -> None:
    series = [_curve_series("Sample A", [0.0, 50.0, 100.0], [0.0, 40.0, 100.0])]

    fig, ax = plot_curves(series, legend_mode="none")
    try:
        x_low, x_high = sorted(float(value) for value in ax.get_xlim())
        y_low, y_high = sorted(float(value) for value in ax.get_ylim())
        x_ticks = np.asarray(ax.get_xticks(), dtype=float)
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        x_ticks = x_ticks[np.isfinite(x_ticks)]
        y_ticks = y_ticks[np.isfinite(y_ticks)]

        assert x_low == pytest.approx(-5.0, abs=1e-9)
        assert x_high == pytest.approx(105.0, abs=1e-9)
        assert y_low == pytest.approx(-5.0, abs=1e-9)
        assert y_high == pytest.approx(105.0, abs=1e-9)
        assert np.any(np.isclose(x_ticks, 0.0))
        assert np.any(np.isclose(x_ticks, 100.0))
        assert np.any(np.isclose(y_ticks, 0.0))
        assert np.any(np.isclose(y_ticks, 100.0))
        assert float(x_ticks.min()) > x_low
        assert float(x_ticks.max()) < x_high
        assert float(y_ticks.min()) > y_low
        assert float(y_ticks.max()) < y_high
    finally:
        plt.close(fig)


def test_plot_curve_snaps_labeled_bounds_to_nice_linear_endpoints() -> None:
    series = [_curve_series("Sample A", [1050.0, 1700.0, 2890.0], [1050.0, 1800.0, 2890.0])]

    fig, ax = plot_curves(series, legend_mode="none")
    try:
        x_low, x_high = sorted(float(value) for value in ax.get_xlim())
        y_low, y_high = sorted(float(value) for value in ax.get_ylim())
        x_ticks = np.asarray(ax.get_xticks(), dtype=float)
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        x_ticks = x_ticks[np.isfinite(x_ticks)]
        y_ticks = y_ticks[np.isfinite(y_ticks)]

        assert x_low == pytest.approx(900.0, abs=1e-9)
        assert x_high == pytest.approx(3100.0, abs=1e-9)
        assert y_low == pytest.approx(900.0, abs=1e-9)
        assert y_high == pytest.approx(3100.0, abs=1e-9)
        assert np.any(np.isclose(x_ticks, 1000.0))
        assert np.any(np.isclose(x_ticks, 3000.0))
        assert np.any(np.isclose(y_ticks, 1000.0))
        assert np.any(np.isclose(y_ticks, 3000.0))
    finally:
        plt.close(fig)


def test_plot_curve_log_axis_keeps_decade_labels_but_can_extend_display_range() -> None:
    series = [
        _curve_series(
            "Sample A",
            [1.0, 10.0, 100.0],
            [10.0, 500.0, 19000.0],
            x_label="Time",
            y_label="Storage Modulus",
            x_unit="s",
            y_unit="Pa",
        )
    ]

    fig, ax = plot_curves(series, legend_mode="none", xscale="log", yscale="log")
    try:
        _, y_high = sorted(float(value) for value in ax.get_ylim())
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        y_ticks = y_ticks[np.isfinite(y_ticks)]

        assert y_high > 19000.0
        assert float(y_ticks[-1]) == pytest.approx(10000.0)
        assert float(y_ticks[-1]) < y_high
    finally:
        plt.close(fig)


def test_stacked_curve_uses_the_same_x_axis_endpoint_policy() -> None:
    series = [
        _curve_series("A", [0.0, 50.0, 100.0], [1.0, 4.0, 3.0], x_label="Wavenumber", x_unit="cm^-1"),
        _curve_series("B", [0.0, 50.0, 100.0], [2.0, 5.0, 2.0], x_label="Wavenumber", x_unit="cm^-1"),
    ]

    fig, ax = plot_curves(series, legend_mode="none", stack_mode="auto_vertical", show_markers=False)
    try:
        x_low, x_high = sorted(float(value) for value in ax.get_xlim())
        x_ticks = np.asarray(ax.get_xticks(), dtype=float)
        x_ticks = x_ticks[np.isfinite(x_ticks)]

        assert x_low == pytest.approx(-5.0, abs=1e-9)
        assert x_high == pytest.approx(105.0, abs=1e-9)
        assert np.any(np.isclose(x_ticks, 0.0))
        assert np.any(np.isclose(x_ticks, 100.0))
    finally:
        plt.close(fig)


def test_plot_box_shows_the_current_lower_labeled_bound_and_keeps_display_padding_unlabeled(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")
    groups = load_replicate_table(input_path)

    fig, ax = plot_box(groups)
    try:
        y_low, _ = sorted(float(value) for value in ax.get_ylim())
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        y_ticks = y_ticks[np.isfinite(y_ticks)]

        assert not np.isclose(y_low, 0.0)
        assert float(y_ticks.min()) > y_low
        assert np.any(np.isclose(y_ticks, float(y_ticks.min())))
    finally:
        plt.close(fig)


def test_plot_bar_keeps_zero_based_lower_bound_without_bottom_display_padding(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")
    groups = load_replicate_table(input_path)

    fig, ax = plot_bar(groups)
    try:
        y_low, _ = sorted(float(value) for value in ax.get_ylim())
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        y_ticks = y_ticks[np.isfinite(y_ticks)]

        assert y_low == pytest.approx(0.0, abs=1e-9)
        assert np.any(np.isclose(y_ticks, 0.0))
    finally:
        plt.close(fig)


def test_plot_curves_records_legend_layout_debug() -> None:
    series = [
        _curve_series("Sample A", [0.0, 1.0, 2.0, 3.0], [1.0, 1.6, 2.1, 2.5]),
        _curve_series("Sample B", [0.0, 1.0, 2.0, 3.0], [2.0, 1.8, 1.6, 1.4]),
    ]
    fig, _ = plot_curves(series, legend_mode="inside_best")
    try:
        debug = getattr(fig, "_sciplot_layout_debug", [])
        legend_records = [entry for entry in debug if entry.get("object_kind") == "legend"]
        assert legend_records
        assert legend_records[0]["chosen_candidate_id"] is not None
        assert legend_records[0]["candidates"]
    finally:
        plt.close(fig)


def test_plot_heatmap_records_colorbar_header_layout_debug() -> None:
    table = HeatmapTable(
        x_label="X",
        y_label="Y",
        z_label="Intensity",
        x_unit="mm",
        y_unit="mm",
        z_unit="a.u.",
        data=pd.DataFrame(
            {
                "x": [0, 0, 1, 1],
                "y": [0, 1, 0, 1],
                "z": [0.1, 0.2, 0.3, 0.4],
            }
        ),
    )
    fig, _ = plot_heatmap(table, show_colorbar=True)
    try:
        debug = getattr(fig, "_sciplot_layout_debug", [])
        colorbar_records = [entry for entry in debug if entry.get("object_kind") == "colorbar_header"]
        assert colorbar_records
        assert colorbar_records[0]["chosen_candidate_id"] is not None
    finally:
        plt.close(fig)


def test_plot_wide_nmr_records_annotation_textbox_layout_debug() -> None:
    x = np.linspace(0.0, 10.0, 120)
    series = [
        _curve_series(
            "Sample A",
            x.tolist(),
            (1.1 + 0.34 * np.sin(x * 1.6)).tolist(),
            x_label="Chemical shift",
            y_label="Intensity",
            x_unit="ppm",
            y_unit="a.u.",
        ),
        _curve_series(
            "Sample B",
            x.tolist(),
            (1.5 + 0.30 * np.cos(x * 1.2)).tolist(),
            x_label="Chemical shift",
            y_label="Intensity",
            x_unit="ppm",
            y_unit="a.u.",
        ),
    ]
    config = WideNMRConfig(
        segments=(WideNMRSegment(x_min=10.0, x_max=6.0), WideNMRSegment(x_min=4.0, x_max=0.0)),
        highlight_regions=(
            WideNMRHighlightRegion(
                x_min=7.6,
                x_max=6.7,
                label="Aromatic",
                color="#9fbfe8",
                label_position="top",
            ),
            WideNMRHighlightRegion(
                x_min=2.9,
                x_max=1.8,
                label="Aliphatic",
                color="#f2c48a",
                label_position="bottom",
            ),
        ),
        panel_label="Wide NMR",
        label_side="left",
    )

    fig, _ = plot_wide_nmr(series, config)
    try:
        debug = getattr(fig, "_sciplot_layout_debug", [])
        annotation_records = [entry for entry in debug if entry.get("object_kind") == "annotation_textbox"]
        assert annotation_records
        highlight_records = [
            entry
            for entry in annotation_records
            if entry.get("context", {}).get("annotation_kind") == "highlight_region_label"
        ]
        panel_records = [
            entry for entry in annotation_records if entry.get("context", {}).get("annotation_kind") == "panel_label"
        ]
        assert len(highlight_records) >= 2
        assert panel_records
        assert all(entry.get("candidates") for entry in annotation_records)
        assert all(entry.get("chosen_candidate_id") is not None for entry in annotation_records)
    finally:
        plt.close(fig)
