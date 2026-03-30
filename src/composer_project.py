from __future__ import annotations

from collections.abc import Iterable
from string import ascii_uppercase
from typing import Any, Literal

from src.composer_types import (
    COMPOSER_CANVAS_HEIGHT_MM,
    COMPOSER_CANVAS_WIDTH_MM,
    COMPOSER_CELL_HEIGHT_MM,
    COMPOSER_CELL_WIDTH_MM,
    COMPOSER_GRID_COLUMNS,
    COMPOSER_GRID_MM,
    COMPOSER_GRID_ROWS,
    COMPOSER_LAYOUT_FRAME_HEIGHT_MM,
    COMPOSER_LAYOUT_FRAME_X_MM,
    COMPOSER_LAYOUT_FRAME_Y_MM,
    COMPOSER_VERSION,
    ComposerCropRect,
    ComposerLayoutGrid,
    ComposerPanel,
    ComposerProject,
    ComposerRegion,
    ComposerText,
    _default_layout_grid,
)


def composer_layout_grid(project: ComposerProject) -> ComposerLayoutGrid:
    return project.layout_grid or _default_layout_grid(project)


def region_rect_mm(
    project: ComposerProject,
    region: ComposerRegion,
) -> tuple[float, float, float, float]:
    grid = composer_layout_grid(project)
    return (
        grid.frame_x_mm + region.col * grid.cell_width_mm,
        grid.frame_y_mm + region.row * grid.cell_height_mm,
        region.col_span * grid.cell_width_mm,
        region.row_span * grid.cell_height_mm,
    )


def region_slot_id(region: ComposerRegion) -> str | None:
    if region.slot_kind != "structure":
        return None
    return f"{region.id}:structure"


def region_slot_rect_mm(
    project: ComposerProject,
    region: ComposerRegion,
) -> tuple[float, float, float, float] | None:
    slot_id = region_slot_id(region)
    if slot_id is None:
        return None
    x_mm, y_mm, w_mm, _ = region_rect_mm(project, region)
    return (x_mm, y_mm, w_mm, composer_layout_grid(project).cell_height_mm)


def normalize_crop_rect(crop_rect: ComposerCropRect | None) -> ComposerCropRect:
    rect = crop_rect or ComposerCropRect()
    x = min(max(float(rect.x), 0.0), 0.999)
    y = min(max(float(rect.y), 0.0), 0.999)
    width = min(max(float(rect.width), 0.001), 1.0 - x)
    height = min(max(float(rect.height), 0.001), 1.0 - y)
    return ComposerCropRect(x=x, y=y, width=width, height=height)


def parse_crop_rect(payload: Any) -> ComposerCropRect:
    if isinstance(payload, ComposerCropRect):
        return normalize_crop_rect(payload)
    if isinstance(payload, dict):
        return normalize_crop_rect(
            ComposerCropRect(
                x=float(payload.get("x", 0.0)),
                y=float(payload.get("y", 0.0)),
                width=float(payload.get("width", 1.0)),
                height=float(payload.get("height", 1.0)),
            )
        )
    return ComposerCropRect()


def region_by_id(project: ComposerProject) -> dict[str, ComposerRegion]:
    return {region.id: region for region in project.regions}


def next_numeric_id(existing_ids: Iterable[str], prefix: str) -> str:
    next_index = 1
    taken = {item for item in existing_ids}
    while f"{prefix}-{next_index}" in taken:
        next_index += 1
    return f"{prefix}-{next_index}"


def drawable_z_pairs(
    project: ComposerProject,
) -> list[tuple[Literal["panel", "text"], str, int]]:
    pairs: list[tuple[Literal["panel", "text"], str, int]] = []
    for index, panel in enumerate(project.panels):
        pairs.append(("panel", panel.id, index))
    for text in project.texts:
        pairs.append(("text", text.id, int(text.z_index)))
    return sorted(pairs, key=lambda item: (item[2], item[0], item[1]))


def assign_z_indexes(project: ComposerProject) -> None:
    next_z = 0
    for panel in project.panels:
        panel.z_index = int(panel.z_index)
    for text in project.texts:
        text.z_index = int(text.z_index)
    for kind, item_id, _ in drawable_z_pairs(project):
        if kind == "panel":
            panel_match = next((item for item in project.panels if item.id == item_id), None)
            if panel_match is not None:
                panel_match.z_index = next_z
        else:
            text_match = next((item for item in project.texts if item.id == item_id), None)
            if text_match is not None:
                text_match.z_index = next_z
        next_z += 1


def _normalize_layout_grid(project: ComposerProject) -> None:
    project.layout_grid = _default_layout_grid(project)


def _normalize_regions(project: ComposerProject) -> None:
    grid = composer_layout_grid(project)
    normalized: list[ComposerRegion] = []
    for region in project.regions:
        normalized.append(
            ComposerRegion(
                id=region.id,
                kind=region.kind,
                col=max(0, min(grid.columns - 1, int(region.col))),
                row=max(0, min(grid.rows - 1, int(region.row))),
                col_span=max(1, min(grid.columns, int(region.col_span))),
                row_span=max(1, min(grid.rows, int(region.row_span))),
                label=region.label,
                locked=bool(region.locked),
                slot_kind=region.slot_kind if region.slot_kind == "structure" else None,
            )
        )
    project.regions = normalized


def _normalize_panels(project: ComposerProject) -> None:
    region_lookup = region_by_id(project)
    for panel in project.panels:
        panel.crop_rect = normalize_crop_rect(panel.crop_rect)
        panel.locked = bool(panel.locked)
        panel.hidden = bool(panel.hidden)
        panel.group_id = str(panel.group_id) if panel.group_id else None
        panel.kind = "asset" if panel.kind == "asset" else "graph"
        if panel.kind == "graph" and panel.region_id and panel.region_id in region_lookup:
            x_mm, y_mm, w_mm, h_mm = region_rect_mm(project, region_lookup[panel.region_id])
            panel.x_mm = x_mm
            panel.y_mm = y_mm
            panel.w_mm = w_mm
            panel.h_mm = h_mm
        else:
            panel.x_mm = min(
                max(float(panel.x_mm), 0.0),
                max(0.0, project.canvas_width_mm - panel.w_mm),
            )
            panel.y_mm = min(
                max(float(panel.y_mm), 0.0),
                max(0.0, project.canvas_height_mm - panel.h_mm),
            )
            panel.w_mm = min(max(float(panel.w_mm), 1.0), project.canvas_width_mm)
            panel.h_mm = min(max(float(panel.h_mm), 1.0), project.canvas_height_mm)


def _normalize_texts(project: ComposerProject) -> None:
    for text in project.texts:
        text.align = text.align if text.align in {"left", "center", "right"} else "left"
        text.font_size_pt = min(max(float(text.font_size_pt), 5.0), 72.0)
        text.locked = bool(text.locked)
        text.hidden = bool(text.hidden)
        text.group_id = str(text.group_id) if text.group_id else None
        text.x_mm = min(max(float(text.x_mm), 0.0), project.canvas_width_mm)
        text.y_mm = min(max(float(text.y_mm), 0.0), project.canvas_height_mm)


def normalize_project(project: ComposerProject) -> ComposerProject:
    project.version = COMPOSER_VERSION
    project.mode = "composer"
    project.canvas_width_mm = COMPOSER_CANVAS_WIDTH_MM
    project.canvas_height_mm = COMPOSER_CANVAS_HEIGHT_MM
    project.grid_mm = COMPOSER_GRID_MM
    _normalize_layout_grid(project)
    _normalize_regions(project)
    _normalize_panels(project)
    _normalize_texts(project)
    assign_z_indexes(project)
    return project


def project_from_dict(data: dict[str, Any]) -> ComposerProject:
    payload = data.get("project") if isinstance(data.get("project"), dict) else data
    if not isinstance(payload, dict):
        raise ValueError("Invalid Composer project field.")
    if payload.get("mode") != "composer":
        raise ValueError("This is not a recognizable Composer project file.")
    if int(payload.get("version", 0)) != COMPOSER_VERSION:
        raise ValueError("Composer projects only support version: 2.")

    layout_grid_payload = payload.get("layout_grid") or {}
    regions_payload = payload.get("regions") or []
    panels_payload = payload.get("panels") or []
    texts_payload = payload.get("texts") or []
    project = ComposerProject(
        version=COMPOSER_VERSION,
        mode="composer",
        canvas_width_mm=float(payload.get("canvas_width_mm", COMPOSER_CANVAS_WIDTH_MM)),
        canvas_height_mm=float(payload.get("canvas_height_mm", COMPOSER_CANVAS_HEIGHT_MM)),
        grid_mm=float(payload.get("grid_mm", COMPOSER_GRID_MM)),
        layout_grid=ComposerLayoutGrid(
            columns=int(layout_grid_payload.get("columns", COMPOSER_GRID_COLUMNS)),
            rows=int(layout_grid_payload.get("rows", COMPOSER_GRID_ROWS)),
            cell_width_mm=float(layout_grid_payload.get("cell_width_mm", COMPOSER_CELL_WIDTH_MM)),
            cell_height_mm=float(layout_grid_payload.get("cell_height_mm", COMPOSER_CELL_HEIGHT_MM)),
            frame_x_mm=float(layout_grid_payload.get("frame_x_mm", COMPOSER_LAYOUT_FRAME_X_MM)),
            frame_y_mm=float(layout_grid_payload.get("frame_y_mm", COMPOSER_LAYOUT_FRAME_Y_MM)),
            frame_width_mm=float(layout_grid_payload.get("frame_width_mm", COMPOSER_CANVAS_WIDTH_MM)),
            frame_height_mm=float(
                layout_grid_payload.get("frame_height_mm", COMPOSER_LAYOUT_FRAME_HEIGHT_MM)
            ),
        ),
        regions=[
            ComposerRegion(
                id=str(item["id"]),
                kind=str(item.get("kind", "free")),
                col=int(item.get("col", 0)),
                row=int(item.get("row", 0)),
                col_span=int(item.get("col_span", 1)),
                row_span=int(item.get("row_span", 1)),
                label=item.get("label"),
                locked=bool(item.get("locked", False)),
                slot_kind=item.get("slot_kind"),
            )
            for item in regions_payload
            if isinstance(item, dict)
        ],
        panels=[
            ComposerPanel(
                id=str(item["id"]),
                file_path=str(item["file_path"]),
                page_index=int(item.get("page_index", 0)),
                x_mm=float(item.get("x_mm", 0.0)),
                y_mm=float(item.get("y_mm", 0.0)),
                w_mm=float(item.get("w_mm", COMPOSER_CELL_WIDTH_MM)),
                h_mm=float(item.get("h_mm", COMPOSER_CELL_HEIGHT_MM)),
                locked=bool(item.get("locked", False)),
                hidden=bool(item.get("hidden", False)),
                label=item.get("label"),
                kind=str(item.get("kind", "graph")),
                z_index=int(item.get("z_index", 0)),
                group_id=item.get("group_id"),
                region_id=item.get("region_id"),
                slot_id=item.get("slot_id"),
                crop_rect=parse_crop_rect(item.get("crop_rect")),
            )
            for item in panels_payload
            if isinstance(item, dict)
        ],
        texts=[
            ComposerText(
                id=str(item["id"]),
                text=str(item.get("text", "")),
                x_mm=float(item.get("x_mm", 0.0)),
                y_mm=float(item.get("y_mm", 0.0)),
                font_size_pt=float(item.get("font_size_pt", 8.0)),
                align=str(item.get("align", "left")),
                z_index=int(item.get("z_index", 0)),
                locked=bool(item.get("locked", False)),
                hidden=bool(item.get("hidden", False)),
                group_id=item.get("group_id"),
                region_id=item.get("region_id"),
                slot_id=item.get("slot_id"),
            )
            for item in texts_payload
            if isinstance(item, dict)
        ],
        auto_labels=bool(payload.get("auto_labels", True)),
    )
    return normalize_project(project)


def resolve_panel_labels(project: ComposerProject) -> dict[str, str]:
    graph_panels = [
        panel for panel in project.panels if panel.kind == "graph" and not panel.hidden
    ]
    if not project.auto_labels:
        return {panel.id: panel.label or "" for panel in graph_panels}
    return {
        panel.id: (
            ascii_uppercase[index]
            if index < len(ascii_uppercase)
            else chr(ord("A") + index)
        )
        for index, panel in enumerate(graph_panels)
    }


__all__ = [
    "assign_z_indexes",
    "composer_layout_grid",
    "drawable_z_pairs",
    "next_numeric_id",
    "normalize_crop_rect",
    "normalize_project",
    "parse_crop_rect",
    "project_from_dict",
    "region_by_id",
    "region_rect_mm",
    "region_slot_id",
    "region_slot_rect_mm",
    "resolve_panel_labels",
]
