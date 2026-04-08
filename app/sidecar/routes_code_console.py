from __future__ import annotations

from fastapi import APIRouter

from app.sidecar.schemas import (
    CodeConsoleContextRequest,
    CodeConsoleContextResponse,
    CodeConsoleRunRequest,
    CodeConsoleRunResponse,
)
from app.sidecar.server_utils import http_bad_request, normalize_path
from src.code_console_service import build_code_console_context, run_code_console_script


def create_code_console_router() -> APIRouter:
    router = APIRouter()

    @router.post("/code-console/context", response_model=CodeConsoleContextResponse)
    def code_console_context(request: CodeConsoleContextRequest) -> CodeConsoleContextResponse:
        try:
            input_path = normalize_path(request.input_path)
            context = build_code_console_context(
                input_path=input_path,
                sheet=request.sheet,
                template=request.template,
                size=request.options.size,
                style_preset=request.options.style_preset,
                palette_preset=request.options.palette_preset,
                visual_theme_id=request.options.visual_theme_id,
                source_kind=request.source_kind,
                source_label=request.source_label,
            )
            return CodeConsoleContextResponse.model_validate(
                {
                    "context_id": context.context_id,
                    "input_path": str(context.input_path),
                    "sheet": context.sheet,
                    "sheet_names": list(context.sheet_names),
                    "inspection": context.inspection,
                    "dataset": context.dataset,
                    "template": context.template,
                    "options": {
                        "size": context.options["size"],
                        "style_preset": context.options["style_preset"],
                        "palette_preset": context.options["palette_preset"],
                        "visual_theme_id": context.options["visual_theme_id"],
                    },
                    "prompt_text": context.prompt_text,
                    "starter_code": context.starter_code,
                    "source_kind": context.source_kind,
                    "source_label": context.source_label,
                }
            )
        except Exception as exc:
            raise http_bad_request("code-console-context", exc) from exc

    @router.post("/code-console/run", response_model=CodeConsoleRunResponse)
    def code_console_run(request: CodeConsoleRunRequest) -> CodeConsoleRunResponse:
        try:
            request_context = request.context
            input_path = normalize_path(request_context.input_path) if request_context else None
            result = run_code_console_script(
                context_id=request.context_id,
                input_path=input_path,
                sheet=request_context.sheet if request_context else None,
                template=request_context.template if request_context else None,
                size=request_context.options.size if request_context else None,
                style_preset=request_context.options.style_preset if request_context else None,
                palette_preset=request_context.options.palette_preset if request_context else None,
                visual_theme_id=request_context.options.visual_theme_id if request_context else None,
                code=request.code,
                timeout_seconds=request.timeout_seconds,
                source_kind=request_context.source_kind if request_context else None,
                source_label=request_context.source_label if request_context else None,
            )
            return CodeConsoleRunResponse.model_validate(
                {
                    "status": result.status,
                    "exit_code": result.exit_code,
                    "duration_seconds": result.duration_seconds,
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                    "run_dir": str(result.run_dir),
                    "output_dir": str(result.output_dir),
                    "script_path": str(result.script_path),
                    "prompt_path": str(result.prompt_path),
                    "context_path": str(result.context_path),
                    "stdout_path": str(result.stdout_path),
                    "stderr_path": str(result.stderr_path),
                    "generated_files": [
                        {
                            "path": str(item.path),
                            "name": item.name,
                            "file_type": item.file_type,
                            "size_bytes": item.size_bytes,
                        }
                        for item in result.generated_files
                    ],
                }
            )
        except Exception as exc:
            raise http_bad_request("code-console-run", exc) from exc

    return router


__all__ = ["create_code_console_router"]
