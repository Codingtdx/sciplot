from __future__ import annotations

import json
from base64 import b64encode
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

from src import plot_style
from src.composer import (
    COMPOSER_VERSION,
    ComposerProject,
    project_from_dict,
    serialize_project,
)


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


class SavedRenderOptionsPayload(StrictModel):
    size: str | None = None
    xscale: str | None = None
    yscale: str | None = None
    reverse_x: bool | None = None
    baseline: str | None = None
    show_colorbar: bool | None = None
    style_preset: str | None = None
    palette_preset: str | None = None
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


class OpenPathRequest(StrictModel):
    output_path: str


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


class SaveProjectRequest(StrictModel):
    project_path: str
    data: Any


class OpenProjectRequest(StrictModel):
    project_path: str


class ThumbnailRequest(StrictModel):
    file_path: str
    page_index: int = 0
    max_side_px: int = 640


class DefaultsResponse(StrictModel):
    style_preset: str
    palette_preset: str


class GlobalFrameResponse(StrictModel):
    panel_width_mm: float
    panel_height_mm: float
    left_margin_mm: float
    right_margin_mm: float
    bottom_margin_mm: float
    top_margin_mm: float


class WorkbenchSizeResponse(StrictModel):
    id: str
    label: str
    width_mm: float
    height_mm: float


class SizePresetContractResponse(StrictModel):
    label: str
    width_mm: float
    height_mm: float


class WorkbenchStyleResponse(StrictModel):
    id: str
    label: str
    public: bool
    description: str
    hard_constraints: bool
    preset_note: str


class WorkbenchPaletteResponse(StrictModel):
    id: str
    label: str
    public: bool
    description: str
    swatches: list[str]


class WorkbenchVisualThemeResponse(StrictModel):
    id: str
    label: str
    description: str


class WorkbenchTemplateResponse(StrictModel):
    id: str
    canonical_id: str
    role: str
    lifecycle_policy: str
    implementation_id: str
    label: str
    description: str
    category: str
    default_size: str
    allowed_sizes: list[str]
    editable_options: list[str]
    default_options: dict[str, Any]
    available_styles: list[str]
    available_palettes: list[str]


class MetaResponse(StrictModel):
    version: int
    defaults: DefaultsResponse
    global_frame: GlobalFrameResponse
    sizes: list[WorkbenchSizeResponse]
    styles: list[WorkbenchStyleResponse]
    palettes: list[WorkbenchPaletteResponse]
    visual_themes: list[WorkbenchVisualThemeResponse] = Field(default_factory=list)
    templates: list[WorkbenchTemplateResponse]
    template_ids: list[str]
    size_ids: list[str]
    palette_preset_ids: list[str]
    default_style: str
    default_palette: str


class DataTemplateSummaryResponse(StrictModel):
    chart_type: str
    label: str
    filename_stem: str
    template_id: str
    input_model: str
    source_template_id: str
    format_summary: str


class DataTemplateCatalogResponse(StrictModel):
    templates: list[DataTemplateSummaryResponse]


class MaterializeDataTemplateRequest(StrictModel):
    template_id: str
    variant: Literal["example", "blank"]


class MaterializeDataTemplateResponse(StrictModel):
    template_id: str
    variant: Literal["example", "blank"]
    label: str
    input_model: str
    typical_families: list[str]
    format_summary: str
    file_path: str
    filename: str
    sheet_name: str


class DataTemplateFolderFileResponse(StrictModel):
    chart_type: str
    label: str
    template_id: str
    filename: str
    file_path: str
    input_model: str
    source_template_id: str
    format_summary: str


class MaterializeDataTemplateFolderRequest(StrictModel):
    variant: Literal["example", "blank"]


class MaterializeDataTemplateFolderResponse(StrictModel):
    variant: Literal["example", "blank"]
    folder_path: str
    folder_name: str
    chart_types: list[str]
    files: list[DataTemplateFolderFileResponse]


class ManagedStorageStatusResponse(StrictModel):
    root_path: str
    data_root: str
    cache_root: str
    example_templates_path: str
    blank_templates_path: str
    single_example_templates_path: str
    single_blank_templates_path: str
    plot_exports_path: str
    code_console_runs_path: str
    example_template_file_count: int
    blank_template_file_count: int
    single_template_file_count: int
    plot_export_dir_count: int
    code_console_run_dir_count: int


class ManagedStorageCleanupRequest(StrictModel):
    strategy: Literal["all", "stale"] = "all"


class ManagedStorageCleanupResponse(ManagedStorageStatusResponse):
    strategy: Literal["all", "stale"]
    removed_files: int
    removed_directories: int


class PlotContractAliasesResponse(StrictModel):
    style_presets: dict[str, str]


class TypographyResponse(StrictModel):
    font_family: list[str]
    font_size_pt: float
    legend_font_size_pt: float
    panel_label_size_pt: float
    panel_label_weight: str


class StrokeResponse(StrictModel):
    axis_linewidth_pt: float
    tick_width_pt: float
    tick_length_pt: float
    minor_tick_width_pt: float
    minor_tick_length_pt: float
    line_width_pt: float
    line_alpha: float
    marker_alpha: float
    fill_alpha: float
    max_fill_alpha: float
    marker_size_pt: float


class SpacingResponse(StrictModel):
    axes_labelpad: float
    xtick_major_pad: float
    ytick_major_pad: float
    legend_inset_fraction: float


class AnnotationResponse(StrictModel):
    legend_frameon: bool
    legend_tightness: str
    label_tightness: str


class ExportContractResponse(StrictModel):
    figure_dpi: int
    savefig_dpi: int
    savefig_format: str
    pdf_fonttype: int
    ps_fonttype: int
    color_space: str
    vector_preferred: bool
    accessibility_note: str


class StyleContractResponse(StrictModel):
    label: str
    public: bool
    description: str
    hard_constraints: bool
    preset_note: str
    typography: TypographyResponse
    stroke: StrokeResponse
    spacing: SpacingResponse
    annotation: AnnotationResponse
    export: ExportContractResponse


class PaletteContractResponse(StrictModel):
    label: str
    public: bool
    description: str
    categorical: list[str]
    sequential: str
    diverging: str


class TemplateContractResponse(StrictModel):
    label: str
    description: str
    category: str
    default_size: str
    allowed_sizes: list[str]
    editable_options: list[str]
    default_options: dict[str, Any]
    available_styles: list[str]
    available_palettes: list[str]
    hard_rules: list[str]
    soft_rules: list[str]


class ValidationRuleResponse(StrictModel):
    label: str
    description: str
    severity: str
    tolerance_mm: float | None = None


class AxisPolicyResponse(StrictModel):
    linear_nice_steps: list[float]
    linear_outer_padding_fraction: float
    linear_force_visible_labeled_endpoints: bool
    log_display_steps: list[float]
    log_label_mode: str
    log_allow_unlabeled_outer_padding: bool
    bar_zero_baseline_no_lower_padding: bool
    tensile_y_include_zero: bool
    stacked_x_use_standard_endpoint_policy: bool


class PlotContractResponse(StrictModel):
    version: int
    defaults: DefaultsResponse
    aliases: PlotContractAliasesResponse
    global_frame: GlobalFrameResponse
    axis_policy: AxisPolicyResponse
    size_presets: dict[str, SizePresetContractResponse]
    special_layouts: dict[str, dict[str, Any]]
    qa_profiles: dict[str, dict[str, Any]]
    styles: dict[str, StyleContractResponse]
    palettes: dict[str, PaletteContractResponse]
    templates: dict[str, TemplateContractResponse]
    validation_rules: dict[str, ValidationRuleResponse]


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
    recommendation_confidence: float = 0.0
    recommendation_summary: str = ""
    warnings: list[str] = Field(default_factory=list)
    signals: list[str] = Field(default_factory=list)


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


class InspectFileResponse(StrictModel):
    input_path: str
    sheet: str | int
    sheet_names: list[str]
    inspection: InputInspectionResponse


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


class ComposerSuggestedPatchResponse(StrictModel):
    kind: Literal["panel", "text"]
    id: str
    patch: dict[str, Any]


class ComposerPreviewResponse(StrictModel):
    valid: bool
    validation_error: str | None
    png_base64: str
    qa: QAReportResponse | None = None
    submission_report: SubmissionReportResponse | None = None
    suggested_project_patch: list[ComposerSuggestedPatchResponse] = Field(default_factory=list)


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


class PathResponse(StrictModel):
    output_path: str


class ProjectPathResponse(StrictModel):
    project_path: str


class ComposerProjectResponse(ComposerRequest):
    pass


class WizardProjectState(StrictModel):
    input_path: str
    sheet: str | int = 0
    template: str | None = None
    options: SavedRenderOptionsPayload = Field(default_factory=SavedRenderOptionsPayload)
    outputs: list[str] = Field(default_factory=list)


class WizardProjectDocument(StrictModel):
    version: Literal[1] = 1
    mode: Literal["wizard"] = "wizard"
    wizard: WizardProjectState


class ComposerProjectDocument(StrictModel):
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

    @field_validator("mode")
    @classmethod
    def _validate_mode(cls, value: str) -> str:
        if value != "composer":
            raise ValueError("mode must be 'composer'")
        return value


class ComposerProjectEnvelope(StrictModel):
    version: Literal[2] = 2
    mode: Literal["composer"] = "composer"
    project: ComposerProjectDocument


class OpenProjectResponse(StrictModel):
    project_path: str
    data: WizardProjectDocument | ComposerProjectEnvelope


class CodeConsoleGenerateRequest(StrictModel):
    intent: Literal["custom_plot", "patch_renderer", "annotation_tweak"] = "custom_plot"
    brief: str = ""
    base_template: str
    options: RenderOptionsPayload | None = None
    size: str | None = None
    style_preset: str | None = None
    palette_preset: str | None = None
    target_path: str | None = None
    input_path: str | None = None
    sheet: str | int | None = 0
    project_path: str | None = None
    include_data_context: bool = True
    include_inspection_summary: bool = True
    include_project_context: bool = False


class CodeConsoleExportRequest(CodeConsoleGenerateRequest):
    output_dir: str
    include_full_data: bool = False


class CodeConsoleReasonedValueResponse(StrictModel):
    label: str
    value: str
    reason: str


class CodeConsoleDefaultsPanelResponse(StrictModel):
    locked_by_contract: list[CodeConsoleReasonedValueResponse]
    user_selectable: list[CodeConsoleReasonedValueResponse]
    derived_from_session: list[CodeConsoleReasonedValueResponse]


class CodeConsoleTruthSourceResponse(StrictModel):
    id: str
    label: str
    path: str | None = None
    display_path: str | None = None
    kind: str
    available: bool
    reason: str


class CodeConsoleContractResponse(StrictModel):
    version: int
    sha256: str
    default_style: str
    default_palette: str


class CodeConsoleSessionResponse(StrictModel):
    session_id: str
    session_source: str
    project_id: str | None = None
    project_path: str | None = None
    project_mode: str | None = None
    input_path: str | None = None
    input_display_path: str | None = None
    input_filename: str | None = None
    sheet: str | int | None = None
    sheet_names: list[str] = Field(default_factory=list)
    template: str
    size_label: str
    size_id: str
    style_preset: str
    palette_preset: str
    xscale: str
    yscale: str
    reverse_x: bool
    baseline: str
    show_colorbar: bool
    intent: str
    target_path: str


class CodeConsoleColumnSummaryResponse(StrictModel):
    name: str
    inferred_type: str
    non_empty_count: int
    missing_count: int
    header_preview: list[str | None]
    min_value: float | int | None = None
    max_value: float | int | None = None


class CodeConsoleInspectionSummaryResponse(StrictModel):
    warnings: list[str]
    signals: list[str]


class CodeConsoleRecommendationSummaryResponse(StrictModel):
    template: str
    reason: str
    size: str | None = None
    style_preset: str | None = None
    palette_preset: str | None = None


class CodeConsoleDataContextResponse(StrictModel):
    available: bool
    model: str | None = None
    model_label: str
    raw_row_count: int
    raw_column_count: int
    column_names: list[str]
    normalized_columns: list[str]
    column_summaries: list[CodeConsoleColumnSummaryResponse]
    sample_rows: list[list[Any]]
    normalized_preview_rows: list[list[Any]]
    missing_summary: dict[str, int]
    inspection: CodeConsoleInspectionSummaryResponse
    recommendation: CodeConsoleRecommendationSummaryResponse
    interpreted_summary: dict[str, Any]
    full_data_rows: int
    full_data_columns: int


class CodeConsoleLightweightBundleResponse(StrictModel):
    text: str
    includes_data_context: bool
    includes_inspection_summary: bool
    includes_project_context: bool
    includes_full_data: bool


class CodeConsoleGenerateResponse(StrictModel):
    bundle_version: int
    generated_at: str
    contract: CodeConsoleContractResponse
    session: CodeConsoleSessionResponse
    defaults_panel: CodeConsoleDefaultsPanelResponse
    truth_sources: list[CodeConsoleTruthSourceResponse]
    data_context: CodeConsoleDataContextResponse
    prompt_text: str
    scaffold_text: str
    lightweight_bundle: CodeConsoleLightweightBundleResponse


class CodeConsoleExportResponse(StrictModel):
    bundle_dir: str
    zip_path: str
    manifest_path: str
    exported_files: list[str]
    includes_full_data: bool
    truth_sources: list[CodeConsoleTruthSourceResponse]


class CodeConsoleRunRequest(StrictModel):
    code: str
    base_template: str
    options: RenderOptionsPayload | None = None
    input_path: str
    sheet: str | int = 0
    project_path: str | None = None
    include_project_context: bool = False


class CodeConsoleGeneratedFileResponse(StrictModel):
    path: str
    filename: str
    kind: str


class CodeConsoleRunResponse(StrictModel):
    generated_at: str
    output_dir: str
    stdout: str
    stderr: str
    exit_code: int
    timed_out: bool
    duration_ms: int
    generated_files: list[CodeConsoleGeneratedFileResponse]
    previews: list[PreviewItemResponse]


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


def rendered_plots_to_preview_payload(rendered_plots: list[Any], *, dpi: int = 160) -> list[PreviewItemResponse]:
    previews: list[PreviewItemResponse] = []
    for rendered in rendered_plots:
        from io import BytesIO

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


def _project_validation_message(exc: ValidationError) -> str:
    error = exc.errors(include_url=False)[0]
    loc = ".".join(str(item) for item in error.get("loc", ()))
    msg = error.get("msg", "invalid value")
    if loc:
        return f"Invalid project file field: {loc} - {msg}"
    return f"Invalid project file field: {msg}"


def _composer_version_error() -> ValueError:
    return ValueError("Composer projects only support version: 2. Re-import the assets to create a new project.")


def _normalize_composer_project(payload: dict[str, Any]) -> ComposerProjectDocument:
    version = payload.get("version")
    if version is not None and int(version) != COMPOSER_VERSION:
        raise _composer_version_error()

    try:
        normalized = project_from_dict(payload)
    except ValueError as exc:
        message = str(exc)
        if "version: 2" in message:
            raise _composer_version_error() from exc
        raise ValueError(f"Invalid Composer project field: {exc}") from exc
    except Exception as exc:
        raise ValueError(f"Invalid Composer project field: {exc}") from exc

    try:
        return ComposerProjectDocument.model_validate(serialize_project(normalized))
    except ValidationError as exc:
        raise ValueError(_project_validation_message(exc)) from exc


def normalize_project_document(data: Any) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise ValueError("This is not a recognizable SciPlot God project file.")

    mode = data.get("mode")
    if mode == "wizard":
        try:
            return WizardProjectDocument.model_validate(data).model_dump()
        except ValidationError as exc:
            raise ValueError(_project_validation_message(exc)) from exc

    if mode == "composer":
        if data.get("version") not in (None, COMPOSER_VERSION):
            raise _composer_version_error()
        project_payload = data.get("project")
        if "project" in data and project_payload is not None and not isinstance(project_payload, dict):
            raise ValueError("Invalid project file field: project - must be an object.")
        if isinstance(project_payload, dict):
            normalized_project = _normalize_composer_project(project_payload)
        else:
            normalized_project = _normalize_composer_project(data)
        envelope = ComposerProjectEnvelope(version=COMPOSER_VERSION, mode="composer", project=normalized_project)
        return envelope.model_dump()

    raise ValueError("This is not a recognizable SciPlot God project file.")


def save_project_document(project_path: str | Path, data: Any) -> Path:
    path = Path(project_path).expanduser()
    normalized = normalize_project_document(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(normalized, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def load_project_document(project_path: str | Path) -> dict[str, Any]:
    path = Path(project_path).expanduser()
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError("The project file is not valid JSON.") from exc
    return normalize_project_document(payload)


def composer_project_from_request(request: ComposerRequest) -> ComposerProject:
    return project_from_dict(request.model_dump())
