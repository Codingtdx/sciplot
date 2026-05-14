from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pytest

from src.data_loader import CurveSeries, HeatmapTable, ReplicateGroup, load_curve_table, load_replicate_table
from src.plotting import plot_bar, plot_box, plot_curves, plot_heatmap, plot_tensile_curve, plot_wide_nmr
from src.text_normalization import normalize_unit
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
        assert ax.get_ylabel() == "Stress (MPa)"
    finally:
        plt.close(fig)


def test_plot_tensile_curve_partial_manual_ymax_keeps_manual_endpoint_tick_visible(tmp_path: Path) -> None:
    input_path = _write_tensile_curve_table(tmp_path / "tensile_curve.csv")
    series_list = load_curve_table(input_path)

    fig, ax = plot_tensile_curve(series_list, ylim=(None, 100.0))
    try:
        y_low, y_high = sorted(float(value) for value in ax.get_ylim())
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        y_ticks = y_ticks[np.isfinite(y_ticks)]

        assert y_high == pytest.approx(100.0, abs=1e-9)
        assert y_low < 0.0
        assert np.any(np.isclose(y_ticks, 0.0))
        assert np.any(np.isclose(y_ticks, 100.0))
    finally:
        plt.close(fig)


def test_plot_tensile_curve_keeps_fixed_bounds_and_prefers_lower_right_legend() -> None:
    series = [
        _curve_series("E0", [0, 4, 8, 12, 20, 30, 36, 40], [0, 45, 68, 71, 71, 70, 62, 25]),
        _curve_series("E2", [0, 4, 8, 12, 20, 30, 40, 52], [0, 43, 63, 64, 65, 65, 58, 20]),
        _curve_series("E3", [0, 4, 8, 12, 20, 30, 42, 53], [0, 44, 66, 67, 67, 67, 57, 25]),
        _curve_series("E4", [0, 4, 8, 12, 20, 30, 42, 45], [0, 46, 75, 71, 70, 69, 61, 29]),
    ]

    fig_none, ax_none = plot_tensile_curve(series, legend_mode="none")
    expected_xlim = tuple(float(value) for value in ax_none.get_xlim())
    expected_ylim = tuple(float(value) for value in ax_none.get_ylim())
    plt.close(fig_none)

    fig, ax = plot_tensile_curve(series)
    try:
        assert tuple(float(value) for value in ax.get_xlim()) == pytest.approx(expected_xlim)
        assert tuple(float(value) for value in ax.get_ylim()) == pytest.approx(expected_ylim)

        y_low, _ = sorted(float(value) for value in ax.get_ylim())
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        y_ticks = y_ticks[np.isfinite(y_ticks)]
        assert y_low < 0.0
        assert float(y_ticks.min()) == pytest.approx(0.0, abs=1e-9)

        layout_debug = getattr(fig, "_sciplot_layout_debug", [])
        legend_records = [entry for entry in layout_debug if entry.get("object_kind") == "legend"]
        assert legend_records
        assert legend_records[0]["chosen_candidate_id"] == "lower_right"
    finally:
        plt.close(fig)


def test_plot_curve_partial_manual_bounds_keep_manual_endpoints_visible() -> None:
    series = [_curve_series("Sample A", [0.0, 50.0, 92.0], [0.0, 42.0, 81.0])]

    fig, ax = plot_curves(
        series,
        legend_mode="none",
        xlim=(None, 100.0),
        ylim=(None, 100.0),
    )
    try:
        x_ticks = np.asarray(ax.get_xticks(), dtype=float)
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        x_ticks = x_ticks[np.isfinite(x_ticks)]
        y_ticks = y_ticks[np.isfinite(y_ticks)]

        assert np.any(np.isclose(x_ticks, 100.0))
        assert np.any(np.isclose(y_ticks, 100.0))
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


def test_normalize_unit_formats_generic_exponents_with_mathtext() -> None:
    assert normalize_unit("kJ/m2") == r"kJ$\cdot$m$^{-2}$"
    assert normalize_unit("J g-1 K-1") == r"J g$^{-1}$ K$^{-1}$"
    assert normalize_unit("m²") == r"m$^{2}$"
    assert normalize_unit("m^2") == r"m$^{2}$"
    assert normalize_unit("cm-1") == r"cm$^{-1}$"
    assert normalize_unit("cm⁻¹") == r"cm$^{-1}$"
    assert normalize_unit("s-1") == r"s$^{-1}$"
    assert normalize_unit("kg m-3") == r"kg m$^{-3}$"
    assert normalize_unit("mol L-1") == r"mol L$^{-1}$"
    assert normalize_unit("W m-1 K-1") == r"W m$^{-1}$ K$^{-1}$"
    assert normalize_unit("m/s") == r"m$\cdot$s$^{-1}$"
    assert normalize_unit("m/s2") == r"m$\cdot$s$^{-2}$"
    assert normalize_unit("mm^2/s") == r"mm$^{2}\cdot$s$^{-1}$"
    assert normalize_unit("W/m/K") == r"W$\cdot$m$^{-1}\cdot$K$^{-1}$"
    assert normalize_unit("N/mm2") == r"N$\cdot$mm$^{-2}$"
    assert normalize_unit("µmol L-1") == r"μmol L$^{-1}$"
    assert normalize_unit("mL min-1") == r"mL min$^{-1}$"
    assert normalize_unit("A cm-2") == r"A cm$^{-2}$"
    assert normalize_unit("J mol-1 K-1") == r"J mol$^{-1}$ K$^{-1}$"
    assert normalize_unit("Ω cm") == "Ω cm"


def test_normalize_unit_formats_middle_dot_compound_units_with_mathtext() -> None:
    assert normalize_unit("kg·m−3") == r"kg$\cdot$m$^{-3}$"
    assert normalize_unit("mol·L^-1") == r"mol$\cdot$L$^{-1}$"
    assert normalize_unit("W·m−1·K−1") == r"W$\cdot$m$^{-1}\cdot$K$^{-1}$"


def test_plot_curve_axis_labels_restore_unit_superscripts() -> None:
    series = [
        _curve_series(
            "Sample A",
            [0.0, 1.0, 2.0],
            [0.0, 2.0, 4.0],
            x_label="Time",
            y_label="Energy density",
            x_unit="s",
            y_unit="kJ/m2",
        )
    ]

    fig, ax = plot_curves(series, legend_mode="none")
    try:
        assert ax.get_ylabel() == r"Energy Density (kJ$\cdot$m$^{-2}$)"
    finally:
        plt.close(fig)


def test_plot_curve_tick_density_controls_major_tick_count_without_changing_bounds() -> None:
    series = [_curve_series("Sample A", [0.0, 20.0, 40.0, 60.0, 80.0, 100.0], [0.0, 18.0, 39.0, 57.0, 78.0, 100.0])]

    fig_auto, ax_auto = plot_curves(series, legend_mode="none")
    fig_sparse, ax_sparse = plot_curves(series, legend_mode="none", x_tick_density="sparse")
    fig_dense, ax_dense = plot_curves(series, legend_mode="none", x_tick_density="dense")
    try:
        auto_ticks = np.asarray(ax_auto.get_xticks(), dtype=float)
        sparse_ticks = np.asarray(ax_sparse.get_xticks(), dtype=float)
        dense_ticks = np.asarray(ax_dense.get_xticks(), dtype=float)
        auto_ticks = auto_ticks[np.isfinite(auto_ticks)]
        sparse_ticks = sparse_ticks[np.isfinite(sparse_ticks)]
        dense_ticks = dense_ticks[np.isfinite(dense_ticks)]

        assert len(sparse_ticks) < len(auto_ticks)
        assert len(dense_ticks) > len(sparse_ticks)
        assert tuple(float(value) for value in ax_sparse.get_xlim()) == pytest.approx(
            tuple(float(value) for value in ax_auto.get_xlim())
        )
        assert tuple(float(value) for value in ax_dense.get_xlim()) == pytest.approx(
            tuple(float(value) for value in ax_auto.get_xlim())
        )
    finally:
        plt.close(fig_auto)
        plt.close(fig_sparse)
        plt.close(fig_dense)


def test_plot_curve_edge_label_hiding_blanks_boundary_labels_without_changing_bounds() -> None:
    series = [_curve_series("Sample A", [0.0, 50.0, 100.0], [0.0, 40.0, 100.0])]

    fig_default, ax_default = plot_curves(series, legend_mode="none")
    fig_hidden, ax_hidden = plot_curves(
        series,
        legend_mode="none",
        x_tick_edge_labels="hide_min",
        y_tick_edge_labels="hide_both",
    )
    try:
        fig_hidden.canvas.draw()
        x_labels = [tick.get_text() for tick in ax_hidden.get_xticklabels()]
        y_labels = [tick.get_text() for tick in ax_hidden.get_yticklabels()]

        assert x_labels[0] == ""
        assert any(label != "" for label in x_labels[1:])
        assert y_labels[0] == ""
        assert y_labels[-1] == ""
        assert tuple(float(value) for value in ax_hidden.get_xlim()) == pytest.approx(
            tuple(float(value) for value in ax_default.get_xlim())
        )
        assert tuple(float(value) for value in ax_hidden.get_ylim()) == pytest.approx(
            tuple(float(value) for value in ax_default.get_ylim())
        )
    finally:
        plt.close(fig_default)
        plt.close(fig_hidden)


def test_plot_curve_hide_min_uses_final_major_ticks_when_manual_xmin_is_present() -> None:
    series = [_curve_series("Sample A", [0.0, 50.0, 100.0], [0.0, 40.0, 100.0])]

    fig, ax = plot_curves(
        series,
        legend_mode="none",
        xlim=(-10.0, None),
        x_tick_edge_labels="hide_min",
    )
    try:
        fig.canvas.draw()
        x_ticks = np.asarray(ax.get_xticks(), dtype=float)
        x_ticks = x_ticks[np.isfinite(x_ticks)]
        x_labels = [tick.get_text() for tick in ax.get_xticklabels()]

        assert tuple(float(value) for value in x_ticks) == pytest.approx((0.0, 20.0, 40.0, 60.0, 80.0, 100.0))
        assert x_labels[0] == ""
        assert any(label != "" for label in x_labels[1:])
        assert float(ax.get_xlim()[0]) == pytest.approx(-10.0)
    finally:
        plt.close(fig)


def test_plot_curve_manual_xmin_recomputes_even_major_ticks_instead_of_inserting_endpoint() -> None:
    series = [_curve_series("Sample A", [0.0, 50.0, 100.0], [0.0, 40.0, 100.0])]

    fig, ax = plot_curves(
        series,
        legend_mode="none",
        xlim=(-5.0, None),
    )
    try:
        x_ticks = np.asarray(ax.get_xticks(), dtype=float)
        x_ticks = x_ticks[np.isfinite(x_ticks)]

        assert tuple(float(value) for value in x_ticks) == pytest.approx((0.0, 20.0, 40.0, 60.0, 80.0, 100.0))
        assert np.allclose(np.diff(x_ticks), 20.0)
        assert float(ax.get_xlim()[0]) == pytest.approx(-5.0)
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


def test_linear_curve_minor_ticks_stay_sparse() -> None:
    series = [_curve_series("Sample A", [0.0, 20.0, 40.0, 60.0, 80.0, 100.0], [0.0, 18.0, 39.0, 57.0, 78.0, 100.0])]

    fig, ax = plot_curves(series, legend_mode="none")
    try:
        x_major = np.asarray(ax.get_xticks(), dtype=float)
        y_major = np.asarray(ax.get_yticks(), dtype=float)
        x_minor = np.asarray(ax.xaxis.get_minorticklocs(), dtype=float)
        y_minor = np.asarray(ax.yaxis.get_minorticklocs(), dtype=float)

        x_major = x_major[np.isfinite(x_major)]
        y_major = y_major[np.isfinite(y_major)]
        x_minor = x_minor[np.isfinite(x_minor)]
        y_minor = y_minor[np.isfinite(y_minor)]

        assert len(x_minor) <= max(len(x_major) - 1, 0)
        assert len(y_minor) <= max(len(y_major) - 1, 0)
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
        assert not ax.collections
        assert all(line.get_marker() in {None, "", "None", " "} for line in ax.lines)
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


def test_plot_bar_partial_manual_ymax_keeps_manual_endpoint_tick_visible(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")
    groups = load_replicate_table(input_path)

    fig, ax = plot_bar(groups, ylim=(None, 100.0))
    try:
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        y_ticks = y_ticks[np.isfinite(y_ticks)]
        assert np.any(np.isclose(y_ticks, 100.0))
    finally:
        plt.close(fig)


def test_plot_box_partial_manual_ymax_keeps_manual_endpoint_tick_visible(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")
    groups = load_replicate_table(input_path)

    fig, ax = plot_box(groups, ylim=(None, 100.0))
    try:
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        y_ticks = y_ticks[np.isfinite(y_ticks)]
        assert np.any(np.isclose(y_ticks, 100.0))
    finally:
        plt.close(fig)


def test_plot_box_manual_y_range_recomputes_even_major_ticks() -> None:
    groups = [
        ReplicateGroup(group="E0", data=pd.Series([40.0, 41.0, 42.0]), value_label="Elongation", value_unit="%"),
        ReplicateGroup(group="E2", data=pd.Series([47.0, 50.0, 51.0, 56.0]), value_label="Elongation", value_unit="%"),
        ReplicateGroup(group="E3", data=pd.Series([49.0, 52.0, 53.0, 55.0]), value_label="Elongation", value_unit="%"),
        ReplicateGroup(group="E4", data=pd.Series([37.0, 39.0, 40.0, 42.0]), value_label="Elongation", value_unit="%"),
    ]

    fig, ax = plot_box(groups, ylim=(20.0, 60.0))
    try:
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        y_ticks = y_ticks[np.isfinite(y_ticks)]

        assert tuple(float(value) for value in y_ticks) == pytest.approx((20.0, 30.0, 40.0, 50.0, 60.0))
        assert np.allclose(np.diff(y_ticks), 10.0)
        assert tuple(float(value) for value in ax.get_ylim()) == pytest.approx((20.0, 60.0))
    finally:
        plt.close(fig)


def test_categorical_stats_hide_only_x_axis_minor_ticks(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")
    groups = load_replicate_table(input_path)

    fig_box, ax_box = plot_box(groups)
    fig_bar, ax_bar = plot_bar(groups)
    try:
        assert len(ax_box.xaxis.get_minorticklocs()) == 0
        assert len(ax_bar.xaxis.get_minorticklocs()) == 0
        assert all(tick.tick1line.get_markersize() > 0.0 for tick in ax_box.xaxis.get_major_ticks())
        assert all(tick.tick1line.get_markersize() > 0.0 for tick in ax_bar.xaxis.get_major_ticks())
    finally:
        plt.close(fig_box)
        plt.close(fig_bar)


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
