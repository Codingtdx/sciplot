from __future__ import annotations

import hashlib
import json
import mimetypes
import tempfile
import zipfile
from collections.abc import Iterable, Mapping
from datetime import UTC, datetime
from pathlib import Path

from app.sidecar.schemas_render import (
    AnalyticalLayerPayload,
    AxisBreakPayload,
    DataStudioProjectPayload,
    DataStudioProjectWorkbookPayload,
    ExtraAxisPayload,
    FitOptionsPayload,
    OpenProjectResponse,
    PlotProjectPayload,
    PlotProjectSourceProvenancePayload,
    ProjectBundlePayload,
    ReferenceGuidePayload,
    RenderOptionsPayload,
    SaveProjectResponse,
    ShapeAnnotationPayload,
    TextAnnotationPayload,
)
from app.sidecar.server_utils import normalize_path, options_from_payload
from src.data_studio.models import serialize_model
from src.data_studio.session import normalize_session_payload as normalize_data_studio_session_payload
from src.infrastructure.persistence.plot_projects import prepare_managed_project_restore_dir
from src.rendering.constants import DEFAULT_SIZE_BY_TEMPLATE
from src.rendering.fit_analysis import normalize_fit_options_payload
from src.rendering.options import validate_template_name
from src.rendering.template_lifecycle import resolve_template_id

_PROJECT_VERSION = 1
_PROJECT_MEMBER = "project.json"
_ARTIFACT_MANIFEST_MEMBER = "artifacts/manifest.json"
_PLOT_SOURCE_DIR = "sources/plot/primary"
_LEGACY_PLOT_SOURCE_DIR = "sources/primary"
_DATA_STUDIO_WORKBOOK_DIR = "sources/data_studio/workbooks"
_SUPPORTED_WORKBENCHES = {"plot", "data_studio"}


def _mapping(value: object) -> Mapping[str, object] | None:
    if isinstance(value, Mapping):
        return value
    return None


def _iter_values(value: object) -> tuple[object, ...]:
    if isinstance(value, Iterable) and not isinstance(value, (str, bytes, bytearray, Mapping)):
        return tuple(value)
    return ()


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


def _string_or_none(value: object) -> str | None:
    if value is None:
        return None
    cleaned = str(value).strip()
    return cleaned or None


def _sheet_value(value: object) -> str | int:
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.isdigit():
        return int(value)
    cleaned = str(value).strip()
    return int(cleaned) if cleaned.isdigit() else cleaned


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _media_type_for(path: Path) -> str | None:
    media_type, _ = mimetypes.guess_type(path.name)
    return media_type


def _default_plot_provenance(source_path: Path | None, *, saved_at: str) -> PlotProjectSourceProvenancePayload:
    if source_path is None:
        return PlotProjectSourceProvenancePayload(saved_at=saved_at)
    return PlotProjectSourceProvenancePayload(
        original_input_path=str(source_path),
        saved_input_mtime_ns=source_path.stat().st_mtime_ns if source_path.exists() else None,
        saved_at=saved_at,
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
        extra_x_axis=(
            ExtraAxisPayload.model_validate(resolved_options.extra_x_axis)
            if resolved_options.extra_x_axis is not None
            else None
        ),
        extra_y_axis=(
            ExtraAxisPayload.model_validate(resolved_options.extra_y_axis)
            if resolved_options.extra_y_axis is not None
            else None
        ),
        x_axis_breaks=(
            [AxisBreakPayload.model_validate(item) for item in resolved_options.x_axis_breaks]
            if resolved_options.x_axis_breaks is not None
            else None
        ),
        y_axis_breaks=(
            [AxisBreakPayload.model_validate(item) for item in resolved_options.y_axis_breaks]
            if resolved_options.y_axis_breaks is not None
            else None
        ),
        reference_guides=(
            [ReferenceGuidePayload.model_validate(item) for item in resolved_options.reference_guides]
            if resolved_options.reference_guides is not None
            else None
        ),
        text_annotations=(
            [TextAnnotationPayload.model_validate(item) for item in resolved_options.text_annotations]
            if resolved_options.text_annotations is not None
            else None
        ),
        shape_annotations=(
            [ShapeAnnotationPayload.model_validate(item) for item in resolved_options.shape_annotations]
            if resolved_options.shape_annotations is not None
            else None
        ),
        analytical_layers=(
            [AnalyticalLayerPayload.model_validate(item) for item in resolved_options.analytical_layers]
            if resolved_options.analytical_layers is not None
            else None
        ),
    )


def _normalize_selected_workbench(payload: Mapping[str, object]) -> str:
    selected = _string_or_none(payload.get("selected_workbench"))
    if selected in _SUPPORTED_WORKBENCHES:
        return selected
    if _mapping(payload.get("data_studio")) is not None and _mapping(payload.get("plot")) is None:
        return "data_studio"
    if _mapping(payload.get("plot")) is not None:
        return "plot"
    raise ValueError("Project payload must include a supported workbench.")


def _normalize_plot_project_payload(
    plot_map: Mapping[str, object],
    *,
    source_path: Path,
) -> PlotProjectPayload:
    template_id = resolve_template_id(str(plot_map.get("selected_template_id", "")).strip())
    validate_template_name(template_id)
    sheet = _sheet_value(plot_map.get("sheet", 0))
    normalized_options = _normalize_render_options(
        template_id=template_id,
        render_options=plot_map.get("render_options"),
        input_path=source_path,
        sheet=sheet,
    )
    normalized_fit_options = FitOptionsPayload.model_validate(
        normalize_fit_options_payload(plot_map.get("fit_options"))
    )
    provenance_map = _mapping(plot_map.get("source_provenance")) or {}
    provenance = PlotProjectSourceProvenancePayload(
        original_input_path=_string_or_none(provenance_map.get("original_input_path")) or str(source_path),
        saved_input_mtime_ns=(
            _optional_int(provenance_map.get("saved_input_mtime_ns")) or source_path.stat().st_mtime_ns
        ),
        saved_at=_string_or_none(provenance_map.get("saved_at")),
    )
    embedded_source_relpath = (
        _string_or_none(plot_map.get("embedded_source_relpath"))
        or f"{_PLOT_SOURCE_DIR}/{source_path.name}"
    )
    if embedded_source_relpath.startswith(f"{_LEGACY_PLOT_SOURCE_DIR}/"):
        embedded_source_relpath = f"{_PLOT_SOURCE_DIR}/{Path(embedded_source_relpath).name}"
    return PlotProjectPayload(
        session_kind="plot",
        source_filename=_string_or_none(plot_map.get("source_filename")) or source_path.name,
        source_media_type=_string_or_none(plot_map.get("source_media_type")) or _media_type_for(source_path),
        embedded_source_relpath=embedded_source_relpath,
        source_sha256=_string_or_none(plot_map.get("source_sha256")) or _sha256_bytes(source_path.read_bytes()),
        sheet=sheet,
        selected_template_id=template_id,
        render_options=normalized_options,
        fit_options=normalized_fit_options,
        project_display_name=_string_or_none(plot_map.get("project_display_name")),
        source_provenance=provenance,
    )


def _parse_embedded_workbooks(
    data_studio_map: Mapping[str, object],
    *,
    fallback_workbook_paths: tuple[str, ...],
) -> list[DataStudioProjectWorkbookPayload]:
    embedded_workbooks: list[DataStudioProjectWorkbookPayload] = []
    for index, item in enumerate(_iter_values(data_studio_map.get("embedded_workbooks"))):
        item_map = _mapping(item)
        if item_map is None:
            continue
        relpath = _string_or_none(item_map.get("embedded_workbook_relpath"))
        filename = _string_or_none(item_map.get("workbook_filename"))
        original_workbook_path = _string_or_none(item_map.get("original_workbook_path"))
        if original_workbook_path is None and index < len(fallback_workbook_paths):
            original_workbook_path = fallback_workbook_paths[index]
        if relpath is None:
            fallback_name = filename or (Path(original_workbook_path).name if original_workbook_path else None)
            if fallback_name is None:
                continue
            relpath = f"{_DATA_STUDIO_WORKBOOK_DIR}/{fallback_name}"
        if filename is None:
            filename = Path(relpath).name
        embedded_workbooks.append(
            DataStudioProjectWorkbookPayload(
                workbook_filename=filename,
                embedded_workbook_relpath=relpath,
                workbook_sha256=_string_or_none(item_map.get("workbook_sha256")) or "",
                original_workbook_path=original_workbook_path,
                saved_workbook_mtime_ns=_optional_int(item_map.get("saved_workbook_mtime_ns")),
            )
        )
    return embedded_workbooks


def _normalize_data_studio_project_payload(
    data_studio_map: Mapping[str, object],
    *,
    embedded_workbooks_override: list[DataStudioProjectWorkbookPayload] | None = None,
) -> DataStudioProjectPayload:
    session_payload = normalize_data_studio_session_payload(
        {
            "version": _int_value(data_studio_map.get("version"), _PROJECT_VERSION),
            "selected_template_id": data_studio_map.get("selected_template_id"),
            "selected_workbook_id": data_studio_map.get("selected_workbook_id"),
            "primary_workbook_id": data_studio_map.get("primary_workbook_id"),
            "selected_recipe_id": data_studio_map.get("selected_recipe_id"),
            "workbook_paths": list(_iter_values(data_studio_map.get("workbook_paths"))),
            "comparison_recipe_ids": list(_iter_values(data_studio_map.get("comparison_recipe_ids"))),
            "selected_figure_family_id": data_studio_map.get("selected_figure_family_id"),
            "selected_figure_template_id": data_studio_map.get("selected_figure_template_id"),
            "group_states": list(_iter_values(data_studio_map.get("group_states"))),
            "specimen_states": list(_iter_values(data_studio_map.get("specimen_states"))),
            "figure_preferences": list(_iter_values(data_studio_map.get("figure_preferences"))),
            "imported_paths": list(_iter_values(data_studio_map.get("imported_paths"))),
            "template_draft_path": data_studio_map.get("template_draft_path"),
        }
    )
    embedded_workbooks = (
        embedded_workbooks_override
        if embedded_workbooks_override is not None
        else _parse_embedded_workbooks(
            data_studio_map,
            fallback_workbook_paths=session_payload.workbook_paths,
        )
    )
    source_provenance = dict(_mapping(data_studio_map.get("source_provenance")) or {})
    return DataStudioProjectPayload(
        session_kind="data_studio",
        version=session_payload.version,
        selected_template_id=session_payload.selected_template_id,
        workbook_paths=list(session_payload.workbook_paths),
        selected_workbook_id=session_payload.selected_workbook_id,
        primary_workbook_id=session_payload.primary_workbook_id,
        selected_recipe_id=session_payload.selected_recipe_id,
        comparison_recipe_ids=list(session_payload.comparison_recipe_ids),
        selected_figure_family_id=session_payload.selected_figure_family_id,
        selected_figure_template_id=session_payload.selected_figure_template_id,
        group_states=serialize_model(session_payload.group_states),
        specimen_states=serialize_model(session_payload.specimen_states),
        figure_preferences=serialize_model(session_payload.figure_preferences),
        imported_paths=list(session_payload.imported_paths),
        template_draft_path=session_payload.template_draft_path,
        embedded_workbooks=embedded_workbooks,
        project_display_name=_string_or_none(data_studio_map.get("project_display_name")),
        source_provenance=source_provenance,
    )


def normalize_project_payload(
    payload: Mapping[str, object],
    *,
    source_path: Path | None = None,
) -> ProjectBundlePayload:
    selected_workbench = _normalize_selected_workbench(payload)
    artifacts = dict(_mapping(payload.get("artifacts")) or {})
    if not artifacts.get("manifest_relpath"):
        artifacts["manifest_relpath"] = _ARTIFACT_MANIFEST_MEMBER
    if selected_workbench == "plot":
        if source_path is None:
            raise ValueError("Plot projects require the current source file path.")
        plot_map = _mapping(payload.get("plot"))
        if plot_map is None:
            raise ValueError("Project payload must include a plot section.")
        return ProjectBundlePayload(
            version=_int_value(payload.get("version"), _PROJECT_VERSION),
            selected_workbench="plot",
            plot=_normalize_plot_project_payload(plot_map, source_path=source_path),
            data_studio=None,
            composer=None,
            code_console=None,
            artifacts=artifacts,
        )
    data_studio_map = _mapping(payload.get("data_studio"))
    if data_studio_map is None:
        raise ValueError("Project payload must include a Data Studio section.")
    return ProjectBundlePayload(
        version=_int_value(payload.get("version"), _PROJECT_VERSION),
        selected_workbench="data_studio",
        plot=None,
        data_studio=_normalize_data_studio_project_payload(data_studio_map),
        composer=None,
        code_console=None,
        artifacts=artifacts,
    )


def _manifest_payload(
    project_payload: ProjectBundlePayload,
    *,
    entries: list[dict[str, object]],
) -> dict[str, object]:
    return {
        "version": project_payload.version,
        "kind": "app_project_bundle",
        "selected_workbench": project_payload.selected_workbench,
        "saved_at": datetime.now(UTC).isoformat(),
        "entries": [{"path": _PROJECT_MEMBER, "kind": "project_payload"}, *entries],
    }


def _unique_bundle_member(base_dir: str, filename: str, *, seen: set[str]) -> str:
    stem = Path(filename).stem or "item"
    suffix = Path(filename).suffix
    candidate = f"{base_dir}/{filename}"
    index = 2
    while candidate in seen:
        candidate = f"{base_dir}/{stem}_{index}{suffix}"
        index += 1
    seen.add(candidate)
    return candidate


def _unique_restore_name(filename: str, *, seen: set[str]) -> str:
    stem = Path(filename).stem or "item"
    suffix = Path(filename).suffix
    candidate = filename
    index = 2
    while candidate in seen:
        candidate = f"{stem}_{index}{suffix}"
        index += 1
    seen.add(candidate)
    return candidate


def save_project_bundle(
    *,
    project_path: Path,
    source_path: Path | None,
    payload: ProjectBundlePayload,
) -> SaveProjectResponse:
    normalized_payload = normalize_project_payload(payload.model_dump(mode="json"), source_path=source_path)
    saved_at = datetime.now(UTC).isoformat()
    archive_entries: list[tuple[str, bytes]] = []
    manifest_entries: list[dict[str, object]] = []

    if normalized_payload.selected_workbench == "plot":
        if source_path is None:
            raise ValueError("Plot projects require a source file.")
        plot_payload = normalized_payload.plot
        if plot_payload is None:
            raise ValueError("Project payload is missing the plot section.")
        source_bytes = source_path.read_bytes()
        embedded_source_relpath = _unique_bundle_member(_PLOT_SOURCE_DIR, source_path.name, seen=set())
        normalized_plot_payload = plot_payload.model_copy(
            update={
                "source_filename": source_path.name,
                "source_media_type": _media_type_for(source_path),
                "embedded_source_relpath": embedded_source_relpath,
                "source_sha256": _sha256_bytes(source_bytes),
                "project_display_name": plot_payload.project_display_name or project_path.stem,
                "source_provenance": _default_plot_provenance(source_path, saved_at=saved_at).model_copy(
                    update={
                        "original_input_path": plot_payload.source_provenance.original_input_path or str(source_path),
                        "saved_input_mtime_ns": source_path.stat().st_mtime_ns,
                    }
                ),
            }
        )
        archive_entries.append((embedded_source_relpath, source_bytes))
        manifest_entries.append(
            {
                "path": embedded_source_relpath,
                "kind": "plot_primary_source",
                "sha256": normalized_plot_payload.source_sha256,
                "size_bytes": len(source_bytes),
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
    else:
        data_studio_payload = normalized_payload.data_studio
        if data_studio_payload is None:
            raise ValueError("Project payload is missing the Data Studio section.")
        resolved_workbook_paths = [
            normalize_path(workbook_path)
            for workbook_path in data_studio_payload.workbook_paths
        ]
        if not resolved_workbook_paths:
            raise ValueError("Import workbook groups before saving a Data Studio project.")
        seen_members: set[str] = set()
        embedded_workbooks: list[DataStudioProjectWorkbookPayload] = []
        for workbook_path in resolved_workbook_paths:
            workbook_bytes = workbook_path.read_bytes()
            member_path = _unique_bundle_member(_DATA_STUDIO_WORKBOOK_DIR, workbook_path.name, seen=seen_members)
            workbook_sha256 = _sha256_bytes(workbook_bytes)
            embedded_workbooks.append(
                DataStudioProjectWorkbookPayload(
                    workbook_filename=workbook_path.name,
                    embedded_workbook_relpath=member_path,
                    workbook_sha256=workbook_sha256,
                    original_workbook_path=str(workbook_path),
                    saved_workbook_mtime_ns=workbook_path.stat().st_mtime_ns,
                )
            )
            archive_entries.append((member_path, workbook_bytes))
            manifest_entries.append(
                {
                    "path": member_path,
                    "kind": "data_studio_workbook",
                    "sha256": workbook_sha256,
                    "size_bytes": len(workbook_bytes),
                }
            )
        source_provenance = dict(data_studio_payload.source_provenance)
        source_provenance.setdefault("saved_at", saved_at)
        saved_payload = normalized_payload.model_copy(
            update={
                "data_studio": data_studio_payload.model_copy(
                    update={
                        "workbook_paths": [str(path) for path in resolved_workbook_paths],
                        "embedded_workbooks": embedded_workbooks,
                        "project_display_name": data_studio_payload.project_display_name or project_path.stem,
                        "source_provenance": source_provenance,
                    }
                ),
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
        _manifest_payload(saved_payload, entries=manifest_entries),
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
            for member_path, member_bytes in archive_entries:
                archive.writestr(member_path, member_bytes)
            archive.writestr(_ARTIFACT_MANIFEST_MEMBER, manifest_json)
        temp_path.replace(project_path)
    finally:
        temp_path.unlink(missing_ok=True)
    return SaveProjectResponse(project_path=str(project_path), payload=saved_payload)


def _remap_workbook_paths(
    data_studio_map: Mapping[str, object],
    *,
    path_lookup: Mapping[str, str],
    restored_workbook_paths: list[str],
) -> dict[str, object]:
    remapped = dict(data_studio_map)

    def remap_path(value: object) -> str:
        raw = _string_or_none(value) or str(value)
        normalized = str(Path(raw).expanduser())
        return path_lookup.get(normalized, path_lookup.get(raw, normalized))

    workbook_paths = [remap_path(item) for item in _iter_values(data_studio_map.get("workbook_paths"))]
    remapped["workbook_paths"] = workbook_paths or list(restored_workbook_paths)

    group_states: list[dict[str, object]] = []
    for item in _iter_values(data_studio_map.get("group_states")):
        item_map = _mapping(item)
        if item_map is None:
            continue
        group_state = dict(item_map)
        group_state["workbook_path"] = remap_path(item_map.get("workbook_path", ""))
        group_states.append(group_state)
    remapped["group_states"] = group_states

    specimen_states: list[dict[str, object]] = []
    for item in _iter_values(data_studio_map.get("specimen_states")):
        item_map = _mapping(item)
        if item_map is None:
            continue
        specimen_state = dict(item_map)
        specimen_state["workbook_path"] = remap_path(item_map.get("workbook_path", ""))
        specimen_states.append(specimen_state)
    remapped["specimen_states"] = specimen_states
    return remapped


def open_project_bundle(*, project_path: Path) -> OpenProjectResponse:
    with zipfile.ZipFile(project_path, mode="r") as archive:
        try:
            raw_payload = json.loads(archive.read(_PROJECT_MEMBER).decode("utf-8"))
        except KeyError as exc:
            raise ValueError("Project bundle is missing project.json.") from exc
        raw_payload_map = _mapping(raw_payload)
        if raw_payload_map is None:
            raise ValueError("Project bundle project.json must contain an object payload.")
        selected_workbench = _normalize_selected_workbench(raw_payload_map)

        if selected_workbench == "plot":
            plot_map = _mapping(raw_payload_map.get("plot"))
            if plot_map is None:
                raise ValueError("Project bundle is missing the plot section.")
            embedded_source_relpath = _string_or_none(plot_map.get("embedded_source_relpath"))
            if embedded_source_relpath is None:
                raise ValueError("Project bundle is missing the embedded Plot source path.")
            try:
                source_bytes = archive.read(embedded_source_relpath)
            except KeyError as exc:
                raise ValueError("Project bundle is missing the embedded Plot source file.") from exc
            expected_sha256 = _string_or_none(plot_map.get("source_sha256")) or ""
            actual_sha256 = _sha256_bytes(source_bytes)
            if expected_sha256 and actual_sha256 != expected_sha256:
                raise ValueError("Embedded source checksum does not match the saved project metadata.")
            source_filename = _string_or_none(plot_map.get("source_filename")) or Path(embedded_source_relpath).name
            restore_dir = prepare_managed_project_restore_dir(project_path, fingerprint=actual_sha256)
            restored_source_path = restore_dir / source_filename
            restored_source_path.write_bytes(source_bytes)
            normalized_payload = normalize_project_payload(raw_payload_map, source_path=restored_source_path)
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
                restored_workbook_paths=[],
                payload=normalized_payload.model_copy(update={"plot": normalized_plot_payload}),
            )

        data_studio_map = _mapping(raw_payload_map.get("data_studio"))
        if data_studio_map is None:
            raise ValueError("Project bundle is missing the Data Studio section.")
        saved_workbook_paths = tuple(str(item) for item in _iter_values(data_studio_map.get("workbook_paths")))
        embedded_workbooks = _parse_embedded_workbooks(
            data_studio_map,
            fallback_workbook_paths=saved_workbook_paths,
        )
        if not embedded_workbooks:
            raise ValueError("Project bundle does not contain embedded Data Studio workbooks.")

        materialized_workbooks: list[tuple[DataStudioProjectWorkbookPayload, bytes, str]] = []
        fingerprint_parts: list[str] = []
        for embedded_workbook in embedded_workbooks:
            try:
                workbook_bytes = archive.read(embedded_workbook.embedded_workbook_relpath)
            except KeyError as exc:
                raise ValueError("Project bundle is missing an embedded Data Studio workbook.") from exc
            actual_sha256 = _sha256_bytes(workbook_bytes)
            if embedded_workbook.workbook_sha256 and actual_sha256 != embedded_workbook.workbook_sha256:
                raise ValueError("Embedded workbook checksum does not match the saved project metadata.")
            materialized_workbooks.append((embedded_workbook, workbook_bytes, actual_sha256))
            fingerprint_parts.append(actual_sha256)

        restore_dir = prepare_managed_project_restore_dir(
            project_path,
            fingerprint=_sha256_text("||".join(sorted(fingerprint_parts))),
        )
        seen_restore_names: set[str] = set()
        restored_workbook_paths: list[str] = []
        path_lookup: dict[str, str] = {}
        normalized_embedded_workbooks: list[DataStudioProjectWorkbookPayload] = []
        for index, (embedded_workbook, workbook_bytes, actual_sha256) in enumerate(materialized_workbooks):
            restore_name = _unique_restore_name(embedded_workbook.workbook_filename, seen=seen_restore_names)
            restored_workbook_path = restore_dir / restore_name
            restored_workbook_path.write_bytes(workbook_bytes)
            restored_workbook_paths.append(str(restored_workbook_path))
            if embedded_workbook.original_workbook_path:
                expanded_original_path = str(Path(embedded_workbook.original_workbook_path).expanduser())
                path_lookup[expanded_original_path] = str(restored_workbook_path)
                path_lookup[embedded_workbook.original_workbook_path] = str(restored_workbook_path)
            if index < len(saved_workbook_paths):
                path_lookup[str(Path(saved_workbook_paths[index]).expanduser())] = str(restored_workbook_path)
                path_lookup[saved_workbook_paths[index]] = str(restored_workbook_path)
            normalized_embedded_workbooks.append(
                embedded_workbook.model_copy(update={"workbook_sha256": actual_sha256})
            )

        remapped_data_studio_map = _remap_workbook_paths(
            data_studio_map,
            path_lookup=path_lookup,
            restored_workbook_paths=restored_workbook_paths,
        )
        remapped_data_studio_map["embedded_workbooks"] = [
            workbook.model_dump(mode="json") for workbook in normalized_embedded_workbooks
        ]
        normalized_payload = normalize_project_payload(
            {
                "version": raw_payload_map.get("version", _PROJECT_VERSION),
                "selected_workbench": "data_studio",
                "plot": None,
                "data_studio": remapped_data_studio_map,
                "composer": raw_payload_map.get("composer"),
                "code_console": raw_payload_map.get("code_console"),
                "artifacts": raw_payload_map.get("artifacts"),
            }
        )
        data_studio_payload = normalized_payload.data_studio
        if data_studio_payload is None:
            raise ValueError("Project bundle is missing the Data Studio section.")
        normalized_data_studio_payload = data_studio_payload.model_copy(
            update={
                "embedded_workbooks": normalized_embedded_workbooks,
                "project_display_name": data_studio_payload.project_display_name or project_path.stem,
            }
        )
        return OpenProjectResponse(
            project_path=str(project_path),
            restored_source_path=None,
            restored_workbook_paths=restored_workbook_paths,
            payload=normalized_payload.model_copy(update={"data_studio": normalized_data_studio_payload}),
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
