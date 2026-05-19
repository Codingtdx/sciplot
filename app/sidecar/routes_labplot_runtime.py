from __future__ import annotations

from fastapi import APIRouter

from app.sidecar.schemas import (
    AnalysisOperationRequest,
    AnalysisOperationResponse,
    CommandApplyPreviewRequest,
    CommandApplyPreviewResponse,
    CommandNormalizeRequest,
    CommandNormalizeResponse,
    ImportPreviewRequest,
    ImportPreviewResponse,
    LiveSourceUpdateRequest,
    LiveSourceUpdateResponse,
    PlotEditCommandNormalizeRequest,
    PlotEditCommandNormalizeResponse,
    PreviewSceneRequest,
    PreviewSceneResponse,
)
from app.sidecar.server_utils import http_bad_request, normalize_path
from src.rendering.analysis_operations import run_analysis_operation
from src.rendering.import_filters import preview_import
from src.rendering.live_sources import update_live_source
from src.rendering.plot_object_commands import apply_command_preview, normalize_plot_edit_command
from src.rendering.preview_scene import build_preview_scene


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
                operation_instance_id=request.operation_instance_id,
                module=request.module,
                x_column=request.x_column,
                y_column=request.y_column,
                parameters=request.parameters,
                source_binding=request.source_binding,
                recalculate_policy=request.recalculate_policy,
                graph_revision=request.graph_revision,
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

    @router.post("/command/normalize", response_model=CommandNormalizeResponse)
    def command_normalize(request: CommandNormalizeRequest) -> CommandNormalizeResponse:
        try:
            payload = normalize_plot_edit_command(
                request.command.model_dump(mode="json"),
                [item.model_dump(mode="json") for item in request.objects],
            )
            return CommandNormalizeResponse.model_validate(payload)
        except Exception as exc:
            raise http_bad_request("command-normalize", exc) from exc

    @router.post("/command/apply-preview", response_model=CommandApplyPreviewResponse)
    def command_apply_preview(request: CommandApplyPreviewRequest) -> CommandApplyPreviewResponse:
        try:
            payload = apply_command_preview(
                request.command.model_dump(mode="json"),
                request.document_graph,
            )
            return CommandApplyPreviewResponse.model_validate(payload)
        except Exception as exc:
            raise http_bad_request("command-apply-preview", exc) from exc

    @router.post("/preview-scene", response_model=PreviewSceneResponse)
    def preview_scene(request: PreviewSceneRequest) -> PreviewSceneResponse:
        try:
            input_path = normalize_path(request.input_path)
            payload = build_preview_scene(
                input_path=input_path,
                sheet=request.sheet,
                template=request.template,
                options=request.options.model_dump(mode="json"),
                fit_options=request.fit_options.model_dump(mode="json"),
                preview_config=(
                    request.preview_config.model_dump(mode="json")
                    if request.preview_config is not None
                    else None
                ),
            )
            return PreviewSceneResponse.model_validate(payload)
        except Exception as exc:
            raise http_bad_request("preview-scene", exc) from exc

    @router.post("/live-source/update-now", response_model=LiveSourceUpdateResponse)
    def live_source_update_now(request: LiveSourceUpdateRequest) -> LiveSourceUpdateResponse:
        try:
            input_path = normalize_path(request.input_path)
            payload = update_live_source(
                live_source=request.live_source.model_dump(mode="json"),
                input_path=input_path,
                sheet=request.sheet,
                options=request.options,
            )
            return LiveSourceUpdateResponse.model_validate(payload)
        except Exception as exc:
            raise http_bad_request("live-source-update-now", exc) from exc

    return router


__all__ = ["create_labplot_runtime_router"]
