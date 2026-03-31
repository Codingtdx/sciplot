from __future__ import annotations

from pathlib import Path

from fastapi import HTTPException

from app.sidecar.schemas import RenderOptionsPayload
from src import plot_style
from src.core.application.render import (
    DEFAULT_SIZE_BY_TEMPLATE,
    ensure_input_path,
    normalize_input_path_text,
    resolve_render_options,
)


def normalize_path(path_text: str) -> Path:
    return ensure_input_path(normalize_input_path_text(path_text))


def options_from_payload(template: str, payload: RenderOptionsPayload):
    return resolve_render_options(
        template=template,
        size=payload.size or DEFAULT_SIZE_BY_TEMPLATE[template],
        xscale=payload.xscale,
        yscale=payload.yscale,
        reverse_x=payload.reverse_x,
        x_min=payload.x_min,
        x_max=payload.x_max,
        y_min=payload.y_min,
        y_max=payload.y_max,
        series_order=payload.series_order,
        x_label_override=payload.x_label_override,
        y_label_override=payload.y_label_override,
        baseline=payload.baseline,
        show_colorbar=payload.show_colorbar,
        style_preset=payload.style_preset or plot_style.DEFAULT_STYLE_PRESET,
        palette_preset=payload.palette_preset,
        use_sidecar=payload.use_sidecar,
        visual_theme_id=payload.visual_theme_id,
    )


def contextual_error_message(context: str, exc: Exception) -> str:
    message = str(exc).strip() or "Unexpected error."
    lower = message.lower()
    if "no such file or directory" in lower or "does not exist" in lower:
        return (
            f"{message} Confirm that the selected file or folder still exists and that the desktop app "
            "can access it."
        )
    if "template `" in message and "does not support" in message:
        return message
    if "non-numeric values" in lower:
        return f"{message} Keep notes outside the plotted data region and leave only numeric values inside it."
    prefixes = {
        "inspect": "Could not inspect this input file.",
        "preflight": "Could not finish the export preflight.",
        "preview": "Could not render the live preview.",
        "export": "Could not export the submission bundle.",
        "tensile_preprocess": "Could not build the tensile workbook.",
        "tensile_workbook": "Could not inspect this tensile workbook.",
        "tensile_compare": "Could not export the tensile comparison bundle.",
    }
    prefix = prefixes.get(context)
    if prefix is None:
        return message
    return f"{prefix} {message}"


def http_bad_request(context: str, exc: Exception) -> HTTPException:
    return HTTPException(status_code=400, detail=contextual_error_message(context, exc))


__all__ = [
    "contextual_error_message",
    "http_bad_request",
    "normalize_path",
    "options_from_payload",
]
