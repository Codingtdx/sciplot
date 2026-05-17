from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np

from src.rendering.source_table_preview import source_table_preview

NATIVE_PREVIEW_TEMPLATES = {
    "area_curve",
    "curve",
    "function_curve",
    "point_line",
    "scatter",
    "step_line",
}
DEFAULT_NATIVE_SCENE_SAMPLE_BUDGET = 2_000


def _numeric(value: object) -> float | None:
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return None
    return numeric if np.isfinite(numeric) else None


def _range(values: list[float]) -> list[float]:
    if not values:
        return [0.0, 1.0]
    low = float(min(values))
    high = float(max(values))
    return [low, high if high != low else low + 1.0]


def _enabled_axis_conflict(options: dict[str, Any]) -> bool:
    for key in ("extra_x_axis", "extra_y_axis"):
        payload = options.get(key)
        if isinstance(payload, dict) and payload.get("enabled"):
            return True
    for key in ("x_axis_breaks", "y_axis_breaks"):
        for item in options.get(key) or []:
            if isinstance(item, dict) and item.get("enabled", True):
                return True
    return False


def _pixel_points(
    samples: list[dict[str, float]],
    *,
    plot_area: dict[str, float],
    x_range: list[float],
    y_range: list[float],
) -> list[list[float]]:
    x_low, x_high = x_range
    y_low, y_high = y_range
    x_span = x_high - x_low or 1.0
    y_span = y_high - y_low or 1.0
    left = plot_area["x"]
    top = plot_area["y"]
    width = plot_area["width"]
    height = plot_area["height"]
    points: list[list[float]] = []
    for sample in samples:
        x_pixel = left + ((sample["x"] - x_low) / x_span) * width
        y_pixel = top + height - ((sample["y"] - y_low) / y_span) * height
        points.append([round(float(x_pixel), 3), round(float(y_pixel), 3)])
    return points


def _bbox(points: list[list[float]]) -> dict[str, float]:
    if not points:
        return {"x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0}
    x_values = [point[0] for point in points]
    y_values = [point[1] for point in points]
    left = min(x_values)
    top = min(y_values)
    return {
        "x": left,
        "y": top,
        "width": max(x_values) - left,
        "height": max(y_values) - top,
    }


def _series_object_kind(template: str) -> str:
    if template == "scatter":
        return "series_points"
    if template == "area_curve":
        return "series_area"
    if template == "step_line":
        return "series_step_line"
    return "series_line"


def _fallback_diagnostic(reason: str) -> dict[str, Any]:
    return {
        "status_code": "native_preview_fallback",
        "fallback_reason": reason,
        "message": "Backend bitmap/PDF preview is required.",
    }


def build_preview_scene(
    *,
    input_path: str | Path,
    sheet: str | int,
    template: str,
    options: dict[str, Any] | None = None,
    preview_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    path = Path(input_path)
    config_payload = preview_config or {}
    sample_budget = max(1, int(config_payload.get("native_scene_sample_budget") or DEFAULT_NATIVE_SCENE_SAMPLE_BUDGET))
    preview = source_table_preview(path, sheet=sheet, offset=0, limit=max(sample_budget + 10, 20))
    width = float(config_payload.get("pixel_width") or 800)
    height = float(config_payload.get("pixel_height") or 600)
    scale = float(config_payload.get("scale") or 1.0)
    rows = [list(row) for row in preview.rows]
    samples: list[dict[str, float]] = []
    for row in rows:
        if len(row) < 2:
            continue
        x_value = _numeric(row[0])
        y_value = _numeric(row[1])
        if x_value is None or y_value is None:
            continue
        samples.append({"x": x_value, "y": y_value})
    options_payload = options or {}
    fallback_reason: str | None = None
    if template not in NATIVE_PREVIEW_TEMPLATES:
        fallback_reason = "unsupported_template"
    elif not samples:
        fallback_reason = "missing_samples"
    elif len(samples) > sample_budget:
        fallback_reason = "sample_budget_exceeded"
    elif _enabled_axis_conflict(options_payload):
        fallback_reason = "advanced_axis_conflict"
    x_values = [sample["x"] for sample in samples]
    y_values = [sample["y"] for sample in samples]
    x_range = _range(x_values)
    y_range = _range(y_values)
    if not np.isfinite(x_range).all() or not np.isfinite(y_range).all():
        fallback_reason = "invalid_axes"
    native_supported = fallback_reason is None
    scene_samples = samples[:sample_budget]
    plot_area = {"x": width * 0.12, "y": height * 0.10, "width": width * 0.76, "height": height * 0.78}
    points = _pixel_points(scene_samples, plot_area=plot_area, x_range=x_range, y_range=y_range)
    series_object_kind = _series_object_kind(template)
    return {
        "scene_id": f"preview-scene:{path.name}:{sheet}:{template}",
        "template": template,
        "sheet": sheet,
        "native_supported": native_supported,
        "fallback_reason": fallback_reason,
        "graph_revision": 1,
        "figure": {"pixel_width": int(width), "pixel_height": int(height), "scale": scale},
        "plot_area": plot_area,
        "axes": [
            {
                "id": "axis:primary",
                "role": "primary",
                "bbox_pixels": plot_area,
                "x_scale": str(options_payload.get("xscale") or "linear"),
                "y_scale": str(options_payload.get("yscale") or "linear"),
                "x_range": x_range,
                "y_range": y_range,
                "x_reversed": False,
                "y_reversed": False,
                "column_refs": {"x": "col-0", "y": "col-1"},
            }
        ],
        "series": [
            {
                "id": "plot:series:0",
                "label": str(preview.column_headers[1] if len(preview.column_headers) > 1 else "Series"),
                "kind": template,
                "column_refs": {"x": "col-0", "y": "col-1"},
                "samples": scene_samples,
                "style_tokens": {
                    "style_preset": options_payload.get("style_preset") or "nature",
                    "palette_preset": options_payload.get("palette_preset"),
                    "visual_theme_id": options_payload.get("visual_theme_id"),
                },
                "hit_test": {"kind": "points" if template == "scatter" else "polyline", "tolerance": 12},
            }
        ]
        if samples
        else [],
        "objects": [
            {
                "id": "plot:series:0",
                "kind": series_object_kind,
                "axis_id": "axis:primary",
                "bbox_pixels": _bbox(points),
                "points": points,
                "payload_ref": {"type": "series", "id": "plot:series:0"},
                "operations": ["select", "quick_edit", "drag_offset", "copy_settings"],
            }
        ]
        if native_supported and samples
        else [],
        "overlays": [],
        "budgets": {
            "native_scene_samples": sample_budget,
            "source_points": len(samples),
            "render_timeout_ms": 10_000,
        },
        "diagnostics": []
        if native_supported
        else [_fallback_diagnostic(str(fallback_reason or "unknown"))],
    }


__all__ = ["DEFAULT_NATIVE_SCENE_SAMPLE_BUDGET", "NATIVE_PREVIEW_TEMPLATES", "build_preview_scene"]
