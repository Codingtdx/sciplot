from __future__ import annotations

import math
from contextlib import suppress
from pathlib import Path

import pandas as pd

from src.data_loader import CurveSeries
from src.plot_contract import default_options_for_template, default_size_for_template
from src.rendering.cache import (
    load_curve_table_cached,
    load_heatmap_table_cached,
    load_replicate_table_cached,
    load_stress_relaxation_metric_cached,
    read_raw_table_cached,
)
from src.rendering.common import looks_like_tensile_curve, to_curve_series
from src.rendering.models import InputInspection, Recommendation, TemplateName
from src.text_normalization import canonicalize_token, normalize_label
from src.wide_nmr import wide_nmr_sidecar_path


def clean_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and pd.isna(value):
        return ""
    return str(value).strip()


def model_label(model: str) -> str:
    labels = {
        "curve_table": "Paired curve table (curve_table)",
        "tensile_curve": "Tensile stress-strain curve (tensile_curve)",
        "replicate_table": "Replicate wide table (replicate_table)",
        "heatmap_table": "Heatmap long table (xyz_long_table)",
        "frequency_sweep": "Frequency sweep export table",
        "temperature_sweep": "Temperature sweep export table",
        "stress_relaxation": "Stress relaxation export table",
    }
    return labels.get(model, model)


def point_line_bundle_signals(bundle: str) -> tuple[str, ...]:
    if bundle == "frequency_sweep":
        return (
            "Detected a 5-column rheology export bundle.",
            "The first x-axis field is Angular Frequency / ω.",
            "Each bundle includes Storage/Loss Modulus, Loss Factor, and Complex Viscosity.",
        )
    if bundle == "temperature_sweep":
        return (
            "Detected a 5-column rheology export bundle.",
            "The first x-axis field is Temperature.",
            "Each bundle includes Storage/Loss Modulus, Loss Factor, and Complex Viscosity.",
        )
    if bundle == "stress_relaxation":
        return (
            "Detected a 4-column stress relaxation export bundle.",
            "The first x-axis field is Time.",
            "The bundle includes the σ/σ₀ metric.",
        )
    return ()


def axis_dynamic_range(
    series_list: list[CurveSeries],
    axis: str,
) -> tuple[float, float, bool] | None:
    positive_min: float | None = None
    positive_max: float | None = None
    all_positive = True

    for series in series_list:
        values = pd.to_numeric(series.data[axis], errors="coerce").dropna()
        if values.empty:
            continue
        positive = values[values > 0]
        if positive.empty:
            all_positive = False
            continue
        if len(positive) != len(values):
            all_positive = False
        current_min = float(positive.min())
        current_max = float(positive.max())
        positive_min = current_min if positive_min is None else min(positive_min, current_min)
        positive_max = current_max if positive_max is None else max(positive_max, current_max)

    if positive_min is None or positive_max is None or positive_max <= 0:
        return None

    ratio = positive_max / positive_min if positive_min > 0 else 0.0
    orders = math.log10(ratio) if ratio > 0 else 0.0
    return ratio, orders, all_positive


def recommend_axis_scale(
    series_list: list[CurveSeries],
    axis: str,
    *,
    label: str,
    min_orders: float,
) -> tuple[str, str]:
    summary = axis_dynamic_range(series_list, axis)
    if summary is None:
        return "linear", f"{label} does not show a stable positive range, so linear stays on."

    _, orders, all_positive = summary
    if all_positive and orders >= min_orders:
        return "log", f"{label} spans about {orders:.1f} orders of magnitude, so log is recommended."
    if not all_positive:
        return "linear", f"{label} includes non-positive or near-zero values, so linear stays on."
    return "linear", f"{label} varies by about {orders:.1f} orders of magnitude, and linear stays easier to read."


def recommend_curve_scales(series_list: list[CurveSeries]) -> tuple[str, str, tuple[str, ...]]:
    xscale, xsignal = recommend_axis_scale(
        series_list,
        "x",
        label="X axis",
        min_orders=2.0,
    )
    yscale, ysignal = recommend_axis_scale(
        series_list,
        "y",
        label="Y axis",
        min_orders=2.3,
    )
    return xscale, yscale, (xsignal, ysignal)


def recommendation(template: TemplateName, reason: str, **overrides: object) -> Recommendation:
    defaults = default_options_for_template(template)
    payload = {
        "template": template,
        "reason": reason,
        "size": defaults.get("size", default_size_for_template(template)),
        "xscale": defaults.get("xscale"),
        "yscale": defaults.get("yscale"),
        "reverse_x": defaults.get("reverse_x"),
        "baseline": defaults.get("baseline"),
        "show_colorbar": defaults.get("show_colorbar"),
        "style_preset": defaults.get("style_preset"),
        "palette_preset": defaults.get("palette_preset"),
        "use_sidecar": defaults.get("use_sidecar"),
    }
    payload.update(overrides)
    return Recommendation(**payload)


def detect_point_line_bundle(input_path: Path, sheet: str | int) -> str | None:
    try:
        raw = read_raw_table_cached(input_path, sheet).dropna(axis=1, how="all")
    except Exception:
        return None

    if raw.shape[0] < 3 or raw.shape[1] == 0:
        return None

    labels = [canonicalize_token(clean_text(value)) for value in raw.iloc[0].tolist()]
    normalized_labels = [normalize_label(clean_text(value)) for value in raw.iloc[0].tolist()]
    first_label = labels[0]

    if raw.shape[1] % 5 == 0 and {
        "storage modulus",
        "loss modulus",
        "loss factor",
        "complex viscosity",
    }.issubset(set(labels)):
        if first_label == "temperature":
            return "temperature_sweep"
        if first_label in {"angular frequency", "frequency", "ω"}:
            return "frequency_sweep"

    if raw.shape[1] % 4 == 0 and first_label == "time":
        if r"$\sigma/\sigma_0$" in normalized_labels:
            return "stress_relaxation"

    return None


def looks_like_nmr(series_list: list[CurveSeries]) -> bool:
    first = series_list[0]
    x_label = canonicalize_token(first.x_label)
    x_unit = clean_text(first.x_unit).lower()
    return x_label == "chemical shift" or "ppm" in x_unit


def looks_like_ftir(series_list: list[CurveSeries]) -> bool:
    first = series_list[0]
    x_label = canonicalize_token(first.x_label)
    x_unit = clean_text(first.x_unit).lower()
    return x_label == "wavenumber" or ("cm" in x_unit and ("-1" in x_unit or "^{-1}" in x_unit))


def looks_like_xrd(series_list: list[CurveSeries]) -> bool:
    first = series_list[0]
    x_label = canonicalize_token(first.x_label)
    y_label = canonicalize_token(first.y_label)
    y_unit = clean_text(first.y_unit).lower()
    return x_label in {"2theta", "2θ"} or ("count" in y_unit) or (x_label == "2 theta" and y_label == "intensity")


def looks_like_dsc(series_list: list[CurveSeries]) -> bool:
    first = series_list[0]
    y_label = canonicalize_token(first.y_label)
    return y_label == "heat flow"


def inspect_input_file(input_path: Path, sheet: str | int = 0) -> InputInspection:
    bundle = detect_point_line_bundle(input_path, sheet)
    if bundle == "frequency_sweep":
        return InputInspection(
            model=bundle,
            model_label=model_label(bundle),
            recommendation=recommendation(
                "point_line",
                "Detected a frequency sweep rheology export table with 5 columns per bundle.",
                xscale="log",
                yscale="log",
                reverse_x=False,
            ),
            warnings=("This export will generate 4 PDF files.",),
            signals=point_line_bundle_signals(bundle),
        )
    if bundle == "temperature_sweep":
        return InputInspection(
            model=bundle,
            model_label=model_label(bundle),
            recommendation=recommendation(
                "point_line",
                "Detected a temperature sweep rheology export table with 5 columns per bundle.",
                size="120x55",
                xscale="linear",
                yscale="log",
                reverse_x=False,
            ),
            warnings=("This export will generate 2 PDF files.",),
            signals=point_line_bundle_signals(bundle),
        )
    if bundle == "stress_relaxation":
        relaxation_series = to_curve_series(
            load_stress_relaxation_metric_cached(input_path, "σ/σ₀", sheet)
        )
        xscale, yscale, range_signals = recommend_curve_scales(relaxation_series)
        return InputInspection(
            model=bundle,
            model_label=model_label(bundle),
            recommendation=recommendation(
                "point_line",
                "Detected a stress relaxation export table with 4 columns per bundle.",
                xscale=xscale,
                yscale=yscale,
                reverse_x=False,
            ),
            signals=point_line_bundle_signals(bundle) + range_signals,
        )

    with suppress(Exception):
        load_heatmap_table_cached(input_path, sheet)
        return InputInspection(
            model="heatmap_table",
            model_label=model_label("heatmap_table"),
            recommendation=recommendation(
                "heatmap",
                "Detected a heatmap long table with explicit X / Y / Z role columns.",
                show_colorbar=True,
            ),
            signals=(
                "Detected a 3-column input layout.",
                "Row 1 explicitly defines the X, Y, and Z role columns.",
                "This input is best converted directly into a heatmap matrix.",
            ),
        )

    try:
        series_list = load_curve_table_cached(input_path, sheet)
    except Exception as exc:
        try:
            groups = load_replicate_table_cached(input_path, sheet)
        except Exception:
            raise ValueError(
                "Could not recognize this file. Reformat it as a curve_table, replicate_table, "
                "heatmap xyz_long_table, or one of the supported rheology export tables."
            ) from exc
        warnings: list[str] = []
        if len(groups) >= 6:
            warnings.append("There are many groups, so x-axis labels may wrap or shrink.")
        return InputInspection(
            model="replicate_table",
            model_label=model_label("replicate_table"),
            recommendation=recommendation(
                "box",
                "Detected a statistical table with a shared y-axis label, sample names, units, and replicate values.",
            ),
            warnings=tuple(warnings),
            signals=(
                "Cell A1 provides the shared y-axis label.",
                "Row 2 contains group names and row 3 contains units.",
                "Row 4 onward contains replicate values, which fits statistical plots well.",
            ),
        )

    if wide_nmr_sidecar_path(input_path).exists():
        return InputInspection(
            model="curve_table",
            model_label=model_label("curve_table"),
            recommendation=recommendation(
                "segmented_stacked_curve",
                "Detected a standard curve table and found a wide_nmr sidecar in the same directory.",
                reverse_x=True,
                baseline="linear_endpoints",
                use_sidecar=True,
            ),
            signals=(
                "Detected a standard paired curve table.",
                "A .wide_nmr.toml sidecar is present in the same directory.",
                "This input is a better fit for a segmented stacked curve plot.",
            ),
        )
    if looks_like_nmr(series_list):
        return InputInspection(
            model="curve_table",
            model_label=model_label("curve_table"),
            recommendation=recommendation(
                "stacked_curve",
                "The Chemical shift / ppm axis suggests an NMR-style spectrum.",
                reverse_x=True,
                baseline="linear_endpoints",
            ),
            signals=(
                "The x-axis label or unit matches Chemical shift / ppm.",
                "Multiple sample curves are better shown as a stacked spectrum.",
                "A reversed x-axis and light baseline correction are recommended.",
            ),
        )
    if looks_like_ftir(series_list):
        return InputInspection(
            model="curve_table",
            model_label=model_label("curve_table"),
            recommendation=recommendation(
                "stacked_curve",
                "The Wavenumber / cm^-1 axis suggests an FTIR-style spectrum.",
                reverse_x=True,
                baseline="none",
            ),
            signals=(
                "The x-axis label or unit matches Wavenumber / cm⁻¹.",
                "Multiple sample curves are better shown as a stacked spectrum.",
                "A reversed x-axis is recommended without forcing baseline correction.",
            ),
        )
    if looks_like_dsc(series_list):
        return InputInspection(
            model="curve_table",
            model_label=model_label("curve_table"),
            recommendation=recommendation(
                "stacked_curve",
                "The Heat flow label suggests a DSC-style stacked plot.",
                reverse_x=False,
                baseline="linear_endpoints",
            ),
            signals=(
                "The y-axis label matches Heat flow.",
                "These thermal analysis curves are easier to compare in a stacked layout.",
                "Linear-endpoint baseline correction is recommended.",
            ),
        )
    if looks_like_xrd(series_list):
        return InputInspection(
            model="curve_table",
            model_label=model_label("curve_table"),
            recommendation=recommendation(
                "stacked_curve",
                "The 2theta / counts / intensity fields suggest an XRD-style spectrum.",
                reverse_x=False,
                baseline="none",
            ),
            signals=(
                "The axis labels or units match 2theta / counts / intensity.",
                "Multiple sample curves are better shown as a stacked spectrum.",
                "A forward x-axis is recommended.",
            ),
        )
    if looks_like_tensile_curve(series_list):
        return InputInspection(
            model="tensile_curve",
            model_label=model_label("tensile_curve"),
            recommendation=recommendation(
                "curve",
                "The strain / elongation x-axis and stress y-axis suggest a tensile curve.",
                size="60x55",
                xscale="linear",
                yscale="linear",
                reverse_x=False,
            ),
            signals=(
                "The x-axis label or unit matches strain / elongation / %.",
                "The y-axis label or unit matches stress / MPa.",
                "Tensile curves always stay on linear x/y axes by default.",
            ),
        )
    xscale, yscale, range_signals = recommend_curve_scales(series_list)
    return InputInspection(
        model="curve_table",
        model_label=model_label("curve_table"),
        recommendation=recommendation(
            "curve",
            "Detected a standard paired curve table, so a basic curve plot is recommended by default.",
            xscale=xscale,
            yscale=yscale,
        ),
        signals=(
            "Detected a standard paired curve table.",
            "The labels and units do not strongly match a spectrum or rheology export bundle.",
            "The default path is a standard curve plot.",
            *range_signals,
        ),
    )
