from __future__ import annotations

from base64 import b64encode
from io import BytesIO
from typing import Any, Literal

from pydantic import AliasChoices, Field, model_validator

from app.sidecar.schemas_common import (
    PreviewItemResponse,
    StrictModel,
    SubmissionReportResponse,
    serialize_dataclass,
)
from app.sidecar.schemas_composer import ComposerRequest
from src import plot_style


class TextAnnotationPayload(StrictModel):
    id: str
    enabled: bool = True
    text: str = ""
    coordinate_space: str = "axes_fraction"
    x: float = 0.5
    y: float = 0.95
    y_axis_target: str = "y_primary"
    horizontal_alignment: str = "center"
    vertical_alignment: str = "top"
    display_style: str = "plain"
    connector_enabled: bool = False
    target_x: float = 0.5
    target_y: float = 0.5
    target_y_axis_target: str = "y_primary"


class ShapeAnnotationPayload(StrictModel):
    id: str
    enabled: bool = True
    kind: str = "rectangle"
    bracket_orientation: str = "horizontal"
    x_start: float = 0.0
    x_end: float = 1.0
    y_start: float = 0.0
    y_end: float = 1.0
    y_axis_target: str = "y_primary"
    label: str | None = None


class AnalyticalLayerPayload(StrictModel):
    id: str
    enabled: bool = True
    kind: str = "function"
    expression: str
    x_start: float = 0.0
    x_end: float = 1.0
    sample_count: int = 200
    y_axis_target: str = "y_primary"
    label: str | None = None


class DataTransformPayload(StrictModel):
    id: str
    enabled: bool = True
    kind: str
    label: str | None = None
    target_column: str | None = None
    expression: str | None = None
    column: str | None = None
    operator: str = "eq"
    value: float | str | None = None
    lower: float | None = None
    upper: float | None = None
    x_column: str | None = None
    y_column: str | None = None
    z_column: str | None = None
    output_mode: str = "xyz_long"
    columns: list[str] | None = None
    target_type: str | None = None
    ascending: bool = True
    bins: int | None = None
    window: int | None = None
    method: str | None = None
    group_by: list[str] | None = None
    value_columns: list[str] | None = None
    statistics: list[str] | None = None


class DataVariablePayload(StrictModel):
    id: str
    enabled: bool = True
    kind: str = "scalar"
    label: str | None = None
    value: float | None = None
    expression: str | None = None


class ReferenceGuidePayload(StrictModel):
    id: str
    enabled: bool = True
    kind: str = "line"
    axis_target: str = "y_primary"
    value: float | None = None
    start: float | None = None
    end: float | None = None
    label: str | None = None


class AxisBreakPayload(StrictModel):
    id: str
    enabled: bool = True
    start: float = 0.0
    end: float = 1.0
    display_mode: str = "compress"


class ExtraAxisPayload(StrictModel):
    enabled: bool = False
    position: str = "top"
    binding_mode: str = "conversion"
    series_ids: list[str] = Field(default_factory=list)
    title: str | None = None
    display_unit: str | None = None
    data_value: float = 1.0
    display_value: float = 1.0


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
    custom_theme_id: str | None = None
    custom_theme_draft: dict[str, Any] | None = None
    extra_x_axis: ExtraAxisPayload | None = None
    extra_y_axis: ExtraAxisPayload | None = None
    x_axis_breaks: list[AxisBreakPayload] | None = None
    y_axis_breaks: list[AxisBreakPayload] | None = None
    reference_guides: list[ReferenceGuidePayload] | None = None
    text_annotations: list[TextAnnotationPayload] | None = None
    shape_annotations: list[ShapeAnnotationPayload] | None = None
    analytical_layers: list[AnalyticalLayerPayload] | None = None
    data_variables: list[DataVariablePayload] | None = None
    data_transforms: list[DataTransformPayload] | None = None

    @model_validator(mode="before")
    @classmethod
    def migrate_legacy_reference_guides(cls, value: object) -> object:
        if not isinstance(value, dict):
            return value
        data = dict(value)
        if data.get("reference_guides") is None:
            guides: list[dict[str, Any]] = []
            line = data.pop("reference_line", None)
            if isinstance(line, dict):
                axis = str(line.get("axis", "y")).strip().lower()
                guides.append(
                    {
                        "id": "reference-line-1",
                        "enabled": line.get("enabled", False),
                        "kind": "line",
                        "axis_target": "x" if axis == "x" else "y_primary",
                        "value": line.get("value"),
                        "label": line.get("label"),
                    }
                )
            band = data.pop("reference_band", None)
            if isinstance(band, dict):
                axis = str(band.get("axis", "y")).strip().lower()
                guides.append(
                    {
                        "id": "reference-band-1",
                        "enabled": band.get("enabled", False),
                        "kind": "band",
                        "axis_target": "x" if axis == "x" else "y_primary",
                        "start": band.get("start"),
                        "end": band.get("end"),
                        "label": band.get("label"),
                    }
                )
            if guides:
                data["reference_guides"] = guides
            return data
        data.pop("reference_line", None)
        data.pop("reference_band", None)
        return data


class ReferenceLinePayload(StrictModel):
    enabled: bool = False
    axis: str = "y"
    value: float = 0.0
    label: str | None = None


class ReferenceBandPayload(StrictModel):
    enabled: bool = False
    axis: str = "y"
    start: float = 0.0
    end: float = 1.0
    label: str | None = None


class FitOptionsPayload(StrictModel):
    enabled: bool = False
    model_id: str = "linear"
    custom_function: dict[str, Any] | None = None


class FileRequest(StrictModel):
    input_path: str
    sheet: str | int = 0
    options: RenderOptionsPayload | None = None


class PreviewRenderConfigPayload(StrictModel):
    pixel_width: int = Field(ge=1, le=4096)
    pixel_height: int = Field(ge=1, le=4096)
    scale: float = Field(ge=1.0, le=4.0)


class RenderRequest(FileRequest):
    template: str
    options: RenderOptionsPayload = Field(default_factory=RenderOptionsPayload)
    fit_options: FitOptionsPayload = Field(default_factory=FitOptionsPayload)
    preview_config: PreviewRenderConfigPayload | None = None


class ExportRenderRequest(RenderRequest):
    output_dir: str | None = None


class SourceTablePreviewRequest(FileRequest):
    offset: int = 0
    limit: int = 50
    encoding: str | None = None
    delimiter: str | None = None
    segment_id: str | None = None
    header_row_index: int | None = Field(default=None, validation_alias=AliasChoices("header_row_index", "header_row"))
    unit_row_index: int | None = Field(default=None, validation_alias=AliasChoices("unit_row_index", "unit_row"))
    data_start_row_index: int | None = Field(
        default=None,
        validation_alias=AliasChoices("data_start_row_index", "data_start_row"),
    )
    options: RenderOptionsPayload | None = None


class SourceTableSegmentResponse(StrictModel):
    id: str
    sheet_name: str
    label: str
    result_label: str | None = None
    interval_index: int | None = None
    start_row: int
    end_row: int
    header_row_index: int | None = None
    unit_row_index: int | None = None
    data_start_row_index: int | None = None
    column_count: int
    row_count: int


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
    column_profiles: list[PlotColumnProfileResponse] = Field(default_factory=list)
    segments: list[SourceTableSegmentResponse] = Field(default_factory=list)
    selected_segment_id: str | None = None
    encoding: str | None = None
    delimiter: str | None = None


class FitAnalysisRequest(FileRequest):
    model_id: str = "linear"
    series_id: str | None = None
    offset: int = 0
    limit: int = 50
    custom_function: dict[str, Any] | None = None


class FitDerivedRowResponse(StrictModel):
    row_index: int
    x: float
    y: float
    y_fit: float
    residual: float


class FitSeriesSummaryResponse(StrictModel):
    series_id: str
    series_label: str
    equation_display: str
    r_squared: float
    rmse: float
    point_count: int
    slope: float | None = None
    intercept: float | None = None
    warnings: list[str] = Field(default_factory=list)


class FitAnalysisResponse(StrictModel):
    input_path: str
    sheet: str | int
    model_id: str
    x_label: str | None = None
    y_label: str | None = None
    selected_series_id: str | None = None
    equation_display: str
    slope: float | None = None
    intercept: float | None = None
    r_squared: float
    rmse: float
    point_count: int
    series_summaries: list[FitSeriesSummaryResponse] = Field(default_factory=list)
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
    preview: PreviewItemResponse | None = None
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
    fit_options: FitOptionsPayload = Field(default_factory=FitOptionsPayload)
    project_display_name: str | None = None
    source_provenance: PlotProjectSourceProvenancePayload = Field(
        default_factory=PlotProjectSourceProvenancePayload
    )


class DataStudioProjectWorkbookPayload(StrictModel):
    workbook_filename: str
    embedded_workbook_relpath: str
    workbook_sha256: str
    original_workbook_path: str | None = None
    saved_workbook_mtime_ns: int | None = None


class DataStudioProjectPayload(StrictModel):
    session_kind: str = "data_studio"
    version: int = 1
    selected_template_id: str | None = None
    workbook_paths: list[str] = Field(default_factory=list)
    selected_workbook_id: str | None = None
    primary_workbook_id: str | None = None
    selected_recipe_id: str | None = None
    comparison_recipe_ids: list[str] = Field(default_factory=list)
    selected_figure_family_id: str | None = None
    selected_figure_template_id: str | None = None
    group_states: list[dict[str, Any]] = Field(default_factory=list)
    specimen_states: list[dict[str, Any]] = Field(default_factory=list)
    figure_preferences: list[dict[str, Any]] = Field(default_factory=list)
    imported_paths: list[str] = Field(default_factory=list)
    template_draft_path: str | None = None
    embedded_workbooks: list[DataStudioProjectWorkbookPayload] = Field(default_factory=list)
    project_display_name: str | None = None
    source_provenance: dict[str, Any] = Field(default_factory=dict)


class ComposerProjectPanelPayload(StrictModel):
    panel_id: str
    panel_filename: str
    embedded_panel_relpath: str
    panel_sha256: str
    original_panel_path: str | None = None
    saved_panel_mtime_ns: int | None = None


class ComposerProjectPayload(StrictModel):
    session_kind: str = "composer"
    version: int = 2
    project: ComposerRequest = Field(default_factory=ComposerRequest)
    embedded_panels: list[ComposerProjectPanelPayload] = Field(default_factory=list)
    project_display_name: str | None = None


class CodeConsoleProjectManualBindingPayload(StrictModel):
    source_filename: str
    embedded_source_relpath: str
    source_sha256: str
    original_source_path: str | None = None
    saved_source_mtime_ns: int | None = None
    sheet: str | int = 0
    template_id: str | None = None
    render_options: RenderOptionsPayload = Field(default_factory=RenderOptionsPayload)
    title: str = "Imported file"


class CodeConsoleProjectGeneratedFilePayload(StrictModel):
    original_path: str | None = None
    embedded_file_relpath: str
    file_sha256: str
    name: str
    file_type: str
    size_bytes: int


class CodeConsoleGeneratedFileSnapshotPayload(StrictModel):
    path: str
    name: str
    file_type: str
    size_bytes: int


class CodeConsoleRunSnapshotPayload(StrictModel):
    status: Literal["succeeded", "failed", "timed_out"]
    exit_code: int | None = None
    duration_seconds: float
    stdout: str = ""
    stderr: str = ""
    run_dir: str = ""
    output_dir: str = ""
    script_path: str = ""
    prompt_path: str = ""
    context_path: str = ""
    stdout_path: str = ""
    stderr_path: str = ""
    generated_files: list[CodeConsoleGeneratedFileSnapshotPayload] = Field(default_factory=list)


class CodeConsoleProjectPayload(StrictModel):
    session_kind: str = "code_console"
    version: int = 2
    selected_source_kind: str | None = None
    selected_sheet: str | int = 0
    editor_text: str = ""
    prompt_text: str = ""
    starter_code: str = ""
    manual_binding: CodeConsoleProjectManualBindingPayload | None = None
    latest_run: CodeConsoleRunSnapshotPayload | None = None
    embedded_generated_files: list[CodeConsoleProjectGeneratedFilePayload] = Field(default_factory=list)
    selected_generated_file_path: str | None = None
    project_display_name: str | None = None


class ProjectBundlePayload(StrictModel):
    version: int = 2
    selected_workbench: str = "plot"
    plot: PlotProjectPayload | None = None
    data_studio: DataStudioProjectPayload | None = None
    composer: ComposerProjectPayload | None = None
    code_console: CodeConsoleProjectPayload | None = None
    artifacts: dict[str, Any] = Field(default_factory=dict)


class SaveProjectRequest(StrictModel):
    project_path: str
    source_path: str | None = None
    payload: ProjectBundlePayload


class SaveProjectResponse(StrictModel):
    project_path: str
    payload: ProjectBundlePayload


class OpenProjectRequest(StrictModel):
    project_path: str


class OpenProjectResponse(StrictModel):
    project_path: str
    restored_source_path: str | None = None
    restored_workbook_paths: list[str] = Field(default_factory=list)
    payload: ProjectBundlePayload


def _preview_png_dpi(rendered: Any, preview_config: PreviewRenderConfigPayload | None) -> int:
    if preview_config is None:
        return 160

    width_inches, height_inches = rendered.figure.get_size_inches()
    width_inches = max(float(width_inches), 0.1)
    height_inches = max(float(height_inches), 0.1)
    target_dpi = max(
        preview_config.pixel_width / width_inches,
        preview_config.pixel_height / height_inches,
    )
    return int(max(180, min(620, round(target_dpi))))


def _preview_axis_role(rendered: Any, axis: Any) -> str:
    try:
        from src.rendering.advanced_plot_axes import primary_axis, secondary_y_axis
        from src.rendering.axis_breaks import axis_break_panel_axes
    except Exception:
        return "axis"

    primary = primary_axis(rendered)
    if axis is primary:
        return "primary"
    if axis is secondary_y_axis(rendered):
        return "secondary_y"
    if axis in axis_break_panel_axes(rendered, axis_name="x"):
        return "broken_x_panel"
    if axis in axis_break_panel_axes(rendered, axis_name="y"):
        return "broken_y_panel"
    return "axis"


def _preview_axis_metadata(
    rendered: Any,
    axis: Any,
    *,
    renderer: Any,
    scale: float,
    figure_height: float,
) -> dict[str, Any]:
    bbox = axis.get_window_extent(renderer=renderer)
    x0, x1 = axis.get_xlim()
    y0, y1 = axis.get_ylim()
    return {
        "id": axis.get_gid() or f"axis-{rendered.figure.axes.index(axis)}",
        "role": _preview_axis_role(rendered, axis),
        "bbox_pixels": {
            "x": float(bbox.x0 * scale),
            "y": float((figure_height - bbox.y1) * scale),
            "width": float(bbox.width * scale),
            "height": float(bbox.height * scale),
        },
        "x_range": [float(min(x0, x1)), float(max(x0, x1))],
        "y_range": [float(min(y0, y1)), float(max(y0, y1))],
        "x_scale": str(axis.get_xscale()),
        "y_scale": str(axis.get_yscale()),
        "x_reversed": bool(x1 < x0),
        "y_reversed": bool(y1 < y0),
    }


def _preview_interaction_metadata(rendered: Any, *, png_dpi: int) -> dict[str, Any] | None:
    figure = getattr(rendered, "figure", None)
    if figure is None or not getattr(figure, "axes", None):
        return None

    try:
        figure.canvas.draw()
        renderer = figure.canvas.get_renderer()
        source_dpi = max(float(figure.dpi), 1.0)
        scale = float(png_dpi) / source_dpi
        width_inches, height_inches = figure.get_size_inches()
        figure_width = float(width_inches) * float(png_dpi)
        figure_height = float(height_inches) * float(png_dpi)
        return {
            "figure": {
                "pixel_width": int(round(figure_width)),
                "pixel_height": int(round(figure_height)),
            },
            "axes": [
                _preview_axis_metadata(
                    rendered,
                    axis,
                    renderer=renderer,
                    scale=scale,
                    figure_height=float(figure.bbox.height),
                )
                for axis in figure.axes
            ],
        }
    except Exception:
        return None


def rendered_plots_to_preview_payload(
    rendered_plots: list[Any],
    preview_config: PreviewRenderConfigPayload | None = None,
) -> list[PreviewItemResponse]:
    previews: list[PreviewItemResponse] = []
    for rendered in rendered_plots:
        png_dpi = _preview_png_dpi(rendered, preview_config)
        interaction_metadata = _preview_interaction_metadata(rendered, png_dpi=png_dpi)
        pdf_buffer = BytesIO()
        rendered.figure.savefig(
            pdf_buffer,
            format="pdf",
            facecolor="white",
            bbox_inches=None,
        )
        png_buffer = BytesIO()
        rendered.figure.savefig(
            png_buffer,
            format="png",
            dpi=png_dpi,
            facecolor="white",
            bbox_inches=None,
        )
        previews.append(
            PreviewItemResponse(
                filename=rendered.filename,
                pdf_base64=b64encode(pdf_buffer.getvalue()).decode("ascii"),
                png_base64=b64encode(png_buffer.getvalue()).decode("ascii"),
                qa=(
                    serialize_dataclass(rendered.qa_report)
                    if getattr(rendered, "qa_report", None) is not None
                    else None
                ),
                interaction_metadata=interaction_metadata,
            )
        )
    return previews


RenderOptionsPayload.model_rebuild()
SourceTablePreviewResponse.model_rebuild()


__all__ = [
    "CodeConsoleGeneratedFileSnapshotPayload",
    "CodeConsoleProjectGeneratedFilePayload",
    "CodeConsoleProjectManualBindingPayload",
    "CodeConsoleProjectPayload",
    "CodeConsoleRunSnapshotPayload",
    "ComposerProjectPanelPayload",
    "ComposerProjectPayload",
    "DataStudioProjectPayload",
    "DataStudioProjectWorkbookPayload",
    "DataTransformPayload",
    "ExportRenderRequest",
    "ExportRenderResponse",
    "FileRequest",
    "FitAnalysisRequest",
    "FitAnalysisResponse",
    "FitDerivedRowResponse",
    "FitOptionsPayload",
    "FitSeriesSummaryResponse",
    "DataVariablePayload",
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
    "PreviewRenderConfigPayload",
    "ProjectBundlePayload",
    "AnalyticalLayerPayload",
    "ReferenceGuidePayload",
    "ReferenceBandPayload",
    "ReferenceLinePayload",
    "RenderOptionsPayload",
    "RenderPreviewResponse",
    "RenderRequest",
    "SaveProjectRequest",
    "SaveProjectResponse",
    "SourceTablePreviewRequest",
    "SourceTablePreviewResponse",
    "SourceTableSegmentResponse",
    "TemplateRecommendationResponse",
    "TextAnnotationPayload",
    "rendered_plots_to_preview_payload",
]
