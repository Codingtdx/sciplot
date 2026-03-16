from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pytest

from src.data_loader import load_curve_table, load_replicate_table
from src.plotting import plot_box, plot_tensile_curve


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


def test_plot_tensile_curve_starts_y_axis_at_zero_and_keeps_zero_tick(tmp_path: Path) -> None:
    input_path = _write_tensile_curve_table(tmp_path / "tensile_curve.csv")
    series_list = load_curve_table(input_path)

    fig, ax = plot_tensile_curve(series_list)
    try:
        y_low, _ = sorted(float(value) for value in ax.get_ylim())
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        y_ticks = y_ticks[np.isfinite(y_ticks)]

        assert y_low == pytest.approx(0.0, abs=1e-9)
        assert np.any(np.isclose(y_ticks, 0.0))
    finally:
        plt.close(fig)


def test_plot_box_shows_the_current_lower_axis_start_as_a_visible_tick(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")
    groups = load_replicate_table(input_path)

    fig, ax = plot_box(groups)
    try:
        y_low, _ = sorted(float(value) for value in ax.get_ylim())
        y_ticks = np.asarray(ax.get_yticks(), dtype=float)
        y_ticks = y_ticks[np.isfinite(y_ticks)]

        assert not np.isclose(y_low, 0.0)
        assert np.any(np.isclose(y_ticks, y_low))
    finally:
        plt.close(fig)
