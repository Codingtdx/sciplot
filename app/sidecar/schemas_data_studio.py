from __future__ import annotations

from pydantic import AliasChoices, Field

from app.sidecar.schemas_common import PreviewItemResponse, StrictModel, serialize_dataclass
from app.sidecar.schemas_render import (
    FitOptionsPayload,
    ImportDiagnosticPayload,
    ImportFilterProfilePayload,
    RenderOptionsPayload,
)


class DataStudioRangeResponse(StrictModel):
    sheet_name: str
    start_row: int
    end_row: int
    start_col: int
    end_col: int


class DataStudioSheetBlockResponse(StrictModel):
    id: str
    sheet_name: str
    label: str
    row_count: int
    col_count: int
    range: DataStudioRangeResponse
    header_row_index: int | None = None
    unit_row_index: int | None = None
    data_start_row_index: int | None = None
    sample_rows: list[list[object]] = Field(default_factory=list)


class DataStudioFieldCandidateResponse(StrictModel):
    id: str
    kind: str
    label: str
    confidence: float
    rationale: str
    sheet_name: str
    block_id: str | None = None
    range: DataStudioRangeResponse | None = None
    sample_values: list[str] = Field(default_factory=list)
    unit_hint: str | None = None


class DataStudioPreviewRangeResponse(StrictModel):
    sheet_name: str
    block_id: str | None = None
    start_row: int
    end_row: int
    start_col: int
    end_col: int
    role: str


class DataStudioBindingSuggestionResponse(StrictModel):
    id: str
    kind: str
    title: str
    summary: str
    sheet_name: str
    block_id: str | None = None
    candidate_ids: list[str] = Field(default_factory=list)
    preview_ranges: list[DataStudioPreviewRangeResponse] = Field(default_factory=list)
    default_selected: bool = False
    rationale: str = ""
    confidence: float | None = None


class DataStudioRawSheetPreviewResponse(StrictModel):
    sheet_name: str
    row_count: int
    col_count: int
    sample_rows: list[list[object]] = Field(default_factory=list)
    blocks: list[DataStudioSheetBlockResponse] = Field(default_factory=list)


class DataStudioRawFilePreviewResponse(StrictModel):
    source_path: str
    file_type: str
    encoding: str | None = None
    delimiter: str | None = None
    sheet_names: list[str] = Field(default_factory=list)
    sheets: list[DataStudioRawSheetPreviewResponse] = Field(default_factory=list)
    field_candidates: list[DataStudioFieldCandidateResponse] = Field(default_factory=list)
    binding_suggestions: list[DataStudioBindingSuggestionResponse] = Field(default_factory=list)
    recommended_template_ids: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class DataStudioTemplateFieldBindingResponse(StrictModel):
    id: str
    role: str
    label: str
    sheet_name: str | None = None
    block_id: str | None = None
    column_name: str | None = None
    column_index: int | None = None
    row_label_contains: str | None = None
    cell_value_contains: list[str] = Field(default_factory=list)
    unit_hint: str | None = None
    sample_name: str | None = None
    optional: bool = False


class DataStudioTemplateConditionResponse(StrictModel):
    sheet_name_contains: list[str] = Field(default_factory=list)
    text_contains: list[str] = Field(default_factory=list)
    field_kinds: list[str] = Field(default_factory=list)
    minimum_score: float = 0.0


class DataStudioTemplateSourceFormatResponse(StrictModel):
    encoding: str | None = None
    delimiter: str | None = None
    sheet_name: str | None = None


class DataStudioTemplateSegmentSelectorResponse(StrictModel):
    id: str
    label: str
    result_label: str | None = None
    interval_index: int | None = None
    header_row_index: int | None = Field(default=None, validation_alias=AliasChoices("header_row_index", "header_row"))
    unit_row_index: int | None = Field(default=None, validation_alias=AliasChoices("unit_row_index", "unit_row"))
    data_start_row_index: int | None = Field(
        default=None,
        validation_alias=AliasChoices("data_start_row_index", "data_start_row"),
    )
    start_row: int | None = None
    end_row: int | None = None


class DataStudioTemplateResponse(StrictModel):
    version: int
    id: str
    label: str
    family: str
    builtin: bool
    description: str
    file_types: list[str] = Field(default_factory=list)
    parse_strategy: str
    match_conditions: list[DataStudioTemplateConditionResponse] = Field(default_factory=list)
    field_bindings: list[DataStudioTemplateFieldBindingResponse] = Field(default_factory=list)
    workbook_metric_ids: list[str] = Field(default_factory=list)
    default_group_name_strategy: str = "common_prefix"
    preferred_sheet_name: str = "Representative_Curve"
    output_kind: str = "curve_metrics"
    comparison_enabled: bool = True
    source_format: DataStudioTemplateSourceFormatResponse = Field(
        default_factory=DataStudioTemplateSourceFormatResponse
    )
    segment_policy: str = "single_table"
    segment_selectors: list[DataStudioTemplateSegmentSelectorResponse] = Field(default_factory=list)
    metadata: dict[str, object] = Field(default_factory=dict)


class DataStudioTemplateMatchResponse(StrictModel):
    template_id: str
    label: str
    family: str
    confidence: float
    reasons: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    matched_sheet_names: list[str] = Field(default_factory=list)
    auto_selected: bool = False


class DataStudioMetricSummaryResponse(StrictModel):
    id: str
    label: str
    unit: str
    mean: float | None
    std: float | None


class DataStudioWorkbookSampleResponse(StrictModel):
    id: str
    source_path: str
    filename: str
    parsed: bool
    warnings: list[str] = Field(default_factory=list)
    exclusions: list[str] = Field(default_factory=list)
    metrics: dict[str, float | None] = Field(default_factory=dict)


class DataStudioCurvePointResponse(StrictModel):
    x: float
    y: float


class DataStudioSpecimenStateRequest(StrictModel):
    workbook_path: str
    specimen_id: str
    included: bool = True
    selected_as_representative: bool = False


class DataStudioSpecimenStateResponse(StrictModel):
    workbook_path: str
    specimen_id: str
    included: bool = True
    selected_as_representative: bool = False


class DataStudioSpecimenPreviewResponse(StrictModel):
    specimen_id: str
    label: str
    filename: str
    source_path: str | None = None
    included: bool
    metrics: dict[str, float | None] = Field(default_factory=dict)
    warnings: list[str] = Field(default_factory=list)
    exclusions: list[str] = Field(default_factory=list)
    mini_curve_points: list[DataStudioCurvePointResponse] = Field(default_factory=list)
    triad_complete: bool = False
    suggested_exclusion: bool = False
    composite_signed_score: float | None = None
    distance_from_mean_score: float | None = None
    score_side: str = "ineligible"
    auto_rule_role: str = "ineligible"
    eligible_for_auto_filter: bool = False


class DataStudioWorkbookResponse(StrictModel):
    workbook_id: str
    workbook_path: str
    label: str
    template_match: DataStudioTemplateMatchResponse
    source_files: list[str] = Field(default_factory=list)
    sheet_names: list[str] = Field(default_factory=list)
    preferred_sheet: str
    parsed_sample_count: int
    failed_sample_count: int
    representative_filename: str
    metrics: list[DataStudioMetricSummaryResponse] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    exclusions: list[str] = Field(default_factory=list)
    samples: list[DataStudioWorkbookSampleResponse] = Field(default_factory=list)


class DataStudioWorkbookPreviewResponse(StrictModel):
    workbook_path: str
    label: str
    supported: bool
    unsupported_reason: str = ""
    total_specimen_count: int = 0
    included_specimen_count: int = 0
    excluded_specimen_count: int = 0
    representative_specimen_id: str | None = None
    representative_filename: str | None = None
    metrics: list[DataStudioMetricSummaryResponse] = Field(default_factory=list)
    specimens: list[DataStudioSpecimenPreviewResponse] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    suggested_exclusion_ids: list[str] = Field(default_factory=list)
    suggestion_supported: bool = False
    suggestion_support_reason: str = ""


class DataStudioImportWorkbookResponse(StrictModel):
    workbooks: list[DataStudioWorkbookResponse] = Field(default_factory=list)


class DataStudioGroupStateResponse(StrictModel):
    workbook_path: str
    display_name: str
    include_in_compare: bool = True
    sort_order: int = 0


class DataStudioComparisonRecipeResponse(StrictModel):
    id: str
    label: str
    category: str
    template_id: str
    sheet_name: str
    metric_id: str | None = None
    enabled_by_default: bool = True
    supported: bool = True
    support_reason: str = ""


class DataStudioFigureOutputResponse(StrictModel):
    path: str
    label: str
    category: str
    template_id: str
    sheet_name: str
    metric_id: str | None = None
    recipe_id: str | None = None


class DataStudioFilteredWorkbookResponse(StrictModel):
    path: str
    label: str
    source_workbook_path: str
    representative_filename: str


class DataStudioComparisonSetResponse(StrictModel):
    id: str
    label: str
    workbook_paths: list[str] = Field(default_factory=list)
    workbook_labels: list[str] = Field(default_factory=list)
    comparison_workbook_path: str
    recipes: list[DataStudioComparisonRecipeResponse] = Field(default_factory=list)


class DataStudioFigurePreferenceResponse(StrictModel):
    family_id: str
    selected_template_id: str | None = None
    options_by_template: dict[str, dict[str, object]] = Field(default_factory=dict)
    fit_options_by_template: dict[str, FitOptionsPayload] = Field(default_factory=dict)


class DataStudioSessionResponse(StrictModel):
    version: int
    selected_template_id: str | None = None
    selected_workbook_id: str | None = None
    primary_workbook_id: str | None = None
    selected_recipe_id: str | None = None
    workbook_paths: list[str] = Field(default_factory=list)
    comparison_recipe_ids: list[str] = Field(default_factory=list)
    selected_figure_family_id: str | None = None
    selected_figure_template_id: str | None = None
    group_states: list[DataStudioGroupStateResponse] = Field(default_factory=list)
    specimen_states: list[DataStudioSpecimenStateResponse] = Field(default_factory=list)
    figure_preferences: list[DataStudioFigurePreferenceResponse] = Field(default_factory=list)
    imported_paths: list[str] = Field(default_factory=list)
    template_draft_path: str | None = None


class DataStudioCreateTemplateRequest(StrictModel):
    label: str
    template_id: str | None = None
    description: str = ""
    output_kind: str = "curve_metrics"
    comparison_enabled: bool = True
    source_format: DataStudioTemplateSourceFormatResponse = Field(
        default_factory=DataStudioTemplateSourceFormatResponse
    )
    segment_policy: str = "single_table"
    segment_selectors: list[DataStudioTemplateSegmentSelectorResponse] = Field(default_factory=list)
    field_bindings: list[DataStudioTemplateFieldBindingResponse] = Field(default_factory=list)
    match_conditions: list[DataStudioTemplateConditionResponse] = Field(default_factory=list)


class DataStudioUpdateTemplateRequest(StrictModel):
    new_id: str | None = None
    new_label: str | None = None


class DataStudioBuildWorkbookRequest(StrictModel):
    file_paths: list[str]
    output_path: str
    template_id: str
    group_name: str | None = None


class DataStudioImportWorkbookRequest(StrictModel):
    workbook_path: str


class DataStudioWorkbookPreviewRequest(StrictModel):
    workbook_path: str
    specimen_states: list[DataStudioSpecimenStateRequest] = Field(default_factory=list)


class DataStudioTemplatePreviewSegmentResponse(StrictModel):
    id: str
    label: str
    curve_count: int = 0
    metric_count: int = 0
    row_count: int = 0


class DataStudioTemplatePreviewRequest(StrictModel):
    source_path: str
    template: DataStudioCreateTemplateRequest
    import_profile: ImportFilterProfilePayload | None = None
    import_diagnostics: list[ImportDiagnosticPayload] = Field(default_factory=list)
    selected_sheet_or_segment: str | None = None


class DataStudioTemplateRecommendationsRequest(StrictModel):
    source_path: str
    import_profile: ImportFilterProfilePayload | None = None
    import_diagnostics: list[ImportDiagnosticPayload] = Field(default_factory=list)
    selected_sheet_or_segment: str | None = None


class DataStudioTemplatePreviewResponse(StrictModel):
    template_id: str
    output_kind: str
    parsed_sample_count: int
    failed_sample_count: int
    series_count: int
    metric_count: int
    matrix_row_count: int
    missing_roles: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    errors: list[str] = Field(default_factory=list)
    segments: list[DataStudioTemplatePreviewSegmentResponse] = Field(default_factory=list)


class DataStudioComparisonRequest(StrictModel):
    workbook_paths: list[str]
    group_states: list[DataStudioGroupStateResponse] = Field(default_factory=list)
    specimen_states: list[DataStudioSpecimenStateRequest] = Field(default_factory=list)


class DataStudioPreviewComparisonRequest(StrictModel):
    workbook_paths: list[str]
    recipe_id: str
    group_states: list[DataStudioGroupStateResponse] = Field(default_factory=list)
    specimen_states: list[DataStudioSpecimenStateRequest] = Field(default_factory=list)


class DataStudioExportComparisonRequest(StrictModel):
    workbook_paths: list[str]
    output_dir: str
    group_states: list[DataStudioGroupStateResponse] = Field(default_factory=list)
    specimen_states: list[DataStudioSpecimenStateRequest] = Field(default_factory=list)
    selected_recipe_ids: list[str] = Field(default_factory=list)
    figure_options_by_recipe_id: dict[str, RenderOptionsPayload] = Field(default_factory=dict)
    figure_fit_options_by_recipe_id: dict[str, FitOptionsPayload] = Field(default_factory=dict)


class DataStudioSessionNormalizeRequest(StrictModel):
    payload: dict[str, object]


class DataStudioTemplateListResponse(StrictModel):
    templates: list[DataStudioTemplateResponse] = Field(default_factory=list)


class DataStudioTemplateRecommendationsResponse(StrictModel):
    matches: list[DataStudioTemplateMatchResponse] = Field(default_factory=list)


class DataStudioComparisonPreviewResponse(StrictModel):
    comparison_set: DataStudioComparisonSetResponse
    recipe: DataStudioComparisonRecipeResponse
    preview: PreviewItemResponse


class DataStudioComparisonContextResponse(StrictModel):
    comparison_set: DataStudioComparisonSetResponse
    cache_key: str | None = None
    materialized_at: str | None = None


class DataStudioComparisonExportResponse(StrictModel):
    comparison_set: DataStudioComparisonSetResponse
    figure_outputs: list[DataStudioFigureOutputResponse] = Field(default_factory=list)
    filtered_workbooks: list[DataStudioFilteredWorkbookResponse] = Field(default_factory=list)


__all__ = [
    "DataStudioBuildWorkbookRequest",
    "DataStudioBindingSuggestionResponse",
    "DataStudioComparisonExportResponse",
    "DataStudioComparisonContextResponse",
    "DataStudioComparisonRecipeResponse",
    "DataStudioComparisonRequest",
    "DataStudioComparisonPreviewResponse",
    "DataStudioComparisonSetResponse",
    "DataStudioCreateTemplateRequest",
    "DataStudioCurvePointResponse",
    "DataStudioExportComparisonRequest",
    "DataStudioFilteredWorkbookResponse",
    "DataStudioFieldCandidateResponse",
    "DataStudioFigurePreferenceResponse",
    "DataStudioFigureOutputResponse",
    "DataStudioGroupStateResponse",
    "DataStudioImportWorkbookResponse",
    "DataStudioImportWorkbookRequest",
    "DataStudioMetricSummaryResponse",
    "DataStudioPreviewComparisonRequest",
    "DataStudioPreviewRangeResponse",
    "DataStudioRawFilePreviewResponse",
    "DataStudioRawSheetPreviewResponse",
    "DataStudioRangeResponse",
    "DataStudioSessionNormalizeRequest",
    "DataStudioSessionResponse",
    "DataStudioSheetBlockResponse",
    "DataStudioSpecimenPreviewResponse",
    "DataStudioSpecimenStateRequest",
    "DataStudioSpecimenStateResponse",
    "DataStudioTemplateConditionResponse",
    "DataStudioTemplateFieldBindingResponse",
    "DataStudioTemplateListResponse",
    "DataStudioTemplateMatchResponse",
    "DataStudioTemplatePreviewRequest",
    "DataStudioTemplatePreviewResponse",
    "DataStudioTemplatePreviewSegmentResponse",
    "DataStudioTemplateRecommendationsRequest",
    "DataStudioTemplateRecommendationsResponse",
    "DataStudioTemplateResponse",
    "DataStudioTemplateSegmentSelectorResponse",
    "DataStudioTemplateSourceFormatResponse",
    "DataStudioUpdateTemplateRequest",
    "DataStudioWorkbookResponse",
    "DataStudioWorkbookPreviewRequest",
    "DataStudioWorkbookPreviewResponse",
    "DataStudioWorkbookSampleResponse",
    "serialize_dataclass",
]
