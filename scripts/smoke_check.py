from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
from collections.abc import Callable, Sequence
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import fitz
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import to_hex

from make_plot import (
    _resolve_render_options,
    build_rendered_plots,
    inspect_input_file,
    list_sheet_names,
    preflight_render_request,
    render_template,
)
from src import (
    mpl_backend,  # noqa: F401
    plot_style,
)
from src.composer import (
    ComposerText,
    compose_export_pdf,
    compose_preview_png,
    import_panels_from_paths,
    three_up_panels_from_paths,
    two_up_editorial_panels_from_paths,
    validate_non_overlapping_panels,
)
from src.composer_qa import analyze_composer_project
from src.data_loader import CurveSeries, load_curve_table, load_replicate_table
from src.plot_contract import lint_public_template_contract, load_plot_contract, validation_rule
from src.plotting import (
    INSIDE_LEGEND_INSET_FRACTION,
    _cap_visible_major_ticks,
    _format_axis_label,
    compute_shared_curve_x_layout,
    plot_bar,
    plot_box,
    plot_dsc,
    plot_frequency_sweep,
    plot_ftir,
    plot_heatmap,
    plot_nmr,
    plot_tensile_curve,
    plot_violin,
    plot_wide_nmr,
    plot_xrd,
)
from src.plotting_curves import _legend_candidates, _place_legend_candidate
from src.rendering import close_rendered_plots, export_rendered_plots
from src.rheology_loader import load_frequency_sweep_metrics, load_temperature_sweep_metrics
from src.tensile_replicates import export_tensile_replicate_workbook
from src.text_normalization import normalize_label, normalize_unit
from src.wide_nmr import (
    WIDE_NMR_SPECTRUM_HEIGHT_MM,
    WIDE_NMR_STRUCTURE_RESERVED_MM,
    WIDE_NMR_TOTAL_HEIGHT_MM,
    WIDE_NMR_WIDTH_MM,
    load_wide_nmr_config,
)

SMOKE_REPORT_PATH = ROOT / "figures" / "debug_outputs" / "smoke_report.json"
SMOKE_CAPTURE_DIR_ENV = "CODEGOD_SMOKE_CAPTURE_DIR"
TENSILE_RAW_FIXTURE_DIR = ROOT / "tests" / "fixtures" / "tensile_raw"
TENSILE_WORKBOOK_SHEETS = {
    "Representative_Curve",
    "All_Curves",
    "Summary",
    "All_Specimens",
    "Strength_Replicates",
    "Modulus_Replicates",
    "Elongation_Replicates",
    "DataStudio_Metadata",
}


def _validation_result(rule_name: str, *, passed: bool, details: dict[str, object]) -> dict[str, object]:
    rule = validation_rule(rule_name)
    payload: dict[str, object] = {
        "id": rule_name,
        "label": rule.label,
        "severity": rule.severity,
        "passed": bool(passed),
        "details": details,
    }
    if rule.tolerance_mm is not None:
        payload["tolerance_mm"] = rule.tolerance_mm
    return payload


def _assert_no_failed_error_validations(reports: list[dict[str, object]]) -> None:
    failures = [
        report
        for report in reports
        if report.get("severity") == "error" and report.get("passed") is False
    ]
    if not failures:
        return
    labels = ", ".join(str(report.get("id", "<unknown>")) for report in failures)
    raise AssertionError(f"Smoke validation failed for error-level checks: {labels}")


def _json_safe(value: object) -> object:
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, list | tuple):
        return [_json_safe(item) for item in value]
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, np.generic):
        return value.item()
    return value


def _repo_relative_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


@dataclass(frozen=True)
class _RecommendationConfig:
    template: str
    size: str | None = None
    xscale: str | None = None
    yscale: str | None = None
    reverse_x: bool | None = None
    baseline: str | None = None
    show_colorbar: bool | None = None
    use_sidecar: bool | None = None


def _coerce_str(value: Any) -> str | None:
    if isinstance(value, str) and value:
        return value
    return None


def _coerce_bool(value: Any) -> bool | None:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"1", "true", "yes", "on"}:
            return True
        if lowered in {"0", "false", "no", "off"}:
            return False
    return None


def _top_recommendation_config(inspection: Any) -> _RecommendationConfig:
    ranked_candidates = list(getattr(inspection, "recommendations", ()))
    ordered_candidates = (
        list(getattr(inspection, "primary_recommendation", ()))
        + list(getattr(inspection, "alternative_recommendations", ()))
        + list(getattr(inspection, "advanced_templates", ()))
    )
    candidates = ranked_candidates or ordered_candidates
    if not candidates:
        raise AssertionError("Inspection did not return ranked recommendations.")
    top = candidates[0]
    summary = getattr(top, "preview_config_summary", {}) or {}
    if not isinstance(summary, dict):
        summary = {}
    return _RecommendationConfig(
        template=str(top.template_id),
        size=_coerce_str(summary.get("size")),
        xscale=_coerce_str(summary.get("xscale")),
        yscale=_coerce_str(summary.get("yscale")),
        reverse_x=_coerce_bool(summary.get("reverse_x")),
        baseline=_coerce_str(summary.get("baseline")),
        show_colorbar=_coerce_bool(summary.get("show_colorbar")),
        use_sidecar=_coerce_bool(summary.get("use_sidecar")),
    )


def _write_curve_table(path: Path, x_label: str, y_label: str, x_unit: str, y_unit: str) -> None:
    x = np.linspace(1, 10, 80)
    y1 = np.sin(x / 2) + 2.0
    y2 = np.cos(x / 3) + 3.2
    rows = [
        [x_label, y_label, x_label, y_label],
        [x_unit, y_unit, x_unit, y_unit],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
    ]
    for xv, yv1, yv2 in zip(x, y1, y2, strict=True):
        rows.append([xv, yv1, xv, yv2])
    pd.DataFrame(rows).to_csv(path, header=False, index=False)


def _write_replicate_table(path: Path) -> None:
    rows = [
        ["Tensile modulus", "", "", ""],
        ["Blend A", "Blend B", "Foam A", "Foam B"],
        ["MPa", "MPa", "MPa", "MPa"],
        [510.13, 567.91, 1544.41, 1556.47],
        [501.10, 501.49, 1551.10, 1605.92],
        [549.61, 549.61, 1567.26, 1581.81],
        [549.54, 562.07, 1549.94, 1619.74],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)


def _write_invalid_curve_table_missing_y(path: Path) -> None:
    rows = [
        ["Time", "Stress"],
        ["s", "MPa"],
        ["Sample A", "Sample A"],
        [0, "bad"],
        [1, "still bad"],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)


def _write_invalid_curve_table_odd_columns(path: Path) -> None:
    rows = [
        ["Time", "Stress", "Time"],
        ["s", "MPa", "s"],
        ["Sample A", "Sample A", "Sample B"],
        [0, 1.0, 0],
        [1, 1.5, 1],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)


def _write_invalid_replicate_table(path: Path) -> None:
    rows = [
        ["Tensile modulus", "", ""],
        ["Blend A", "Blend B", "Blend C"],
        ["MPa", "MPa", "MPa"],
        [510.13, "bad", 620.4],
        [501.10, "still bad", 618.2],
    ]
    pd.DataFrame(rows).to_csv(path, header=False, index=False)


def _gaussian(x: np.ndarray, center: float, width: float, amplitude: float) -> np.ndarray:
    return amplitude * np.exp(-0.5 * ((x - center) / width) ** 2)


def _write_stacked_curve_table(path: Path, *, template: str) -> None:
    if template == "ftir":
        x = np.linspace(4000, 600, 320)
        y_label, x_label, x_unit, y_unit = "Transmittance", "Wavenumber", "cm-1", "%"
        curves = [
            82 - _gaussian(x, 3340, 120, 18) - _gaussian(x, 2920, 90, 9) - _gaussian(x, 1710, 45, 14),
            79 - _gaussian(x, 3320, 130, 15) - _gaussian(x, 2960, 85, 8) - _gaussian(x, 1650, 50, 17),
            77 - _gaussian(x, 3290, 115, 12) - _gaussian(x, 2870, 95, 7) - _gaussian(x, 1605, 55, 13),
            75 - _gaussian(x, 3250, 140, 10) - _gaussian(x, 2850, 100, 6) - _gaussian(x, 1570, 60, 11),
        ]
    elif template == "nmr":
        x = np.linspace(0, 10, 300)
        y_label, x_label, x_unit, y_unit = "Intensity", "Chemical shift", "ppm", "a.u."
        curves = [
            _gaussian(x, 7.2, 0.12, 1.1) + _gaussian(x, 3.6, 0.10, 0.7) + _gaussian(x, 1.2, 0.08, 0.4) + 0.02 * x,
            _gaussian(x, 7.0, 0.11, 1.0) + _gaussian(x, 3.3, 0.11, 0.8) + _gaussian(x, 1.0, 0.09, 0.5) + 0.015 * x,
            _gaussian(x, 6.8, 0.10, 0.9) + _gaussian(x, 3.1, 0.12, 0.75) + _gaussian(x, 0.9, 0.10, 0.55) + 0.01 * x,
            _gaussian(x, 6.5, 0.13, 0.85) + _gaussian(x, 2.9, 0.13, 0.7) + _gaussian(x, 0.8, 0.11, 0.6) + 0.008 * x,
        ]
    elif template == "xrd":
        x = np.linspace(5, 45, 320)
        y_label, x_label, x_unit, y_unit = "Intensity", "2theta", "°", "a.u."
        curves = [
            _gaussian(x, 12.4, 0.35, 1.4) + _gaussian(x, 21.8, 0.45, 1.0) + _gaussian(x, 28.9, 0.40, 0.8),
            _gaussian(x, 12.9, 0.40, 1.2) + _gaussian(x, 22.4, 0.42, 0.95) + _gaussian(x, 29.6, 0.38, 0.9),
            _gaussian(x, 13.2, 0.36, 1.1) + _gaussian(x, 23.1, 0.44, 0.9) + _gaussian(x, 30.4, 0.41, 0.85),
            _gaussian(x, 13.6, 0.38, 1.0) + _gaussian(x, 23.8, 0.46, 0.88) + _gaussian(x, 31.2, 0.43, 0.8),
        ]
    elif template == "dsc":
        x = np.linspace(30, 240, 320)
        y_label, x_label, x_unit, y_unit = "Heat flow", "Temperature", "°C", "mW"
        curves = [
            0.002 * (x - 30) - _gaussian(x, 88, 8, 0.55) - _gaussian(x, 172, 12, 0.9),
            0.0018 * (x - 30) - _gaussian(x, 95, 9, 0.45) - _gaussian(x, 180, 14, 0.8),
            0.0016 * (x - 30) - _gaussian(x, 102, 10, 0.40) - _gaussian(x, 186, 13, 0.72),
            0.0014 * (x - 30) - _gaussian(x, 108, 11, 0.36) - _gaussian(x, 193, 15, 0.68),
        ]
    else:
        raise ValueError(f"Unsupported stacked template: {template}")

    sample_names = [f"Sample {idx}" for idx in range(1, len(curves) + 1)]
    axis_row: list[object] = []
    unit_row: list[object] = []
    sample_row: list[object] = []
    for sample in sample_names:
        axis_row.extend([x_label, y_label])
        unit_row.extend([x_unit, y_unit])
        sample_row.extend([sample, sample])

    rows = [axis_row, unit_row, sample_row]
    for row_idx in range(len(x)):
        row: list[object] = []
        for y in curves:
            row.extend([float(x[row_idx]), float(y[row_idx])])
        rows.append(row)
    pd.DataFrame(rows).to_csv(path, header=False, index=False)


def _write_frequency_xlsx(path: Path) -> None:
    x = np.logspace(-1, 2, 50)
    rows = [
        ["Angular Frequency", "Storage Modulus", "Loss Modulus", "Loss Factor", "Complex Viscosity"] * 2,
        ["Sample A", "", "", "", "", "Sample B", "", "", "", ""],
        ["rad/s", "Pa", "Pa", "", "mPa·s", "rad/s", "Pa", "Pa", "", "mPa·s"],
    ]
    for value in x:
        rows.append(
            [
                value,
                1.2e3 * value**0.25,
                6.8e2 * value**0.18,
                0.45 + 0.03 * np.log10(value + 1),
                4.2e4 / value**0.55,
                value,
                1.5e3 * value**0.22,
                7.2e2 * value**0.20,
                0.52 + 0.025 * np.log10(value + 1),
                4.8e4 / value**0.50,
            ]
        )
    pd.DataFrame(rows).to_excel(path, header=False, index=False)


def _write_temperature_xlsx(path: Path) -> None:
    x = np.linspace(30, 220, 60)
    rows = [
        ["Temperature", "Storage Modulus", "Loss Modulus", "Loss Factor", "Complex Viscosity"] * 2,
        ["Sample A", "", "", "", "", "Sample B", "", "", "", ""],
        ["°C", "Pa", "Pa", "", "Pa·s", "°C", "Pa", "Pa", "", "Pa·s"],
    ]
    for value in x:
        rows.append(
            [
                value,
                3.2e6 * np.exp(-value / 150),
                1.4e6 * np.exp(-value / 145),
                0.42 + value / 600,
                1.1e5 * np.exp(-value / 55),
                value,
                2.5e6 * np.exp(-value / 155),
                1.0e6 * np.exp(-value / 150),
                0.38 + value / 650,
                9.0e4 * np.exp(-value / 60),
            ]
        )
    pd.DataFrame(rows).to_excel(path, header=False, index=False)


def _write_relaxation_xlsx(path: Path) -> None:
    x = np.logspace(-1, 3, 70)
    rows = [
        ["Time", "Shear Strain", "Shear Stress", "σ/σ0"] * 2,
        ["Sample A", "", "", "", "Sample B", "", "", ""],
        ["[s]", "[%]", "[Pa]", "", "[s]", "[%]", "[Pa]", ""],
    ]
    for value in x:
        stress_a = 1200 * np.exp(-np.log10(value + 1) / 1.5) + 120
        stress_b = 1000 * np.exp(-np.log10(value + 1) / 1.7) + 100
        rows.append([value, 1.0, stress_a, stress_a / 1320, value, 1.0, stress_b, stress_b / 1100])
    pd.DataFrame(rows).to_excel(path, header=False, index=False)


def _write_tga_curve_table(path: Path) -> None:
    x = np.linspace(30, 700, 120)
    rows = [
        ["Temperature", "Weight", "Temperature", "Weight"],
        ["°C", "%", "°C", "%"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
    ]
    for value in x:
        rows.append(
            [
                value,
                100 - 0.02 * value - 18 / (1 + np.exp(-(value - 360) / 18)),
                value,
                100 - 0.018 * value - 20 / (1 + np.exp(-(value - 390) / 22)),
            ]
        )
    pd.DataFrame(rows).to_csv(path, header=False, index=False)


def _write_dma_curve_table(path: Path) -> None:
    x = np.linspace(25, 220, 120)
    rows = [
        ["Temperature", "E'", "Temperature", "E'"],
        ["°C", "MPa", "°C", "MPa"],
        ["Sample A", "Sample A", "Sample B", "Sample B"],
    ]
    for value in x:
        rows.append(
            [
                value,
                3200 * np.exp(-value / 140) + 180,
                value,
                2800 * np.exp(-value / 150) + 220,
            ]
        )
    pd.DataFrame(rows).to_csv(path, header=False, index=False)


def _write_heatmap_table(path: Path) -> None:
    rows = [
        ["X", "Y", "Z"],
        ["Temperature", "Blend ratio", "Storage Modulus"],
        ["°C", "%", "MPa"],
    ]
    temperatures = [30, 60, 90, 120]
    ratios = ["0:1", "0.3:1", "0.6:1", "1:1"]
    for ratio_index, ratio in enumerate(ratios):
        for temp_index, temperature in enumerate(temperatures):
            value = 1800 - temp_index * 220 + ratio_index * 140
            rows.append([temperature, ratio, value])
    pd.DataFrame(rows).to_csv(path, header=False, index=False)


def _write_wide_nmr_bundle(path: Path) -> None:
    x = np.linspace(3.7, 9.3, 2400)
    sample_names = ["0:1", "0.1:1", "0.2:1", "0.3:1", "0.4:1", "0.5:1"]
    curve_params = [
        [
            (8.95, 0.010, 1.4),
            (8.45, 0.012, 1.1),
            (8.18, 0.010, 1.6),
            (8.08, 0.010, 1.4),
            (7.86, 0.013, 1.1),
            (7.58, 0.014, 0.9),
            (7.50, 0.014, 0.8),
            (4.06, 0.010, 2.6),
        ],
        [
            (8.94, 0.010, 1.2),
            (8.43, 0.012, 0.9),
            (8.19, 0.010, 1.2),
            (8.07, 0.010, 1.1),
            (7.85, 0.013, 1.0),
            (7.57, 0.014, 0.9),
            (7.49, 0.014, 0.7),
            (4.06, 0.010, 2.1),
        ],
        [
            (8.93, 0.010, 1.0),
            (8.44, 0.012, 0.8),
            (8.18, 0.010, 1.0),
            (8.06, 0.010, 0.95),
            (7.84, 0.013, 0.9),
            (7.56, 0.014, 0.85),
            (7.48, 0.014, 0.65),
            (4.06, 0.010, 1.8),
        ],
        [
            (8.92, 0.010, 0.8),
            (8.45, 0.012, 0.65),
            (8.19, 0.010, 0.82),
            (8.05, 0.010, 0.8),
            (7.83, 0.013, 0.8),
            (7.55, 0.014, 0.8),
            (7.47, 0.014, 0.62),
            (4.06, 0.010, 1.5),
        ],
        [
            (8.91, 0.010, 0.65),
            (8.46, 0.012, 0.52),
            (8.20, 0.010, 0.66),
            (8.04, 0.010, 0.65),
            (7.82, 0.013, 0.72),
            (7.54, 0.014, 0.74),
            (7.46, 0.014, 0.58),
            (4.06, 0.010, 1.2),
        ],
        [
            (8.90, 0.010, 0.52),
            (8.47, 0.012, 0.44),
            (8.21, 0.010, 0.54),
            (8.03, 0.010, 0.53),
            (7.81, 0.013, 0.64),
            (7.53, 0.014, 0.68),
            (7.45, 0.014, 0.54),
            (4.06, 0.010, 1.0),
        ],
    ]
    rows = [
        ["Chemical shift", "Intensity"] * len(sample_names),
        ["ppm", "a.u."] * len(sample_names),
        [item for sample in sample_names for item in (sample, sample)],
    ]
    for _idx, x_value in enumerate(x):
        row: list[float] = []
        for series_peaks in curve_params:
            y_value = 0.01 * np.sin(x_value * 2.5)
            for center, width, amplitude in series_peaks:
                y_value += _gaussian(np.array([x_value]), center, width, amplitude)[0]
            row.extend([float(x_value), float(y_value)])
        rows.append(row)
    pd.DataFrame(rows).to_csv(path, header=False, index=False)

    sidecar = path.with_suffix(".wide_nmr.toml")
    sidecar.write_text(
        "\n".join(
            [
                'series_order = ["0:1", "0.1:1", "0.2:1", "0.3:1", "0.4:1", "0.5:1"]',
                "",
                "[series_labels]",
                '"0:1" = "0:1"',
                '"0.1:1" = "0.1:1"',
                '"0.2:1" = "0.2:1"',
                '"0.3:1" = "0.3:1"',
                '"0.4:1" = "0.4:1"',
                '"0.5:1" = "0.5:1"',
                "",
                "[layout]",
                'label_side = "left"',
                'panel_label = "b)"',
                "segment_gap = 0.03",
                "stack_floor_fraction = 0.28",
                "stack_gap_fraction = 0.30",
                "label_inset_fraction = 0.035",
                "label_offset_pt = 3.0",
                "",
                "[[segments]]",
                "x_min = 6.6",
                "x_max = 9.2",
                "width_ratio = 4.3",
                "",
                "[[segments]]",
                "x_min = 3.85",
                "x_max = 4.25",
                "width_ratio = 1.25",
                "",
                "[[highlight_regions]]",
                "x_min = 8.88",
                "x_max = 8.99",
                'label = "1"',
                'color = "#d76659"',
                "alpha = 0.18",
                'series = ["0:1", "0.1:1"]',
                'label_position = "bottom"',
                "",
                "[[highlight_regions]]",
                "x_min = 8.39",
                "x_max = 8.49",
                'label = "2"',
                'color = "#d76659"',
                "alpha = 0.16",
                'series = ["0:1", "0.1:1"]',
                'label_position = "bottom"',
                "",
                "[[highlight_regions]]",
                "x_min = 8.02",
                "x_max = 8.22",
                'label = "3"',
                'color = "#9cbbe5"',
                "alpha = 0.18",
                'series = ["0.3:1", "0.4:1", "0.5:1"]',
                "",
                "[[highlight_regions]]",
                "x_min = 7.74",
                "x_max = 7.90",
                'label = "4"',
                'color = "#9cbbe5"',
                "alpha = 0.16",
                'series = ["0.3:1", "0.4:1", "0.5:1"]',
                "",
                "[[highlight_regions]]",
                "x_min = 7.43",
                "x_max = 7.63",
                'label = "5"',
                'color = "#9cbbe5"',
                "alpha = 0.14",
                'series = ["0.3:1", "0.4:1", "0.5:1"]',
                "",
                "[[highlight_regions]]",
                "x_min = 4.00",
                "x_max = 4.11",
                'label = "0"',
                'color = "#9cbbe5"',
                "alpha = 0.18",
                'series = ["0.2:1", "0.3:1", "0.4:1", "0.5:1"]',
                "",
            ]
        ),
        encoding="utf-8",
    )


def _assert_stacked_layout(plot_fn, path: Path) -> None:
    def _densify(points: np.ndarray, max_step_px: float = 3.0) -> np.ndarray:
        if len(points) < 2:
            return points
        dense = [points[:1]]
        for start, end in zip(points[:-1], points[1:], strict=True):
            delta = end - start
            steps = max(int(np.ceil(max(abs(delta[0]), abs(delta[1])) / max_step_px)), 1)
            if steps == 1:
                dense.append(end[None, :])
                continue
            fractions = np.linspace(0.0, 1.0, steps + 1, dtype=float)[1:]
            dense.append(start + fractions[:, None] * delta[None, :])
        return np.vstack(dense)

    series_list = load_curve_table(path)
    fig, ax = plot_fn(series_list)
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    axes_bbox = ax.get_window_extent(renderer=renderer)

    line_ymins = [float(np.nanmin(line.get_ydata())) for line in ax.lines if len(line.get_ydata())]
    if not line_ymins:
        raise AssertionError("Expected plotted lines for stacked layout check.")
    if min(line_ymins) <= ax.get_ylim()[0]:
        raise AssertionError("Lowest stacked curve is touching the x-axis boundary.")

    if any(label.get_visible() for label in ax.get_yticklabels()):
        raise AssertionError("Stacked spectral templates should hide y tick labels.")

    if any(tick.tick1line.get_visible() or tick.tick2line.get_visible() for tick in ax.yaxis.get_major_ticks()):
        raise AssertionError("Stacked spectral templates should hide y tick marks.")

    label_texts = ax.texts
    if len(label_texts) != len(series_list):
        raise AssertionError("Expected one in-axes sample label per stacked spectral series.")

    anchor_x = [float(text.get_transform().transform(text.get_position())[0]) for text in label_texts]
    if max(anchor_x) - min(anchor_x) > 4.0:
        raise AssertionError("Stacked spectral sample labels should stay aligned on a common x rail.")

    bboxes = [text.get_window_extent(renderer=renderer).expanded(1.01, 1.03) for text in label_texts]
    if any(
        bbox.x0 < axes_bbox.x0 or bbox.x1 > axes_bbox.x1 or bbox.y0 < axes_bbox.y0 or bbox.y1 > axes_bbox.y1
        for bbox in bboxes
    ):
        raise AssertionError("Stacked spectral sample labels should stay inside the axes.")
    for idx, bbox in enumerate(bboxes):
        for other in bboxes[idx + 1 :]:
            if bbox.overlaps(other):
                raise AssertionError("Stacked spectral sample labels should not overlap each other.")

    for bbox in bboxes:
        for line in ax.lines:
            x = np.asarray(line.get_xdata(), dtype=float)
            y = np.asarray(line.get_ydata(), dtype=float)
            valid = np.isfinite(x) & np.isfinite(y)
            if valid.sum() == 0:
                continue
            points = _densify(ax.transData.transform(np.column_stack([x[valid], y[valid]])))
            inside = (
                (points[:, 0] >= bbox.x0)
                & (points[:, 0] <= bbox.x1)
                & (points[:, 1] >= bbox.y0)
                & (points[:, 1] <= bbox.y1)
            )
            if np.any(inside):
                raise AssertionError("Stacked spectral sample labels should not overlap plotted curves.")

    plt.close(fig)


def _assert_normalization_rules() -> None:
    expected_labels = {
        "time": "Time",
        "temperature": "Temperature",
        "angular frequency": "ω",
        "storage modulus": "G'",
        "loss modulus": 'G"',
        "count": "Counts",
    }
    for raw, expected in expected_labels.items():
        actual = normalize_label(raw)
        if actual != expected:
            raise AssertionError(f"Label normalization drifted: {raw!r} -> {actual!r}, expected {expected!r}.")

    expected_units = {
        "rad/s": r"rad$\cdot$s$^{-1}$",
        "mpa": "MPa",
        "pa.s": r"Pa$\cdot$s",
        "cm-1": r"cm$^{-1}$",
        "[ppm]": "ppm",
        "counts": "counts",
    }
    for raw, expected in expected_units.items():
        actual = normalize_unit(raw)
        if actual != expected:
            raise AssertionError(f"Unit normalization drifted: {raw!r} -> {actual!r}, expected {expected!r}.")


def _assert_input_validation(base: Path) -> None:
    odd_curve = base / "invalid_curve_odd.csv"
    missing_y_curve = base / "invalid_curve_missing_y.csv"
    invalid_replicate = base / "invalid_replicate.csv"

    _write_invalid_curve_table_odd_columns(odd_curve)
    _write_invalid_curve_table_missing_y(missing_y_curve)
    _write_invalid_replicate_table(invalid_replicate)

    try:
        load_curve_table(odd_curve)
    except ValueError as exc:
        if "X/Y pairs" not in str(exc):
            raise AssertionError("Odd-column curve table should fail with an X/Y pair error.") from exc
    else:
        raise AssertionError("Odd-column curve table should not load successfully.")

    try:
        load_curve_table(missing_y_curve)
    except ValueError as exc:
        if "matching X/Y numeric data" not in str(exc):
            raise AssertionError("Mismatched X/Y data should fail with a numeric pair error.") from exc
    else:
        raise AssertionError("Curve table with only one numeric side should not load successfully.")

    try:
        load_replicate_table(invalid_replicate)
    except ValueError as exc:
        if "no numeric replicate values" not in str(exc):
            raise AssertionError("Invalid replicate columns should fail with a numeric replicate error.") from exc
    else:
        raise AssertionError("Replicate table with non-numeric values should not load successfully.")


def _assert_inspection_and_preflight(
    *,
    freq_path: Path,
    temp_path: Path,
    relax_path: Path,
    replicate_path: Path,
    heatmap_path: Path,
    tensile_path: Path,
    ftir_path: Path,
    wide_nmr_path: Path,
) -> None:
    if list_sheet_names(freq_path) != ["Sheet1"]:
        raise AssertionError("Excel sheet listing should expose the default Sheet1 sheet.")

    freq_inspection = inspect_input_file(freq_path)
    freq_recommendation = _top_recommendation_config(freq_inspection)
    if freq_inspection.model != "frequency_sweep":
        raise AssertionError("Frequency export should be recognized as frequency_sweep.")
    if freq_recommendation.template != "point_line":
        raise AssertionError("Frequency export should recommend point_line.")
    if (freq_recommendation.xscale, freq_recommendation.yscale) != ("log", "log"):
        raise AssertionError("Frequency export should recommend log/log point_line.")
    if len(freq_inspection.signals) < 2:
        raise AssertionError("Frequency export should expose recommendation signals for the wizard.")
    freq_options = _resolve_render_options(
        template=freq_recommendation.template,
        size=freq_recommendation.size,
        xscale=freq_recommendation.xscale,
        yscale=freq_recommendation.yscale,
        reverse_x=bool(freq_recommendation.reverse_x),
    )
    freq_preflight = preflight_render_request("point_line", freq_path, 0, freq_options)
    if freq_preflight.errors:
        raise AssertionError(f"Frequency preflight should succeed, got: {freq_preflight.errors}")
    if len(freq_preflight.output_filenames) != 4:
        raise AssertionError("Frequency preflight should predict 4 PDF outputs.")

    temp_inspection = inspect_input_file(temp_path)
    temp_recommendation = _top_recommendation_config(temp_inspection)
    if temp_inspection.model != "temperature_sweep":
        raise AssertionError("Temperature export should be recognized as temperature_sweep.")
    if temp_recommendation.size != "120x55":
        raise AssertionError("Temperature export should recommend the 120x55 preset.")
    if (temp_recommendation.xscale, temp_recommendation.yscale) != ("linear", "log"):
        raise AssertionError("Temperature export should recommend linear/log point_line.")

    relax_inspection = inspect_input_file(relax_path)
    relax_recommendation = _top_recommendation_config(relax_inspection)
    if relax_inspection.model != "stress_relaxation":
        raise AssertionError("Relaxation export should be recognized as stress_relaxation.")
    if (relax_recommendation.xscale, relax_recommendation.yscale) != ("log", "linear"):
        raise AssertionError("Relaxation export should recommend log/linear point_line.")

    replicate_inspection = inspect_input_file(replicate_path)
    replicate_recommendation = _top_recommendation_config(replicate_inspection)
    if replicate_inspection.model != "replicate_table":
        raise AssertionError("Replicate table should be recognized as replicate_table.")
    if replicate_recommendation.template != "box":
        raise AssertionError("Replicate table should default to box.")
    if len(replicate_inspection.signals) < 2:
        raise AssertionError("Replicate table should expose recommendation signals for the wizard.")

    heatmap_inspection = inspect_input_file(heatmap_path)
    heatmap_recommendation = _top_recommendation_config(heatmap_inspection)
    if heatmap_inspection.model != "heatmap_table":
        raise AssertionError("Heatmap long table should be recognized as heatmap_table.")
    if heatmap_recommendation.template != "heatmap":
        raise AssertionError("Heatmap table should recommend heatmap.")
    if len(heatmap_inspection.signals) < 2:
        raise AssertionError("Heatmap inspection should expose recommendation signals for the wizard.")

    ftir_inspection = inspect_input_file(ftir_path)
    ftir_recommendation = _top_recommendation_config(ftir_inspection)
    if ftir_recommendation.template != "stacked_curve":
        raise AssertionError("FTIR-like curve table should recommend stacked_curve.")
    if not ftir_recommendation.reverse_x:
        raise AssertionError("FTIR-like curve table should recommend reverse_x.")

    wide_nmr_inspection = inspect_input_file(wide_nmr_path)
    wide_nmr_recommendation = _top_recommendation_config(wide_nmr_inspection)
    if wide_nmr_recommendation.template != "segmented_stacked_curve":
        raise AssertionError("wide_nmr sidecar should recommend segmented_stacked_curve.")
    if len(wide_nmr_inspection.signals) < 2:
        raise AssertionError("wide_nmr inspection should expose recommendation signals for the wizard.")
    segmented_options = _resolve_render_options(
        template="segmented_stacked_curve",
        size=wide_nmr_recommendation.size,
        reverse_x=bool(wide_nmr_recommendation.reverse_x),
        baseline=wide_nmr_recommendation.baseline,
        use_sidecar=wide_nmr_recommendation.use_sidecar,
    )
    segmented_preflight = preflight_render_request(
        "segmented_stacked_curve",
        wide_nmr_path,
        0,
        segmented_options,
    )
    if segmented_preflight.errors:
        raise AssertionError(
            "segmented_stacked_curve preflight should succeed with sidecar, "
            f"got: {segmented_preflight.errors}"
        )

    missing_sidecar_options = _resolve_render_options(
        template="segmented_stacked_curve",
        size="60x110",
        reverse_x=True,
        baseline="linear_endpoints",
        use_sidecar=True,
    )
    missing_sidecar_preflight = preflight_render_request(
        "segmented_stacked_curve",
        tensile_path,
        0,
        missing_sidecar_options,
    )
    if not missing_sidecar_preflight.errors:
        raise AssertionError("segmented_stacked_curve preflight should fail when sidecar is required but missing.")
    if "sidecar config" not in missing_sidecar_preflight.errors[0]:
        raise AssertionError("Missing sidecar preflight error should be rewritten into user-facing English copy.")


def _sorted_limits(bounds: tuple[float, float]) -> tuple[float, float]:
    return (min(bounds), max(bounds))


def _assert_curve_padding(
    plot_fn,
    series_list,
    *,
    expect_log_y: bool = False,
    expect_zero_y_origin: bool = False,
) -> None:
    fig, ax = plot_fn(series_list)
    fig.canvas.draw()

    raw_x_min = min(float(series.data["x"].min()) for series in series_list)
    raw_x_max = max(float(series.data["x"].max()) for series in series_list)
    raw_y_min = min(float(series.data["y"].min()) for series in series_list)
    raw_y_max = max(float(series.data["y"].max()) for series in series_list)
    x_low, x_high = _sorted_limits(ax.get_xlim())
    y_low, y_high = _sorted_limits(ax.get_ylim())

    if not (x_low < raw_x_min and x_high > raw_x_max):
        raise AssertionError("Curve x-axis was not padded beyond the raw data bounds.")
    if not (y_low < raw_y_min and y_high > raw_y_max):
        raise AssertionError("Curve y-axis was not padded beyond the raw data bounds.")

    xticks = np.asarray(ax.get_xticks(), dtype=float)
    xticks = xticks[np.isfinite(xticks)]
    if xticks.size:
        if not (xticks.min() > x_low and xticks.max() < x_high):
            raise AssertionError("Curve x-axis should keep display padding unlabeled.")
        if xticks.min() > raw_x_min or xticks.max() < raw_x_max:
            raise AssertionError("Curve x-axis should still cover the raw data with labeled major ticks.")

    yticks = np.asarray(ax.get_yticks(), dtype=float)
    yticks = yticks[np.isfinite(yticks)]
    if expect_zero_y_origin:
        if not (y_low < 0.0):
            raise AssertionError("Tensile curve y-axis should leave unlabeled padding below 0.")
        if not np.any(np.isclose(yticks, 0.0)):
            raise AssertionError("Tensile curve should retain 0 as a visible y-axis major tick.")
        if not np.isclose(float(yticks.min()), 0.0):
            raise AssertionError("Tensile curve should keep 0 as the first visible labeled tick.")
    elif yticks.size and not (yticks.min() > y_low and yticks.max() < y_high):
        raise AssertionError("Curve y-axis should keep display padding unlabeled.")
    elif yticks.size and yticks.min() > raw_y_min:
        if not expect_log_y:
            raise AssertionError("Curve y-axis should still cover the raw data with labeled major ticks.")
    elif yticks.size and yticks.max() < raw_y_max:
        if not expect_log_y:
            raise AssertionError("Curve y-axis should still cover the raw data with labeled major ticks.")
    elif yticks.size and yticks.min() < y_low:
        raise AssertionError("Curve y-axis should not show ticks beyond the display bounds.")
    elif yticks.size and yticks.max() > y_high:
        raise AssertionError("Curve y-axis should not show ticks beyond the display bounds.")
    elif yticks.size and yticks.min() < raw_y_min:
        if expect_log_y:
            if not (yticks.max() < y_high):
                raise AssertionError("Log y-axis should keep its upper display padding unlabeled.")
        else:
            raise AssertionError("Linear curve y-axis should not show labels below the labeled lower bound.")

    visible_y_ticks = np.asarray(ax.get_yticks(), dtype=float)
    visible_y_ticks = visible_y_ticks[np.isfinite(visible_y_ticks)]
    if visible_y_ticks.size > 7:
        raise AssertionError("Visible y-axis major ticks should be capped at 7 or fewer.")

    plt.close(fig)


def _assert_stat_plot_tick_cap(groups) -> None:
    figures_axes = []
    try:
        for plot_fn in (plot_bar, plot_box, plot_violin):
            fig, ax = plot_fn(groups)
            fig.canvas.draw()
            figures_axes.append((plot_fn.__name__, fig, ax))
            visible_y_ticks = np.asarray(ax.get_yticks(), dtype=float)
            visible_y_ticks = visible_y_ticks[np.isfinite(visible_y_ticks)]
            if visible_y_ticks.size > 7:
                raise AssertionError(f"{plot_fn.__name__} should cap visible y-axis major ticks at 7 or fewer.")

        name_to_ax = {name: ax for name, _, ax in figures_axes}
        bar_ticks = np.asarray(name_to_ax["plot_bar"].get_yticks(), dtype=float)
        bar_ticks = bar_ticks[np.isfinite(bar_ticks)]
        if not np.any(np.isclose(bar_ticks, 0.0)):
            raise AssertionError("Bar plot should retain 0 as a visible y-axis major tick.")
        bar_low, _ = _sorted_limits(name_to_ax["plot_bar"].get_ylim())
        if not np.isclose(bar_low, 0.0):
            raise AssertionError("Bar plot should start its y-axis at 0.")

        box_ylim = tuple(float(value) for value in name_to_ax["plot_box"].get_ylim())
        violin_ylim = tuple(float(value) for value in name_to_ax["plot_violin"].get_ylim())
        if not np.allclose(box_ylim, violin_ylim):
            raise AssertionError("Box and violin plots should share the same adaptive y-axis range.")
        box_low, _ = _sorted_limits(box_ylim)
        if np.isclose(box_low, 0.0):
            raise AssertionError("Box and violin plots should no longer be forced to start at 0.")
        box_ticks = np.asarray(name_to_ax["plot_box"].get_yticks(), dtype=float)
        box_ticks = box_ticks[np.isfinite(box_ticks)]
        if not (box_ticks.min() > box_low):
            raise AssertionError("Box plot should keep its lower display padding unlabeled.")
    finally:
        for _, fig, _ in figures_axes:
            plt.close(fig)


def _assert_axis_frame_alignment(
    *,
    replicate_path: Path,
    tensile_path: Path,
    heatmap_path: Path,
    wide_nmr_path: Path,
) -> list[dict[str, object]]:
    from src.data_loader import load_heatmap_table

    groups = load_replicate_table(replicate_path)
    tensile_series = load_curve_table(tensile_path)
    heatmap_table = load_heatmap_table(heatmap_path)
    wide_nmr_series = load_curve_table(wide_nmr_path)
    wide_nmr_config = load_wide_nmr_config(wide_nmr_path)

    figures: list[plt.Figure] = []
    validation_reports: list[dict[str, object]] = []
    try:
        axis_frames: dict[str, np.ndarray] = {}
        for name, builder in (
            ("bar", lambda: plot_bar(groups)),
            ("box", lambda: plot_box(groups)),
            ("violin", lambda: plot_violin(groups)),
            ("curve", lambda: plot_tensile_curve(tensile_series)),
            ("heatmap", lambda: plot_heatmap(heatmap_table)),
        ):
            fig, ax = builder()
            figures.append(fig)
            fig.canvas.draw()
            axis_frames[name] = np.asarray(ax.get_position().bounds, dtype=float)

        reference = axis_frames["curve"]
        single_panel_tolerance_mm = validation_rule("single_panel_axis_frame").tolerance_mm or 0.05
        for name, frame in axis_frames.items():
            if not np.allclose(frame, reference, atol=5e-6):
                raise AssertionError(f"{name} drifted away from the shared single-panel axis frame.")

        reference_fig = figures[0]
        reference_width_mm = reference_fig.get_size_inches()[0] * 25.4
        reference_height_mm = reference_fig.get_size_inches()[1] * 25.4
        reference_left_mm = reference[0] * reference_width_mm
        reference_right_mm = (1.0 - (reference[0] + reference[2])) * reference_width_mm
        reference_bottom_mm = reference[1] * reference_height_mm
        reference_top_mm = (1.0 - (reference[1] + reference[3])) * reference_height_mm
        validation_reports.append(
            _validation_result(
                "single_panel_axis_frame",
                passed=True,
                details={
                    "reference_template": "curve",
                    "reference_edges_mm": {
                        "left": round(reference_left_mm, 3),
                        "right": round(reference_right_mm, 3),
                        "bottom": round(reference_bottom_mm, 3),
                        "top": round(reference_top_mm, 3),
                    },
                    "checked_templates": {
                        name: {
                            "left": round(frame[0] * reference_width_mm, 3),
                            "right": round((1.0 - (frame[0] + frame[2])) * reference_width_mm, 3),
                            "bottom": round(frame[1] * reference_height_mm, 3),
                            "top": round((1.0 - (frame[1] + frame[3])) * reference_height_mm, 3),
                        }
                        for name, frame in axis_frames.items()
                    },
                    "tolerance_mm": single_panel_tolerance_mm,
                },
            )
        )

        heatmap_fig = figures[-1]
        heatmap_renderer = heatmap_fig.canvas.get_renderer()
        heatmap_canvas = heatmap_fig.bbox
        heatmap_cbar_ax = heatmap_fig.axes[-1]
        heatmap_cbar_bbox = heatmap_cbar_ax.get_tightbbox(renderer=heatmap_renderer)
        validation_reports.append(
            _validation_result(
                "heatmap_main_frame",
                passed=True,
                details={
                    "edges_mm": {
                        "left": round(axis_frames["heatmap"][0] * reference_width_mm, 3),
                        "right": round(
                            (1.0 - (axis_frames["heatmap"][0] + axis_frames["heatmap"][2]))
                            * reference_width_mm,
                            3,
                        ),
                        "bottom": round(axis_frames["heatmap"][1] * reference_height_mm, 3),
                        "top": round(
                            (1.0 - (axis_frames["heatmap"][1] + axis_frames["heatmap"][3]))
                            * reference_height_mm,
                            3,
                        ),
                    },
                    "reference_edges_mm": {
                        "left": round(reference_left_mm, 3),
                        "right": round(reference_right_mm, 3),
                        "bottom": round(reference_bottom_mm, 3),
                        "top": round(reference_top_mm, 3),
                    },
                },
            )
        )
        if (
            heatmap_cbar_bbox.x0 < heatmap_canvas.x0
            or heatmap_cbar_bbox.x1 > heatmap_canvas.x1
            or heatmap_cbar_bbox.y0 < heatmap_canvas.y0
            or heatmap_cbar_bbox.y1 > heatmap_canvas.y1
        ):
            raise AssertionError("Heatmap top colorbar should stay inside the figure canvas.")
        validation_reports.append(
            _validation_result(
                "heatmap_colorbar_inside_canvas",
                passed=True,
                details={
                    "colorbar_bbox_px": {
                        "x0": round(float(heatmap_cbar_bbox.x0), 3),
                        "x1": round(float(heatmap_cbar_bbox.x1), 3),
                        "y0": round(float(heatmap_cbar_bbox.y0), 3),
                        "y1": round(float(heatmap_cbar_bbox.y1), 3),
                    },
                    "canvas_bbox_px": {
                        "x0": round(float(heatmap_canvas.x0), 3),
                        "x1": round(float(heatmap_canvas.x1), 3),
                        "y0": round(float(heatmap_canvas.y0), 3),
                        "y1": round(float(heatmap_canvas.y1), 3),
                    },
                },
            )
        )
        if heatmap_cbar_bbox.width <= heatmap_cbar_bbox.height:
            raise AssertionError("Heatmap colorbar should remain horizontal.")
        validation_reports.append(
            _validation_result(
                "heatmap_horizontal_colorbar",
                passed=True,
                details={
                    "width_px": round(float(heatmap_cbar_bbox.width), 3),
                    "height_px": round(float(heatmap_cbar_bbox.height), 3),
                },
            )
        )

        expected_heatmap_label = _format_axis_label(heatmap_table.z_label, heatmap_table.z_unit)
        heatmap_labels = [text for text in heatmap_fig.texts if text.get_text() == expected_heatmap_label]
        if len(heatmap_labels) != 1:
            raise AssertionError("Heatmap should render one explicit top-strip z label.")
        label_bbox = heatmap_labels[0].get_window_extent(renderer=heatmap_renderer)
        if (
            label_bbox.x0 < heatmap_canvas.x0
            or label_bbox.x1 > heatmap_canvas.x1
            or label_bbox.y0 < heatmap_canvas.y0
            or label_bbox.y1 > heatmap_canvas.y1
        ):
            raise AssertionError("Heatmap top-strip z label should stay inside the figure canvas.")

        wide_fig, _ = plot_wide_nmr(wide_nmr_series, wide_nmr_config)
        figures.append(wide_fig)
        wide_fig.canvas.draw()
        left_axis = wide_fig.axes[0]
        right_axis = wide_fig.axes[-1]
        left_frame = np.asarray(left_axis.get_position().bounds, dtype=float)
        right_frame = np.asarray(right_axis.get_position().bounds, dtype=float)
        wide_width_mm = wide_fig.get_size_inches()[0] * 25.4
        wide_height_mm = wide_fig.get_size_inches()[1] * 25.4
        wide_left_mm = left_frame[0] * wide_width_mm
        wide_right_mm = (1.0 - (right_frame[0] + right_frame[2])) * wide_width_mm
        wide_bottom_mm = left_frame[1] * wide_height_mm
        wide_top_mm = (1.0 - (left_frame[1] + left_frame[3])) * wide_height_mm
        if not np.isclose(wide_left_mm, reference_left_mm, atol=0.05):
            raise AssertionError("wide_nmr should share the same left axis anchor as the standard single-panel frame.")
        if not np.isclose(wide_right_mm, reference_right_mm, atol=0.05):
            raise AssertionError("wide_nmr should share the same right axis anchor as the standard single-panel frame.")
        if not np.isclose(wide_bottom_mm, reference_bottom_mm, atol=0.05):
            raise AssertionError(
                "wide_nmr should share the same bottom axis anchor as the standard single-panel frame."
            )
        validation_reports.append(
            _validation_result(
                "wide_nmr_horizontal_alignment",
                passed=True,
                details={
                    "edges_mm": {
                        "left": round(wide_left_mm, 3),
                        "right": round(wide_right_mm, 3),
                        "bottom": round(wide_bottom_mm, 3),
                        "top": round(wide_top_mm, 3),
                    },
                    "reference_edges_mm": {
                        "left": round(reference_left_mm, 3),
                        "right": round(reference_right_mm, 3),
                        "bottom": round(reference_bottom_mm, 3),
                        "top": round(reference_top_mm, 3),
                    },
                },
            )
        )
        segment_bottoms = [axis.get_position().y0 for axis in wide_fig.axes]
        segment_tops = [axis.get_position().y1 for axis in wide_fig.axes]
        if not np.allclose(segment_bottoms, segment_bottoms[0], atol=5e-6):
            raise AssertionError("wide_nmr segment axes should align on a common bottom edge.")
        if not np.allclose(segment_tops, segment_tops[0], atol=5e-6):
            raise AssertionError("wide_nmr segment axes should align on a common top edge.")
        validation_reports.append(
            _validation_result(
                "wide_nmr_segment_alignment",
                passed=True,
                details={
                    "segment_bottoms": [round(float(item), 6) for item in segment_bottoms],
                    "segment_tops": [round(float(item), 6) for item in segment_tops],
                },
            )
        )
    finally:
        for fig in figures:
            plt.close(fig)
    return validation_reports


def _assert_major_tick_skip_every_other() -> None:
    ticks = np.array([0, 1, 2, 3, 4, 5, 6], dtype=float)
    kept = _cap_visible_major_ticks(ticks, scale="linear", max_major_ticks=7)
    expected = np.array([0, 1, 2, 3, 4, 5, 6], dtype=float)
    if not np.array_equal(kept, expected):
        raise AssertionError(
            "Seven visible y-axis ticks should remain intact when they already fit the cap."
        )


def _assert_style_palette_presets(
    *,
    replicate_path: Path,
    tensile_path: Path,
    ftir_path: Path,
    wide_nmr_path: Path,
    heatmap_path: Path,
    temp_path: Path,
) -> None:
    contract = load_plot_contract()

    def _allowed_palette(template_name: str, preferred: str) -> str:
        template_spec = contract.templates[template_name]
        if preferred in template_spec.available_palettes:
            return preferred
        return template_spec.available_palettes[-1]

    combos = [
        (
            "point_line",
            temp_path,
            {"yscale": "log", "style_preset": "default", "palette_preset": "colorblind_safe"},
        ),
        (
            "point_line",
            temp_path,
            {"yscale": "log", "style_preset": "nature", "palette_preset": "colorblind_safe"},
        ),
        ("bar", replicate_path, {"style_preset": "default", "palette_preset": "deep"}),
        ("box", replicate_path, {"style_preset": "nature", "palette_preset": "mono"}),
        (
            "stacked_curve",
            ftir_path,
            {
                "reverse_x": True,
                "style_preset": "default",
                "palette_preset": _allowed_palette("stacked_curve", "materials_warm"),
            },
        ),
        (
            "segmented_stacked_curve",
            wide_nmr_path,
            {
                "reverse_x": True,
                "baseline": "linear_endpoints",
                "use_sidecar": True,
                "style_preset": "nature",
                "palette_preset": _allowed_palette("segmented_stacked_curve", "okabe_ito"),
            },
        ),
        (
            "heatmap",
            heatmap_path,
            {
                "style_preset": "default",
                "palette_preset": _allowed_palette("heatmap", "materials_warm"),
            },
        ),
    ]

    for template, input_path, options in combos:
        rendered = build_rendered_plots(template, input_path, 0, **options)
        try:
            expected_style_preset = plot_style.normalize_style_preset(options["style_preset"])
            if plot_style.current_style_preset() != expected_style_preset:
                raise AssertionError("Style preset should follow the normalized explicit render option.")
            if plot_style.current_palette_preset() != options["palette_preset"]:
                raise AssertionError("Palette preset should follow the explicit render option.")
            if not rendered:
                raise AssertionError(f"{template} should render at least one figure for style/palette regression.")
        finally:
            for item in rendered:
                plt.close(item.figure)

    rendered = build_rendered_plots(
        "point_line",
        temp_path,
        0,
        yscale="log",
        style_preset="nature",
        palette_preset="colorblind_safe",
        visual_theme_id="clean_light",
        extra_x_axis={
            "enabled": True,
            "position": "top",
            "title": "Scaled Frequency",
            "data_value": 10.0,
            "display_value": 1.0,
        },
        extra_y_axis={
            "enabled": True,
            "position": "right",
            "title": "Scaled Modulus",
            "data_value": 1000.0,
            "display_value": 1.0,
        },
    )
    try:
        if not rendered:
            raise AssertionError("Extra-axis smoke case should render at least one figure.")
        qa_report = rendered[0].qa_report
        if qa_report is None or "extra_axis_overlay" not in qa_report.autofixes_applied:
            raise AssertionError("Extra-axis smoke case should report the extra-axis overlay autofix.")
        if len(rendered[0].figure.axes[0].child_axes) < 2:
            raise AssertionError("Extra-axis smoke case should materialize secondary axes.")
    finally:
        close_rendered_plots(rendered)

    rendered = build_rendered_plots(
        "curve",
        tensile_path,
        0,
        style_preset="nature",
        palette_preset="colorblind_safe",
        visual_theme_id="clean_light",
        fit_options={"enabled": True, "model_id": "linear"},
        extra_y_axis={
            "enabled": True,
            "position": "right",
            "binding_mode": "series_assignment",
            "series_ids": ["Sample B"],
            "title": "Secondary Stress",
        },
    )
    try:
        if not rendered:
            raise AssertionError("Double-Y smoke case should render at least one figure.")
        qa_report = rendered[0].qa_report
        if qa_report is None or "extra_axis_series_assignment" not in qa_report.autofixes_applied:
            raise AssertionError("Double-Y smoke case should report the series-assignment autofix.")
        if len(rendered[0].figure.axes) < 2:
            raise AssertionError("Double-Y smoke case should materialize a secondary Y axis.")
        primary_ax, secondary_ax = rendered[0].figure.axes[0], rendered[0].figure.axes[1]
        if [line.get_label() for line in primary_ax.lines if line.get_label() != "_nolegend_"] != ["Sample A"]:
            raise AssertionError("Double-Y smoke case should keep Sample A on the primary axis.")
        if [line.get_label() for line in secondary_ax.lines if line.get_label() != "_nolegend_"] != ["Sample B"]:
            raise AssertionError("Double-Y smoke case should move Sample B onto the secondary axis.")
    finally:
        close_rendered_plots(rendered)

    groups = load_replicate_table(replicate_path)
    plot_style.apply_style("nature", "mono")
    mono_fig, mono_ax = plot_bar(groups)
    try:
        mono_expected = plot_style.get_palette_spec("mono").categorical[0].lower()
        mono_actual = to_hex(mono_ax.patches[0].get_facecolor(), keep_alpha=False).lower()
        if mono_actual != mono_expected:
            raise AssertionError("Bar plot should respect the selected mono categorical palette.")
    finally:
        plt.close(mono_fig)

    heatmap_table = inspect_input_file(heatmap_path)
    if _top_recommendation_config(heatmap_table).template != "heatmap":
        raise AssertionError("Heatmap inspection should still recommend heatmap during style regression.")
    from src.data_loader import load_heatmap_table  # local import to keep top import list compact

    plot_style.apply_style("default", "materials_warm")
    heatmap_fig, heatmap_ax = plot_heatmap(load_heatmap_table(heatmap_path))
    try:
        mesh = heatmap_ax.collections[0]
        if mesh.cmap.name != plot_style.get_sequential_cmap("materials_warm"):
            raise AssertionError("Heatmap should respect the selected sequential palette preset.")

        if len(heatmap_fig.axes) < 2:
            raise AssertionError("Heatmap should create an explicit in-figure colorbar axis.")
        cbar_ax = heatmap_fig.axes[-1]
        renderer = heatmap_fig.canvas.get_renderer()
        fig_bbox = heatmap_fig.bbox
        label_bbox = cbar_ax.get_tightbbox(renderer=renderer)
        if (
            label_bbox.x0 < fig_bbox.x0
            or label_bbox.x1 > fig_bbox.x1
            or label_bbox.y0 < fig_bbox.y0
            or label_bbox.y1 > fig_bbox.y1
        ):
            raise AssertionError("Heatmap colorbar strip should stay inside the figure canvas.")

        heatmap_table = load_heatmap_table(heatmap_path)
        expected_label = _format_axis_label(heatmap_table.z_label, heatmap_table.z_unit)
        matching_labels = [text for text in heatmap_fig.texts if text.get_text() == expected_label]
        if len(matching_labels) != 1:
            raise AssertionError("Heatmap should render one explicit top-strip z label.")
        top_label_bbox = matching_labels[0].get_window_extent(renderer=renderer)
        if (
            top_label_bbox.x0 < fig_bbox.x0
            or top_label_bbox.x1 > fig_bbox.x1
            or top_label_bbox.y0 < fig_bbox.y0
            or top_label_bbox.y1 > fig_bbox.y1
        ):
            raise AssertionError("Heatmap top-strip z label should stay inside the figure canvas.")
    finally:
        plt.close(heatmap_fig)


def _assert_public_template_contract_lint() -> list[dict[str, object]]:
    issues = list(lint_public_template_contract())
    if issues:
        joined = "; ".join(issues)
        raise AssertionError(f"Public template contract lint failed: {joined}")
    return [
        {
            "id": "public_template_contract_lint",
            "passed": True,
            "issue_count": 0,
        }
    ]


def _style_theme_template_matrix(
    *,
    tensile_path: Path,
    replicate_path: Path,
    heatmap_path: Path,
) -> list[dict[str, object]]:
    cases = [
        (
            "curve",
            tensile_path,
            {"style_preset": "nature", "palette_preset": "colorblind_safe", "visual_theme_id": "clean_light"},
        ),
        (
            "curve",
            tensile_path,
            {
                "style_preset": "presentation",
                "palette_preset": "infographic",
                "visual_theme_id": "presentation_like",
            },
        ),
        (
            "area_curve",
            tensile_path,
            {"style_preset": "nature", "palette_preset": "colorblind_safe", "visual_theme_id": "clean_light"},
        ),
        (
            "area_curve",
            tensile_path,
            {
                "style_preset": "presentation",
                "palette_preset": "infographic",
                "visual_theme_id": "presentation_like",
            },
        ),
        (
            "step_line",
            tensile_path,
            {"style_preset": "nature", "palette_preset": "colorblind_safe", "visual_theme_id": "clean_light"},
        ),
        (
            "step_line",
            tensile_path,
            {"style_preset": "editorial", "palette_preset": "roma", "visual_theme_id": "roma"},
        ),
        (
            "bar",
            replicate_path,
            {"style_preset": "nature", "palette_preset": "colorblind_safe", "visual_theme_id": "clean_light"},
        ),
        (
            "bar",
            replicate_path,
            {"style_preset": "poster", "palette_preset": "shine", "visual_theme_id": "shine"},
        ),
        (
            "scatter",
            tensile_path,
            {"style_preset": "nature", "palette_preset": "colorblind_safe", "visual_theme_id": "clean_light"},
        ),
        (
            "scatter",
            tensile_path,
            {
                "style_preset": "presentation",
                "palette_preset": "infographic",
                "visual_theme_id": "presentation_like",
            },
        ),
        (
            "heatmap",
            heatmap_path,
            {"style_preset": "nature", "palette_preset": "colorblind_safe", "visual_theme_id": "clean_light"},
        ),
        (
            "heatmap",
            heatmap_path,
            {"style_preset": "poster", "palette_preset": "shine", "visual_theme_id": "shine"},
        ),
    ]

    manifest: list[dict[str, object]] = []
    for template, input_path, options in cases:
        rendered = build_rendered_plots(template, input_path, 0, **options)
        try:
            if not rendered:
                raise AssertionError(f"{template} matrix case should render at least one figure.")
            manifest.append(
                {
                    "template": template,
                    "input_path": _repo_relative_path(input_path),
                    "style_preset": options["style_preset"],
                    "palette_preset": options["palette_preset"],
                    "visual_theme_id": options["visual_theme_id"],
                    "output_filenames": [plot.filename for plot in rendered],
                    "qa_grades": [plot.qa_report.grade if plot.qa_report is not None else None for plot in rendered],
                }
            )
        finally:
            close_rendered_plots(rendered)

    coverage_by_template: dict[str, dict[str, set[str]]] = {}
    for item in manifest:
        template = str(item["template"])
        coverage = coverage_by_template.setdefault(template, {"styles": set(), "combos": set()})
        coverage["styles"].add(str(item["style_preset"]))
        coverage["combos"].add(f"{item['palette_preset']}::{item['visual_theme_id']}")

    for template, coverage in coverage_by_template.items():
        if "nature" not in coverage["styles"]:
            raise AssertionError(f"{template} matrix must include a Nature style case.")
        if len(coverage["styles"]) < 2:
            raise AssertionError(f"{template} matrix must include at least one non-Nature style case.")
        if len(coverage["combos"]) < 2:
            raise AssertionError(f"{template} matrix must include at least two palette/theme combinations.")

    return manifest


def _assert_axis_break_overlays(tensile_path: Path) -> list[dict[str, object]]:
    reports: list[dict[str, object]] = []

    curve = build_rendered_plots(
        "curve",
        tensile_path,
        0,
        x_axis_breaks=[{"id": "x-gap", "enabled": True, "start": 4.0, "end": 6.0}],
        y_axis_breaks=[{"id": "y-gap", "enabled": True, "start": 2.2, "end": 2.8}],
        reference_guides=[
            {
                "id": "target-line",
                "enabled": True,
                "kind": "line",
                "axis_target": "y_primary",
                "value": 3.0,
                "label": "Target",
            }
        ],
        text_annotations=[
            {
                "id": "note-1",
                "enabled": True,
                "text": "Peak",
                "coordinate_space": "data",
                "x": 8.0,
                "y": 3.1,
                "y_axis_target": "y_primary",
                "horizontal_alignment": "right",
                "vertical_alignment": "bottom",
            }
        ],
        shape_annotations=[
            {
                "id": "focus-window",
                "enabled": True,
                "kind": "rectangle",
                "x_start": 2.0,
                "x_end": 7.5,
                "y_start": 2.4,
                "y_end": 3.3,
                "label": "Window",
            }
        ],
    )
    try:
        plot = curve[0]
        ax = plot.figure.axes[0]
        autofixes = set(plot.qa_report.autofixes_applied) if plot.qa_report is not None else set()
        visible_texts = {text.get_text() for text in ax.texts if text.get_visible()}
        if "axis_break_overlay" not in autofixes:
            raise AssertionError(f"curve axis break overlay was not applied; autofixes={sorted(autofixes)}")
        if "shape_annotation_overlay" not in autofixes:
            raise AssertionError(f"curve shape annotation overlay was not applied; autofixes={sorted(autofixes)}")
        if ax.get_xlim()[1] >= 10.0:
            raise AssertionError(f"curve x axis break did not compress display limits: xlim={ax.get_xlim()}")
        if not {"Peak", "Window"}.issubset(visible_texts):
            raise AssertionError(f"curve overlay labels missing: visible_texts={sorted(visible_texts)}")
    finally:
        close_rendered_plots(curve)

    split_curve = build_rendered_plots(
        "curve",
        tensile_path,
        0,
        x_axis_breaks=[{"id": "x-gap", "enabled": True, "start": 4.0, "end": 6.0, "display_mode": "split"}],
        reference_guides=[
            {
                "id": "target-line",
                "enabled": True,
                "kind": "line",
                "axis_target": "y_primary",
                "value": 3.0,
                "label": "Target",
            }
        ],
        text_annotations=[
            {
                "id": "note-1",
                "enabled": True,
                "text": "Peak",
                "coordinate_space": "data",
                "x": 8.0,
                "y": 3.1,
                "y_axis_target": "y_primary",
                "horizontal_alignment": "right",
                "vertical_alignment": "bottom",
            }
        ],
        shape_annotations=[
            {
                "id": "focus-window",
                "enabled": True,
                "kind": "ellipse",
                "x_start": 2.0,
                "x_end": 8.0,
                "y_start": 2.4,
                "y_end": 3.3,
                "label": "Window",
            },
            {
                "id": "significance",
                "enabled": True,
                "kind": "bracket",
                "bracket_orientation": "horizontal",
                "x_start": 6.5,
                "x_end": 8.5,
                "y_start": 3.35,
                "y_end": 3.35,
                "label": "p < 0.05",
            }
        ],
    )
    try:
        plot = split_curve[0]
        visible_texts = {
            text.get_text()
            for axis in plot.figure.axes
            for text in axis.texts
            if text.get_visible()
        }
        autofixes = set(plot.qa_report.autofixes_applied) if plot.qa_report is not None else set()
        if "axis_break_split_layout" not in autofixes:
            raise AssertionError(f"split axis break layout was not applied; autofixes={sorted(autofixes)}")
        if "shape_annotation_overlay" not in autofixes:
            raise AssertionError(f"split shape annotation overlay was not applied; autofixes={sorted(autofixes)}")
        if len(plot.figure.axes) < 2:
            raise AssertionError(f"split axis break should render multiple axes; axis_count={len(plot.figure.axes)}")
        if not {"Peak", "Window", "p < 0.05"}.issubset(visible_texts):
            raise AssertionError(f"split overlay labels missing: visible_texts={sorted(visible_texts)}")
    finally:
        close_rendered_plots(split_curve)

    scatter = build_rendered_plots(
        "scatter",
        tensile_path,
        0,
        x_axis_breaks=[{"id": "x-gap", "enabled": True, "start": 4.0, "end": 6.0}],
    )
    try:
        ax = scatter[0].figure.axes[0]
        visible_points = 0
        for collection in ax.collections:
            offsets = np.asarray(collection.get_offsets())
            if offsets.ndim == 2:
                visible_points += int(offsets.shape[0])
        if visible_points <= 0 or visible_points >= 160:
            raise AssertionError(f"scatter axis break rendered unexpected visible points: {visible_points}")
    finally:
        close_rendered_plots(scatter)

    return reports


def _assert_frequency_batch_sync(freq_path: Path) -> None:
    metric_series = {
        metric_name: _to_curve_series(series_list)
        for metric_name, series_list in load_frequency_sweep_metrics(freq_path).items()
    }
    shared_x_layout = compute_shared_curve_x_layout(
        [
            series.data["x"].to_numpy(dtype=float)
            for metric_name in ("storage_modulus", "loss_modulus", "loss_factor", "complex_viscosity")
            for series in metric_series[metric_name]
        ],
        xscale="log",
    )

    xlims: list[tuple[float, float]] = []
    xticks_list: list[np.ndarray] = []
    right_insets: list[float] = []
    top_bottom_insets: list[float] = []

    for metric_name in ("storage_modulus", "loss_modulus", "loss_factor", "complex_viscosity"):
        fig, ax = plot_frequency_sweep(
            metric_series[metric_name],
            xlim=shared_x_layout.display_bounds,
            visible_xticks=shared_x_layout.visible_ticks,
            legend_expand_axes="y",
        )
        fig.canvas.draw()
        xlims.append(tuple(float(value) for value in ax.get_xlim()))
        xticks_list.append(np.asarray(ax.get_xticks(), dtype=float))

        legend = ax.get_legend()
        if legend is None:
            raise AssertionError("Frequency sweep should still render an inside legend.")
        renderer = fig.canvas.get_renderer()
        axes_bbox = ax.get_window_extent(renderer=renderer)
        legend_bbox = legend.get_window_extent(renderer=renderer)
        right_insets.append(
            min(abs(axes_bbox.x1 - legend_bbox.x1), abs(legend_bbox.x0 - axes_bbox.x0)) / axes_bbox.width
        )
        top_bottom_insets.append(
            min(abs(axes_bbox.y1 - legend_bbox.y1), abs(legend_bbox.y0 - axes_bbox.y0)) / axes_bbox.height
        )
        plt.close(fig)

    if any(not np.allclose(bounds, xlims[0]) for bounds in xlims[1:]):
        raise AssertionError("Frequency sweep batch should share identical x limits across all metrics.")
    if any(not np.array_equal(ticks, xticks_list[0]) for ticks in xticks_list[1:]):
        raise AssertionError("Frequency sweep batch should share identical visible x ticks across all metrics.")

    inset_tolerance = 0.01
    target_inset = INSIDE_LEGEND_INSET_FRACTION
    if any(abs(inset - target_inset) > inset_tolerance for inset in right_insets + top_bottom_insets):
        raise AssertionError("Frequency sweep legends are no longer anchored near the configured 2.5% inset.")


def _assert_tensile_preprocess_workflow(
    *,
    base: Path,
    outputs_dir: Path,
    template_by_output: dict[str, str],
) -> list[dict[str, object]]:
    valid_a = TENSILE_RAW_FIXTURE_DIR / "BlendSet_A.csv"
    valid_b = TENSILE_RAW_FIXTURE_DIR / "BlendSet_B.csv"
    invalid_bad = TENSILE_RAW_FIXTURE_DIR / "BlendSet_bad.csv"
    invalid_no_curve = TENSILE_RAW_FIXTURE_DIR / "BlendSet_nocurve.csv"
    required_fixtures = (valid_a, valid_b, invalid_bad, invalid_no_curve)
    missing = [path for path in required_fixtures if not path.exists()]
    if missing:
        raise FileNotFoundError(
            "Tensile preprocess smoke fixtures are missing: "
            + ", ".join(_repo_relative_path(path) for path in missing)
        )

    preprocess_dir = base / "tensile_preprocess"
    preprocess_dir.mkdir(parents=True, exist_ok=True)
    reports: list[dict[str, object]] = []
    successful_cases = (
        (
            "all_valid",
            (valid_a, valid_b),
            2,
            0,
            "BlendSet",
        ),
        (
            "mixed_valid_invalid",
            (valid_a, valid_b, invalid_bad),
            2,
            1,
            "BlendSet",
        ),
    )

    for case_id, input_paths, expected_samples, expected_warnings, expected_group in successful_cases:
        workbook_path = preprocess_dir / f"{case_id}.xlsx"
        result = export_tensile_replicate_workbook(input_paths, workbook_path)
        if not result.output_path.exists():
            raise AssertionError(f"{case_id} should write a workbook for the wizard.")
        if result.group_name != expected_group:
            raise AssertionError(
                f"{case_id} inferred group name drifted: {result.group_name!r} != {expected_group!r}."
            )
        if result.sample_count != expected_samples:
            raise AssertionError(
                f"{case_id} should keep {expected_samples} parsed samples, got {result.sample_count}."
            )
        if len(result.warnings) != expected_warnings:
            raise AssertionError(
                f"{case_id} should surface {expected_warnings} warnings, got {len(result.warnings)}."
            )
        if set(result.sheet_names) != TENSILE_WORKBOOK_SHEETS:
            raise AssertionError(f"{case_id} workbook sheets drifted away from the tensile export contract.")
        if result.preferred_sheet != "Representative_Curve" or result.preferred_sheet not in result.sheet_names:
            raise AssertionError(f"{case_id} should default the wizard to Representative_Curve.")
        if result.representative_filename not in {valid_a.name, valid_b.name}:
            raise AssertionError(f"{case_id} representative sample should come from a valid raw CSV.")

        if case_id == "mixed_valid_invalid":
            warning_text = "\n".join(result.warnings)
            if invalid_bad.name not in warning_text:
                raise AssertionError("Mixed tensile preprocess warnings should name the skipped invalid raw CSV.")

        inspection = inspect_input_file(result.output_path, result.preferred_sheet)
        recommendation = _top_recommendation_config(inspection)
        if inspection.model != "tensile_curve":
            raise AssertionError(f"{case_id} workbook should load back into the wizard as a tensile curve.")
        if recommendation.template != "curve":
            raise AssertionError(f"{case_id} representative sheet should recommend the standard curve template.")
        if recommendation.xscale != "linear" or recommendation.yscale != "linear":
            raise AssertionError(f"{case_id} tensile workbook should recommend linear x/y scales.")
        options = _resolve_render_options(
            template=recommendation.template,
            size=recommendation.size,
            xscale=recommendation.xscale,
            yscale=recommendation.yscale,
            reverse_x=bool(recommendation.reverse_x),
            baseline=recommendation.baseline,
            show_colorbar=recommendation.show_colorbar,
            use_sidecar=recommendation.use_sidecar,
        )
        preflight = preflight_render_request(
            recommendation.template,
            result.output_path,
            result.preferred_sheet,
            options,
        )
        if preflight.errors:
            raise AssertionError(f"{case_id} workbook should pass preflight, got: {preflight.errors}")

        render_outputs = render_template(
            recommendation.template,
            result.output_path,
            outputs_dir / f"tensile_preprocess_{case_id}",
            result.preferred_sheet,
            size=recommendation.size,
            xscale=recommendation.xscale,
            yscale=recommendation.yscale,
            reverse_x=bool(recommendation.reverse_x),
            baseline=recommendation.baseline,
            show_colorbar=recommendation.show_colorbar,
            use_sidecar=recommendation.use_sidecar,
        )
        if not render_outputs:
            raise AssertionError(f"{case_id} workbook should remain renderable after preprocess.")
        for output in render_outputs:
            if not output.exists() or output.stat().st_size <= 0:
                raise AssertionError(f"{case_id} downstream render produced an empty PDF: {output.name}")
            template_by_output[str(output)] = recommendation.template

        reports.append(
            {
                "case_id": case_id,
                "status": "passed",
                "input_files": [_repo_relative_path(path) for path in input_paths],
                "output_path": str(result.output_path),
                "group_name": result.group_name,
                "preferred_sheet": result.preferred_sheet,
                "sheet_names": list(result.sheet_names),
                "sample_count": result.sample_count,
                "representative_filename": result.representative_filename,
                "warnings_count": len(result.warnings),
                "warnings": list(result.warnings),
                "downstream": {
                    "inspection_model": inspection.model,
                    "recommended_template": recommendation.template,
                    "preflight_warnings": list(preflight.warnings),
                    "render_outputs": [str(path) for path in render_outputs],
                },
            }
        )

    failed_case_output = preprocess_dir / "all_invalid.xlsx"
    try:
        export_tensile_replicate_workbook((invalid_bad, invalid_no_curve), failed_case_output)
    except ValueError as exc:
        message = str(exc)
        if "No tensile CSV files could be parsed successfully" not in message:
            raise AssertionError(
                "All-invalid tensile preprocess should fail with a user-facing aggregate error."
            ) from exc
        if failed_case_output.exists():
            raise AssertionError(
                "All-invalid tensile preprocess should not leave behind an empty workbook."
            ) from exc
        reports.append(
            {
                "case_id": "all_invalid",
                "status": "blocked",
                "input_files": [
                    _repo_relative_path(invalid_bad),
                    _repo_relative_path(invalid_no_curve),
                ],
                "error": message,
                "generated_workbook": False,
            }
        )
    else:
        raise AssertionError("All-invalid tensile preprocess should fail instead of creating a workbook.")

    return reports


def _assert_composer_workflow(outputs_dir: Path, base: Path) -> None:
    graph_paths = [
        outputs_dir / "point_line" / "freq_storage_modulus.pdf",
        outputs_dir / "point_line" / "freq_loss_modulus.pdf",
        outputs_dir / "bar" / "tensile_modulus_bar.pdf",
    ]
    if any(not path.exists() for path in graph_paths):
        raise AssertionError("Composer smoke test requires rendered graph PDFs to exist.")

    project = three_up_panels_from_paths(graph_paths)
    ok, reason = validate_non_overlapping_panels(project)
    if not ok:
        raise AssertionError(f"Three-up composer layout should be valid: {reason}")
    if [round(panel.x_mm, 1) for panel in project.panels] != [0.0, 60.0, 120.0]:
        raise AssertionError("Three-up composer layout should snap graph panels to 0/60/120 mm.")
    if any(panel.kind != "graph" for panel in project.panels):
        raise AssertionError("Three-up composer layout should create graph panels only.")
    if len(project.regions) != 3:
        raise AssertionError("Three-up composer layout should create one region per graph panel.")

    editorial_project = two_up_editorial_panels_from_paths(graph_paths[:2])
    ok, reason = validate_non_overlapping_panels(editorial_project)
    if not ok:
        raise AssertionError(f"Two-up editorial composer layout should be valid: {reason}")
    editorial_panels = editorial_project.panels
    if [round(panel.x_mm, 1) for panel in editorial_panels] != [0.0, 60.0]:
        raise AssertionError("Two-up editorial layout should snap graph panels to 0/60 mm.")
    if len(editorial_panels) != 2 or any(panel.kind != "graph" for panel in editorial_panels):
        raise AssertionError("Two-up editorial layout should create exactly two graph panels.")
    if len([region for region in editorial_project.regions if region.kind == "free"]) != 1:
        raise AssertionError("Two-up editorial layout should create one free editorial region.")

    asset_paths = [
        outputs_dir / "heatmap" / "heatmap_heatmap.pdf",
        outputs_dir / "stacked_curve" / "ftir_stacked_curve.pdf",
    ]
    if any(not path.exists() for path in asset_paths):
        raise AssertionError("Composer smoke test requires asset-import PDFs to exist.")
    project = import_panels_from_paths(project, asset_paths, kind="asset")
    if len(project.panels) != 3 + len(asset_paths):
        raise AssertionError("Asset import should append one panel per imported file.")
    if any(panel.kind != "asset" for panel in project.panels[-len(asset_paths) :]):
        raise AssertionError("PDF asset import should preserve asset kind for composer panels.")

    project.texts = [
        ComposerText(
            id="text-1",
            text="Panel note",
            x_mm=5.0,
            y_mm=160.0,
            font_size_pt=9.0,
            align="left",
            z_index=len(project.panels),
        )
    ]

    composer_qa, _ = analyze_composer_project(project)
    if composer_qa.grade not in {"solid", "excellent"}:
        raise AssertionError("Composer smoke project should reach at least a solid QA grade.")

    preview_png = compose_preview_png(project)
    if len(preview_png) < 1024:
        raise AssertionError("Composer preview should produce a non-trivial PNG payload.")

    export_path = base / "composer_export.pdf"
    exported = compose_export_pdf(project, export_path)
    if not exported.exists() or exported.stat().st_size <= 0:
        raise AssertionError("Composer export should write a non-empty PDF.")


def _assert_legend_candidate_insets() -> None:
    fig, ax = plt.subplots()
    try:
        for idx in range(3):
            ax.plot([0, 1, 2], [idx, idx + 0.3, idx + 0.1], label=f"S{idx + 1}")
        fig.canvas.draw()
        renderer = fig.canvas.get_renderer()
        axes_bbox = ax.get_window_extent(renderer=renderer)
        tolerance = 0.002

        for candidate in _legend_candidates():
            legend = _place_legend_candidate(ax, candidate)
            fig.canvas.draw()
            legend_bbox = legend.get_window_extent(renderer=renderer)
            if "left" in candidate[0]:
                inset = (legend_bbox.x0 - axes_bbox.x0) / axes_bbox.width
            else:
                inset = (axes_bbox.x1 - legend_bbox.x1) / axes_bbox.width
            if "upper" in candidate[0]:
                vertical_inset = (axes_bbox.y1 - legend_bbox.y1) / axes_bbox.height
            else:
                vertical_inset = (legend_bbox.y0 - axes_bbox.y0) / axes_bbox.height

            if abs(inset - INSIDE_LEGEND_INSET_FRACTION) > tolerance:
                raise AssertionError("Legend horizontal inset drifted away from 2.5%.")
            if abs(vertical_inset - INSIDE_LEGEND_INSET_FRACTION) > tolerance:
                raise AssertionError("Legend vertical inset drifted away from 2.5%.")
            legend.remove()
    finally:
        plt.close(fig)


def _assert_rendered_output_files(
    outputs_dir: Path,
    template_by_output: dict[str, str],
    qa_by_output_key: dict[str, dict[str, object] | None],
) -> list[dict[str, object]]:
    pdf_paths = sorted(outputs_dir.rglob("*.pdf"))
    if not pdf_paths:
        raise AssertionError("Smoke outputs should include at least one exported PDF.")

    reports: list[dict[str, object]] = []
    for pdf_path in pdf_paths:
        doc = fitz.open(pdf_path)
        try:
            if doc.page_count < 1:
                raise AssertionError(f"{pdf_path.name} should contain at least one page.")

            page = doc[0]
            if page.rect.width <= 0 or page.rect.height <= 0:
                raise AssertionError(f"{pdf_path.name} should have a positive page size.")

            if not page.get_drawings() and not page.get_images() and not page.get_text("words"):
                raise AssertionError(f"{pdf_path.name} appears to have no visible page content.")

            pixmap = page.get_pixmap(dpi=96, alpha=False)
            pixels = np.frombuffer(pixmap.samples, dtype=np.uint8)
            if pixels.size == 0 or pixels.min() == pixels.max():
                raise AssertionError(f"{pdf_path.name} failed raster sanity-check and may be blank.")

            channels = max(pixmap.n, 1)
            if pixels.size % channels != 0:
                raise AssertionError(f"{pdf_path.name} produced an unexpected raster layout.")

            raster = pixels.reshape(-1, channels)
            if np.all(raster[:, :3] >= 250):
                raise AssertionError(f"{pdf_path.name} rasterized to an almost fully white page.")

            reports.append(
                {
                    "template": template_by_output.get(str(pdf_path), pdf_path.parent.name),
                    "output_path": str(pdf_path),
                    "output_filename": pdf_path.name,
                    "output_key": f"{template_by_output.get(str(pdf_path), pdf_path.parent.name)}/{pdf_path.name}",
                    "qa": qa_by_output_key.get(
                        f"{template_by_output.get(str(pdf_path), pdf_path.parent.name)}/{pdf_path.name}"
                    ),
                    "page_count": int(doc.page_count),
                    "page_size_mm": {
                        "width": round(float(page.rect.width * 25.4 / 72.0), 3),
                        "height": round(float(page.rect.height * 25.4 / 72.0), 3),
                    },
                    "has_visible_content": True,
                    "non_blank": True,
                    "rules": [
                        _validation_result(
                            "non_blank_pdf",
                            passed=True,
                            details={
                                "filename": pdf_path.name,
                                "page_count": int(doc.page_count),
                                "channels": int(channels),
                            },
                        )
                    ],
                }
            )
        finally:
            doc.close()
    return reports


def _assert_editorial_policy_outputs(qa_by_output_key: dict[str, dict[str, object] | None]) -> None:
    def _report_for(key: str) -> dict[str, object]:
        payload = qa_by_output_key.get(key)
        if payload is None:
            raise AssertionError(f"Missing QA report for smoke output: {key}")
        return payload

    def _issue_map(payload: dict[str, object]) -> dict[str, str]:
        issues = payload.get("issues", [])
        if not isinstance(issues, list):
            return {}
        return {
            str(item.get("id")): str(item.get("severity"))
            for item in issues
            if isinstance(item, dict) and item.get("id") is not None
        }

    tensile_curve = _report_for("curve/tensile_curve.pdf")
    tensile_autofixes = {str(item) for item in tensile_curve.get("autofixes_applied", [])}
    if "direct_series_labels" not in tensile_autofixes:
        raise AssertionError("Small tensile curve should prefer direct series labels when they fit cleanly.")
    tensile_issue_ids = set(_issue_map(tensile_curve))
    if "series_identification" in tensile_issue_ids:
        raise AssertionError("Chosen tensile curve candidate should not lose series identification.")
    if str(tensile_curve.get("grade")) != "excellent":
        raise AssertionError("Tensile curve should remain excellent after compact-panel autofix selection.")

    heatmap_report = _report_for("heatmap/heatmap_heatmap.pdf")
    heatmap_autofixes = {str(item) for item in heatmap_report.get("autofixes_applied", [])}
    if "heatmap_colorbar_tuned" not in heatmap_autofixes:
        raise AssertionError("Heatmap editorial policy should tune the top-strip colorbar layout.")
    heatmap_issue_ids = {str(item.get("id")) for item in heatmap_report.get("issues", []) if isinstance(item, dict)}
    if "colorbar_label_gap" in heatmap_issue_ids:
        raise AssertionError("Heatmap top-strip label and colorbar should no longer be cramped.")

    bar_report = _report_for("bar/tensile_modulus_bar.pdf")
    bar_autofixes = {str(item) for item in bar_report.get("autofixes_applied", [])}
    if "bar_raw_points_overlay" in bar_autofixes:
        raise AssertionError("Plain bar render should remain summary-only and skip raw-point overlays.")
    bar_issue_ids = {str(item.get("id")) for item in bar_report.get("issues", []) if isinstance(item, dict)}
    if "raw_point_overlay" in bar_issue_ids:
        raise AssertionError("Plain bar render should not expect a raw-point overlay under the new summary policy.")

    wide_nmr_report = _report_for("segmented_stacked_curve/wide_nmr_segmented_stacked_curve.pdf")
    wide_issue_ids = {str(item.get("id")) for item in wide_nmr_report.get("issues", []) if isinstance(item, dict)}
    if "stacked_label_collision" in wide_issue_ids:
        raise AssertionError("wide_nmr labels should remain non-overlapping after editorial review.")
    if "wide_nmr_reserve" in wide_issue_ids:
        raise AssertionError("wide_nmr reserve space should remain intact after editorial review.")

    dma_curve = _report_for("curve/dma_curve.pdf")
    if str(dma_curve.get("grade")) != "excellent":
        raise AssertionError("Canonical compact curve output should stay excellent after submission autofix.")

    for key, payload in qa_by_output_key.items():
        if payload is None:
            continue
        grade = str(payload.get("grade"))
        issue_map = _issue_map(payload)
        if key.startswith(("curve/", "point_line/", "scatter/")):
            if grade not in {"solid", "excellent"}:
                raise AssertionError(f"{key} should reach at least a solid editorial grade in smoke.")
            if issue_map.get("legend_footprint") == "critical":
                raise AssertionError(f"{key} should not keep a critical legend footprint after compact-panel tuning.")
            continue
        if key.startswith(("bar/", "box/", "violin/", "heatmap/")) and grade not in {"solid", "excellent"}:
            raise AssertionError(f"{key} should keep at least a solid editorial grade in smoke.")


def _assert_wide_nmr_layout(bundle_path: Path) -> list[dict[str, object]]:
    def _densify(points: np.ndarray, max_step_px: float = 3.0) -> np.ndarray:
        if len(points) < 2:
            return points
        dense = [points[:1]]
        for start, end in zip(points[:-1], points[1:], strict=True):
            delta = end - start
            steps = max(int(np.ceil(max(abs(delta[0]), abs(delta[1])) / max_step_px)), 1)
            if steps == 1:
                dense.append(end[None, :])
                continue
            fractions = np.linspace(0.0, 1.0, steps + 1, dtype=float)[1:]
            dense.append(start + fractions[:, None] * delta[None, :])
        return np.vstack(dense)

    config = load_wide_nmr_config(bundle_path)
    series_list = load_curve_table(bundle_path)
    fig, ax = plot_wide_nmr(series_list, config)
    fig.canvas.draw()

    width_mm = fig.get_size_inches()[0] * 25.4
    height_mm = fig.get_size_inches()[1] * 25.4
    if not np.isclose(width_mm, WIDE_NMR_WIDTH_MM, atol=0.2):
        raise AssertionError("wide_nmr should render at 60 mm width.")
    if not np.isclose(height_mm, WIDE_NMR_TOTAL_HEIGHT_MM, atol=0.2):
        raise AssertionError("wide_nmr should render at 110 mm total height.")
    if ax.get_ylabel():
        raise AssertionError("wide_nmr should hide the y-axis label.")
    if any(tick.label1.get_visible() for tick in ax.yaxis.get_major_ticks()):
        raise AssertionError("wide_nmr should hide y tick labels.")
    if ax.get_legend() is not None:
        raise AssertionError("wide_nmr should not render a legend.")
    if len(fig.axes) != 2:
        raise AssertionError("wide_nmr review example should render two x-axis segments.")
    highest_axis = max(axis.get_position().y1 for axis in fig.axes)
    reserved_mm = (1.0 - highest_axis) * height_mm
    if abs(reserved_mm - WIDE_NMR_STRUCTURE_RESERVED_MM) > 1.0:
        raise AssertionError("wide_nmr should reserve about 18 mm at the top for structure placement.")
    spectrum_mm = highest_axis * height_mm
    if abs(spectrum_mm - WIDE_NMR_SPECTRUM_HEIGHT_MM) > 1.0:
        raise AssertionError("wide_nmr lower spectrum region height drifted away from 92 mm.")

    sample_names = {series.sample for series in series_list}
    text_items = []
    for axis in fig.axes:
        text_items.extend([text for text in axis.texts if text.get_text() in sample_names])
    if len(text_items) != len(series_list):
        raise AssertionError("wide_nmr should render one in-axes sample label per series.")

    anchor_x = [float(text.get_transform().transform(text.get_position())[0]) for text in text_items]
    if max(anchor_x) - min(anchor_x) > 4.0:
        raise AssertionError("wide_nmr sample labels should stay aligned on a common x rail.")

    renderer = fig.canvas.get_renderer()
    bboxes = [text.get_window_extent(renderer=renderer).expanded(1.01, 1.03) for text in text_items]
    for text, bbox in zip(text_items, bboxes, strict=True):
        axis = text.axes
        axis_bbox = axis.get_window_extent(renderer=renderer)
        if bbox.x0 < axis_bbox.x0 or bbox.x1 > axis_bbox.x1 or bbox.y0 < axis_bbox.y0 or bbox.y1 > axis_bbox.y1:
            raise AssertionError("wide_nmr sample labels should stay inside the target axes.")
    for idx, bbox in enumerate(bboxes):
        for other in bboxes[idx + 1 :]:
            if bbox.overlaps(other):
                raise AssertionError("wide_nmr sample labels should not overlap each other.")

    for text, bbox in zip(text_items, bboxes, strict=True):
        axis = text.axes
        for line in axis.lines:
            x = np.asarray(line.get_xdata(), dtype=float)
            y = np.asarray(line.get_ydata(), dtype=float)
            valid = np.isfinite(x) & np.isfinite(y)
            if valid.sum() == 0:
                continue
            points = _densify(axis.transData.transform(np.column_stack([x[valid], y[valid]])))
            inside = (
                (points[:, 0] >= bbox.x0)
                & (points[:, 0] <= bbox.x1)
                & (points[:, 1] >= bbox.y0)
                & (points[:, 1] <= bbox.y1)
            )
            if np.any(inside):
                raise AssertionError("wide_nmr sample labels should not overlap plotted curves.")
    plt.close(fig)
    return [
        _validation_result(
            "wide_nmr_structure_reserve",
            passed=True,
            details={
                "reserved_mm": round(float(reserved_mm), 3),
                "spectrum_mm": round(float(spectrum_mm), 3),
                "expected_reserved_mm": round(float(WIDE_NMR_STRUCTURE_RESERVED_MM), 3),
                "expected_spectrum_mm": round(float(WIDE_NMR_SPECTRUM_HEIGHT_MM), 3),
            },
        )
    ]


def _assert_stacked_series_clearance(
    plotter: Callable[[Sequence[CurveSeries]], tuple[plt.Figure, plt.Axes]],
    table_path: Path,
) -> None:
    series_list = load_curve_table(table_path)
    fig, ax = plotter(series_list)
    try:
        line_arrays: list[np.ndarray] = []
        for line in ax.lines:
            y = np.asarray(line.get_ydata(), dtype=float)
            y = y[np.isfinite(y)]
            if y.size:
                line_arrays.append(y)
        if len(line_arrays) < 2:
            raise AssertionError("Stacked spectra check requires at least two plotted series.")

        spans = [float(np.nanmax(arr) - np.nanmin(arr)) for arr in line_arrays]
        max_span = max(spans) if spans else 0.0
        min_clearance = max(max_span * 0.03, 1e-9)
        for lower, upper in zip(line_arrays, line_arrays[1:], strict=False):
            lower_peak = float(np.nanmax(lower))
            upper_baseline = float(np.nanmin(upper))
            if upper_baseline - lower_peak <= min_clearance:
                raise AssertionError(
                    "Stacked spectra should leave a visible gap between one trace's peak envelope "
                    "and the next trace's baseline."
                )
    finally:
        plt.close(fig)


def _to_curve_series(series_list) -> list[CurveSeries]:
    return [
        CurveSeries(
            sample=series.sample,
            x_label=series.x_label,
            y_label=series.y_label,
            x_unit=series.x_unit,
            y_unit=series.y_unit,
            data=series.data,
        )
        for series in series_list
    ]


def _write_smoke_report(
    *,
    output_reports: list[dict[str, object]],
    validation_reports: list[dict[str, object]],
    preprocess_reports: list[dict[str, object]],
    contract_lint_reports: list[dict[str, object]],
    style_theme_matrix: list[dict[str, object]],
) -> Path:
    contract = load_plot_contract()
    payload = {
        "generated_at": datetime.now(UTC).isoformat(),
        "contract_version": contract.version,
        "summary": {
            "pdf_count": len(output_reports),
            "validation_count": len(validation_reports),
            "preprocess_case_count": len(preprocess_reports),
            "contract_lint_check_count": len(contract_lint_reports),
            "style_theme_matrix_case_count": len(style_theme_matrix),
            "templates_checked": sorted({str(item["template"]) for item in output_reports}),
        },
        "outputs": output_reports,
        "validations": validation_reports,
        "preprocess_runs": preprocess_reports,
        "contract_lint": contract_lint_reports,
        "style_theme_template_matrix": style_theme_matrix,
    }
    SMOKE_REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    SMOKE_REPORT_PATH.write_text(
        json.dumps(_json_safe(payload), ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return SMOKE_REPORT_PATH


def _run_smoke_workspace(base: Path) -> Path:
    outputs = base / "outputs"

    replicate_path = base / "replicate.csv"
    tensile_path = base / "tensile.csv"
    ftir_path = base / "ftir.csv"
    nmr_path = base / "nmr.csv"
    xrd_path = base / "xrd.csv"
    dsc_path = base / "dsc.csv"
    tga_path = base / "tga.csv"
    dma_path = base / "dma.csv"
    heatmap_path = base / "heatmap.csv"
    wide_nmr_path = base / "wide_nmr.csv"
    freq_path = base / "freq.xlsx"
    temp_path = base / "temp.xlsx"
    relax_path = base / "relax.xlsx"

    _write_replicate_table(replicate_path)
    _write_curve_table(tensile_path, "Strain", "Stress", "%", "MPa")
    _write_stacked_curve_table(ftir_path, template="ftir")
    _write_stacked_curve_table(nmr_path, template="nmr")
    _write_stacked_curve_table(xrd_path, template="xrd")
    _write_stacked_curve_table(dsc_path, template="dsc")
    _write_tga_curve_table(tga_path)
    _write_dma_curve_table(dma_path)
    _write_heatmap_table(heatmap_path)
    _write_wide_nmr_bundle(wide_nmr_path)
    _write_frequency_xlsx(freq_path)
    _write_temperature_xlsx(temp_path)
    _write_relaxation_xlsx(relax_path)
    _assert_normalization_rules()
    _assert_input_validation(base)
    _assert_inspection_and_preflight(
        freq_path=freq_path,
        temp_path=temp_path,
        relax_path=relax_path,
        replicate_path=replicate_path,
        heatmap_path=heatmap_path,
        tensile_path=tensile_path,
        ftir_path=ftir_path,
        wide_nmr_path=wide_nmr_path,
    )
    jobs = [
        ("bar", replicate_path, {}),
        ("box", replicate_path, {}),
        ("violin", replicate_path, {}),
        ("point_line", freq_path, {"xscale": "log", "yscale": "log"}),
        ("point_line", temp_path, {"yscale": "log"}),
        ("point_line", relax_path, {"xscale": "log"}),
        ("curve", tensile_path, {}),
        ("scatter", tensile_path, {}),
        ("stacked_curve", ftir_path, {"reverse_x": True}),
        ("stacked_area", ftir_path, {"reverse_x": True}),
        ("stacked_curve", nmr_path, {"reverse_x": True, "baseline": "linear_endpoints"}),
        (
            "segmented_stacked_curve",
            wide_nmr_path,
            {"reverse_x": True, "baseline": "linear_endpoints", "use_sidecar": True},
        ),
        ("stacked_curve", xrd_path, {}),
        ("stacked_curve", dsc_path, {"baseline": "linear_endpoints"}),
        ("density_area", replicate_path, {}),
        ("curve", tga_path, {}),
        ("curve", dma_path, {}),
        ("heatmap", heatmap_path, {}),
    ]

    template_by_output: dict[str, str] = {}
    qa_by_output_key: dict[str, dict[str, object] | None] = {}
    for template, input_path, options in jobs:
        rendered_plots = build_rendered_plots(template, input_path, 0, **options)
        try:
            rendered_paths = export_rendered_plots(rendered_plots, outputs / template)
            for rendered_plot, output in zip(rendered_plots, rendered_paths, strict=True):
                if not output.exists():
                    raise FileNotFoundError(f"Expected output was not created: {output}")
                template_by_output[str(output)] = template
                qa_by_output_key[f"{template}/{output.name}"] = (
                    asdict(rendered_plot.qa_report) if rendered_plot.qa_report is not None else None
                )
                print(output)
        finally:
            close_rendered_plots(rendered_plots)

    preprocess_reports = _assert_tensile_preprocess_workflow(
        base=base,
        outputs_dir=outputs,
        template_by_output=template_by_output,
    )
    output_reports = _assert_rendered_output_files(outputs, template_by_output, qa_by_output_key)
    _assert_editorial_policy_outputs(qa_by_output_key)
    _assert_stacked_layout(plot_ftir, ftir_path)
    _assert_stacked_layout(plot_nmr, nmr_path)
    _assert_stacked_layout(plot_xrd, xrd_path)
    _assert_stacked_layout(plot_dsc, dsc_path)
    _assert_stacked_series_clearance(plot_ftir, ftir_path)
    _assert_stacked_series_clearance(plot_nmr, nmr_path)
    _assert_stacked_series_clearance(plot_xrd, xrd_path)
    _assert_stacked_series_clearance(plot_dsc, dsc_path)
    _assert_style_palette_presets(
        replicate_path=replicate_path,
        tensile_path=tensile_path,
        ftir_path=ftir_path,
        wide_nmr_path=wide_nmr_path,
        heatmap_path=heatmap_path,
        temp_path=temp_path,
    )
    tensile_series = load_curve_table(tensile_path)
    _assert_curve_padding(plot_tensile_curve, tensile_series, expect_zero_y_origin=True)
    _assert_major_tick_skip_every_other()
    _assert_stat_plot_tick_cap(load_replicate_table(replicate_path))
    freq_series = _to_curve_series(load_frequency_sweep_metrics(freq_path)["storage_modulus"])
    _assert_curve_padding(
        plot_frequency_sweep,
        freq_series,
        expect_log_y=True,
    )
    temp_series = _to_curve_series(load_temperature_sweep_metrics(temp_path)["storage_modulus"])
    _assert_curve_padding(
        lambda series: plot_frequency_sweep(series, xscale="linear", yscale="log"),
        temp_series,
        expect_log_y=True,
    )
    validation_reports = _assert_axis_frame_alignment(
        replicate_path=replicate_path,
        tensile_path=tensile_path,
        heatmap_path=heatmap_path,
        wide_nmr_path=wide_nmr_path,
    )
    validation_reports.extend(_assert_axis_break_overlays(tensile_path))
    validation_reports.extend(_assert_wide_nmr_layout(wide_nmr_path))
    _assert_frequency_batch_sync(freq_path)
    _assert_legend_candidate_insets()
    _assert_composer_workflow(outputs, base)
    contract_lint_reports = _assert_public_template_contract_lint()
    style_theme_matrix = _style_theme_template_matrix(
        tensile_path=tensile_path,
        replicate_path=replicate_path,
        heatmap_path=heatmap_path,
    )
    nested_output_rules = [
        rule
        for output_report in output_reports
        for rule in output_report.get("rules", [])
        if isinstance(rule, dict)
    ]
    _assert_no_failed_error_validations([*nested_output_rules, *validation_reports, *contract_lint_reports])
    return _write_smoke_report(
        output_reports=output_reports,
        validation_reports=validation_reports,
        preprocess_reports=preprocess_reports,
        contract_lint_reports=contract_lint_reports,
        style_theme_matrix=style_theme_matrix,
    )


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the SciPlot God public-surface smoke matrix.")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    parse_args(argv)
    capture_dir = os.environ.get(SMOKE_CAPTURE_DIR_ENV)
    if capture_dir:
        base = Path(capture_dir).expanduser()
        if base.exists():
            shutil.rmtree(base)
        base.mkdir(parents=True, exist_ok=True)
        report_path = _run_smoke_workspace(base)
        print(f"Smoke check passed. Report: {report_path}")
        print(f"Smoke artifacts preserved in: {base}")
        return 0

    with tempfile.TemporaryDirectory(prefix="plot_smoke_") as tmp:
        report_path = _run_smoke_workspace(Path(tmp))

    print(f"Smoke check passed. Report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
