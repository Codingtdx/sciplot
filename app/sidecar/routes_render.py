from __future__ import annotations

import hashlib
import json
from collections.abc import Callable
from pathlib import Path
from typing import Any, cast

from fastapi import APIRouter

from app.sidecar.project_bundle import (
    is_supported_project_path,
    normalize_project_path,
    open_project_bundle,
    project_extension_error,
    save_project_bundle,
)
from app.sidecar.schemas import (
    ExportRenderRequest,
    ExportRenderResponse,
    FileRequest,
    FitAnalysisRequest,
    FitAnalysisResponse,
    InspectFileResponse,
    OpenProjectRequest,
    OpenProjectResponse,
    PreflightRenderResponse,
    RenderPreviewResponse,
    RenderRequest,
    SaveProjectRequest,
    SaveProjectResponse,
    SourceTablePreviewRequest,
    SourceTablePreviewResponse,
    rendered_plots_to_preview_payload,
    serialize_dataclass,
)
from app.sidecar.server_utils import (
    bundle_manifest_payload,
    data_engine_options_from_payload,
    http_bad_request,
    normalize_path,
    options_from_payload,
    preview_artifact_path,
    render_options_from_payload,
    write_json_artifact,
)
from src.core.application.render import (
    build_normalized_dataset,
    build_render_submission_report,
    build_rendered_plots_from_options,
    close_rendered_plots,
    coerce_sheet,
    dataframe_sample_rows,
    export_rendered_plots,
    inspect_input_file,
    list_sheet_names,
    normalized_dataset_payload,
    preflight_render_request,
    resolve_template_id,
    template_identity,
    validate_template_name,
)
from src.infrastructure.persistence.plot_exports import prepare_managed_plot_export_dir
from src.infrastructure.runtime_cache import LRUCache
from src.rendering.cache import load_curve_table_for_options, read_raw_table_cached, read_raw_table_for_options
from src.rendering.data_containers import (
    fit_result_container,
)
from src.rendering.data_containers import (
    source_table_data_containers as runtime_source_table_data_containers,
)
from src.rendering.fit_analysis import fit_series_list
from src.rendering.recommendation import model_label
from src.rendering.recommendation_policy import build_recommendation_presentation
from src.rendering.recommender import DEFAULT_RECOMMENDER
from src.rendering.source_table_preview import SourceTablePreview
from src.rendering.source_table_preview import source_table_preview as build_source_table_preview

_RENDER_PREVIEW_CACHE = LRUCache[str, RenderPreviewResponse](maxsize=64)


def _stable_json_hash(payload: object) -> str:
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _render_preview_cache_key(
    *,
    input_path: Path,
    sheet: str | int,
    template: str,
    options_payload: object,
    fit_options_payload: object,
    preview_config_payload: object,
) -> str:
    return _stable_json_hash(
        {
            "input_path": str(input_path.resolve()),
            "input_mtime_ns": input_path.stat().st_mtime_ns,
            "sheet": str(sheet),
            "template": template,
            "options": options_payload,
            "fit_options": fit_options_payload,
            "preview_config": preview_config_payload,
        }
    )


def _inspection_payload_and_preview_rows(
    input_path: Path,
    sheet: str | int,
    options: object,
) -> tuple[dict[str, object], object, object]:
    if getattr(options, "data_transforms", None):
        normalized_dataset = build_normalized_dataset(input_path, sheet, options=options)
        ranked = DEFAULT_RECOMMENDER.recommend(normalized_dataset, limit=10)
        presentation = build_recommendation_presentation(ranked)
        inspection_payload: dict[str, object] = {
            "model": normalized_dataset.model,
            "model_label": model_label(normalized_dataset.model),
            "recommendations": [serialize_dataclass(item) for item in ranked],
            "primary_recommendation": [serialize_dataclass(item) for item in presentation.primary_recommendation],
            "alternative_recommendations": [
                serialize_dataclass(item) for item in presentation.alternative_recommendations
            ],
            "advanced_templates": [serialize_dataclass(item) for item in presentation.advanced_templates],
            "recommendation_confidence": 0.8 if ranked else 0.0,
            "recommendation_summary": "Recommendations are based on transformed data.",
            "warnings": [],
            "signals": list(normalized_dataset.semantic_signals),
        }
        raw = read_raw_table_for_options(input_path, sheet, options).dropna(axis=1, how="all")
        return inspection_payload, normalized_dataset, raw

    inspection = inspect_input_file(input_path, sheet)
    normalized_dataset = build_normalized_dataset(input_path, sheet, model=inspection.model)
    raw = read_raw_table_cached(input_path, sheet).dropna(axis=1, how="all")
    return serialize_dataclass(inspection), normalized_dataset, raw


def _bounded_page(offset: int, limit: int, *, maximum: int = 200) -> tuple[int, int]:
    return max(0, offset), max(1, min(limit, maximum))


_CONTAINER_ROLE_ORDER = ("x", "y", "z", "group", "sample", "value", "metric", "label", "series")


def _role_hints_for_column(column_name: str, role_payload: dict[str, Any]) -> list[str]:
    return [
        role
        for role in _CONTAINER_ROLE_ORDER
        if column_name in {str(value) for value in role_payload.get(role, [])}
    ]


def _unit_from_profile(profile: dict[str, Any] | None) -> str | None:
    if not profile:
        return None
    header_preview = profile.get("header_preview")
    if not isinstance(header_preview, list) or len(header_preview) < 2:
        return None
    unit = header_preview[1]
    if isinstance(unit, str) and unit.strip():
        return unit
    return None


def _numeric_values(rows: tuple[tuple[Any, ...], ...], column_index: int) -> list[float]:
    values: list[float] = []
    for row in rows:
        if column_index >= len(row):
            continue
        try:
            values.append(float(row[column_index]))
        except (TypeError, ValueError):
            continue
    return values


def _source_table_data_containers(
    preview: SourceTablePreview,
    *,
    transform_count: int = 0,
    variable_count: int = 0,
) -> list[dict[str, Any]]:
    roles = serialize_dataclass(preview.candidate_roles)
    role_payload = roles if isinstance(roles, dict) else {}
    profile_payloads = [
        profile
        for profile in (serialize_dataclass(item) for item in preview.column_profiles)
        if isinstance(profile, dict)
    ]
    columns: list[dict[str, Any]] = []
    for index, name in enumerate(preview.column_headers):
        profile = profile_payloads[index] if index < len(profile_payloads) else None
        columns.append(
            {
                "id": f"col-{index}",
                "name": str(name),
                "index": index,
                "role_hints": _role_hints_for_column(str(name), role_payload),
                "unit": _unit_from_profile(profile),
                "comment": None,
                "profile": profile,
            }
        )

    sheet = preview.sheet
    source = {
        "input_path": str(preview.input_path),
        "sheet": sheet,
        "selected_segment_id": preview.selected_segment_id,
        "encoding": preview.encoding,
        "delimiter": preview.delimiter,
        "offset": int(preview.offset),
        "limit": int(preview.limit),
        "transform_count": transform_count,
        "variable_count": variable_count,
    }
    containers: list[dict[str, Any]] = [
        {
            "id": f"source-table:{sheet}",
            "kind": "table",
            "label": f"{sheet} table",
            "status": "enabled",
            "readonly": True,
            "row_count": int(preview.total_rows),
            "column_count": int(preview.total_cols),
            "columns": columns,
            "source": source,
            "help": "Readonly table container generated by source preview.",
        }
    ]
    if transform_count:
        containers.append(
            {
                "id": f"transformed-view:{sheet}",
                "kind": "transformed_view",
                "label": f"{sheet} transformed view",
                "status": "enabled",
                "readonly": True,
                "row_count": int(preview.total_rows),
                "column_count": int(preview.total_cols),
                "columns": columns,
                "source": source,
                "diagnostics": [
                    {
                        "status_code": "transforms_applied",
                        "message": f"Applied {transform_count} typed data transform(s).",
                    }
                ],
                "help": "Readonly transformed view generated by the typed data engine.",
            }
        )
    if role_payload.get("x") and role_payload.get("y") and role_payload.get("z") and preview.total_cols >= 3:
        x_values = sorted(set(_numeric_values(preview.rows, 0)))
        y_values = sorted(set(_numeric_values(preview.rows, 1)))
        containers.append(
            {
                "id": f"matrix:{sheet}",
                "kind": "matrix",
                "label": f"{sheet} scalar field",
                "status": "enabled",
                "readonly": True,
                "row_count": int(preview.total_rows),
                "column_count": int(preview.total_cols),
                "columns": columns,
                "source": source,
                "dimensions": {"rows": len(y_values), "columns": len(x_values)},
                "coordinate_vectors": {"x": x_values, "y": y_values},
                "missing_value_policy": "preserve",
                "diagnostics": [
                    {
                        "status_code": "matrix_detected",
                        "message": "XYZ scalar-field preview has a matrix container landing.",
                    }
                ],
                "help": "Matrix container generated from XYZ scalar-field roles.",
            }
        )
    return containers


def create_render_router(*, dep_provider: Callable[[], object] | None = None) -> APIRouter:
    router = APIRouter()

    def _dep(name: str, default: object) -> object:
        if dep_provider is None:
            return default
        return getattr(dep_provider(), name, default)

    @router.post("/inspect-file", response_model=InspectFileResponse)
    def inspect_file(request: FileRequest) -> InspectFileResponse:
        try:
            input_path = normalize_path(request.input_path)
            sheet = coerce_sheet(str(request.sheet))
            transform_options = data_engine_options_from_payload(request.options)
            inspection_payload, normalized_dataset, raw = _inspection_payload_and_preview_rows(
                input_path,
                sheet,
                transform_options,
            )
            return InspectFileResponse.model_validate(
                {
                    "input_path": str(input_path),
                    "sheet": sheet,
                    "sheet_names": list_sheet_names(input_path),
                    "inspection": inspection_payload,
                    "dataset": {
                        **normalized_dataset_payload(normalized_dataset),
                        "sample_rows": dataframe_sample_rows(raw),
                    },
                }
            )
        except Exception as exc:
            raise http_bad_request("inspect", exc) from exc

    @router.post("/source-table-preview", response_model=SourceTablePreviewResponse)
    def source_table_preview(request: SourceTablePreviewRequest) -> SourceTablePreviewResponse:
        try:
            input_path = normalize_path(request.input_path)
            sheet = coerce_sheet(str(request.sheet))
            offset, limit = _bounded_page(request.offset, request.limit)
            transform_options = data_engine_options_from_payload(request.options)
            preview = build_source_table_preview(
                input_path,
                sheet=sheet,
                offset=offset,
                limit=limit,
                encoding=request.encoding,
                delimiter=request.delimiter,
                segment_id=request.segment_id,
                header_row_index=request.header_row_index,
                unit_row_index=request.unit_row_index,
                data_start_row_index=request.data_start_row_index,
                data_transforms=transform_options.data_transforms,
                data_variables=transform_options.data_variables,
            )
            return SourceTablePreviewResponse.model_validate(
                {
                    "input_path": str(preview.input_path),
                    "sheet": preview.sheet,
                    "offset": preview.offset,
                    "limit": preview.limit,
                    "total_rows": preview.total_rows,
                    "total_cols": preview.total_cols,
                    "column_headers": list(preview.column_headers),
                    "rows": [list(row) for row in preview.rows],
                    "candidate_roles": serialize_dataclass(preview.candidate_roles),
                    "detected_x_label": preview.detected_x_label,
                    "detected_y_label": preview.detected_y_label,
                    "column_profiles": [serialize_dataclass(profile) for profile in preview.column_profiles],
                    "segments": [serialize_dataclass(segment) for segment in preview.segments],
                    "selected_segment_id": preview.selected_segment_id,
                    "encoding": preview.encoding,
                    "delimiter": preview.delimiter,
                    "diagnostics": list(preview.diagnostics),
                    "data_containers": runtime_source_table_data_containers(
                        preview,
                        transform_count=len(transform_options.data_transforms or []),
                        variable_count=len(transform_options.data_variables or []),
                    ),
                }
            )
        except Exception as exc:
            raise http_bad_request("source-table-preview", exc) from exc

    @router.post("/fit-analysis", response_model=FitAnalysisResponse)
    def fit_analysis(request: FitAnalysisRequest) -> FitAnalysisResponse:
        try:
            input_path = normalize_path(request.input_path)
            sheet = coerce_sheet(str(request.sheet))
            offset, limit = _bounded_page(request.offset, request.limit)
            transform_options = data_engine_options_from_payload(request.options)
            series_list = load_curve_table_for_options(input_path, sheet, transform_options)
            fit_result = fit_series_list(
                series_list,
                model_id=request.model_id,
                custom_function=request.custom_function,
            )
            selected_series = fit_result.selected_series(request.series_id)
            rows = selected_series.derived_rows[offset : offset + limit]
            fit_container = fit_result_container(
                input_path=input_path,
                sheet=sheet,
                series_id=selected_series.series_id,
                series_label=selected_series.series_label,
                x_label=selected_series.x_label,
                y_label=selected_series.y_label,
                row_count=len(selected_series.derived_rows),
                offset=offset,
                limit=limit,
                r_squared=selected_series.r_squared,
                rmse=selected_series.rmse,
                point_count=selected_series.point_count,
                transform_count=len(transform_options.data_transforms or []),
                variable_count=len(transform_options.data_variables or []),
            )
            return FitAnalysisResponse.model_validate(
                {
                    "input_path": str(input_path),
                    "sheet": sheet,
                    "model_id": request.model_id,
                    "x_label": selected_series.x_label,
                    "y_label": selected_series.y_label,
                    "selected_series_id": selected_series.series_id,
                    "equation_display": selected_series.equation_display,
                    "slope": selected_series.slope,
                    "intercept": selected_series.intercept,
                    "r_squared": selected_series.r_squared,
                    "rmse": selected_series.rmse,
                    "point_count": selected_series.point_count,
                    "series_summaries": [
                        {
                            "series_id": result.series_id,
                            "series_label": result.series_label,
                            "equation_display": result.equation_display,
                            "r_squared": result.r_squared,
                            "rmse": result.rmse,
                            "point_count": result.point_count,
                            "slope": result.slope,
                            "intercept": result.intercept,
                            "warnings": list(result.warnings),
                        }
                        for result in fit_result.series_results
                    ],
                    "warnings": list(fit_result.warnings) + list(selected_series.warnings),
                    "total_rows": len(selected_series.derived_rows),
                    "offset": offset,
                    "limit": limit,
                    "rows": [serialize_dataclass(row) for row in rows],
                    "operation_result": {
                        "operation_id": "analysis.fit",
                        "available": True,
                        "valid": not selected_series.warnings,
                        "status_code": "ok" if not selected_series.warnings else "warning",
                        "message": "Fit analysis complete.",
                        "diagnostics": [
                            {"status_code": "fit_warning", "message": warning}
                            for warning in selected_series.warnings
                        ],
                        "metrics": {
                            "r_squared": selected_series.r_squared,
                            "rmse": selected_series.rmse,
                            "point_count": selected_series.point_count,
                        },
                        "tables": [
                            {
                                "id": f"fit-table:{selected_series.series_id}",
                                "row_count": len(selected_series.derived_rows),
                                "columns": ["x", "y", "y_fit", "residual"],
                            }
                        ],
                        "overlays": [
                            {
                                "kind": "fit_overlay",
                                "series_id": selected_series.series_id,
                                "model_id": request.model_id,
                            }
                        ],
                        "data_containers": [fit_container],
                    },
                }
            )
        except Exception as exc:
            raise http_bad_request("fit-analysis", exc) from exc

    @router.post("/save-project", response_model=SaveProjectResponse)
    def save_project(request: SaveProjectRequest) -> SaveProjectResponse:
        try:
            project_path = Path(request.project_path).expanduser()
            if not is_supported_project_path(project_path):
                raise ValueError(project_extension_error())
            return save_project_bundle(
                project_path=project_path,
                source_path=normalize_path(request.source_path) if request.source_path else None,
                payload=request.payload,
            )
        except Exception as exc:
            raise http_bad_request("save-project", exc) from exc

    @router.post("/open-project", response_model=OpenProjectResponse)
    def open_project(request: OpenProjectRequest) -> OpenProjectResponse:
        try:
            return open_project_bundle(project_path=normalize_project_path(request.project_path))
        except Exception as exc:
            raise http_bad_request("open-project", exc) from exc

    @router.post("/preflight-render", response_model=PreflightRenderResponse)
    def preflight_render(request: RenderRequest) -> PreflightRenderResponse:
        try:
            input_path = normalize_path(request.input_path)
            sheet = coerce_sheet(str(request.sheet))
            requested_template = validate_template_name(request.template)
            resolved_template = resolve_template_id(requested_template, input_path=input_path, sheet=sheet)
            identity = template_identity(requested_template, resolved_template_id=resolved_template)
            options = options_from_payload(
                requested_template,
                request.options,
                input_path=input_path,
                sheet=sheet,
            )
            preflight = preflight_render_request(requested_template, input_path, sheet, options)
            return PreflightRenderResponse.model_validate(
                {
                    "input_path": str(input_path),
                    "template": preflight.template,
                    "requested_template_id": identity.requested_template_id,
                    "canonical_id": identity.canonical_id,
                    "role": identity.role,
                    "lifecycle_policy": identity.lifecycle_policy,
                    "implementation_id": identity.implementation_id,
                    "sheet": sheet,
                    "options": request.options.model_dump(),
                    "preflight": serialize_dataclass(preflight),
                }
            )
        except Exception as exc:
            raise http_bad_request("preflight", exc) from exc

    @router.post("/render-preview", response_model=RenderPreviewResponse)
    def render_preview(request: RenderRequest) -> RenderPreviewResponse:
        try:
            input_path = normalize_path(request.input_path)
            sheet = coerce_sheet(str(request.sheet))
            requested_template = validate_template_name(request.template)
            resolved_template = resolve_template_id(requested_template, input_path=input_path, sheet=sheet)
            identity = template_identity(requested_template, resolved_template_id=resolved_template)
            payload_options = request.options
            options_payload = payload_options.model_dump(mode="json")
            fit_options_payload = request.fit_options.model_dump(mode="json")
            preview_config_payload = (
                request.preview_config.model_dump(mode="json")
                if request.preview_config is not None
                else None
            )
            cache_key = _render_preview_cache_key(
                input_path=input_path,
                sheet=sheet,
                template=resolved_template,
                options_payload=options_payload,
                fit_options_payload=fit_options_payload,
                preview_config_payload=preview_config_payload,
            )
            cached = _RENDER_PREVIEW_CACHE.get(cache_key)
            if cached is not None:
                return cached.model_copy(deep=True)
            resolved_options = render_options_from_payload(
                requested_template,
                payload_options,
                input_path=input_path,
                sheet=sheet,
                fit_options=fit_options_payload,
            )
            rendered_plots = build_rendered_plots_from_options(
                requested_template,
                input_path,
                sheet,
                resolved_options,
                resolved_template_id=resolved_template,
            )
            try:
                previews = rendered_plots_to_preview_payload(rendered_plots, preview_config=request.preview_config)
                submission_report = build_render_submission_report(
                    context="preview",
                    template=resolved_template,
                    options=resolved_options,
                    output_filenames=[rendered.filename for rendered in rendered_plots],
                    qa_reports=[rendered.qa_report for rendered in rendered_plots],
                )
            finally:
                close_rendered_plots(rendered_plots)
            response = RenderPreviewResponse(
                template=resolved_template,
                requested_template_id=identity.requested_template_id,
                canonical_id=identity.canonical_id,
                role=identity.role,
                lifecycle_policy=identity.lifecycle_policy,
                implementation_id=identity.implementation_id,
                sheet=sheet,
                preview=previews[0] if previews else None,
                previews=previews,
                submission_report=serialize_dataclass(submission_report),
            )
            _RENDER_PREVIEW_CACHE.set(cache_key, response)
            return response
        except Exception as exc:
            raise http_bad_request("preview", exc) from exc

    @router.post("/export-render", response_model=ExportRenderResponse)
    def export_render(request: ExportRenderRequest) -> ExportRenderResponse:
        try:
            input_path = normalize_path(request.input_path)
            sheet = coerce_sheet(str(request.sheet))
            requested_template = validate_template_name(request.template)
            resolved_template = resolve_template_id(requested_template, input_path=input_path, sheet=sheet)
            identity = template_identity(requested_template, resolved_template_id=resolved_template)
            payload_options = request.options
            managed_output_dir_fn = cast(
                Callable[..., Path],
                _dep(
                    "prepare_managed_plot_export_dir",
                    prepare_managed_plot_export_dir,
                ),
            )
            output_dir = (
                Path(request.output_dir).expanduser()
                if request.output_dir
                else managed_output_dir_fn(input_path, sheet=sheet, template=resolved_template)
            )
            output_dir.mkdir(parents=True, exist_ok=True)
            resolved_options = render_options_from_payload(
                requested_template,
                payload_options,
                input_path=input_path,
                sheet=sheet,
                fit_options=request.fit_options.model_dump(mode="json"),
            )
            inspection_payload, _, _ = _inspection_payload_and_preview_rows(input_path, sheet, resolved_options)
            preflight = preflight_render_request(requested_template, input_path, sheet, resolved_options)
            if preflight.errors:
                raise ValueError("\n".join(preflight.errors))
            created_paths: list[Path] = []
            expected_output_existence = {
                output_dir / filename: (output_dir / filename).exists()
                for filename in preflight.output_filenames
            }
            rendered_plots = build_rendered_plots_from_options(
                requested_template,
                input_path,
                sheet,
                resolved_options,
                resolved_template_id=resolved_template,
            )
            try:
                outputs = export_rendered_plots(rendered_plots, output_dir, close=False)
                for path in outputs:
                    if not expected_output_existence.get(path, False):
                        created_paths.append(path)
                preview_outputs: list[Path] = []
                for rendered in rendered_plots:
                    preview_path = preview_artifact_path(output_dir, rendered.filename)
                    existed_before = preview_path.exists()
                    rendered.figure.savefig(
                        preview_path,
                        format="png",
                        dpi=220,
                        facecolor="white",
                        bbox_inches=None,
                    )
                    preview_outputs.append(preview_path)
                    if not existed_before:
                        created_paths.append(preview_path)

                submission_report = build_render_submission_report(
                    context="export",
                    template=resolved_template,
                    options=resolved_options,
                    output_filenames=[path.name for path in outputs],
                    qa_reports=[rendered.qa_report for rendered in rendered_plots],
                    blockers=preflight.errors,
                    warnings=preflight.warnings,
                )
                normalized_options_payload = serialize_dataclass(resolved_options)
                submission_payload = serialize_dataclass(submission_report)
                artifact_paths: list[Path] = []
                for filename, payload in (
                    ("sciplot_normalized_options.json", normalized_options_payload),
                    ("sciplot_inspection.json", inspection_payload),
                    ("sciplot_preflight.json", serialize_dataclass(preflight)),
                    ("sciplot_submission_report.json", submission_payload),
                ):
                    artifact_path = output_dir / filename
                    existed_before = artifact_path.exists()
                    artifact_paths.append(write_json_artifact(output_dir, filename, payload))
                    if not existed_before:
                        created_paths.append(artifact_path)
                manifest_path = output_dir / "sciplot_manifest.json"
                manifest_existed_before = manifest_path.exists()
                manifest_payload = bundle_manifest_payload(
                    input_path=input_path,
                    sheet=sheet,
                    requested_template_id=identity.requested_template_id,
                    canonical_template_id=identity.canonical_id,
                    output_dir=output_dir,
                    outputs=outputs,
                    preview_outputs=preview_outputs,
                    artifact_paths=artifact_paths,
                    submission_report=submission_payload,
                    inspection=inspection_payload,
                    options=normalized_options_payload,
                )
                manifest_path = write_json_artifact(
                    output_dir,
                    "sciplot_manifest.json",
                    manifest_payload,
                )
                artifact_paths.append(manifest_path)
                if not manifest_existed_before:
                    created_paths.append(manifest_path)
            finally:
                close_rendered_plots(rendered_plots)
            return ExportRenderResponse(
                requested_template_id=identity.requested_template_id,
                canonical_id=identity.canonical_id,
                role=identity.role,
                lifecycle_policy=identity.lifecycle_policy,
                implementation_id=identity.implementation_id,
                outputs=[str(path) for path in outputs],
                output_dir=str(output_dir),
                preview_outputs=[str(path) for path in preview_outputs],
                artifact_paths=[str(path) for path in artifact_paths],
                manifest_path=str(manifest_path),
                submission_report=serialize_dataclass(submission_report),
            )
        except Exception as exc:
            for path in reversed(locals().get("created_paths", [])):
                try:
                    path.unlink(missing_ok=True)
                except OSError:
                    pass
            raise http_bad_request("export", exc) from exc

    return router
