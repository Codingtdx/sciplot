from __future__ import annotations

from fastapi import APIRouter

from app.sidecar.schemas import (
    AnalysisOperationRequest,
    AnalysisOperationResponse,
    ImportPreviewRequest,
    ImportPreviewResponse,
    PlotEditCommandNormalizeRequest,
    PlotEditCommandNormalizeResponse,
)
from app.sidecar.server_utils import http_bad_request, normalize_path
from src.rendering.analysis_operations import run_analysis_operation
from src.rendering.import_filters import preview_import
from src.rendering.plot_object_commands import normalize_plot_edit_command


def create_labplot_runtime_router() -> APIRouter:
    router = APIRouter()

    @router.post("/analysis-operation", response_model=AnalysisOperationResponse)
    def analysis_operation(request: AnalysisOperationRequest) -> AnalysisOperationResponse:
        try:
            input_path = normalize_path(request.input_path)
            result = run_analysis_operation(
                operation_id=request.operation_id,
                input_path=input_path,
                sheet=request.sheet,
                x_column=request.x_column,
                y_column=request.y_column,
                parameters=request.parameters,
            )
            return AnalysisOperationResponse.model_validate(
                {
                    "operation_id": request.operation_id,
                    "input_path": str(input_path),
                    "sheet": request.sheet,
                    "operation_result": result,
                }
            )
        except Exception as exc:
            raise http_bad_request("analysis-operation", exc) from exc

    @router.post("/import-preview", response_model=ImportPreviewResponse)
    def import_preview(request: ImportPreviewRequest) -> ImportPreviewResponse:
        try:
            input_path = normalize_path(request.input_path)
            return ImportPreviewResponse.model_validate(
                preview_import(
                    input_path=input_path,
                    filter_id=request.filter_id,
                    sheet=request.sheet,
                    offset=request.offset,
                    limit=request.limit,
                    options=request.options,
                )
            )
        except Exception as exc:
            raise http_bad_request("import-preview", exc) from exc

    @router.post("/plot-edit-command/normalize", response_model=PlotEditCommandNormalizeResponse)
    def plot_edit_command_normalize(
        request: PlotEditCommandNormalizeRequest,
    ) -> PlotEditCommandNormalizeResponse:
        try:
            payload = normalize_plot_edit_command(
                request.command.model_dump(mode="json"),
                [item.model_dump(mode="json") for item in request.objects],
            )
            return PlotEditCommandNormalizeResponse.model_validate(payload)
        except Exception as exc:
            raise http_bad_request("plot-edit-command-normalize", exc) from exc

    return router


__all__ = ["create_labplot_runtime_router"]
