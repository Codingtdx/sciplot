from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any, TypedDict

import numpy as np
import pandas as pd

from src.data_loader import CurveSeries, ReplicateGroup, load_curve_table, load_replicate_table, read_raw_table
from src.data_studio.builtin import tensile as tensile_builtin
from src.data_studio.ingest import preview_raw_file, read_preview_source
from src.data_studio.io_utils import ensure_input_path, list_sheet_names
from src.data_studio.models import (
    DataStudioCurvePoint,
    DataStudioSpecimenPreview,
    DataStudioSpecimenState,
    DataStudioWorkbook,
    DataStudioWorkbookPreview,
    FieldCandidate,
    TemplateDefinition,
    TemplateFieldBinding,
    TemplateFieldRole,
    TemplateMatch,
    WorkbookMetricSummary,
    WorkbookSample,
)
from src.data_studio.template_store import load_template
from src.infrastructure.persistence.data_studio_imports import prepare_managed_data_studio_import_dir

GENERIC_TEMPLATE_PARSE_STRATEGY = "structured:curve_metrics_columns"


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


class ParsedStructuredSample(TypedDict):
    filename: str
    curve: pd.DataFrame
    metrics: dict[str, float | None]
    x_label: str
    y_label: str
    x_unit: str | None
    y_unit: str | None


def create_template_from_candidates(
    *,
    source_path: str | Path,
    label: str,
    accepted_candidate_ids: Iterable[str] | None = None,
    template_id: str | None = None,
    description: str = "",
) -> TemplateDefinition:
    preview = preview_raw_file(source_path)
    accepted_ids = set(accepted_candidate_ids or ())
    all_candidates = list(preview.field_candidates)
    candidates = [candidate for candidate in all_candidates if not accepted_ids or candidate.id in accepted_ids]
    x_candidate, y_candidate = _resolve_curve_pair(preview, accepted_ids, candidates, all_candidates)
    if x_candidate is None or y_candidate is None:
        raise ValueError("Template creation needs at least one recommended X field and one recommended Y field.")
    metric_candidates = [candidate for candidate in candidates if candidate.kind == "metric"]
    block = _resolve_block(preview, x_candidate.block_id or y_candidate.block_id)
    metadata = {
        "sheet_name": block.sheet_name if block is not None else x_candidate.sheet_name,
        "block_id": block.id if block is not None else x_candidate.block_id,
        "header_row_index": block.header_row_index if block is not None else None,
        "unit_row_index": block.unit_row_index if block is not None else None,
        "data_start_row_index": block.data_start_row_index if block is not None else None,
    }
    field_bindings = [
        _binding_from_candidate(x_candidate, role="curve_x"),
        _binding_from_candidate(y_candidate, role="curve_y"),
    ]
    for candidate in metric_candidates:
        field_bindings.append(_binding_from_candidate(candidate, role="metric"))

    resolved_id = template_id or f"user/{slugify_template_label(label)}"
    return TemplateDefinition(
        version=1,
        id=resolved_id,
        label=label.strip() or "Untitled Data Studio Template",
        family="structured_curve_metrics",
        builtin=False,
        description=description.strip() or f"Template created from {Path(source_path).name}.",
        file_types=(Path(source_path).suffix.lower().lstrip("."),),
        parse_strategy=GENERIC_TEMPLATE_PARSE_STRATEGY,
        field_bindings=tuple(field_bindings),
        workbook_metric_ids=tuple(binding.label for binding in field_bindings if binding.role == "metric"),
        preferred_sheet_name="Representative_Curve",
        metadata=metadata,
    )


def _resolve_curve_pair(
    preview,
    accepted_ids: set[str],
    candidates: list[FieldCandidate],
    all_candidates: list[FieldCandidate],
) -> tuple[FieldCandidate | None, FieldCandidate | None]:
    selected_curve_suggestions = [
        suggestion
        for suggestion in preview.binding_suggestions
        if suggestion.kind == "curve_pair"
        and suggestion.candidate_ids
        and set(suggestion.candidate_ids).issubset(accepted_ids)
    ]
    if selected_curve_suggestions:
        curve_candidate_ids = set(selected_curve_suggestions[0].candidate_ids)
        x_candidate = next(
            (
                candidate
                for candidate in all_candidates
                if candidate.id in curve_candidate_ids and candidate.kind == "curve_x"
            ),
            None,
        )
        y_candidate = next(
            (
                candidate
                for candidate in all_candidates
                if candidate.id in curve_candidate_ids and candidate.kind == "curve_y"
            ),
            None,
        )
        if x_candidate is not None and y_candidate is not None:
            return x_candidate, y_candidate

    same_block_pairs: list[tuple[float, FieldCandidate, FieldCandidate]] = []
    candidate_pool = candidates or all_candidates
    x_candidates = [candidate for candidate in candidate_pool if candidate.kind == "curve_x"]
    y_candidates = [candidate for candidate in candidate_pool if candidate.kind == "curve_y"]
    for x_candidate in x_candidates:
        for y_candidate in y_candidates:
            if x_candidate.block_id and y_candidate.block_id and x_candidate.block_id != y_candidate.block_id:
                continue
            score = x_candidate.confidence + y_candidate.confidence
            same_block_pairs.append((score, x_candidate, y_candidate))
    if same_block_pairs:
        same_block_pairs.sort(key=lambda item: (-item[0], item[1].label.lower(), item[2].label.lower()))
        _, x_candidate, y_candidate = same_block_pairs[0]
        return x_candidate, y_candidate

    return _best_candidate(candidates, "curve_x") or _best_candidate(all_candidates, "curve_x"), _best_candidate(
        candidates, "curve_y"
    ) or _best_candidate(all_candidates, "curve_y")


def build_workbook(
    *,
    file_paths: Iterable[str | Path],
    output_path: str | Path,
    template_id: str,
    group_name: str | None = None,
) -> DataStudioWorkbook:
    template = load_template(template_id)
    if template.parse_strategy == "builtin:tensile":
        return tensile_builtin.export_tensile_replicate_workbook(file_paths, output_path, group_name=group_name)
    if template.parse_strategy != GENERIC_TEMPLATE_PARSE_STRATEGY:
        raise ValueError(f"Unsupported Data Studio parse strategy: {template.parse_strategy}")

    paths = [Path(path).expanduser() for path in file_paths]
    if not paths:
        raise ValueError("Select at least one source file.")

    parsed_samples: list[ParsedStructuredSample] = []
    workbook_samples: list[WorkbookSample] = []
    warnings: list[str] = []
    for path in paths:
        try:
            parsed = parse_structured_sample(path, template)
            parsed_samples.append(parsed)
            workbook_samples.append(
                WorkbookSample(
                    id=str(path),
                    source_path=path,
                    filename=path.name,
                    parsed=True,
                    metrics=dict(parsed["metrics"]),
                )
            )
        except Exception as exc:
            warning = f"Skipped {path.name}: {exc}"
            warnings.append(warning)
            workbook_samples.append(
                WorkbookSample(
                    id=str(path),
                    source_path=path,
                    filename=path.name,
                    parsed=False,
                    warnings=(warning,),
                    exclusions=(str(exc),),
                )
            )

    if not parsed_samples:
        raise ValueError("No source files matched the selected Data Studio template.")

    resolved_group_name = (group_name or infer_group_name(paths)).strip() or "DataStudio_Group"
    metrics_df = _metrics_dataframe(parsed_samples)
    representative_index = _representative_index(metrics_df)
    representative = parsed_samples[representative_index]
    workbook_path = Path(output_path).expanduser().with_suffix(".xlsx")
    workbook_path.parent.mkdir(parents=True, exist_ok=True)

    metric_summaries = _metric_summaries(metrics_df)
    with pd.ExcelWriter(workbook_path) as writer:
        _metadata_sheet_dataframe(
            label=resolved_group_name,
            template_id=template.id,
            source_files=paths,
            warnings=warnings,
            representative_filename=str(representative["filename"]),
            sample_count=len(parsed_samples),
            metric_ids=[metric.id for metric in metric_summaries],
        ).to_excel(writer, sheet_name=tensile_builtin.METADATA_SHEET, header=False, index=False)
        _curve_table_dataframe(
            ((f"{resolved_group_name} representative", representative["curve"]),)
        ).to_excel(writer, sheet_name=tensile_builtin.REPRESENTATIVE_CURVE_SHEET, header=False, index=False)
        _curve_table_dataframe((str(item["filename"]), item["curve"]) for item in parsed_samples).to_excel(
            writer,
            sheet_name=tensile_builtin.ALL_CURVES_SHEET,
            header=False,
            index=False,
        )
        _plain_table_dataframe(metrics_df).to_excel(
            writer,
            sheet_name=tensile_builtin.ALL_SPECIMENS_SHEET,
            header=False,
            index=False,
        )
        _summary_sheet_dataframe(
            metrics_df,
            representative_filename=str(representative["filename"]),
            metrics=metric_summaries,
        ).to_excel(writer, sheet_name=tensile_builtin.SUMMARY_SHEET, header=False, index=False)
        for metric in metric_summaries:
            _replicate_table_dataframe(
                group_name=resolved_group_name,
                value_label=metric.label,
                value_unit=metric.unit,
                values=metrics_df[f"{metric.label} ({metric.unit})"].dropna().tolist(),
            ).to_excel(writer, sheet_name=f"{metric.label}_Replicates", header=False, index=False)

    return DataStudioWorkbook(
        workbook_id=str(workbook_path),
        workbook_path=workbook_path,
        label=resolved_group_name,
        template_match=TemplateMatch(
            template_id=template.id,
            label=template.label,
            family=template.family,
            confidence=0.92,
            reasons=("Built with the selected Data Studio template.",),
            auto_selected=True,
        ),
        source_files=tuple(paths),
        sheet_names=tuple(list_sheet_names(workbook_path)),
        preferred_sheet=tensile_builtin.REPRESENTATIVE_CURVE_SHEET,
        parsed_sample_count=len(parsed_samples),
        failed_sample_count=len(paths) - len(parsed_samples),
        representative_filename=str(representative["filename"]),
        metrics=tuple(metric_summaries),
        warnings=tuple(warnings),
        exclusions=tuple(sample.filename for sample in workbook_samples if not sample.parsed),
        samples=tuple(workbook_samples),
    )


def import_workbook(path: str | Path) -> DataStudioWorkbook:
    workbook_path = ensure_input_path(str(Path(path).expanduser()))
    metadata = tensile_builtin.load_metadata_sheet(workbook_path)
    template_id = str(metadata.get("template_id", "")).strip()
    if template_id == tensile_builtin.TENSILE_TEMPLATE_ID or _looks_like_legacy_tensile_workbook(workbook_path):
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
    suggested_ids, suggestion_reason = _suggested_exclusion_ids(filtered.included_specimens)
    included_ids = {specimen.specimen_id for specimen in filtered.included_specimens}
    specimen_previews = tuple(
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
        )
        for specimen in bundle.specimens
    )
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
        suggestion_supported=bool(suggested_ids),
        suggestion_support_reason=suggestion_reason,
    )


def load_workbook_specimen_bundle(path: str | Path) -> LoadedWorkbookSpecimenBundle:
    workbook = import_workbook(path)
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
        label = filename or (matched_curve.sample if matched_curve is not None else filename)
        warnings: list[str] = []
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


def load_filtered_workbook_context(
    path: str | Path,
    *,
    specimen_states: Iterable[DataStudioSpecimenState] | None = None,
    allow_empty: bool = False,
) -> FilteredWorkbookContext:
    bundle = load_workbook_specimen_bundle(path)
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
    representative_specimen = _representative_specimen(
        included_specimens,
        metric_order=[metric.label for metric in bundle.workbook.metrics],
        require_curve=False,
    )
    representative_curve_specimen = _representative_specimen(
        included_specimens,
        metric_order=[metric.label for metric in bundle.workbook.metrics],
        require_curve=True,
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


def parse_structured_sample(path: str | Path, template: TemplateDefinition) -> ParsedStructuredSample:
    source_path = Path(path).expanduser()
    sheets, _encoding, _delimiter = read_preview_source(source_path)
    sheet_name = str(template.metadata.get("sheet_name", "")) or sheets[0][0]
    frame = next((frame for current_sheet, frame in sheets if current_sheet == sheet_name), None)
    if frame is None:
        raise ValueError(f"{source_path.name} does not contain the expected sheet {sheet_name!r}.")

    header_row_index = int(template.metadata.get("header_row_index", 0) or 0)
    unit_row_index = (
        int(template.metadata["unit_row_index"]) if template.metadata.get("unit_row_index") is not None else None
    )
    data_start_row_index = (
        int(template.metadata["data_start_row_index"])
        if template.metadata.get("data_start_row_index") is not None
        else header_row_index + 1
    )
    header_row = [_cell_text(value) for value in frame.iloc[header_row_index].tolist()]
    unit_row = (
        [_cell_text(value) for value in frame.iloc[unit_row_index].tolist()]
        if unit_row_index is not None
        else []
    )

    x_binding = _binding_by_role(template.field_bindings, "curve_x")
    y_binding = _binding_by_role(template.field_bindings, "curve_y")
    if x_binding is None or y_binding is None:
        raise ValueError("Template is missing curve_x or curve_y bindings.")

    x_column_index = _resolve_column_index(header_row, x_binding)
    y_column_index = _resolve_column_index(header_row, y_binding)
    if x_column_index is None or y_column_index is None:
        raise ValueError("Template bindings could not be matched to file columns.")

    pair = frame.iloc[data_start_row_index:, [x_column_index, y_column_index]].copy()
    pair.columns = ["x", "y"]
    pair = pair.apply(pd.to_numeric, errors="coerce").dropna(subset=["x", "y"]).reset_index(drop=True)
    if pair.empty:
        raise ValueError("Selected curve columns did not contain numeric data.")

    metrics: dict[str, float | None] = {}
    for binding in [binding for binding in template.field_bindings if binding.role == "metric"]:
        metric_column_index = _resolve_column_index(header_row, binding)
        if metric_column_index is None:
            if binding.optional:
                metrics[binding.label] = None
                continue
            raise ValueError(f"Metric binding {binding.label!r} could not be matched.")
        metric_values = pd.to_numeric(frame.iloc[:, metric_column_index], errors="coerce").dropna()
        metrics[binding.label] = float(metric_values.iloc[-1]) if not metric_values.empty else None

    x_unit = _unit_for_column(unit_row, x_column_index)
    y_unit = _unit_for_column(unit_row, y_column_index)
    return {
        "filename": source_path.name,
        "curve": pair,
        "metrics": metrics,
        "x_label": x_binding.label,
        "y_label": y_binding.label,
        "x_unit": x_unit,
        "y_unit": y_unit,
    }


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
) -> LoadedWorkbookSpecimen | None:
    specimen_list = [specimen for specimen in specimens if specimen.curve is not None or not require_curve]
    if not specimen_list:
        return None
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


def _representative_scores(summary_df: pd.DataFrame) -> pd.Series:
    numeric_columns = [column for column in summary_df.columns if column != "Filename"]
    if not numeric_columns:
        return pd.Series(0.0, index=summary_df.index, dtype=float)
    scores = pd.Series(0.0, index=summary_df.index, dtype=float)
    contributions = pd.Series(0, index=summary_df.index, dtype=int)
    for column in numeric_columns:
        series = pd.to_numeric(summary_df[column], errors="coerce")
        std_value = float(series.std(ddof=1)) if series.notna().sum() > 1 else 0.0
        if std_value <= 0:
            continue
        z_squared = ((series - float(series.mean())) / std_value) ** 2
        scores = scores.add(z_squared.fillna(0.0), fill_value=0.0)
        contributions = contributions.add(series.notna().astype(int), fill_value=0).astype(int)
    if not (contributions > 0).any():
        return pd.Series(0.0, index=summary_df.index, dtype=float)
    return scores.where(contributions > 0, other=np.inf)


def _suggested_exclusion_ids(specimens: Iterable[LoadedWorkbookSpecimen]) -> tuple[tuple[str, ...], str]:
    eligible = [specimen for specimen in specimens if _has_complete_triad(specimen.metrics)]
    if len(eligible) < 7:
        return (), "Suggest Exclusions needs at least 7 included specimens with Strength / Modulus / Elongation."
    triad = ["Strength", "Modulus", "Elongation"]
    summary_df = _specimen_metric_dataframe(eligible, metric_order=triad)
    zscore_columns: list[pd.Series] = []
    for metric in triad:
        series = pd.to_numeric(summary_df[metric], errors="coerce")
        std_value = float(series.std(ddof=1)) if series.notna().sum() > 1 else 0.0
        if std_value <= 0:
            continue
        zscore_columns.append((series - float(series.mean())) / std_value)
    if len(zscore_columns) != len(triad):
        return (), "Suggest Exclusions needs varying Strength / Modulus / Elongation values across the included set."
    composite = pd.concat(zscore_columns, axis=1).mean(axis=1)
    if composite.empty:
        return (), "Suggest Exclusions could not score the included specimens."
    lowest_index = int(composite.idxmin())
    highest_index = int(composite.idxmax())
    if lowest_index == highest_index:
        return (), "Suggest Exclusions needs at least two distinct composite scores."
    return (
        eligible[lowest_index].specimen_id,
        eligible[highest_index].specimen_id,
    ), ""


def _has_complete_triad(metrics: dict[str, float | None]) -> bool:
    triad = ("Strength", "Modulus", "Elongation")
    return all(metrics.get(metric) is not None and pd.notna(metrics.get(metric)) for metric in triad)


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


def infer_group_name(file_paths: Iterable[str | Path]) -> str:
    return tensile_builtin.infer_group_name(file_paths)


def slugify_template_label(label: str) -> str:
    return "".join(ch.lower() if ch.isalnum() else "_" for ch in label).strip("_") or "template"


def _resolve_block(preview: Any, block_id: str | None) -> Any:
    if block_id is None:
        return None
    for sheet in preview.sheets:
        for block in sheet.blocks:
            if block.id == block_id:
                return block
    return None


def _best_candidate(candidates: list[FieldCandidate], kind: str) -> FieldCandidate | None:
    matches = [candidate for candidate in candidates if candidate.kind == kind]
    if not matches:
        return None
    matches.sort(key=lambda item: (-item.confidence, item.label.lower(), item.id))
    return matches[0]


def _binding_from_candidate(candidate: FieldCandidate, *, role: TemplateFieldRole) -> TemplateFieldBinding:
    column_index = candidate.range.start_col if candidate.range is not None else None
    return TemplateFieldBinding(
        id=candidate.id,
        role=role,
        label=candidate.label,
        sheet_name=candidate.sheet_name,
        block_id=candidate.block_id,
        column_name=candidate.label,
        column_index=column_index,
        unit_hint=candidate.unit_hint,
    )


def _binding_by_role(bindings: Iterable[TemplateFieldBinding], role: str) -> TemplateFieldBinding | None:
    for binding in bindings:
        if binding.role == role:
            return binding
    return None


def _resolve_column_index(header_row: list[str], binding: TemplateFieldBinding) -> int | None:
    if binding.column_index is not None and 0 <= binding.column_index < len(header_row):
        return binding.column_index
    if binding.column_name:
        lowered = binding.column_name.lower()
        for index, header in enumerate(header_row):
            if lowered == header.lower() or lowered in header.lower():
                return index
    return None


def _metrics_dataframe(parsed_samples: list[ParsedStructuredSample]) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    metric_units: dict[str, str] = {}
    for sample in parsed_samples:
        row: dict[str, object] = {"Filename": sample["filename"]}
        for label, value in sample["metrics"].items():
            unit = "%" if "elong" in label.lower() else "a.u."
            metric_units[label] = unit
            row[f"{label} ({unit})"] = value
        rows.append(row)
    return pd.DataFrame(rows)


def _representative_index(summary_df: pd.DataFrame) -> int:
    if summary_df.empty:
        return 0
    scores = _representative_scores(summary_df)
    return int(scores.idxmin())


def _metric_summaries(summary_df: pd.DataFrame) -> list[WorkbookMetricSummary]:
    metrics: list[WorkbookMetricSummary] = []
    for column in summary_df.columns:
        if column == "Filename" or "(" not in column or ")" not in column:
            continue
        label, unit = column.rsplit("(", 1)
        unit = unit.rstrip(")")
        series = pd.to_numeric(summary_df[column], errors="coerce").dropna()
        metrics.append(
            WorkbookMetricSummary(
                id=label.strip(),
                label=label.strip(),
                unit=unit.strip(),
                mean=float(series.mean()) if not series.empty else None,
                std=float(series.std(ddof=1)) if len(series.index) > 1 else None,
            )
        )
    return metrics


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


def _looks_like_legacy_tensile_workbook(path: Path) -> bool:
    sheet_names = set(list_sheet_names(path))
    return bool(sheet_names) and tensile_builtin.REQUIRED_TENSILE_WORKBOOK_SHEETS.issubset(sheet_names)


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


def _unit_for_column(unit_row: list[str], column_index: int) -> str:
    if 0 <= column_index < len(unit_row):
        return unit_row[column_index]
    return ""


def _metadata_sheet_dataframe(
    *,
    label: str,
    template_id: str,
    source_files: Iterable[Path],
    warnings: Iterable[str],
    representative_filename: str,
    sample_count: int,
    metric_ids: Iterable[str],
) -> pd.DataFrame:
    return pd.DataFrame(
        [
            ["label", label],
            ["template_id", template_id],
            ["source_files", " | ".join(str(path) for path in source_files)],
            ["warnings", " | ".join(warnings)],
            ["representative_filename", representative_filename],
            ["sample_count", sample_count],
            ["metric_ids", " | ".join(metric_ids)],
        ]
    )


def _curve_table_dataframe(series_pairs: Iterable[tuple[str, pd.DataFrame]]) -> pd.DataFrame:
    return tensile_builtin._curve_table_dataframe(series_pairs)  # noqa: SLF001


def _replicate_table_dataframe(
    *,
    group_name: str,
    value_label: str,
    value_unit: str,
    values: Iterable[float],
) -> pd.DataFrame:
    return tensile_builtin._replicate_table_dataframe(  # noqa: SLF001
        group_name=group_name,
        value_label=value_label,
        value_unit=value_unit,
        values=values,
    )


def _summary_sheet_dataframe(
    summary_df: pd.DataFrame,
    representative_filename: str,
    metrics: list[WorkbookMetricSummary],
) -> pd.DataFrame:
    converted = [
        tensile_builtin.TensileMetricSummary(
            label=metric.label,
            unit=metric.unit,
            mean=metric.mean,
            std=metric.std,
        )
        for metric in metrics
    ]
    return tensile_builtin._summary_sheet_dataframe(summary_df, representative_filename, tuple(converted))  # noqa: SLF001


def _plain_table_dataframe(dataframe: pd.DataFrame) -> pd.DataFrame:
    return tensile_builtin._plain_table_dataframe(dataframe)  # noqa: SLF001


def _cell_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and pd.isna(value):
        return ""
    return str(value).strip()


__all__ = [
    "GENERIC_TEMPLATE_PARSE_STRATEGY",
    "build_workbook",
    "create_template_from_candidates",
    "import_workbook",
    "import_workbooks",
    "parse_structured_sample",
]
