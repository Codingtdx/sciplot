from __future__ import annotations

import hashlib
import importlib.metadata
import json
import platform
from collections.abc import Mapping
from datetime import UTC, datetime
from pathlib import Path

from src import plot_style
from src.core.application.render import template_identity
from src.plot_contract import CONTRACT_PATH, load_plot_contract, template_contract
from src.rendering.style_composer import DEFAULT_STYLE_COMPOSER


def preview_artifact_path(output_dir: Path, filename: str) -> Path:
    return output_dir / f"{Path(filename).stem}.preview.png"


def write_json_artifact(output_dir: Path, filename: str, payload: object) -> Path:
    path = output_dir / filename
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def as_mapping(value: object) -> Mapping[str, object]:
    return value if isinstance(value, Mapping) else {}


def sha256_text(payload: object) -> str:
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def now_utc_iso() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def file_entry(path: Path) -> dict[str, object]:
    stat = path.stat()
    return {
        "path": str(path),
        "name": path.name,
        "size_bytes": int(stat.st_size),
        "mtime_ns": int(stat.st_mtime_ns),
        "sha256": sha256_path(path),
    }


def input_entry(input_path: Path, sheet: str | int) -> dict[str, object]:
    entry = file_entry(input_path)
    entry["sheet"] = sheet
    return entry


def runtime_versions() -> dict[str, object]:
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


def template_layer(requested_template_id: str) -> dict[str, object]:
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


def mapping_layer(
    requested_template_id: str,
    canonical_template_id: str,
    inspection: object,
) -> dict[str, object]:
    inspection_data = as_mapping(inspection)
    recommendations = inspection_data.get("recommendations")
    matched_mapping: dict[str, object] = {}
    if isinstance(recommendations, list):
        for candidate in recommendations:
            candidate_data = as_mapping(candidate)
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


def theme_layer(options: object) -> dict[str, object]:
    option_data = as_mapping(options)
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


def contract_layer() -> dict[str, object]:
    contract = load_plot_contract()
    return {
        "path": str(CONTRACT_PATH.resolve()),
        "version": contract.version,
        "sha256": sha256_path(CONTRACT_PATH),
    }


def run_fingerprint_payload(
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
        "options": as_mapping(options),
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
    input_data = input_entry(input_path, sheet)
    output_entries = [file_entry(path) for path in outputs]
    preview_entries = [file_entry(path) for path in preview_outputs]
    artifact_entries = [file_entry(path) for path in artifact_paths]
    contract_data = contract_layer()
    return {
        "bundle_version": 2,
        "generated_at": now_utc_iso(),
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
        "template_layer": template_layer(requested_template_id),
        "mapping_layer": mapping_layer(requested_template_id, canonical_template_id, inspection),
        "theme_layer": theme_layer(options),
        "contract_layer": contract_data,
        "reproducibility": {
            "run_fingerprint": sha256_text(
                run_fingerprint_payload(
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
            ),
            "runtime": runtime_versions(),
            "input": input_data,
            "outputs": output_entries,
            "preview_outputs": preview_entries,
            "artifacts": artifact_entries,
        },
    }


__all__ = [
    "bundle_manifest_payload",
    "preview_artifact_path",
    "write_json_artifact",
]
