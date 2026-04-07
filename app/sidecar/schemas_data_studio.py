from __future__ import annotations

from pydantic import Field

from app.sidecar.schemas_common import PreviewItemResponse, StrictModel, serialize_dataclass
from app.sidecar.schemas_render import RenderOptionsPayload


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
    optional: bool = False


class DataStudioTemplateConditionResponse(StrictModel):
    sheet_name_contains: list[str] = Field(default_factory=list)
    text_contains: list[str] = Field(default_factory=list)
    field_kinds: list[str] = Field(default_factory=list)
    minimum_score: float = 0.0


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
    figure_preferences: list[DataStudioFigurePreferenceResponse] = Field(default_factory=list)
    imported_paths: list[str] = Field(default_factory=list)
    template_draft_path: str | None = None


class DataStudioSourcePreviewRequest(StrictModel):
    input_path: str


class DataStudioCreateTemplateRequest(StrictModel):
    source_path: str
    label: str
    accepted_candidate_ids: list[str] = Field(default_factory=list)
    template_id: str | None = None
    description: str = ""


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


class DataStudioComparisonRequest(StrictModel):
    workbook_paths: list[str]
    group_states: list[DataStudioGroupStateResponse] = Field(default_factory=list)


class DataStudioPreviewComparisonRequest(StrictModel):
    workbook_paths: list[str]
    recipe_id: str
    group_states: list[DataStudioGroupStateResponse] = Field(default_factory=list)


class DataStudioExportComparisonRequest(StrictModel):
    workbook_paths: list[str]
    output_dir: str
    group_states: list[DataStudioGroupStateResponse] = Field(default_factory=list)
    selected_recipe_ids: list[str] = Field(default_factory=list)
    figure_options_by_recipe_id: dict[str, RenderOptionsPayload] = Field(default_factory=dict)


class DataStudioSessionNormalizeRequest(StrictModel):
    payload: dict[str, object]


class DataStudioSourcePreviewResponse(StrictModel):
    preview: DataStudioRawFilePreviewResponse
    matches: list[DataStudioTemplateMatchResponse] = Field(default_factory=list)


class DataStudioTemplateListResponse(StrictModel):
    templates: list[DataStudioTemplateResponse] = Field(default_factory=list)


class DataStudioComparisonPreviewResponse(StrictModel):
    comparison_set: DataStudioComparisonSetResponse
    recipe: DataStudioComparisonRecipeResponse
    preview: PreviewItemResponse


class DataStudioComparisonExportResponse(StrictModel):
    comparison_set: DataStudioComparisonSetResponse
    figure_outputs: list[DataStudioFigureOutputResponse] = Field(default_factory=list)


__all__ = [
    "DataStudioBuildWorkbookRequest",
    "DataStudioBindingSuggestionResponse",
    "DataStudioComparisonExportResponse",
    "DataStudioComparisonRecipeResponse",
    "DataStudioComparisonRequest",
    "DataStudioComparisonPreviewResponse",
    "DataStudioComparisonSetResponse",
    "DataStudioCreateTemplateRequest",
    "DataStudioExportComparisonRequest",
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
    "DataStudioSourcePreviewRequest",
    "DataStudioSourcePreviewResponse",
    "DataStudioTemplateConditionResponse",
    "DataStudioTemplateFieldBindingResponse",
    "DataStudioTemplateListResponse",
    "DataStudioTemplateMatchResponse",
    "DataStudioTemplateResponse",
    "DataStudioUpdateTemplateRequest",
    "DataStudioWorkbookResponse",
    "DataStudioWorkbookSampleResponse",
    "serialize_dataclass",
]
