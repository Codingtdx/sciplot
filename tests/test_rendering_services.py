from __future__ import annotations

from pathlib import Path

import pandas as pd

from src.rendering import (
    build_rendered_plots,
    close_rendered_plots,
    inspect_input_file,
    preflight_render_request,
    resolve_render_options,
)


def _write_curve_table(path: Path) -> Path:
    rows = [
        ["Time", "Stress", "Time", "Stress"],
        ["s", "MPa", "s", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
        [0, 1.0, 0, 2.0],
        [1, 1.3, 1, 2.4],
        [2, 1.5, 2, 2.8],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_replicate_table(path: Path) -> Path:
    rows = [
        ["Tensile modulus", "", ""],
        ["Blend A", "Blend B", "Blend C"],
        ["MPa", "MPa", "MPa"],
        [510.13, 567.91, 544.10],
        [501.10, 501.49, 549.54],
        [549.61, 549.61, 562.07],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_frequency_sweep_table(path: Path) -> Path:
    rows = [
        [
            "Angular Frequency",
            "Storage Modulus",
            "Loss Modulus",
            "Loss Factor",
            "Complex Viscosity",
        ],
        ["Sample A", "Sample A", "Sample A", "Sample A", "Sample A"],
        ["rad/s", "Pa", "Pa", "", "Pa.s"],
        [0.1, 1000, 200, 0.2, 500],
        [1.0, 2000, 400, 0.2, 250],
        [10.0, 4000, 800, 0.2, 120],
    ]
    pd.DataFrame(rows).to_excel(path, header=False, index=False)
    return path


def test_curve_inspect_preflight_and_render_filenames_match(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    inspection = inspect_input_file(input_path)
    assert inspection.recommendation.template == "curve"

    options = resolve_render_options(template="curve")
    preflight = preflight_render_request("curve", input_path, 0, options)
    assert preflight.errors == ()

    rendered = build_rendered_plots("curve", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
    finally:
        close_rendered_plots(rendered)


def test_frequency_bundle_preflight_matches_multi_output_render(tmp_path: Path) -> None:
    input_path = _write_frequency_sweep_table(tmp_path / "frequency.xlsx")

    inspection = inspect_input_file(input_path)
    assert inspection.model == "frequency_sweep"
    assert inspection.recommendation.template == "point_line"

    options = resolve_render_options(template="point_line", xscale="log", yscale="log")
    preflight = preflight_render_request("point_line", input_path, 0, options)
    assert preflight.errors == ()
    assert len(preflight.output_filenames) == 4

    rendered = build_rendered_plots("point_line", input_path, xscale="log", yscale="log")
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
    finally:
        close_rendered_plots(rendered)


def test_bar_preflight_matches_render_filename(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    options = resolve_render_options(template="bar")
    preflight = preflight_render_request("bar", input_path, 0, options)
    assert preflight.errors == ()

    rendered = build_rendered_plots("bar", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
    finally:
        close_rendered_plots(rendered)
