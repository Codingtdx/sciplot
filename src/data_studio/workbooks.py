from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from src.data_loader import CurveSeries, ReplicateGroup, load_curve_table, load_replicate_table, read_raw_table
from src.data_studio.builtin import tensile as tensile_builtin
from src.data_studio.io_utils import ensure_input_path, list_sheet_names
from src.data_studio.models import (
    DataStudioCurvePoint,
    DataStudioSpecimenPreview,
    DataStudioSpecimenState,
    DataStudioWorkbook,
    DataStudioWorkbookPreview,
    TemplateDefinition,
    TemplateMatch,
    WorkbookMetricSummary,
)
from src.data_studio.template_store import load_template
from src.data_studio.workbook_building import (
    _representative_scores,
    build_workbook,
    parse_structured_sample,
)
from src.data_studio.workbook_constants import (
    AUTO_FILTER_KEEP_COUNT,
    AUTO_FILTER_METRIC_TRIAD,
    FILTERED_WORKBOOK_CURVE_DECIMAL_PLACES,
    FILTERED_WORKBOOK_DECIMAL_PLACES,
    GENERIC_TEMPLATE_PARSE_STRATEGY,
)
from src.data_studio.workbook_export import export_filtered_workbook_from_context
from src.data_studio.workbook_template_authoring import create_template_from_candidates, slugify_template_label
from src.infrastructure.persistence.data_studio_imports import prepare_managed_data_studio_import_dir


@dataclass(frozen=True)
class LoadedWorkbookSpecimen:
    specimen_id: str
    label: str
    filename: str
    source_path: Path | None
    metrics: dict[str, float | None]
    curve: CurveSeries | None
    warnings: tuple[str, ...] = ()
    exclusions: tuple[str, ...] = ()


@dataclass(frozen=True)
class LoadedWorkbookSpecimenBundle:
    workbook: DataStudioWorkbook
    supported: bool
    unsupported_reason: str
    specimens: tuple[LoadedWorkbookSpecimen, ...] = ()


@dataclass(frozen=True)
class FilteredWorkbookContext:
    workbook: DataStudioWorkbook
    included_specimens: tuple[LoadedWorkbookSpecimen, ...]
    metric_summaries: tuple[WorkbookMetricSummary, ...]
    representative_specimen_id: str | None
    representative_filename: str | None
    representative_curve: CurveSeries | None
    replicate_groups: dict[str, ReplicateGroup]


@dataclass(frozen=True)
class _SpecimenAutoFilterScore:
    composite_signed_score: float | None
    distance_from_mean_score: float | None
    score_side: str
    auto_rule_role: str
    eligible_for_auto_filter: bool


def _auto_filter_minimum_reason() -> str:
    metrics = " / ".join(AUTO_FILTER_METRIC_TRIAD)
    return (
        f"Auto Keep {AUTO_FILTER_KEEP_COUNT} needs at least "
        f"{AUTO_FILTER_KEEP_COUNT} included specimens with {metrics}."
    )


def _auto_filter_variation_reason() -> str:
    metrics = " / ".join(AUTO_FILTER_METRIC_TRIAD)
    return f"Auto Keep {AUTO_FILTER_KEEP_COUNT} needs varying {metrics} values across the included set."


def _workbook_cache_key(path: str | Path) -> tuple[str, int]:
    workbook_path = ensure_input_path(str(Path(path).expanduser()))
    return str(workbook_path.resolve()), workbook_path.stat().st_mtime_ns


def _import_workbook_from_path(workbook_path: Path) -> DataStudioWorkbook:
    metadata = tensile_builtin.load_metadata_sheet(workbook_path)
    template_id = str(metadata.get("template_id", "")).strip()
    if template_id == tensile_builtin.TENSILE_TEMPLATE_ID:
        return tensile_builtin.inspect_tensile_workbook(workbook_path)

    sheet_names = tuple(list_sheet_names(workbook_path))
    if not sheet_names:
        raise ValueError(f"{workbook_path.name} is not a valid Excel workbook.")
    label = str(metadata.get("label", workbook_path.stem)).strip() or workbook_path.stem
    template = load_template(template_id) if template_id else TemplateDefinition(
        version=1,
        id="imported/unknown",
        label="Imported Workbook",
        family="imported_workbook",
        builtin=False,
        description="Imported Data Studio workbook without a template reference.",
        file_types=("xlsx",),
        parse_strategy=GENERIC_TEMPLATE_PARSE_STRATEGY,
    )
    metric_summaries = _metric_summaries_from_workbook(workbook_path)
    representative_filename = str(metadata.get("representative_filename", workbook_path.name))
    sample_count = int(metadata.get("sample_count", 0) or 0)
    source_files = tuple(Path(item) for item in metadata.get("source_files", ()))
    warnings = tuple(str(item) for item in metadata.get("warnings", ()))
    return DataStudioWorkbook(
        workbook_id=str(workbook_path),
        workbook_path=workbook_path,
        label=label,
        template_match=TemplateMatch(
            template_id=template.id,
            label=template.label,
            family=template.family,
            confidence=0.9,
            reasons=("Loaded Data Studio workbook metadata.",),
            auto_selected=True,
        ),
        source_files=source_files,
        sheet_names=sheet_names,
        preferred_sheet=tensile_builtin.REPRESENTATIVE_CURVE_SHEET,
        parsed_sample_count=sample_count,
        failed_sample_count=0,
        representative_filename=representative_filename,
        metrics=tuple(metric_summaries),
        warnings=warnings,
        samples=(),
    )


@lru_cache(maxsize=64)
def _import_workbook_cached(resolved_path: str, mtime_ns: int) -> DataStudioWorkbook:
    _ = mtime_ns
    return _import_workbook_from_path(Path(resolved_path))


def import_workbook(path: str | Path) -> DataStudioWorkbook:
    return _import_workbook_cached(*_workbook_cache_key(path))


def import_workbooks(path: str | Path) -> tuple[DataStudioWorkbook, ...]:
    workbook_path = ensure_input_path(str(Path(path).expanduser()))
    metadata = tensile_builtin.load_metadata_sheet(workbook_path)
    if _looks_like_comparison_bundle(workbook_path, metadata):
        imported = _import_source_workbooks_from_metadata(workbook_path, metadata)
        if imported:
            return imported
        materialized = _materialize_comparison_bundle_groups(workbook_path, metadata)
        if materialized:
            return materialized
        raise ValueError(
            f"{workbook_path.name} looks like a comparison workbook, but Data Studio could not recover any "
            "single-group workbooks from it."
        )
    return (import_workbook(workbook_path),)


def preview_workbook(
    path: str | Path,
    *,
    specimen_states: Iterable[DataStudioSpecimenState] | None = None,
) -> DataStudioWorkbookPreview:
    bundle = load_workbook_specimen_bundle(path)
    if not bundle.supported:
        total_count = bundle.workbook.parsed_sample_count
        return DataStudioWorkbookPreview(
            workbook_path=bundle.workbook.workbook_path,
            label=bundle.workbook.label,
            supported=False,
            unsupported_reason=bundle.unsupported_reason,
            total_specimen_count=total_count,
            included_specimen_count=total_count,
            excluded_specimen_count=0,
            representative_filename=bundle.workbook.representative_filename,
            metrics=bundle.workbook.metrics,
            warnings=bundle.workbook.warnings,
        )

    filtered = load_filtered_workbook_context(path, specimen_states=specimen_states, allow_empty=True)
    auto_filter_scores, suggested_ids, suggestion_reason = _analyze_auto_filter_specimens(filtered.included_specimens)
    included_ids = {specimen.specimen_id for specimen in filtered.included_specimens}
    specimen_previews_list: list[DataStudioSpecimenPreview] = []
    for specimen in bundle.specimens:
        score_info = auto_filter_scores.get(specimen.specimen_id, _DEFAULT_AUTO_FILTER_SCORE)
        specimen_previews_list.append(
            DataStudioSpecimenPreview(
                specimen_id=specimen.specimen_id,
                label=specimen.label,
                filename=specimen.filename,
                source_path=specimen.source_path,
                included=specimen.specimen_id in included_ids,
                metrics={key: value for key, value in specimen.metrics.items()},
                warnings=specimen.warnings,
                exclusions=specimen.exclusions,
                mini_curve_points=_downsample_curve_points(specimen.curve),
                triad_complete=_has_complete_triad(specimen.metrics),
                suggested_exclusion=specimen.specimen_id in suggested_ids,
                composite_signed_score=score_info.composite_signed_score,
                distance_from_mean_score=score_info.distance_from_mean_score,
                score_side=score_info.score_side,
                auto_rule_role=score_info.auto_rule_role,
                eligible_for_auto_filter=score_info.eligible_for_auto_filter,
            )
        )
    specimen_previews = tuple(specimen_previews_list)
    return DataStudioWorkbookPreview(
        workbook_path=bundle.workbook.workbook_path,
        label=bundle.workbook.label,
        supported=True,
        total_specimen_count=len(bundle.specimens),
        included_specimen_count=len(filtered.included_specimens),
        excluded_specimen_count=max(len(bundle.specimens) - len(filtered.included_specimens), 0),
        representative_specimen_id=filtered.representative_specimen_id,
        representative_filename=filtered.representative_filename,
        metrics=filtered.metric_summaries,
        specimens=specimen_previews,
        warnings=bundle.workbook.warnings,
        suggested_exclusion_ids=suggested_ids,
        suggestion_supported=not suggestion_reason,
        suggestion_support_reason=suggestion_reason,
    )


def _load_workbook_specimen_bundle_from_workbook(workbook: DataStudioWorkbook) -> LoadedWorkbookSpecimenBundle:
    workbook_path = workbook.workbook_path
    sheet_names = set(workbook.sheet_names)
    if tensile_builtin.ALL_SPECIMENS_SHEET not in sheet_names or tensile_builtin.ALL_CURVES_SHEET not in sheet_names:
        return LoadedWorkbookSpecimenBundle(
            workbook=workbook,
            supported=False,
            unsupported_reason=(
                "Specimen editing needs workbook-level All_Specimens and All_Curves sheets. "
                "This workbook can still be compared and exported."
            ),
        )

    try:
        summary_rows = _load_all_specimens_rows(workbook_path)
        if not summary_rows:
            raise ValueError("All_Specimens did not contain any specimen rows.")
        curves = load_curve_table(workbook_path, sheet_name=tensile_builtin.ALL_CURVES_SHEET)
        if not curves:
            raise ValueError("All_Curves did not contain any specimen curves.")
    except Exception as exc:
        return LoadedWorkbookSpecimenBundle(
            workbook=workbook,
            supported=False,
            unsupported_reason=f"Specimen editing could not read workbook details: {exc}",
        )

    source_path_by_name = {
        Path(source_path).name: Path(source_path)
        for source_path in workbook.source_files
    }
    curve_by_keys = _curve_lookup(curves)
    specimens: list[LoadedWorkbookSpecimen] = []
    for row in summary_rows:
        filename = str(row.get("Filename", "")).strip()
        if not filename:
            continue
        matched_curve = _match_curve_for_filename(filename, curve_by_keys)
        source_path = source_path_by_name.get(filename)
        metrics: dict[str, float | None] = {}
        for key, value in row.items():
            if key == "Filename":
                continue
            if value is None:
                metrics[key] = None
            elif isinstance(value, (int, float, np.floating)):
                metrics[key] = float(value)
            else:
                metrics[key] = None
        warnings: list[str] = []
        label = filename or (matched_curve.sample if matched_curve is not None else filename)
        if matched_curve is None:
            warnings.append("Curve preview unavailable.")
        specimens.append(
            LoadedWorkbookSpecimen(
                specimen_id=_specimen_id_for_filename(filename),
                label=label,
                filename=filename,
                source_path=source_path,
                metrics=metrics,
                curve=matched_curve,
                warnings=tuple(warnings),
            )
        )
    if not specimens:
        return LoadedWorkbookSpecimenBundle(
            workbook=workbook,
            supported=False,
            unsupported_reason="Specimen editing could not recover any specimen rows from All_Specimens.",
        )
    return LoadedWorkbookSpecimenBundle(
        workbook=workbook,
        supported=True,
        unsupported_reason="",
        specimens=tuple(specimens),
    )


@lru_cache(maxsize=64)
def _load_workbook_specimen_bundle_cached(resolved_path: str, mtime_ns: int) -> LoadedWorkbookSpecimenBundle:
    _ = mtime_ns
    workbook = _import_workbook_cached(resolved_path, mtime_ns)
    return _load_workbook_specimen_bundle_from_workbook(workbook)


def load_workbook_specimen_bundle(
    path: str | Path,
    *,
    workbook: DataStudioWorkbook | None = None,
) -> LoadedWorkbookSpecimenBundle:
    if workbook is not None:
        return _load_workbook_specimen_bundle_from_workbook(workbook)
    return _load_workbook_specimen_bundle_cached(*_workbook_cache_key(path))


def load_filtered_workbook_context(
    path: str | Path,
    *,
    specimen_states: Iterable[DataStudioSpecimenState] | None = None,
    allow_empty: bool = False,
    bundle: LoadedWorkbookSpecimenBundle | None = None,
) -> FilteredWorkbookContext:
    bundle = bundle or load_workbook_specimen_bundle(path)
    if not bundle.supported:
        raise ValueError(
            bundle.unsupported_reason
            or f"{bundle.workbook.workbook_path.name} does not support specimen editing."
        )

    state_map = _specimen_state_map(bundle.workbook.workbook_path, specimen_states)
    included_specimens = tuple(
        specimen
        for specimen in bundle.specimens
        if state_map.get(specimen.specimen_id, True)
    )
    if not included_specimens and not allow_empty:
        raise ValueError(f"{bundle.workbook.workbook_path.name} needs at least one included specimen.")

    metric_summaries = _metric_summaries_for_specimens(bundle.workbook.metrics, included_specimens)
    preferred_representative_specimen_id = _selected_representative_specimen_id(
        bundle.workbook.workbook_path,
        specimen_states,
    )
    if preferred_representative_specimen_id is None:
        preferred_representative_specimen_id = _metadata_representative_specimen_id(bundle.workbook.workbook_path)
    representative_curve_specimen = _representative_specimen(
        included_specimens,
        metric_order=[metric.label for metric in bundle.workbook.metrics],
        require_curve=True,
        preferred_specimen_id=preferred_representative_specimen_id,
    )
    representative_specimen = representative_curve_specimen or _representative_specimen(
        included_specimens,
        metric_order=[metric.label for metric in bundle.workbook.metrics],
        require_curve=False,
    )
    representative_curve = representative_curve_specimen.curve if representative_curve_specimen is not None else None
    replicate_groups = _replicate_groups_for_specimens(bundle.workbook, included_specimens)
    return FilteredWorkbookContext(
        workbook=bundle.workbook,
        included_specimens=included_specimens,
        metric_summaries=metric_summaries,
        representative_specimen_id=representative_specimen.specimen_id if representative_specimen is not None else None,
        representative_filename=representative_specimen.filename if representative_specimen is not None else None,
        representative_curve=representative_curve,
        replicate_groups=replicate_groups,
    )


def _load_all_specimens_rows(workbook_path: Path) -> list[dict[str, float | str | None]]:
    raw = read_raw_table(workbook_path, sheet_name=tensile_builtin.ALL_SPECIMENS_SHEET).fillna("")
    if raw.empty:
        return []
    headers = [_cell_text(value) for value in raw.iloc[0].tolist()]
    rows: list[dict[str, float | str | None]] = []
    for row_index in range(1, raw.shape[0]):
        values = raw.iloc[row_index].tolist()
        if all(_cell_text(value) == "" for value in values):
            continue
        row: dict[str, float | str | None] = {}
        for header, value in zip(headers, values, strict=False):
            if not header:
                continue
            if header == "Filename":
                row[header] = _cell_text(value)
                continue
            label, _unit = _split_metric_header(header)
            numeric = pd.to_numeric(pd.Series([value]), errors="coerce").iloc[0]
            row[label] = float(numeric) if pd.notna(numeric) else None
        rows.append(row)
    return rows


def _curve_lookup(curves: Iterable[CurveSeries]) -> dict[str, CurveSeries]:
    lookup: dict[str, CurveSeries] = {}
    for curve in curves:
        for key in _specimen_match_keys(curve.sample):
            lookup.setdefault(key, curve)
    return lookup


def _match_curve_for_filename(filename: str, curve_by_keys: dict[str, CurveSeries]) -> CurveSeries | None:
    for key in _specimen_match_keys(filename):
        if key in curve_by_keys:
            return curve_by_keys[key]
    return None


def _specimen_id_for_filename(filename: str) -> str:
    normalized = _normalize_specimen_token(filename)
    return normalized or filename or "specimen"


def _specimen_state_map(
    workbook_path: Path,
    specimen_states: Iterable[DataStudioSpecimenState] | None,
) -> dict[str, bool]:
    normalized_path = str(workbook_path.expanduser())
    return {
        state.specimen_id: state.included
        for state in (specimen_states or ())
        if str(Path(state.workbook_path).expanduser()) == normalized_path
    }


def _selected_representative_specimen_id(
    workbook_path: Path,
    specimen_states: Iterable[DataStudioSpecimenState] | None,
) -> str | None:
    normalized_path = str(workbook_path.expanduser())
    selected_specimen_id: str | None = None
    for state in specimen_states or ():
        if str(Path(state.workbook_path).expanduser()) != normalized_path:
            continue
        if state.selected_as_representative:
            selected_specimen_id = state.specimen_id
    return selected_specimen_id


def _metadata_representative_specimen_id(workbook_path: Path) -> str | None:
    metadata = tensile_builtin.load_metadata_sheet(workbook_path)
    specimen_id = str(metadata.get("representative_specimen_id", "")).strip()
    return specimen_id or None


def _metric_summaries_for_specimens(
    workbook_metrics: Iterable[WorkbookMetricSummary],
    specimens: Iterable[LoadedWorkbookSpecimen],
) -> tuple[WorkbookMetricSummary, ...]:
    specimen_list = list(specimens)
    summaries: list[WorkbookMetricSummary] = []
    for metric in workbook_metrics:
        values = [
            float(value)
            for specimen in specimen_list
            if (value := specimen.metrics.get(metric.label)) is not None and pd.notna(value)
        ]
        series = pd.Series(values, dtype=float) if values else pd.Series(dtype=float)
        summaries.append(
            WorkbookMetricSummary(
                id=metric.id,
                label=metric.label,
                unit=metric.unit,
                mean=float(series.mean()) if not series.empty else None,
                std=float(series.std(ddof=1)) if len(series.index) > 1 else None,
            )
        )
    return tuple(summaries)


def _replicate_groups_for_specimens(
    workbook: DataStudioWorkbook,
    specimens: Iterable[LoadedWorkbookSpecimen],
) -> dict[str, ReplicateGroup]:
    specimen_list = list(specimens)
    groups: dict[str, ReplicateGroup] = {}
    for metric in workbook.metrics:
        values = [
            float(value)
            for specimen in specimen_list
            if (value := specimen.metrics.get(metric.label)) is not None and pd.notna(value)
        ]
        groups[metric.label] = ReplicateGroup(
            group=workbook.label,
            value_label=metric.label,
            value_unit=metric.unit,
            data=pd.Series(values, dtype=float),
        )
    return groups


def _representative_specimen(
    specimens: Iterable[LoadedWorkbookSpecimen],
    *,
    metric_order: Iterable[str],
    require_curve: bool,
    preferred_specimen_id: str | None = None,
) -> LoadedWorkbookSpecimen | None:
    specimen_list = [specimen for specimen in specimens if specimen.curve is not None or not require_curve]
    if not specimen_list:
        return None
    if preferred_specimen_id:
        preferred = next(
            (specimen for specimen in specimen_list if specimen.specimen_id == preferred_specimen_id),
            None,
        )
        if preferred is not None:
            return preferred
    summary_df = _specimen_metric_dataframe(specimen_list, metric_order=metric_order)
    if summary_df.empty:
        return specimen_list[0]
    scores = _representative_scores(summary_df)
    ordered_indices = sorted(
        range(len(specimen_list)),
        key=lambda index: (scores.iloc[index], index, specimen_list[index].filename.lower()),
    )
    return specimen_list[ordered_indices[0]] if ordered_indices else specimen_list[0]


def _specimen_metric_dataframe(
    specimens: Iterable[LoadedWorkbookSpecimen],
    *,
    metric_order: Iterable[str],
) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for specimen in specimens:
        row: dict[str, object] = {"Filename": specimen.filename}
        for metric_label in metric_order:
            row[metric_label] = specimen.metrics.get(metric_label)
        rows.append(row)
    return pd.DataFrame(rows)


_DEFAULT_AUTO_FILTER_SCORE = _SpecimenAutoFilterScore(
    composite_signed_score=None,
    distance_from_mean_score=None,
    score_side="ineligible",
    auto_rule_role="ineligible",
    eligible_for_auto_filter=False,
)


def _analyze_auto_filter_specimens(
    specimens: Iterable[LoadedWorkbookSpecimen],
) -> tuple[dict[str, _SpecimenAutoFilterScore], tuple[str, ...], str]:
    specimen_list = list(specimens)
    eligible = [specimen for specimen in specimen_list if _has_complete_triad(specimen.metrics)]
    scores_by_specimen_id = {specimen.specimen_id: _DEFAULT_AUTO_FILTER_SCORE for specimen in specimen_list}
    if not eligible:
        return scores_by_specimen_id, (), _auto_filter_minimum_reason()

    composite = _composite_signed_scores(eligible)
    if composite is not None:
        for index, specimen in enumerate(eligible):
            signed_score = float(composite.iloc[index])
            if abs(signed_score) < 1e-9:
                score_side = "neutral"
            elif signed_score < 0:
                score_side = "low"
            else:
                score_side = "high"
            scores_by_specimen_id[specimen.specimen_id] = _SpecimenAutoFilterScore(
                composite_signed_score=signed_score,
                distance_from_mean_score=abs(signed_score),
                score_side=score_side,
                auto_rule_role="ineligible",
                eligible_for_auto_filter=True,
            )

    if len(eligible) < AUTO_FILTER_KEEP_COUNT:
        return scores_by_specimen_id, (), _auto_filter_minimum_reason()
    if composite is None:
        for specimen in eligible:
            scores_by_specimen_id[specimen.specimen_id] = _SpecimenAutoFilterScore(
                composite_signed_score=None,
                distance_from_mean_score=None,
                score_side="ineligible",
                auto_rule_role="ineligible",
                eligible_for_auto_filter=True,
            )
        return scores_by_specimen_id, (), _auto_filter_variation_reason()
    if composite.empty:
        return scores_by_specimen_id, (), f"Auto Keep {AUTO_FILTER_KEEP_COUNT} could not score the included specimens."

    ordered_eligible = sorted(
        eligible,
        key=lambda specimen: (
            scores_by_specimen_id[specimen.specimen_id].distance_from_mean_score
            if scores_by_specimen_id[specimen.specimen_id].distance_from_mean_score is not None
            else np.inf,
            specimen.filename.lower(),
            specimen.specimen_id,
        ),
    )
    kept_ids = {specimen.specimen_id for specimen in ordered_eligible[:AUTO_FILTER_KEEP_COUNT]}
    suggested_ids = tuple(
        specimen.specimen_id for specimen in specimen_list if specimen.specimen_id not in kept_ids
    )
    for specimen in eligible:
        score = scores_by_specimen_id[specimen.specimen_id]
        scores_by_specimen_id[specimen.specimen_id] = _SpecimenAutoFilterScore(
            composite_signed_score=score.composite_signed_score,
            distance_from_mean_score=score.distance_from_mean_score,
            score_side=score.score_side,
            auto_rule_role="keep" if specimen.specimen_id in kept_ids else "exclude",
            eligible_for_auto_filter=True,
        )
    return scores_by_specimen_id, suggested_ids, ""


def _composite_signed_scores(specimens: list[LoadedWorkbookSpecimen]) -> pd.Series | None:
    summary_df = _specimen_metric_dataframe(specimens, metric_order=AUTO_FILTER_METRIC_TRIAD)
    zscore_columns: list[pd.Series] = []
    for metric in AUTO_FILTER_METRIC_TRIAD:
        series = pd.to_numeric(summary_df[metric], errors="coerce")
        std_value = float(series.std(ddof=1)) if series.notna().sum() > 1 else 0.0
        if std_value <= 0:
            return None
        zscore_columns.append((series - float(series.mean())) / std_value)
    if not zscore_columns:
        return None
    return pd.concat(zscore_columns, axis=1).mean(axis=1)


def _has_complete_triad(metrics: dict[str, float | None]) -> bool:
    return all(metrics.get(metric) is not None and pd.notna(metrics.get(metric)) for metric in AUTO_FILTER_METRIC_TRIAD)


def _downsample_curve_points(curve: CurveSeries | None, *, max_points: int = 32) -> tuple[DataStudioCurvePoint, ...]:
    if curve is None or curve.data.empty:
        return ()
    dataframe = curve.data.reset_index(drop=True)
    if len(dataframe.index) <= max_points:
        indices = list(range(len(dataframe.index)))
    else:
        indices = np.linspace(0, len(dataframe.index) - 1, num=max_points, dtype=int).tolist()
    return tuple(
        DataStudioCurvePoint(
            x=float(dataframe.iloc[index]["x"]),
            y=float(dataframe.iloc[index]["y"]),
        )
        for index in indices
    )


def _split_metric_header(header: str) -> tuple[str, str]:
    if "(" not in header or ")" not in header:
        return header.strip(), ""
    label, unit = header.rsplit("(", 1)
    return label.strip(), unit.rstrip(")").strip()


def _specimen_match_keys(value: str) -> tuple[str, ...]:
    text = value.strip()
    if not text:
        return ()
    path = Path(text)
    name = path.name.strip()
    stem = path.stem.strip()
    candidates = [text, name, stem]
    normalized: list[str] = []
    seen: set[str] = set()
    for candidate in candidates:
        key = _normalize_specimen_token(candidate)
        if key and key not in seen:
            normalized.append(key)
            seen.add(key)
    return tuple(normalized)


def _normalize_specimen_token(value: str) -> str:
    return "".join(ch.lower() for ch in value.strip() if ch.isalnum())


def _metric_summaries_from_workbook(workbook_path: Path) -> list[WorkbookMetricSummary]:
    metrics: list[WorkbookMetricSummary] = []
    for sheet_name in list_sheet_names(workbook_path):
        if not sheet_name.endswith("_Replicates"):
            continue
        groups = load_replicate_table(workbook_path, sheet_name=sheet_name)
        if not groups:
            continue
        group = groups[0]
        series = group.data.dropna()
        metrics.append(
            WorkbookMetricSummary(
                id=group.value_label,
                label=group.value_label,
                unit=group.value_unit,
                mean=float(series.mean()) if not series.empty else None,
                std=float(series.std(ddof=1)) if len(series.index) > 1 else None,
            )
        )
    return metrics


def _looks_like_comparison_bundle(path: Path, metadata: dict[str, Any]) -> bool:
    template_id = str(metadata.get("template_id", "")).strip()
    if template_id == "data_studio/comparison":
        return True
    try:
        representative_curves = load_curve_table(path, sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET)
    except Exception:
        representative_curves = []
    if len(representative_curves) > 1:
        return True

    for sheet_name in list_sheet_names(path):
        if not sheet_name.endswith("_Replicates"):
            continue
        try:
            groups = load_replicate_table(path, sheet_name=sheet_name)
        except Exception:
            continue
        if len(groups) > 1:
            return True

    source_files = tuple(Path(item) for item in metadata.get("source_files", ()) if str(item).strip())
    return len(source_files) >= 2 and all(
        source_file.suffix.lower() in {".xlsx", ".xlsm", ".xls"} for source_file in source_files
    )


def _import_source_workbooks_from_metadata(path: Path, metadata: dict[str, Any]) -> tuple[DataStudioWorkbook, ...]:
    source_files = tuple(Path(item) for item in metadata.get("source_files", ()) if str(item).strip())
    if not source_files:
        return ()
    imported: list[DataStudioWorkbook] = []
    seen_paths: set[str] = set()
    try:
        for source_file in source_files:
            resolved = ensure_input_path(str(source_file.expanduser()))
            resolved_key = str(resolved)
            if resolved_key == str(path) or resolved_key in seen_paths:
                continue
            seen_paths.add(resolved_key)
            imported.append(import_workbook(resolved))
    except Exception:
        return ()
    return tuple(imported)


def _materialize_comparison_bundle_groups(path: Path, metadata: dict[str, Any]) -> tuple[DataStudioWorkbook, ...]:
    representative_curves = load_curve_table(path, sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET)
    if not representative_curves:
        return ()

    replicate_sheet_names = [sheet_name for sheet_name in list_sheet_names(path) if sheet_name.endswith("_Replicates")]
    replicate_groups_by_sheet = {
        sheet_name: load_replicate_table(path, sheet_name=sheet_name)
        for sheet_name in replicate_sheet_names
    }
    source_files = tuple(Path(item) for item in metadata.get("source_files", ()) if str(item).strip())
    import_dir = prepare_managed_data_studio_import_dir(path)
    imported: list[DataStudioWorkbook] = []

    for index, curve in enumerate(representative_curves):
        label = curve.sample.strip() or f"Recovered Group {index + 1}"
        workbook_path = import_dir / f"{slugify_template_label(label) or 'group'}_{index + 1}.xlsx"
        selected_metric_groups: list[tuple[str, Any]] = []
        sample_count = 0
        for sheet_name, groups in replicate_groups_by_sheet.items():
            group = _select_group_for_label(groups, label, index)
            if group is None:
                continue
            selected_metric_groups.append((sheet_name, group))
            sample_count = max(sample_count, len(group.data.index))
        source_path = source_files[index] if index < len(source_files) else path
        metadata_sheet = _comparison_group_metadata_sheet_dataframe(
            label=label,
            source_files=(source_path,),
            representative_filename=curve.sample or label,
            sample_count=sample_count or len(curve.data.index),
            warnings=(f"Recovered from comparison workbook {path.name}.",),
        )
        with pd.ExcelWriter(workbook_path) as writer:
            _single_curve_table_dataframe(label=label, curve=curve).to_excel(
                writer,
                sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET,
                header=False,
                index=False,
            )
            for sheet_name, group in selected_metric_groups:
                _single_replicate_table_dataframe(group).to_excel(
                    writer,
                    sheet_name=sheet_name,
                    header=False,
                    index=False,
                )
            metadata_sheet.to_excel(writer, sheet_name=tensile_builtin.METADATA_SHEET, header=False, index=False)
        imported.append(import_workbook(workbook_path))
    return tuple(imported)


def _select_group_for_label(groups: list[Any], label: str, index: int):
    if not groups:
        return None
    normalized_label = _normalize_group_key(label)
    for group in groups:
        if _normalize_group_key(group.group) == normalized_label:
            return group
    if index < len(groups):
        return groups[index]
    return None


def _normalize_group_key(value: object) -> str:
    return str(value).strip().casefold()


def _single_curve_table_dataframe(*, label: str, curve) -> pd.DataFrame:
    rows: list[list[object]] = [
        [curve.x_label, curve.y_label],
        [curve.x_unit, curve.y_unit],
        [label, label],
    ]
    for row_index in range(len(curve.data.index)):
        rows.append(
            [
                float(curve.data.iloc[row_index]["x"]),
                float(curve.data.iloc[row_index]["y"]),
            ]
        )
    return pd.DataFrame(rows)


def _single_replicate_table_dataframe(group) -> pd.DataFrame:
    rows: list[list[object]] = [
        [group.value_label],
        [group.group],
        [group.value_unit],
    ]
    rows.extend([[float(value)] for value in group.data.reset_index(drop=True).tolist()])
    return pd.DataFrame(rows)


def _comparison_group_metadata_sheet_dataframe(
    *,
    label: str,
    source_files: Iterable[Path],
    representative_filename: str,
    sample_count: int,
    warnings: Iterable[str],
) -> pd.DataFrame:
    rows = [
        ["label", label],
        ["source_files", " | ".join(str(path) for path in source_files)],
        ["warnings", " | ".join(str(item) for item in warnings)],
        ["representative_filename", representative_filename],
        ["sample_count", sample_count],
    ]
    return pd.DataFrame(rows)


def _cell_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and pd.isna(value):
        return ""
    return str(value).strip()


__all__ = [
    "GENERIC_TEMPLATE_PARSE_STRATEGY",
    "FILTERED_WORKBOOK_DECIMAL_PLACES",
    "FILTERED_WORKBOOK_CURVE_DECIMAL_PLACES",
    "build_workbook",
    "create_template_from_candidates",
    "export_filtered_workbook_from_context",
    "import_workbook",
    "import_workbooks",
    "load_filtered_workbook_context",
    "parse_structured_sample",
]
