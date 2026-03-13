from __future__ import annotations

from pathlib import Path

from src.plot_contract import validation_rule
from src.rendering.cache import (
    load_curve_table_cached,
    load_frequency_sweep_metrics_cached,
    load_heatmap_table_cached,
    load_replicate_table_cached,
    load_stress_relaxation_metric_cached,
    load_temperature_sweep_metrics_cached,
)
from src.rendering.common import (
    append_multi_output_warning,
    humanize_preflight_exception,
    load_segmented_config,
    preview_output_filenames,
    style_preflight_warnings,
    to_curve_series,
    validate_series_scales,
)
from src.rendering.models import PreflightResult, RenderOptions, TemplateName
from src.rendering.recommendation import detect_point_line_bundle


def preflight_render_request(
    template: TemplateName,
    input_path: Path,
    sheet: str | int,
    options: RenderOptions,
) -> PreflightResult:
    warnings: list[str] = list(style_preflight_warnings(options))
    errors: list[str] = []
    bundle = detect_point_line_bundle(input_path, sheet) if template == "point_line" else None

    try:
        if template == "point_line":
            if bundle == "frequency_sweep":
                metric_series = load_frequency_sweep_metrics_cached(input_path, sheet)
                for metric_name, rheology_series in metric_series.items():
                    if not rheology_series:
                        raise ValueError(f"频率扫描缺少指标数据：{metric_name}")
                    validate_series_scales(
                        to_curve_series(rheology_series),
                        xscale=options.xscale,
                        yscale=options.yscale,
                    )
            elif bundle == "temperature_sweep":
                metric_series = load_temperature_sweep_metrics_cached(input_path, sheet)
                for metric_name, rheology_series in metric_series.items():
                    if not rheology_series:
                        raise ValueError(f"温度扫描缺少指标数据：{metric_name}")
                    validate_series_scales(
                        to_curve_series(rheology_series),
                        xscale=options.xscale,
                        yscale=options.yscale,
                    )
            elif bundle == "stress_relaxation":
                relaxation_series = to_curve_series(
                    load_stress_relaxation_metric_cached(input_path, "σ/σ₀", sheet)
                )
                if not relaxation_series:
                    raise ValueError("应力松弛表中没有读到 σ/σ₀ 曲线。")
                validate_series_scales(relaxation_series, xscale=options.xscale, yscale=options.yscale)
            else:
                curve_series = load_curve_table_cached(input_path, sheet)
                validate_series_scales(curve_series, xscale=options.xscale, yscale=options.yscale)
        elif template == "curve":
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
                raise ValueError("统计表没有有效分组。")
            if len(groups) >= 6:
                warnings.append(validation_rule("dense_group_label_warning").description)
        elif template == "heatmap":
            load_heatmap_table_cached(input_path, sheet)
        else:
            raise ValueError(f"Unsupported template in preflight: {template}")
    except Exception as exc:
        errors.append(humanize_preflight_exception(exc))

    if not errors:
        preview_names = preview_output_filenames(template, input_path, sheet, bundle)
        append_multi_output_warning(warnings, preview_names)
    else:
        preview_names = ()

    return PreflightResult(
        template=template,
        warnings=tuple(warnings),
        errors=tuple(errors),
        output_filenames=preview_names,
    )


__all__ = ["preflight_render_request"]
