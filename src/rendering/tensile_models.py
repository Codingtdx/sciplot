from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from src.data_loader import CurveSeries, ReplicateGroup
from src.tensile_replicates import METRIC_SPECS, REPRESENTATIVE_CURVE_SHEET, SUMMARY_SHEET, TensileMetricSummary

METRIC_NAMES = tuple(label for label, _, _, _ in METRIC_SPECS)
METRIC_UNITS = {label: unit for label, unit, _, _ in METRIC_SPECS}
REQUIRED_TENSILE_WORKBOOK_SHEETS = frozenset(
    {
        REPRESENTATIVE_CURVE_SHEET,
        SUMMARY_SHEET,
        *(f"{label}_Replicates" for label in METRIC_NAMES),
    }
)
COMPARISON_CURVE_FILENAME = "representative_curve_compare.pdf"
SUMMARY_COLUMNS = (
    "Label",
    "Workbook Path",
    "Specimens",
    "Representative File",
    "Strength Mean (MPa)",
    "Strength Std (MPa)",
    "Modulus Mean (MPa)",
    "Modulus Std (MPa)",
    "Elongation Mean (%)",
    "Elongation Std (%)",
)


@dataclass(frozen=True)
class TensileWorkbookSummary:
    workbook_path: Path
    label: str
    sheet_names: tuple[str, ...]
    sample_count: int
    representative_filename: str
    metrics: tuple[TensileMetricSummary, ...]


@dataclass(frozen=True)
class TensileComparisonExport:
    bundle_dir: Path
    comparison_workbook_path: Path
    labels: tuple[str, ...]
    outputs: tuple[Path, ...]


@dataclass(frozen=True)
class LoadedTensileWorkbook:
    workbook_path: Path
    base_label: str
    sheet_names: tuple[str, ...]
    sample_count: int
    representative_filename: str
    representative_curve: CurveSeries
    metrics: tuple[TensileMetricSummary, ...]
    replicate_groups: dict[str, ReplicateGroup]


__all__ = [
    "COMPARISON_CURVE_FILENAME",
    "LoadedTensileWorkbook",
    "METRIC_NAMES",
    "METRIC_UNITS",
    "REQUIRED_TENSILE_WORKBOOK_SHEETS",
    "SUMMARY_COLUMNS",
    "TensileComparisonExport",
    "TensileWorkbookSummary",
]
