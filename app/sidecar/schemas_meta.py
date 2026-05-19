from __future__ import annotations

from typing import Any

from pydantic import Field

from app.sidecar.schemas_common import StrictModel


class MetaDefaultsResponse(StrictModel):
    style_preset: str
    palette_preset: str


class MetaGlobalFrameResponse(StrictModel):
    panel_width_mm: float
    panel_height_mm: float
    left_margin_mm: float
    right_margin_mm: float
    bottom_margin_mm: float
    top_margin_mm: float


class MetaSizeResponse(StrictModel):
    id: str
    label: str
    width_mm: float
    height_mm: float


class MetaStyleResponse(StrictModel):
    id: str
    label: str
    public: bool
    display_group: str = "publication"
    description: str
    hard_constraints: bool
    preset_note: str
    recommended_palette_preset: str
    recommended_visual_theme_id: str | None = None


class MetaPaletteResponse(StrictModel):
    id: str
    label: str
    public: bool
    description: str
    swatches: list[str] = Field(default_factory=list)


class MetaTemplateSummaryResponse(StrictModel):
    id: str
    label: str
    description: str
    category: str
    presentation_kind: str
    default_size: str
    allowed_sizes: list[str] = Field(default_factory=list)
    editable_options: list[str] = Field(default_factory=list)
    default_options: dict[str, Any] = Field(default_factory=dict)
    available_styles: list[str] = Field(default_factory=list)
    available_palettes: list[str] = Field(default_factory=list)
    canonical_id: str
    role: str
    lifecycle_policy: str
    implementation_id: str


class VisualThemeResponse(StrictModel):
    id: str
    label: str
    description: str


class CapabilityCatalogEntryResponse(StrictModel):
    id: str
    label: str
    status: str
    owner: str
    surface: str
    extensions: list[str] = Field(default_factory=list)
    mime_types: list[str] = Field(default_factory=list)
    dependency: str | None = None
    dependency_status: str = "not_required"
    preview_supported: bool = False
    read_supported: bool = False
    write_supported: bool = False
    typed_payload_schema: dict[str, Any] = Field(default_factory=dict)
    help: str
    introduced_in: str
    test_requirements: list[str] = Field(default_factory=list)


class CapabilityCatalogGroupResponse(StrictModel):
    id: str
    label: str
    description: str
    capabilities: list[CapabilityCatalogEntryResponse] = Field(default_factory=list)


class MetaResponse(StrictModel):
    version: int
    defaults: MetaDefaultsResponse
    global_frame: MetaGlobalFrameResponse
    sizes: list[MetaSizeResponse] = Field(default_factory=list)
    styles: list[MetaStyleResponse] = Field(default_factory=list)
    palettes: list[MetaPaletteResponse] = Field(default_factory=list)
    templates: list[MetaTemplateSummaryResponse] = Field(default_factory=list)
    template_ids: list[str] = Field(default_factory=list)
    size_ids: list[str] = Field(default_factory=list)
    palette_preset_ids: list[str] = Field(default_factory=list)
    visual_themes: list[VisualThemeResponse] = Field(default_factory=list)
    capability_catalogs: list[CapabilityCatalogGroupResponse] = Field(default_factory=list)


class PlotContractResponse(StrictModel):
    version: int
    defaults: MetaDefaultsResponse
    aliases: dict[str, Any] = Field(default_factory=dict)
    global_frame: dict[str, Any] = Field(default_factory=dict)
    axis_policy: dict[str, Any] = Field(default_factory=dict)
    size_presets: dict[str, dict[str, Any]] = Field(default_factory=dict)
    special_layouts: dict[str, dict[str, Any]] = Field(default_factory=dict)
    qa_profiles: dict[str, dict[str, Any]] = Field(default_factory=dict)
    styles: dict[str, dict[str, Any]] = Field(default_factory=dict)
    palettes: dict[str, dict[str, Any]] = Field(default_factory=dict)
    templates: dict[str, dict[str, Any]] = Field(default_factory=dict)
    validation_rules: dict[str, dict[str, Any]] = Field(default_factory=dict)


__all__ = [
    "CapabilityCatalogEntryResponse",
    "CapabilityCatalogGroupResponse",
    "MetaDefaultsResponse",
    "MetaGlobalFrameResponse",
    "MetaPaletteResponse",
    "MetaResponse",
    "MetaSizeResponse",
    "MetaStyleResponse",
    "MetaTemplateSummaryResponse",
    "PlotContractResponse",
    "VisualThemeResponse",
]
