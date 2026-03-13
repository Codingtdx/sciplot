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


def _write_stress_relaxation_table(path: Path) -> Path:
    rows = [
        [
            "Time",
            "Shear Strain",
            "Shear Stress",
            "σ/σ0",
            "Time",
            "Shear Strain",
            "Shear Stress",
            "σ/σ0",
        ],
        ["PA", "PA", "PA", "PA", "D-PA", "D-PA", "D-PA", "D-PA"],
        ["s", "%", "Pa", "", "s", "%", "Pa", ""],
        [0.01, 1.0, 1000, 1.0, 0.01, 1.1, 1200, 1.0],
        [0.1, 1.2, 600, 0.65, 0.1, 1.3, 820, 0.68],
        [1.0, 1.4, 320, 0.32, 1.0, 1.6, 460, 0.38],
        [10.0, 1.5, 180, 0.18, 10.0, 1.8, 290, 0.24],
        [100.0, 1.6, 120, 0.12, 100.0, 2.0, 210, 0.17],
    ]
    pd.DataFrame(rows).to_excel(path, header=False, index=False)
    return path


def _write_temperature_sweep_table(path: Path) -> Path:
    rows = [
        [
            "Temperature",
            "Storage Modulus",
            "Loss Modulus",
            "Loss Factor",
            "Complex Viscosity",
            "Temperature",
            "Storage Modulus",
            "Loss Modulus",
            "Loss Factor",
            "Complex Viscosity",
        ],
        [
            "Sample A",
            "Sample A",
            "Sample A",
            "Sample A",
            "Sample A",
            "Sample B",
            "Sample B",
            "Sample B",
            "Sample B",
            "Sample B",
        ],
        ["°C", "Pa", "Pa", "", "Pa.s", "°C", "Pa", "Pa", "", "Pa.s"],
        [30, 1200, 200, 0.17, 550, 30, 980, 180, 0.18, 630],
        [60, 900, 190, 0.21, 360, 60, 760, 150, 0.20, 420],
        [90, 660, 150, 0.23, 210, 90, 580, 120, 0.21, 270],
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

    curve_options = resolve_render_options(template="curve", xscale="log", yscale="log")
    curve_preflight = preflight_render_request("curve", input_path, 0, curve_options)
    assert curve_preflight.errors == ()
    assert curve_preflight.output_filenames == (
        "freq_storage_modulus_curve.pdf",
        "freq_loss_modulus_curve.pdf",
        "freq_loss_factor_curve.pdf",
        "freq_complex_viscosity_curve.pdf",
    )

    rendered_curve = build_rendered_plots("curve", input_path, xscale="log", yscale="log")
    try:
        assert tuple(plot.filename for plot in rendered_curve) == curve_preflight.output_filenames
    finally:
        close_rendered_plots(rendered_curve)


def test_stress_relaxation_defaults_to_log_linear_and_curve_also_renders(tmp_path: Path) -> None:
    input_path = _write_stress_relaxation_table(tmp_path / "relaxation.xlsx")

    inspection = inspect_input_file(input_path)
    assert inspection.model == "stress_relaxation"
    assert inspection.recommendation.template == "point_line"
    assert inspection.recommendation.xscale == "log"
    assert inspection.recommendation.yscale == "linear"

    point_options = resolve_render_options(template="point_line", xscale="log", yscale="linear")
    point_preflight = preflight_render_request("point_line", input_path, 0, point_options)
    assert point_preflight.errors == ()

    curve_options = resolve_render_options(template="curve", xscale="log", yscale="linear")
    curve_preflight = preflight_render_request("curve", input_path, 0, curve_options)
    assert curve_preflight.errors == ()
    assert curve_preflight.output_filenames == ("stress_relaxation_sigma_over_sigma0_curve.pdf",)

    rendered = build_rendered_plots("curve", input_path, xscale="log", yscale="linear")
    try:
        assert tuple(plot.filename for plot in rendered) == curve_preflight.output_filenames
    finally:
        close_rendered_plots(rendered)


def test_temperature_bundle_curve_preflight_matches_multi_output_render(tmp_path: Path) -> None:
    input_path = _write_temperature_sweep_table(tmp_path / "temperature.xlsx")

    inspection = inspect_input_file(input_path)
    assert inspection.model == "temperature_sweep"
    assert inspection.recommendation.template == "point_line"

    curve_options = resolve_render_options(template="curve", xscale="linear", yscale="log")
    curve_preflight = preflight_render_request("curve", input_path, 0, curve_options)
    assert curve_preflight.errors == ()
    assert curve_preflight.output_filenames == (
        "temp_storage_modulus_curve.pdf",
        "temp_complex_viscosity_curve.pdf",
    )

    rendered = build_rendered_plots("curve", input_path, xscale="linear", yscale="log")
    try:
        assert tuple(plot.filename for plot in rendered) == curve_preflight.output_filenames
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
