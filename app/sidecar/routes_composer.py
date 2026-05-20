from __future__ import annotations

from base64 import b64encode
from pathlib import Path
from tempfile import NamedTemporaryFile

from fastapi import APIRouter

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
from app.sidecar.server_utils import http_bad_request, normalize_path
from src.composer_preflight import build_composer_export_preflight, composer_export_blocker_message
from src.core.application.composer import (
    analyze_composer_project,
    build_composer_submission_report,
    compose_export_pdf,
    compose_preview_png,
    import_panels_from_paths,
    panel_thumbnail_png,
    three_up_panels_from_paths,
    two_up_editorial_panels_from_paths,
    validate_non_overlapping_panels,
)


def create_composer_router() -> APIRouter:
    router = APIRouter()

    @router.post("/panel-thumbnail", response_model=PanelThumbnailResponse)
    def panel_thumbnail(request: ThumbnailRequest) -> PanelThumbnailResponse:
        try:
            input_path = normalize_path(request.file_path)
            png_bytes = panel_thumbnail_png(
                input_path,
                request.page_index,
                max_side_px=request.max_side_px,
            )
            return PanelThumbnailResponse(png_base64=b64encode(png_bytes).decode("ascii"))
        except Exception as exc:
            raise http_bad_request("composer-panel-thumbnail", exc) from exc

    @router.post("/compose-preview", response_model=ComposerPreviewResponse)
    def compose_preview(request: ComposerRequest) -> ComposerPreviewResponse:
        try:
            project = composer_project_from_request(request)
            ok, reason = validate_non_overlapping_panels(project)
            preflight = build_composer_export_preflight(project)
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
                export_preflight=preflight,
            )
        except Exception as exc:
            raise http_bad_request("composer-preview", exc) from exc

    @router.post("/compose-export", response_model=PathResponse)
    def compose_export(request: ComposerRequest) -> PathResponse:
        try:
            project = composer_project_from_request(request)
            ok, reason = validate_non_overlapping_panels(project)
            if not ok:
                raise ValueError(reason)
            preflight = build_composer_export_preflight(project)
            if preflight["status"] == "blocked":
                raise ValueError(composer_export_blocker_message(preflight))
            with NamedTemporaryFile(delete=False, suffix=".pdf") as handle:
                output_path = Path(handle.name)
            exported = compose_export_pdf(project, output_path)
            return PathResponse(output_path=str(exported))
        except Exception as exc:
            raise http_bad_request("composer-export", exc) from exc

    @router.post("/composer/three-up", response_model=ComposerProjectResponse)
    def composer_three_up(request: list[str]) -> ComposerProjectResponse:
        try:
            project = three_up_panels_from_paths(request)
            return ComposerProjectResponse.model_validate(serialize_dataclass(project))
        except Exception as exc:
            raise http_bad_request("composer-three-up", exc) from exc

    @router.post("/composer/two-up-editorial", response_model=ComposerProjectResponse)
    def composer_two_up_editorial(request: list[str]) -> ComposerProjectResponse:
        try:
            project = two_up_editorial_panels_from_paths(request)
            return ComposerProjectResponse.model_validate(serialize_dataclass(project))
        except Exception as exc:
            raise http_bad_request("composer-two-up-editorial", exc) from exc

    @router.post("/composer/import-panels", response_model=ComposerProjectResponse)
    def composer_import_panels(request: ComposerImportRequest) -> ComposerProjectResponse:
        try:
            project = composer_project_from_request(request.project)
            file_paths = [str(Path(path).expanduser()) for path in request.file_paths]
            next_project = import_panels_from_paths(
                project,
                file_paths,
                kind=request.kind,
                asset_refs=[item.model_dump(mode="json") for item in request.asset_refs],
            )
            return ComposerProjectResponse.model_validate(serialize_dataclass(next_project))
        except Exception as exc:
            raise http_bad_request("composer-import-panels", exc) from exc

    return router
