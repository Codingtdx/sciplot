from __future__ import annotations

from base64 import b64encode
from io import BytesIO
from typing import Any

from pydantic import Field

from app.sidecar.schemas_common import (
    PreviewItemResponse,
    StrictModel,
    SubmissionReportResponse,
    serialize_dataclass,
)
from src import plot_style


class RenderOptionsPayload(StrictModel):
    size: str | None = None
    xscale: str | None = None
    yscale: str | None = None
    reverse_x: bool = False
    x_min: float | None = None
    x_max: float | None = None
    y_min: float | None = None
    y_max: float | None = None
    x_tick_density: str | None = None
    y_tick_density: str | None = None
    x_tick_edge_labels: str | None = None
    y_tick_edge_labels: str | None = None
    series_order: list[str] | None = None
    x_label_override: str | None = None
    y_label_override: str | None = None
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


class SourceTablePreviewRequest(FileRequest):
    offset: int = 0
    limit: int = 50


class SourceTablePreviewResponse(StrictModel):
    input_path: str
    sheet: str | int
    offset: int
    limit: int
    total_rows: int
    total_cols: int
    column_headers: list[str] = Field(default_factory=list)
    rows: list[list[Any]] = Field(default_factory=list)
    candidate_roles: PlotCandidateRolesResponse = Field(default_factory=lambda: PlotCandidateRolesResponse())
    detected_x_label: str | None = None
    detected_y_label: str | None = None


class FitAnalysisRequest(FileRequest):
    model_id: str = "linear"
    offset: int = 0
    limit: int = 50


class FitDerivedRowResponse(StrictModel):
    row_index: int
    x: float
    y: float
    y_fit: float
    residual: float


class FitAnalysisResponse(StrictModel):
    input_path: str
    sheet: str | int
    model_id: str
    x_label: str | None = None
    y_label: str | None = None
    equation_display: str
    slope: float
    intercept: float
    r_squared: float
    rmse: float
    point_count: int
    warnings: list[str] = Field(default_factory=list)
    total_rows: int
    offset: int
    limit: int
    rows: list[FitDerivedRowResponse] = Field(default_factory=list)


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


class PlotProjectSourceProvenancePayload(StrictModel):
    original_input_path: str | None = None
    saved_input_mtime_ns: int | None = None
    saved_at: str | None = None


class PlotProjectPayload(StrictModel):
    session_kind: str = "plot"
    source_filename: str
    source_media_type: str | None = None
    embedded_source_relpath: str
    source_sha256: str
    sheet: str | int
    selected_template_id: str
    render_options: RenderOptionsPayload
    project_display_name: str | None = None
    source_provenance: PlotProjectSourceProvenancePayload = Field(
        default_factory=PlotProjectSourceProvenancePayload
    )


class ProjectBundlePayload(StrictModel):
    version: int = 1
    selected_workbench: str = "plot"
    plot: PlotProjectPayload | None = None
    data_studio: dict[str, Any] | None = None
    composer: dict[str, Any] | None = None
    code_console: dict[str, Any] | None = None
    artifacts: dict[str, Any] = Field(default_factory=dict)


class SaveProjectRequest(StrictModel):
    project_path: str
    source_path: str
    payload: ProjectBundlePayload


class SaveProjectResponse(StrictModel):
    project_path: str
    payload: ProjectBundlePayload


class OpenProjectRequest(StrictModel):
    project_path: str


class OpenProjectResponse(StrictModel):
    project_path: str
    restored_source_path: str
    payload: ProjectBundlePayload


def rendered_plots_to_preview_payload(
    rendered_plots: list[Any],
) -> list[PreviewItemResponse]:
    previews: list[PreviewItemResponse] = []
    for rendered in rendered_plots:
        buffer = BytesIO()
        rendered.figure.savefig(
            buffer,
            format="pdf",
            facecolor="white",
            bbox_inches=None,
        )
        previews.append(
            PreviewItemResponse(
                filename=rendered.filename,
                pdf_base64=b64encode(buffer.getvalue()).decode("ascii"),
                qa=(
                    serialize_dataclass(rendered.qa_report)
                    if getattr(rendered, "qa_report", None) is not None
                    else None
                ),
            )
        )
    return previews


SourceTablePreviewResponse.model_rebuild()


__all__ = [
    "ExportRenderRequest",
    "ExportRenderResponse",
    "FileRequest",
    "FitAnalysisRequest",
    "FitAnalysisResponse",
    "FitDerivedRowResponse",
    "InputInspectionResponse",
    "InspectFileResponse",
    "OpenProjectRequest",
    "OpenProjectResponse",
    "PlotCandidateRolesResponse",
    "PlotColumnProfileResponse",
    "PlotDatasetPreviewResponse",
    "PlotProjectPayload",
    "PlotProjectSourceProvenancePayload",
    "PreflightRenderResponse",
    "PreflightResultResponse",
    "ProjectBundlePayload",
    "RenderOptionsPayload",
    "RenderPreviewResponse",
    "RenderRequest",
    "SaveProjectRequest",
    "SaveProjectResponse",
    "SourceTablePreviewRequest",
    "SourceTablePreviewResponse",
    "TemplateRecommendationResponse",
    "rendered_plots_to_preview_payload",
]
