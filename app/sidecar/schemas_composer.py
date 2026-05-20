from __future__ import annotations

from typing import Any, Literal

from pydantic import Field

from app.sidecar.schemas_common import PathResponse, QAReportResponse, StrictModel, SubmissionReportResponse
from src.composer import ComposerProject, project_from_dict


class ComposerCropRectPayload(StrictModel):
    x: float = 0.0
    y: float = 0.0
    width: float = 1.0
    height: float = 1.0


class ComposerLayoutGridPayload(StrictModel):
    columns: int = 3
    rows: int = 3
    cell_width_mm: float = 60.0
    cell_height_mm: float = 55.0
    frame_x_mm: float = 0.0
    frame_y_mm: float = 2.5
    frame_width_mm: float = 180.0
    frame_height_mm: float = 165.0


class ComposerRegionPayload(StrictModel):
    id: str
    kind: Literal["graph", "free"]
    col: int
    row: int
    col_span: int
    row_span: int
    label: str | None = None
    locked: bool = False
    slot_kind: Literal["structure"] | None = None


class ComposerAssetRefPayload(StrictModel):
    asset_id: str
    source_module: str
    source_graph_node_id: str | None = None
    artifact_manifest_id: str | None = None
    label: str
    kind: str = "figure"
    mime_type: str | None = None
    sha256: str = ""
    embedded_path: str | None = None
    refresh_policy: Literal["manual", "on_open", "live"] = "manual"
    preflight_status: Literal["ready", "warning", "blocked", "missing", "stale"] = "ready"
    help: str = "Linked Composer artifact managed through the project artifact manifest."


class ComposerPanelPayload(StrictModel):
    id: str
    file_path: str
    page_index: int = 0
    x_mm: float
    y_mm: float
    w_mm: float
    h_mm: float
    locked: bool = False
    hidden: bool = False
    label: str | None = None
    kind: Literal["graph", "asset"] = "graph"
    z_index: int = 0
    group_id: str | None = None
    region_id: str | None = None
    slot_id: str | None = None
    crop_rect: ComposerCropRectPayload = Field(default_factory=ComposerCropRectPayload)
    asset_ref: ComposerAssetRefPayload | None = None


class ComposerTextPayload(StrictModel):
    id: str
    text: str
    x_mm: float
    y_mm: float
    font_size_pt: float = 8.0
    align: Literal["left", "center", "right"] = "left"
    z_index: int = 0
    locked: bool = False
    hidden: bool = False
    group_id: str | None = None
    region_id: str | None = None
    slot_id: str | None = None


class ComposerRequest(StrictModel):
    version: Literal[2] = 2
    mode: Literal["composer"] = "composer"
    canvas_width_mm: float = 180.0
    canvas_height_mm: float = 170.0
    grid_mm: float = 0.5
    layout_grid: ComposerLayoutGridPayload = Field(default_factory=ComposerLayoutGridPayload)
    regions: list[ComposerRegionPayload] = Field(default_factory=list)
    panels: list[ComposerPanelPayload] = Field(default_factory=list)
    texts: list[ComposerTextPayload] = Field(default_factory=list)
    auto_labels: bool = True


class ComposerImportRequest(StrictModel):
    project: ComposerRequest
    file_paths: list[str]
    kind: str = "graph"
    asset_refs: list[ComposerAssetRefPayload] = Field(default_factory=list)


class ComposerPreflightDiagnosticPayload(StrictModel):
    id: str
    severity: Literal["info", "warning", "critical"]
    message: str
    panel_id: str | None = None
    source_module: str | None = None
    help: str = ""


class ComposerExportPreflightPayload(StrictModel):
    status: Literal["ready", "warning", "blocked"]
    diagnostics: list[ComposerPreflightDiagnosticPayload] = Field(default_factory=list)
    blocking_panel_ids: list[str] = Field(default_factory=list)
    help: str = "Composer export preflight completed."


class ThumbnailRequest(StrictModel):
    file_path: str
    page_index: int = 0
    max_side_px: int = 640


class PanelThumbnailResponse(StrictModel):
    png_base64: str


class ComposerPreviewResponse(StrictModel):
    valid: bool
    validation_error: str | None
    png_base64: str
    qa: QAReportResponse | None = None
    submission_report: SubmissionReportResponse | None = None
    suggested_project_patch: list[dict[str, Any]] = Field(default_factory=list)
    export_preflight: ComposerExportPreflightPayload | None = None


class ComposerProjectResponse(ComposerRequest):
    pass


def composer_project_from_request(request: ComposerRequest) -> ComposerProject:
    return project_from_dict(request.model_dump())


__all__ = [
    "ComposerAssetRefPayload",
    "ComposerExportPreflightPayload",
    "ComposerImportRequest",
    "ComposerPreflightDiagnosticPayload",
    "ComposerPreviewResponse",
    "ComposerProjectResponse",
    "ComposerRequest",
    "PanelThumbnailResponse",
    "PathResponse",
    "ThumbnailRequest",
    "composer_project_from_request",
]
