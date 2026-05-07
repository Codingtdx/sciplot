from __future__ import annotations

from fastapi import APIRouter

from app.sidecar.render_support import http_bad_request
from app.sidecar.schemas import StatusResponse
from app.sidecar.schemas_plot_themes import (
    PlotThemeListResponse,
    PlotThemePreviewRequest,
    PlotThemePreviewResponse,
    PlotThemeSaveRequest,
    PlotThemeSaveResponse,
)
from src.rendering.custom_theme_store import delete_custom_theme, list_theme_summaries, save_custom_theme
from src.rendering.custom_themes import custom_theme_to_payload, normalize_custom_theme_package


def create_plot_themes_router() -> APIRouter:
    router = APIRouter()

    @router.get("/plot-themes", response_model=PlotThemeListResponse)
    def list_plot_themes() -> PlotThemeListResponse:
        try:
            return PlotThemeListResponse.model_validate({"themes": list_theme_summaries()})
        except Exception as exc:  # pragma: no cover - normalized by shared error helper
            raise http_bad_request("plot_themes", exc) from exc

    @router.post("/plot-themes/preview", response_model=PlotThemePreviewResponse)
    def preview_plot_theme(request: PlotThemePreviewRequest) -> PlotThemePreviewResponse:
        try:
            normalized = normalize_custom_theme_package(request.theme.model_dump(mode="json"))
            return PlotThemePreviewResponse.model_validate(
                {
                    "theme": custom_theme_to_payload(normalized.package),
                    "blocked_keys": list(normalized.blocked_keys),
                    "warnings": list(normalized.warnings),
                }
            )
        except Exception as exc:
            raise http_bad_request("plot_theme_preview", exc) from exc

    @router.post("/plot-themes", response_model=PlotThemeSaveResponse)
    def create_plot_theme(request: PlotThemeSaveRequest) -> PlotThemeSaveResponse:
        try:
            normalized = normalize_custom_theme_package(request.theme.model_dump(mode="json"))
            theme = save_custom_theme(custom_theme_to_payload(normalized.package), overwrite=False)
            return PlotThemeSaveResponse.model_validate(
                {
                    "theme": custom_theme_to_payload(theme),
                    "blocked_keys": list(normalized.blocked_keys),
                    "warnings": list(normalized.warnings),
                }
            )
        except Exception as exc:
            raise http_bad_request("plot_theme_save", exc) from exc

    @router.put("/plot-themes/{theme_id:path}", response_model=PlotThemeSaveResponse)
    def update_plot_theme(theme_id: str, request: PlotThemeSaveRequest) -> PlotThemeSaveResponse:
        try:
            payload = request.theme.model_dump(mode="json")
            payload["id"] = theme_id
            normalized = normalize_custom_theme_package(payload)
            theme = save_custom_theme(custom_theme_to_payload(normalized.package), overwrite=True)
            return PlotThemeSaveResponse.model_validate(
                {
                    "theme": custom_theme_to_payload(theme),
                    "blocked_keys": list(normalized.blocked_keys),
                    "warnings": list(normalized.warnings),
                }
            )
        except Exception as exc:
            raise http_bad_request("plot_theme_update", exc) from exc

    @router.delete("/plot-themes/{theme_id:path}", response_model=StatusResponse)
    def delete_plot_theme(theme_id: str) -> StatusResponse:
        try:
            delete_custom_theme(theme_id)
            return StatusResponse(status="ok")
        except Exception as exc:
            raise http_bad_request("plot_theme_delete", exc) from exc

    return router


__all__ = ["create_plot_themes_router"]
