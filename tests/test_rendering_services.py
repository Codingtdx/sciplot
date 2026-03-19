from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

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


def _write_dense_curve_table(path: Path) -> Path:
    import numpy as np

    x = np.linspace(0.5, 10.0, 80)
    y_a = np.sin(x / 2.0) + 2.1
    y_b = np.cos(x / 3.0) + 3.2
    rows = [
        ["Strain", "Stress", "Strain", "Stress"],
        ["%", "MPa", "%", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
    ]
    for x_value, y_value_a, y_value_b in zip(x, y_a, y_b, strict=True):
        rows.append([x_value, y_value_a, x_value, y_value_b])
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_monotonic_curve_table(path: Path) -> Path:
    import numpy as np

    x = np.linspace(25.0, 220.0, 120)
    rows = [
        ["Temperature", "E'", "Temperature", "E'"],
        ["°C", "MPa", "°C", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
    ]
    for value in x:
        rows.append(
            [
                value,
                3200 * np.exp(-value / 140.0) + 180.0,
                value,
                2800 * np.exp(-value / 150.0) + 220.0,
            ]
        )
    pd.DataFrame(rows).to_csv(path, header=False, index=False)
    return path


def _write_tensile_curve_table(path: Path) -> Path:
    rows = [
        ["Strain", "Stress", "Strain", "Stress"],
        ["%", "MPa", "%", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
        [0.1, 1.0, 0.1, 1.4],
        [10.0, 120.0, 12.0, 160.0],
        [1000.0, 12000.0, 1200.0, 14500.0],
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
    assert preflight.submission_report is not None
    assert preflight.submission_report.context == "preflight"
    assert preflight.submission_report.style_preset == "default"

    rendered = build_rendered_plots("curve", input_path)
    try:
        assert tuple(plot.filename for plot in rendered) == preflight.output_filenames
    finally:
        close_rendered_plots(rendered)


def test_resolve_render_options_accepts_public_style_preset(tmp_path: Path) -> None:
    input_path = _write_curve_table(tmp_path / "curve.csv")

    options = resolve_render_options(
        template="curve",
        style_preset="nature",
        palette_preset="colorblind_safe",
    )
    preflight = preflight_render_request("curve", input_path, 0, options)

    assert options.style_preset == "nature"
    assert preflight.submission_report is not None
    assert preflight.submission_report.style_preset == "nature"


def test_tensile_curve_defaults_to_linear_and_rejects_log_scale(tmp_path: Path) -> None:
    input_path = _write_tensile_curve_table(tmp_path / "tensile_curve.csv")

    inspection = inspect_input_file(input_path)
    assert inspection.model == "tensile_curve"
    assert inspection.recommendation.template == "curve"
    assert inspection.recommendation.size == "60x55"
    assert inspection.recommendation.xscale == "linear"
    assert inspection.recommendation.yscale == "linear"

    linear_options = resolve_render_options(template="curve", xscale="linear", yscale="linear")
    linear_preflight = preflight_render_request("curve", input_path, 0, linear_options)
    assert linear_preflight.errors == ()

    log_options = resolve_render_options(template="curve", xscale="log", yscale="linear")
    log_preflight = preflight_render_request("curve", input_path, 0, log_options)
    assert log_preflight.errors == ("Tensile curves must use linear axes. Log x / y is not supported.",)

    with pytest.raises(ValueError, match="Tensile curves must use linear axes"):
        build_rendered_plots("curve", input_path, xscale="log", yscale="linear")


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


def test_small_curve_render_prefers_direct_labels_when_they_fit(tmp_path: Path) -> None:
    input_path = _write_dense_curve_table(tmp_path / "dense_curve.csv")

    rendered = build_rendered_plots("curve", input_path)
    try:
        assert len(rendered) == 1
        plot = rendered[0]
        assert plot.qa_report is not None
        assert "direct_series_labels" in plot.qa_report.autofixes_applied
        ax = plot.figure.axes[0]
        assert ax.get_legend() is None
        assert {text.get_text() for text in ax.texts} == {"Sample A", "Sample B"}
    finally:
        close_rendered_plots(rendered)


def test_small_monotonic_curve_uses_direct_label_fallback_when_edge_labels_fail(tmp_path: Path) -> None:
    input_path = _write_monotonic_curve_table(tmp_path / "dma_like_curve.csv")

    rendered = build_rendered_plots("curve", input_path)
    try:
        assert len(rendered) == 1
        plot = rendered[0]
        assert plot.qa_report is not None
        issue_ids = {issue.id for issue in plot.qa_report.issues}
        assert plot.qa_report.grade in {"solid", "excellent"}
        assert "direct_series_labels" in plot.qa_report.autofixes_applied
        assert "legend_footprint" not in issue_ids
        assert "series_identification" not in issue_ids
        assert "stroke_hierarchy" not in issue_ids
        ax = plot.figure.axes[0]
        assert ax.get_legend() is None
        assert {text.get_text() for text in ax.texts} == {"Sample A", "Sample B"}
    finally:
        close_rendered_plots(rendered)


def test_small_point_line_quality_clears_compact_editorial_checks(tmp_path: Path) -> None:
    input_path = _write_temperature_sweep_table(tmp_path / "temperature.xlsx")

    rendered = build_rendered_plots("point_line", input_path, yscale="log")
    try:
        assert rendered
        for plot in rendered:
            assert plot.qa_report is not None
            issue_ids = {issue.id for issue in plot.qa_report.issues}
            assert plot.qa_report.grade in {"solid", "excellent"}
            assert "legend_footprint" not in issue_ids
            assert "stroke_hierarchy" not in issue_ids
            assert "series_identification" not in issue_ids
    finally:
        close_rendered_plots(rendered)


def test_bar_render_uses_editorial_spacing_and_raw_point_overlay(tmp_path: Path) -> None:
    input_path = _write_replicate_table(tmp_path / "replicates.csv")

    rendered = build_rendered_plots("bar", input_path)
    try:
        assert len(rendered) == 1
        plot = rendered[0]
        assert plot.qa_report is not None
        assert "bar_raw_points_overlay" in plot.qa_report.autofixes_applied
        assert "stats_spacing_profile" in plot.qa_report.autofixes_applied
        ax = plot.figure.axes[0]
        assert ax.collections
    finally:
        close_rendered_plots(rendered)
