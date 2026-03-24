from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from fastapi import HTTPException

from app.sidecar.schemas import CodeConsoleGenerateRequest, RenderOptionsPayload
from src import plot_style
from src.rendering import DEFAULT_SIZE_BY_TEMPLATE, ensure_input_path, normalize_input_path_text, resolve_render_options


def normalize_path(path_text: str) -> Path:
    return ensure_input_path(normalize_input_path_text(path_text))


def optional_input_path(path_text: str | None) -> Path | None:
    if path_text is None or path_text.strip() == "":
        return None
    return normalize_path(path_text)


def optional_project_path(path_text: str | None) -> Path | None:
    if path_text is None or path_text.strip() == "":
        return None
    return Path(path_text).expanduser()


def options_from_payload(template: str, payload: RenderOptionsPayload):
    return resolve_render_options(
        template=template,
        size=payload.size or DEFAULT_SIZE_BY_TEMPLATE[template],
        xscale=payload.xscale,
        yscale=payload.yscale,
        reverse_x=payload.reverse_x,
        baseline=payload.baseline,
        show_colorbar=payload.show_colorbar,
        style_preset=payload.style_preset or plot_style.DEFAULT_STYLE_PRESET,
        palette_preset=payload.palette_preset,
        use_sidecar=payload.use_sidecar,
        visual_theme_id=payload.visual_theme_id,
    )


def code_console_payload_options(request: CodeConsoleGenerateRequest) -> RenderOptionsPayload:
    payload = request.options or RenderOptionsPayload()
    return RenderOptionsPayload(
        size=payload.size or request.size,
        xscale=payload.xscale,
        yscale=payload.yscale,
        reverse_x=payload.reverse_x,
        baseline=payload.baseline,
        show_colorbar=payload.show_colorbar,
        style_preset=payload.style_preset or request.style_preset or plot_style.DEFAULT_STYLE_PRESET,
        palette_preset=payload.palette_preset
        or request.palette_preset
        or plot_style.DEFAULT_PALETTE_PRESET,
        use_sidecar=payload.use_sidecar,
        visual_theme_id=payload.visual_theme_id,
    )


def resolved_code_console_options(request: CodeConsoleGenerateRequest):
    return options_from_payload(request.base_template, code_console_payload_options(request))


def preview_artifact_path(output_dir: Path, filename: str) -> Path:
    return output_dir / f"{Path(filename).stem}.preview.png"


def write_json_artifact(output_dir: Path, filename: str, payload: object) -> Path:
    path = output_dir / filename
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return path


def contextual_error_message(context: str, exc: Exception) -> str:
    message = str(exc).strip() or "Unexpected error."
    lower = message.lower()
    if message in {
        "The project file is not valid JSON.",
        "This is not a recognizable SciPlot God project file.",
    }:
        return message
    if message.startswith("Invalid project file field:"):
        return message
    if "only support version: 2" in message:
        return message
    if "no such file or directory" in lower or "does not exist" in lower:
        return (
            f"{message} Confirm that the selected file or folder still exists and that the desktop app "
            "can access it."
        )
    if "not valid json" in lower:
        return message
    if "template `" in message and "does not support" in message:
        return message
    if "non-numeric values" in lower:
        return f"{message} Keep notes outside the plotted data region and leave only numeric values inside it."
    prefixes = {
        "inspect": "Could not inspect this input file.",
        "preflight": "Could not finish the export preflight.",
        "preview": "Could not render the live preview.",
        "export": "Could not export the submission bundle.",
        "code_console_generate": "Could not build the Code Console prompt context.",
        "code_console_export": "Could not export the Code Console context bundle.",
        "code_console_run": "Could not run this repo-native Python snippet.",
        "data_template": "Could not build the requested data template.",
        "open_path": "Could not open the selected folder.",
        "save_project": "Could not save this SciPlot God project.",
        "open_project": "Could not open this SciPlot God project.",
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


def open_path_with_host(target: Path) -> None:
    if sys.platform == "darwin":
        subprocess.run(["open", str(target)], check=True)
        return
    if os.name == "nt" and hasattr(os, "startfile"):
        os.startfile(str(target))
        return
    subprocess.run(["xdg-open", str(target)], check=True)


def bundle_manifest_payload(
    *,
    input_path: Path,
    sheet: str | int,
    template: str,
    output_dir: Path,
    outputs: list[Path],
    preview_outputs: list[Path],
    artifact_paths: list[Path],
    submission_report: object,
    inspection: object,
    options: object,
) -> dict[str, object]:
    return {
        "input_path": str(input_path),
        "sheet": sheet,
        "template": template,
        "output_dir": str(output_dir),
        "outputs": [str(path) for path in outputs],
        "preview_outputs": [str(path) for path in preview_outputs],
        "artifact_paths": [str(path) for path in artifact_paths],
        "normalized_options": options,
        "inspection": inspection,
        "submission_report": submission_report,
    }
