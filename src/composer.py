from __future__ import annotations

import html
from collections.abc import Iterable
from dataclasses import asdict, dataclass, field, replace
from io import BytesIO
from pathlib import Path
from string import ascii_lowercase
from typing import Any, Literal, cast

import fitz
from PIL import Image, ImageDraw, ImageFont

MM_TO_PT = 72.0 / 25.4
PT_TO_MM = 25.4 / 72.0
COMPOSER_VERSION = 2
COMPOSER_CANVAS_WIDTH_MM = 180.0
COMPOSER_CANVAS_HEIGHT_MM = 170.0
COMPOSER_GRID_COLUMNS = 3
COMPOSER_GRID_ROWS = 3
COMPOSER_CELL_WIDTH_MM = 60.0
COMPOSER_CELL_HEIGHT_MM = 55.0
COMPOSER_LAYOUT_FRAME_HEIGHT_MM = COMPOSER_CELL_HEIGHT_MM * COMPOSER_GRID_ROWS
COMPOSER_LAYOUT_FRAME_Y_MM = (COMPOSER_CANVAS_HEIGHT_MM - COMPOSER_LAYOUT_FRAME_HEIGHT_MM) / 2.0
COMPOSER_LAYOUT_FRAME_X_MM = 0.0
COMPOSER_GRID_MM = 0.5
RASTER_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"}
GRAPH_SIZE_TOLERANCE_MM = 1.2
GRAPH_SIZE_RULES: tuple[tuple[float, float, int, int, str | None], ...] = (
    (60.0, 55.0, 1, 1, None),
    (120.0, 55.0, 2, 1, None),
    (60.0, 110.0, 1, 2, "structure"),
)


def mm_to_pt(value_mm: float) -> float:
    return value_mm * MM_TO_PT


def pt_to_mm(value_pt: float) -> float:
    return value_pt * PT_TO_MM


def mm_to_px(value_mm: float, dpi: float) -> int:
    return max(1, int(round(value_mm / 25.4 * dpi)))


@dataclass
class ComposerCropRect:
    x: float = 0.0
    y: float = 0.0
    width: float = 1.0
    height: float = 1.0


@dataclass
class ComposerLayoutGrid:
    columns: int = COMPOSER_GRID_COLUMNS
    rows: int = COMPOSER_GRID_ROWS
    cell_width_mm: float = COMPOSER_CELL_WIDTH_MM
    cell_height_mm: float = COMPOSER_CELL_HEIGHT_MM
    frame_x_mm: float = COMPOSER_LAYOUT_FRAME_X_MM
    frame_y_mm: float = COMPOSER_LAYOUT_FRAME_Y_MM
    frame_width_mm: float = COMPOSER_CELL_WIDTH_MM * COMPOSER_GRID_COLUMNS
    frame_height_mm: float = COMPOSER_LAYOUT_FRAME_HEIGHT_MM


@dataclass
class ComposerRegion:
    id: str
    kind: str
    col: int
    row: int
    col_span: int
    row_span: int
    label: str | None = None
    locked: bool = False
    slot_kind: str | None = None


@dataclass
class ComposerPanel:
    id: str
    file_path: str
    page_index: int
    x_mm: float
    y_mm: float
    w_mm: float
    h_mm: float
    locked: bool = False
    hidden: bool = False
    label: str | None = None
    kind: str = "graph"
    z_index: int = 0
    group_id: str | None = None
    region_id: str | None = None
    slot_id: str | None = None
    crop_rect: ComposerCropRect = field(default_factory=ComposerCropRect)


@dataclass
class ComposerText:
    id: str
    text: str
    x_mm: float
    y_mm: float
    font_size_pt: float = 8.0
    align: str = "left"
    z_index: int = 0
    locked: bool = False
    hidden: bool = False
    group_id: str | None = None
    region_id: str | None = None
    slot_id: str | None = None


@dataclass
class ComposerProject:
    version: int = COMPOSER_VERSION
    mode: str = "composer"
    canvas_width_mm: float = COMPOSER_CANVAS_WIDTH_MM
    canvas_height_mm: float = COMPOSER_CANVAS_HEIGHT_MM
    grid_mm: float = COMPOSER_GRID_MM
    layout_grid: ComposerLayoutGrid = field(default_factory=ComposerLayoutGrid)
    regions: list[ComposerRegion] = field(default_factory=list)
    panels: list[ComposerPanel] = field(default_factory=list)
    texts: list[ComposerText] = field(default_factory=list)
    auto_labels: bool = True

    def to_dict(self) -> dict[str, Any]:
        return serialize_project(self)


def serialize_project(project: ComposerProject) -> dict[str, Any]:
    return {
        "version": project.version,
        "mode": project.mode,
        "canvas_width_mm": project.canvas_width_mm,
        "canvas_height_mm": project.canvas_height_mm,
        "grid_mm": project.grid_mm,
        "layout_grid": asdict(project.layout_grid),
        "regions": [asdict(region) for region in project.regions],
        "panels": [asdict(panel) for panel in project.panels],
        "texts": [asdict(text) for text in project.texts],
        "auto_labels": project.auto_labels,
    }


def _default_layout_grid(project: ComposerProject | None = None) -> ComposerLayoutGrid:
    canvas_width_mm = project.canvas_width_mm if project else COMPOSER_CANVAS_WIDTH_MM
    canvas_height_mm = project.canvas_height_mm if project else COMPOSER_CANVAS_HEIGHT_MM
    frame_height_mm = COMPOSER_CELL_HEIGHT_MM * COMPOSER_GRID_ROWS
    return ComposerLayoutGrid(
        columns=COMPOSER_GRID_COLUMNS,
        rows=COMPOSER_GRID_ROWS,
        cell_width_mm=COMPOSER_CELL_WIDTH_MM,
        cell_height_mm=COMPOSER_CELL_HEIGHT_MM,
        frame_x_mm=0.0,
        frame_y_mm=max(0.0, (canvas_height_mm - frame_height_mm) / 2.0),
        frame_width_mm=min(canvas_width_mm, COMPOSER_CELL_WIDTH_MM * COMPOSER_GRID_COLUMNS),
        frame_height_mm=frame_height_mm,
    )


def _font(size: int) -> ImageFont.ImageFont:
    try:
        return ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", size)
    except Exception:
        return ImageFont.load_default()


def _is_pdf_path(file_path: str | Path) -> bool:
    return Path(file_path).suffix.lower() == ".pdf"


def _is_raster_path(file_path: str | Path) -> bool:
    return Path(file_path).suffix.lower() in RASTER_EXTENSIONS


def pdf_page_size_pt(file_path: str | Path, page_index: int = 0) -> tuple[float, float]:
    document = fitz.open(str(file_path))
    try:
        page = document.load_page(page_index)
        return float(page.rect.width), float(page.rect.height)
    finally:
        document.close()


def pdf_page_aspect_ratio(file_path: str | Path, page_index: int = 0) -> float:
    width_pt, height_pt = pdf_page_size_pt(file_path, page_index)
    if width_pt <= 0 or height_pt <= 0:
        return 1.0
    return width_pt / height_pt


def image_aspect_ratio(file_path: str | Path) -> float:
    with Image.open(file_path) as image:
        width_px, height_px = image.size
    if width_px <= 0 or height_px <= 0:
        return 1.0
    return width_px / height_px


def panel_aspect_ratio(file_path: str | Path, page_index: int = 0) -> float:
    if _is_pdf_path(file_path):
        return pdf_page_aspect_ratio(file_path, page_index)
    if _is_raster_path(file_path):
        return image_aspect_ratio(file_path)
    raise ValueError(f"Unsupported panel asset type: {file_path}")


def composer_layout_grid(project: ComposerProject) -> ComposerLayoutGrid:
    return project.layout_grid or _default_layout_grid(project)


def region_rect_mm(project: ComposerProject, region: ComposerRegion) -> tuple[float, float, float, float]:
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


def region_slot_rect_mm(project: ComposerProject, region: ComposerRegion) -> tuple[float, float, float, float] | None:
    slot_id = region_slot_id(region)
    if slot_id is None:
        return None
    x_mm, y_mm, w_mm, _ = region_rect_mm(project, region)
    return (x_mm, y_mm, w_mm, composer_layout_grid(project).cell_height_mm)


def _normalize_crop_rect(crop_rect: ComposerCropRect | None) -> ComposerCropRect:
    rect = crop_rect or ComposerCropRect()
    x = min(max(float(rect.x), 0.0), 0.999)
    y = min(max(float(rect.y), 0.0), 0.999)
    width = min(max(float(rect.width), 0.001), 1.0 - x)
    height = min(max(float(rect.height), 0.001), 1.0 - y)
    return ComposerCropRect(x=x, y=y, width=width, height=height)


def _region_by_id(project: ComposerProject) -> dict[str, ComposerRegion]:
    return {region.id: region for region in project.regions}


def _next_numeric_id(existing_ids: Iterable[str], prefix: str) -> str:
    next_index = 1
    taken = {item for item in existing_ids}
    while f"{prefix}-{next_index}" in taken:
        next_index += 1
    return f"{prefix}-{next_index}"


def _drawable_z_pairs(project: ComposerProject) -> list[tuple[Literal["panel", "text"], str, int]]:
    pairs: list[tuple[Literal["panel", "text"], str, int]] = []
    for panel in project.panels:
        pairs.append(("panel", panel.id, int(panel.z_index)))
    for text in project.texts:
        pairs.append(("text", text.id, int(text.z_index)))
    return sorted(pairs, key=lambda item: (item[2], item[0], item[1]))


def _assign_z_indexes(project: ComposerProject) -> None:
    next_z = 0
    for panel in project.panels:
        panel.z_index = int(panel.z_index)
    for text in project.texts:
        text.z_index = int(text.z_index)
    for kind, item_id, _ in _drawable_z_pairs(project):
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
    region_lookup = _region_by_id(project)
    for panel in project.panels:
        panel.crop_rect = _normalize_crop_rect(panel.crop_rect)
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
            panel.x_mm = min(max(float(panel.x_mm), 0.0), max(0.0, project.canvas_width_mm - panel.w_mm))
            panel.y_mm = min(max(float(panel.y_mm), 0.0), max(0.0, project.canvas_height_mm - panel.h_mm))
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
    _assign_z_indexes(project)
    return project


def _parse_crop_rect(payload: Any) -> ComposerCropRect:
    if isinstance(payload, ComposerCropRect):
        return _normalize_crop_rect(payload)
    if isinstance(payload, dict):
        return _normalize_crop_rect(
            ComposerCropRect(
                x=float(payload.get("x", 0.0)),
                y=float(payload.get("y", 0.0)),
                width=float(payload.get("width", 1.0)),
                height=float(payload.get("height", 1.0)),
            )
        )
    return ComposerCropRect()


def project_from_dict(data: dict[str, Any]) -> ComposerProject:
    payload = data.get("project") if isinstance(data.get("project"), dict) else data
    if not isinstance(payload, dict):
        raise ValueError("拼图项目字段无效。")
    if payload.get("mode") != "composer":
        raise ValueError("这不是可识别的拼图器项目文件。")
    if int(payload.get("version", 0)) != COMPOSER_VERSION:
        raise ValueError("Composer 项目仅支持 version: 2。")

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
            frame_height_mm=float(layout_grid_payload.get("frame_height_mm", COMPOSER_LAYOUT_FRAME_HEIGHT_MM)),
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
                crop_rect=_parse_crop_rect(item.get("crop_rect")),
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
    graph_panels = [panel for panel in project.panels if panel.kind == "graph"]
    if not project.auto_labels:
        return {panel.id: panel.label or "" for panel in graph_panels}
    ordered = sorted(
        graph_panels,
        key=lambda panel: (round(panel.y_mm, 3), round(panel.x_mm, 3), panel.id),
    )
    return {
        panel.id: ascii_lowercase[index] if index < len(ascii_lowercase) else chr(ord("a") + index)
        for index, panel in enumerate(ordered)
    }


def panel_thumbnail_png(file_path: str | Path, page_index: int = 0, *, max_side_px: int = 640) -> bytes:
    if _is_pdf_path(file_path):
        document = fitz.open(str(file_path))
        try:
            page = document.load_page(page_index)
            rect = page.rect
            scale = max_side_px / max(rect.width, rect.height)
            scale = max(scale, 0.2)
            pix = page.get_pixmap(matrix=fitz.Matrix(scale, scale), alpha=False)
            return pix.tobytes("png")
        finally:
            document.close()
    if _is_raster_path(file_path):
        with Image.open(file_path) as image:
            image = image.convert("RGBA")
            image.thumbnail((max_side_px, max_side_px), Image.Resampling.LANCZOS)
            output = BytesIO()
            image.save(output, format="PNG")
            return output.getvalue()
    raise ValueError(f"Unsupported panel asset type: {file_path}")


def _crop_image(image: Image.Image, crop_rect: ComposerCropRect) -> Image.Image:
    width, height = image.size
    left = int(round(crop_rect.x * width))
    top = int(round(crop_rect.y * height))
    right = int(round((crop_rect.x + crop_rect.width) * width))
    bottom = int(round((crop_rect.y + crop_rect.height) * height))
    right = max(left + 1, min(right, width))
    bottom = max(top + 1, min(bottom, height))
    return image.crop((left, top, right, bottom))


def _fit_asset_panel_size_mm(
    file_path: str | Path,
    max_width_mm: float,
    max_height_mm: float,
    page_index: int = 0,
) -> tuple[float, float]:
    aspect_ratio = panel_aspect_ratio(file_path, page_index)
    width_mm = max_width_mm
    height_mm = width_mm / max(aspect_ratio, 1e-6)
    if height_mm > max_height_mm:
        height_mm = max_height_mm
        width_mm = height_mm * max(aspect_ratio, 1e-6)
    return max(12.0, width_mm), max(12.0, height_mm)


def _match_graph_pdf_span(file_path: str | Path, page_index: int = 0) -> tuple[int, int, str | None]:
    width_pt, height_pt = pdf_page_size_pt(file_path, page_index)
    width_mm = pt_to_mm(width_pt)
    height_mm = pt_to_mm(height_pt)
    for expected_width_mm, expected_height_mm, col_span, row_span, slot_kind in GRAPH_SIZE_RULES:
        width_ok = abs(width_mm - expected_width_mm) <= GRAPH_SIZE_TOLERANCE_MM
        height_ok = abs(height_mm - expected_height_mm) <= GRAPH_SIZE_TOLERANCE_MM
        if width_ok and height_ok:
            return col_span, row_span, slot_kind
    raise ValueError(
        "Graph 模式只接受 60x55、120x55 或 60x110 mm 的 CodeGod PDF；请改用 asset 模式导入。"
    )


def _cell_occupancy(project: ComposerProject, *, skip_region_id: str | None = None) -> set[tuple[int, int]]:
    occupied: set[tuple[int, int]] = set()
    for region in project.regions:
        if region.id == skip_region_id:
            continue
        for col in range(region.col, region.col + region.col_span):
            for row in range(region.row, region.row + region.row_span):
                occupied.add((col, row))
    return occupied


def _find_first_fit(project: ComposerProject, col_span: int, row_span: int) -> tuple[int, int]:
    grid = composer_layout_grid(project)
    occupied = _cell_occupancy(project)
    for row in range(grid.rows - row_span + 1):
        for col in range(grid.columns - col_span + 1):
            cells = {
                (check_col, check_row)
                for check_col in range(col, col + col_span)
                for check_row in range(row, row + row_span)
            }
            if occupied.isdisjoint(cells):
                return col, row
    raise ValueError("画布网格没有足够连续空位了。")


def _next_panel_id(project: ComposerProject, kind: str) -> str:
    prefix = "asset" if kind == "asset" else "panel"
    return _next_numeric_id((panel.id for panel in project.panels), prefix)


def _next_region_id(project: ComposerProject) -> str:
    return _next_numeric_id((region.id for region in project.regions), "region")


def _graph_panel_for_region(project: ComposerProject, region_id: str) -> ComposerPanel | None:
    for panel in project.panels:
        if panel.kind == "graph" and panel.region_id == region_id:
            return panel
    return None


def _sorted_drawables(
    project: ComposerProject,
) -> list[tuple[Literal["panel", "text"], ComposerPanel | ComposerText]]:
    drawables: list[tuple[Literal["panel", "text"], ComposerPanel | ComposerText]] = []
    for panel in project.panels:
        drawables.append(("panel", panel))
    for text in project.texts:
        drawables.append(("text", text))
    drawables.sort(key=lambda item: (item[1].z_index, 0 if item[0] == "panel" else 1, item[1].id))
    return drawables


def import_panels_from_paths(
    project: ComposerProject,
    file_paths: list[str | Path],
    *,
    kind: str,
) -> ComposerProject:
    next_project = normalize_project(
        ComposerProject(
            version=project.version,
            mode=project.mode,
            canvas_width_mm=project.canvas_width_mm,
            canvas_height_mm=project.canvas_height_mm,
            grid_mm=project.grid_mm,
            layout_grid=replace(project.layout_grid),
            regions=[replace(region) for region in project.regions],
            panels=[replace(panel, crop_rect=replace(panel.crop_rect)) for panel in project.panels],
            texts=[replace(text) for text in project.texts],
            auto_labels=project.auto_labels,
        )
    )
    next_z = len(next_project.panels) + len(next_project.texts)
    for raw_path in file_paths:
        normalized_path = Path(raw_path).expanduser()
        if kind == "graph":
            if not _is_pdf_path(normalized_path):
                raise ValueError("Graph 模式只支持 PDF。")
            col_span, row_span, slot_kind = _match_graph_pdf_span(normalized_path)
            col, row = _find_first_fit(next_project, col_span, row_span)
            region = ComposerRegion(
                id=_next_region_id(next_project),
                kind="graph",
                col=col,
                row=row,
                col_span=col_span,
                row_span=row_span,
                slot_kind=slot_kind,
            )
            next_project.regions.append(region)
            x_mm, y_mm, w_mm, h_mm = region_rect_mm(next_project, region)
            next_project.panels.append(
                ComposerPanel(
                    id=_next_panel_id(next_project, "graph"),
                    file_path=str(normalized_path),
                    page_index=0,
                    x_mm=x_mm,
                    y_mm=y_mm,
                    w_mm=w_mm,
                    h_mm=h_mm,
                    kind="graph",
                    z_index=next_z,
                    region_id=region.id,
                )
            )
        else:
            max_width_mm = next_project.layout_grid.cell_width_mm - 8.0
            max_height_mm = next_project.layout_grid.cell_height_mm - 8.0
            w_mm, h_mm = _fit_asset_panel_size_mm(normalized_path, max_width_mm, max_height_mm, 0)
            x_mm = (next_project.canvas_width_mm - w_mm) / 2.0
            y_mm = (next_project.canvas_height_mm - h_mm) / 2.0
            next_project.panels.append(
                ComposerPanel(
                    id=_next_panel_id(next_project, "asset"),
                    file_path=str(normalized_path),
                    page_index=0,
                    x_mm=x_mm,
                    y_mm=y_mm,
                    w_mm=w_mm,
                    h_mm=h_mm,
                    kind="asset",
                    z_index=next_z,
                )
            )
        next_z += 1
    return normalize_project(next_project)


def _project_with_graph_regions(file_paths: list[str | Path], placements: list[tuple[int, int]]) -> ComposerProject:
    project = ComposerProject()
    for raw_path, (col, row) in zip(file_paths, placements, strict=False):
        normalized_path = Path(raw_path).expanduser()
        col_span, row_span, slot_kind = _match_graph_pdf_span(normalized_path)
        region = ComposerRegion(
            id=_next_region_id(project),
            kind="graph",
            col=col,
            row=row,
            col_span=col_span,
            row_span=row_span,
            slot_kind=slot_kind,
        )
        project.regions.append(region)
        x_mm, y_mm, w_mm, h_mm = region_rect_mm(project, region)
        project.panels.append(
            ComposerPanel(
                id=_next_panel_id(project, "graph"),
                file_path=str(normalized_path),
                page_index=0,
                x_mm=x_mm,
                y_mm=y_mm,
                w_mm=w_mm,
                h_mm=h_mm,
                kind="graph",
                z_index=len(project.panels),
                region_id=region.id,
            )
        )
    return normalize_project(project)


def three_up_panels_from_paths(file_paths: list[str | Path]) -> ComposerProject:
    return _project_with_graph_regions(file_paths[:3], [(0, 0), (1, 0), (2, 0)])


def two_up_editorial_panels_from_paths(file_paths: list[str | Path]) -> ComposerProject:
    project = _project_with_graph_regions(file_paths[:2], [(0, 0), (1, 0)])
    project.regions.append(
        ComposerRegion(
            id=_next_region_id(project),
            kind="free",
            col=2,
            row=0,
            col_span=1,
            row_span=2,
            label="Editorial",
        )
    )
    return normalize_project(project)


def _draw_text(draw: ImageDraw.ImageDraw, text: ComposerText, dpi: float) -> None:
    x_px = mm_to_px(text.x_mm, dpi)
    y_px = mm_to_px(text.y_mm, dpi)
    font = _font(max(8, int(round(text.font_size_pt * dpi / 72.0))))
    bbox = draw.textbbox((0, 0), text.text, font=font)
    width = bbox[2] - bbox[0]
    anchor_x = x_px
    if text.align == "center":
        anchor_x -= width // 2
    elif text.align == "right":
        anchor_x -= width
    draw.text((anchor_x, y_px), text.text, font=font, fill=(24, 24, 24))


def _panel_label_text(project: ComposerProject, panel: ComposerPanel) -> str:
    return resolve_panel_labels(project).get(panel.id, "")


def compose_preview_png(project: ComposerProject, *, dpi: int = 144) -> bytes:
    normalized = normalize_project(project)
    canvas_width_px = mm_to_px(normalized.canvas_width_mm, dpi)
    canvas_height_px = mm_to_px(normalized.canvas_height_mm, dpi)
    canvas_image = Image.new("RGBA", (canvas_width_px, canvas_height_px), (255, 255, 255, 255))
    draw = ImageDraw.Draw(canvas_image)
    label_font = _font(max(10, int(round(9 * dpi / 72.0))))

    for kind, drawable in _sorted_drawables(normalized):
        if kind == "panel":
            panel = cast(ComposerPanel, drawable)
            if panel.hidden:
                continue
            source = Image.open(BytesIO(panel_thumbnail_png(panel.file_path, panel.page_index))).convert("RGBA")
            panel_image = _crop_image(source, panel.crop_rect)
            target_width_px = mm_to_px(panel.w_mm, dpi)
            target_height_px = mm_to_px(panel.h_mm, dpi)
            panel_image = panel_image.resize((target_width_px, target_height_px), Image.Resampling.LANCZOS)
            x_px = mm_to_px(panel.x_mm, dpi)
            y_px = mm_to_px(panel.y_mm, dpi)
            canvas_image.alpha_composite(panel_image, (x_px, y_px))
            if normalized.auto_labels and panel.kind == "graph":
                label = _panel_label_text(normalized, panel)
                if label:
                    draw.text((x_px + 8, y_px + 8), label, font=label_font, fill=(24, 24, 24))
        else:
            text = cast(ComposerText, drawable)
            if text.hidden:
                continue
            _draw_text(draw, text, dpi)

    output = BytesIO()
    canvas_image.convert("RGB").save(output, format="PNG")
    return output.getvalue()


def _pdf_clip_rect(panel: ComposerPanel, source_rect: fitz.Rect) -> fitz.Rect:
    crop = _normalize_crop_rect(panel.crop_rect)
    return fitz.Rect(
        source_rect.x0 + source_rect.width * crop.x,
        source_rect.y0 + source_rect.height * crop.y,
        source_rect.x0 + source_rect.width * (crop.x + crop.width),
        source_rect.y0 + source_rect.height * (crop.y + crop.height),
    )


def _raster_stream_for_panel(panel: ComposerPanel) -> bytes:
    with Image.open(panel.file_path) as image:
        rgba = image.convert("RGBA")
        cropped = _crop_image(rgba, panel.crop_rect)
        output = BytesIO()
        cropped.save(output, format="PNG")
        return output.getvalue()


def _draw_text_pdf(page: fitz.Page, text: ComposerText) -> None:
    text_length = fitz.get_text_length(text.text, fontname="helv", fontsize=text.font_size_pt)
    x_pt = mm_to_pt(text.x_mm)
    if text.align == "center":
        x_pt -= text_length / 2.0
    elif text.align == "right":
        x_pt -= text_length
    y_pt = mm_to_pt(text.y_mm)
    text_rect = fitz.Rect(
        x_pt,
        y_pt,
        x_pt + max(text_length + 4.0, text.font_size_pt),
        y_pt + text.font_size_pt * 1.8,
    )
    escaped_text = html.escape(text.text).replace("\n", "<br/>")
    page.insert_htmlbox(
        text_rect,
        (
            "<div "
            f"style=\"font-family: Helvetica; font-size: {text.font_size_pt}pt; "
            "color: rgb(26, 26, 31); margin: 0; padding: 0; "
            f"text-align: {text.align};\">"
            f"{escaped_text}"
            "</div>"
        ),
        overlay=True,
    )


def _clean_layer_fragment(value: str | None, fallback: str) -> str:
    normalized = " ".join((value or "").split())
    if not normalized:
        return fallback
    return normalized[:72]


def _panel_layer_name(project: ComposerProject, panel: ComposerPanel) -> str:
    if panel.kind == "graph":
        label = _panel_label_text(project, panel)
        suffix = f" [{label}]" if label else ""
        return f"Graph/{panel.id}{suffix}"
    prefix = "Structure Asset" if panel.slot_id else "Asset"
    leaf = _clean_layer_fragment(panel.label or Path(panel.file_path).name, panel.id)
    return f"{prefix}/{panel.id} {leaf}"


def _text_layer_name(text: ComposerText) -> str:
    prefix = "Structure Text" if text.slot_id else "Text"
    snippet = _clean_layer_fragment(text.text, text.id)
    return f"{prefix}/{text.id} {snippet}"


def _ensure_ocg(document: fitz.Document, cache: dict[str, int], name: str) -> int:
    existing = cache.get(name)
    if existing is not None:
        return existing
    ocg_xref = int(document.add_ocg(name))
    cache[name] = ocg_xref
    return ocg_xref


def _draw_text_pdf_with_oc(page: fitz.Page, text: ComposerText, oc_xref: int) -> None:
    text_length = fitz.get_text_length(text.text, fontname="helv", fontsize=text.font_size_pt)
    x_pt = mm_to_pt(text.x_mm)
    if text.align == "center":
        x_pt -= text_length / 2.0
    elif text.align == "right":
        x_pt -= text_length
    y_pt = mm_to_pt(text.y_mm)
    text_rect = fitz.Rect(
        x_pt,
        y_pt,
        x_pt + max(text_length + 4.0, text.font_size_pt),
        y_pt + text.font_size_pt * 1.8,
    )
    escaped_text = html.escape(text.text).replace("\n", "<br/>")
    page.insert_htmlbox(
        text_rect,
        (
            "<div "
            f"style=\"font-family: Helvetica; font-size: {text.font_size_pt}pt; "
            "color: rgb(26, 26, 31); margin: 0; padding: 0; "
            f"text-align: {text.align};\">"
            f"{escaped_text}"
            "</div>"
        ),
        oc=oc_xref,
        overlay=True,
    )


def compose_export_pdf(project: ComposerProject, output_path: str | Path) -> Path:
    normalized = normalize_project(project)
    output = Path(output_path).expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)

    document = fitz.open()
    page = document.new_page(width=mm_to_pt(normalized.canvas_width_mm), height=mm_to_pt(normalized.canvas_height_mm))
    ocg_cache: dict[str, int] = {}

    for kind, drawable in _sorted_drawables(normalized):
        if kind == "panel":
            panel = cast(ComposerPanel, drawable)
            if panel.hidden:
                continue
            panel_ocg = _ensure_ocg(document, ocg_cache, _panel_layer_name(normalized, panel))
            target_rect = fitz.Rect(
                mm_to_pt(panel.x_mm),
                mm_to_pt(panel.y_mm),
                mm_to_pt(panel.x_mm + panel.w_mm),
                mm_to_pt(panel.y_mm + panel.h_mm),
            )
            if _is_pdf_path(panel.file_path):
                source_document = fitz.open(panel.file_path)
                try:
                    source_page = source_document.load_page(panel.page_index)
                    page.show_pdf_page(
                        target_rect,
                        source_document,
                        panel.page_index,
                        clip=_pdf_clip_rect(panel, source_page.rect),
                        keep_proportion=False,
                        oc=panel_ocg,
                        overlay=True,
                    )
                finally:
                    source_document.close()
            elif _is_raster_path(panel.file_path):
                page.insert_image(
                    target_rect,
                    stream=_raster_stream_for_panel(panel),
                    keep_proportion=False,
                    oc=panel_ocg,
                    overlay=True,
                )
            else:
                raise ValueError(f"Unsupported panel asset type: {panel.file_path}")

            if normalized.auto_labels and panel.kind == "graph":
                label = _panel_label_text(normalized, panel)
                if label:
                    _draw_text_pdf_with_oc(
                        page,
                        ComposerText(
                            id=f"{panel.id}:label",
                            text=label,
                            x_mm=panel.x_mm + (8.0 * PT_TO_MM),
                            y_mm=panel.y_mm + (3.0 * PT_TO_MM),
                            font_size_pt=9,
                            align="left",
                        ),
                        panel_ocg,
                    )
        else:
            text = cast(ComposerText, drawable)
            if text.hidden:
                continue
            text_ocg = _ensure_ocg(document, ocg_cache, _text_layer_name(text))
            _draw_text_pdf_with_oc(page, text, text_ocg)

    document.save(output)
    document.close()
    return output


def validate_non_overlapping_panels(project: ComposerProject) -> tuple[bool, str | None]:
    normalized = normalize_project(project)
    grid = composer_layout_grid(normalized)

    if normalized.version != COMPOSER_VERSION:
        return False, "Composer 项目仅支持 version: 2。"

    occupied: dict[tuple[int, int], str] = {}
    region_lookup = _region_by_id(normalized)
    for region in normalized.regions:
        if region.kind not in {"graph", "free"}:
            return False, f"未知 region 类型: {region.kind}"
        if region.col < 0 or region.row < 0:
            return False, f"Region {region.id} 越界。"
        if region.col + region.col_span > grid.columns or region.row + region.row_span > grid.rows:
            return False, f"Region {region.id} 超出网格范围。"
        for col in range(region.col, region.col + region.col_span):
            for row in range(region.row, region.row + region.row_span):
                key = (col, row)
                if key in occupied:
                    return False, f"Regions {occupied[key]} and {region.id} overlap."
                occupied[key] = region.id
        if region.kind == "graph" and _graph_panel_for_region(normalized, region.id) is None:
            return False, f"Graph region {region.id} 缺少对应图 panel。"

    for panel in normalized.panels:
        if panel.w_mm <= 0 or panel.h_mm <= 0:
            return False, f"Panel {panel.id} 尺寸无效。"
        if panel.kind == "graph":
            if panel.region_id is None or panel.region_id not in region_lookup:
                return False, f"Graph panel {panel.id} 缺少有效 region。"
            if region_lookup[panel.region_id].kind != "graph":
                return False, f"Graph panel {panel.id} 绑定了非 graph region。"
        elif panel.region_id and panel.region_id not in region_lookup:
            return False, f"Panel {panel.id} 绑定了不存在的 region。"
        if panel.slot_id and panel.region_id:
            slot_region = region_lookup.get(panel.region_id)
            if slot_region is None or region_slot_id(slot_region) != panel.slot_id:
                return False, f"Panel {panel.id} 绑定了无效 slot。"

    for text in normalized.texts:
        if text.region_id and text.region_id not in region_lookup:
            return False, f"Text {text.id} 绑定了不存在的 region。"
        if text.slot_id and text.region_id:
            slot_region = region_lookup.get(text.region_id)
            if slot_region is None or region_slot_id(slot_region) != text.slot_id:
                return False, f"Text {text.id} 绑定了无效 slot。"

    return True, None
