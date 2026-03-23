from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter

from app.sidecar.schemas import (
    CodeConsoleExportRequest,
    CodeConsoleExportResponse,
    CodeConsoleGenerateRequest,
    CodeConsoleGenerateResponse,
    CodeConsoleRunRequest,
    CodeConsoleRunResponse,
    RenderOptionsPayload,
    load_project_document,
)
from app.sidecar.server_utils import (
    code_console_payload_options,
    http_bad_request,
    normalize_path,
    optional_input_path,
    optional_project_path,
    options_from_payload,
    resolved_code_console_options,
)
from src.rendering import (
    coerce_sheet,
    export_code_console_bundle,
    generate_code_console_payload,
    run_code_console_python,
)


def create_code_console_router() -> APIRouter:
    router = APIRouter()

    @router.post("/code-console/generate", response_model=CodeConsoleGenerateResponse)
    def code_console_generate(
        request: CodeConsoleGenerateRequest,
    ) -> CodeConsoleGenerateResponse:
        try:
            input_path = optional_input_path(request.input_path)
            sheet = coerce_sheet(str(request.sheet)) if input_path is not None else None
            project_path = optional_project_path(request.project_path)
            project_payload = None
            if request.include_project_context and project_path is not None:
                project_payload = load_project_document(project_path)
            payload_options = code_console_payload_options(request)
            options = resolved_code_console_options(request)
            payload = generate_code_console_payload(
                intent=request.intent,
                brief=request.brief,
                base_template=request.base_template,
                size=payload_options.size,
                xscale=options.xscale,
                yscale=options.yscale,
                reverse_x=options.reverse_x,
                baseline=options.baseline,
                show_colorbar=options.show_colorbar,
                style_preset=options.style_preset,
                palette_preset=options.palette_preset,
                use_sidecar=options.use_sidecar,
                target_path=request.target_path,
                input_path=input_path,
                sheet=sheet,
                project_path=project_path,
                project_payload=project_payload,
                include_data_context=request.include_data_context,
                include_inspection_summary=request.include_inspection_summary,
                include_project_context=request.include_project_context,
            )
            return CodeConsoleGenerateResponse.model_validate(payload)
        except Exception as exc:
            raise http_bad_request("code_console_generate", exc) from exc

    @router.post(
        "/code-console/export-bundle",
        response_model=CodeConsoleExportResponse,
    )
    def code_console_export_bundle(
        request: CodeConsoleExportRequest,
    ) -> CodeConsoleExportResponse:
        try:
            input_path = optional_input_path(request.input_path)
            sheet = coerce_sheet(str(request.sheet)) if input_path is not None else None
            project_path = optional_project_path(request.project_path)
            project_payload = None
            if request.include_project_context and project_path is not None:
                project_payload = load_project_document(project_path)
            payload_options = code_console_payload_options(request)
            options = resolved_code_console_options(request)
            payload = generate_code_console_payload(
                intent=request.intent,
                brief=request.brief,
                base_template=request.base_template,
                size=payload_options.size,
                xscale=options.xscale,
                yscale=options.yscale,
                reverse_x=options.reverse_x,
                baseline=options.baseline,
                show_colorbar=options.show_colorbar,
                style_preset=options.style_preset,
                palette_preset=options.palette_preset,
                use_sidecar=options.use_sidecar,
                target_path=request.target_path,
                input_path=input_path,
                sheet=sheet,
                project_path=project_path,
                project_payload=project_payload,
                include_data_context=request.include_data_context,
                include_inspection_summary=request.include_inspection_summary,
                include_project_context=request.include_project_context,
            )
            exported = export_code_console_bundle(
                output_dir=Path(request.output_dir).expanduser(),
                payload=payload,
                include_full_data=request.include_full_data,
            )
            return CodeConsoleExportResponse.model_validate(exported)
        except Exception as exc:
            raise http_bad_request("code_console_export", exc) from exc

    @router.post("/code-console/run", response_model=CodeConsoleRunResponse)
    def code_console_run(request: CodeConsoleRunRequest) -> CodeConsoleRunResponse:
        try:
            input_path = normalize_path(request.input_path)
            sheet = coerce_sheet(str(request.sheet))
            project_path = optional_project_path(request.project_path)
            project_payload = None
            if request.include_project_context and project_path is not None:
                project_payload = load_project_document(project_path)
            payload_options = request.options or RenderOptionsPayload()
            options = options_from_payload(request.base_template, payload_options)
            payload = generate_code_console_payload(
                intent="custom_plot",
                brief="",
                base_template=request.base_template,
                size=payload_options.size,
                xscale=options.xscale,
                yscale=options.yscale,
                reverse_x=options.reverse_x,
                baseline=options.baseline,
                show_colorbar=options.show_colorbar,
                style_preset=options.style_preset,
                palette_preset=options.palette_preset,
                use_sidecar=options.use_sidecar,
                target_path="",
                input_path=input_path,
                sheet=sheet,
                project_path=project_path,
                project_payload=project_payload,
                include_data_context=True,
                include_inspection_summary=True,
                include_project_context=request.include_project_context,
            )
            result = run_code_console_python(request.code, payload=payload)
            return CodeConsoleRunResponse.model_validate(result)
        except Exception as exc:
            raise http_bad_request("code_console_run", exc) from exc

    return router
