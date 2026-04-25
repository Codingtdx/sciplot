from __future__ import annotations

from dataclasses import replace
from pathlib import Path

from fastapi import HTTPException

from app.sidecar.schemas import RenderOptionsPayload
from src import plot_style
from src.core.application.render import (
    DEFAULT_SIZE_BY_TEMPLATE,
    ensure_input_path,
    normalize_input_path_text,
    resolve_render_options,
    resolve_template_id,
)
from src.rendering.fit_analysis import fit_options_from_payload
from src.rendering.models import RenderOptions


def normalize_path(path_text: str) -> Path:
    return ensure_input_path(normalize_input_path_text(path_text))


def options_from_payload(
    template: str,
    payload: RenderOptionsPayload,
    *,
    input_path: Path | None = None,
    sheet: str | int = 0,
):
    resolved_template = resolve_template_id(template, input_path=input_path, sheet=sheet)
    return resolve_render_options(
        template=template,
        size=payload.size or DEFAULT_SIZE_BY_TEMPLATE.get(resolved_template),
        xscale=payload.xscale,
        yscale=payload.yscale,
        reverse_x=payload.reverse_x,
        x_min=payload.x_min,
        x_max=payload.x_max,
        y_min=payload.y_min,
        y_max=payload.y_max,
        x_tick_density=payload.x_tick_density,
        y_tick_density=payload.y_tick_density,
        x_tick_edge_labels=payload.x_tick_edge_labels,
        y_tick_edge_labels=payload.y_tick_edge_labels,
        series_order=payload.series_order,
        x_label_override=payload.x_label_override,
        y_label_override=payload.y_label_override,
        baseline=payload.baseline,
        show_colorbar=payload.show_colorbar,
        style_preset=payload.style_preset or plot_style.DEFAULT_STYLE_PRESET,
        palette_preset=payload.palette_preset,
        use_sidecar=payload.use_sidecar,
        visual_theme_id=payload.visual_theme_id,
        extra_x_axis=payload.extra_x_axis.model_dump(mode="json") if payload.extra_x_axis else None,
        extra_y_axis=payload.extra_y_axis.model_dump(mode="json") if payload.extra_y_axis else None,
        x_axis_breaks=(
            [item.model_dump(mode="json") for item in payload.x_axis_breaks]
            if payload.x_axis_breaks
            else None
        ),
        y_axis_breaks=(
            [item.model_dump(mode="json") for item in payload.y_axis_breaks]
            if payload.y_axis_breaks
            else None
        ),
        reference_guides=(
            [item.model_dump(mode="json") for item in payload.reference_guides]
            if payload.reference_guides
            else None
        ),
        text_annotations=(
            [item.model_dump(mode="json") for item in payload.text_annotations]
            if payload.text_annotations
            else None
        ),
        shape_annotations=(
            [item.model_dump(mode="json") for item in payload.shape_annotations]
            if payload.shape_annotations
            else None
        ),
        analytical_layers=(
            [item.model_dump(mode="json") for item in payload.analytical_layers]
            if payload.analytical_layers
            else None
        ),
        data_variables=(
            [item.model_dump(mode="json") for item in payload.data_variables]
            if payload.data_variables
            else None
        ),
        data_transforms=(
            [item.model_dump(mode="json") for item in payload.data_transforms]
            if payload.data_transforms
            else None
        ),
        resolved_template_id=resolved_template,
    )


def render_options_from_payload(
    template: str,
    payload: RenderOptionsPayload,
    *,
    input_path: Path | None = None,
    sheet: str | int = 0,
    fit_options: object = None,
) -> RenderOptions:
    options = options_from_payload(template, payload, input_path=input_path, sheet=sheet)
    return replace(options, fit_options=fit_options_from_payload(fit_options).__dict__)


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
        "source-table-preview": "Could not load the source table preview.",
        "fit-analysis": "Could not analyze the current fit.",
        "save-project": "Could not save this project file.",
        "open-project": "Could not open this project file.",
        "data_studio_templates": "Could not load Data Studio templates.",
        "data_studio_template_preview": "Could not preview the Data Studio import template.",
        "data_studio_template_create": "Could not create the Data Studio template.",
        "data_studio_template_update": "Could not update the Data Studio template.",
        "data_studio_template_delete": "Could not delete the Data Studio template.",
        "data_studio_build_workbook": "Could not build the Data Studio workbook.",
        "data_studio_import_workbook": "Could not load this Data Studio workbook.",
        "data_studio_comparison_context": "Could not materialize the Data Studio comparison context.",
        "data_studio_comparison_preview": "Could not render the Data Studio comparison preview.",
        "data_studio_comparison_export": "Could not export the Data Studio comparison bundle.",
        "data_studio_session_normalize": "Could not normalize the Data Studio session payload.",
        "code-console-context": "Could not build the Code Console context.",
        "code-console-run": "Could not execute the Code Console run.",
        "composer-panel-thumbnail": "Could not generate the composer panel thumbnail.",
        "composer-preview": "Could not render the composer preview.",
        "composer-export": "Could not export the composer project.",
        "composer-three-up": "Could not build the three-up composer preset.",
        "composer-two-up-editorial": "Could not build the two-up editorial composer preset.",
        "composer-import-panels": "Could not import panels into the composer project.",
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
    "render_options_from_payload",
]
