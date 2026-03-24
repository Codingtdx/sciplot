from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

from fastapi import APIRouter

from app.sidecar.schemas import (
    ExportRenderRequest,
    ExportRenderResponse,
    FileRequest,
    InspectFileResponse,
    PreflightRenderResponse,
    RenderPreviewResponse,
    RenderRequest,
    rendered_plots_to_preview_payload,
    serialize_dataclass,
)
from app.sidecar.server_utils import (
    bundle_manifest_payload,
    http_bad_request,
    normalize_path,
    options_from_payload,
    preview_artifact_path,
    write_json_artifact,
)
from src.rendering import (
    build_rendered_plots,
    close_rendered_plots,
    coerce_sheet,
    export_rendered_plots,
    inspect_input_file,
    list_sheet_names,
    preflight_render_request,
    prepare_managed_plot_export_dir,
    validate_template_name,
)
from src.submission import build_render_submission_report


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
            return InspectFileResponse.model_validate(
                {
                    "input_path": str(input_path),
                    "sheet": sheet,
                    "sheet_names": list_sheet_names(input_path),
                    "inspection": serialize_dataclass(inspection),
                }
            )
        except Exception as exc:
            raise http_bad_request("inspect", exc) from exc

    @router.post("/recommend-render", response_model=InspectFileResponse)
    def recommend_render(request: FileRequest) -> InspectFileResponse:
        return inspect_file(request)

    @router.post("/preflight-render", response_model=PreflightRenderResponse)
    def preflight_render(request: RenderRequest) -> PreflightRenderResponse:
        try:
            input_path = normalize_path(request.input_path)
            template = validate_template_name(request.template)
            sheet = coerce_sheet(str(request.sheet))
            options = options_from_payload(template, request.options)
            preflight = preflight_render_request(template, input_path, sheet, options)
            return PreflightRenderResponse.model_validate(
                {
                    "input_path": str(input_path),
                    "template": template,
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
            template = validate_template_name(request.template)
            sheet = coerce_sheet(str(request.sheet))
            payload_options = request.options
            resolved_options = options_from_payload(template, payload_options)
            rendered_plots = build_rendered_plots(
                template,
                input_path,
                sheet,
                size=payload_options.size,
                xscale=payload_options.xscale,
                yscale=payload_options.yscale,
                reverse_x=payload_options.reverse_x,
                baseline=payload_options.baseline,
                show_colorbar=payload_options.show_colorbar,
                style_preset=payload_options.style_preset,
                palette_preset=payload_options.palette_preset,
                use_sidecar=payload_options.use_sidecar,
                visual_theme_id=payload_options.visual_theme_id,
            )
            try:
                previews = rendered_plots_to_preview_payload(rendered_plots)
                submission_report = build_render_submission_report(
                    context="preview",
                    template=template,
                    options=resolved_options,
                    output_filenames=[rendered.filename for rendered in rendered_plots],
                    qa_reports=[rendered.qa_report for rendered in rendered_plots],
                )
            finally:
                close_rendered_plots(rendered_plots)
            return RenderPreviewResponse(
                template=template,
                sheet=sheet,
                previews=previews,
                submission_report=serialize_dataclass(submission_report),
            )
        except Exception as exc:
            raise http_bad_request("preview", exc) from exc

    @router.post("/export-render", response_model=ExportRenderResponse)
    def export_render(request: ExportRenderRequest) -> ExportRenderResponse:
        try:
            input_path = normalize_path(request.input_path)
            template = validate_template_name(request.template)
            sheet = coerce_sheet(str(request.sheet))
            payload_options = request.options
            managed_output_dir_fn = _dep(
                "prepare_managed_plot_export_dir",
                prepare_managed_plot_export_dir,
            )
            output_dir = (
                Path(request.output_dir).expanduser()
                if request.output_dir
                else managed_output_dir_fn(input_path, sheet=sheet, template=template)
            )
            output_dir.mkdir(parents=True, exist_ok=True)
            resolved_options = options_from_payload(template, payload_options)
            inspection = inspect_input_file(input_path, sheet)
            preflight = preflight_render_request(template, input_path, sheet, resolved_options)
            if preflight.errors:
                raise ValueError("\n".join(preflight.errors))
            created_paths: list[Path] = []
            expected_output_existence = {
                output_dir / filename: (output_dir / filename).exists()
                for filename in preflight.output_filenames
            }
            rendered_plots = build_rendered_plots(
                template,
                input_path,
                sheet,
                size=payload_options.size,
                xscale=payload_options.xscale,
                yscale=payload_options.yscale,
                reverse_x=payload_options.reverse_x,
                baseline=payload_options.baseline,
                show_colorbar=payload_options.show_colorbar,
                style_preset=payload_options.style_preset,
                palette_preset=payload_options.palette_preset,
                use_sidecar=payload_options.use_sidecar,
                visual_theme_id=payload_options.visual_theme_id,
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
                    template=template,
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
                    template=template,
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
