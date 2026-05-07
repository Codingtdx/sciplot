from __future__ import annotations

from typing import Any

from pydantic import Field

from app.sidecar.schemas_common import StrictModel


class PlotThemeSummaryResponse(StrictModel):
    id: str
    label: str
    builtin: bool = False
    base_style_id: str
    palette_preset: str | None = None
    visual_theme_id: str | None = None
    swatches: list[str] = Field(default_factory=list)


class CustomPlotThemePackagePayload(StrictModel):
    id: str
    label: str
    base_style_id: str = "nature"
    palette_preset: str | None = None
    visual_theme_id: str | None = None
    palette: dict[str, Any] = Field(default_factory=dict)
    hard_overrides: dict[str, dict[str, Any]] = Field(default_factory=dict)
    soft_overrides: dict[str, Any] = Field(default_factory=dict)
    expert_rcparams: dict[str, Any] = Field(default_factory=dict)


class PlotThemeListResponse(StrictModel):
    themes: list[PlotThemeSummaryResponse] = Field(default_factory=list)


class PlotThemePreviewRequest(StrictModel):
    theme: CustomPlotThemePackagePayload


class PlotThemePreviewResponse(StrictModel):
    theme: CustomPlotThemePackagePayload
    blocked_keys: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class PlotThemeSaveRequest(StrictModel):
    theme: CustomPlotThemePackagePayload


class PlotThemeSaveResponse(StrictModel):
    theme: CustomPlotThemePackagePayload
    blocked_keys: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


__all__ = [
    "CustomPlotThemePackagePayload",
    "PlotThemeListResponse",
    "PlotThemePreviewRequest",
    "PlotThemePreviewResponse",
    "PlotThemeSaveRequest",
    "PlotThemeSaveResponse",
    "PlotThemeSummaryResponse",
]
