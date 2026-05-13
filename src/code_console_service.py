from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import textwrap
import time
from dataclasses import asdict, dataclass, is_dataclass
from pathlib import Path
from typing import Any

import pandas as pd

from src.code_console_runner import DEFAULT_RUNNER_MANAGER
from src.infrastructure.persistence.code_console_runs import prepare_managed_code_console_run_dir
from src.infrastructure.runtime_cache import LRUCache
from src.plot_contract import template_contract
from src.rendering.cache import read_raw_table_cached
from src.rendering.dataset_models import (
    build_normalized_dataset,
    dataframe_sample_rows,
    normalized_dataset_payload,
)
from src.rendering.io import coerce_sheet, list_sheet_names
from src.rendering.options import resolve_render_options, validate_template_name
from src.rendering.recommendation import inspect_input_file
from src.text_normalization import slugify_label

REPO_ROOT = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class CodeConsoleResolvedContext:
    context_id: str
    input_path: Path
    input_mtime_ns: int
    sheet: str | int
    sheet_names: tuple[str, ...]
    inspection: dict[str, Any]
    dataset: dict[str, Any] | None
    template: str
    options: dict[str, Any]
    prompt_text: str
    starter_code: str
    source_kind: str | None = None
    source_label: str | None = None


_CONTEXT_BY_ID_CACHE = LRUCache[str, CodeConsoleResolvedContext](maxsize=128)
_CONTEXT_REQUEST_KEY_CACHE = LRUCache[str, str](maxsize=128)


@dataclass(frozen=True)
class CodeConsoleGeneratedFile:
    path: Path
    name: str
    file_type: str
    size_bytes: int


@dataclass(frozen=True)
class CodeConsoleRunResult:
    status: str
    exit_code: int | None
    duration_seconds: float
    stdout: str
    stderr: str
    run_dir: Path
    output_dir: Path
    script_path: Path
    prompt_path: Path
    context_path: Path
    stdout_path: Path
    stderr_path: Path
    generated_files: tuple[CodeConsoleGeneratedFile, ...]


def _stable_json_hash(payload: object) -> str:
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _context_request_cache_key(
    *,
    input_path: Path,
    sheet: str | int,
    template: str | None,
    size: str | None,
    style_preset: str | None,
    palette_preset: str | None,
    visual_theme_id: str | None,
    source_kind: str | None,
    source_label: str | None,
) -> str:
    return _stable_json_hash(
        {
            "input_path": str(input_path.resolve()),
            "input_mtime_ns": input_path.stat().st_mtime_ns,
            "sheet": str(sheet),
            "template": template,
            "size": size,
            "style_preset": style_preset,
            "palette_preset": palette_preset,
            "visual_theme_id": visual_theme_id,
            "source_kind": source_kind,
            "source_label": source_label,
        }
    )


def _context_id_for_payload(payload: dict[str, object]) -> str:
    return f"ctx_{_stable_json_hash(payload)[:24]}"


def _context_id_for_context(
    *,
    input_path: Path,
    input_mtime_ns: int,
    sheet: str | int,
    template: str,
    options: dict[str, Any],
    source_kind: str | None,
    source_label: str | None,
) -> str:
    return _context_id_for_payload(
        {
            "input_path": str(input_path.resolve()),
            "input_mtime_ns": input_mtime_ns,
            "sheet": str(sheet),
            "template": template,
            "options": options,
            "source_kind": source_kind,
            "source_label": source_label,
        }
    )


def _context_is_fresh(context: CodeConsoleResolvedContext) -> bool:
    try:
        return (
            context.input_path.exists()
            and context.input_path.stat().st_mtime_ns == context.input_mtime_ns
        )
    except Exception:
        return False


def _cached_context_by_id(context_id: str) -> CodeConsoleResolvedContext | None:
    cached = _CONTEXT_BY_ID_CACHE.get(context_id)
    if cached is None:
        return None
    if not _context_is_fresh(cached):
        return None
    return cached


def _cache_context(context: CodeConsoleResolvedContext, *, request_key: str | None = None) -> None:
    _CONTEXT_BY_ID_CACHE.set(context.context_id, context)
    if request_key:
        _CONTEXT_REQUEST_KEY_CACHE.set(request_key, context.context_id)


def _json_ready(value: Any) -> Any:
    if is_dataclass(value) and not isinstance(value, type):
        return {key: _json_ready(item) for key, item in asdict(value).items()}
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, dict):
        return {key: _json_ready(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_ready(item) for item in value]
    return value


def _truncate_cell(value: object, *, max_chars: int = 48) -> object:
    text = str(value)
    if len(text) <= max_chars:
        return value
    return f"{text[: max_chars - 1]}…"


def _safe_sample_rows(
    dataset: dict[str, Any] | None,
    *,
    limit_rows: int = 6,
    limit_cols: int = 8,
) -> list[list[object]]:
    if not dataset:
        return []
    sample_rows = dataset.get("sample_rows", [])
    safe_rows: list[list[object]] = []
    for row in sample_rows[:limit_rows]:
        if not isinstance(row, list):
            continue
        safe_rows.append([_truncate_cell(item) for item in row[:limit_cols]])
    return safe_rows


def _safe_column_profiles(
    dataset: dict[str, Any] | None,
    *,
    limit_cols: int = 12,
) -> list[dict[str, object]]:
    if not dataset:
        return []
    profiles = dataset.get("column_profiles", [])
    safe_profiles: list[dict[str, object]] = []
    for profile in profiles[:limit_cols]:
        if not isinstance(profile, dict):
            continue
        safe_profiles.append(
            {
                "name": profile.get("name"),
                "inferred_type": profile.get("inferred_type"),
                "non_empty_count": profile.get("non_empty_count"),
                "missing_count": profile.get("missing_count"),
                "min_value": profile.get("min_value"),
                "max_value": profile.get("max_value"),
                "header_preview": profile.get("header_preview", []),
            }
        )
    return safe_profiles


def _ranked_template_hint(inspection: dict[str, Any]) -> str:
    recommendations = inspection.get("recommendations", [])
    if isinstance(recommendations, list) and recommendations:
        lines = ["Ranked template candidates:"]
        for index, item in enumerate(recommendations[:5], start=1):
            if not isinstance(item, dict):
                continue
            template_id = item.get("template_id")
            if not template_id:
                continue
            score = item.get("score")
            reason = str(item.get("reason") or item.get("suitability_hint") or "").strip()
            score_fragment = f" score={score}" if score is not None else ""
            reason_fragment = f" — {reason}" if reason else ""
            lines.append(f"{index}. {template_id}{score_fragment}{reason_fragment}")
        if len(lines) > 1:
            return "\n".join(lines)

    if inspection.get("model") == "raw_table":
        return (
            "Raw table fallback: no Plot template recommendation was available. "
            "Use the column profiles and sample rows to write a custom figure."
        )
    return "No ranked template candidates are available for this context."


def _cell_to_prompt_value(value: object) -> object:
    if value is None:
        return None
    if hasattr(value, "item") and not isinstance(value, (str, bytes)):
        try:
            value = value.item()
        except Exception:
            pass
    try:
        if bool(pd.isna(value)):
            return None
    except Exception:
        pass
    return value


def _string_or_none(value: object) -> str | None:
    value = _cell_to_prompt_value(value)
    if value is None:
        return None
    cleaned = str(value).strip()
    return cleaned or None


def _numeric_or_none(value: object) -> float | int | None:
    value = _cell_to_prompt_value(value)
    if value is None:
        return None
    try:
        numeric = float(str(value))
    except (TypeError, ValueError):
        return None
    if pd.isna(numeric):
        return None
    return int(numeric) if numeric.is_integer() else round(numeric, 6)


def _raw_table_column_name(raw: pd.DataFrame, index: int) -> str:
    preview = [
        _string_or_none(raw.iloc[row_index, index])
        for row_index in range(min(3, raw.shape[0]))
    ]
    labels = [value for value in preview if value]
    return " | ".join(labels) if labels else f"Column {index + 1}"


def _raw_table_column_profiles(raw: pd.DataFrame, *, limit: int = 24) -> list[dict[str, object]]:
    profiles: list[dict[str, object]] = []
    for index in range(min(raw.shape[1], limit)):
        series = raw.iloc[:, index]
        numeric = pd.to_numeric(series, errors="coerce")
        non_empty = sum(_string_or_none(value) is not None for value in series.tolist())
        missing = int(len(series) - non_empty)
        numeric_values = numeric.dropna()
        if numeric_values.empty:
            inferred_type = "text"
            min_value = None
            max_value = None
        elif numeric_values.shape[0] == non_empty:
            inferred_type = "numeric"
            min_value = _numeric_or_none(numeric_values.min())
            max_value = _numeric_or_none(numeric_values.max())
        else:
            inferred_type = "mixed"
            min_value = _numeric_or_none(numeric_values.min())
            max_value = _numeric_or_none(numeric_values.max())
        profiles.append(
            {
                "name": _raw_table_column_name(raw, index),
                "header_preview": [
                    _string_or_none(raw.iloc[row_index, index])
                    for row_index in range(min(3, raw.shape[0]))
                ],
                "inferred_type": inferred_type,
                "non_empty_count": int(non_empty),
                "missing_count": missing,
                "min_value": min_value,
                "max_value": max_value,
            }
        )
    return profiles


def _raw_table_candidate_roles(profiles: list[dict[str, object]]) -> dict[str, list[str]]:
    labels = [str(profile["name"]) for profile in profiles if profile.get("name")]
    numeric = [
        str(profile["name"])
        for profile in profiles
        if profile.get("name") and profile.get("inferred_type") in {"numeric", "mixed"}
    ]
    return {
        "x": [],
        "y": [],
        "z": [],
        "group": [],
        "sample": [],
        "value": numeric,
        "metric": [],
        "label": labels,
        "series": [],
    }


def _raw_table_dataset_payload(input_path: Path, sheet: str | int, raw: pd.DataFrame) -> dict[str, Any]:
    working_raw = raw.dropna(axis=1, how="all")
    profiles = _raw_table_column_profiles(working_raw)
    dataset_hash = _stable_json_hash(
        {
            "input_path": str(input_path),
            "input_mtime_ns": input_path.stat().st_mtime_ns,
            "sheet": str(sheet),
            "raw_rows": int(raw.shape[0]),
            "raw_cols": int(raw.shape[1]),
        }
    )
    dataset_id = f"raw_{dataset_hash[:16]}"
    quality_flags: list[str] = []
    if working_raw.shape[1] != raw.shape[1]:
        quality_flags.append("empty_columns_dropped")
    if any(profile.get("inferred_type") == "mixed" for profile in profiles[:8]):
        quality_flags.append("type_ambiguity")
    quality_flags.append("code_console_raw_table_fallback")
    return {
        "dataset_id": dataset_id,
        "source_path": str(input_path),
        "sheet": sheet,
        "model": "raw_table",
        "raw_rows": int(raw.shape[0]),
        "raw_cols": int(raw.shape[1]),
        "column_profiles": profiles,
        "candidate_roles": _raw_table_candidate_roles(profiles),
        "data_shapes": ["table"],
        "semantic_signals": [
            "Raw table fallback: standard Plot inspection did not recognize this table.",
            "The Code Console can still load the raw dataframe for custom Python plotting.",
            "Use column profiles and sample rows to decide how to parse or reshape the data.",
        ],
        "quality_flags": quality_flags,
        "sample_rows": dataframe_sample_rows(raw),
    }


def _raw_table_inspection_payload() -> dict[str, Any]:
    return {
        "model": "raw_table",
        "model_label": "Raw table (Code Console fallback)",
        "recommendations": [],
        "primary_recommendation": [],
        "alternative_recommendations": [],
        "advanced_templates": [],
        "recommendation_confidence": 0.0,
        "recommendation_summary": (
            "Code Console raw-table fallback is active because Plot inspection did not "
            "produce a supported template recommendation."
        ),
        "warnings": [
            "This dataset has no automatic Plot template recommendation; "
            "external AI code must choose the plotting semantics."
        ],
        "signals": [
            "Raw table fallback keeps the dataset available for custom Python code.",
        ],
    }


def _first_recommendation_payload(inspection: dict[str, Any]) -> dict[str, Any] | None:
    for key in ("recommendations", "primary_recommendation"):
        items = inspection.get(key, [])
        if not isinstance(items, list):
            continue
        for item in items:
            if isinstance(item, dict) and item.get("template_id"):
                return item
    return None


def _build_prompt(
    *,
    context: CodeConsoleResolvedContext,
) -> str:
    dataset = context.dataset or {}
    prompt_payload = {
        "input_path": str(context.input_path),
        "sheet": context.sheet,
        "sheet_names": list(context.sheet_names),
        "model": context.inspection.get("model"),
        "model_label": context.inspection.get("model_label"),
        "recommended_template": context.template,
        "style_preset": context.options["style_preset"],
        "palette_preset": context.options["palette_preset"],
        "size": context.options["size"],
        "visual_theme_id": context.options.get("visual_theme_id"),
        "raw_rows": dataset.get("raw_rows"),
        "raw_cols": dataset.get("raw_cols"),
        "data_shapes": dataset.get("data_shapes", []),
        "semantic_signals": dataset.get("semantic_signals", []),
        "quality_flags": dataset.get("quality_flags", []),
        "column_profiles": _safe_column_profiles(dataset),
        "candidate_roles": dataset.get("candidate_roles", {}),
        "sample_rows": _safe_sample_rows(dataset),
    }
    source_line = (
        f"- Bound source: {context.source_label} ({context.source_kind}).\n"
        if context.source_label and context.source_kind
        else ""
    )
    return textwrap.dedent(
        f"""
        Write one Python script for the SciPlot Code Console.

        Requirements:
        - Return Python code only. Do not wrap the answer in markdown fences.
        - The script will run with the repo root as the working directory.
        - Read the already selected dataset at `{context.input_path}` and sheet `{context.sheet}`.
        - Use repo-native helpers so the figure keeps SciPlot styling.
        - Treat the user's separate figure description as the custom plotting request.
        - External AI should handle fitting / derived analysis / custom overlays, not restyle the whole figure system.
        - Save every generated file inside `OUTPUT_DIR` only.
        - Do not write files outside `OUTPUT_DIR`; use `console.output_path(...)` helpers when needed.
        - Print a short textual summary of what the script generated.

        Use this helper API:
        ```python
        from src.code_console_runtime import console

        df = console.load_raw_dataframe()
        normalized = console.load_normalized_dataset_payload()
        fig, ax = console.new_figure()
        console.save_figure(fig, "result_name")
        console.write_dataframe(df, "derived_table.csv", index=False)
        ```

        Styling target:
        - Style preset: `{context.options["style_preset"]}`
        - Palette preset: `{context.options["palette_preset"]}`
        - Size preset: `{context.options["size"]}`
        - Visual theme: `{context.options.get("visual_theme_id") or "none"}`

        {_ranked_template_hint(context.inspection)}

        {source_line}Context snapshot:
        ```json
        {json.dumps(prompt_payload, ensure_ascii=False, indent=2)}
        ```
        """
    ).strip()


def _build_starter_code(*, context: CodeConsoleResolvedContext) -> str:
    output_stem = slugify_label(context.input_path.stem) or "code_console_output"
    title = json.dumps(str(context.inspection.get("model_label") or "Code Console"))
    return textwrap.dedent(
        f"""
        from src.code_console_runtime import console
        import pandas as pd

        df = console.load_raw_dataframe()
        normalized = console.load_normalized_dataset_payload()
        profiles = normalized.get("column_profiles", [])

        def column_label(column):
            columns = list(df.columns)
            try:
                index = columns.index(column)
            except ValueError:
                try:
                    index = int(column)
                except (TypeError, ValueError):
                    index = -1
            if 0 <= index < len(profiles):
                return str(profiles[index].get("name") or f"Column {{index + 1}}")
            return str(column)

        profile_rows = [
            {{
                "column": item.get("name"),
                "inferred_type": item.get("inferred_type"),
                "non_empty_count": item.get("non_empty_count"),
                "missing_count": item.get("missing_count"),
                "min_value": item.get("min_value"),
                "max_value": item.get("max_value"),
            }}
            for item in profiles
            if isinstance(item, dict)
        ]
        profile_frame = pd.DataFrame(profile_rows)

        fig, ax = console.new_figure()
        numeric_frame = df.apply(pd.to_numeric, errors="coerce")
        numeric_columns = [
            column
            for column in numeric_frame.columns
            if numeric_frame[column].dropna().shape[0] >= 2
        ]

        plotted = 0
        if len(numeric_columns) >= 2:
            if len(numeric_columns) % 2 == 0:
                pairs = list(zip(numeric_columns[0::2], numeric_columns[1::2]))
            else:
                pairs = [(numeric_columns[0], column) for column in numeric_columns[1:]]
            first_x = None
            for x_column, y_column in pairs[:4]:
                x_values = numeric_frame[x_column]
                y_values = numeric_frame[y_column]
                mask = x_values.notna() & y_values.notna()
                if int(mask.sum()) < 2:
                    continue
                ax.plot(
                    x_values[mask],
                    y_values[mask],
                    marker="o",
                    linewidth=1.2,
                    label=column_label(y_column),
                )
                first_x = first_x if first_x is not None else x_column
                plotted += 1
            ax.set_xlabel(column_label(first_x if first_x is not None else numeric_columns[0]))
            ax.set_ylabel("Value")
            if plotted > 1:
                ax.legend(frameon=False)
        elif profile_rows:
            compact = profile_frame.head(8)
            ax.bar(
                range(len(compact)),
                compact["non_empty_count"].fillna(0),
            )
            ax.set_xticks(range(len(compact)))
            ax.set_xticklabels(compact["column"].fillna("Column"), rotation=45, ha="right")
            ax.set_ylabel("Non-empty cells")
            plotted = len(compact)
        else:
            ax.text(0.5, 0.5, "No plottable columns detected", ha="center", va="center")
            ax.set_axis_off()

        ax.set_title({title})

        console.save_figure(fig, "{output_stem}")
        console.write_dataframe(profile_frame, "{output_stem}_data_profile.csv", index=False)
        console.write_json(normalized, "{output_stem}_normalized_dataset.json")

        print(f"Plotted {{plotted}} series from {{len(df)}} raw rows; outputs saved to {{console.output_dir}}")
        """
    ).strip()


def _build_code_console_context_uncached(
    *,
    input_path: Path,
    sheet: str | int,
    template: str | None,
    size: str | None,
    style_preset: str | None,
    palette_preset: str | None,
    visual_theme_id: str | None,
    source_kind: str | None = None,
    source_label: str | None = None,
) -> CodeConsoleResolvedContext:
    resolved_input_path = input_path.expanduser().resolve()
    resolved_sheet = coerce_sheet(str(sheet))
    try:
        inspection = inspect_input_file(resolved_input_path, resolved_sheet)
        normalized_dataset = build_normalized_dataset(
            resolved_input_path,
            resolved_sheet,
            model=inspection.model,
        )
        raw = read_raw_table_cached(resolved_input_path, resolved_sheet).dropna(axis=1, how="all")
        dataset_payload = {
            **normalized_dataset_payload(normalized_dataset),
            "sample_rows": dataframe_sample_rows(raw),
        }
        inspection_payload = _json_ready(inspection)
        fallback_template = None
    except Exception as inspection_error:
        try:
            raw = read_raw_table_cached(resolved_input_path, resolved_sheet)
        except Exception as raw_error:
            raise inspection_error from raw_error
        inspection_payload = _raw_table_inspection_payload()
        dataset_payload = _raw_table_dataset_payload(resolved_input_path, resolved_sheet, raw)
        fallback_template = "table_figure"

    top_recommendation = _first_recommendation_payload(inspection_payload)
    recommended_size = (
        top_recommendation.get("preview_config_summary", {}).get("size")
        if top_recommendation is not None
        else None
    )
    resolved_template = validate_template_name(
        template
        or (str(top_recommendation["template_id"]) if top_recommendation is not None else None)
        or fallback_template
        or "table_figure"
    )
    resolved_render_options = resolve_render_options(
        template=resolved_template,
        size=size or (str(recommended_size) if recommended_size is not None else None),
        style_preset=style_preset,
        palette_preset=palette_preset,
        visual_theme_id=visual_theme_id,
    )
    input_mtime_ns = resolved_input_path.stat().st_mtime_ns
    options = {
        "size": size
        or (
            str(recommended_size)
            if recommended_size is not None
            else template_contract(resolved_template).default_size
        ),
        "width_mm": resolved_render_options.width_mm,
        "height_mm": resolved_render_options.height_mm,
        "style_preset": resolved_render_options.style_preset,
        "palette_preset": resolved_render_options.palette_preset,
        "visual_theme_id": resolved_render_options.visual_theme_id,
    }
    context_id = _context_id_for_context(
        input_path=resolved_input_path,
        input_mtime_ns=input_mtime_ns,
        sheet=resolved_sheet,
        template=resolved_template,
        options=options,
        source_kind=source_kind,
        source_label=source_label,
    )
    context = CodeConsoleResolvedContext(
        context_id=context_id,
        input_path=resolved_input_path,
        input_mtime_ns=input_mtime_ns,
        sheet=resolved_sheet,
        sheet_names=tuple(list_sheet_names(resolved_input_path)),
        inspection=inspection_payload,
        dataset=_json_ready(dataset_payload),
        template=resolved_template,
        options=options,
        prompt_text="",
        starter_code="",
        source_kind=source_kind,
        source_label=source_label,
    )
    prompt_text = _build_prompt(context=context)
    starter_code = _build_starter_code(context=context)
    return CodeConsoleResolvedContext(
        context_id=context.context_id,
        input_path=context.input_path,
        input_mtime_ns=context.input_mtime_ns,
        sheet=context.sheet,
        sheet_names=context.sheet_names,
        inspection=context.inspection,
        dataset=context.dataset,
        template=context.template,
        options=context.options,
        prompt_text=prompt_text,
        starter_code=starter_code,
        source_kind=context.source_kind,
        source_label=context.source_label,
    )


def build_code_console_context(
    *,
    input_path: Path,
    sheet: str | int,
    template: str | None,
    size: str | None,
    style_preset: str | None,
    palette_preset: str | None,
    visual_theme_id: str | None,
    source_kind: str | None = None,
    source_label: str | None = None,
) -> CodeConsoleResolvedContext:
    resolved_input_path = input_path.expanduser().resolve()
    resolved_sheet = coerce_sheet(str(sheet))
    request_key = _context_request_cache_key(
        input_path=resolved_input_path,
        sheet=resolved_sheet,
        template=template,
        size=size,
        style_preset=style_preset,
        palette_preset=palette_preset,
        visual_theme_id=visual_theme_id,
        source_kind=source_kind,
        source_label=source_label,
    )
    cached_context_id = _CONTEXT_REQUEST_KEY_CACHE.get(request_key)
    if cached_context_id is not None:
        cached_context = _cached_context_by_id(cached_context_id)
        if cached_context is not None:
            return cached_context
    context = _build_code_console_context_uncached(
        input_path=resolved_input_path,
        sheet=resolved_sheet,
        template=template,
        size=size,
        style_preset=style_preset,
        palette_preset=palette_preset,
        visual_theme_id=visual_theme_id,
        source_kind=source_kind,
        source_label=source_label,
    )
    _cache_context(context, request_key=request_key)
    return context


def resolve_code_console_context(
    *,
    context_id: str | None,
    input_path: Path | None = None,
    sheet: str | int | None = None,
    template: str | None = None,
    size: str | None = None,
    style_preset: str | None = None,
    palette_preset: str | None = None,
    visual_theme_id: str | None = None,
    source_kind: str | None = None,
    source_label: str | None = None,
) -> CodeConsoleResolvedContext:
    if context_id:
        cached_context = _cached_context_by_id(context_id)
        if cached_context is not None:
            return cached_context
    if input_path is None or sheet is None:
        raise ValueError(
            "Code Console context_id is unavailable. Request /code-console/context again or provide context details."
        )
    return build_code_console_context(
        input_path=input_path,
        sheet=sheet,
        template=template,
        size=size,
        style_preset=style_preset,
        palette_preset=palette_preset,
        visual_theme_id=visual_theme_id,
        source_kind=source_kind,
        source_label=source_label,
    )


def _serialize_context(context: CodeConsoleResolvedContext) -> dict[str, Any]:
    return {
        "context_id": context.context_id,
        "input_path": str(context.input_path),
        "input_mtime_ns": context.input_mtime_ns,
        "sheet": context.sheet,
        "sheet_names": list(context.sheet_names),
        "inspection": context.inspection,
        "dataset": context.dataset,
        "template": context.template,
        "options": context.options,
        "prompt_text": context.prompt_text,
        "starter_code": context.starter_code,
        "source_kind": context.source_kind,
        "source_label": context.source_label,
    }


def _generated_files(output_dir: Path) -> tuple[CodeConsoleGeneratedFile, ...]:
    if not output_dir.exists():
        return ()
    files = [path for path in output_dir.rglob("*") if path.is_file()]
    files.sort(key=lambda item: item.relative_to(output_dir).as_posix())
    return tuple(
        CodeConsoleGeneratedFile(
            path=path,
            name=path.relative_to(output_dir).as_posix(),
            file_type=(path.suffix.lower().lstrip(".") or "file"),
            size_bytes=path.stat().st_size,
        )
        for path in files
    )


def _coerce_subprocess_text(value: bytes | str | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def _subprocess_environment(*, output_dir: Path, context_json_path: Path) -> dict[str, str]:
    environment = dict(os.environ)
    existing_pythonpath = environment.get("PYTHONPATH", "").strip()
    environment["PYTHONPATH"] = (
        f"{REPO_ROOT}{os.pathsep}{existing_pythonpath}" if existing_pythonpath else str(REPO_ROOT)
    )
    environment["PYTHONUNBUFFERED"] = "1"
    environment["OUTPUT_DIR"] = str(output_dir)
    environment["CODEGOD_CODE_CONSOLE_CONTEXT_JSON"] = str(context_json_path)
    return environment


def _run_script_subprocess(
    *,
    script_path: Path,
    output_dir: Path,
    context_path: Path,
    timeout_seconds: int,
) -> tuple[str, int | None, str, str]:
    environment = _subprocess_environment(output_dir=output_dir, context_json_path=context_path)
    try:
        completed = subprocess.run(
            [sys.executable, str(script_path)],
            cwd=str(REPO_ROOT),
            env=environment,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
        status = "succeeded" if completed.returncode == 0 else "failed"
        return status, completed.returncode, completed.stdout, completed.stderr
    except subprocess.TimeoutExpired as exc:
        stderr = _coerce_subprocess_text(exc.stderr) + (
            f"\nCode Console timed out after {timeout_seconds} seconds."
            if timeout_seconds > 0
            else "\nCode Console timed out."
        )
        return "timed_out", None, _coerce_subprocess_text(exc.stdout), stderr


def run_code_console_script(
    *,
    code: str,
    timeout_seconds: int,
    context_id: str | None = None,
    input_path: Path | None = None,
    sheet: str | int | None = None,
    template: str | None = None,
    size: str | None = None,
    style_preset: str | None = None,
    palette_preset: str | None = None,
    visual_theme_id: str | None = None,
    source_kind: str | None = None,
    source_label: str | None = None,
) -> CodeConsoleRunResult:
    context = resolve_code_console_context(
        context_id=context_id,
        input_path=input_path,
        sheet=sheet,
        template=template,
        size=size,
        style_preset=style_preset,
        palette_preset=palette_preset,
        visual_theme_id=visual_theme_id,
        source_kind=source_kind,
        source_label=source_label,
    )
    _cache_context(context)
    run_dir = prepare_managed_code_console_run_dir(context.input_path, sheet=context.sheet)
    output_dir = run_dir / "outputs"
    output_dir.mkdir(parents=True, exist_ok=True)
    prompt_path = run_dir / "external_ai_prompt.txt"
    context_path = run_dir / "context.json"
    script_path = run_dir / "user_code.py"
    stdout_path = run_dir / "stdout.txt"
    stderr_path = run_dir / "stderr.txt"

    prompt_path.write_text(context.prompt_text, encoding="utf-8")
    context_path.write_text(
        json.dumps(_serialize_context(context), ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    script_path.write_text(code, encoding="utf-8")

    started_at = time.perf_counter()
    fallback_reason: str | None = None
    try:
        execution = DEFAULT_RUNNER_MANAGER.run(
            script_path=script_path,
            repo_root=REPO_ROOT,
            output_dir=output_dir,
            context_json_path=context_path,
            timeout_seconds=timeout_seconds,
        )
        status = execution.status
        exit_code = execution.exit_code
        stdout = execution.stdout
        stderr = execution.stderr
    except Exception as exc:
        fallback_reason = str(exc).strip() or "unknown persistent runner error"
        status, exit_code, stdout, stderr = _run_script_subprocess(
            script_path=script_path,
            output_dir=output_dir,
            context_path=context_path,
            timeout_seconds=timeout_seconds,
        )

    duration_seconds = time.perf_counter() - started_at
    if fallback_reason:
        fallback_note = f"Persistent runner unavailable, fell back to subprocess: {fallback_reason}"
        stderr = f"{stderr.rstrip()}\n{fallback_note}".strip()

    stdout_path.write_text(stdout, encoding="utf-8")
    stderr_path.write_text(stderr, encoding="utf-8")

    return CodeConsoleRunResult(
        status=status,
        exit_code=exit_code,
        duration_seconds=round(duration_seconds, 3),
        stdout=stdout,
        stderr=stderr,
        run_dir=run_dir,
        output_dir=output_dir,
        script_path=script_path,
        prompt_path=prompt_path,
        context_path=context_path,
        stdout_path=stdout_path,
        stderr_path=stderr_path,
        generated_files=_generated_files(output_dir),
    )
__all__ = [
    "CodeConsoleGeneratedFile",
    "CodeConsoleResolvedContext",
    "CodeConsoleRunResult",
    "build_code_console_context",
    "resolve_code_console_context",
    "run_code_console_script",
]
