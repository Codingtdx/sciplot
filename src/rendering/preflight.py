from __future__ import annotations

from pathlib import Path

from src.plot_contract import validation_rule
from src.rendering.cache import (
    load_curve_table_cached,
    load_heatmap_table_cached,
    load_replicate_table_cached,
)
from src.rendering.common import (
    append_multi_output_warning,
    humanize_preflight_exception,
    load_segmented_config,
    preview_output_filenames,
    style_preflight_warnings,
    validate_rheology_bundle_scales,
    validate_series_scales,
)
from src.rendering.models import PreflightResult, RenderOptions, TemplateName
from src.rendering.dataset_models import build_normalized_dataset
from src.submission import build_render_submission_report


def preflight_render_request(
    template: TemplateName,
    input_path: Path,
    sheet: str | int,
    options: RenderOptions,
) -> PreflightResult:
    warnings: list[str] = list(style_preflight_warnings(options))
    errors: list[str] = []
    normalized_dataset = build_normalized_dataset(input_path, sheet) if template in {"point_line", "curve"} else None

    try:
        if template in {"point_line", "curve"}:
            if normalized_dataset and normalized_dataset.model in {"frequency_sweep", "temperature_sweep", "stress_relaxation"}:
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
        elif template in {"bar", "box", "violin"}:
            groups = load_replicate_table_cached(input_path, sheet)
            if not groups:
                raise ValueError("No valid groups were found in the replicate table.")
            if len(groups) >= 6:
                warnings.append(validation_rule("dense_group_label_warning").description)
        elif template == "heatmap":
            load_heatmap_table_cached(input_path, sheet)
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
