from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np

from src.rendering.source_table_preview import source_table_preview

NATIVE_PREVIEW_TEMPLATES = {
    "area_curve",
    "bar",
    "contour_field",
    "curve",
    "function_curve",
    "heatmap",
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


def build_preview_scene(
    *,
    input_path: str | Path,
    sheet: str | int,
    template: str,
    options: dict[str, Any] | None = None,
    preview_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    path = Path(input_path)
    preview = source_table_preview(path, sheet=sheet, offset=0, limit=DEFAULT_NATIVE_SCENE_SAMPLE_BUDGET)
    width = float((preview_config or {}).get("pixel_width") or 800)
    height = float((preview_config or {}).get("pixel_height") or 600)
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
    native_supported = template in NATIVE_PREVIEW_TEMPLATES and len(samples) <= DEFAULT_NATIVE_SCENE_SAMPLE_BUDGET
    fallback_reason = None if native_supported else "unsupported_template_or_budget"
    x_values = [sample["x"] for sample in samples]
    y_values = [sample["y"] for sample in samples]
    options_payload = options or {}
    return {
        "scene_id": f"preview-scene:{path.name}:{sheet}:{template}",
        "template": template,
        "sheet": sheet,
        "native_supported": native_supported,
        "fallback_reason": fallback_reason,
        "graph_revision": 1,
        "plot_area": {"x": width * 0.12, "y": height * 0.10, "width": width * 0.76, "height": height * 0.78},
        "axes": [
            {
                "id": "axis:primary",
                "role": "primary",
                "x_scale": str(options_payload.get("xscale") or "linear"),
                "y_scale": str(options_payload.get("yscale") or "linear"),
                "x_range": _range(x_values),
                "y_range": _range(y_values),
                "column_refs": {"x": "col-0", "y": "col-1"},
            }
        ],
        "series": [
            {
                "id": "plot:series:0",
                "label": str(preview.column_headers[1] if len(preview.column_headers) > 1 else "Series"),
                "kind": template,
                "column_refs": {"x": "col-0", "y": "col-1"},
                "samples": samples,
                "style_tokens": {
                    "style_preset": options_payload.get("style_preset") or "nature",
                    "palette_preset": options_payload.get("palette_preset"),
                    "visual_theme_id": options_payload.get("visual_theme_id"),
                },
                "hit_test": {"kind": "polyline", "tolerance": 12},
            }
        ]
        if samples
        else [],
        "objects": [
            {
                "id": "plot:series:0",
                "kind": "series",
                "payload_ref": {"type": "series", "id": "plot:series:0"},
                "operations": ["select", "quick_edit", "drag", "copy_settings"],
            }
        ]
        if samples
        else [],
        "overlays": [],
        "budgets": {
            "native_scene_samples": DEFAULT_NATIVE_SCENE_SAMPLE_BUDGET,
            "source_points": len(samples),
            "render_timeout_ms": 10_000,
        },
        "diagnostics": []
        if native_supported
        else [{"status_code": "native_preview_fallback", "message": "Backend bitmap/PDF preview is required."}],
    }


__all__ = ["DEFAULT_NATIVE_SCENE_SAMPLE_BUDGET", "NATIVE_PREVIEW_TEMPLATES", "build_preview_scene"]
