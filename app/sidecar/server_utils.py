from __future__ import annotations

import hashlib
import importlib.metadata
import json
import os
import platform
import subprocess
import sys
from collections.abc import Mapping
from datetime import UTC, datetime
from pathlib import Path

from fastapi import HTTPException

from app.sidecar.schemas import CodeConsoleGenerateRequest, RenderOptionsPayload
from src import plot_style
from src.plot_contract import CONTRACT_PATH, load_plot_contract, template_contract
from src.rendering import DEFAULT_SIZE_BY_TEMPLATE, ensure_input_path, normalize_input_path_text, resolve_render_options
from src.rendering.style_composer import DEFAULT_STYLE_COMPOSER
from src.rendering.template_lifecycle import template_identity


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


def _as_mapping(value: object) -> Mapping[str, object]:
    return value if isinstance(value, Mapping) else {}


def _sha256_text(payload: object) -> str:
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _now_utc_iso() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _file_entry(path: Path) -> dict[str, object]:
    stat = path.stat()
    return {
        "path": str(path),
        "name": path.name,
        "size_bytes": int(stat.st_size),
        "mtime_ns": int(stat.st_mtime_ns),
        "sha256": _sha256_path(path),
    }


def _input_entry(input_path: Path, sheet: str | int) -> dict[str, object]:
    entry = _file_entry(input_path)
    entry["sheet"] = sheet
    return entry


def _runtime_versions() -> dict[str, object]:
    def _pkg(name: str) -> str | None:
        try:
            return importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            return None

    return {
        "python": {
            "version": platform.python_version(),
            "implementation": platform.python_implementation(),
        },
        "platform": platform.platform(),
        "packages": {
            "matplotlib": _pkg("matplotlib"),
            "numpy": _pkg("numpy"),
            "pandas": _pkg("pandas"),
            "seaborn": _pkg("seaborn"),
        },
    }


def _template_layer(requested_template_id: str) -> dict[str, object]:
    spec = template_contract(requested_template_id)
    identity = template_identity(requested_template_id)
    return {
        "id": requested_template_id,
        "requested_template_id": identity.requested_template_id,
        "canonical_id": identity.canonical_id,
        "role": identity.role,
        "lifecycle_policy": identity.lifecycle_policy,
        "implementation_id": identity.implementation_id,
        "default_size": spec.default_size,
        "allowed_sizes": list(spec.allowed_sizes),
        "available_styles": list(spec.available_styles),
        "available_palettes": list(spec.available_palettes),
    }


def _mapping_layer(
    requested_template_id: str,
    canonical_template_id: str,
    inspection: object,
) -> dict[str, object]:
    inspection_data = _as_mapping(inspection)
    recommendations = inspection_data.get("recommendations")
    matched_mapping: dict[str, object] = {}
    if isinstance(recommendations, list):
        for candidate in recommendations:
            candidate_data = _as_mapping(candidate)
            if candidate_data.get("template_id") == requested_template_id:
                inferred = candidate_data.get("inferred_mapping")
                if isinstance(inferred, Mapping):
                    matched_mapping = {str(key): value for key, value in inferred.items()}
                break
    recommendation_template = None
    recommendation_payload = inspection_data.get("recommendation")
    if isinstance(recommendation_payload, Mapping):
        recommendation_template = recommendation_payload.get("template")
    return {
        "detected_model": inspection_data.get("model"),
        "selected_template": requested_template_id,
        "requested_template_id": requested_template_id,
        "selected_implementation_id": canonical_template_id,
        "canonical_id": canonical_template_id,
        "recommendation_template": recommendation_template,
        "inferred_mapping": matched_mapping,
        "source": "inspection.recommendations",
    }


def _theme_layer(options: object) -> dict[str, object]:
    option_data = _as_mapping(options)
    style_preset = str(option_data.get("style_preset") or plot_style.DEFAULT_STYLE_PRESET)
    palette_preset = str(option_data.get("palette_preset") or plot_style.DEFAULT_PALETTE_PRESET)
    visual_theme_raw = option_data.get("visual_theme_id")
    visual_theme_id = str(visual_theme_raw) if isinstance(visual_theme_raw, str) and visual_theme_raw.strip() else None
    bundle = DEFAULT_STYLE_COMPOSER.compose(style_preset, visual_theme_id)
    return {
        "publication_profile_id": bundle.publication_profile_id,
        "style_preset": style_preset,
        "palette_preset": palette_preset,
        "visual_theme_id": visual_theme_id,
        "soft_overrides": bundle.resolved_soft,
        "blocked_soft_overrides": list(bundle.blocked_soft_keys),
        "protected_keys": list(bundle.protected_keys),
    }


def _contract_layer() -> dict[str, object]:
    contract = load_plot_contract()
    return {
        "path": str(CONTRACT_PATH.resolve()),
        "version": contract.version,
        "sha256": _sha256_path(CONTRACT_PATH),
    }


def _run_fingerprint_payload(
    *,
    input_entry: dict[str, object],
    sheet: str | int,
    requested_template_id: str,
    canonical_template_id: str,
    options: object,
    output_entries: list[dict[str, object]],
    preview_entries: list[dict[str, object]],
    artifact_entries: list[dict[str, object]],
    contract_layer: dict[str, object],
) -> dict[str, object]:
    return {
        "input_sha256": input_entry.get("sha256"),
        "sheet": sheet,
        "requested_template_id": requested_template_id,
        "canonical_template_id": canonical_template_id,
        "options": _as_mapping(options),
        "output_sha256": [entry.get("sha256") for entry in output_entries],
        "preview_sha256": [entry.get("sha256") for entry in preview_entries],
        "artifact_sha256": [entry.get("sha256") for entry in artifact_entries],
        "contract_sha256": contract_layer.get("sha256"),
    }


def bundle_manifest_payload(
    *,
    input_path: Path,
    sheet: str | int,
    requested_template_id: str,
    canonical_template_id: str,
    output_dir: Path,
    outputs: list[Path],
    preview_outputs: list[Path],
    artifact_paths: list[Path],
    submission_report: object,
    inspection: object,
    options: object,
) -> dict[str, object]:
    generated_at = _now_utc_iso()
    input_data = _input_entry(input_path, sheet)
    output_entries = [_file_entry(path) for path in outputs]
    preview_entries = [_file_entry(path) for path in preview_outputs]
    artifact_entries = [_file_entry(path) for path in artifact_paths]
    template_data = _template_layer(requested_template_id)
    mapping_data = _mapping_layer(requested_template_id, canonical_template_id, inspection)
    theme_data = _theme_layer(options)
    contract_data = _contract_layer()
    run_fingerprint = _sha256_text(
        _run_fingerprint_payload(
            input_entry=input_data,
            sheet=sheet,
            requested_template_id=requested_template_id,
            canonical_template_id=canonical_template_id,
            options=options,
            output_entries=output_entries,
            preview_entries=preview_entries,
            artifact_entries=artifact_entries,
            contract_layer=contract_data,
        )
    )
    return {
        "bundle_version": 2,
        "generated_at": generated_at,
        "input_path": str(input_path),
        "sheet": sheet,
        "template": requested_template_id,
        "requested_template_id": requested_template_id,
        "canonical_template_id": canonical_template_id,
        "output_dir": str(output_dir),
        "outputs": [str(path) for path in outputs],
        "preview_outputs": [str(path) for path in preview_outputs],
        "artifact_paths": [str(path) for path in artifact_paths],
        "normalized_options": options,
        "inspection": inspection,
        "submission_report": submission_report,
        "template_layer": template_data,
        "mapping_layer": mapping_data,
        "theme_layer": theme_data,
        "contract_layer": contract_data,
        "reproducibility": {
            "run_fingerprint": run_fingerprint,
            "runtime": _runtime_versions(),
            "input": input_data,
            "outputs": output_entries,
            "preview_outputs": preview_entries,
            "artifacts": artifact_entries,
        },
    }
