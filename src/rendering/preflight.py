from __future__ import annotations

from pathlib import Path

from src.plot_contract import validation_rule
from src.rendering.cache import (
    load_curve_table_cached,
    load_heatmap_table_cached,
    load_replicate_table_cached,
)
from src.rendering.common import (
    aligned_replicate_band,
    append_multi_output_warning,
    humanize_preflight_exception,
    load_segmented_config,
    preview_output_filenames,
    style_preflight_warnings,
    summarize_replicate_distribution,
    validate_rheology_bundle_scales,
    validate_series_scales,
)
from src.rendering.dataset_models import build_normalized_dataset
from src.rendering.models import PreflightResult, RenderOptions, TemplateName
from src.rendering.template_lifecycle import template_family_ids, template_identity
from src.submission import build_render_submission_report

_FIT_SCATTER_TEMPLATES = set(template_family_ids("scatter_fit"))
_MEAN_BAND_TEMPLATES = set(template_family_ids("mean_band"))
_GROUPED_BAR_ERROR_TEMPLATES = set(template_family_ids("grouped_bar_error"))


def preflight_render_request(
    template: TemplateName,
    input_path: Path,
    sheet: str | int,
    options: RenderOptions,
) -> PreflightResult:
    identity = template_identity(template)
    warnings: list[str] = list(style_preflight_warnings(options))
    errors: list[str] = []
    normalized_dataset = (
        build_normalized_dataset(input_path, sheet)
        if template in {"point_line", "curve"} | _FIT_SCATTER_TEMPLATES | _MEAN_BAND_TEMPLATES
        else None
    )

    try:
        if template in {"point_line", "curve"} | _MEAN_BAND_TEMPLATES:
            if normalized_dataset and normalized_dataset.model in {
                "frequency_sweep",
                "temperature_sweep",
                "stress_relaxation",
            }:
                if template in _MEAN_BAND_TEMPLATES:
                    raise ValueError(f"{template} is not supported for rheology export bundles.")
                validate_rheology_bundle_scales(
                    normalized_dataset.model,
                    input_path,
                    sheet,
                    xscale=options.xscale,
                    yscale=options.yscale,
                )
            else:
                curve_series = load_curve_table_cached(input_path, sheet)
                validate_series_scales(curve_series, xscale=options.xscale, yscale=options.yscale)
                if template in _MEAN_BAND_TEMPLATES:
                    aligned_replicate_band(curve_series)
        elif template == "stacked_curve":
            load_curve_table_cached(input_path, sheet)
        elif template == "segmented_stacked_curve":
            curve_series = load_curve_table_cached(input_path, sheet)
            load_segmented_config(
                input_path,
                curve_series,
                use_sidecar=True if options.use_sidecar is None else options.use_sidecar,
            )
        elif template == "scatter":
            curve_series = load_curve_table_cached(input_path, sheet)
            validate_series_scales(curve_series, xscale=options.xscale, yscale=options.yscale)
        elif template in _FIT_SCATTER_TEMPLATES:
            curve_series = load_curve_table_cached(input_path, sheet)
            validate_series_scales(curve_series, xscale=options.xscale, yscale=options.yscale)
            if not curve_series:
                raise ValueError("No valid X/Y series found.")
            for series in curve_series:
                data = series.data.dropna(subset=["x", "y"])
                if data.shape[0] < 2:
                    raise ValueError(
                        f"Series {series.sample!r} does not contain enough points for a deterministic linear fit."
                    )
                if data["x"].nunique() < 2:
                    raise ValueError(
                        f"Series {series.sample!r} has constant x values, so a linear fit cannot be computed."
                    )
        elif template in {
            "bar",
            "box",
            "box_strip",
            "violin",
            "violin_box",
            "grouped_bar_compare",
            "grouped_bar_error",
            "point_error",
            "distribution_compare",
            "histogram_density",
        }:
            groups = load_replicate_table_cached(input_path, sheet)
            if not groups:
                raise ValueError("No valid groups were found in the replicate table.")
            summary = summarize_replicate_distribution(groups)
            if template in _GROUPED_BAR_ERROR_TEMPLATES | {"distribution_compare"} and len(groups) < 2:
                raise ValueError(f"{template} requires at least two replicate groups.")
            if template == "distribution_compare" and summary.min_group_points < 3:
                warnings.append(
                    "Some groups have very few replicates, so distribution_compare may fall back to a simpler variant."
                )
            if template == "histogram_density":
                if summary.total_points < 12 or summary.min_group_points < 4:
                    warnings.append(
                        "Histogram-density overlays are less stable with sparse replicates; "
                        "box/distribution views may read better."
                    )
                if summary.total_points >= 8 and summary.pooled_unique_ratio <= 0.35:
                    warnings.append(
                        "Values are highly discrete, so histogram-density overlays may look blocky."
                    )
            if len(groups) >= 6:
                warnings.append(validation_rule("dense_group_label_warning").description)
        elif template in {"heatmap", "annotated_heatmap"}:
            table = load_heatmap_table_cached(input_path, sheet)
            if template == "annotated_heatmap":
                x_count = int(table.data["x"].nunique(dropna=True))
                y_count = int(table.data["y"].nunique(dropna=True))
                matrix_cells = x_count * y_count
                if x_count < 2 or y_count < 2:
                    warnings.append(
                        "Annotated heatmap adds limited value for single-row/column matrices; "
                        "plain heatmap may be clearer."
                    )
                if matrix_cells > 225:
                    warnings.append(
                        "Annotated heatmap may become dense at this matrix size; "
                        "consider plain heatmap for readability."
                    )
        else:
            raise ValueError(f"Unsupported template in preflight: {template}")
    except Exception as exc:
        errors.append(humanize_preflight_exception(exc))

    if not errors:
        preview_names = preview_output_filenames(
            template,
            input_path,
            sheet,
            normalized_dataset.model if normalized_dataset else None,
        )
        append_multi_output_warning(warnings, preview_names)
    else:
        preview_names = ()

    return PreflightResult(
        template=template,
        requested_template_id=identity.requested_template_id,
        canonical_id=identity.canonical_id,
        role=identity.role,
        lifecycle_policy=identity.lifecycle_policy,
        implementation_id=identity.implementation_id,
        warnings=tuple(warnings),
        errors=tuple(errors),
        output_filenames=preview_names,
        submission_report=build_render_submission_report(
            context="preflight",
            template=template,
            options=options,
            output_filenames=preview_names,
            blockers=errors,
            warnings=warnings,
        ),
    )


__all__ = ["preflight_render_request"]
