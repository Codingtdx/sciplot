from __future__ import annotations

from base64 import b64encode
from dataclasses import asdict, is_dataclass
from io import BytesIO
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

from src import plot_style
from src.composer import ComposerProject, project_from_dict


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class RenderOptionsPayload(StrictModel):
    size: str | None = None
    xscale: str | None = None
    yscale: str | None = None
    reverse_x: bool = False
    baseline: str | None = None
    show_colorbar: bool | None = None
    style_preset: str = plot_style.DEFAULT_STYLE_PRESET
    palette_preset: str = plot_style.DEFAULT_PALETTE_PRESET
    use_sidecar: bool | None = None
    visual_theme_id: str | None = None


class FileRequest(StrictModel):
    input_path: str
    sheet: str | int = 0


class RenderRequest(FileRequest):
    template: str
    options: RenderOptionsPayload = Field(default_factory=RenderOptionsPayload)


class ExportRenderRequest(RenderRequest):
    output_dir: str | None = None


class TensileReplicateRequest(StrictModel):
    file_paths: list[str]
    output_path: str
    group_name: str | None = None


class TensileWorkbookRequest(StrictModel):
    workbook_path: str


class TensileComparisonExportRequest(StrictModel):
    workbook_paths: list[str]
    output_dir: str


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


class ThumbnailRequest(StrictModel):
    file_path: str
    page_index: int = 0
    max_side_px: int = 640


class RecommendationResponse(StrictModel):
    template: str
    reason: str
    size: str | None = None
    xscale: str | None = None
    yscale: str | None = None
    reverse_x: bool | None = None
    baseline: str | None = None
    show_colorbar: bool | None = None
    style_preset: str | None = None
    palette_preset: str | None = None
    use_sidecar: bool | None = None


class TemplateRecommendationResponse(StrictModel):
    template_id: str
    canonical_id: str = ""
    role: str = "canonical"
    lifecycle_policy: str = "canonical"
    implementation_id: str = ""
    score: float
    rank: int | None = None
    reason: str = ""
    suitability_hint: str = ""
    score_gap_to_top: float = 0.0
    why_hard_match: list[str] = Field(default_factory=list)
    why_soft_prior: list[str] = Field(default_factory=list)
    inferred_mapping: dict[str, str] = Field(default_factory=dict)
    optional_enhancements: list[str] = Field(default_factory=list)
    preview_config_summary: dict[str, Any] = Field(default_factory=dict)


class InputInspectionResponse(StrictModel):
    model: str
    model_label: str
    recommendation: RecommendationResponse
    recommendations: list[TemplateRecommendationResponse] = Field(default_factory=list)
    primary_recommendation: list[TemplateRecommendationResponse] = Field(default_factory=list)
    alternative_recommendations: list[TemplateRecommendationResponse] = Field(default_factory=list)
    advanced_templates: list[TemplateRecommendationResponse] = Field(default_factory=list)
    recommendation_confidence: float = 0.0
    recommendation_summary: str = ""
    warnings: list[str] = Field(default_factory=list)
    signals: list[str] = Field(default_factory=list)


class PlotColumnProfileResponse(StrictModel):
    name: str
    header_preview: list[str | None]
    inferred_type: str
    non_empty_count: int
    missing_count: int
    min_value: float | int | None = None
    max_value: float | int | None = None


class PlotCandidateRolesResponse(StrictModel):
    x: list[str] = Field(default_factory=list)
    y: list[str] = Field(default_factory=list)
    z: list[str] = Field(default_factory=list)
    group: list[str] = Field(default_factory=list)
    sample: list[str] = Field(default_factory=list)
    value: list[str] = Field(default_factory=list)
    metric: list[str] = Field(default_factory=list)
    label: list[str] = Field(default_factory=list)
    series: list[str] = Field(default_factory=list)


class PlotDatasetPreviewResponse(StrictModel):
    dataset_id: str
    source_path: str | None = None
    sheet: str | int | None = None
    model: str
    raw_rows: int
    raw_cols: int
    column_profiles: list[PlotColumnProfileResponse]
    candidate_roles: PlotCandidateRolesResponse
    data_shapes: list[str]
    semantic_signals: list[str]
    quality_flags: list[str]
    sample_rows: list[list[Any]]


class InspectFileResponse(StrictModel):
    input_path: str
    sheet: str | int
    sheet_names: list[str]
    inspection: InputInspectionResponse
    dataset: PlotDatasetPreviewResponse | None = None


class QAIssueResponse(StrictModel):
    id: str
    severity: str
    metric_value: float | str | None = None
    target: float | str | None = None
    message: str


class QAReportResponse(StrictModel):
    score: float
    grade: Literal["excellent", "solid", "needs_cleanup"]
    issues: list[QAIssueResponse] = Field(default_factory=list)
    autofixes_applied: list[str] = Field(default_factory=list)


class SubmissionCheckResponse(StrictModel):
    id: str
    status: str
    message: str
    metric_value: float | str | None = None
    target: float | str | None = None
    source: str | None = None


class SubmissionReportResponse(StrictModel):
    context: str
    readiness: str
    summary: str
    template: str | None = None
    style_preset: str | None = None
    palette_preset: str | None = None
    output_count: int = 0
    output_filenames: list[str] = Field(default_factory=list)
    blockers: list[str] = Field(default_factory=list)
    checks: list[SubmissionCheckResponse] = Field(default_factory=list)


class PreflightResultResponse(StrictModel):
    template: str
    requested_template_id: str
    canonical_id: str
    role: str
    lifecycle_policy: str
    implementation_id: str
    warnings: list[str] = Field(default_factory=list)
    errors: list[str] = Field(default_factory=list)
    output_filenames: list[str] = Field(default_factory=list)
    submission_report: SubmissionReportResponse | None = None


class PreflightRenderResponse(StrictModel):
    input_path: str
    template: str
    requested_template_id: str
    canonical_id: str
    role: str
    lifecycle_policy: str
    implementation_id: str
    sheet: str | int
    options: RenderOptionsPayload
    preflight: PreflightResultResponse


class PreviewItemResponse(StrictModel):
    filename: str
    png_base64: str
    qa: QAReportResponse | None = None


class RenderPreviewResponse(StrictModel):
    template: str
    requested_template_id: str
    canonical_id: str
    role: str
    lifecycle_policy: str
    implementation_id: str
    sheet: str | int
    previews: list[PreviewItemResponse]
    submission_report: SubmissionReportResponse | None = None


class ExportRenderResponse(StrictModel):
    requested_template_id: str
    canonical_id: str
    role: str
    lifecycle_policy: str
    implementation_id: str
    outputs: list[str]
    output_dir: str
    preview_outputs: list[str] = Field(default_factory=list)
    artifact_paths: list[str] = Field(default_factory=list)
    manifest_path: str | None = None
    submission_report: SubmissionReportResponse | None = None


class HealthResponse(StrictModel):
    status: str
    version: str


class PanelThumbnailResponse(StrictModel):
    png_base64: str


class ComposerPreviewResponse(StrictModel):
    valid: bool
    validation_error: str | None
    png_base64: str
    qa: QAReportResponse | None = None
    submission_report: SubmissionReportResponse | None = None
    suggested_project_patch: list[dict[str, Any]] = Field(default_factory=list)


class PathResponse(StrictModel):
    output_path: str


class ComposerProjectResponse(ComposerRequest):
    pass


class TensileMetricSummaryResponse(StrictModel):
    label: str
    unit: str
    mean: float | None
    std: float | None


class TensileReplicateResponseModel(StrictModel):
    output_path: str
    group_name: str
    preferred_sheet: str
    sheet_names: list[str]
    sample_count: int
    representative_filename: str
    metrics: list[TensileMetricSummaryResponse]
    warnings: list[str]


class TensileWorkbookSummaryResponse(StrictModel):
    workbook_path: str
    label: str
    sheet_names: list[str]
    sample_count: int
    representative_filename: str
    metrics: list[TensileMetricSummaryResponse]


class TensileComparisonExportResponse(StrictModel):
    bundle_dir: str
    comparison_workbook_path: str
    labels: list[str]
    outputs: list[str]


def serialize_dataclass(value: Any) -> Any:
    if is_dataclass(value) and not isinstance(value, type):
        return {key: serialize_dataclass(item) for key, item in asdict(value).items()}
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, dict):
        return {key: serialize_dataclass(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [serialize_dataclass(item) for item in value]
    return value


def rendered_plots_to_preview_payload(
    rendered_plots: list[Any],
    *,
    dpi: int = 160,
) -> list[PreviewItemResponse]:
    previews: list[PreviewItemResponse] = []
    for rendered in rendered_plots:
        buffer = BytesIO()
        rendered.figure.savefig(
            buffer,
            format="png",
            dpi=dpi,
            facecolor="white",
            bbox_inches=None,
        )
        previews.append(
            PreviewItemResponse(
                filename=rendered.filename,
                png_base64=b64encode(buffer.getvalue()).decode("ascii"),
                qa=(
                    serialize_dataclass(rendered.qa_report)
                    if getattr(rendered, "qa_report", None) is not None
                    else None
                ),
            )
        )
    return previews


def composer_project_from_request(request: ComposerRequest) -> ComposerProject:
    return project_from_dict(request.model_dump())
