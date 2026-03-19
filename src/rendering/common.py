from __future__ import annotations

from pathlib import Path

from src.data_loader import CurveSeries, ReplicateGroup
from src.plot_contract import validation_rule
from src.rendering.cache import (
    load_frequency_sweep_metrics_cached,
    load_replicate_table_cached,
    load_stress_relaxation_metric_cached,
    load_temperature_sweep_metrics_cached,
)
from src.rendering.constants import (
    FREQUENCY_CURVE_OUTPUTS,
    FREQUENCY_OUTPUTS,
    STRESS_RELAXATION_CURVE_OUTPUT,
    STRESS_RELAXATION_OUTPUT,
    TEMPERATURE_CURVE_OUTPUTS,
    TEMPERATURE_OUTPUTS,
)
from src.rendering.models import RenderOptions, TemplateName
from src.rheology_loader import RheologySeries
from src.text_normalization import canonicalize_token, normalize_label, slugify_label
from src.wide_nmr import WideNMRConfig, WideNMRSegment, load_wide_nmr_config, wide_nmr_sidecar_path

TENSILE_LINEAR_SCALE_ERROR = "Tensile curves must use linear axes. Log x / y is not supported."


def humanize_preflight_exception(exc: Exception) -> str:
    message = str(exc)

    if "Missing segmented_stacked_curve sidecar config" in message:
        return (
            "This figure type requires a sidecar config in the same directory "
            "for split axes, highlights, and labels, but none was found."
        )
    if "must include at least" in message:
        return (
            "The table does not contain enough rows. Keep the label row, unit "
            "row, sample row, and at least one data row."
        )
    if "axis label row" in message:
        return "Row 1 is missing the label row. Put the X/Y labels there."
    if "unit row" in message:
        return "Row 2 is missing the unit row. Put the units there."
    if "sample row" in message:
        return "Row 3 is missing the sample row. Put the sample names there."
    if "group row" in message:
        return "Row 2 is missing the group row. Put the group names there."
    if "Curve table must contain an even number of columns arranged in X/Y pairs." in message or "X/Y pairs" in message:
        return "The curve table columns are not arranged in X/Y pairs. Reformat them as X/Y, X/Y, and so on."
    if "matching X/Y numeric data" in message:
        return (
            "One X/Y pair only has valid numeric data on one side. Check that "
            "both columns are paired and fully numeric."
        )
    if "contains incomplete X/Y rows" in message:
        return "One X/Y series contains incomplete rows. Remove half-empty rows or fill that series completely."
    if "contains non-numeric values in the data region" in message:
        return "The data region contains non-numeric values. Move notes outside the data area and keep only numbers."
    if "Sample names in columns" in message:
        return "The sample names in one X/Y pair do not match. Make both columns use the same sample name."
    if "contains non-positive x values" in message:
        return (
            "Log x is selected, but the data contains x values that are less "
            "than or equal to 0. Switch to linear or clean those values first."
        )
    if "contains non-positive y values" in message:
        return (
            "Log y is selected, but the data contains y values that are less "
            "than or equal to 0. Switch to linear or clean those values first."
        )
    if "contains no numeric replicate values" in message:
        return (
            "One replicate column does not contain usable numeric values. "
            "Remove the empty column or fill it with numbers only."
        )
    if "No valid replicate columns found" in message:
        return "No valid replicate columns were found. Confirm that numeric replicate values begin on row 4."
    if "No valid X/Y series found" in message:
        return (
            "No valid X/Y series were found. Confirm that row 4 onward "
            "contains at least one complete numeric series."
        )
    if "Heatmap table must contain exactly three columns: X, Y, Z." in message:
        return "The heatmap table must contain exactly three columns mapped to X, Y, and Z."
    if "Heatmap table role row must contain exactly X, Y and Z." in message:
        return "Row 1 of the heatmap table must explicitly define the X, Y, and Z role columns."
    if "does not contain any numeric Z values" in message:
        return "The heatmap Z column does not contain any valid numeric values. Check the data from row 4 onward."
    if "does not contain any valid X/Y coordinates" in message:
        return "The heatmap X/Y coordinate columns are empty or invalid. Check the data from row 4 onward."
    if "Frequency sweep is missing metric data" in message:
        return f"{message} Confirm that this exported bundle includes the complete metric columns."
    if "Temperature sweep is missing metric data" in message:
        return f"{message} Confirm that this exported bundle includes the complete metric columns."
    if "No σ/σ₀ curve was found in the stress relaxation table" in message:
        return (
            "No σ/σ₀ curve was found in the stress relaxation table. Confirm "
            "that the exported file includes that series."
        )
    if "No valid groups were found in the replicate table" in message:
        return (
            "No valid groups were found in the replicate table. Confirm that "
            "row 2 contains group names and row 4 onward contains replicate values."
        )
    return message


def style_preflight_warnings(options: RenderOptions) -> tuple[str, ...]:
    if options.style_preset == "nature":
        return ("The Nature preset is active, so official figure constraints take priority.",)
    return ()


def to_curve_series(series_list: list[RheologySeries]) -> list[CurveSeries]:
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


def validate_series_scales(series_list: list[CurveSeries], *, xscale: str, yscale: str) -> None:
    if looks_like_tensile_curve(series_list) and (xscale != "linear" or yscale != "linear"):
        raise ValueError(TENSILE_LINEAR_SCALE_ERROR)
    if xscale == "log":
        for series in series_list:
            if (series.data["x"] <= 0).any():
                raise ValueError(f"Series {series.sample!r} contains non-positive x values and cannot use log x-axis.")
    if yscale == "log":
        for series in series_list:
            if (series.data["y"] <= 0).any():
                raise ValueError(f"Series {series.sample!r} contains non-positive y values and cannot use log y-axis.")


def looks_like_tensile_curve(series_list: list[CurveSeries]) -> bool:
    if not series_list:
        return False
    first = series_list[0]
    x_label = canonicalize_token(normalize_label(first.x_label))
    y_label = canonicalize_token(normalize_label(first.y_label))
    x_unit = canonicalize_token(first.x_unit)
    y_unit = canonicalize_token(first.y_unit)

    x_label_match = x_label in {"strain", "elongation"} or "strain" in x_label or "elongation" in x_label
    y_label_match = y_label in {"stress", "σ"} or "stress" in y_label
    x_unit_match = x_unit in {"%", "percent"}
    y_unit_match = y_unit in {"pa", "kpa", "mpa", "gpa"}
    return x_label_match and y_label_match and (x_unit_match or y_unit_match)


def load_rheology_bundle_series(
    bundle: str,
    input_path: Path,
    sheet: str | int,
) -> dict[str, list[CurveSeries]]:
    if bundle == "frequency_sweep":
        return {
            metric_name: to_curve_series(series_list)
            for metric_name, series_list in load_frequency_sweep_metrics_cached(input_path, sheet).items()
        }
    if bundle == "temperature_sweep":
        return {
            metric_name: to_curve_series(series_list)
            for metric_name, series_list in load_temperature_sweep_metrics_cached(input_path, sheet).items()
        }
    if bundle == "stress_relaxation":
        return {
            "sigma_over_sigma0": to_curve_series(
                load_stress_relaxation_metric_cached(input_path, "σ/σ₀", sheet)
            ),
        }
    raise ValueError(f"Unsupported rheology bundle: {bundle}")


def rheology_output_filenames(
    bundle: str,
    template: TemplateName,
) -> dict[str, str]:
    if template == "point_line":
        if bundle == "frequency_sweep":
            return FREQUENCY_OUTPUTS
        if bundle == "temperature_sweep":
            return TEMPERATURE_OUTPUTS
        if bundle == "stress_relaxation":
            return {"sigma_over_sigma0": STRESS_RELAXATION_OUTPUT}
    if template == "curve":
        if bundle == "frequency_sweep":
            return FREQUENCY_CURVE_OUTPUTS
        if bundle == "temperature_sweep":
            return TEMPERATURE_CURVE_OUTPUTS
        if bundle == "stress_relaxation":
            return {"sigma_over_sigma0": STRESS_RELAXATION_CURVE_OUTPUT}
    raise ValueError(f"Unsupported bundle/template combination: {bundle} / {template}")


def validate_rheology_bundle_scales(
    bundle: str,
    input_path: Path,
    sheet: str | int,
    *,
    xscale: str,
    yscale: str,
) -> dict[str, list[CurveSeries]]:
    metric_series = load_rheology_bundle_series(bundle, input_path, sheet)
    bundle_label = {
        "frequency_sweep": "Frequency sweep",
        "temperature_sweep": "Temperature sweep",
        "stress_relaxation": "Stress relaxation",
    }.get(bundle, bundle)
    for metric_name, series_list in metric_series.items():
        if not series_list:
            if bundle == "stress_relaxation":
                raise ValueError("No σ/σ₀ curve was found in the stress relaxation table.")
            raise ValueError(f"{bundle_label} is missing metric data: {metric_name}")
        validate_series_scales(series_list, xscale=xscale, yscale=yscale)
    return metric_series


def predict_bar_box_slug(groups: list[ReplicateGroup]) -> str:
    return slugify_label(groups[0].value_label if groups else "value")


def preview_output_filenames(
    template: TemplateName,
    input_path: Path,
    sheet: str | int,
    bundle: str | None,
) -> tuple[str, ...]:
    if template in {"point_line", "curve"} and bundle in {
        "frequency_sweep",
        "temperature_sweep",
        "stress_relaxation",
    }:
        return tuple(rheology_output_filenames(bundle, template).values())
    if template == "point_line":
        return (f"{input_path.stem}_point_line.pdf",)
    if template == "curve":
        return (f"{input_path.stem}_curve.pdf",)
    if template == "stacked_curve":
        return (f"{input_path.stem}_stacked_curve.pdf",)
    if template == "segmented_stacked_curve":
        return (f"{input_path.stem}_segmented_stacked_curve.pdf",)
    if template == "scatter":
        return (f"{input_path.stem}_scatter.pdf",)
    if template == "heatmap":
        return (f"{input_path.stem}_heatmap.pdf",)
    if template in {"bar", "box", "violin"}:
        groups = load_replicate_table_cached(input_path, sheet)
        slug = predict_bar_box_slug(groups)
        return (f"{slug}_{template}.pdf",)
    return ()


def build_default_segmented_config(series_list: list[CurveSeries]) -> WideNMRConfig:
    x_min = min(float(series.data["x"].min()) for series in series_list)
    x_max = max(float(series.data["x"].max()) for series in series_list)
    return WideNMRConfig(
        segments=(WideNMRSegment(x_min=x_min, x_max=x_max),),
        series_order=tuple(series.sample for series in series_list),
    )


def load_segmented_config(
    input_path: Path,
    series_list: list[CurveSeries],
    *,
    use_sidecar: bool | None,
) -> WideNMRConfig:
    sidecar_path = wide_nmr_sidecar_path(input_path)
    if use_sidecar is False:
        return build_default_segmented_config(series_list)
    if sidecar_path.exists():
        return load_wide_nmr_config(input_path)
    if use_sidecar:
        raise FileNotFoundError(f"Missing segmented_stacked_curve sidecar config: {sidecar_path}")
    return build_default_segmented_config(series_list)


def append_multi_output_warning(warnings: list[str], preview_names: tuple[str, ...]) -> None:
    if len(preview_names) > 1:
        warnings.append(
            f"{validation_rule('multi_output_bundle_notice').description} "
            f"This run will export {len(preview_names)} PDF files."
        )


__all__ = [
    "append_multi_output_warning",
    "humanize_preflight_exception",
    "load_segmented_config",
    "load_rheology_bundle_series",
    "looks_like_tensile_curve",
    "predict_bar_box_slug",
    "preview_output_filenames",
    "rheology_output_filenames",
    "style_preflight_warnings",
    "TENSILE_LINEAR_SCALE_ERROR",
    "to_curve_series",
    "validate_rheology_bundle_scales",
    "validate_series_scales",
]
