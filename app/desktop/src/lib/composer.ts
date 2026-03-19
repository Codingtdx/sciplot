import type {
  ComposerCropRect,
  ComposerLayoutGrid,
  ComposerPanel,
  ComposerProject,
  ComposerRegion,
  ComposerText,
} from "./types";
import { formatLeaf } from "./workbench";

export const DEFAULT_CROP_RECT: ComposerCropRect = {
  x: 0,
  y: 0,
  width: 1,
  height: 1,
};

export const DEFAULT_LAYOUT_GRID: ComposerLayoutGrid = {
  columns: 3,
  rows: 3,
  cell_width_mm: 60,
  cell_height_mm: 55,
  frame_x_mm: 0,
  frame_y_mm: 2.5,
  frame_width_mm: 180,
  frame_height_mm: 165,
};

export const EMPTY_COMPOSER_PROJECT: ComposerProject = {
  version: 2,
  mode: "composer",
  canvas_width_mm: 180,
  canvas_height_mm: 170,
  grid_mm: 0.5,
  layout_grid: { ...DEFAULT_LAYOUT_GRID },
  regions: [],
  panels: [],
  texts: [],
  auto_labels: true,
};

function asObject(payload: unknown): Record<string, unknown> {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("This is not a recognizable Composer project file.");
  }
  return payload as Record<string, unknown>;
}

function readNumber(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function readBoolean(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function readText(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function readOptionalText(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

export function normalizeCropRect(cropRect?: Partial<ComposerCropRect> | null): ComposerCropRect {
  const x = Math.min(Math.max(readNumber(cropRect?.x, 0), 0), 0.999);
  const y = Math.min(Math.max(readNumber(cropRect?.y, 0), 0), 0.999);
  const width = Math.min(Math.max(readNumber(cropRect?.width, 1), 0.001), 1 - x);
  const height = Math.min(Math.max(readNumber(cropRect?.height, 1), 0.001), 1 - y);
  return { x, y, width, height };
}

export function normalizeComposerProject(project: ComposerProject): ComposerProject {
  const panels: ComposerPanel[] = (project.panels ?? []).map((panel, index) => ({
    ...panel,
    kind: panel.kind === "asset" ? "asset" : "graph",
    z_index: readNumber(panel.z_index, index),
    locked: readBoolean(panel.locked, false),
    hidden: readBoolean(panel.hidden, false),
    group_id: readOptionalText(panel.group_id),
    region_id: panel.region_id ?? null,
    slot_id: panel.slot_id ?? null,
    crop_rect: normalizeCropRect(panel.crop_rect),
  }));

  const texts: ComposerText[] = (project.texts ?? []).map((text, index) => ({
    ...text,
    align: text.align === "center" || text.align === "right" ? text.align : "left",
    z_index: readNumber(text.z_index, panels.length + index),
    locked: readBoolean(text.locked, false),
    hidden: readBoolean(text.hidden, false),
    group_id: readOptionalText(text.group_id),
    region_id: text.region_id ?? null,
    slot_id: text.slot_id ?? null,
  }));

  const drawables = [
    ...panels.map((panel) => ({ kind: "panel" as const, id: panel.id, z: panel.z_index })),
    ...texts.map((text) => ({ kind: "text" as const, id: text.id, z: text.z_index })),
  ].sort((a, b) => a.z - b.z || a.kind.localeCompare(b.kind) || a.id.localeCompare(b.id));

  drawables.forEach((item, index) => {
    if (item.kind === "panel") {
      const target = panels.find((panel) => panel.id === item.id);
      if (target) {
        target.z_index = index;
      }
    } else {
      const target = texts.find((text) => text.id === item.id);
      if (target) {
        target.z_index = index;
      }
    }
  });

  return {
    ...EMPTY_COMPOSER_PROJECT,
    ...project,
    version: 2,
    mode: "composer",
    canvas_width_mm: 180,
    canvas_height_mm: 170,
    grid_mm: 0.5,
    layout_grid: { ...DEFAULT_LAYOUT_GRID },
    regions: (project.regions ?? []).map((region) => ({
      id: region.id,
      kind: region.kind === "graph" ? "graph" : "free",
      col: Math.max(0, Math.min(2, Math.round(region.col))),
      row: Math.max(0, Math.min(2, Math.round(region.row))),
      col_span: Math.max(1, Math.min(3, Math.round(region.col_span))),
      row_span: Math.max(1, Math.min(3, Math.round(region.row_span))),
      label: region.label ?? null,
      locked: Boolean(region.locked),
      slot_kind: region.slot_kind === "structure" ? "structure" : null,
    })),
    panels,
    texts,
    auto_labels: project.auto_labels ?? true,
  };
}

export function regionRect(project: ComposerProject, region: ComposerRegion) {
  return {
    x_mm: project.layout_grid.frame_x_mm + region.col * project.layout_grid.cell_width_mm,
    y_mm: project.layout_grid.frame_y_mm + region.row * project.layout_grid.cell_height_mm,
    w_mm: region.col_span * project.layout_grid.cell_width_mm,
    h_mm: region.row_span * project.layout_grid.cell_height_mm,
  };
}

export function regionSlotId(region: ComposerRegion) {
  return region.slot_kind === "structure" ? `${region.id}:structure` : null;
}

export function regionSlotRect(project: ComposerProject, region: ComposerRegion) {
  if (region.slot_kind !== "structure") {
    return null;
  }
  const rect = regionRect(project, region);
  return {
    x_mm: rect.x_mm,
    y_mm: rect.y_mm,
    w_mm: rect.w_mm,
    h_mm: project.layout_grid.cell_height_mm,
  };
}

export function findRegion(project: ComposerProject, regionId: string | null | undefined) {
  return regionId ? project.regions.find((region) => region.id === regionId) ?? null : null;
}

export function orderGraphPanels(project: ComposerProject) {
  return [...project.panels]
    .filter((panel) => panel.kind === "graph")
    .sort((a, b) => {
      if (Math.abs(a.y_mm - b.y_mm) > 0.25) {
        return a.y_mm - b.y_mm;
      }
      if (Math.abs(a.x_mm - b.x_mm) > 0.25) {
        return a.x_mm - b.x_mm;
      }
      return a.id.localeCompare(b.id);
    });
}

export function resolveSelectedPanelLabel(project: ComposerProject, panel: ComposerPanel) {
  if (panel.kind !== "graph") {
    return panel.label ?? "";
  }
  if (!project.auto_labels) {
    return panel.label ?? "";
  }
  const ordered = orderGraphPanels(project);
  const index = ordered.findIndex((item) => item.id === panel.id);
  return index >= 0 ? String.fromCharCode("a".charCodeAt(0) + index) : "";
}

function regionSpanLabel(region: ComposerRegion) {
  const columnEnd = region.col + region.col_span;
  const rowEnd = region.row + region.row_span;
  const columnLabel =
    region.col_span > 1 ? `C${region.col + 1}-${columnEnd}` : `C${region.col + 1}`;
  const rowLabel = region.row_span > 1 ? `R${region.row + 1}-${rowEnd}` : `R${region.row + 1}`;
  return `${columnLabel} / ${rowLabel}`;
}

export function describePanelSlot(panel: ComposerPanel, project: ComposerProject) {
  if (panel.slot_id) {
    return "Structure Slot";
  }
  if (panel.region_id) {
    const region = findRegion(project, panel.region_id);
    if (region) {
      return region.kind === "graph" ? regionSpanLabel(region) : `Free · ${regionSpanLabel(region)}`;
    }
  }
  return panel.kind === "graph" ? "Graph Region" : "Free Asset";
}

export function composerLayerTitle(project: ComposerProject, panel: ComposerPanel) {
  return panel.kind === "graph"
    ? `Figure ${resolveSelectedPanelLabel(project, panel) || panel.id}`
    : panel.label || formatLeaf(panel.file_path);
}

function extractLayoutGrid(payload: unknown): ComposerLayoutGrid {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return { ...DEFAULT_LAYOUT_GRID };
  }
  const grid = payload as Record<string, unknown>;
  return {
    columns: 3,
    rows: 3,
    cell_width_mm: readNumber(grid.cell_width_mm, 60),
    cell_height_mm: readNumber(grid.cell_height_mm, 55),
    frame_x_mm: readNumber(grid.frame_x_mm, 0),
    frame_y_mm: readNumber(grid.frame_y_mm, 2.5),
    frame_width_mm: readNumber(grid.frame_width_mm, 180),
    frame_height_mm: readNumber(grid.frame_height_mm, 165),
  };
}

function extractRegions(payload: unknown): ComposerRegion[] {
  if (!Array.isArray(payload)) {
    return [];
  }
  return payload.map((item, index) => {
    const region = asObject(item);
    return {
      id: readText(region.id, `region-${index + 1}`),
      kind: region.kind === "graph" ? "graph" : "free",
      col: readNumber(region.col, 0),
      row: readNumber(region.row, 0),
      col_span: readNumber(region.col_span, 1),
      row_span: readNumber(region.row_span, 1),
      label: readOptionalText(region.label),
      locked: readBoolean(region.locked, false),
      slot_kind: region.slot_kind === "structure" ? "structure" : null,
    };
  });
}

function extractComposerPanels(payload: unknown): ComposerPanel[] {
  if (!Array.isArray(payload)) {
    return [];
  }
  return payload.map((item, index) => {
    const panel = asObject(item);
    return {
      id: readText(panel.id, `panel-${index + 1}`),
      file_path: readText(panel.file_path),
      page_index: readNumber(panel.page_index, 0),
      x_mm: readNumber(panel.x_mm, 0),
      y_mm: readNumber(panel.y_mm, 0),
      w_mm: readNumber(panel.w_mm, 60),
      h_mm: readNumber(panel.h_mm, 55),
      locked: readBoolean(panel.locked, false),
      hidden: readBoolean(panel.hidden, false),
      label: readOptionalText(panel.label),
      kind: panel.kind === "asset" ? "asset" : "graph",
      z_index: readNumber(panel.z_index, index),
      group_id: readOptionalText(panel.group_id),
      region_id: readOptionalText(panel.region_id),
      slot_id: readOptionalText(panel.slot_id),
      crop_rect: normalizeCropRect(panel.crop_rect as Partial<ComposerCropRect> | undefined),
    };
  });
}

function extractComposerTexts(payload: unknown): ComposerText[] {
  if (!Array.isArray(payload)) {
    return [];
  }
  return payload.map((item, index) => {
    const text = asObject(item);
    const align = text.align === "center" || text.align === "right" ? text.align : "left";
    return {
      id: readText(text.id, `text-${index + 1}`),
      text: readText(text.text),
      x_mm: readNumber(text.x_mm, 0),
      y_mm: readNumber(text.y_mm, 0),
      font_size_pt: readNumber(text.font_size_pt, 8),
      align,
      z_index: readNumber(text.z_index, index),
      locked: readBoolean(text.locked, false),
      hidden: readBoolean(text.hidden, false),
      group_id: readOptionalText(text.group_id),
      region_id: readOptionalText(text.region_id),
      slot_id: readOptionalText(text.slot_id),
    };
  });
}

export function extractComposerProject(payload: unknown): ComposerProject {
  const candidate = asObject(payload);
  if ("project" in candidate && candidate.project != null) {
    if (candidate.mode != null && candidate.mode !== "composer") {
      throw new Error("This is not a recognizable Composer project file.");
    }
    return extractComposerProject(candidate.project);
  }

  if ("mode" in candidate && candidate.mode !== "composer") {
    throw new Error("This is not a recognizable Composer project file.");
  }

  const version = readNumber(candidate.version, 0);
  if (version !== 2) {
    throw new Error("Composer projects only support version: 2. Re-import the assets to create a new project.");
  }

  return normalizeComposerProject({
    version: 2,
    mode: "composer",
    canvas_width_mm: readNumber(candidate.canvas_width_mm, 180),
    canvas_height_mm: readNumber(candidate.canvas_height_mm, 170),
    grid_mm: readNumber(candidate.grid_mm, 0.5),
    layout_grid: extractLayoutGrid(candidate.layout_grid),
    regions: extractRegions(candidate.regions),
    panels: extractComposerPanels(candidate.panels),
    texts: extractComposerTexts(candidate.texts),
    auto_labels: readBoolean(candidate.auto_labels, true),
  });
}

export function orderDrawables(project: ComposerProject) {
  return [
    ...project.panels.map((panel) => ({ type: "panel" as const, id: panel.id, z_index: panel.z_index })),
    ...project.texts.map((text) => ({ type: "text" as const, id: text.id, z_index: text.z_index })),
  ].sort((a, b) => a.z_index - b.z_index || a.type.localeCompare(b.type) || a.id.localeCompare(b.id));
}

export function nextRegionId(project: ComposerProject) {
  const ids = new Set(project.regions.map((region) => region.id));
  let index = 1;
  while (ids.has(`region-${index}`)) {
    index += 1;
  }
  return `region-${index}`;
}

export function nextTextId(project: ComposerProject) {
  const ids = new Set(project.texts.map((text) => text.id));
  let index = 1;
  while (ids.has(`text-${index}`)) {
    index += 1;
  }
  return `text-${index}`;
}

export function nextZIndex(project: ComposerProject) {
  return project.panels.length + project.texts.length;
}

export function cellsForRegion(region: ComposerRegion) {
  const cells: Array<{ col: number; row: number }> = [];
  for (let col = region.col; col < region.col + region.col_span; col += 1) {
    for (let row = region.row; row < region.row + region.row_span; row += 1) {
      cells.push({ col, row });
    }
  }
  return cells;
}

export function regionAtCell(project: ComposerProject, col: number, row: number) {
  return (
    project.regions.find(
      (region) =>
        col >= region.col &&
        col < region.col + region.col_span &&
        row >= region.row &&
        row < region.row + region.row_span,
    ) ?? null
  );
}

export function regionBoundsContains(region: ComposerRegion, col: number, row: number) {
  return (
    col >= region.col &&
    col < region.col + region.col_span &&
    row >= region.row &&
    row < region.row + region.row_span
  );
}

export function cellRect(project: ComposerProject, col: number, row: number) {
  return {
    x_mm: project.layout_grid.frame_x_mm + col * project.layout_grid.cell_width_mm,
    y_mm: project.layout_grid.frame_y_mm + row * project.layout_grid.cell_height_mm,
    w_mm: project.layout_grid.cell_width_mm,
    h_mm: project.layout_grid.cell_height_mm,
  };
}

export function mergeableCells(project: ComposerProject, selectedCells: Array<{ col: number; row: number }>) {
  if (selectedCells.length < 2) {
    return false;
  }
  const unique = Array.from(
    new Map(selectedCells.map((cell) => [`${cell.col}:${cell.row}`, cell])).values(),
  );
  if (unique.some((cell) => regionAtCell(project, cell.col, cell.row))) {
    return false;
  }
  const cols = unique.map((cell) => cell.col);
  const rows = unique.map((cell) => cell.row);
  const minCol = Math.min(...cols);
  const maxCol = Math.max(...cols);
  const minRow = Math.min(...rows);
  const maxRow = Math.max(...rows);
  const area = (maxCol - minCol + 1) * (maxRow - minRow + 1);
  return area === unique.length;
}

export function mergeCellsIntoFreeRegion(
  project: ComposerProject,
  selectedCells: Array<{ col: number; row: number }>,
) {
  if (!mergeableCells(project, selectedCells)) {
    throw new Error("Only continuous, unoccupied empty cells can be merged.");
  }
  const cols = selectedCells.map((cell) => cell.col);
  const rows = selectedCells.map((cell) => cell.row);
  const region: ComposerRegion = {
    id: nextRegionId(project),
    kind: "free",
    col: Math.min(...cols),
    row: Math.min(...rows),
    col_span: Math.max(...cols) - Math.min(...cols) + 1,
    row_span: Math.max(...rows) - Math.min(...rows) + 1,
    label: null,
    locked: false,
    slot_kind: null,
  };
  return normalizeComposerProject({
    ...project,
    regions: [...project.regions, region],
  });
}

export function removeRegion(project: ComposerProject, regionId: string) {
  return normalizeComposerProject({
    ...project,
    regions: project.regions.filter((region) => region.id !== regionId),
    panels: project.panels.map((panel) =>
      panel.region_id === regionId || panel.slot_id?.startsWith(`${regionId}:`)
        ? { ...panel, region_id: null, slot_id: null }
        : panel,
    ),
    texts: project.texts.map((text) =>
      text.region_id === regionId || text.slot_id?.startsWith(`${regionId}:`)
        ? { ...text, region_id: null, slot_id: null }
        : text,
    ),
  });
}

export function moveRegion(project: ComposerProject, regionId: string, col: number, row: number) {
  const target = findRegion(project, regionId);
  if (!target || target.locked) {
    return project;
  }
  const nextRegion: ComposerRegion = { ...target, col, row };
  const collides = project.regions.some((region) => {
    if (region.id === regionId) {
      return false;
    }
    return cellsForRegion(region).some((cell) => regionBoundsContains(nextRegion, cell.col, cell.row));
  });
  if (collides) {
    return project;
  }
  const currentRect = regionRect(project, target);
  const nextRect = regionRect(project, nextRegion);
  const dx = nextRect.x_mm - currentRect.x_mm;
  const dy = nextRect.y_mm - currentRect.y_mm;
  return normalizeComposerProject({
    ...project,
    regions: project.regions.map((region) => (region.id === regionId ? nextRegion : region)),
    panels: project.panels.map((panel) => {
      if (panel.kind === "graph" && panel.region_id === regionId) {
        return {
          ...panel,
          x_mm: nextRect.x_mm,
          y_mm: nextRect.y_mm,
          w_mm: nextRect.w_mm,
          h_mm: nextRect.h_mm,
        };
      }
      if (panel.region_id === regionId || panel.slot_id?.startsWith(`${regionId}:`)) {
        return { ...panel, x_mm: panel.x_mm + dx, y_mm: panel.y_mm + dy };
      }
      return panel;
    }),
    texts: project.texts.map((text) =>
      text.region_id === regionId || text.slot_id?.startsWith(`${regionId}:`)
        ? { ...text, x_mm: text.x_mm + dx, y_mm: text.y_mm + dy }
        : text,
    ),
  });
}

export function reorderDrawable(
  project: ComposerProject,
  id: string,
  type: "panel" | "text",
  action: "forward" | "backward" | "front" | "back",
) {
  const drawables = orderDrawables(project);
  const index = drawables.findIndex((item) => item.id === id && item.type === type);
  if (index < 0) {
    return project;
  }

  const next = [...drawables];
  const [item] = next.splice(index, 1);
  let nextIndex = index;
  if (action === "forward") {
    nextIndex = Math.min(next.length, index + 1);
  } else if (action === "backward") {
    nextIndex = Math.max(0, index - 1);
  } else if (action === "front") {
    nextIndex = next.length;
  } else if (action === "back") {
    nextIndex = 0;
  }
  next.splice(nextIndex, 0, item);

  return normalizeComposerProject({
    ...project,
    panels: project.panels.map((panel) => {
      const drawable = next.find((entry) => entry.type === "panel" && entry.id === panel.id);
      return drawable ? { ...panel, z_index: next.indexOf(drawable) } : panel;
    }),
    texts: project.texts.map((text) => {
      const drawable = next.find((entry) => entry.type === "text" && entry.id === text.id);
      return drawable ? { ...text, z_index: next.indexOf(drawable) } : text;
    }),
  });
}

type DrawableSelectionItem =
  | { type: "panel"; item: ComposerPanel }
  | { type: "text"; item: ComposerText };

type DrawableRect = {
  x_mm: number;
  y_mm: number;
  w_mm: number;
  h_mm: number;
};

function rectsIntersect(a: DrawableRect, b: DrawableRect) {
  return (
    a.x_mm < b.x_mm + b.w_mm &&
    a.x_mm + a.w_mm > b.x_mm &&
    a.y_mm < b.y_mm + b.h_mm &&
    a.y_mm + a.h_mm > b.y_mm
  );
}

function clampDrawableRect(rect: DrawableRect, project: ComposerProject): DrawableRect {
  return {
    ...rect,
    x_mm: Math.max(0, Math.min(project.canvas_width_mm - rect.w_mm, rect.x_mm)),
    y_mm: Math.max(0, Math.min(project.canvas_height_mm - rect.h_mm, rect.y_mm)),
  };
}

export function textRect(text: ComposerText): DrawableRect {
  const w_mm = Math.max(10, text.text.length * text.font_size_pt * 0.18);
  const h_mm = Math.max(6, text.font_size_pt * 0.45);
  const x_mm =
    text.align === "center"
      ? text.x_mm - w_mm / 2
      : text.align === "right"
        ? text.x_mm - w_mm
        : text.x_mm;
  return { x_mm, y_mm: text.y_mm, w_mm, h_mm };
}

function drawableSelection(project: ComposerProject, ids: string[]): DrawableSelectionItem[] {
  return ids.reduce<DrawableSelectionItem[]>((selection, id) => {
    const panel = project.panels.find((item) => item.id === id);
    if (panel) {
      selection.push({ type: "panel", item: panel });
      return selection;
    }
    const text = project.texts.find((item) => item.id === id);
    if (text) {
      selection.push({ type: "text", item: text });
    }
    return selection;
  }, []);
}

function drawableHidden(item: DrawableSelectionItem) {
  return Boolean(item.item.hidden);
}

function drawableGroupId(item: DrawableSelectionItem) {
  return item.item.group_id ?? null;
}

function isFreeTransformDrawable(item: DrawableSelectionItem) {
  return item.type === "text" || item.item.kind === "asset";
}

function isGraphPanelMovementLocked(project: ComposerProject, panel: ComposerPanel) {
  if (panel.kind !== "graph") {
    return Boolean(panel.locked);
  }
  return Boolean(panel.locked || findRegion(project, panel.region_id)?.locked);
}

function drawablePositionLocked(project: ComposerProject, item: DrawableSelectionItem) {
  if (item.type === "panel") {
    return isGraphPanelMovementLocked(project, item.item);
  }
  return Boolean(item.item.locked);
}

function drawableRect(item: DrawableSelectionItem): DrawableRect {
  if (item.type === "panel") {
    return {
      x_mm: item.item.x_mm,
      y_mm: item.item.y_mm,
      w_mm: item.item.w_mm,
      h_mm: item.item.h_mm,
    };
  }
  return textRect(item.item);
}

function applyRectToDrawable(
  project: ComposerProject,
  selection: DrawableSelectionItem,
  rect: DrawableRect,
): ComposerProject {
  if (drawablePositionLocked(project, selection)) {
    return project;
  }
  const nextRect = clampDrawableRect(rect, project);
  if (selection.type === "panel") {
    return normalizeComposerProject({
      ...project,
      panels: project.panels.map((panel) =>
        panel.id === selection.item.id
          ? {
              ...panel,
              x_mm: Math.round(nextRect.x_mm / 0.5) * 0.5,
              y_mm: Math.round(nextRect.y_mm / 0.5) * 0.5,
              w_mm: Math.round(nextRect.w_mm / 0.5) * 0.5,
              h_mm: Math.round(nextRect.h_mm / 0.5) * 0.5,
            }
          : panel,
      ),
    });
  }

  const x_mm =
    selection.item.align === "center"
      ? nextRect.x_mm + nextRect.w_mm / 2
      : selection.item.align === "right"
        ? nextRect.x_mm + nextRect.w_mm
        : nextRect.x_mm;
  return normalizeComposerProject({
    ...project,
    texts: project.texts.map((text) =>
      text.id === selection.item.id
        ? {
            ...text,
            x_mm: Math.round(x_mm / 0.5) * 0.5,
            y_mm: Math.round(nextRect.y_mm / 0.5) * 0.5,
          }
        : text,
    ),
  });
}

function selectionBounds(items: DrawableSelectionItem[]) {
  const rects = items.map(drawableRect);
  return {
    left: Math.min(...rects.map((rect) => rect.x_mm)),
    top: Math.min(...rects.map((rect) => rect.y_mm)),
    right: Math.max(...rects.map((rect) => rect.x_mm + rect.w_mm)),
    bottom: Math.max(...rects.map((rect) => rect.y_mm + rect.h_mm)),
  };
}

export function nextGroupId(project: ComposerProject) {
  const ids = new Set(
    [
      ...project.panels.map((panel) => panel.group_id),
      ...project.texts.map((text) => text.group_id),
    ].filter((value): value is string => Boolean(value)),
  );
  let index = 1;
  while (ids.has(`group-${index}`)) {
    index += 1;
  }
  return `group-${index}`;
}

export function groupMemberIds(project: ComposerProject, groupId: string) {
  return orderDrawables(project)
    .filter((entry) => {
      const item = drawableSelection(project, [entry.id])[0];
      return item ? drawableGroupId(item) === groupId : false;
    })
    .map((entry) => entry.id);
}

export function expandSelectionWithGroups(project: ComposerProject, ids: string[]) {
  const expanded = new Set(ids);
  drawableSelection(project, ids).forEach((item) => {
    const groupId = drawableGroupId(item);
    if (!groupId) {
      return;
    }
    groupMemberIds(project, groupId).forEach((memberId) => expanded.add(memberId));
  });
  return orderDrawables(project)
    .map((entry) => entry.id)
    .filter((id) => expanded.has(id));
}

export function groupDrawables(project: ComposerProject, ids: string[]) {
  const items = drawableSelection(project, ids).filter(isFreeTransformDrawable);
  if (items.length < 2) {
    return project;
  }
  const groupId = nextGroupId(project);
  const targetIds = new Set(items.map((item) => item.item.id));
  return normalizeComposerProject({
    ...project,
    panels: project.panels.map((panel) =>
      targetIds.has(panel.id) ? { ...panel, group_id: groupId } : panel,
    ),
    texts: project.texts.map((text) =>
      targetIds.has(text.id) ? { ...text, group_id: groupId } : text,
    ),
  });
}

export function ungroupDrawables(project: ComposerProject, ids: string[]) {
  const items = drawableSelection(project, ids).filter(isFreeTransformDrawable);
  if (items.length === 0) {
    return project;
  }
  const targetIds = new Set(items.map((item) => item.item.id));
  const groupIds = new Set(
    items
      .map((item) => drawableGroupId(item))
      .filter((value): value is string => Boolean(value)),
  );
  const shouldClear = (id: string, groupId?: string | null) =>
    targetIds.has(id) || Boolean(groupId && groupIds.has(groupId));
  return normalizeComposerProject({
    ...project,
    panels: project.panels.map((panel) =>
      shouldClear(panel.id, panel.group_id) ? { ...panel, group_id: null } : panel,
    ),
    texts: project.texts.map((text) =>
      shouldClear(text.id, text.group_id) ? { ...text, group_id: null } : text,
    ),
  });
}

export function moveDrawablesByDelta(
  project: ComposerProject,
  ids: string[],
  dx_mm: number,
  dy_mm: number,
) {
  const items = drawableSelection(project, ids).filter(
    (item) => isFreeTransformDrawable(item) && !drawablePositionLocked(project, item),
  );
  if (items.length === 0) {
    return project;
  }
  return items.reduce((nextProject, item) => {
    const rect = drawableRect(item);
    return applyRectToDrawable(nextProject, item, {
      ...rect,
      x_mm: rect.x_mm + dx_mm,
      y_mm: rect.y_mm + dy_mm,
    });
  }, project);
}

export function editableSelectionIds(project: ComposerProject, ids: string[]) {
  return drawableSelection(project, ids)
    .filter(isFreeTransformDrawable)
    .map((entry) => entry.item.id);
}

export function drawableIdsInRect(project: ComposerProject, rect: DrawableRect) {
  return orderDrawables(project)
    .filter((entry) => {
      const item = drawableSelection(project, [entry.id])[0];
      return item ? !drawableHidden(item) && rectsIntersect(drawableRect(item), rect) : false;
    })
    .map((entry) => entry.id);
}

export function selectedRegionIdsForObjects(project: ComposerProject, ids: string[]) {
  return Array.from(
    new Set(
      drawableSelection(project, ids)
        .map((entry) => entry.item.region_id)
        .filter((value): value is string => Boolean(value)),
    ),
  );
}

export function alignDrawables(
  project: ComposerProject,
  ids: string[],
  mode: "left" | "center" | "right" | "top" | "middle" | "bottom",
) {
  const items = drawableSelection(project, ids).filter(isFreeTransformDrawable);
  if (items.length < 2) {
    return project;
  }
  const bounds = selectionBounds(items);
  return items.reduce((nextProject, item) => {
    const rect = drawableRect(item);
    const nextRect =
      mode === "left"
        ? { ...rect, x_mm: bounds.left }
        : mode === "center"
          ? { ...rect, x_mm: bounds.left + (bounds.right - bounds.left) / 2 - rect.w_mm / 2 }
          : mode === "right"
            ? { ...rect, x_mm: bounds.right - rect.w_mm }
            : mode === "top"
              ? { ...rect, y_mm: bounds.top }
              : mode === "middle"
                ? { ...rect, y_mm: bounds.top + (bounds.bottom - bounds.top) / 2 - rect.h_mm / 2 }
                : { ...rect, y_mm: bounds.bottom - rect.h_mm };
    return applyRectToDrawable(nextProject, item, nextRect);
  }, project);
}

export function distributeDrawables(
  project: ComposerProject,
  ids: string[],
  axis: "horizontal" | "vertical",
) {
  const items = drawableSelection(project, ids).filter(isFreeTransformDrawable);
  if (items.length < 3) {
    return project;
  }

  const sorted = [...items].sort((a, b) => {
    const rectA = drawableRect(a);
    const rectB = drawableRect(b);
    return axis === "horizontal" ? rectA.x_mm - rectB.x_mm : rectA.y_mm - rectB.y_mm;
  });
  const rects = sorted.map(drawableRect);
  const start = axis === "horizontal" ? rects[0].x_mm : rects[0].y_mm;
  const end =
    axis === "horizontal"
      ? rects[rects.length - 1].x_mm + rects[rects.length - 1].w_mm
      : rects[rects.length - 1].y_mm + rects[rects.length - 1].h_mm;
  const occupied = rects.reduce(
    (sum, rect) => sum + (axis === "horizontal" ? rect.w_mm : rect.h_mm),
    0,
  );
  const gap = (end - start - occupied) / (sorted.length - 1);
  let cursor = start;

  return sorted.reduce((nextProject, item, index) => {
    const rect = rects[index];
    const nextRect =
      axis === "horizontal"
        ? { ...rect, x_mm: cursor }
        : { ...rect, y_mm: cursor };
    cursor += (axis === "horizontal" ? rect.w_mm : rect.h_mm) + gap;
    return applyRectToDrawable(nextProject, item, nextRect);
  }, project);
}

export function nudgeDrawables(project: ComposerProject, ids: string[], dx_mm: number, dy_mm: number) {
  const items = drawableSelection(project, ids).filter(isFreeTransformDrawable);
  if (items.length === 0) {
    return project;
  }
  return items.reduce((nextProject, item) => {
    const rect = drawableRect(item);
    return applyRectToDrawable(nextProject, item, {
      ...rect,
      x_mm: rect.x_mm + dx_mm,
      y_mm: rect.y_mm + dy_mm,
    });
  }, project);
}

export function placeDrawableInRect(
  project: ComposerProject,
  id: string,
  rect: DrawableRect,
  mode: "top" | "middle" | "bottom" | "center" | "left" | "hcenter" | "right",
) {
  const item = drawableSelection(project, [id])[0];
  if (!item || !isFreeTransformDrawable(item)) {
    return project;
  }

  const currentRect = drawableRect(item);
  const maxX = rect.x_mm + Math.max(0, rect.w_mm - currentRect.w_mm);
  const clampedX = Math.min(maxX, Math.max(rect.x_mm, currentRect.x_mm));
  const maxY = rect.y_mm + Math.max(0, rect.h_mm - currentRect.h_mm);
  const clampedY = Math.min(maxY, Math.max(rect.y_mm, currentRect.y_mm));
  const nextRect =
    mode === "top"
      ? {
          ...currentRect,
          x_mm: clampedX,
          y_mm: rect.y_mm,
        }
      : mode === "middle"
        ? {
            ...currentRect,
            x_mm: clampedX,
            y_mm: rect.y_mm + (rect.h_mm - currentRect.h_mm) / 2,
          }
        : mode === "bottom"
          ? {
              ...currentRect,
              x_mm: clampedX,
              y_mm: rect.y_mm + rect.h_mm - currentRect.h_mm,
            }
          : {
              ...currentRect,
              x_mm: rect.x_mm + (rect.w_mm - currentRect.w_mm) / 2,
              y_mm: rect.y_mm + (rect.h_mm - currentRect.h_mm) / 2,
            };
  if (mode === "left") {
    return applyRectToDrawable(project, item, {
      ...currentRect,
      x_mm: rect.x_mm,
      y_mm: clampedY,
    });
  }
  if (mode === "hcenter") {
    return applyRectToDrawable(project, item, {
      ...currentRect,
      x_mm: rect.x_mm + (rect.w_mm - currentRect.w_mm) / 2,
      y_mm: clampedY,
    });
  }
  if (mode === "right") {
    return applyRectToDrawable(project, item, {
      ...currentRect,
      x_mm: rect.x_mm + rect.w_mm - currentRect.w_mm,
      y_mm: clampedY,
    });
  }
  return applyRectToDrawable(project, item, nextRect);
}

export function moveGraphSelectionByCells(
  project: ComposerProject,
  ids: string[],
  dcol: number,
  drow: number,
) {
  const regions = Array.from(
    new Map(
      ids
        .map((id) => project.panels.find((item) => item.id === id && item.kind === "graph"))
        .filter((panel): panel is ComposerPanel => Boolean(panel?.region_id))
        .filter((panel) => !isGraphPanelMovementLocked(project, panel))
        .map((panel) => {
          const region = findRegion(project, panel.region_id);
          return region ? [region.id, region] : null;
        })
        .filter((entry): entry is [string, ComposerRegion] => entry != null),
    ).values(),
  );

  if (regions.length === 0) {
    return project;
  }

  const selectedRegionIds = new Set(regions.map((region) => region.id));
  const occupiedByOthers = new Set(
    project.regions
      .filter((region) => !selectedRegionIds.has(region.id))
      .flatMap((region) => cellsForRegion(region).map((cell) => `${cell.col}:${cell.row}`)),
  );
  const nextRegions = new Map<string, ComposerRegion>();
  const regionDeltas = new Map<
    string,
    { dx_mm: number; dy_mm: number; rect: ReturnType<typeof regionRect> }
  >();

  for (const region of regions) {
    const nextRegion = {
      ...region,
      col: region.col + dcol,
      row: region.row + drow,
    };
    if (
      nextRegion.col < 0 ||
      nextRegion.row < 0 ||
      nextRegion.col + nextRegion.col_span > project.layout_grid.columns ||
      nextRegion.row + nextRegion.row_span > project.layout_grid.rows
    ) {
      return project;
    }
    if (
      cellsForRegion(nextRegion).some((cell) =>
        occupiedByOthers.has(`${cell.col}:${cell.row}`),
      )
    ) {
      return project;
    }
    const currentRect = regionRect(project, region);
    const rect = regionRect(project, nextRegion);
    nextRegions.set(region.id, nextRegion);
    regionDeltas.set(region.id, {
      dx_mm: rect.x_mm - currentRect.x_mm,
      dy_mm: rect.y_mm - currentRect.y_mm,
      rect,
    });
  }

  const linkedRegionId = (value: { region_id?: string | null; slot_id?: string | null }) => {
    for (const regionId of selectedRegionIds) {
      if (value.region_id === regionId || value.slot_id?.startsWith(`${regionId}:`)) {
        return regionId;
      }
    }
    return null;
  };

  return normalizeComposerProject({
    ...project,
    regions: project.regions.map((region) => nextRegions.get(region.id) ?? region),
    panels: project.panels.map((panel) => {
      const regionId = linkedRegionId(panel);
      if (!regionId) {
        return panel;
      }
      if (panel.kind === "graph" && panel.region_id === regionId) {
        const nextRect = regionDeltas.get(regionId)?.rect;
        return nextRect
          ? {
              ...panel,
              x_mm: nextRect.x_mm,
              y_mm: nextRect.y_mm,
              w_mm: nextRect.w_mm,
              h_mm: nextRect.h_mm,
            }
          : panel;
      }
      const delta = regionDeltas.get(regionId);
      return delta
        ? {
            ...panel,
            x_mm: panel.x_mm + delta.dx_mm,
            y_mm: panel.y_mm + delta.dy_mm,
          }
        : panel;
    }),
    texts: project.texts.map((text) => {
      const regionId = linkedRegionId(text);
      const delta = regionId ? regionDeltas.get(regionId) : null;
      return delta
        ? {
            ...text,
            x_mm: text.x_mm + delta.dx_mm,
            y_mm: text.y_mm + delta.dy_mm,
          }
        : text;
    }),
  });
}

export type ComposerClipboard = {
  regions: ComposerRegion[];
  panels: ComposerPanel[];
  texts: ComposerText[];
};

export type PasteComposerResult = {
  project: ComposerProject;
  selectedId: string | null;
  selectedObjectIds: string[];
};

type PasteComposerOptions = {
  freeOffsetMm?: number;
};

function cloneProject(project: ComposerProject): ComposerProject {
  return normalizeComposerProject({
    ...project,
    layout_grid: { ...project.layout_grid },
    regions: project.regions.map((region) => ({ ...region })),
    panels: project.panels.map((panel) => ({
      ...panel,
      crop_rect: { ...panel.crop_rect },
    })),
    texts: project.texts.map((text) => ({ ...text })),
  });
}

function nextPanelId(project: ComposerProject, kind: ComposerPanel["kind"]) {
  const ids = new Set(project.panels.map((panel) => panel.id));
  const prefix = kind === "asset" ? "asset" : "panel";
  let index = 1;
  while (ids.has(`${prefix}-${index}`)) {
    index += 1;
  }
  return `${prefix}-${index}`;
}

function regionCells(region: ComposerRegion) {
  return cellsForRegion(region);
}

function canPlaceRegions(
  project: ComposerProject,
  regions: ComposerRegion[],
  dcol: number,
  drow: number,
) {
  const occupied = new Set(
    project.regions.flatMap((region) =>
      regionCells(region).map((cell) => `${cell.col}:${cell.row}`),
    ),
  );
  return regions.every((region) => {
    const nextCol = region.col + dcol;
    const nextRow = region.row + drow;
    if (
      nextCol < 0 ||
      nextRow < 0 ||
      nextCol + region.col_span > project.layout_grid.columns ||
      nextRow + region.row_span > project.layout_grid.rows
    ) {
      return false;
    }
    return regionCells(region).every((cell) => {
      const nextKey = `${cell.col + dcol}:${cell.row + drow}`;
      return !occupied.has(nextKey);
    });
  });
}

function regionPasteOffset(project: ComposerProject, regions: ComposerRegion[]) {
  const offsets = Array.from({ length: 5 }, (_, index) => index - 2)
    .flatMap((drow) => Array.from({ length: 5 }, (_, index) => index - 2).map((dcol) => ({ dcol, drow })))
    .filter(({ dcol, drow }) => dcol !== 0 || drow !== 0)
    .sort((a, b) => {
      const distanceA = Math.abs(a.dcol) + Math.abs(a.drow);
      const distanceB = Math.abs(b.dcol) + Math.abs(b.drow);
      if (distanceA !== distanceB) {
        return distanceA - distanceB;
      }
      const aScore = (a.dcol >= 0 ? 0 : 1) + (a.drow >= 0 ? 0 : 1);
      const bScore = (b.dcol >= 0 ? 0 : 1) + (b.drow >= 0 ? 0 : 1);
      if (aScore !== bScore) {
        return aScore - bScore;
      }
      if (a.drow !== b.drow) {
        return a.drow - b.drow;
      }
      return a.dcol - b.dcol;
    });

  return offsets.find(({ dcol, drow }) => canPlaceRegions(project, regions, dcol, drow)) ?? null;
}

function offsetDrawableRect(
  project: ComposerProject,
  rect: DrawableRect,
  dx_mm: number,
  dy_mm: number,
) {
  return clampDrawableRect(
    {
      ...rect,
      x_mm: rect.x_mm + dx_mm,
      y_mm: rect.y_mm + dy_mm,
    },
    project,
  );
}

export function buildComposerClipboard(
  project: ComposerProject,
  selectedRegionId: string | null,
  selectedObjectIds: string[],
): ComposerClipboard | null {
  const selectedIds = new Set(selectedObjectIds);
  const selectedRegion =
    selectedObjectIds.length === 0
      ? project.regions.find((region) => region.id === selectedRegionId) ?? null
      : null;
  const selectedRegionIds = new Set<string>();

  if (selectedRegion) {
    selectedRegionIds.add(selectedRegion.id);
  }

  project.panels.forEach((panel) => {
    if (selectedIds.has(panel.id) && panel.kind === "graph" && panel.region_id) {
      selectedRegionIds.add(panel.region_id);
    }
  });

  const panels = project.panels
    .filter(
      (panel) =>
        selectedIds.has(panel.id) ||
        (selectedRegion != null &&
          (panel.region_id === selectedRegion.id ||
            panel.slot_id?.startsWith(`${selectedRegion.id}:`))),
    )
    .map((panel) => ({
      ...panel,
      crop_rect: { ...panel.crop_rect },
    }));

  const texts = project.texts
    .filter(
      (text) =>
        selectedIds.has(text.id) ||
        (selectedRegion != null &&
          (text.region_id === selectedRegion.id ||
            text.slot_id?.startsWith(`${selectedRegion.id}:`))),
    )
    .map((text) => ({ ...text }));

  const regions = project.regions
    .filter((region) => selectedRegionIds.has(region.id))
    .map((region) => ({ ...region }));

  if (regions.length === 0 && panels.length === 0 && texts.length === 0) {
    return null;
  }

  return { regions, panels, texts };
}

export function pasteComposerClipboard(
  project: ComposerProject,
  clipboard: ComposerClipboard,
  options: PasteComposerOptions = {},
): PasteComposerResult {
  if (
    clipboard.regions.length === 0 &&
    clipboard.panels.length === 0 &&
    clipboard.texts.length === 0
  ) {
    return {
      project,
      selectedId: null,
      selectedObjectIds: [],
    };
  }

  const nextProject = cloneProject(project);
  const regionOffset = clipboard.regions.length > 0 ? regionPasteOffset(nextProject, clipboard.regions) : null;
  if (clipboard.regions.length > 0 && !regionOffset) {
    throw new Error("The current canvas does not have enough continuous free cells to paste this region.");
  }

  const regionIdMap = new Map<string, string>();
  const groupCounts = new Map<string, number>();
  [...clipboard.panels, ...clipboard.texts].forEach((item) => {
    if (!item.group_id) {
      return;
    }
    groupCounts.set(item.group_id, (groupCounts.get(item.group_id) ?? 0) + 1);
  });
  const groupIdMap = new Map<string, string>();
  groupCounts.forEach((count, groupId) => {
    if (count > 1) {
      groupIdMap.set(groupId, nextGroupId(nextProject));
    }
  });
  const regionDeltaMm = regionOffset
    ? {
        dx_mm: regionOffset.dcol * project.layout_grid.cell_width_mm,
        dy_mm: regionOffset.drow * project.layout_grid.cell_height_mm,
      }
    : { dx_mm: 0, dy_mm: 0 };
  const freeOffsetMm = options.freeOffsetMm ?? 4;
  const newSelectedObjectIds: string[] = [];
  let selectedId: string | null = null;

  clipboard.regions.forEach((region) => {
    const newRegionId = nextRegionId(nextProject);
    regionIdMap.set(region.id, newRegionId);
    nextProject.regions.push({
      ...region,
      id: newRegionId,
      col: region.col + (regionOffset?.dcol ?? 0),
      row: region.row + (regionOffset?.drow ?? 0),
    });
    selectedId = newRegionId;
  });

  let nextZ = nextZIndex(nextProject);
  clipboard.panels.forEach((panel) => {
    const clonedPanelId = nextPanelId(nextProject, panel.kind);
    const nextPanelRegionId = panel.region_id ? regionIdMap.get(panel.region_id) ?? panel.region_id : null;
    const nextPanel = {
      ...panel,
      id: clonedPanelId,
      z_index: nextZ,
      crop_rect: { ...panel.crop_rect },
      group_id: panel.group_id ? groupIdMap.get(panel.group_id) ?? null : null,
      region_id: nextPanelRegionId,
      slot_id: panel.slot_id,
    } satisfies ComposerPanel;

    if (panel.kind === "graph" && nextPanel.region_id) {
      const region = findRegion(nextProject, nextPanel.region_id);
      if (!region) {
        throw new Error("Could not find the target region while pasting the graph.");
      }
      Object.assign(nextPanel, regionRect(nextProject, region));
      nextPanel.slot_id = regionSlotId(region);
    } else if (panel.region_id && regionIdMap.has(panel.region_id)) {
      Object.assign(
        nextPanel,
        offsetDrawableRect(
          nextProject,
          {
            x_mm: panel.x_mm,
            y_mm: panel.y_mm,
            w_mm: panel.w_mm,
            h_mm: panel.h_mm,
          },
          regionDeltaMm.dx_mm,
          regionDeltaMm.dy_mm,
        ),
      );
      const targetRegion = findRegion(nextProject, nextPanel.region_id);
      nextPanel.slot_id =
        panel.slot_id && targetRegion ? regionSlotId(targetRegion) : null;
    } else {
      Object.assign(
        nextPanel,
        offsetDrawableRect(
          nextProject,
          {
            x_mm: panel.x_mm,
            y_mm: panel.y_mm,
            w_mm: panel.w_mm,
            h_mm: panel.h_mm,
          },
          freeOffsetMm,
          freeOffsetMm,
        ),
      );
    }

    nextProject.panels.push(nextPanel);
    newSelectedObjectIds.push(clonedPanelId);
    nextZ += 1;
  });

  clipboard.texts.forEach((text) => {
    const clonedTextId = nextTextId(nextProject);
    const nextTextRegionId = text.region_id ? regionIdMap.get(text.region_id) ?? text.region_id : null;
    let nextText = {
      ...text,
      id: clonedTextId,
      z_index: nextZ,
      group_id: text.group_id ? groupIdMap.get(text.group_id) ?? null : null,
      region_id: nextTextRegionId,
      slot_id: text.slot_id,
    } satisfies ComposerText;

    if (text.region_id && regionIdMap.has(text.region_id)) {
      const nextRect = offsetDrawableRect(
        nextProject,
        textRect(text),
        regionDeltaMm.dx_mm,
        regionDeltaMm.dy_mm,
      );
      nextText = {
        ...nextText,
        x_mm:
          text.align === "center"
            ? nextRect.x_mm + nextRect.w_mm / 2
            : text.align === "right"
              ? nextRect.x_mm + nextRect.w_mm
              : nextRect.x_mm,
        y_mm: nextRect.y_mm,
      };
      const targetRegion = nextTextRegionId ? findRegion(nextProject, nextTextRegionId) : null;
      nextText.slot_id = text.slot_id && targetRegion ? regionSlotId(targetRegion) : null;
    } else {
      nextText = {
        ...nextText,
        x_mm: Math.min(nextProject.canvas_width_mm, text.x_mm + freeOffsetMm),
        y_mm: Math.min(nextProject.canvas_height_mm, text.y_mm + freeOffsetMm),
      };
    }

    nextProject.texts.push(nextText);
    newSelectedObjectIds.push(clonedTextId);
    nextZ += 1;
  });

  return {
    project: normalizeComposerProject(nextProject),
    selectedId: newSelectedObjectIds[newSelectedObjectIds.length - 1] ?? selectedId,
    selectedObjectIds: newSelectedObjectIds,
  };
}

export function duplicateComposerSelection(
  project: ComposerProject,
  selectedRegionId: string | null,
  selectedObjectIds: string[],
  options: PasteComposerOptions = {},
) {
  const clipboard = buildComposerClipboard(project, selectedRegionId, selectedObjectIds);
  if (!clipboard) {
    return {
      project,
      selectedId: selectedRegionId,
      selectedObjectIds,
    } satisfies PasteComposerResult;
  }
  return pasteComposerClipboard(project, clipboard, options);
}
