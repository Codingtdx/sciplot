from __future__ import annotations

import csv
from collections.abc import Iterable
from dataclasses import replace
from pathlib import Path
from typing import Any

import pandas as pd

from src.data_studio.models import (
    DataStudioRange,
    FieldCandidate,
    RawFilePreview,
    RawSheetPreview,
    SheetBlock,
    TemplateDefinition,
    TemplateMatch,
)
from src.data_studio.template_store import list_templates

try:
    from charset_normalizer import from_bytes as detect_charset
except Exception:  # pragma: no cover - optional import fallback
    detect_charset = None


TEXT_EXTENSIONS = {".csv", ".txt", ".tsv"}
EXCEL_EXTENSIONS = {".xls", ".xlsx", ".xlsm"}
SUPPORTED_EXTENSIONS = TEXT_EXTENSIONS | EXCEL_EXTENSIONS
FALLBACK_ENCODINGS = (
    "utf-8",
    "utf-8-sig",
    "utf-16",
    "utf-16-le",
    "utf-16-be",
    "gb18030",
    "gbk",
    "gb2312",
    "latin-1",
)
UNIT_TOKENS = {
    "%",
    "mpa",
    "gpa",
    "pa",
    "kpa",
    "s",
    "sec",
    "min",
    "h",
    "n",
    "kn",
    "mm",
    "um",
    "cm",
    "c",
    "°c",
    "k",
}


def _cell_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and pd.isna(value):
        return ""
    return str(value).strip()


def _has_content(value: object) -> bool:
    return _cell_text(value) != ""


def _normalize_token(text: str) -> str:
    return "".join(ch.lower() if ch.isalnum() else " " for ch in text).strip()


def _token_set(text: str) -> set[str]:
    return {token for token in _normalize_token(text).split() if token}


def sniff_text_encoding(raw_bytes: bytes) -> str | None:
    if raw_bytes.startswith(b"\xef\xbb\xbf"):
        return "utf-8-sig"
    if raw_bytes.startswith(b"\xff\xfe") or raw_bytes.startswith(b"\xfe\xff"):
        return "utf-16"
    if detect_charset is not None:
        match = detect_charset(raw_bytes).best()
        if match is not None and match.encoding:
            return match.encoding
    for encoding in FALLBACK_ENCODINGS:
        try:
            raw_bytes.decode(encoding)
            return encoding
        except UnicodeDecodeError:
            continue
    return None


def sniff_delimiter(text: str, suffix: str) -> str | None:
    if suffix == ".tsv":
        return "\t"
    sample = "\n".join(text.splitlines()[:12])
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",\t;|")
        return dialect.delimiter
    except csv.Error:
        return "," if suffix == ".csv" else None


def _read_text_frame(path: Path) -> tuple[pd.DataFrame, str | None, str | None]:
    raw_bytes = path.read_bytes()
    encoding = sniff_text_encoding(raw_bytes)
    if encoding is None:
        raise ValueError(f"Could not decode {path.name} with the common experiment encodings.")
    text = raw_bytes.decode(encoding, errors="replace")
    delimiter = sniff_delimiter(text, path.suffix.lower())
    lines = text.splitlines()
    if delimiter is None:
        sample = "\n".join(lines[:12])
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=",\t;|")
            reader = csv.reader(lines, dialect=dialect)
            delimiter = dialect.delimiter
        except csv.Error:
            reader = csv.reader(lines)
            delimiter = ","
    else:
        reader = csv.reader(lines, delimiter=delimiter)
    rows = list(reader)
    width = max((len(row) for row in rows), default=0)
    padded_rows = [row + [""] * (width - len(row)) for row in rows]
    frame = pd.DataFrame(padded_rows)
    return frame.fillna(""), encoding, delimiter


def _read_excel_sheets(path: Path) -> tuple[list[tuple[str, pd.DataFrame]], None, None]:
    with pd.ExcelFile(path) as workbook:
        sheets = [
            (str(sheet_name), pd.read_excel(workbook, sheet_name=sheet_name, header=None).fillna(""))
            for sheet_name in workbook.sheet_names
        ]
    return sheets, None, None


def read_preview_source(path: str | Path) -> tuple[list[tuple[str, pd.DataFrame]], str | None, str | None]:
    source_path = Path(path).expanduser()
    suffix = source_path.suffix.lower()
    if suffix not in SUPPORTED_EXTENSIONS:
        raise ValueError(f"Unsupported Data Studio input type: {suffix}")
    if suffix in TEXT_EXTENSIONS:
        frame, encoding, delimiter = _read_text_frame(source_path)
        return [("Sheet1", frame)], encoding, delimiter
    return _read_excel_sheets(source_path)


def _contiguous_runs(indices: Iterable[int]) -> list[tuple[int, int]]:
    sorted_indices = sorted(set(indices))
    if not sorted_indices:
        return []
    runs: list[tuple[int, int]] = []
    start = sorted_indices[0]
    end = start
    for index in sorted_indices[1:]:
        if index == end + 1:
            end = index
            continue
        runs.append((start, end))
        start = index
        end = index
    runs.append((start, end))
    return runs


def detect_sheet_blocks(sheet_name: str, frame: pd.DataFrame) -> tuple[SheetBlock, ...]:
    non_empty_rows = [
        row_index
        for row_index in range(frame.shape[0])
        if any(_has_content(value) for value in frame.iloc[row_index].tolist())
    ]
    blocks: list[SheetBlock] = []
    for block_index, (row_start, row_end) in enumerate(_contiguous_runs(non_empty_rows), start=1):
        slice_frame = frame.iloc[row_start : row_end + 1].reset_index(drop=True)
        active_cols = [
            col_index
            for col_index in range(slice_frame.shape[1])
            if any(_has_content(value) for value in slice_frame.iloc[:, col_index].tolist())
        ]
        for col_run_index, (col_start, col_end) in enumerate(_contiguous_runs(active_cols), start=1):
            block_frame = slice_frame.iloc[:, col_start : col_end + 1].reset_index(drop=True)
            header_row_index = detect_header_row(block_frame)
            unit_row_index = detect_unit_row(block_frame, header_row_index)
            data_start = detect_data_start_row(block_frame, header_row_index, unit_row_index)
            sample_rows = tuple(tuple(value for value in row) for row in block_frame.head(8).itertuples(index=False))
            blocks.append(
                SheetBlock(
                    id=f"{sheet_name}::block{block_index}_{col_run_index}",
                    sheet_name=sheet_name,
                    label=f"{sheet_name} block {block_index}.{col_run_index}",
                    row_count=block_frame.shape[0],
                    col_count=block_frame.shape[1],
                    range=DataStudioRange(
                        sheet_name=sheet_name,
                        start_row=row_start,
                        end_row=row_end,
                        start_col=col_start,
                        end_col=col_end,
                    ),
                    header_row_index=header_row_index,
                    unit_row_index=unit_row_index,
                    data_start_row_index=data_start,
                    sample_rows=sample_rows,
                )
            )
    return tuple(blocks)


def detect_header_row(frame: pd.DataFrame) -> int | None:
    candidates: list[tuple[float, int]] = []
    for row_index in range(min(frame.shape[0], 6)):
        row = [_cell_text(value) for value in frame.iloc[row_index].tolist()]
        if not any(row):
            continue
        non_empty_count = sum(1 for value in row if value)
        text_count = sum(1 for value in row if value and not _looks_numeric(value))
        numeric_count = sum(1 for value in row if _looks_numeric(value))
        unit_like_count = sum(
            1
            for value in row
            if value.lower() in UNIT_TOKENS or value.startswith("(") or value.endswith(")")
        )
        score = text_count - numeric_count * 0.5 - unit_like_count * 0.85
        if non_empty_count >= 2:
            score += 0.25
        if non_empty_count == 1:
            score -= 1.0
        if score > 0:
            candidates.append((score, row_index))
    if not candidates:
        return None
    candidates.sort(key=lambda item: (-item[0], item[1]))
    return candidates[0][1]


def detect_unit_row(frame: pd.DataFrame, header_row_index: int | None) -> int | None:
    if header_row_index is None:
        return None
    next_index = header_row_index + 1
    if next_index >= frame.shape[0]:
        return None
    row = [_cell_text(value).lower() for value in frame.iloc[next_index].tolist()]
    unit_like = sum(1 for value in row if value in UNIT_TOKENS or value.startswith("(") or value.endswith(")"))
    return next_index if unit_like > 0 else None


def detect_data_start_row(
    frame: pd.DataFrame,
    header_row_index: int | None,
    unit_row_index: int | None,
) -> int | None:
    start = 0
    if unit_row_index is not None:
        start = unit_row_index + 1
    elif header_row_index is not None:
        start = header_row_index + 1
    for row_index in range(start, frame.shape[0]):
        numeric_count = sum(1 for value in frame.iloc[row_index].tolist() if _looks_numeric(_cell_text(value)))
        if numeric_count >= 2:
            return row_index
    return None


def _looks_numeric(value: str) -> bool:
    try:
        float(value)
    except ValueError:
        return False
    return True


def infer_field_candidates(sheet_name: str, frame: pd.DataFrame, block: SheetBlock) -> list[FieldCandidate]:
    block_frame = frame.iloc[
        block.range.start_row : block.range.end_row + 1,
        block.range.start_col : block.range.end_col + 1,
    ].reset_index(drop=True)
    header_row = (
        [_cell_text(value) for value in block_frame.iloc[block.header_row_index].tolist()]
        if block.header_row_index is not None
        else []
    )
    unit_row = (
        [_cell_text(value) for value in block_frame.iloc[block.unit_row_index].tolist()]
        if block.unit_row_index is not None
        else []
    )
    candidates: list[FieldCandidate] = []
    for local_index, header in enumerate(header_row):
        tokens = _token_set(header)
        unit_hint = unit_row[local_index] if local_index < len(unit_row) and unit_row[local_index] else None
        range_payload = DataStudioRange(
            sheet_name=sheet_name,
            start_row=block.range.start_row,
            end_row=block.range.end_row,
            start_col=block.range.start_col + local_index,
            end_col=block.range.start_col + local_index,
        )
        sample_values = tuple(
            _cell_text(value)
            for value in block_frame.iloc[(block.data_start_row_index or 0) : (block.data_start_row_index or 0) + 5, local_index]
            .tolist()
            if _cell_text(value)
        )
        for kind, keywords, confidence, rationale in (
            ("curve_x", {"strain", "time", "temperature", "frequency", "wavenumber", "chemical", "shift"}, 0.88, "Header looks like an X-axis field."),
            ("curve_y", {"stress", "force", "load", "modulus", "intensity", "signal"}, 0.88, "Header looks like a Y-axis field."),
            ("metric", {"strength", "modulus", "elongation", "break"}, 0.84, "Header looks like a group metric."),
            ("metadata", {"sample", "name", "batch", "group", "specimen", "id"}, 0.76, "Header looks like metadata."),
        ):
            if tokens & keywords:
                candidates.append(
                    FieldCandidate(
                        id=f"{block.id}::{kind}_{local_index}",
                        kind=kind,
                        label=header or f"Column {local_index + 1}",
                        confidence=confidence,
                        rationale=rationale,
                        sheet_name=sheet_name,
                        block_id=block.id,
                        range=range_payload,
                        sample_values=sample_values,
                        unit_hint=unit_hint,
                    )
                )
        if header:
            candidates.append(
                FieldCandidate(
                    id=f"{block.id}::header_{local_index}",
                    kind="header",
                    label=header,
                    confidence=0.55,
                    rationale="Column is available for manual template binding.",
                    sheet_name=sheet_name,
                    block_id=block.id,
                    range=range_payload,
                    sample_values=sample_values,
                    unit_hint=unit_hint,
                )
            )

    if block.header_row_index is not None:
        candidates.append(
            FieldCandidate(
                id=f"{block.id}::header_row",
                kind="header_row",
                label=f"{sheet_name} header row",
                confidence=0.7,
                rationale="Likely header row for this data block.",
                sheet_name=sheet_name,
                block_id=block.id,
                range=DataStudioRange(
                    sheet_name=sheet_name,
                    start_row=block.range.start_row + block.header_row_index,
                    end_row=block.range.start_row + block.header_row_index,
                    start_col=block.range.start_col,
                    end_col=block.range.end_col,
                ),
            )
        )
    if block.unit_row_index is not None:
        candidates.append(
            FieldCandidate(
                id=f"{block.id}::unit_row",
                kind="unit_row",
                label=f"{sheet_name} unit row",
                confidence=0.64,
                rationale="Likely unit row for this data block.",
                sheet_name=sheet_name,
                block_id=block.id,
                range=DataStudioRange(
                    sheet_name=sheet_name,
                    start_row=block.range.start_row + block.unit_row_index,
                    end_row=block.range.start_row + block.unit_row_index,
                    start_col=block.range.start_col,
                    end_col=block.range.end_col,
                ),
            )
        )
    return candidates


def match_template(preview: RawFilePreview, template: TemplateDefinition) -> TemplateMatch | None:
    reasons: list[str] = []
    matched_sheets: list[str] = []
    score = 0.0
    preview_text = " ".join(
        _cell_text(value)
        for sheet in preview.sheets
        for row in sheet.sample_rows
        for value in row
        if _cell_text(value)
    ).lower()
    candidate_kinds = {candidate.kind for candidate in preview.field_candidates}
    file_suffix = preview.source_path.suffix.lower().lstrip(".")
    if template.file_types and file_suffix not in {item.lower() for item in template.file_types}:
        return None
    for condition in template.match_conditions:
        condition_score = 0.0
        if condition.sheet_name_contains:
            sheet_hits = [
                sheet.sheet_name
                for sheet in preview.sheets
                if any(keyword.lower() in sheet.sheet_name.lower() for keyword in condition.sheet_name_contains)
            ]
            if sheet_hits:
                condition_score += 0.25
                matched_sheets.extend(sheet_hits)
                reasons.append(f"Matched sheet hint: {', '.join(sorted(set(sheet_hits)))}.")
        if condition.text_contains:
            text_hits = [keyword for keyword in condition.text_contains if keyword.lower() in preview_text]
            if text_hits:
                condition_score += 0.45
                reasons.append(f"Matched text hints: {', '.join(text_hits[:4])}.")
        if condition.field_kinds:
            field_hits = [kind for kind in condition.field_kinds if kind in candidate_kinds]
            if field_hits:
                condition_score += 0.3
                reasons.append(f"Matched field candidates: {', '.join(field_hits)}.")
        score += condition_score
    if not template.match_conditions:
        score = 0.1
    if score <= 0:
        return None
    confidence = min(0.99, max(score, 0.1))
    minimum_score = max((condition.minimum_score for condition in template.match_conditions), default=0.0)
    if confidence < minimum_score:
        return None
    return TemplateMatch(
        template_id=template.id,
        label=template.label,
        family=template.family,
        confidence=confidence,
        reasons=tuple(dict.fromkeys(reasons)),
        matched_sheet_names=tuple(dict.fromkeys(matched_sheets)),
        auto_selected=confidence >= 0.75,
    )


def recommend_templates_for_preview(preview: RawFilePreview) -> tuple[TemplateMatch, ...]:
    matches = [match for template in list_templates() if (match := match_template(preview, template)) is not None]
    matches.sort(key=lambda item: (-item.confidence, item.label.lower(), item.template_id))
    return tuple(matches)


def preview_raw_file(path: str | Path) -> RawFilePreview:
    source_path = Path(path).expanduser()
    sheets, encoding, delimiter = read_preview_source(source_path)
    sheet_previews: list[RawSheetPreview] = []
    field_candidates: list[FieldCandidate] = []
    for sheet_name, frame in sheets:
        blocks = detect_sheet_blocks(sheet_name, frame)
        sheet_previews.append(
            RawSheetPreview(
                sheet_name=sheet_name,
                row_count=frame.shape[0],
                col_count=frame.shape[1],
                sample_rows=tuple(tuple(value for value in row) for row in frame.head(12).itertuples(index=False)),
                blocks=blocks,
            )
        )
        for block in blocks:
            field_candidates.extend(infer_field_candidates(sheet_name, frame, block))
    preview = RawFilePreview(
        source_path=source_path,
        file_type=source_path.suffix.lower().lstrip("."),
        encoding=encoding,
        delimiter=delimiter,
        sheet_names=tuple(sheet.sheet_name for sheet in sheet_previews),
        sheets=tuple(sheet_previews),
        field_candidates=tuple(field_candidates),
    )
    recommendations = recommend_templates_for_preview(preview)
    return replace(preview, recommended_template_ids=tuple(match.template_id for match in recommendations[:5]))


def preview_and_recommend(path: str | Path) -> tuple[RawFilePreview, tuple[TemplateMatch, ...]]:
    preview = preview_raw_file(path)
    return preview, recommend_templates_for_preview(preview)


__all__ = [
    "SUPPORTED_EXTENSIONS",
    "detect_data_start_row",
    "detect_header_row",
    "detect_sheet_blocks",
    "infer_field_candidates",
    "match_template",
    "preview_and_recommend",
    "preview_raw_file",
    "read_preview_source",
    "recommend_templates_for_preview",
    "sniff_delimiter",
    "sniff_text_encoding",
]
