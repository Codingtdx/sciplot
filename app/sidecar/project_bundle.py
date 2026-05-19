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
    CodeConsoleProjectGeneratedFilePayload,
    CodeConsoleProjectManualBindingPayload,
    CodeConsoleProjectPayload,
    ComposerProjectPanelPayload,
    ComposerProjectPayload,
    DataStudioProjectPayload,
    DataStudioProjectWorkbookPayload,
    DataTransformPayload,
    DataVariablePayload,
    DocumentGraphEdgePayload,
    DocumentGraphNodePayload,
    DocumentGraphPayload,
    ExtraAxisPayload,
    FitOptionsPayload,
    OpenProjectResponse,
    PlotProjectPayload,
    PlotProjectSourceProvenancePayload,
    ProjectBundlePayload,
    ReferenceGuidePayload,
    RenderOptionsPayload,
    SaveProjectResponse,
    SeriesOffsetPayload,
    SeriesStylePayload,
    ShapeAnnotationPayload,
    TextAnnotationPayload,
)
from app.sidecar.server_utils import normalize_path, options_from_payload
from src.data_studio.models import serialize_model
from src.data_studio.session import normalize_session_payload as normalize_data_studio_session_payload
from src.infrastructure.persistence.plot_projects import prepare_managed_project_restore_dir
from src.rendering.constants import DEFAULT_SIZE_BY_TEMPLATE
from src.rendering.custom_theme_store import load_custom_theme, theme_member_filename
from src.rendering.custom_themes import custom_theme_to_payload
from src.rendering.fit_analysis import normalize_fit_options_payload
from src.rendering.options import validate_template_name
from src.rendering.template_lifecycle import resolve_template_id

_PROJECT_VERSION = 2
_PROJECT_MEMBER = "project.json"
_ARTIFACT_MANIFEST_MEMBER = "artifacts/manifest.json"
_PLOT_SOURCE_DIR = "sources/plot/primary"
_LEGACY_PLOT_SOURCE_DIR = "sources/primary"
_DATA_STUDIO_WORKBOOK_DIR = "sources/data_studio/workbooks"
_COMPOSER_PANEL_DIR = "sources/composer/panels"
_CODE_CONSOLE_MANUAL_DIR = "sources/code_console/manual"
_CODE_CONSOLE_LATEST_RUN_DIR = "artifacts/code_console/latest_run"
_CUSTOM_THEME_DIR = "artifacts/custom_themes"
_SUPPORTED_WORKBENCHES = {"plot", "data_studio", "composer", "code_console"}
PROJECT_FILE_EXTENSION = ".sciplot"


def is_supported_project_path(path: Path) -> bool:
    return path.suffix.lower() == PROJECT_FILE_EXTENSION


def project_extension_error() -> str:
    return f"Project file must use the {PROJECT_FILE_EXTENSION} extension."


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
        series_styles=(
            [SeriesStylePayload.model_validate(item) for item in resolved_options.series_styles]
            if resolved_options.series_styles is not None
            else None
        ),
        series_offsets=(
            [SeriesOffsetPayload.model_validate(item) for item in resolved_options.series_offsets]
            if resolved_options.series_offsets is not None
            else None
        ),
        x_label_override=resolved_options.x_label_override,
        y_label_override=resolved_options.y_label_override,
        baseline=resolved_options.baseline,
        show_colorbar=resolved_options.show_colorbar,
        style_preset=resolved_options.style_preset,
        palette_preset=resolved_options.palette_preset,
        use_sidecar=payload.use_sidecar,
        visual_theme_id=resolved_options.visual_theme_id,
        custom_theme_id=resolved_options.custom_theme_id,
        custom_theme_draft=resolved_options.custom_theme_draft,
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
        data_variables=(
            [DataVariablePayload.model_validate(item) for item in resolved_options.data_variables]
            if resolved_options.data_variables is not None
            else None
        ),
        data_transforms=(
            [DataTransformPayload.model_validate(item) for item in resolved_options.data_transforms]
            if resolved_options.data_transforms is not None
            else None
        ),
    )


def _normalize_selected_workbench(payload: Mapping[str, object]) -> str:
    selected = _string_or_none(payload.get("selected_workbench"))
    if selected in _SUPPORTED_WORKBENCHES:
        return selected
    if _mapping(payload.get("code_console")) is not None:
        return "code_console"
    if _mapping(payload.get("composer")) is not None:
        return "composer"
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


def _normalize_composer_project_payload(composer_map: Mapping[str, object]) -> ComposerProjectPayload:
    return ComposerProjectPayload.model_validate(
        {
            "session_kind": composer_map.get("session_kind", "composer"),
            "version": _int_value(composer_map.get("version"), _PROJECT_VERSION),
            "project": composer_map.get("project") or {},
            "embedded_panels": list(_iter_values(composer_map.get("embedded_panels"))),
            "project_display_name": _string_or_none(composer_map.get("project_display_name")),
        }
    )


def _normalize_code_console_project_payload(
    code_console_map: Mapping[str, object],
) -> CodeConsoleProjectPayload:
    return CodeConsoleProjectPayload.model_validate(
        {
            "session_kind": code_console_map.get("session_kind", "code_console"),
            "version": _int_value(code_console_map.get("version"), _PROJECT_VERSION),
            "selected_source_kind": _string_or_none(code_console_map.get("selected_source_kind")),
            "selected_sheet": code_console_map.get("selected_sheet", 0),
            "editor_text": str(code_console_map.get("editor_text") or ""),
            "prompt_text": str(code_console_map.get("prompt_text") or ""),
            "starter_code": str(code_console_map.get("starter_code") or ""),
            "manual_binding": code_console_map.get("manual_binding"),
            "latest_run": code_console_map.get("latest_run"),
            "embedded_generated_files": list(_iter_values(code_console_map.get("embedded_generated_files"))),
            "selected_generated_file_path": _string_or_none(
                code_console_map.get("selected_generated_file_path")
            ),
            "project_display_name": _string_or_none(code_console_map.get("project_display_name")),
        }
    )


def _graph_node(
    *,
    id: str,
    kind: str,
    module: str,
    label: str,
    payload: dict[str, object] | None = None,
) -> DocumentGraphNodePayload:
    return DocumentGraphNodePayload(
        id=id,
        kind=kind,
        module=module,
        label=label,
        payload=dict(payload or {}),
    )


def _graph_edge(source: str, target: str, relationship: str) -> DocumentGraphEdgePayload:
    return DocumentGraphEdgePayload(source=source, target=target, relationship=relationship)


def _generate_document_graph(
    *,
    selected_workbench: str,
    plot: PlotProjectPayload | None,
    data_studio: DataStudioProjectPayload | None,
    composer: ComposerProjectPayload | None,
    code_console: CodeConsoleProjectPayload | None,
) -> DocumentGraphPayload:
    nodes: list[DocumentGraphNodePayload] = []
    edges: list[DocumentGraphEdgePayload] = []
    module_roots: dict[str, str] = {}

    if plot is not None:
        scene_id = "plot:scene"
        page_id = "plot:page"
        plot_area_id = "plot:plot_area"
        series_id = "plot:series:primary"
        module_roots["plot"] = scene_id
        nodes.extend(
            [
                _graph_node(
                    id=scene_id,
                    kind="plot.scene",
                    module="plot",
                    label=plot.project_display_name or "Plot Scene",
                    payload={
                        "graph_addressable": True,
                        "selected_template_id": plot.selected_template_id,
                        "sheet": plot.sheet,
                    },
                ),
                _graph_node(
                    id=page_id,
                    kind="plot.page",
                    module="plot",
                    label="Figure Page",
                    payload={"graph_addressable": True},
                ),
                _graph_node(
                    id=plot_area_id,
                    kind="plot.plot_area",
                    module="plot",
                    label="Plot Area",
                    payload={"graph_addressable": True},
                ),
                _graph_node(
                    id=series_id,
                    kind="plot.series",
                    module="plot",
                    label="Primary Series",
                    payload={
                        "graph_addressable": True,
                        "selected_template_id": plot.selected_template_id,
                    },
                ),
                _graph_node(
                    id="plot:source:primary",
                    kind="plot.source",
                    module="plot",
                    label=plot.source_filename,
                    payload={
                        "embedded_source_relpath": plot.embedded_source_relpath,
                        "source_sha256": plot.source_sha256,
                    },
                ),
                _graph_node(
                    id="plot:axis:x",
                    kind="plot.axis",
                    module="plot",
                    label="X Axis",
                    payload={"graph_addressable": True, "axis": "x"},
                ),
                _graph_node(
                    id="plot:axis:y_primary",
                    kind="plot.axis",
                    module="plot",
                    label="Primary Y Axis",
                    payload={"graph_addressable": True, "axis": "y_primary"},
                ),
                _graph_node(
                    id="plot:legend",
                    kind="plot.legend",
                    module="plot",
                    label="Legend",
                    payload={"graph_addressable": True},
                ),
            ]
        )
        edges.extend(
            [
                _graph_edge(scene_id, page_id, "contains"),
                _graph_edge(page_id, plot_area_id, "contains"),
                _graph_edge(plot_area_id, series_id, "contains"),
                _graph_edge(scene_id, "plot:source:primary", "uses_source"),
                _graph_edge(plot_area_id, "plot:axis:x", "contains"),
                _graph_edge(plot_area_id, "plot:axis:y_primary", "contains"),
                _graph_edge(plot_area_id, "plot:legend", "contains"),
            ]
        )
        if plot.render_options.extra_x_axis is not None and plot.render_options.extra_x_axis.enabled:
            nodes.append(
                _graph_node(
                    id="plot:axis:extra_x",
                    kind="plot.axis.extra",
                    module="plot",
                    label=plot.render_options.extra_x_axis.title or "Extra X Axis",
                    payload={"graph_addressable": True, "axis": "extra_x"},
                )
            )
            edges.append(_graph_edge(plot_area_id, "plot:axis:extra_x", "contains"))
        if plot.render_options.extra_y_axis is not None and plot.render_options.extra_y_axis.enabled:
            nodes.append(
                _graph_node(
                    id="plot:axis:extra_y",
                    kind="plot.axis.extra",
                    module="plot",
                    label=plot.render_options.extra_y_axis.title or "Extra Y Axis",
                    payload={"graph_addressable": True, "axis": "extra_y"},
                )
            )
            edges.append(_graph_edge(plot_area_id, "plot:axis:extra_y", "contains"))
        for axis_name, breaks in (
            ("x", plot.render_options.x_axis_breaks or []),
            ("y", plot.render_options.y_axis_breaks or []),
        ):
            for index, axis_break in enumerate(breaks, start=1):
                node_id = f"plot:axis_break:{axis_name}:{index}"
                nodes.append(
                    _graph_node(
                        id=node_id,
                        kind="plot.axis.break",
                        module="plot",
                        label=f"{axis_name.upper()} Axis Break {index}",
                        payload={
                            "graph_addressable": True,
                            "axis": axis_name,
                            "enabled": axis_break.enabled,
                            "start": axis_break.start,
                            "end": axis_break.end,
                        },
                    )
                )
                edges.append(_graph_edge(plot_area_id, node_id, "contains"))
        for guide in plot.render_options.reference_guides or []:
            node_id = f"plot:guide:{guide.id}"
            nodes.append(
                _graph_node(
                    id=node_id,
                    kind="plot.guide",
                    module="plot",
                    label=guide.label or guide.id,
                    payload={
                        "graph_addressable": True,
                        "guide_id": guide.id,
                        "kind": guide.kind,
                        "enabled": guide.enabled,
                    },
                )
            )
            edges.append(_graph_edge(plot_area_id, node_id, "contains"))
        for annotation in plot.render_options.text_annotations or []:
            node_id = f"plot:annotation:text:{annotation.id}"
            nodes.append(
                _graph_node(
                    id=node_id,
                    kind="plot.annotation.text",
                    module="plot",
                    label=annotation.text or annotation.id,
                    payload={
                        "graph_addressable": True,
                        "annotation_id": annotation.id,
                        "enabled": annotation.enabled,
                    },
                )
            )
            edges.append(_graph_edge(plot_area_id, node_id, "contains"))
        for shape in plot.render_options.shape_annotations or []:
            node_id = f"plot:annotation:shape:{shape.id}"
            nodes.append(
                _graph_node(
                    id=node_id,
                    kind="plot.annotation.shape",
                    module="plot",
                    label=shape.label or shape.id,
                    payload={
                        "graph_addressable": True,
                        "shape_id": shape.id,
                        "kind": shape.kind,
                        "enabled": shape.enabled,
                    },
                )
            )
            edges.append(_graph_edge(plot_area_id, node_id, "contains"))
        for layer in plot.render_options.analytical_layers or []:
            node_id = f"plot:layer:function:{layer.id}"
            nodes.append(
                _graph_node(
                    id=node_id,
                    kind="plot.layer.function",
                    module="plot",
                    label=layer.label or layer.id,
                    payload={
                        "graph_addressable": True,
                        "layer_id": layer.id,
                        "expression": layer.expression,
                        "enabled": layer.enabled,
                    },
                )
            )
            edges.append(_graph_edge(plot_area_id, node_id, "contains"))
        if plot.fit_options.enabled:
            nodes.append(
                _graph_node(
                    id="plot:fit_overlay",
                    kind="plot.fit_overlay",
                    module="plot",
                    label="Fit Overlay",
                    payload={
                        "graph_addressable": True,
                        "model_id": plot.fit_options.model_id,
                        "enabled": plot.fit_options.enabled,
                    },
                )
            )
            nodes.append(
                _graph_node(
                    id="plot:analysis:fit",
                    kind="analysis.fit",
                    module="plot",
                    label="Fit Overlay",
                    payload={
                        "model_id": plot.fit_options.model_id,
                        "enabled": plot.fit_options.enabled,
                    },
                )
            )
            edges.append(_graph_edge(plot_area_id, "plot:fit_overlay", "contains"))
            edges.append(_graph_edge(scene_id, "plot:analysis:fit", "contains"))

    if data_studio is not None:
        root_id = "data_studio:workbooks"
        module_roots["data_studio"] = root_id
        nodes.append(
            _graph_node(
                id=root_id,
                kind="data.workbook_group",
                module="data_studio",
                label=data_studio.project_display_name or "Workbook Groups",
                payload={
                    "selected_template_id": data_studio.selected_template_id,
                    "selected_workbook_id": data_studio.selected_workbook_id,
                },
            )
        )
        for index, imported_path in enumerate(data_studio.imported_paths):
            source_id = f"data_studio:import_source:{index + 1}"
            nodes.append(
                _graph_node(
                    id=source_id,
                    kind="data.import_source",
                    module="data_studio",
                    label=Path(imported_path).name or f"Import Source {index + 1}",
                    payload={
                        "original_path": imported_path,
                        "selected_template_id": data_studio.selected_template_id,
                        "readonly": True,
                    },
                )
            )
            edges.append(_graph_edge(root_id, source_id, "contains"))
            if data_studio.selected_template_id:
                template_node_id = f"{source_id}:template_application"
                nodes.append(
                    _graph_node(
                        id=template_node_id,
                        kind="data.template_application",
                        module="data_studio",
                        label=f"{data_studio.selected_template_id} application",
                        payload={
                            "source_node_id": source_id,
                            "template_id": data_studio.selected_template_id,
                        },
                    )
                )
                edges.append(_graph_edge(source_id, template_node_id, "applies"))
        for index, workbook in enumerate(data_studio.embedded_workbooks):
            workbook_id = f"data_studio:workbook:{index + 1}"
            nodes.append(
                _graph_node(
                    id=workbook_id,
                    kind="data.workbook",
                    module="data_studio",
                    label=workbook.workbook_filename,
                    payload={
                        "embedded_workbook_relpath": workbook.embedded_workbook_relpath,
                        "workbook_sha256": workbook.workbook_sha256,
                    },
                )
            )
            edges.append(_graph_edge(root_id, workbook_id, "contains"))
            table_id = f"{workbook_id}:table"
            nodes.append(
                _graph_node(
                    id=table_id,
                    kind="data.table",
                    module="data_studio",
                    label=f"{workbook.workbook_filename} table",
                    payload={
                        "workbook_node_id": workbook_id,
                        "readonly": True,
                    },
                )
            )
            edges.append(_graph_edge(workbook_id, table_id, "contains"))

    if composer is not None:
        root_id = "composer:document"
        module_roots["composer"] = root_id
        nodes.append(
            _graph_node(
                id=root_id,
                kind="composer.document",
                module="composer",
                label=composer.project_display_name or "Composer Document",
                payload={"panel_count": len(composer.project.panels)},
            )
        )
        for panel in composer.project.panels:
            panel_id = f"composer:panel:{panel.id}"
            nodes.append(
                _graph_node(
                    id=panel_id,
                    kind="composer.panel",
                    module="composer",
                    label=panel.label or panel.id,
                    payload={"panel_id": panel.id},
                )
            )
            edges.append(_graph_edge(root_id, panel_id, "contains"))

    if code_console is not None:
        root_id = "code_console:context"
        module_roots["code_console"] = root_id
        nodes.append(
            _graph_node(
                id=root_id,
                kind="code.context",
                module="code_console",
                label=code_console.project_display_name or "Code Console Context",
                payload={
                    "selected_source_kind": code_console.selected_source_kind,
                    "selected_sheet": code_console.selected_sheet,
                },
            )
        )
        if code_console.latest_run is not None:
            run_id = "code_console:latest_run"
            nodes.append(
                _graph_node(
                    id=run_id,
                    kind="code.run",
                    module="code_console",
                    label="Latest Run",
                    payload={"generated_file_count": len(code_console.latest_run.generated_files)},
                )
            )
            edges.append(_graph_edge(root_id, run_id, "contains"))
            for index, generated in enumerate(code_console.latest_run.generated_files, start=1):
                output_id = f"code_console:notebook_output:{index}"
                nodes.append(
                    _graph_node(
                        id=output_id,
                        kind="data.notebook_output",
                        module="code_console",
                        label=generated.name,
                        payload={
                            "graph_addressable": True,
                            "file_type": generated.file_type,
                            "output_path": generated.path,
                            "source_run_id": run_id,
                        },
                    )
                )
                edges.append(_graph_edge(run_id, output_id, "emits"))
        for index, generated in enumerate(code_console.embedded_generated_files, start=1):
            output_id = f"code_console:embedded_notebook_output:{index}"
            nodes.append(
                _graph_node(
                    id=output_id,
                    kind="data.notebook_output",
                    module="code_console",
                    label=generated.name,
                    payload={
                        "graph_addressable": True,
                        "file_type": generated.file_type,
                        "embedded_file_relpath": generated.embedded_file_relpath,
                    },
                )
            )
            edges.append(_graph_edge(root_id, output_id, "contains"))

    selected_nodes = {
        module: root_id
        for module, root_id in module_roots.items()
        if module == selected_workbench
    }
    return DocumentGraphPayload(
        schema_version=1,
        nodes=nodes,
        edges=edges,
        selected_nodes=selected_nodes,
        module_roots=module_roots,
        capabilities=["project_bundle.document_graph"],
        migration_notes=["Generated document_graph from project payload v2."],
    )


def _normalize_document_graph(
    value: object,
    *,
    selected_workbench: str,
    plot: PlotProjectPayload | None,
    data_studio: DataStudioProjectPayload | None,
    composer: ComposerProjectPayload | None,
    code_console: CodeConsoleProjectPayload | None,
) -> DocumentGraphPayload:
    graph_map = _mapping(value)
    if graph_map is not None:
        return DocumentGraphPayload.model_validate(graph_map)
    return _generate_document_graph(
        selected_workbench=selected_workbench,
        plot=plot,
        data_studio=data_studio,
        composer=composer,
        code_console=code_console,
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

    plot_map = _mapping(payload.get("plot"))
    data_studio_map = _mapping(payload.get("data_studio"))
    composer_map = _mapping(payload.get("composer"))
    code_console_map = _mapping(payload.get("code_console"))

    plot_payload: PlotProjectPayload | None = None
    if plot_map is not None:
        if source_path is None:
            raise ValueError("Plot projects require the current source file path.")
        plot_payload = _normalize_plot_project_payload(plot_map, source_path=source_path)

    data_studio_payload = (
        _normalize_data_studio_project_payload(data_studio_map)
        if data_studio_map is not None
        else None
    )
    composer_payload = (
        _normalize_composer_project_payload(composer_map)
        if composer_map is not None
        else None
    )
    code_console_payload = (
        _normalize_code_console_project_payload(code_console_map)
        if code_console_map is not None
        else None
    )

    selected_payloads = {
        "plot": plot_payload,
        "data_studio": data_studio_payload,
        "composer": composer_payload,
        "code_console": code_console_payload,
    }
    if selected_payloads[selected_workbench] is None:
        raise ValueError("Project payload must include the selected workbench section.")

    document_graph = _normalize_document_graph(
        payload.get("document_graph"),
        selected_workbench=selected_workbench,
        plot=plot_payload,
        data_studio=data_studio_payload,
        composer=composer_payload,
        code_console=code_console_payload,
    )

    return ProjectBundlePayload(
        version=_PROJECT_VERSION,
        selected_workbench=selected_workbench,
        plot=plot_payload,
        data_studio=data_studio_payload,
        composer=composer_payload,
        code_console=code_console_payload,
        document_graph=document_graph,
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


def _render_option_custom_theme_ids(payload: ProjectBundlePayload) -> tuple[str, ...]:
    theme_ids: list[str] = []

    def append_from_options(options: RenderOptionsPayload | None) -> None:
        if options is not None and options.custom_theme_id:
            theme_ids.append(options.custom_theme_id)

    def append_from_raw_options(options: object) -> None:
        options_map = _mapping(options)
        if options_map is None:
            return
        theme_id = _string_or_none(options_map.get("custom_theme_id"))
        if theme_id is not None:
            theme_ids.append(theme_id)

    if payload.plot is not None:
        append_from_options(payload.plot.render_options)
    if payload.data_studio is not None:
        for preference in payload.data_studio.figure_preferences:
            preference_map = _mapping(preference)
            if preference_map is None:
                continue
            options_by_template = _mapping(preference_map.get("options_by_template")) or {}
            for options in options_by_template.values():
                append_from_raw_options(options)
    if payload.code_console is not None and payload.code_console.manual_binding is not None:
        append_from_options(payload.code_console.manual_binding.render_options)
    return tuple(dict.fromkeys(theme_ids))


def _theme_payload_for_render_options(options: RenderOptionsPayload) -> dict[str, object] | None:
    if options.custom_theme_draft is not None:
        return dict(options.custom_theme_draft)
    if not options.custom_theme_id:
        return None
    return custom_theme_to_payload(load_custom_theme(options.custom_theme_id))


def _theme_payload_for_raw_render_options(options: object) -> dict[str, object] | None:
    options_map = _mapping(options)
    if options_map is None:
        return None
    return _theme_payload_for_render_options(RenderOptionsPayload.model_validate(options_map))


def _embed_custom_theme_drafts(payload: ProjectBundlePayload) -> ProjectBundlePayload:
    updates: dict[str, object] = {}
    if payload.plot is not None:
        theme_payload = _theme_payload_for_render_options(payload.plot.render_options)
        if theme_payload is not None:
            updates["plot"] = payload.plot.model_copy(
                update={
                    "render_options": payload.plot.render_options.model_copy(
                        update={"custom_theme_draft": theme_payload}
                    )
                }
            )
    if payload.data_studio is not None:
        preferences: list[dict[str, object]] = []
        changed = False
        for preference in payload.data_studio.figure_preferences:
            preference_map = dict(_mapping(preference) or {})
            options_by_template = dict(_mapping(preference_map.get("options_by_template")) or {})
            normalized_options_by_template: dict[str, object] = {}
            for template_id, options in options_by_template.items():
                options_map = _mapping(options)
                theme_payload = _theme_payload_for_raw_render_options(options)
                if options_map is not None and theme_payload is not None:
                    normalized_options_by_template[str(template_id)] = RenderOptionsPayload.model_validate(
                        options_map
                    ).model_copy(update={"custom_theme_draft": theme_payload}).model_dump(mode="json")
                    changed = True
                else:
                    normalized_options_by_template[str(template_id)] = options
            if changed:
                preference_map["options_by_template"] = normalized_options_by_template
            preferences.append(preference_map)
        if changed:
            updates["data_studio"] = payload.data_studio.model_copy(update={"figure_preferences": preferences})
    if payload.code_console is not None and payload.code_console.manual_binding is not None:
        theme_payload = _theme_payload_for_render_options(payload.code_console.manual_binding.render_options)
        if theme_payload is not None:
            manual_binding = payload.code_console.manual_binding.model_copy(
                update={
                    "render_options": payload.code_console.manual_binding.render_options.model_copy(
                        update={"custom_theme_draft": theme_payload}
                    )
                }
            )
            updates["code_console"] = payload.code_console.model_copy(update={"manual_binding": manual_binding})
    return payload.model_copy(update=updates) if updates else payload


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
    payload_updates: dict[str, object] = {
        "artifacts": {
            **normalized_payload.artifacts,
            "manifest_relpath": _ARTIFACT_MANIFEST_MEMBER,
        }
    }
    seen_members: set[str] = set()

    if normalized_payload.plot is not None:
        if source_path is None:
            raise ValueError("Plot projects require a source file.")
        plot_payload = normalized_payload.plot
        source_bytes = source_path.read_bytes()
        embedded_source_relpath = _unique_bundle_member(_PLOT_SOURCE_DIR, source_path.name, seen=seen_members)
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
        payload_updates["plot"] = normalized_plot_payload

    if normalized_payload.data_studio is not None:
        data_studio_payload = normalized_payload.data_studio
        resolved_workbook_paths = [
            normalize_path(workbook_path)
            for workbook_path in data_studio_payload.workbook_paths
        ]
        if not resolved_workbook_paths:
            raise ValueError("Import workbook groups before saving a Data Studio project.")
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
        payload_updates["data_studio"] = data_studio_payload.model_copy(
            update={
                "workbook_paths": [str(path) for path in resolved_workbook_paths],
                "embedded_workbooks": embedded_workbooks,
                "project_display_name": data_studio_payload.project_display_name or project_path.stem,
                "source_provenance": source_provenance,
            }
        )

    if normalized_payload.composer is not None:
        composer_payload = normalized_payload.composer
        embedded_panels: list[ComposerProjectPanelPayload] = []
        for panel in composer_payload.project.panels:
            panel_path = normalize_path(panel.file_path)
            panel_bytes = panel_path.read_bytes()
            member_path = _unique_bundle_member(_COMPOSER_PANEL_DIR, panel_path.name, seen=seen_members)
            panel_sha256 = _sha256_bytes(panel_bytes)
            embedded_panels.append(
                ComposerProjectPanelPayload(
                    panel_id=panel.id,
                    panel_filename=panel_path.name,
                    embedded_panel_relpath=member_path,
                    panel_sha256=panel_sha256,
                    original_panel_path=str(panel_path),
                    saved_panel_mtime_ns=panel_path.stat().st_mtime_ns,
                )
            )
            archive_entries.append((member_path, panel_bytes))
            manifest_entries.append(
                {
                    "path": member_path,
                    "kind": "composer_panel",
                    "panel_id": panel.id,
                    "sha256": panel_sha256,
                    "size_bytes": len(panel_bytes),
                }
            )
        payload_updates["composer"] = composer_payload.model_copy(
            update={
                "embedded_panels": embedded_panels,
                "project_display_name": composer_payload.project_display_name or project_path.stem,
            }
        )

    if normalized_payload.code_console is not None:
        code_console_payload = normalized_payload.code_console
        manual_binding = code_console_payload.manual_binding
        normalized_manual_binding: CodeConsoleProjectManualBindingPayload | None = manual_binding
        if manual_binding is not None and manual_binding.original_source_path:
            manual_path = normalize_path(manual_binding.original_source_path)
            manual_bytes = manual_path.read_bytes()
            member_path = _unique_bundle_member(_CODE_CONSOLE_MANUAL_DIR, manual_path.name, seen=seen_members)
            manual_sha256 = _sha256_bytes(manual_bytes)
            normalized_manual_binding = manual_binding.model_copy(
                update={
                    "source_filename": manual_path.name,
                    "embedded_source_relpath": member_path,
                    "source_sha256": manual_sha256,
                    "original_source_path": str(manual_path),
                    "saved_source_mtime_ns": manual_path.stat().st_mtime_ns,
                }
            )
            archive_entries.append((member_path, manual_bytes))
            manifest_entries.append(
                {
                    "path": member_path,
                    "kind": "code_console_manual_source",
                    "sha256": manual_sha256,
                    "size_bytes": len(manual_bytes),
                }
            )

        embedded_generated_files: list[CodeConsoleProjectGeneratedFilePayload] = []
        if code_console_payload.latest_run is not None:
            for generated_file in code_console_payload.latest_run.generated_files:
                generated_path = normalize_path(generated_file.path)
                if not generated_path.exists():
                    continue
                generated_bytes = generated_path.read_bytes()
                member_path = _unique_bundle_member(
                    _CODE_CONSOLE_LATEST_RUN_DIR,
                    generated_path.name,
                    seen=seen_members,
                )
                generated_sha256 = _sha256_bytes(generated_bytes)
                embedded_generated_files.append(
                    CodeConsoleProjectGeneratedFilePayload(
                        original_path=str(generated_path),
                        embedded_file_relpath=member_path,
                        file_sha256=generated_sha256,
                        name=generated_file.name or generated_path.name,
                        file_type=generated_file.file_type,
                        size_bytes=len(generated_bytes),
                    )
                )
                archive_entries.append((member_path, generated_bytes))
                manifest_entries.append(
                    {
                        "path": member_path,
                        "kind": "code_console_generated_file",
                        "sha256": generated_sha256,
                        "size_bytes": len(generated_bytes),
                    }
                )
        payload_updates["code_console"] = code_console_payload.model_copy(
            update={
                "manual_binding": normalized_manual_binding,
                "embedded_generated_files": embedded_generated_files,
                "project_display_name": code_console_payload.project_display_name or project_path.stem,
            }
        )

    saved_payload = _embed_custom_theme_drafts(normalized_payload.model_copy(update=payload_updates))

    embedded_theme_ids: set[str] = set()
    for theme_id in _render_option_custom_theme_ids(saved_payload):
        if theme_id in embedded_theme_ids:
            continue
        embedded_theme_ids.add(theme_id)
        theme_payload: dict[str, object] | None = None
        if saved_payload.plot is not None and saved_payload.plot.render_options.custom_theme_id == theme_id:
            theme_payload = saved_payload.plot.render_options.custom_theme_draft
        if theme_payload is None and saved_payload.data_studio is not None:
            for preference in saved_payload.data_studio.figure_preferences:
                preference_map = _mapping(preference)
                if preference_map is None:
                    continue
                options_by_template = _mapping(preference_map.get("options_by_template")) or {}
                for options in options_by_template.values():
                    options_map = _mapping(options)
                    if options_map is None or _string_or_none(options_map.get("custom_theme_id")) != theme_id:
                        continue
                    draft = _mapping(options_map.get("custom_theme_draft"))
                    if draft is not None:
                        theme_payload = dict(draft)
                        break
                if theme_payload is not None:
                    break
        if (
            theme_payload is None
            and saved_payload.code_console is not None
            and saved_payload.code_console.manual_binding is not None
            and saved_payload.code_console.manual_binding.render_options.custom_theme_id == theme_id
        ):
            theme_payload = saved_payload.code_console.manual_binding.render_options.custom_theme_draft
        if theme_payload is None:
            continue
        theme_json = json.dumps(theme_payload, ensure_ascii=False, indent=2, sort_keys=True).encode("utf-8")
        member_path = f"{_CUSTOM_THEME_DIR}/{theme_member_filename(theme_id)}"
        archive_entries.append((member_path, theme_json))
        manifest_entries.append(
            {
                "path": member_path,
                "kind": "custom_plot_theme",
                "theme_id": theme_id,
                "sha256": _sha256_bytes(theme_json),
                "size_bytes": len(theme_json),
            }
        )

    if payload.document_graph is None:
        saved_payload = saved_payload.model_copy(
            update={
                "document_graph": _generate_document_graph(
                    selected_workbench=saved_payload.selected_workbench,
                    plot=saved_payload.plot,
                    data_studio=saved_payload.data_studio,
                    composer=saved_payload.composer,
                    code_console=saved_payload.code_console,
                )
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
        suffix=project_path.suffix or PROJECT_FILE_EXTENSION,
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


def _remap_composer_paths(
    composer_map: Mapping[str, object],
    *,
    panel_id_lookup: Mapping[str, str],
    path_lookup: Mapping[str, str],
    embedded_panels: list[ComposerProjectPanelPayload],
) -> dict[str, object]:
    remapped = dict(composer_map)
    project_map = dict(_mapping(composer_map.get("project")) or {})
    panels: list[dict[str, object]] = []
    for item in _iter_values(project_map.get("panels")):
        item_map = _mapping(item)
        if item_map is None:
            continue
        panel = dict(item_map)
        panel_id = _string_or_none(panel.get("id"))
        raw_path = _string_or_none(panel.get("file_path"))
        restored_path = panel_id_lookup.get(panel_id or "")
        if restored_path is None and raw_path is not None:
            restored_path = path_lookup.get(str(Path(raw_path).expanduser()), path_lookup.get(raw_path))
        if restored_path is not None:
            panel["file_path"] = restored_path
        panels.append(panel)
    project_map["panels"] = panels
    remapped["project"] = project_map
    remapped["embedded_panels"] = [panel.model_dump(mode="json") for panel in embedded_panels]
    return remapped


def _remap_code_console_paths(
    code_console_map: Mapping[str, object],
    *,
    manual_binding: CodeConsoleProjectManualBindingPayload | None,
    generated_path_lookup: Mapping[str, str],
    embedded_generated_files: list[CodeConsoleProjectGeneratedFilePayload],
) -> dict[str, object]:
    remapped = dict(code_console_map)
    if manual_binding is not None:
        remapped["manual_binding"] = manual_binding.model_dump(mode="json")

    latest_run_map = _mapping(code_console_map.get("latest_run"))
    if latest_run_map is not None:
        remapped_latest_run = dict(latest_run_map)
        generated_files: list[dict[str, object]] = []
        for item in _iter_values(latest_run_map.get("generated_files")):
            item_map = _mapping(item)
            if item_map is None:
                continue
            generated_file = dict(item_map)
            raw_path = _string_or_none(generated_file.get("path"))
            restored_path = None
            if raw_path is not None:
                restored_path = generated_path_lookup.get(
                    str(Path(raw_path).expanduser()),
                    generated_path_lookup.get(raw_path),
                )
            if restored_path is None:
                name = _string_or_none(generated_file.get("name"))
                if name is not None:
                    restored_path = generated_path_lookup.get(name)
            if restored_path is not None:
                generated_file["path"] = restored_path
                generated_file["size_bytes"] = Path(restored_path).stat().st_size
            generated_files.append(generated_file)
        remapped_latest_run["generated_files"] = generated_files
        remapped["latest_run"] = remapped_latest_run

    selected_generated_file_path = _string_or_none(code_console_map.get("selected_generated_file_path"))
    if selected_generated_file_path is not None:
        restored_selected = generated_path_lookup.get(
            str(Path(selected_generated_file_path).expanduser()),
            generated_path_lookup.get(selected_generated_file_path),
        )
        if restored_selected is not None:
            remapped["selected_generated_file_path"] = restored_selected

    remapped["embedded_generated_files"] = [
        item.model_dump(mode="json") for item in embedded_generated_files
    ]
    return remapped


def _custom_theme_payloads_from_archive(archive: zipfile.ZipFile) -> dict[str, dict[str, object]]:
    themes: dict[str, dict[str, object]] = {}
    for name in archive.namelist():
        if not name.startswith(f"{_CUSTOM_THEME_DIR}/") or not name.endswith(".json"):
            continue
        payload = json.loads(archive.read(name).decode("utf-8"))
        payload_map = _mapping(payload)
        if payload_map is None:
            continue
        theme_id = _string_or_none(payload_map.get("id"))
        if theme_id is not None:
            themes[theme_id] = dict(payload_map)
    return themes


def _restore_custom_theme_draft_in_render_options(
    render_options: object,
    *,
    embedded_themes: Mapping[str, dict[str, object]],
) -> object:
    options_map = _mapping(render_options)
    if options_map is None:
        return render_options
    theme_id = _string_or_none(options_map.get("custom_theme_id"))
    if theme_id is None or options_map.get("custom_theme_draft") is not None:
        return render_options
    theme_payload = embedded_themes.get(theme_id)
    if theme_payload is None:
        return render_options
    return {**options_map, "custom_theme_draft": theme_payload}


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
        plot_map = _mapping(raw_payload_map.get("plot"))
        data_studio_map = _mapping(raw_payload_map.get("data_studio"))
        composer_map = _mapping(raw_payload_map.get("composer"))
        code_console_map = _mapping(raw_payload_map.get("code_console"))
        embedded_custom_themes = _custom_theme_payloads_from_archive(archive)

        if plot_map is not None:
            plot_map = {
                **plot_map,
                "render_options": _restore_custom_theme_draft_in_render_options(
                    plot_map.get("render_options"),
                    embedded_themes=embedded_custom_themes,
                ),
            }
        if data_studio_map is not None:
            figure_preferences: list[object] = []
            for preference in _iter_values(data_studio_map.get("figure_preferences")):
                preference_map = _mapping(preference)
                if preference_map is None:
                    figure_preferences.append(preference)
                    continue
                options_by_template = _mapping(preference_map.get("options_by_template")) or {}
                figure_preferences.append(
                    {
                        **preference_map,
                        "options_by_template": {
                            str(template_id): _restore_custom_theme_draft_in_render_options(
                                options,
                                embedded_themes=embedded_custom_themes,
                            )
                            for template_id, options in options_by_template.items()
                        },
                    }
                )
            data_studio_map = {**data_studio_map, "figure_preferences": figure_preferences}
        if code_console_map is not None:
            manual_binding_map = _mapping(code_console_map.get("manual_binding"))
            if manual_binding_map is not None:
                code_console_map = {
                    **code_console_map,
                    "manual_binding": {
                        **manual_binding_map,
                        "render_options": _restore_custom_theme_draft_in_render_options(
                            manual_binding_map.get("render_options"),
                            embedded_themes=embedded_custom_themes,
                        ),
                    },
                }

        plot_materialized: tuple[bytes, str, str, str] | None = None
        fingerprint_parts: list[str] = []
        if plot_map is not None:
            embedded_source_relpath = _string_or_none(plot_map.get("embedded_source_relpath"))
            if embedded_source_relpath is None:
                raise ValueError("Project bundle is missing the embedded Plot source path.")
            try:
                source_bytes = archive.read(embedded_source_relpath)
            except KeyError as exc:
                raise ValueError("Project bundle is missing the embedded Plot source file.") from exc
            actual_sha256 = _sha256_bytes(source_bytes)
            expected_sha256 = _string_or_none(plot_map.get("source_sha256")) or ""
            if expected_sha256 and actual_sha256 != expected_sha256:
                raise ValueError("Embedded source checksum does not match the saved project metadata.")
            source_filename = _string_or_none(plot_map.get("source_filename")) or Path(embedded_source_relpath).name
            plot_materialized = (source_bytes, actual_sha256, source_filename, embedded_source_relpath)
            fingerprint_parts.append(actual_sha256)

        saved_workbook_paths: tuple[str, ...] = ()
        materialized_workbooks: list[tuple[DataStudioProjectWorkbookPayload, bytes, str]] = []
        if data_studio_map is not None:
            saved_workbook_paths = tuple(str(item) for item in _iter_values(data_studio_map.get("workbook_paths")))
            embedded_workbooks = _parse_embedded_workbooks(
                data_studio_map,
                fallback_workbook_paths=saved_workbook_paths,
            )
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

        materialized_panels: list[tuple[ComposerProjectPanelPayload, bytes, str]] = []
        if composer_map is not None:
            for item in _iter_values(composer_map.get("embedded_panels")):
                item_map = _mapping(item)
                if item_map is None:
                    continue
                embedded_panel = ComposerProjectPanelPayload.model_validate(item_map)
                try:
                    panel_bytes = archive.read(embedded_panel.embedded_panel_relpath)
                except KeyError as exc:
                    raise ValueError("Project bundle is missing an embedded Composer panel.") from exc
                actual_sha256 = _sha256_bytes(panel_bytes)
                if embedded_panel.panel_sha256 and actual_sha256 != embedded_panel.panel_sha256:
                    raise ValueError("Embedded Composer panel checksum does not match the saved project metadata.")
                materialized_panels.append((embedded_panel, panel_bytes, actual_sha256))
                fingerprint_parts.append(actual_sha256)

        manual_binding: CodeConsoleProjectManualBindingPayload | None = None
        manual_materialized: tuple[bytes, str] | None = None
        materialized_generated_files: list[tuple[CodeConsoleProjectGeneratedFilePayload, bytes, str]] = []
        if code_console_map is not None:
            manual_binding_map = _mapping(code_console_map.get("manual_binding"))
            if manual_binding_map is not None:
                raw_manual_binding = CodeConsoleProjectManualBindingPayload.model_validate(manual_binding_map)
                try:
                    manual_bytes = archive.read(raw_manual_binding.embedded_source_relpath)
                except KeyError as exc:
                    raise ValueError("Project bundle is missing the embedded Code Console source file.") from exc
                actual_sha256 = _sha256_bytes(manual_bytes)
                if raw_manual_binding.source_sha256 and actual_sha256 != raw_manual_binding.source_sha256:
                    raise ValueError("Embedded Code Console source checksum does not match the saved project metadata.")
                manual_binding = raw_manual_binding.model_copy(update={"source_sha256": actual_sha256})
                manual_materialized = (manual_bytes, actual_sha256)
                fingerprint_parts.append(actual_sha256)

            for item in _iter_values(code_console_map.get("embedded_generated_files")):
                item_map = _mapping(item)
                if item_map is None:
                    continue
                embedded_generated_file = CodeConsoleProjectGeneratedFilePayload.model_validate(item_map)
                try:
                    generated_bytes = archive.read(embedded_generated_file.embedded_file_relpath)
                except KeyError as exc:
                    raise ValueError("Project bundle is missing an embedded Code Console generated file.") from exc
                actual_sha256 = _sha256_bytes(generated_bytes)
                if embedded_generated_file.file_sha256 and actual_sha256 != embedded_generated_file.file_sha256:
                    raise ValueError(
                        "Embedded Code Console generated file checksum does not match the saved project metadata."
                    )
                materialized_generated_files.append((embedded_generated_file, generated_bytes, actual_sha256))
                fingerprint_parts.append(actual_sha256)

        restore_dir = prepare_managed_project_restore_dir(
            project_path,
            fingerprint=_sha256_text("||".join(sorted(fingerprint_parts)) or project_path.name),
        )
        seen_restore_names: set[str] = set()
        restored_source_path: Path | None = None

        if plot_materialized is not None:
            source_bytes, actual_sha256, source_filename, _ = plot_materialized
            restored_source_path = restore_dir / _unique_restore_name(source_filename, seen=seen_restore_names)
            restored_source_path.write_bytes(source_bytes)
            plot_map = {
                **plot_map,
                "source_filename": source_filename,
                "source_sha256": actual_sha256,
                "project_display_name": _string_or_none(plot_map.get("project_display_name")) or project_path.stem,
            }

        restored_workbook_paths: list[str] = []
        workbook_path_lookup: dict[str, str] = {}
        normalized_embedded_workbooks: list[DataStudioProjectWorkbookPayload] = []
        for index, (embedded_workbook, workbook_bytes, actual_sha256) in enumerate(materialized_workbooks):
            restore_name = _unique_restore_name(embedded_workbook.workbook_filename, seen=seen_restore_names)
            restored_workbook_path = restore_dir / restore_name
            restored_workbook_path.write_bytes(workbook_bytes)
            restored_workbook_paths.append(str(restored_workbook_path))
            if embedded_workbook.original_workbook_path:
                expanded_original_path = str(Path(embedded_workbook.original_workbook_path).expanduser())
                workbook_path_lookup[expanded_original_path] = str(restored_workbook_path)
                workbook_path_lookup[embedded_workbook.original_workbook_path] = str(restored_workbook_path)
            if index < len(saved_workbook_paths):
                workbook_path_lookup[str(Path(saved_workbook_paths[index]).expanduser())] = str(restored_workbook_path)
                workbook_path_lookup[saved_workbook_paths[index]] = str(restored_workbook_path)
            normalized_embedded_workbooks.append(
                embedded_workbook.model_copy(update={"workbook_sha256": actual_sha256})
            )

        if data_studio_map is not None:
            data_studio_map = _remap_workbook_paths(
                data_studio_map,
                path_lookup=workbook_path_lookup,
                restored_workbook_paths=restored_workbook_paths,
            )
            data_studio_map["embedded_workbooks"] = [
                workbook.model_dump(mode="json") for workbook in normalized_embedded_workbooks
            ]

        panel_id_lookup: dict[str, str] = {}
        panel_path_lookup: dict[str, str] = {}
        normalized_embedded_panels: list[ComposerProjectPanelPayload] = []
        for embedded_panel, panel_bytes, actual_sha256 in materialized_panels:
            restore_name = _unique_restore_name(embedded_panel.panel_filename, seen=seen_restore_names)
            restored_panel_path = restore_dir / restore_name
            restored_panel_path.write_bytes(panel_bytes)
            panel_id_lookup[embedded_panel.panel_id] = str(restored_panel_path)
            if embedded_panel.original_panel_path:
                panel_path_lookup[str(Path(embedded_panel.original_panel_path).expanduser())] = str(restored_panel_path)
                panel_path_lookup[embedded_panel.original_panel_path] = str(restored_panel_path)
            normalized_embedded_panels.append(
                embedded_panel.model_copy(update={"panel_sha256": actual_sha256})
            )
        if composer_map is not None:
            composer_map = _remap_composer_paths(
                composer_map,
                panel_id_lookup=panel_id_lookup,
                path_lookup=panel_path_lookup,
                embedded_panels=normalized_embedded_panels,
            )

        normalized_manual_binding = manual_binding
        if manual_binding is not None and manual_materialized is not None:
            manual_bytes, actual_sha256 = manual_materialized
            restore_name = _unique_restore_name(manual_binding.source_filename, seen=seen_restore_names)
            restored_manual_path = restore_dir / restore_name
            restored_manual_path.write_bytes(manual_bytes)
            normalized_manual_binding = manual_binding.model_copy(
                update={
                    "original_source_path": str(restored_manual_path),
                    "source_sha256": actual_sha256,
                    "saved_source_mtime_ns": restored_manual_path.stat().st_mtime_ns,
                }
            )

        generated_path_lookup: dict[str, str] = {}
        normalized_embedded_generated_files: list[CodeConsoleProjectGeneratedFilePayload] = []
        for embedded_generated_file, generated_bytes, actual_sha256 in materialized_generated_files:
            restore_name = _unique_restore_name(embedded_generated_file.name, seen=seen_restore_names)
            restored_generated_path = restore_dir / restore_name
            restored_generated_path.write_bytes(generated_bytes)
            if embedded_generated_file.original_path:
                generated_path_lookup[str(Path(embedded_generated_file.original_path).expanduser())] = str(
                    restored_generated_path
                )
                generated_path_lookup[embedded_generated_file.original_path] = str(restored_generated_path)
            generated_path_lookup[embedded_generated_file.name] = str(restored_generated_path)
            normalized_embedded_generated_files.append(
                embedded_generated_file.model_copy(
                    update={
                        "file_sha256": actual_sha256,
                        "size_bytes": len(generated_bytes),
                    }
                )
            )
        if code_console_map is not None:
            code_console_map = _remap_code_console_paths(
                code_console_map,
                manual_binding=normalized_manual_binding,
                generated_path_lookup=generated_path_lookup,
                embedded_generated_files=normalized_embedded_generated_files,
            )

        normalized_payload = normalize_project_payload(
            {
                "version": raw_payload_map.get("version", _PROJECT_VERSION),
                "selected_workbench": selected_workbench,
                "plot": plot_map,
                "data_studio": data_studio_map,
                "composer": composer_map,
                "code_console": code_console_map,
                "document_graph": raw_payload_map.get("document_graph"),
                "artifacts": raw_payload_map.get("artifacts"),
            },
            source_path=restored_source_path,
        )

        payload_updates: dict[str, object] = {}
        if normalized_payload.plot is not None and restored_source_path is not None:
            payload_updates["plot"] = normalized_payload.plot.model_copy(
                update={
                    "source_media_type": (
                        normalized_payload.plot.source_media_type or _media_type_for(restored_source_path)
                    ),
                    "project_display_name": normalized_payload.plot.project_display_name or project_path.stem,
                }
            )
        if normalized_payload.data_studio is not None:
            payload_updates["data_studio"] = normalized_payload.data_studio.model_copy(
                update={
                    "embedded_workbooks": normalized_embedded_workbooks,
                    "project_display_name": normalized_payload.data_studio.project_display_name or project_path.stem,
                }
            )
        if normalized_payload.composer is not None:
            payload_updates["composer"] = normalized_payload.composer.model_copy(
                update={
                    "embedded_panels": normalized_embedded_panels,
                    "project_display_name": normalized_payload.composer.project_display_name or project_path.stem,
                }
            )
        if normalized_payload.code_console is not None:
            payload_updates["code_console"] = normalized_payload.code_console.model_copy(
                update={
                    "manual_binding": normalized_manual_binding,
                    "embedded_generated_files": normalized_embedded_generated_files,
                    "project_display_name": normalized_payload.code_console.project_display_name or project_path.stem,
                }
            )

        return OpenProjectResponse(
            project_path=str(project_path),
            restored_source_path=str(restored_source_path) if restored_source_path is not None else None,
            restored_workbook_paths=restored_workbook_paths,
            payload=normalized_payload.model_copy(update=payload_updates),
        )


def normalize_project_path(path_text: str) -> Path:
    path = normalize_path(path_text)
    if not is_supported_project_path(path):
        raise ValueError(project_extension_error())
    return path


__all__ = [
    "PROJECT_FILE_EXTENSION",
    "is_supported_project_path",
    "normalize_project_path",
    "normalize_project_payload",
    "open_project_bundle",
    "project_extension_error",
    "save_project_bundle",
]
