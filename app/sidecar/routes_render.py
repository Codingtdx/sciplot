from __future__ import annotations

import hashlib
import json
from collections.abc import Callable
from pathlib import Path
from types import SimpleNamespace
from typing import cast

from fastapi import APIRouter

from app.sidecar.project_bundle import (
    normalize_project_path,
    open_project_bundle,
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
    read_raw_table_cached,
    resolve_template_id,
    template_identity,
    validate_template_name,
)
from src.infrastructure.persistence.plot_exports import prepare_managed_plot_export_dir
from src.infrastructure.runtime_cache import LRUCache
from src.rendering.cache import load_curve_table_for_options
from src.rendering.fit_analysis import fit_series_list
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
) -> str:
    return _stable_json_hash(
        {
            "input_path": str(input_path.resolve()),
            "input_mtime_ns": input_path.stat().st_mtime_ns,
            "sheet": str(sheet),
            "template": template,
            "options": options_payload,
            "fit_options": fit_options_payload,
        }
    )


def _bounded_page(offset: int, limit: int, *, maximum: int = 200) -> tuple[int, int]:
    return max(0, offset), max(1, min(limit, maximum))


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
            inspection = inspect_input_file(input_path, sheet)
            normalized_dataset = build_normalized_dataset(input_path, sheet, model=inspection.model)
            raw = read_raw_table_cached(input_path, sheet).dropna(axis=1, how="all")
            return InspectFileResponse.model_validate(
                {
                    "input_path": str(input_path),
                    "sheet": sheet,
                    "sheet_names": list_sheet_names(input_path),
                    "inspection": serialize_dataclass(inspection),
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
                data_transforms=(
                    [item.model_dump(mode="json") for item in request.options.data_transforms]
                    if request.options is not None and request.options.data_transforms
                    else None
                ),
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
            transform_options = SimpleNamespace(
                data_transforms=(
                    tuple(item.model_dump(mode="json") for item in request.options.data_transforms)
                    if request.options is not None and request.options.data_transforms
                    else None
                )
            )
            series_list = load_curve_table_for_options(input_path, sheet, transform_options)
            fit_result = fit_series_list(series_list, model_id=request.model_id)
            selected_series = fit_result.selected_series(request.series_id)
            rows = selected_series.derived_rows[offset : offset + limit]
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
                }
            )
        except Exception as exc:
            raise http_bad_request("fit-analysis", exc) from exc

    @router.post("/save-project", response_model=SaveProjectResponse)
    def save_project(request: SaveProjectRequest) -> SaveProjectResponse:
        try:
            project_path = Path(request.project_path).expanduser()
            if project_path.suffix.lower() != ".sciplotgod":
                raise ValueError("Project file must use the .sciplotgod extension.")
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
            cache_key = _render_preview_cache_key(
                input_path=input_path,
                sheet=sheet,
                template=resolved_template,
                options_payload=options_payload,
                fit_options_payload=fit_options_payload,
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
                previews = rendered_plots_to_preview_payload(rendered_plots)
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
            inspection = inspect_input_file(input_path, sheet)
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
                inspection_payload = serialize_dataclass(inspection)
                submission_payload = serialize_dataclass(submission_report)
                artifact_paths: list[Path] = []
                for filename, payload in (
                    ("codegod_normalized_options.json", normalized_options_payload),
                    ("codegod_inspection.json", inspection_payload),
                    ("codegod_preflight.json", serialize_dataclass(preflight)),
                    ("codegod_submission_report.json", submission_payload),
                ):
                    artifact_path = output_dir / filename
                    existed_before = artifact_path.exists()
                    artifact_paths.append(write_json_artifact(output_dir, filename, payload))
                    if not existed_before:
                        created_paths.append(artifact_path)
                manifest_path = output_dir / "codegod_manifest.json"
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
                    "codegod_manifest.json",
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
