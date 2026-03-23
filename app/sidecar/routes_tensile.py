from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter

from app.sidecar.schemas import (
    TensileComparisonExportRequest,
    TensileComparisonExportResponse,
    TensileReplicateRequest,
    TensileReplicateResponseModel,
    TensileWorkbookRequest,
    TensileWorkbookSummaryResponse,
    serialize_dataclass,
)
from app.sidecar.server_utils import http_bad_request
from src.rendering import export_tensile_comparison_bundle, inspect_tensile_workbook
from src.tensile_replicates import export_tensile_replicate_workbook


def create_tensile_router() -> APIRouter:
    router = APIRouter()

    @router.post(
        "/preprocess-tensile-replicates",
        response_model=TensileReplicateResponseModel,
    )
    def preprocess_tensile_replicates(
        request: TensileReplicateRequest,
    ) -> TensileReplicateResponseModel:
        try:
            result = export_tensile_replicate_workbook(
                request.file_paths,
                request.output_path,
                group_name=request.group_name,
            )
            return TensileReplicateResponseModel.model_validate(serialize_dataclass(result))
        except Exception as exc:
            raise http_bad_request("tensile_preprocess", exc) from exc

    @router.post(
        "/inspect-tensile-workbook",
        response_model=TensileWorkbookSummaryResponse,
    )
    def inspect_tensile_workbook_endpoint(
        request: TensileWorkbookRequest,
    ) -> TensileWorkbookSummaryResponse:
        try:
            summary = inspect_tensile_workbook(request.workbook_path)
            return TensileWorkbookSummaryResponse.model_validate(serialize_dataclass(summary))
        except Exception as exc:
            raise http_bad_request("tensile_workbook", exc) from exc

    @router.post(
        "/export-tensile-comparison",
        response_model=TensileComparisonExportResponse,
    )
    def export_tensile_comparison(
        request: TensileComparisonExportRequest,
    ) -> TensileComparisonExportResponse:
        try:
            exported = export_tensile_comparison_bundle(
                [Path(path).expanduser() for path in request.workbook_paths],
                request.output_dir,
            )
            return TensileComparisonExportResponse.model_validate(serialize_dataclass(exported))
        except Exception as exc:
            raise http_bad_request("tensile_compare", exc) from exc

    return router
