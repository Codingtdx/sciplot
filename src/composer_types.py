from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any

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
COMPOSER_LAYOUT_FRAME_Y_MM = (
    COMPOSER_CANVAS_HEIGHT_MM - COMPOSER_LAYOUT_FRAME_HEIGHT_MM
) / 2.0
COMPOSER_LAYOUT_FRAME_X_MM = 0.0
COMPOSER_GRID_MM = 0.5
RASTER_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"}
GRAPH_SIZE_TOLERANCE_MM = 1.2
GRAPH_SIZE_RULES: tuple[tuple[float, float, int, int, str | None], ...] = (
    (60.0, 55.0, 1, 1, None),
    (120.0, 55.0, 2, 1, None),
    (180.0, 55.0, 3, 1, None),
    (60.0, 110.0, 1, 2, "structure"),
    (120.0, 110.0, 2, 2, None),
    (180.0, 110.0, 3, 2, None),
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
