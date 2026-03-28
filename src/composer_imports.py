from __future__ import annotations

from collections.abc import Iterable
from dataclasses import replace
from pathlib import Path

from src.composer_assets import is_pdf_path, panel_aspect_ratio, pdf_page_size_pt
from src.composer_project import (
    composer_layout_grid,
    next_numeric_id,
    normalize_project,
    region_by_id,
    region_rect_mm,
    region_slot_id,
)
from src.composer_types import (
    GRAPH_SIZE_RULES,
    GRAPH_SIZE_TOLERANCE_MM,
    ComposerPanel,
    ComposerProject,
    ComposerRegion,
    pt_to_mm,
)


def fit_asset_panel_size_mm(
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


def match_graph_pdf_span(
    file_path: str | Path,
    page_index: int = 0,
) -> tuple[int, int, str | None]:
    width_pt, height_pt = pdf_page_size_pt(file_path, page_index)
    width_mm = pt_to_mm(width_pt)
    height_mm = pt_to_mm(height_pt)
    for expected_width_mm, expected_height_mm, col_span, row_span, slot_kind in GRAPH_SIZE_RULES:
        width_ok = abs(width_mm - expected_width_mm) <= GRAPH_SIZE_TOLERANCE_MM
        height_ok = abs(height_mm - expected_height_mm) <= GRAPH_SIZE_TOLERANCE_MM
        if width_ok and height_ok:
            return col_span, row_span, slot_kind
    raise ValueError(
        "Graph mode only accepts 60x55, 120x55, or 60x110 mm SciPlot God PDFs. "
        "Use asset mode instead."
    )


def cell_occupancy(
    project: ComposerProject,
    *,
    skip_region_id: str | None = None,
) -> set[tuple[int, int]]:
    occupied: set[tuple[int, int]] = set()
    for region in project.regions:
        if region.id == skip_region_id:
            continue
        for col in range(region.col, region.col + region.col_span):
            for row in range(region.row, region.row + region.row_span):
                occupied.add((col, row))
    return occupied


def find_first_fit(
    project: ComposerProject,
    col_span: int,
    row_span: int,
) -> tuple[int, int]:
    grid = composer_layout_grid(project)
    occupied = cell_occupancy(project)
    for row in range(grid.rows - row_span + 1):
        for col in range(grid.columns - col_span + 1):
            cells = {
                (check_col, check_row)
                for check_col in range(col, col + col_span)
                for check_row in range(row, row + row_span)
            }
            if occupied.isdisjoint(cells):
                return col, row
    raise ValueError("The layout grid does not have enough continuous free cells.")


def next_panel_id(project: ComposerProject, kind: str) -> str:
    prefix = "asset" if kind == "asset" else "panel"
    return next_numeric_id((panel.id for panel in project.panels), prefix)


def next_region_id(project: ComposerProject) -> str:
    return next_numeric_id((region.id for region in project.regions), "region")


def graph_panel_for_region(
    project: ComposerProject,
    region_id: str,
) -> ComposerPanel | None:
    for panel in project.panels:
        if panel.kind == "graph" and panel.region_id == region_id:
            return panel
    return None


def clone_project(project: ComposerProject) -> ComposerProject:
    return ComposerProject(
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


def import_panels_from_paths(
    project: ComposerProject,
    file_paths: list[str | Path],
    *,
    kind: str,
) -> ComposerProject:
    next_project = normalize_project(clone_project(project))
    next_z = len(next_project.panels) + len(next_project.texts)
    for raw_path in file_paths:
        normalized_path = Path(raw_path).expanduser()
        if kind == "graph":
            if not is_pdf_path(normalized_path):
                raise ValueError("Graph mode only supports PDF files.")
            col_span, row_span, slot_kind = match_graph_pdf_span(normalized_path)
            col, row = find_first_fit(next_project, col_span, row_span)
            region = ComposerRegion(
                id=next_region_id(next_project),
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
                    id=next_panel_id(next_project, "graph"),
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
            w_mm, h_mm = fit_asset_panel_size_mm(normalized_path, max_width_mm, max_height_mm, 0)
            x_mm = (next_project.canvas_width_mm - w_mm) / 2.0
            y_mm = (next_project.canvas_height_mm - h_mm) / 2.0
            next_project.panels.append(
                ComposerPanel(
                    id=next_panel_id(next_project, "asset"),
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


def project_with_graph_regions(
    file_paths: list[str | Path],
    placements: list[tuple[int, int]],
) -> ComposerProject:
    project = ComposerProject()
    for raw_path, (col, row) in zip(file_paths, placements, strict=False):
        normalized_path = Path(raw_path).expanduser()
        col_span, row_span, slot_kind = match_graph_pdf_span(normalized_path)
        region = ComposerRegion(
            id=next_region_id(project),
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
                id=next_panel_id(project, "graph"),
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
    return project_with_graph_regions(file_paths[:3], [(0, 0), (1, 0), (2, 0)])


def two_up_editorial_panels_from_paths(file_paths: list[str | Path]) -> ComposerProject:
    project = project_with_graph_regions(file_paths[:2], [(0, 0), (1, 0)])
    project.regions.append(
        ComposerRegion(
            id=next_region_id(project),
            kind="free",
            col=2,
            row=0,
            col_span=1,
            row_span=2,
            label="Editorial",
        )
    )
    return normalize_project(project)


def validate_non_overlapping_panels(
    project: ComposerProject,
) -> tuple[bool, str | None]:
    normalized = normalize_project(project)
    grid = composer_layout_grid(normalized)

    if normalized.version != 2:
        return False, "Composer projects only support version: 2."

    occupied: dict[tuple[int, int], str] = {}
    regions = region_by_id(normalized)
    for region in normalized.regions:
        if region.kind not in {"graph", "free"}:
            return False, f"Unknown region kind: {region.kind}"
        if region.col < 0 or region.row < 0:
            return False, f"Region {region.id} is out of bounds."
        if region.col + region.col_span > grid.columns or region.row + region.row_span > grid.rows:
            return False, f"Region {region.id} exceeds the layout grid."
        for col in range(region.col, region.col + region.col_span):
            for row in range(region.row, region.row + region.row_span):
                key = (col, row)
                if key in occupied:
                    return False, f"Regions {occupied[key]} and {region.id} overlap."
                occupied[key] = region.id
        if region.kind == "graph" and graph_panel_for_region(normalized, region.id) is None:
            return False, f"Graph region {region.id} is missing its matching graph panel."

    for panel in normalized.panels:
        if panel.w_mm <= 0 or panel.h_mm <= 0:
            return False, f"Panel {panel.id} has an invalid size."
        if panel.kind == "graph":
            if panel.region_id is None or panel.region_id not in regions:
                return False, f"Graph panel {panel.id} is missing a valid region."
            if regions[panel.region_id].kind != "graph":
                return False, f"Graph panel {panel.id} is bound to a non-graph region."
        elif panel.region_id and panel.region_id not in regions:
            return False, f"Panel {panel.id} is bound to a region that does not exist."
        if panel.slot_id and panel.region_id:
            slot_region = regions.get(panel.region_id)
            if slot_region is None or region_slot_id(slot_region) != panel.slot_id:
                return False, f"Panel {panel.id} is bound to an invalid slot."

    for text in normalized.texts:
        if text.region_id and text.region_id not in regions:
            return False, f"Text {text.id} is bound to a region that does not exist."
        if text.slot_id and text.region_id:
            slot_region = regions.get(text.region_id)
            if slot_region is None or region_slot_id(slot_region) != text.slot_id:
                return False, f"Text {text.id} is bound to an invalid slot."

    return True, None


__all__ = [
    "clone_project",
    "find_first_fit",
    "fit_asset_panel_size_mm",
    "graph_panel_for_region",
    "import_panels_from_paths",
    "match_graph_pdf_span",
    "next_panel_id",
    "next_region_id",
    "project_with_graph_regions",
    "three_up_panels_from_paths",
    "two_up_editorial_panels_from_paths",
    "validate_non_overlapping_panels",
]
