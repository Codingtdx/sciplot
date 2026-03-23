from __future__ import annotations

from base64 import b64encode
from pathlib import Path
from tempfile import NamedTemporaryFile

from fastapi import APIRouter, HTTPException

from app.sidecar.schemas import (
    ComposerImportRequest,
    ComposerPreviewResponse,
    ComposerProjectResponse,
    ComposerRequest,
    PanelThumbnailResponse,
    PathResponse,
    ThumbnailRequest,
    composer_project_from_request,
    serialize_dataclass,
)
from src.composer import (
    compose_export_pdf,
    compose_preview_png,
    import_panels_from_paths,
    panel_thumbnail_png,
    three_up_panels_from_paths,
    two_up_editorial_panels_from_paths,
    validate_non_overlapping_panels,
)
from src.composer_qa import analyze_composer_project
from src.submission import build_composer_submission_report


def create_composer_router() -> APIRouter:
    router = APIRouter()

    @router.post("/panel-thumbnail", response_model=PanelThumbnailResponse)
    def panel_thumbnail(request: ThumbnailRequest) -> PanelThumbnailResponse:
        from app.sidecar.server_utils import normalize_path

        try:
            input_path = normalize_path(request.file_path)
            png_bytes = panel_thumbnail_png(
                input_path,
                request.page_index,
                max_side_px=request.max_side_px,
            )
            return PanelThumbnailResponse(png_base64=b64encode(png_bytes).decode("ascii"))
        except Exception as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @router.post("/compose-preview", response_model=ComposerPreviewResponse)
    def compose_preview(request: ComposerRequest) -> ComposerPreviewResponse:
        try:
            project = composer_project_from_request(request)
            ok, reason = validate_non_overlapping_panels(project)
            png_bytes = compose_preview_png(project)
            qa_report, suggested_patch = analyze_composer_project(project)
            submission_report = build_composer_submission_report(
                project=project,
                qa_report=qa_report,
                valid=ok,
                validation_error=reason,
            )
            return ComposerPreviewResponse(
                valid=ok,
                validation_error=reason,
                png_base64=b64encode(png_bytes).decode("ascii"),
                qa=serialize_dataclass(qa_report),
                submission_report=serialize_dataclass(submission_report),
                suggested_project_patch=serialize_dataclass(suggested_patch),
            )
        except Exception as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @router.post("/compose-export", response_model=PathResponse)
    def compose_export(request: ComposerRequest) -> PathResponse:
        try:
            project = composer_project_from_request(request)
            ok, reason = validate_non_overlapping_panels(project)
            if not ok:
                raise ValueError(reason)
            with NamedTemporaryFile(delete=False, suffix=".pdf") as handle:
                output_path = Path(handle.name)
            exported = compose_export_pdf(project, output_path)
            return PathResponse(output_path=str(exported))
        except Exception as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @router.post("/composer/three-up", response_model=ComposerProjectResponse)
    def composer_three_up(request: list[str]) -> ComposerProjectResponse:
        try:
            project = three_up_panels_from_paths(request)
            return ComposerProjectResponse.model_validate(serialize_dataclass(project))
        except Exception as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @router.post("/composer/two-up-editorial", response_model=ComposerProjectResponse)
    def composer_two_up_editorial(request: list[str]) -> ComposerProjectResponse:
        try:
            project = two_up_editorial_panels_from_paths(request)
            return ComposerProjectResponse.model_validate(serialize_dataclass(project))
        except Exception as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @router.post("/composer/import-panels", response_model=ComposerProjectResponse)
    def composer_import_panels(request: ComposerImportRequest) -> ComposerProjectResponse:
        try:
            project = composer_project_from_request(request.project)
            file_paths = [str(Path(path).expanduser()) for path in request.file_paths]
            next_project = import_panels_from_paths(project, file_paths, kind=request.kind)
            return ComposerProjectResponse.model_validate(serialize_dataclass(next_project))
        except Exception as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    return router
