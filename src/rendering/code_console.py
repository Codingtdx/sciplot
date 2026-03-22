from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import zipfile
from base64 import b64encode
from datetime import UTC, datetime
from pathlib import Path
from time import perf_counter
from typing import Any

import pandas as pd

from src import plot_style
from src.composer_render import panel_thumbnail_png
from src.data_loader import CurveSeries, HeatmapTable, ReplicateGroup
from src.plot_contract import CONTRACT_PATH, load_plot_contract, template_contract
from src.rendering.cache import (
    load_curve_table_cached,
    load_frequency_sweep_metrics_cached,
    load_heatmap_table_cached,
    load_replicate_table_cached,
    load_stress_relaxation_metric_cached,
    load_temperature_sweep_metrics_cached,
    read_raw_table_cached,
)
from src.rendering.io import list_sheet_names
from src.rendering.local_storage import create_managed_code_console_run_dir
from src.rendering.models import InputInspection, RenderOptions
from src.rendering.options import resolve_render_options, validate_template_name
from src.rendering.recommendation import detect_point_line_bundle, inspect_input_file
from src.rheology_loader import RheologySeries
from src.text_normalization import slugify_label

AI_BUNDLE_VERSION = 1
_BUNDLE_TIMESTAMP_FORMAT = "%Y%m%dT%H%M%SZ"
CODE_CONSOLE_RUN_TIMEOUT_SECONDS = 20
CODE_CONSOLE_PREVIEW_SUFFIXES = {".pdf", ".png", ".jpg", ".jpeg", ".tif", ".tiff"}

_TRUSTED_REPO_FILES: tuple[dict[str, str], ...] = (
    {
        "id": "plot_contract",
        "label": "Plot contract",
        "path": "src/plot_contract.json",
        "kind": "contract",
        "reason": "The canonical plotting contract. Size, style, palette, and template rules come from here first.",
    },
    {
        "id": "plot_contract_docs",
        "label": "Plot contract docs",
        "path": "docs/plot_contract.md",
        "kind": "documentation",
        "reason": (
            "Human-readable contract output generated from the contract JSON. "
            "Useful for explanation, not as the source of truth."
        ),
    },
    {
        "id": "plot_style",
        "label": "Plot style helper",
        "path": "src/plot_style.py",
        "kind": "style_helper",
        "reason": (
            "The shared style helper that applies contract-backed typography, "
            "stroke, margins, palette, and export defaults."
        ),
    },
    {
        "id": "rendering_init",
        "label": "Rendering service entry",
        "path": "src/rendering/__init__.py",
        "kind": "service_entry",
        "reason": "The public rendering service surface that CLI and sidecar are expected to reuse.",
    },
    {
        "id": "rendering_options",
        "label": "Render option resolver",
        "path": "src/rendering/options.py",
        "kind": "service_helper",
        "reason": "Resolves size/style/palette selections against the contract and enforces template compatibility.",
    },
    {
        "id": "rendering_render",
        "label": "Render orchestration",
        "path": "src/rendering/render.py",
        "kind": "service_helper",
        "reason": (
            "The render orchestration layer that turns normalized inputs plus "
            "resolved options into project-native outputs."
        ),
    },
    {
        "id": "make_plot",
        "label": "CLI compatibility entry",
        "path": "make_plot.py",
        "kind": "entry_point",
        "reason": (
            "Shows the supported repo-native invocation pattern and keeps "
            "custom helpers aligned with the main rendering flow."
        ),
    },
)


def _now_utc_iso() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _bundle_stamp() -> str:
    return datetime.now(UTC).strftime(_BUNDLE_TIMESTAMP_FORMAT)


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(_repo_root()))
    except ValueError:
        return str(path.resolve())


def _contract_sha256() -> str:
    return hashlib.sha256(CONTRACT_PATH.read_bytes()).hexdigest()


def _hash_identifier(prefix: str, payload: dict[str, Any], *, length: int = 16) -> str:
    digest = hashlib.sha256(
        json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    ).hexdigest()
    return f"{prefix}_{digest[:length]}"


def _clean_cell(value: object) -> object:
    if value is None:
        return None
    if hasattr(value, "item") and not isinstance(value, (str, bytes)):
        try:
            value = value.item()
        except Exception:
            pass
    if isinstance(value, float):
        if pd.isna(value):
            return None
        return round(value, 6)
    if isinstance(value, int):
        return value
    if pd.isna(value):
        return None
    text = str(value).strip()
    return text or None


def _subprocess_text(value: bytes | str | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def _numeric_or_none(value: object) -> float | int | None:
    cleaned = _clean_cell(value)
    if cleaned is None:
        return None
    if isinstance(cleaned, (float, int)):
        return cleaned
    try:
        numeric = float(str(cleaned))
    except (TypeError, ValueError):
        return None
    return int(numeric) if numeric.is_integer() else round(numeric, 6)


def _string_or_none(value: object) -> str | None:
    cleaned = _clean_cell(value)
    if cleaned is None:
        return None
    return str(cleaned)


def _dataframe_sample_rows(frame: pd.DataFrame, *, limit: int = 6) -> list[list[object]]:
    rows: list[list[object]] = []
    preview = frame.head(limit)
    for row in preview.itertuples(index=False, name=None):
        rows.append([_clean_cell(value) for value in row])
    return rows


def _column_name(raw: pd.DataFrame, index: int) -> str:
    preview = [
        _string_or_none(raw.iloc[row_index, index])
        for row_index in range(min(3, raw.shape[0]))
    ]
    labels = [value for value in preview if value]
    return " | ".join(labels) if labels else f"Column {index + 1}"


def _summarize_raw_columns(raw: pd.DataFrame, *, limit: int = 24) -> list[dict[str, object]]:
    summaries: list[dict[str, object]] = []
    max_columns = min(raw.shape[1], limit)
    for index in range(max_columns):
        series = raw.iloc[:, index]
        numeric = pd.to_numeric(series, errors="coerce")
        non_empty = sum(_clean_cell(value) is not None for value in series.tolist())
        missing = len(series) - non_empty
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
        summaries.append(
            {
                "name": _column_name(raw, index),
                "inferred_type": inferred_type,
                "non_empty_count": non_empty,
                "missing_count": missing,
                "header_preview": [
                    _string_or_none(raw.iloc[row_index, index])
                    for row_index in range(min(3, raw.shape[0]))
                ],
                "min_value": min_value,
                "max_value": max_value,
            }
        )
    return summaries


def _build_curve_frame(series_list: list[CurveSeries]) -> pd.DataFrame:
    frames: list[pd.DataFrame] = []
    for series in series_list:
        frame = series.data.copy(deep=True)
        frame.insert(0, "sample", series.sample)
        frame["x_label"] = series.x_label
        frame["y_label"] = series.y_label
        frame["x_unit"] = series.x_unit
        frame["y_unit"] = series.y_unit
        frames.append(frame)
    return pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()


def _build_replicate_frame(groups: list[ReplicateGroup]) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for group in groups:
        for value in group.data.tolist():
            rows.append(
                {
                    "group": group.group,
                    "value": _numeric_or_none(value),
                    "value_label": group.value_label,
                    "value_unit": group.value_unit,
                }
            )
    return pd.DataFrame(rows)


def _build_heatmap_frame(table: HeatmapTable) -> pd.DataFrame:
    frame = table.data.copy(deep=True)
    frame["x_label"] = table.x_label
    frame["y_label"] = table.y_label
    frame["z_label"] = table.z_label
    frame["x_unit"] = table.x_unit
    frame["y_unit"] = table.y_unit
    frame["z_unit"] = table.z_unit
    return frame


def _build_rheology_frame(series_map: dict[str, list[RheologySeries]]) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for metric_name, series_list in series_map.items():
        for series in series_list:
            for row in series.data.itertuples(index=False):
                rows.append(
                    {
                        "metric": metric_name,
                        "sample": series.sample,
                        "x": _numeric_or_none(row[0]),
                        "y": _numeric_or_none(row[1]),
                        "x_label": series.x_label,
                        "y_label": series.y_label,
                        "x_unit": series.x_unit,
                        "y_unit": series.y_unit,
                    }
                )
    return pd.DataFrame(rows)


def _curve_summary(series_list: list[CurveSeries]) -> dict[str, object]:
    return {
        "kind": "curve_series",
        "series_count": len(series_list),
        "samples": [series.sample for series in series_list],
        "axes": [
            {
                "sample": series.sample,
                "x_label": series.x_label,
                "y_label": series.y_label,
                "x_unit": series.x_unit,
                "y_unit": series.y_unit,
                "point_count": int(series.data.shape[0]),
                "x_min": _numeric_or_none(series.data["x"].min()),
                "x_max": _numeric_or_none(series.data["x"].max()),
                "y_min": _numeric_or_none(series.data["y"].min()),
                "y_max": _numeric_or_none(series.data["y"].max()),
            }
            for series in series_list
        ],
    }


def _replicate_summary(groups: list[ReplicateGroup]) -> dict[str, object]:
    return {
        "kind": "replicate_groups",
        "group_count": len(groups),
        "groups": [
            {
                "group": group.group,
                "value_label": group.value_label,
                "value_unit": group.value_unit,
                "replicate_count": int(group.data.shape[0]),
                "min_value": _numeric_or_none(group.data.min()),
                "max_value": _numeric_or_none(group.data.max()),
                "mean_value": _numeric_or_none(group.data.mean()),
            }
            for group in groups
        ],
    }


def _heatmap_summary(table: HeatmapTable) -> dict[str, object]:
    return {
        "kind": "heatmap_matrix",
        "x_label": table.x_label,
        "y_label": table.y_label,
        "z_label": table.z_label,
        "x_unit": table.x_unit,
        "y_unit": table.y_unit,
        "z_unit": table.z_unit,
        "point_count": int(table.data.shape[0]),
        "x_unique": int(table.data["x"].nunique()),
        "y_unique": int(table.data["y"].nunique()),
        "z_min": _numeric_or_none(table.data["z"].min()),
        "z_max": _numeric_or_none(table.data["z"].max()),
    }


def _rheology_summary(series_map: dict[str, list[RheologySeries]]) -> dict[str, object]:
    metrics: list[dict[str, object]] = []
    for metric_name, series_list in series_map.items():
        metrics.append(
            {
                "metric": metric_name,
                "series_count": len(series_list),
                "samples": [series.sample for series in series_list],
                "point_count": int(sum(series.data.shape[0] for series in series_list)),
            }
        )
    return {
        "kind": "rheology_bundle",
        "metric_count": len(metrics),
        "metrics": metrics,
    }


def _series_map_for_bundle(bundle: str, input_path: Path, sheet: str | int) -> dict[str, list[RheologySeries]]:
    if bundle == "frequency_sweep":
        return load_frequency_sweep_metrics_cached(input_path, sheet)
    if bundle == "temperature_sweep":
        return load_temperature_sweep_metrics_cached(input_path, sheet)
    if bundle == "stress_relaxation":
        return {
            "sigma_over_sigma0": load_stress_relaxation_metric_cached(
                input_path,
                "σ/σ₀",
                sheet,
            )
        }
    raise ValueError(f"Unsupported bundle type: {bundle}")


def _normalized_dataset(
    input_path: Path,
    sheet: str | int,
    inspection: InputInspection,
) -> tuple[pd.DataFrame, dict[str, object]]:
    if inspection.model in {"curve_table", "tensile_curve"}:
        series_list = load_curve_table_cached(input_path, sheet)
        return _build_curve_frame(series_list), _curve_summary(series_list)
    if inspection.model == "replicate_table":
        groups = load_replicate_table_cached(input_path, sheet)
        return _build_replicate_frame(groups), _replicate_summary(groups)
    if inspection.model == "heatmap_table":
        table = load_heatmap_table_cached(input_path, sheet)
        return _build_heatmap_frame(table), _heatmap_summary(table)

    bundle = detect_point_line_bundle(input_path, sheet)
    if bundle in {"frequency_sweep", "temperature_sweep", "stress_relaxation"}:
        series_map = _series_map_for_bundle(bundle, input_path, sheet)
        return _build_rheology_frame(series_map), _rheology_summary(series_map)

    series_list = load_curve_table_cached(input_path, sheet)
    return _build_curve_frame(series_list), _curve_summary(series_list)


def _missing_summary(raw: pd.DataFrame) -> dict[str, int]:
    empty_cells = 0
    for row in raw.itertuples(index=False, name=None):
        empty_cells += sum(value is None for value in [_clean_cell(item) for item in row])
    return {
        "empty_cells": empty_cells,
        "rows": int(raw.shape[0]),
        "columns": int(raw.shape[1]),
    }


def _truth_sources(
    *,
    input_path: Path | None,
    sheet: str | int | None,
    inspection: InputInspection | None,
    project_path: Path | None,
    bundle_path: Path | None = None,
) -> list[dict[str, object]]:
    sources: list[dict[str, object]] = []
    for item in _TRUSTED_REPO_FILES:
        sources.append(
            {
                **item,
                "display_path": item["path"],
                "available": True,
            }
        )
    if input_path is not None:
        sources.append(
            {
                "id": "current_data",
                "label": "Current data file",
                "path": str(input_path),
                "display_path": _display_path(input_path),
                "kind": "data",
                "available": True,
                "reason": (
                    "This is the raw input currently bound to the plot session. "
                    "The sidecar reads this file directly for inspect, preview, "
                    "and bundle export."
                ),
            }
        )
    if input_path is not None and sheet is not None:
        sources.append(
            {
                "id": "current_sheet",
                "label": "Current sheet",
                "path": None,
                "display_path": str(sheet),
                "kind": "sheet",
                "available": True,
                "reason": (
                    "This is the exact worksheet or sheet index used to derive "
                    "the current session summary and any exported AI bundle."
                ),
            }
        )
    if inspection is not None:
        sources.append(
            {
                "id": "current_inspection",
                "label": "Current inspect summary",
                "path": None,
                "display_path": inspection.model_label,
                "kind": "inspection",
                "available": True,
                "reason": (
                    "This summary is generated by the sidecar from the same "
                    "bound file and sheet, so it is safer than handwritten "
                    "prompt notes."
                ),
            }
        )
    if project_path is not None:
        sources.append(
            {
                "id": "current_project",
                "label": "Current project file",
                "path": str(project_path),
                "display_path": _display_path(project_path),
                "kind": "project",
                "available": True,
                "reason": (
                    "This is the validated SciPlot God project file attached to "
                    "the current session context, if one is available."
                ),
            }
        )
    if bundle_path is not None:
        sources.append(
            {
                "id": "generated_bundle",
                "label": "Generated AI bundle",
                "path": str(bundle_path),
                "display_path": _display_path(bundle_path),
                "kind": "bundle",
                "available": True,
                "reason": (
                    "This exported bundle is produced by the sidecar from the "
                    "current session and is the canonical package to hand to an "
                    "external AI."
                ),
            }
        )
    return sources


def _defaults_panel(
    *,
    template: str,
    options: RenderOptions,
    input_path: Path | None,
    sheet: str | int | None,
    inspection: InputInspection | None,
    project_path: Path | None,
) -> dict[str, list[dict[str, object]]]:
    spec = template_contract(template)
    contract = load_plot_contract()
    return {
        "locked_by_contract": [
            {
                "label": "Axis frame",
                "value": f"{contract.global_frame.panel_width_mm:g} x {contract.global_frame.panel_height_mm:g} mm",
                "reason": (
                    "Shared physical panel frame comes from the plot contract "
                    "and stays fixed across standard plots."
                ),
            },
            {
                "label": "Margins",
                "value": (
                    f"L {contract.global_frame.left_margin_mm:g} / "
                    f"R {contract.global_frame.right_margin_mm:g} / "
                    f"B {contract.global_frame.bottom_margin_mm:g} / "
                    f"T {contract.global_frame.top_margin_mm:g} mm"
                ),
                "reason": "Global panel margins are inherited from the contract-backed style system.",
            },
            {
                "label": "Allowed sizes",
                "value": ", ".join(spec.allowed_sizes),
                "reason": "Only sizes allowed by the selected template remain legal.",
            },
            {
                "label": "Allowed styles",
                "value": ", ".join(spec.available_styles),
                "reason": (
                    "Style presets are restricted by the selected template and "
                    "resolved through the rendering options service."
                ),
            },
            {
                "label": "Allowed palettes",
                "value": ", ".join(spec.available_palettes),
                "reason": (
                    "Palette presets are restricted by the selected template and "
                    "should still come from project helpers."
                ),
            },
        ],
        "user_selectable": [
            {
                "label": "Base template",
                "value": template,
                "reason": (
                    "User-selected in Code Console, then validated against the "
                    "contract before prompt/scaffold generation."
                ),
            },
            {
                "label": "Target size",
                "value": f"{options.width_mm:g} x {options.height_mm:g} mm",
                "reason": "Selected in the builder, but normalized by `resolve_render_options(...)`.",
            },
            {
                "label": "Style preset",
                "value": options.style_preset,
                "reason": (
                    "Selected in the builder, but still must remain a "
                    "contract-backed public style."
                ),
            },
            {
                "label": "Palette preset",
                "value": options.palette_preset,
                "reason": (
                    "Selected in the builder, but still must remain a "
                    "contract-backed palette."
                ),
            },
        ],
        "derived_from_session": [
            {
                "label": "Bound data",
                "value": _display_path(input_path) if input_path is not None else "No data bound",
                "reason": "Derived from the active plot session if a data file is currently open.",
            },
            {
                "label": "Bound sheet",
                "value": str(sheet) if sheet is not None else "-",
                "reason": "Derived from the active plot session sheet selection.",
            },
            {
                "label": "Detected model",
                "value": inspection.model_label if inspection is not None else "-",
                "reason": "Derived by sidecar inspect from the current data file and sheet.",
            },
            {
                "label": "Project context",
                "value": _display_path(project_path) if project_path is not None else "Not attached",
                "reason": "Included only when a validated project file path is available and explicitly attached.",
            },
        ],
    }


def _lightweight_context_text(
    *,
    session: dict[str, Any],
    data_context: dict[str, Any] | None,
    truth_sources: list[dict[str, Any]],
    include_data_context: bool,
    include_inspection_summary: bool,
) -> str:
    lines = [
        "SciPlot God AI context bundle",
        f"- session_id: {session['session_id']}",
        f"- bound_data: {session['input_path'] or 'none'}",
        f"- sheet: {session['sheet']}",
        f"- template: {session['template']}",
        f"- size: {session['size_label']}",
        f"- style_preset: {session['style_preset']}",
        f"- palette_preset: {session['palette_preset']}",
    ]
    if include_data_context and data_context is not None:
        normalized_columns = [str(item) for item in data_context.get("normalized_columns", [])]
        missing_summary = data_context.get("missing_summary") or {}
        lines.extend(
            [
                "",
                "Data context:",
                f"- model: {data_context['model_label']}",
                f"- raw rows / columns: {data_context['raw_row_count']} / {data_context['raw_column_count']}",
                f"- normalized columns: {', '.join(normalized_columns) or '-'}",
                f"- missing cells: {missing_summary.get('empty_cells', 0)}",
            ]
        )
    if include_inspection_summary and data_context is not None:
        recommendation = data_context.get("recommendation") or {}
        lines.extend(
            [
                "",
                "Inspect / recommendation summary:",
                f"- recommended template: {recommendation.get('template', '-')}",
                f"- recommended size: {recommendation.get('size') or '-'}",
                f"- recommended style: {recommendation.get('style_preset') or '-'}",
                f"- recommended palette: {recommendation.get('palette_preset') or '-'}",
                f"- reason: {recommendation.get('reason', '-')}",
            ]
        )
    lines.extend(["", "Trusted sources:"])
    for source in truth_sources:
        label = source.get("display_path") or source.get("label")
        lines.append(f"- {label}: {source.get('reason', '')}")
    return "\n".join(lines)


def _intent_label(intent: str) -> str:
    return {
        "custom_plot": "Special plot",
        "patch_renderer": "Patch renderer",
        "annotation_tweak": "Annotation tweak",
    }.get(intent, "Special plot")


def _default_target_path(intent: str, template: str) -> str:
    if intent == "annotation_tweak":
        return "scripts/custom_plot_annotation.py or the relevant renderer/helper"
    if intent == "patch_renderer":
        return "The most relevant existing renderer/helper file under src/rendering/"
    return f"src/rendering/custom_{template}_helper.py"


def _implementation_bullets(intent: str) -> list[str]:
    shared = [
        "Reuse `src/rendering/options.py::resolve_render_options(...)` before inventing any local option parsing.",
        "Call `src/plot_style.py::apply_style(...)` before creating figures so rcParams stay aligned with the project.",
        (
            "Read linewidth, marker size, typography, legend, margins, and "
            "export rules from project helpers instead of hardcoding them."
        ),
        (
            "Use `create_panel_figure(...)`, `get_style_spec(...)`, "
            "`get_categorical_palette(...)` / `get_sequential_cmap(...)`, "
            "and `save_pdf(...)`."
        ),
    ]
    if intent == "annotation_tweak":
        return shared + [
            "Prefer the smallest possible change on top of the existing renderer or axes state.",
            "Keep annotation arrows and text tied to style-backed linewidth and typography values.",
        ]
    if intent == "patch_renderer":
        return shared + [
            (
                "Modify the existing renderer/helper in place instead of "
                "creating a detached demo path outside the rendering service "
                "layer."
            ),
        ]
    return shared + [
        (
            "If the existing template cannot express the target figure, add a "
            "focused custom helper/renderer without breaking "
            "sidecar/rendering boundaries."
        ),
    ]


def _prompt_text(
    *,
    intent: str,
    brief: str,
    target_path: str,
    session: dict[str, Any],
    data_context: dict[str, Any] | None,
    truth_sources: list[dict[str, Any]],
    include_data_context: bool,
    include_inspection_summary: bool,
) -> str:
    task_brief = brief.strip() or "Replace this with the requested special plot or renderer tweak."
    lines = [
        (
            "You are writing Python plotting code inside the SciPlot God repository. "
            "Treat this as an incremental modification of the current plot, not a "
            "standalone matplotlib demo or a from-scratch rewrite."
        ),
        "",
        "Repository constraints:",
        "- The only plotting truth source is `src/plot_contract.json`.",
        "- Reuse the `src/rendering/` service layer and the `make_plot.py` compatibility pattern first.",
        "- Inherit style, size, palette, margins, and export behavior from `src/plot_style.py` and rendering helpers.",
        "- Do not add frontend constants and do not move visual truth back into the GUI.",
        (
            "- Do not hardcode figure size, margins, font size, line width, or "
            "palette hex values unless they are read from project helpers "
            "first."
        ),
        "- Keep `style_preset` and `palette_preset` parameters in the final code path.",
        "",
        "Current task:",
        f"- mode: {_intent_label(intent)}",
        f"- request: {task_brief}",
        "- Start from the current plot session and current data context instead of rebuilding the figure from zero.",
        "- Aim for a special plot path or a visual micro-adjustment layered onto the current SciPlot God behavior.",
        f"- base template: {session['template']}",
        f"- target size: {session['size_label']}",
        f"- style_preset: {session['style_preset']}",
        f"- palette_preset: {session['palette_preset']}",
        f"- xscale / yscale: {session['xscale']} / {session['yscale']}",
        f"- reverse_x: {session['reverse_x']}",
        f"- baseline: {session['baseline']}",
        f"- show_colorbar: {session['show_colorbar']}",
        f"- suggested file target: {target_path}",
    ]

    if include_data_context and data_context is not None:
        normalized_columns = [str(item) for item in data_context.get("normalized_columns", [])]
        missing_summary = data_context.get("missing_summary") or {}
        lines.extend(
            [
                "",
                "Current data context:",
                f"- bound data: {session['input_path']}",
                f"- sheet: {session['sheet']}",
                f"- detected model: {data_context['model_label']}",
                f"- raw rows / columns: {data_context['raw_row_count']} / {data_context['raw_column_count']}",
                f"- normalized columns: {', '.join(normalized_columns) or '-'}",
                f"- missing cells: {missing_summary.get('empty_cells', 0)}",
            ]
        )
    if include_inspection_summary and data_context is not None:
        recommendation = data_context.get("recommendation") or {}
        lines.extend(
            [
                "",
                "Current inspect / recommendation summary:",
                f"- recommended template: {recommendation.get('template', '-')}",
                f"- recommended size: {recommendation.get('size') or '-'}",
                f"- recommended style: {recommendation.get('style_preset') or '-'}",
                f"- recommended palette: {recommendation.get('palette_preset') or '-'}",
                f"- recommendation reason: {recommendation.get('reason', '-')}",
            ]
        )
    lines.extend(["", "Truth sources to trust:"])
    for source in truth_sources:
        display_path = source.get("display_path") or source.get("label")
        lines.append(f"- {display_path}: {source.get('reason', '')}")
    lines.extend(
        [
            "",
            "Runner contract:",
            "- The pasted code will run in a repo-native Python runner from the repository root.",
            "- Save any generated previews, PDFs, or helper outputs only under `OUTPUT_DIR`.",
            (
                "- The runner exposes `OUTPUT_DIR`, `INPUT_PATH`, `CURRENT_SHEET`, "
                "`CURRENT_TEMPLATE`, `CURRENT_OPTIONS`, `CURRENT_INSPECTION`, "
                "`CURRENT_RECOMMENDATION`, and `CURRENT_DATA_CONTEXT`."
            ),
        ]
    )
    lines.extend(["", "Implementation strategy:"])
    lines.extend(f"- {bullet}" for bullet in _implementation_bullets(intent))
    lines.extend(
        [
            "",
            "Output requirements:",
            "- Return paste-ready Python code that can run inside the repo-native Code Console runner.",
            "- Do not wrap the Python code in Markdown fences.",
            "- Reuse project entry points instead of writing a detached demo script.",
            "- Keep the implementation compatible with the sidecar/rendering boundary.",
            "- Write generated outputs under `OUTPUT_DIR` only.",
        ]
    )
    return "\n".join(lines)


def _scaffold_text(
    *,
    intent: str,
    template: str,
    options: RenderOptions,
) -> str:
    function_name = {
        "annotation_tweak": "apply_annotation_tweak",
        "patch_renderer": "patch_existing_renderer",
    }.get(intent, "render_custom_plot")

    if template == "heatmap":
        custom_lines = [
            "    cmap = plot_style.get_sequential_cmap(options.palette_preset)",
            "    image = ax.imshow(matrix, cmap=cmap, aspect='auto')",
            "    if options.show_colorbar:",
            "        fig.colorbar(image, ax=ax)",
        ]
    elif intent == "annotation_tweak":
        custom_lines = [
            "    annotation_color = colors[0]",
            "    ax.plot(x, y, color=annotation_color, linewidth=style.stroke.line_width_pt)",
            "    ax.annotate(",
            "        'Callout',",
            "        xy=(x_anchor, y_anchor),",
            "        xytext=(x_text, y_text),",
            "        fontsize=style.typography.font_size_pt,",
            "        color=annotation_color,",
            "        arrowprops={",
            "            'arrowstyle': '->',",
            "            'lw': style.stroke.line_width_pt,",
            "            'alpha': style.stroke.line_alpha,",
            "            'color': annotation_color,",
            "        },",
            "    )",
        ]
    else:
        custom_lines = [
            "    ax.plot(x, y, color=colors[0], linewidth=style.stroke.line_width_pt)",
            "    # Add the custom plot logic here while preserving SciPlot God defaults.",
        ]

    argument_line = "    matrix," if template == "heatmap" else "    x, y,"
    return "\n".join(
        [
            "# Reuse these project entry points:",
            "# - src.rendering.options.resolve_render_options",
            "# - src.plot_style.apply_style / get_style_spec / create_panel_figure / save_pdf",
            "",
            "from __future__ import annotations",
            "",
            "from pathlib import Path",
            "",
            "from src import plot_style",
            "from src.rendering.options import resolve_render_options",
            "",
            "",
            f"def {function_name}(",
            "    output_path: str | Path,",
            argument_line,
            "    *,",
            f"    size: str = '{int(options.width_mm)}x{int(options.height_mm)}',",
            f"    style_preset: str = '{options.style_preset}',",
            f"    palette_preset: str = '{options.palette_preset}',",
            "):",
            "    options = resolve_render_options(",
            f"        template='{template}',",
            "        size=size,",
            "        style_preset=style_preset,",
            "        palette_preset=palette_preset,",
            "    )",
            "    plot_style.apply_style(options.style_preset, options.palette_preset)",
            "    style = plot_style.get_style_spec(options.style_preset)",
            "    colors = plot_style.get_categorical_palette(options.palette_preset, n_colors=6)",
            "    fig, ax = plot_style.create_panel_figure(options.width_mm, options.height_mm)",
            "",
            *custom_lines,
            "",
            "    plot_style.save_pdf(fig, output_path)",
            "    return Path(output_path)",
        ]
    )


def generate_code_console_payload(
    *,
    intent: str,
    brief: str,
    base_template: str,
    size: str | None,
    xscale: str | None = None,
    yscale: str | None = None,
    reverse_x: bool | None = None,
    baseline: str | None = None,
    show_colorbar: bool | None = None,
    style_preset: str | None,
    palette_preset: str | None,
    use_sidecar: bool | None = None,
    target_path: str | None,
    input_path: Path | None,
    sheet: str | int | None,
    project_path: Path | None = None,
    project_payload: dict[str, Any] | None = None,
    include_data_context: bool = True,
    include_inspection_summary: bool = True,
    include_project_context: bool = False,
) -> dict[str, Any]:
    template = validate_template_name(base_template)
    options = resolve_render_options(
        template=template,
        size=size,
        xscale=xscale,
        yscale=yscale,
        reverse_x=bool(reverse_x),
        baseline=baseline,
        show_colorbar=show_colorbar,
        style_preset=style_preset or plot_style.DEFAULT_STYLE_PRESET,
        palette_preset=palette_preset or plot_style.DEFAULT_PALETTE_PRESET,
        use_sidecar=use_sidecar,
    )
    normalized_target_path = (target_path or "").strip() or _default_target_path(intent, template)
    normalized_sheet = sheet if sheet is not None else 0
    inspection: InputInspection | None = None
    data_context: dict[str, object] | None = None
    sheet_names: list[str] = []
    if input_path is not None:
        inspection = inspect_input_file(input_path, normalized_sheet)
        raw = read_raw_table_cached(input_path, normalized_sheet)
        normalized_frame, interpreted_summary = _normalized_dataset(
            input_path,
            normalized_sheet,
            inspection,
        )
        sheet_names = list_sheet_names(input_path)
        data_context = {
            "available": True,
            "model": inspection.model,
            "model_label": inspection.model_label,
            "raw_row_count": int(raw.shape[0]),
            "raw_column_count": int(raw.shape[1]),
            "column_names": [_column_name(raw, index) for index in range(raw.shape[1])],
            "normalized_columns": [str(column) for column in normalized_frame.columns.tolist()],
            "column_summaries": _summarize_raw_columns(raw),
            "sample_rows": _dataframe_sample_rows(raw),
            "normalized_preview_rows": _dataframe_sample_rows(normalized_frame.head(10)),
            "missing_summary": _missing_summary(raw),
            "inspection": {
                "warnings": list(inspection.warnings),
                "signals": list(inspection.signals),
            },
            "recommendation": {
                "template": inspection.recommendation.template,
                "reason": inspection.recommendation.reason,
                "size": inspection.recommendation.size,
                "style_preset": inspection.recommendation.style_preset,
                "palette_preset": inspection.recommendation.palette_preset,
            },
            "interpreted_summary": interpreted_summary,
            "full_data_rows": int(normalized_frame.shape[0]),
            "full_data_columns": int(normalized_frame.shape[1]),
        }
    else:
        data_context = {
            "available": False,
            "model": None,
            "model_label": "No data bound",
            "raw_row_count": 0,
            "raw_column_count": 0,
            "column_names": [],
            "normalized_columns": [],
            "column_summaries": [],
            "sample_rows": [],
            "normalized_preview_rows": [],
            "missing_summary": {"empty_cells": 0, "rows": 0, "columns": 0},
            "inspection": {"warnings": [], "signals": []},
            "recommendation": {
                "template": template,
                "reason": "No bound data file. This prompt is generated from explicit Code Console selections only.",
                "size": size,
                "style_preset": options.style_preset,
                "palette_preset": options.palette_preset,
            },
            "interpreted_summary": {},
            "full_data_rows": 0,
            "full_data_columns": 0,
        }

    contract = load_plot_contract()
    session_payload = {
        "input_path": str(input_path) if input_path is not None else None,
        "sheet": normalized_sheet if input_path is not None else None,
        "template": template,
        "style_preset": options.style_preset,
        "palette_preset": options.palette_preset,
        "width_mm": options.width_mm,
        "height_mm": options.height_mm,
    }
    session_id = _hash_identifier("session", session_payload)
    project_id = (
        _hash_identifier("project", {"project_path": str(project_path)})
        if include_project_context and project_path is not None
        else None
    )
    truth_sources = _truth_sources(
        input_path=input_path,
        sheet=normalized_sheet if input_path is not None else None,
        inspection=inspection if include_inspection_summary else None,
        project_path=project_path if include_project_context else None,
    )
    session = {
        "session_id": session_id,
        "session_source": "wizard",
        "project_id": project_id,
        "project_path": str(project_path) if include_project_context and project_path is not None else None,
        "project_mode": project_payload.get("mode") if include_project_context and project_payload else None,
        "input_path": str(input_path) if input_path is not None else None,
        "input_display_path": _display_path(input_path) if input_path is not None else None,
        "input_filename": input_path.name if input_path is not None else None,
        "sheet": normalized_sheet if input_path is not None else None,
        "sheet_names": sheet_names,
        "template": template,
        "size_label": f"{options.width_mm:g} x {options.height_mm:g} mm",
        "size_id": size or template_contract(template).default_size,
        "style_preset": options.style_preset,
        "palette_preset": options.palette_preset,
        "xscale": options.xscale,
        "yscale": options.yscale,
        "reverse_x": options.reverse_x,
        "baseline": options.baseline,
        "show_colorbar": options.show_colorbar,
        "intent": intent,
        "target_path": normalized_target_path,
    }
    lightweight_text = _lightweight_context_text(
        session=session,
        data_context=data_context,
        truth_sources=truth_sources,
        include_data_context=include_data_context,
        include_inspection_summary=include_inspection_summary,
    )
    return {
        "bundle_version": AI_BUNDLE_VERSION,
        "generated_at": _now_utc_iso(),
        "contract": {
            "version": contract.version,
            "sha256": _contract_sha256(),
            "default_style": contract.defaults.style_preset,
            "default_palette": contract.defaults.palette_preset,
        },
        "session": session,
        "defaults_panel": _defaults_panel(
            template=template,
            options=options,
            input_path=input_path,
            sheet=normalized_sheet if input_path is not None else None,
            inspection=inspection,
            project_path=project_path if include_project_context else None,
        ),
        "truth_sources": truth_sources,
        "data_context": data_context,
        "prompt_text": _prompt_text(
            intent=intent,
            brief=brief,
            target_path=normalized_target_path,
            session=session,
            data_context=data_context if include_data_context else None,
            truth_sources=truth_sources,
            include_data_context=include_data_context,
            include_inspection_summary=include_inspection_summary,
        ),
        "scaffold_text": _scaffold_text(
            intent=intent,
            template=template,
            options=options,
        ),
        "lightweight_bundle": {
            "text": lightweight_text,
            "includes_data_context": include_data_context and bool(input_path),
            "includes_inspection_summary": include_inspection_summary and inspection is not None,
            "includes_project_context": include_project_context and project_path is not None,
            "includes_full_data": False,
        },
    }


def _bootstrap_context(payload: dict[str, Any], *, output_dir: Path) -> dict[str, Any]:
    data_context = payload["data_context"]
    return {
        "repo_root": str(_repo_root()),
        "output_dir": str(output_dir),
        "contract": payload["contract"],
        "session": payload["session"],
        "input_path": payload["session"].get("input_path"),
        "sheet": payload["session"].get("sheet"),
        "template": payload["session"].get("template"),
        "options": {
            "size": payload["session"].get("size_id"),
            "style_preset": payload["session"].get("style_preset"),
            "palette_preset": payload["session"].get("palette_preset"),
            "xscale": payload["session"].get("xscale"),
            "yscale": payload["session"].get("yscale"),
            "reverse_x": payload["session"].get("reverse_x"),
            "baseline": payload["session"].get("baseline"),
            "show_colorbar": payload["session"].get("show_colorbar"),
        },
        "inspection": data_context.get("inspection"),
        "recommendation": data_context.get("recommendation"),
        "data_context": data_context,
        "truth_sources": payload["truth_sources"],
    }


def _write_bootstrap_files(run_dir: Path, *, payload: dict[str, Any], output_dir: Path, code: str) -> Path:
    context_path = run_dir / "context.json"
    user_code_path = run_dir / "user_code.py"
    runner_path = run_dir / "run_user_code.py"
    _write_json(context_path, _bootstrap_context(payload, output_dir=output_dir))
    _write_text(user_code_path, code)
    _write_text(
        runner_path,
        "\n".join(
            [
                "from __future__ import annotations",
                "",
                "import json",
                "from pathlib import Path",
                "",
                "RUN_DIR = Path(__file__).resolve().parent",
                "BOOTSTRAP = json.loads((RUN_DIR / 'context.json').read_text(encoding='utf-8'))",
                "REPO_ROOT = Path(BOOTSTRAP['repo_root'])",
                "OUTPUT_DIR = Path(BOOTSTRAP['output_dir'])",
                "OUTPUT_DIR.mkdir(parents=True, exist_ok=True)",
                "INPUT_PATH = Path(BOOTSTRAP['input_path']) if BOOTSTRAP.get('input_path') else None",
                "CURRENT_SHEET = BOOTSTRAP.get('sheet')",
                "CURRENT_TEMPLATE = BOOTSTRAP['template']",
                "CURRENT_OPTIONS = BOOTSTRAP['options']",
                "CURRENT_CONTRACT = BOOTSTRAP['contract']",
                "CURRENT_SESSION = BOOTSTRAP['session']",
                "CURRENT_INSPECTION = BOOTSTRAP.get('inspection')",
                "CURRENT_RECOMMENDATION = BOOTSTRAP.get('recommendation')",
                "CURRENT_DATA_CONTEXT = BOOTSTRAP['data_context']",
                "CURRENT_TRUTH_SOURCES = BOOTSTRAP['truth_sources']",
                "",
                "def output_path(filename: str) -> Path:",
                "    root = OUTPUT_DIR.resolve()",
                "    target = (root / filename).resolve()",
                "    if target != root and root not in target.parents:",
                "        raise ValueError('Generated files must stay inside OUTPUT_DIR.')",
                "    target.parent.mkdir(parents=True, exist_ok=True)",
                "    return target",
                "",
                "globals_dict = {",
                "    '__name__': '__main__',",
                "    'REPO_ROOT': REPO_ROOT,",
                "    'OUTPUT_DIR': OUTPUT_DIR,",
                "    'INPUT_PATH': INPUT_PATH,",
                "    'CURRENT_SHEET': CURRENT_SHEET,",
                "    'CURRENT_TEMPLATE': CURRENT_TEMPLATE,",
                "    'CURRENT_OPTIONS': CURRENT_OPTIONS,",
                "    'CURRENT_CONTRACT': CURRENT_CONTRACT,",
                "    'CURRENT_SESSION': CURRENT_SESSION,",
                "    'CURRENT_INSPECTION': CURRENT_INSPECTION,",
                "    'CURRENT_RECOMMENDATION': CURRENT_RECOMMENDATION,",
                "    'CURRENT_DATA_CONTEXT': CURRENT_DATA_CONTEXT,",
                "    'CURRENT_TRUTH_SOURCES': CURRENT_TRUTH_SOURCES,",
                "    'output_path': output_path,",
                "}",
                "source = (RUN_DIR / 'user_code.py').read_text(encoding='utf-8')",
                "exec(compile(source, str(RUN_DIR / 'user_code.py'), 'exec'), globals_dict, globals_dict)",
            ]
        ),
    )
    return runner_path


def _generated_files(output_dir: Path) -> list[Path]:
    return sorted(
        [path for path in output_dir.rglob("*") if path.is_file()],
        key=lambda path: path.relative_to(output_dir).as_posix(),
    )


def _preview_items(output_dir: Path) -> list[dict[str, object]]:
    previews: list[dict[str, object]] = []
    for path in _generated_files(output_dir):
        if path.suffix.lower() not in CODE_CONSOLE_PREVIEW_SUFFIXES:
            continue
        try:
            png_bytes = panel_thumbnail_png(path, max_side_px=960)
        except Exception:
            continue
        previews.append(
            {
                "filename": path.name,
                "png_base64": b64encode(png_bytes).decode("ascii"),
                "qa": None,
            }
        )
    return previews


def run_code_console_python(code: str, *, payload: dict[str, Any]) -> dict[str, Any]:
    if not code.strip():
        raise ValueError("Paste Python code before running the repo-native runner.")

    run_dir = create_managed_code_console_run_dir(payload.get("session", {}))
    output_dir = run_dir / "outputs"
    output_dir.mkdir(parents=True, exist_ok=True)
    runner_path = _write_bootstrap_files(
        run_dir,
        payload=payload,
        output_dir=output_dir,
        code=code,
    )
    env = os.environ.copy()
    env.update(
        {
            "CODEGOD_REPO_ROOT": str(_repo_root()),
            "CODEGOD_OUTPUT_DIR": str(output_dir),
            "CODEGOD_INPUT_PATH": payload["session"].get("input_path") or "",
            "CODEGOD_SHEET": str(payload["session"].get("sheet") or ""),
            "CODEGOD_TEMPLATE": str(payload["session"].get("template") or ""),
        }
    )

    timed_out = False
    start = perf_counter()
    stdout = ""
    stderr = ""
    exit_code = 0
    try:
        completed = subprocess.run(
            [sys.executable, str(runner_path)],
            cwd=_repo_root(),
            capture_output=True,
            text=True,
            timeout=CODE_CONSOLE_RUN_TIMEOUT_SECONDS,
            env=env,
            check=False,
        )
        stdout = completed.stdout
        stderr = completed.stderr
        exit_code = completed.returncode
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        stdout = _subprocess_text(exc.stdout)
        stderr = _subprocess_text(exc.stderr)
        stderr = f"{stderr}\nRunner timed out after {CODE_CONSOLE_RUN_TIMEOUT_SECONDS} seconds.".strip()
        exit_code = 124

    duration_ms = int(round((perf_counter() - start) * 1000))
    generated_files = _generated_files(output_dir)
    return {
        "generated_at": _now_utc_iso(),
        "output_dir": str(output_dir),
        "stdout": stdout,
        "stderr": stderr,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "duration_ms": duration_ms,
        "generated_files": [
            {
                "path": str(path),
                "filename": path.name,
                "kind": path.suffix.lower().lstrip(".") or "file",
            }
            for path in generated_files
        ],
        "previews": _preview_items(output_dir),
    }


def _bundle_dir_name(session: dict[str, object], *, include_full_data: bool) -> str:
    stem_source = (
        session.get("input_filename")
        or session.get("project_id")
        or session.get("template")
        or "code_console"
    )
    slug = slugify_label(str(stem_source))
    suffix = "full_ai_bundle" if include_full_data else "light_ai_bundle"
    return f"{slug}_{suffix}_{_bundle_stamp()}"


def _write_json(path: Path, payload: object) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def _write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def _write_csv(path: Path, frame: pd.DataFrame) -> None:
    export = frame.copy(deep=True)
    export = export.map(_clean_cell) if hasattr(export, "map") else export.applymap(_clean_cell)
    export.to_csv(path, index=False)


def _normalized_frame_for_export(
    input_path: Path,
    sheet: str | int,
    model: str | None,
) -> pd.DataFrame:
    if model in {"curve_table", "tensile_curve"}:
        return _build_curve_frame(load_curve_table_cached(input_path, sheet))
    if model == "replicate_table":
        return _build_replicate_frame(load_replicate_table_cached(input_path, sheet))
    if model == "heatmap_table":
        return _build_heatmap_frame(load_heatmap_table_cached(input_path, sheet))

    bundle = detect_point_line_bundle(input_path, sheet)
    if bundle in {"frequency_sweep", "temperature_sweep", "stress_relaxation"}:
        return _build_rheology_frame(_series_map_for_bundle(bundle, input_path, sheet))

    return _build_curve_frame(load_curve_table_cached(input_path, sheet))


def export_code_console_bundle(
    *,
    output_dir: Path,
    payload: dict[str, Any],
    include_full_data: bool,
) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    session = payload["session"]
    input_path_text = payload["session"].get("input_path")
    sheet = payload["session"].get("sheet")
    effective_include_full_data = bool(include_full_data and input_path_text and sheet is not None)
    bundle_dir = output_dir / _bundle_dir_name(
        session,
        include_full_data=effective_include_full_data,
    )
    bundle_dir.mkdir(parents=True, exist_ok=True)

    prompt_path = bundle_dir / "ai_prompt.txt"
    scaffold_path = bundle_dir / "starter_scaffold.py"
    lightweight_path = bundle_dir / "lightweight_context.txt"
    context_path = bundle_dir / "context_summary.json"
    truth_sources_path = bundle_dir / "truth_sources.json"
    manifest_path = bundle_dir / "manifest.json"

    _write_text(prompt_path, payload["prompt_text"])
    _write_text(scaffold_path, payload["scaffold_text"])
    _write_text(lightweight_path, payload["lightweight_bundle"]["text"])
    _write_json(
        context_path,
        {
            "session": payload["session"],
            "contract": payload["contract"],
            "defaults_panel": payload["defaults_panel"],
            "data_context": payload["data_context"],
            "lightweight_bundle": payload["lightweight_bundle"],
        },
    )
    _write_json(truth_sources_path, payload["truth_sources"])

    exported_files = [
        str(prompt_path),
        str(scaffold_path),
        str(lightweight_path),
        str(context_path),
        str(truth_sources_path),
    ]

    raw_sample_path: Path | None = None
    normalized_json_path: Path | None = None
    normalized_csv_path: Path | None = None
    project_context_path: Path | None = None

    project_path_text = payload["session"].get("project_path")
    if project_path_text:
        project_context_path = bundle_dir / "project_context.json"
        _write_json(
            project_context_path,
            {
                "project_id": payload["session"].get("project_id"),
                "project_path": project_path_text,
                "project_mode": payload["session"].get("project_mode"),
            },
        )
        exported_files.append(str(project_context_path))

    if effective_include_full_data and input_path_text and sheet is not None:
        input_path = Path(input_path_text)
        raw = read_raw_table_cached(input_path, sheet)
        raw_sample_path = bundle_dir / "data_sample.csv"
        _write_csv(raw_sample_path, raw.head(20))
        normalized = _normalized_frame_for_export(
            input_path,
            sheet,
            payload["data_context"].get("model"),
        )
        normalized_csv_path = bundle_dir / "normalized_full_data.csv"
        normalized_json_path = bundle_dir / "normalized_full_data.json"
        _write_csv(normalized_csv_path, normalized)
        _write_json(
            normalized_json_path,
            {
                "columns": [str(column) for column in normalized.columns.tolist()],
                "rows": [
                    {str(key): _clean_cell(value) for key, value in record.items()}
                    for record in normalized.to_dict(orient="records")
                ],
            },
        )
        exported_files.extend(
            [
                str(raw_sample_path),
                str(normalized_csv_path),
                str(normalized_json_path),
            ]
        )

    manifest = {
        "bundle_version": AI_BUNDLE_VERSION,
        "generated_at": payload["generated_at"],
        "session": {
            "id": payload["session"]["session_id"],
            "source": payload["session"]["session_source"],
            "input_path": payload["session"]["input_path"],
            "sheet": payload["session"]["sheet"],
            "template": payload["session"]["template"],
        },
        "project": {
            "id": payload["session"]["project_id"],
            "path": payload["session"]["project_path"],
            "mode": payload["session"]["project_mode"],
        },
        "contract": {
            "version": payload["contract"]["version"],
            "sha256": payload["contract"]["sha256"],
        },
        "includes_full_data": effective_include_full_data,
        "paths": {
            "bundle_dir": str(bundle_dir),
            "prompt": str(prompt_path),
            "scaffold": str(scaffold_path),
            "lightweight_context": str(lightweight_path),
            "context_summary": str(context_path),
            "truth_sources": str(truth_sources_path),
            "project_context": str(project_context_path) if project_context_path else None,
            "data_sample": str(raw_sample_path) if raw_sample_path else None,
            "normalized_csv": str(normalized_csv_path) if normalized_csv_path else None,
            "normalized_json": str(normalized_json_path) if normalized_json_path else None,
        },
    }
    _write_json(manifest_path, manifest)
    exported_files.append(str(manifest_path))

    zip_path = output_dir / f"{bundle_dir.name}.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for file_path in bundle_dir.rglob("*"):
            if file_path.is_file():
                archive.write(file_path, arcname=file_path.relative_to(bundle_dir))

    truth_sources = _truth_sources(
        input_path=Path(input_path_text) if input_path_text else None,
        sheet=sheet if input_path_text else None,
        inspection=None,
        project_path=Path(project_path_text) if project_path_text else None,
        bundle_path=bundle_dir,
    )
    return {
        "bundle_dir": str(bundle_dir),
        "zip_path": str(zip_path),
        "manifest_path": str(manifest_path),
        "exported_files": exported_files,
        "includes_full_data": effective_include_full_data,
        "truth_sources": truth_sources,
    }


__all__ = [
    "AI_BUNDLE_VERSION",
    "CODE_CONSOLE_RUN_TIMEOUT_SECONDS",
    "export_code_console_bundle",
    "generate_code_console_payload",
    "run_code_console_python",
]
