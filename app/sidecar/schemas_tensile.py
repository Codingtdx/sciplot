from __future__ import annotations

from app.sidecar.schemas_common import StrictModel


class TensileReplicateRequest(StrictModel):
    file_paths: list[str]
    output_path: str
    group_name: str | None = None


class TensileWorkbookRequest(StrictModel):
    workbook_path: str


class TensileComparisonExportRequest(StrictModel):
    workbook_paths: list[str]
    output_dir: str


class TensileMetricSummaryResponse(StrictModel):
    label: str
    unit: str
    mean: float | None
    std: float | None


class TensileComparisonFigureOutputResponse(StrictModel):
    path: str
    category: str
    kind: str
    metric: str | None = None
    label: str


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
    preferred_sheet: str
    sheet_names: list[str]
    sample_count: int
    representative_filename: str
    metrics: list[TensileMetricSummaryResponse]
    warnings: list[str]


class TensileComparisonExportResponse(StrictModel):
    bundle_dir: str
    comparison_workbook_path: str
    labels: list[str]
    outputs: list[str]
    figure_outputs: list[TensileComparisonFigureOutputResponse]


__all__ = [
    "TensileComparisonExportRequest",
    "TensileComparisonExportResponse",
    "TensileComparisonFigureOutputResponse",
    "TensileMetricSummaryResponse",
    "TensileReplicateRequest",
    "TensileReplicateResponseModel",
    "TensileWorkbookRequest",
    "TensileWorkbookSummaryResponse",
]
