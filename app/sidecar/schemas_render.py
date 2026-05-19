from __future__ import annotations

import math
from base64 import b64encode
from collections.abc import Mapping
from io import BytesIO
from typing import Any, Literal

from pydantic import AliasChoices, ConfigDict, Field, model_validator

from app.sidecar.schemas_common import (
    PreviewItemResponse,
    StrictModel,
    SubmissionReportResponse,
    serialize_dataclass,
)
from app.sidecar.schemas_composer import ComposerRequest
from src import plot_style
from src.rendering.artist_tags import interaction_artist_metadata
from src.rendering.extra_axes import normalize_series_selection_ids


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


class SeriesStylePayload(StrictModel):
    series_id: str
    enabled: bool = True
    color: str | None = None
    line_width: float | None = None
    marker: str | None = None
    y_axis_target: str | None = None


class SeriesOffsetPayload(StrictModel):
    series_id: str
    enabled: bool = True
    x_offset: float = 0.0
    y_offset: float = 0.0
    y_axis_target: str | None = None


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
    series_styles: list[SeriesStylePayload] | None = None
    series_offsets: list[SeriesOffsetPayload] | None = None
    legend_position: str | None = None
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


class DataContainerColumnPayload(StrictModel):
    id: str
    name: str
    index: int
    role_hints: list[str] = Field(default_factory=list)
    mode: str = "unknown"
    unit: str | None = None
    comment: str | None = None
    format: str | None = None
    dictionary: list[str] = Field(default_factory=list)
    category: str | None = None
    missing_policy: str = "preserve"
    lineage: dict[str, Any] = Field(default_factory=dict)
    computed_expression: str | None = None
    readonly: bool = True
    lifecycle_events: list[str] = Field(default_factory=list)
    profile: PlotColumnProfileResponse | None = None


class DataContainerSourcePayload(StrictModel):
    input_path: str
    sheet: str | int
    selected_segment_id: str | None = None
    encoding: str | None = None
    delimiter: str | None = None
    offset: int
    limit: int
    transform_count: int = 0
    variable_count: int = 0


class DataContainerPayload(StrictModel):
    id: str
    kind: Literal["table", "matrix", "transformed_view", "statistics_summary", "fit_result", "notebook_output"]
    label: str
    status: Literal["enabled", "disabled"] = "enabled"
    readonly: bool = True
    row_count: int
    column_count: int
    columns: list[DataContainerColumnPayload] = Field(default_factory=list)
    column_ids: list[str] = Field(default_factory=list)
    source: DataContainerSourcePayload
    dimensions: dict[str, int] | None = None
    coordinate_vectors: dict[str, list[float | int | str | None]] = Field(default_factory=dict)
    missing_value_policy: str | None = None
    statistics: dict[str, Any] = Field(default_factory=dict)
    diagnostics: list[dict[str, Any]] = Field(default_factory=list)
    result_tables: list[dict[str, Any]] = Field(default_factory=list)
    overlays: list[dict[str, Any]] = Field(default_factory=list)
    artifact_paths: list[str] = Field(default_factory=list)
    container_ids: list[str] = Field(default_factory=list)
    source_run_id: str | None = None
    data_revision: int = 1
    help: str


class PlotObjectPayload(StrictModel):
    id: str
    kind: str
    module: str = "plot"
    label: str
    status: Literal["active", "disabled"] = "active"
    visible: bool = True
    locked: bool = False
    graph_node_id: str
    payload: dict[str, Any] = Field(default_factory=dict)
    help: str = "Graph-addressable plot object landing."


class PlotEditCommandPayload(StrictModel):
    command_id: str
    kind: Literal[
        "add",
        "edit",
        "delete",
        "reorder",
        "rename",
        "visibility",
        "lock",
        "copy_settings",
        "bind_source",
        "apply_template",
        "import_container",
        "create_output_ref",
    ]
    module: Literal["plot", "data_studio", "composer", "code_console"] = "plot"
    target_object_id: str
    source_object_id: str | None = None
    before: dict[str, Any] | None = None
    after: dict[str, Any] | None = None
    graph_patch: dict[str, Any] = Field(default_factory=dict)
    graph_revision: int | None = None
    compound_id: str | None = None
    reversible: bool = True
    help: str = "Undoable typed plot edit command landing."


class AnalysisOperationResultPayload(StrictModel):
    operation_id: str
    operation_instance_id: str | None = None
    operation_kind: str | None = None
    available: bool = True
    valid: bool = True
    status_code: str = "ok"
    message: str = ""
    diagnostics: list[dict[str, Any]] = Field(default_factory=list)
    metrics: dict[str, Any] = Field(default_factory=dict)
    tables: list[dict[str, Any]] = Field(default_factory=list)
    overlays: list[dict[str, Any]] = Field(default_factory=list)
    data_containers: list[DataContainerPayload] = Field(default_factory=list)
    settings: dict[str, Any] = Field(default_factory=dict)
    source_binding: dict[str, Any] = Field(default_factory=dict)
    prepared_arrays: dict[str, Any] = Field(default_factory=dict)
    elapsed_ms: float = 0.0
    lineage: dict[str, Any] = Field(default_factory=dict)
    artifact_refs: list[dict[str, Any]] = Field(default_factory=list)
    graph_node_id: str | None = None
    result_node_id: str | None = None
    result_container_ids: list[str] = Field(default_factory=list)
    overlay_refs: list[dict[str, Any]] = Field(default_factory=list)
    recalculate_policy: Literal["manual", "auto", "on_open"] = "manual"


class ImportDiagnosticPayload(StrictModel):
    model_config = ConfigDict(extra="allow")

    status_code: str
    severity: str = "info"
    message: str = ""
    dependency: str | None = None
    help_action: str | None = None

    def __getitem__(self, key: str) -> Any:
        if hasattr(self, key):
            return getattr(self, key)
        extra = self.__pydantic_extra__ or {}
        return extra[key]


class ImportOptionPayload(StrictModel):
    id: str
    label: str
    kind: str = "string"
    default_value: Any | None = None
    choices: list[Any] = Field(default_factory=list)
    required: bool = False
    help: str = ""


class ImportStructureNodePayload(StrictModel):
    id: str
    kind: str
    label: str
    parent_id: str | None = None
    row_count: int | None = None
    column_count: int | None = None
    children: list[ImportStructureNodePayload] = Field(default_factory=list)
    payload: dict[str, Any] = Field(default_factory=dict)


class ImportFilterProfilePayload(StrictModel):
    id: str
    label: str
    status: Literal["enabled", "disabled"] = "disabled"
    extensions: list[str] = Field(default_factory=list)
    mime_types: list[str] = Field(default_factory=list)
    dependency: str | None = None
    dependency_status: str = "not_required"
    preview_supported: bool = False
    read_supported: bool = False
    write_supported: bool = False
    options_schema: dict[str, Any] = Field(default_factory=lambda: {"type": "object"})
    output_container_kinds: list[str] = Field(default_factory=list)
    help: str
    test_requirements: list[str] = Field(default_factory=list)


class ImportFilterPayload(StrictModel):
    id: str
    label: str
    status: Literal["enabled", "disabled"] = "disabled"
    owner: str = "sidecar"
    surface: str = "plot,data_studio"
    extensions: list[str] = Field(default_factory=list)
    mime_types: list[str] = Field(default_factory=list)
    dependency: str | None = None
    dependency_status: str = "not_required"
    preview_supported: bool = False
    read_supported: bool = False
    write_supported: bool = False
    options_schema: dict[str, Any] = Field(default_factory=lambda: {"type": "object"})
    output_container_kinds: list[str] = Field(default_factory=list)
    help: str
    test_requirements: list[str] = Field(default_factory=list)


class ExportTargetPayload(StrictModel):
    id: str
    label: str
    status: Literal["enabled", "disabled"] = "disabled"
    owner: str = "sidecar"
    surface: str = "all"
    allowed_modules: list[str] = Field(default_factory=list)
    artifact_kind: str
    filename_policy: str
    help: str
    test_requirements: list[str] = Field(default_factory=list)


class NotebookOutputPayload(StrictModel):
    id: str
    kind: Literal["table", "figure", "artifact", "text"]
    label: str
    status: Literal["enabled", "disabled"] = "enabled"
    source_run_id: str
    artifact_paths: list[str] = Field(default_factory=list)
    container_ids: list[str] = Field(default_factory=list)
    help: str = "Code Console generated output landing."


class AnalysisOperationRequest(FileRequest):
    operation_id: str
    operation_instance_id: str | None = None
    module: Literal["plot", "data_studio"] = "plot"
    x_column: str | None = None
    y_column: str | None = None
    parameters: dict[str, Any] = Field(default_factory=dict)
    source_binding: dict[str, Any] = Field(default_factory=dict)
    recalculate_policy: Literal["manual", "auto", "on_open"] = "manual"
    graph_revision: int | None = None
    offset: int = 0
    limit: int = 200


class AnalysisOperationResponse(StrictModel):
    operation_id: str
    input_path: str
    sheet: str | int
    operation_result: AnalysisOperationResultPayload


class ImportPreviewRequest(StrictModel):
    input_path: str
    filter_id: str | None = None
    sheet: str | int = 0
    offset: int = 0
    limit: int = 50
    options: dict[str, Any] = Field(default_factory=dict)


class ImportPreviewResponse(StrictModel):
    input_path: str
    filter_id: str
    status: Literal["enabled", "disabled"]
    label: str
    profile: ImportFilterProfilePayload | None = None
    data_containers: list[DataContainerPayload] = Field(default_factory=list)
    diagnostics: list[ImportDiagnosticPayload] = Field(default_factory=list)
    available_options: list[ImportOptionPayload] = Field(default_factory=list)
    structure: list[ImportStructureNodePayload] = Field(default_factory=list)
    selected_sheet_or_segment: str | None = None
    options_schema: dict[str, Any] = Field(default_factory=lambda: {"type": "object"})
    help: str


class PlotEditCommandNormalizeRequest(StrictModel):
    command: PlotEditCommandPayload
    objects: list[PlotObjectPayload] = Field(default_factory=list)


class PlotEditCommandNormalizeResponse(StrictModel):
    command: PlotEditCommandPayload
    diagnostics: list[dict[str, Any]] = Field(default_factory=list)


class CommandNormalizeRequest(StrictModel):
    command: PlotEditCommandPayload
    objects: list[PlotObjectPayload] = Field(default_factory=list)


class CommandNormalizeResponse(StrictModel):
    command: PlotEditCommandPayload
    diagnostics: list[dict[str, Any]] = Field(default_factory=list)


class CommandApplyPreviewRequest(StrictModel):
    command: PlotEditCommandPayload
    document_graph: dict[str, Any] = Field(default_factory=dict)


class CommandApplyPreviewResponse(StrictModel):
    command: PlotEditCommandPayload
    graph_revision: int
    graph_patch: dict[str, Any] = Field(default_factory=dict)
    render_invalidation: dict[str, Any] = Field(default_factory=dict)
    diagnostics: list[dict[str, Any]] = Field(default_factory=list)


class PreviewSceneRequest(RenderRequest):
    pass


class PreviewSceneResponse(StrictModel):
    scene_id: str
    template: str
    sheet: str | int
    native_supported: bool
    fallback_reason: str | None = None
    graph_revision: int = 1
    figure: dict[str, Any] = Field(default_factory=dict)
    plot_area: dict[str, float]
    axes: list[dict[str, Any]] = Field(default_factory=list)
    series: list[dict[str, Any]] = Field(default_factory=list)
    objects: list[dict[str, Any]] = Field(default_factory=list)
    overlays: list[dict[str, Any]] = Field(default_factory=list)
    budgets: dict[str, Any] = Field(default_factory=dict)
    diagnostics: list[dict[str, Any]] = Field(default_factory=list)


class LiveSourcePayload(StrictModel):
    id: str
    kind: Literal["file_tail", "folder_watch", "periodic_csv", "mqtt", "serial", "socket"]
    status: Literal["enabled", "disabled"] = "disabled"
    poll_interval_ms: int = 1000
    sample_window: int = 1000
    append_policy: Literal["append", "replace"] = "append"
    paused: bool = True
    last_update_diagnostic: dict[str, Any] = Field(default_factory=dict)
    help: str


class LiveSourceUpdateRequest(StrictModel):
    live_source: LiveSourcePayload
    input_path: str
    sheet: str | int = 0
    options: dict[str, Any] = Field(default_factory=dict)


class LiveSourceUpdateResponse(StrictModel):
    live_source: LiveSourcePayload
    input_path: str
    sheet: str | int
    data_revision: int
    data_containers: list[DataContainerPayload] = Field(default_factory=list)
    diagnostics: list[dict[str, Any]] = Field(default_factory=list)
    render_invalidation: dict[str, Any] = Field(default_factory=dict)
    help: str


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
    data_containers: list[DataContainerPayload] = Field(default_factory=list)
    diagnostics: list[ImportDiagnosticPayload] = Field(default_factory=list)


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
    operation_result: AnalysisOperationResultPayload | None = None


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


class DataStudioAnalysisOperationPayload(StrictModel):
    operation_instance_id: str
    operation_id: str
    operation_kind: str | None = None
    graph_node_id: str | None = None
    label: str = "Analysis Operation"
    source_binding: dict[str, Any] = Field(default_factory=dict)
    settings: dict[str, Any] = Field(default_factory=dict)
    overlay_refs: list[dict[str, Any]] = Field(default_factory=list)
    recalculate_policy: Literal["manual", "auto", "on_open"] = "manual"


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
    analysis_operations: list[DataStudioAnalysisOperationPayload] = Field(default_factory=list)
    analysis_results: list[AnalysisOperationResultPayload] = Field(default_factory=list)
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


class DocumentGraphNodePayload(StrictModel):
    id: str
    kind: str
    module: str
    label: str
    status: str = "active"
    parent_id: str | None = None
    order: int = 0
    visible: bool = True
    locked: bool = False
    selected: bool = False
    payload: dict[str, Any] = Field(default_factory=dict)


class DocumentGraphEdgePayload(StrictModel):
    source: str
    target: str
    relationship: str


class DocumentGraphPayload(StrictModel):
    schema_version: int = 2
    revision: int = 1
    nodes: list[DocumentGraphNodePayload] = Field(default_factory=list)
    edges: list[DocumentGraphEdgePayload] = Field(default_factory=list)
    selected_nodes: dict[str, str] = Field(default_factory=dict)
    module_roots: dict[str, str] = Field(default_factory=dict)
    capabilities: list[str] = Field(default_factory=list)
    events: list[dict[str, Any]] = Field(default_factory=list)
    migration_notes: list[str] = Field(default_factory=list)


class ProjectBundlePayload(StrictModel):
    version: int = 2
    selected_workbench: str = "plot"
    plot: PlotProjectPayload | None = None
    data_studio: DataStudioProjectPayload | None = None
    composer: ComposerProjectPayload | None = None
    code_console: CodeConsoleProjectPayload | None = None
    document_graph: DocumentGraphPayload | None = None
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


def _preview_pixel_point(
    point: tuple[float, float],
    *,
    scale: float,
    figure_height: float,
) -> list[float]:
    return [float(point[0] * scale), float((figure_height - point[1]) * scale)]


def _preview_bbox_for_points(
    points: list[tuple[float, float]],
    *,
    scale: float,
    figure_height: float,
) -> dict[str, float]:
    if not points:
        return {"x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0}
    x_values = [point[0] for point in points]
    y_values = [point[1] for point in points]
    min_x = min(x_values)
    max_x = max(x_values)
    min_y = min(y_values)
    max_y = max(y_values)
    return {
        "x": float(min_x * scale),
        "y": float((figure_height - max_y) * scale),
        "width": float((max_x - min_x) * scale),
        "height": float((max_y - min_y) * scale),
    }


def _preview_bbox_from_display_bbox(
    bbox: Any,
    *,
    scale: float,
    figure_height: float,
) -> dict[str, float]:
    return {
        "x": float(bbox.x0 * scale),
        "y": float((figure_height - bbox.y1) * scale),
        "width": float(max(bbox.width, 0.0) * scale),
        "height": float(max(bbox.height, 0.0) * scale),
    }


def _inflate_degenerate_bbox(
    bbox: Mapping[str, float],
    *,
    min_size: float = 6.0,
) -> dict[str, float]:
    x = float(bbox.get("x", 0.0))
    y = float(bbox.get("y", 0.0))
    width = float(bbox.get("width", 0.0))
    height = float(bbox.get("height", 0.0))
    if width <= 0.5:
        x -= min_size / 2.0
        width = min_size
    if height <= 0.5:
        y -= min_size / 2.0
        height = min_size
    return {"x": x, "y": y, "width": width, "height": height}


def _bbox_has_area(bbox: Mapping[str, float]) -> bool:
    return (
        math.isfinite(float(bbox.get("x", 0.0)))
        and math.isfinite(float(bbox.get("y", 0.0)))
        and float(bbox.get("width", 0.0)) > 0.5
        and float(bbox.get("height", 0.0)) > 0.5
    )


def _preview_object(
    *,
    object_id: str,
    kind: str,
    axis_id: str | None,
    label: str | None,
    bbox_pixels: Mapping[str, float],
    points: list[list[float]] | None = None,
    payload_type: str | None = None,
    payload_id: str | None = None,
    operations: list[str] | None = None,
) -> dict[str, Any]:
    payload_ref = None
    if payload_type is not None and payload_id is not None:
        payload_ref = {"type": payload_type, "id": payload_id}
    return {
        "id": object_id,
        "kind": kind,
        "label": label,
        "axis_id": axis_id,
        "bbox_pixels": dict(bbox_pixels),
        "points": points or [],
        "payload_ref": payload_ref,
        "operations": operations or ["select", "more"],
    }


def _finite_data_points(raw_points: Any) -> list[tuple[float, float]]:
    resolved: list[tuple[float, float]] = []
    for raw_x, raw_y in raw_points:
        try:
            x_value = float(raw_x)
            y_value = float(raw_y)
        except (TypeError, ValueError):
            continue
        if math.isfinite(x_value) and math.isfinite(y_value):
            resolved.append((x_value, y_value))
    return resolved


def _downsample_points(points: list[tuple[float, float]], *, limit: int = 512) -> list[tuple[float, float]]:
    if len(points) <= limit:
        return points
    stride = max(int(math.ceil(len(points) / limit)), 1)
    sampled = points[::stride]
    if sampled[-1] != points[-1]:
        sampled.append(points[-1])
    return sampled


def _visible_artist_label(artist: Any) -> str | None:
    if not bool(getattr(artist, "get_visible", lambda: True)()):
        return None
    label = str(getattr(artist, "get_label", lambda: "")() or "").strip()
    if not label or label.startswith("_"):
        return None
    return label


def _line_display_points(line: Any) -> list[tuple[float, float]]:
    data_points = _finite_data_points(zip(line.get_xdata(), line.get_ydata(), strict=False))
    if not data_points:
        return []
    return [tuple(point) for point in line.axes.transData.transform(data_points)]


def _collection_display_points(collection: Any) -> list[tuple[float, float]]:
    offsets = getattr(collection, "get_offsets", lambda: [])()
    data_points = _finite_data_points(offsets)
    if not data_points:
        return []
    return [tuple(point) for point in collection.axes.transData.transform(data_points)]


def _preview_series_artist_metadata(
    rendered: Any,
    *,
    scale: float,
    figure_height: float,
) -> list[dict[str, Any]]:
    artists: list[dict[str, Any]] = []
    for axis in getattr(rendered.figure, "axes", []):
        axis_id = axis.get_gid() or f"axis-{rendered.figure.axes.index(axis)}"
        candidates: list[tuple[str, str, Any, list[tuple[float, float]]]] = []
        for line in getattr(axis, "lines", []):
            if interaction_artist_metadata(line) is not None:
                continue
            label = _visible_artist_label(line)
            if label is None:
                continue
            points = _line_display_points(line)
            if len(points) >= 2:
                candidates.append(("series_line", label, line, points))
        for collection in getattr(axis, "collections", []):
            if interaction_artist_metadata(collection) is not None:
                continue
            label = _visible_artist_label(collection)
            if label is None:
                continue
            points = _collection_display_points(collection)
            if points:
                candidates.append(("series_points", label, collection, points))

        series_ids = normalize_series_selection_ids(label for _, label, _, _ in candidates)
        for index, (kind, label, artist, display_points) in enumerate(candidates):
            sampled_points = _downsample_points(display_points)
            series_id = series_ids[index] if index < len(series_ids) else label
            artists.append(
                {
                    "id": getattr(artist, "get_gid", lambda: None)() or f"{kind}:{axis_id}:{series_id}",
                    "kind": kind,
                    "axis_id": axis_id,
                    "series_id": series_id,
                    "label": label,
                    "bbox_pixels": _preview_bbox_for_points(
                        display_points,
                        scale=scale,
                        figure_height=figure_height,
                    ),
                    "points": [
                        _preview_pixel_point(point, scale=scale, figure_height=figure_height)
                        for point in sampled_points
                    ],
                }
            )
    return artists


_INTERACTION_CELL_TARGET_LIMIT = 2500


def _preview_series_objects(artists: list[dict[str, Any]]) -> list[dict[str, Any]]:
    objects: list[dict[str, Any]] = []
    for artist in artists:
        series_id = str(artist.get("series_id") or artist.get("label") or "").strip()
        if not series_id:
            continue
        objects.append(
            _preview_object(
                object_id=str(artist.get("id") or f"{artist.get('kind')}:{series_id}"),
                kind=str(artist.get("kind") or "series"),
                axis_id=str(artist.get("axis_id")) if artist.get("axis_id") is not None else None,
                label=str(artist.get("label") or series_id),
                bbox_pixels=artist.get("bbox_pixels") or {},
                points=list(artist.get("points") or []),
                payload_type="series",
                payload_id=series_id,
                operations=["select", "quick_edit", "drag_offset"],
            )
        )
    return objects


def _preview_text_object(
    *,
    axis_id: str,
    kind: str,
    text_artist: Any,
    renderer: Any,
    scale: float,
    figure_height: float,
    payload_type: str,
    payload_id: str,
) -> dict[str, Any] | None:
    text = str(getattr(text_artist, "get_text", lambda: "")() or "").strip()
    if not text or not bool(getattr(text_artist, "get_visible", lambda: True)()):
        return None
    try:
        bbox = _preview_bbox_from_display_bbox(
            text_artist.get_window_extent(renderer=renderer),
            scale=scale,
            figure_height=figure_height,
        )
    except Exception:
        return None
    if not _bbox_has_area(bbox):
        return None
    return _preview_object(
        object_id=f"{kind}:{axis_id}:{payload_id}",
        kind=kind,
        axis_id=axis_id,
        label=text,
        bbox_pixels=bbox,
        payload_type=payload_type,
        payload_id=payload_id,
        operations=["select", "quick_edit", "more"],
    )


def _preview_axis_objects(
    rendered: Any,
    axes_metadata: list[dict[str, Any]],
    *,
    renderer: Any,
    scale: float,
    figure_height: float,
) -> list[dict[str, Any]]:
    objects: list[dict[str, Any]] = []
    axes = list(getattr(rendered.figure, "axes", []))
    for index, (axis, axis_metadata) in enumerate(zip(axes, axes_metadata, strict=False)):
        axis_id = str(axis_metadata.get("id") or axis.get_gid() or f"axis-{index}")
        role = str(axis_metadata.get("role") or "axis")
        objects.append(
            _preview_object(
                object_id=f"axis:{axis_id}",
                kind="colorbar" if index > 0 and role != "primary" else "axis",
                axis_id=axis_id,
                label=role,
                bbox_pixels=axis_metadata["bbox_pixels"],
                payload_type="axis",
                payload_id=axis_id,
                operations=["select", "more"],
            )
        )
        for kind, axis_artist, payload_id in (
            ("x_axis", axis.xaxis, "x"),
            ("y_axis", axis.yaxis, "y"),
        ):
            try:
                axis_bbox = _preview_bbox_from_display_bbox(
                    axis_artist.get_tightbbox(renderer=renderer),
                    scale=scale,
                    figure_height=figure_height,
                )
            except Exception:
                continue
            if not _bbox_has_area(axis_bbox):
                continue
            objects.append(
                _preview_object(
                    object_id=f"{kind}:{axis_id}",
                    kind=kind,
                    axis_id=axis_id,
                    label=payload_id.upper(),
                    bbox_pixels=axis_bbox,
                    payload_type="axis",
                    payload_id=f"{axis_id}:{payload_id}",
                    operations=["select", "more"],
                )
            )
        for kind, text_artist, payload_id in (
            ("axis_title", axis.title, "title"),
            ("x_label", axis.xaxis.label, "x"),
            ("y_label", axis.yaxis.label, "y"),
        ):
            obj = _preview_text_object(
                axis_id=axis_id,
                kind=kind,
                text_artist=text_artist,
                renderer=renderer,
                scale=scale,
                figure_height=figure_height,
                payload_type="axis_label",
                payload_id=f"{axis_id}:{payload_id}",
            )
            if obj is not None:
                objects.append(obj)

        legend = axis.get_legend()
        if legend is None or not bool(getattr(legend, "get_visible", lambda: True)()):
            continue
        try:
            legend_bbox = _preview_bbox_from_display_bbox(
                legend.get_window_extent(renderer=renderer),
                scale=scale,
                figure_height=figure_height,
            )
        except Exception:
            legend_bbox = None
        if legend_bbox is not None and _bbox_has_area(legend_bbox):
            objects.append(
                _preview_object(
                    object_id=f"legend:{axis_id}",
                    kind="legend",
                    axis_id=axis_id,
                    label="Legend",
                    bbox_pixels=legend_bbox,
                    payload_type="legend",
                    payload_id=axis_id,
                    operations=["select", "more"],
                )
            )
        for entry_index, text_artist in enumerate(legend.get_texts()):
            text = str(text_artist.get_text() or "").strip()
            if not text:
                continue
            try:
                bbox = _preview_bbox_from_display_bbox(
                    text_artist.get_window_extent(renderer=renderer),
                    scale=scale,
                    figure_height=figure_height,
                )
            except Exception:
                continue
            if not _bbox_has_area(bbox):
                continue
            objects.append(
                _preview_object(
                    object_id=f"legend_entry:{axis_id}:{entry_index}",
                    kind="legend_entry",
                    axis_id=axis_id,
                    label=text,
                    bbox_pixels=bbox,
                    payload_type="series",
                    payload_id=normalize_series_selection_ids([text])[0],
                    operations=["select", "quick_edit", "more"],
                )
            )
    return objects


def _preview_tagged_artist_bbox_and_points(
    artist: Any,
    *,
    renderer: Any,
    scale: float,
    figure_height: float,
) -> tuple[dict[str, float], list[list[float]]]:
    if hasattr(artist, "get_xdata") and hasattr(artist, "get_ydata") and hasattr(artist, "axes"):
        display_points = _line_display_points(artist)
        bbox = _inflate_degenerate_bbox(
            _preview_bbox_for_points(
                display_points,
                scale=scale,
                figure_height=figure_height,
            )
        )
        points = [
            _preview_pixel_point(point, scale=scale, figure_height=figure_height)
            for point in _downsample_points(display_points)
        ]
        return bbox, points
    try:
        bbox = _preview_bbox_from_display_bbox(
            artist.get_window_extent(renderer=renderer),
            scale=scale,
            figure_height=figure_height,
        )
    except Exception:
        bbox = {"x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0}
    return _inflate_degenerate_bbox(bbox), []


def _preview_tagged_interaction_objects(
    rendered: Any,
    *,
    renderer: Any,
    scale: float,
    figure_height: float,
) -> list[dict[str, Any]]:
    objects: list[dict[str, Any]] = []
    for axis_index, axis in enumerate(getattr(rendered.figure, "axes", [])):
        axis_id = axis.get_gid() or f"axis-{axis_index}"
        artist_groups = (
            getattr(axis, "lines", []),
            getattr(axis, "patches", []),
            getattr(axis, "texts", []),
            getattr(axis, "collections", []),
        )
        for artists in artist_groups:
            for artist in artists:
                metadata = interaction_artist_metadata(artist)
                if metadata is None or not bool(getattr(artist, "get_visible", lambda: True)()):
                    continue
                payload_type = str(metadata.get("payload_type") or "").strip()
                payload_id = str(metadata.get("payload_id") or "").strip()
                kind = str(metadata.get("kind") or payload_type or "object").strip()
                if not payload_type or not payload_id:
                    continue
                bbox, points = _preview_tagged_artist_bbox_and_points(
                    artist,
                    renderer=renderer,
                    scale=scale,
                    figure_height=figure_height,
                )
                if not _bbox_has_area(bbox):
                    continue
                label = metadata.get("label")
                objects.append(
                    _preview_object(
                        object_id=f"{kind}:{axis_id}:{payload_id}",
                        kind=kind,
                        axis_id=axis_id,
                        label=str(label) if label is not None else None,
                        bbox_pixels=bbox,
                        points=points,
                        payload_type=payload_type,
                        payload_id=payload_id,
                        operations=list(metadata.get("operations") or ["select", "more"]),
                    )
                )
    return objects


def _nearest_tick_label(axis: Any, x_value: float) -> str | None:
    tick_positions = [float(value) for value in axis.get_xticks()]
    tick_labels = [str(label.get_text()).strip() for label in axis.get_xticklabels()]
    candidates = [(position, label) for position, label in zip(tick_positions, tick_labels, strict=False) if label]
    if not candidates:
        return None
    return min(candidates, key=lambda item: abs(item[0] - x_value))[1]


def _preview_bar_objects(
    rendered: Any,
    *,
    renderer: Any,
    scale: float,
    figure_height: float,
) -> list[dict[str, Any]]:
    objects: list[dict[str, Any]] = []
    for axis_index, axis in enumerate(getattr(rendered.figure, "axes", [])):
        if axis_index > 0:
            continue
        axis_id = axis.get_gid() or f"axis-{axis_index}"
        for patch_index, patch in enumerate(getattr(axis, "patches", [])):
            if interaction_artist_metadata(patch) is not None:
                continue
            if patch.__class__.__name__ == "Cell" or not bool(getattr(patch, "get_visible", lambda: True)()):
                continue
            try:
                display_bbox = patch.get_window_extent(renderer=renderer)
                bbox = _preview_bbox_from_display_bbox(display_bbox, scale=scale, figure_height=figure_height)
            except Exception:
                continue
            if not _bbox_has_area(bbox):
                continue
            axis_bbox = axis.get_window_extent(renderer=renderer)
            if display_bbox.width >= axis_bbox.width * 0.95 and display_bbox.height >= axis_bbox.height * 0.95:
                continue
            label = _visible_artist_label(patch)
            if label is None:
                try:
                    label = _nearest_tick_label(axis, float(patch.get_x() + patch.get_width() / 2.0))
                except Exception:
                    label = None
            object_id = f"bar:{axis_id}:{patch_index}"
            payload_id = label or object_id
            objects.append(
                _preview_object(
                    object_id=object_id,
                    kind="bar",
                    axis_id=axis_id,
                    label=label,
                    bbox_pixels=bbox,
                    payload_type="series",
                    payload_id=payload_id,
                    operations=["select", "quick_edit", "more"],
                )
            )
    return objects


def _preview_cell_objects_for_paths(
    *,
    axis_id: str,
    kind: str,
    aggregate_kind: str,
    payload_type: str,
    collection: Any,
    paths: list[Any],
    scale: float,
    figure_height: float,
) -> list[dict[str, Any]]:
    if len(paths) > _INTERACTION_CELL_TARGET_LIMIT:
        try:
            transform = collection.get_transform()
            display_points = [
                tuple(point)
                for path in paths
                for point in transform.transform(path.vertices)
            ]
            bbox = _preview_bbox_for_points(display_points, scale=scale, figure_height=figure_height)
        except Exception:
            bbox = {"x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0}
        return [
            _preview_object(
                object_id=f"{aggregate_kind}:{axis_id}",
                kind=aggregate_kind,
                axis_id=axis_id,
                label=None,
                bbox_pixels=bbox,
                payload_type=payload_type,
                payload_id=axis_id,
                operations=["select", "more"],
            )
        ]

    objects: list[dict[str, Any]] = []
    transform = collection.get_transform()
    for index, path in enumerate(paths):
        try:
            display_points = [tuple(point) for point in transform.transform(path.vertices)]
        except Exception:
            continue
        bbox = _preview_bbox_for_points(display_points, scale=scale, figure_height=figure_height)
        if not _bbox_has_area(bbox):
            continue
        object_id = f"{kind}:{axis_id}:{index}"
        objects.append(
            _preview_object(
                object_id=object_id,
                kind=kind,
                axis_id=axis_id,
                label=None,
                bbox_pixels=bbox,
                points=[
                    _preview_pixel_point(point, scale=scale, figure_height=figure_height)
                    for point in _downsample_points(display_points, limit=12)
                ],
                payload_type=payload_type,
                payload_id=str(index),
                operations=["select", "more"],
            )
        )
    return objects


def _preview_heatmap_and_distribution_objects(
    rendered: Any,
    *,
    scale: float,
    figure_height: float,
) -> list[dict[str, Any]]:
    objects: list[dict[str, Any]] = []
    for axis_index, axis in enumerate(getattr(rendered.figure, "axes", [])):
        if axis_index > 0:
            continue
        axis_id = axis.get_gid() or f"axis-{axis_index}"
        for collection_index, collection in enumerate(getattr(axis, "collections", [])):
            if not bool(getattr(collection, "get_visible", lambda: True)()):
                continue
            class_name = collection.__class__.__name__
            paths = list(getattr(collection, "get_paths", lambda: [])())
            if class_name == "QuadMesh" and paths:
                objects.extend(
                    _preview_cell_objects_for_paths(
                        axis_id=axis_id,
                        kind="heatmap_cell",
                        aggregate_kind="heatmap_region",
                        payload_type="heatmap_cell",
                        collection=collection,
                        paths=paths,
                        scale=scale,
                        figure_height=figure_height,
                    )
                )
            elif class_name in {"PolyCollection", "QuadContourSet"} and paths:
                objects.extend(
                    _preview_cell_objects_for_paths(
                        axis_id=axis_id,
                        kind="distribution_body",
                        aggregate_kind="contour_region",
                        payload_type="artist",
                        collection=collection,
                        paths=paths[:1],
                        scale=scale,
                        figure_height=figure_height,
                    )
                )
            elif axis.name == "polar" and paths:
                objects.extend(
                    _preview_cell_objects_for_paths(
                        axis_id=axis_id,
                        kind="polar_region",
                        aggregate_kind="polar_region",
                        payload_type="artist",
                        collection=collection,
                        paths=paths[:1],
                        scale=scale,
                        figure_height=figure_height,
                    )
                )
            for obj in objects[-1:]:
                if obj["id"].endswith(f":{axis_id}"):
                    obj["id"] = f"{obj['id']}:{collection_index}"
    return objects


def _preview_table_objects(
    rendered: Any,
    *,
    renderer: Any,
    scale: float,
    figure_height: float,
) -> list[dict[str, Any]]:
    objects: list[dict[str, Any]] = []
    for axis_index, axis in enumerate(getattr(rendered.figure, "axes", [])):
        axis_id = axis.get_gid() or f"axis-{axis_index}"
        tables = list(getattr(axis, "tables", []))
        for table_index, table in enumerate(tables):
            cells = list(table.get_celld().items())
            if len(cells) > _INTERACTION_CELL_TARGET_LIMIT:
                try:
                    bbox = _preview_bbox_from_display_bbox(
                        table.get_window_extent(renderer=renderer),
                        scale=scale,
                        figure_height=figure_height,
                    )
                except Exception:
                    bbox = {"x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0}
                objects.append(
                    _preview_object(
                        object_id=f"table_region:{axis_id}:{table_index}",
                        kind="table_region",
                        axis_id=axis_id,
                        label=None,
                        bbox_pixels=bbox,
                        payload_type="table",
                        payload_id=str(table_index),
                        operations=["select", "more"],
                    )
                )
                continue
            for (row, column), cell in cells:
                try:
                    bbox = _preview_bbox_from_display_bbox(
                        cell.get_window_extent(renderer=renderer),
                        scale=scale,
                        figure_height=figure_height,
                    )
                except Exception:
                    continue
                if not _bbox_has_area(bbox):
                    continue
                text = str(cell.get_text().get_text() or "").strip()
                objects.append(
                    _preview_object(
                        object_id=f"table_cell:{axis_id}:{row}:{column}",
                        kind="table_cell",
                        axis_id=axis_id,
                        label=text or None,
                        bbox_pixels=bbox,
                        payload_type="table_cell",
                        payload_id=f"{row}:{column}",
                        operations=["select", "more"],
                    )
                )
    return objects


def _preview_interaction_objects(
    rendered: Any,
    *,
    axes_metadata: list[dict[str, Any]],
    artists: list[dict[str, Any]],
    renderer: Any,
    scale: float,
    figure_height: float,
) -> list[dict[str, Any]]:
    objects: list[dict[str, Any]] = []
    objects.extend(_preview_series_objects(artists))
    objects.extend(
        _preview_axis_objects(
            rendered,
            axes_metadata,
            renderer=renderer,
            scale=scale,
            figure_height=figure_height,
        )
    )
    objects.extend(
        _preview_tagged_interaction_objects(
            rendered,
            renderer=renderer,
            scale=scale,
            figure_height=figure_height,
        )
    )
    objects.extend(
        _preview_bar_objects(
            rendered,
            renderer=renderer,
            scale=scale,
            figure_height=figure_height,
        )
    )
    objects.extend(
        _preview_heatmap_and_distribution_objects(
            rendered,
            scale=scale,
            figure_height=figure_height,
        )
    )
    objects.extend(
        _preview_table_objects(
            rendered,
            renderer=renderer,
            scale=scale,
            figure_height=figure_height,
        )
    )
    deduped: dict[str, dict[str, Any]] = {}
    for obj in objects:
        bbox = obj.get("bbox_pixels") or {}
        if _bbox_has_area(bbox):
            deduped[str(obj["id"])] = obj
    return list(deduped.values())


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
        source_figure_height = float(figure.bbox.height)
        axes_metadata = [
            _preview_axis_metadata(
                rendered,
                axis,
                renderer=renderer,
                scale=scale,
                figure_height=source_figure_height,
            )
            for axis in figure.axes
        ]
        artists = _preview_series_artist_metadata(
            rendered,
            scale=scale,
            figure_height=source_figure_height,
        )
        return {
            "schema_version": 2,
            "figure": {
                "pixel_width": int(round(figure_width)),
                "pixel_height": int(round(figure_height)),
            },
            "axes": axes_metadata,
            "artists": artists,
            "objects": _preview_interaction_objects(
                rendered,
                axes_metadata=axes_metadata,
                artists=artists,
                renderer=renderer,
                scale=scale,
                figure_height=source_figure_height,
            ),
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
ImportStructureNodePayload.model_rebuild()
SourceTablePreviewResponse.model_rebuild()


__all__ = [
    "CodeConsoleGeneratedFileSnapshotPayload",
    "CodeConsoleProjectGeneratedFilePayload",
    "CodeConsoleProjectManualBindingPayload",
    "CodeConsoleProjectPayload",
    "CodeConsoleRunSnapshotPayload",
    "ComposerProjectPanelPayload",
    "ComposerProjectPayload",
    "DataStudioAnalysisOperationPayload",
    "DataStudioProjectPayload",
    "DataStudioProjectWorkbookPayload",
    "DataTransformPayload",
    "DataContainerColumnPayload",
    "DataContainerPayload",
    "DataContainerSourcePayload",
    "AnalysisOperationRequest",
    "AnalysisOperationResponse",
    "AnalysisOperationResultPayload",
    "ExportTargetPayload",
    "ImportDiagnosticPayload",
    "ImportFilterProfilePayload",
    "ImportOptionPayload",
    "ImportPreviewRequest",
    "ImportPreviewResponse",
    "ImportFilterPayload",
    "ImportStructureNodePayload",
    "NotebookOutputPayload",
    "PlotEditCommandNormalizeRequest",
    "PlotEditCommandNormalizeResponse",
    "PlotEditCommandPayload",
    "PlotObjectPayload",
    "DocumentGraphEdgePayload",
    "DocumentGraphNodePayload",
    "DocumentGraphPayload",
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
    "SeriesOffsetPayload",
    "SeriesStylePayload",
    "SourceTablePreviewRequest",
    "SourceTablePreviewResponse",
    "SourceTableSegmentResponse",
    "TemplateRecommendationResponse",
    "TextAnnotationPayload",
    "rendered_plots_to_preview_payload",
]
