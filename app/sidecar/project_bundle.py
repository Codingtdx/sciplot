from __future__ import annotations

import hashlib
import json
import mimetypes
import tempfile
import zipfile
from collections.abc import Mapping
from datetime import UTC, datetime
from pathlib import Path

from app.sidecar.schemas_render import (
    OpenProjectResponse,
    PlotProjectPayload,
    PlotProjectSourceProvenancePayload,
    ProjectBundlePayload,
    RenderOptionsPayload,
    SaveProjectResponse,
)
from app.sidecar.server_utils import normalize_path, options_from_payload
from src.infrastructure.persistence.plot_projects import prepare_managed_plot_project_restore_dir
from src.rendering.constants import DEFAULT_SIZE_BY_TEMPLATE
from src.rendering.options import validate_template_name
from src.rendering.template_lifecycle import resolve_template_id

_PROJECT_VERSION = 1
_PROJECT_MEMBER = "project.json"
_ARTIFACT_MANIFEST_MEMBER = "artifacts/manifest.json"
_SOURCE_DIR = "sources/primary"


def _mapping(value: object) -> Mapping[str, object] | None:
    if isinstance(value, Mapping):
        return value
    return None


def _int_value(value: object, default: int) -> int:
    if value is None:
        return default
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return default


def _optional_int(value: object) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return None


def _sheet_value(value: object) -> str | int:
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.isdigit():
        return int(value)
    cleaned = str(value).strip()
    return int(cleaned) if cleaned.isdigit() else cleaned


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _media_type_for(path: Path) -> str | None:
    media_type, _ = mimetypes.guess_type(path.name)
    return media_type


def _default_provenance(source_path: Path | None) -> PlotProjectSourceProvenancePayload:
    if source_path is None:
        return PlotProjectSourceProvenancePayload(saved_at=datetime.now(UTC).isoformat())
    return PlotProjectSourceProvenancePayload(
        original_input_path=str(source_path),
        saved_input_mtime_ns=source_path.stat().st_mtime_ns if source_path.exists() else None,
        saved_at=datetime.now(UTC).isoformat(),
    )


def _normalize_render_options(
    *,
    template_id: str,
    render_options: object,
    input_path: Path,
    sheet: str | int,
) -> RenderOptionsPayload:
    payload = RenderOptionsPayload.model_validate(render_options or {})
    resolved_template_id = resolve_template_id(template_id, input_path=input_path, sheet=sheet)
    validate_template_name(resolved_template_id)
    resolved_options = options_from_payload(
        template_id,
        payload,
        input_path=input_path,
        sheet=sheet,
    )
    return RenderOptionsPayload(
        size=payload.size or DEFAULT_SIZE_BY_TEMPLATE.get(resolved_template_id),
        xscale=resolved_options.xscale,
        yscale=resolved_options.yscale,
        reverse_x=resolved_options.reverse_x,
        x_min=payload.x_min,
        x_max=payload.x_max,
        y_min=payload.y_min,
        y_max=payload.y_max,
        x_tick_density=resolved_options.x_tick_density,
        y_tick_density=resolved_options.y_tick_density,
        x_tick_edge_labels=resolved_options.x_tick_edge_labels,
        y_tick_edge_labels=resolved_options.y_tick_edge_labels,
        series_order=list(resolved_options.series_order) if resolved_options.series_order is not None else None,
        x_label_override=resolved_options.x_label_override,
        y_label_override=resolved_options.y_label_override,
        baseline=resolved_options.baseline,
        show_colorbar=resolved_options.show_colorbar,
        style_preset=resolved_options.style_preset,
        palette_preset=resolved_options.palette_preset,
        use_sidecar=payload.use_sidecar,
        visual_theme_id=resolved_options.visual_theme_id,
    )


def normalize_project_payload(
    payload: Mapping[str, object],
    *,
    source_path: Path,
) -> ProjectBundlePayload:
    plot_map = _mapping(payload.get("plot"))
    if plot_map is None:
        raise ValueError("Project payload must include a plot section.")
    template_id = resolve_template_id(str(plot_map.get("selected_template_id", "")).strip())
    validate_template_name(template_id)
    sheet = _sheet_value(plot_map.get("sheet", 0))
    normalized_options = _normalize_render_options(
        template_id=template_id,
        render_options=plot_map.get("render_options"),
        input_path=source_path,
        sheet=sheet,
    )
    provenance_map = _mapping(plot_map.get("source_provenance")) or {}
    provenance = PlotProjectSourceProvenancePayload(
        original_input_path=(
            str(provenance_map.get("original_input_path")).strip()
            if provenance_map.get("original_input_path") is not None
            else str(source_path)
        ),
        saved_input_mtime_ns=(
            _optional_int(provenance_map.get("saved_input_mtime_ns")) or source_path.stat().st_mtime_ns
        ),
        saved_at=(
            str(provenance_map.get("saved_at")).strip()
            if provenance_map.get("saved_at") is not None
            else datetime.now(UTC).isoformat()
        ),
    )
    embedded_source_relpath = (
        str(plot_map.get("embedded_source_relpath")).strip()
        if plot_map.get("embedded_source_relpath") is not None
        else f"{_SOURCE_DIR}/{source_path.name}"
    )
    source_filename = (
        str(plot_map.get("source_filename")).strip()
        if plot_map.get("source_filename") is not None
        else source_path.name
    )
    source_sha256 = (
        str(plot_map.get("source_sha256")).strip()
        if plot_map.get("source_sha256") is not None
        else _sha256_bytes(source_path.read_bytes())
    )
    plot_payload = PlotProjectPayload(
        session_kind="plot",
        source_filename=source_filename or source_path.name,
        source_media_type=(
            str(plot_map.get("source_media_type")).strip()
            if plot_map.get("source_media_type") is not None
            else _media_type_for(source_path)
        ),
        embedded_source_relpath=embedded_source_relpath or f"{_SOURCE_DIR}/{source_path.name}",
        source_sha256=source_sha256,
        sheet=sheet,
        selected_template_id=template_id,
        render_options=normalized_options,
        project_display_name=(
            str(plot_map.get("project_display_name")).strip()
            if plot_map.get("project_display_name") is not None
            else None
        ),
        source_provenance=provenance,
    )
    artifacts_value = payload.get("artifacts")
    artifacts = dict(_mapping(artifacts_value) or {})
    if not artifacts.get("manifest_relpath"):
        artifacts["manifest_relpath"] = _ARTIFACT_MANIFEST_MEMBER
    return ProjectBundlePayload(
        version=_int_value(payload.get("version"), _PROJECT_VERSION),
        selected_workbench="plot",
        plot=plot_payload,
        data_studio=None,
        composer=None,
        code_console=None,
        artifacts=artifacts,
    )


def _bundle_manifest_payload(project_payload: ProjectBundlePayload, *, source_size_bytes: int) -> dict[str, object]:
    plot = project_payload.plot
    if plot is None:
        raise ValueError("Project payload is missing the plot section.")
    return {
        "version": project_payload.version,
        "kind": "plot_project_bundle",
        "saved_at": datetime.now(UTC).isoformat(),
        "entries": [
            {"path": _PROJECT_MEMBER, "kind": "project_payload"},
            {
                "path": plot.embedded_source_relpath,
                "kind": "primary_source",
                "sha256": plot.source_sha256,
                "size_bytes": source_size_bytes,
            },
        ],
    }


def save_project_bundle(
    *,
    project_path: Path,
    source_path: Path,
    payload: ProjectBundlePayload,
) -> SaveProjectResponse:
    source_bytes = source_path.read_bytes()
    normalized_payload = normalize_project_payload(payload.model_dump(mode="json"), source_path=source_path)
    plot_payload = normalized_payload.plot
    if plot_payload is None:
        raise ValueError("Project payload is missing the plot section.")
    normalized_plot_payload = plot_payload.model_copy(
        update={
            "source_filename": source_path.name,
            "source_media_type": _media_type_for(source_path),
            "embedded_source_relpath": f"{_SOURCE_DIR}/{source_path.name}",
            "source_sha256": _sha256_bytes(source_bytes),
            "project_display_name": plot_payload.project_display_name or project_path.stem,
            "source_provenance": _default_provenance(source_path).model_copy(
                update={
                    "original_input_path": plot_payload.source_provenance.original_input_path or str(source_path),
                    "saved_input_mtime_ns": source_path.stat().st_mtime_ns,
                }
            ),
        }
    )
    saved_payload = normalized_payload.model_copy(
        update={
            "plot": normalized_plot_payload,
            "artifacts": {
                **normalized_payload.artifacts,
                "manifest_relpath": _ARTIFACT_MANIFEST_MEMBER,
            },
        }
    )
    project_json = json.dumps(
        saved_payload.model_dump(mode="json"),
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    ).encode("utf-8")
    manifest_json = json.dumps(
        _bundle_manifest_payload(saved_payload, source_size_bytes=len(source_bytes)),
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    ).encode("utf-8")
    project_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        prefix=f"{project_path.stem}_",
        suffix=project_path.suffix or ".sciplotgod",
        dir=project_path.parent,
        delete=False,
    ) as temporary_file:
        temp_path = Path(temporary_file.name)
    try:
        with zipfile.ZipFile(temp_path, mode="w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(_PROJECT_MEMBER, project_json)
            archive.writestr(normalized_plot_payload.embedded_source_relpath, source_bytes)
            archive.writestr(_ARTIFACT_MANIFEST_MEMBER, manifest_json)
        temp_path.replace(project_path)
    finally:
        temp_path.unlink(missing_ok=True)
    return SaveProjectResponse(
        project_path=str(project_path),
        payload=saved_payload,
    )


def open_project_bundle(*, project_path: Path) -> OpenProjectResponse:
    with zipfile.ZipFile(project_path, mode="r") as archive:
        try:
            raw_payload = json.loads(archive.read(_PROJECT_MEMBER).decode("utf-8"))
        except KeyError as exc:
            raise ValueError("Project bundle is missing project.json.") from exc
        plot_map = _mapping(_mapping(raw_payload).get("plot") if _mapping(raw_payload) is not None else None)
        if plot_map is None:
            raise ValueError("Project bundle is missing the plot section.")
        embedded_source_relpath = str(plot_map.get("embedded_source_relpath", "")).strip()
        if not embedded_source_relpath:
            raise ValueError("Project bundle is missing the embedded source path.")
        try:
            source_bytes = archive.read(embedded_source_relpath)
        except KeyError as exc:
            raise ValueError("Project bundle is missing the embedded source file.") from exc
        expected_sha256 = str(plot_map.get("source_sha256", "")).strip()
        actual_sha256 = _sha256_bytes(source_bytes)
        if expected_sha256 and actual_sha256 != expected_sha256:
            raise ValueError("Embedded source checksum does not match the saved project metadata.")
        source_filename = str(plot_map.get("source_filename", "")).strip() or Path(embedded_source_relpath).name
        restore_dir = prepare_managed_plot_project_restore_dir(project_path, source_sha256=actual_sha256)
        restored_source_path = restore_dir / source_filename
        restored_source_path.write_bytes(source_bytes)
    normalized_payload = normalize_project_payload(raw_payload, source_path=restored_source_path)
    plot_payload = normalized_payload.plot
    if plot_payload is None:
        raise ValueError("Project bundle is missing the plot section.")
    normalized_plot_payload = plot_payload.model_copy(
        update={
            "source_filename": source_filename,
            "source_media_type": plot_payload.source_media_type or _media_type_for(restored_source_path),
            "embedded_source_relpath": embedded_source_relpath,
            "source_sha256": actual_sha256,
            "project_display_name": plot_payload.project_display_name or project_path.stem,
        }
    )
    return OpenProjectResponse(
        project_path=str(project_path),
        restored_source_path=str(restored_source_path),
        payload=normalized_payload.model_copy(update={"plot": normalized_plot_payload}),
    )


def normalize_project_path(path_text: str) -> Path:
    path = normalize_path(path_text)
    if path.suffix.lower() != ".sciplotgod":
        raise ValueError("Project file must use the .sciplotgod extension.")
    return path


__all__ = [
    "normalize_project_path",
    "normalize_project_payload",
    "open_project_bundle",
    "save_project_bundle",
]
