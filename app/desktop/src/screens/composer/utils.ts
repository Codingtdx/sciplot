import {
  findRegion,
  normalizeComposerProject,
  regionRect,
  regionSlotId,
  regionSlotRect,
} from "../../lib/composer";
import type { ComposerPanel, ComposerProject, ComposerText } from "../../lib/types";

const RASTER_EXTENSIONS = new Set([
  ".png",
  ".jpg",
  ".jpeg",
  ".webp",
  ".bmp",
  ".tif",
  ".tiff",
]);

export type CellRef = { col: number; row: number };

export function isPdfPath(path: string): boolean {
  return path.toLowerCase().endsWith(".pdf");
}

export function isRasterPath(path: string): boolean {
  const dotIndex = path.lastIndexOf(".");
  if (dotIndex < 0) {
    return false;
  }
  return RASTER_EXTENSIONS.has(path.slice(dotIndex).toLowerCase());
}

export function describeSkippedFiles(paths: string[]): string | null {
  if (paths.length === 0) {
    return null;
  }
  const leaves = paths.map((path) => path.split(/[/\\]/).pop() ?? path);
  return `Skipped unsupported files: ${leaves.join(", ")}.`;
}

export function centerObjectInRect<T extends { x_mm: number; y_mm: number; w_mm?: number; h_mm?: number }>(
  target: T,
  rect: { x_mm: number; y_mm: number; w_mm: number; h_mm: number },
) {
  const width = "w_mm" in target ? target.w_mm ?? 0 : 0;
  const height = "h_mm" in target ? target.h_mm ?? 0 : 0;
  return {
    ...target,
    x_mm: rect.x_mm + (rect.w_mm - width) / 2,
    y_mm: rect.y_mm + (rect.h_mm - height) / 2,
  };
}

export function fitPanelToRect(
  panel: ComposerPanel,
  rect: { x_mm: number; y_mm: number; w_mm: number; h_mm: number },
) {
  return {
    ...panel,
    x_mm: rect.x_mm,
    y_mm: rect.y_mm,
    w_mm: rect.w_mm,
    h_mm: rect.h_mm,
  };
}

export function boundRectForDrawable(
  project: ComposerProject,
  drawable: ComposerPanel | ComposerText,
) {
  if (!drawable.region_id) {
    return null;
  }
  const region = findRegion(project, drawable.region_id);
  if (!region) {
    return null;
  }
  return drawable.slot_id ? regionSlotRect(project, region) : regionRect(project, region);
}

export function bindingValueForDrawable(drawable: ComposerPanel | ComposerText) {
  if (drawable.slot_id && drawable.region_id) {
    return `slot:${drawable.region_id}`;
  }
  if (drawable.region_id) {
    return `region:${drawable.region_id}`;
  }
  return "none";
}

export function uniqueCells(cells: CellRef[]) {
  return Array.from(new Map(cells.map((cell) => [`${cell.col}:${cell.row}`, cell])).values());
}

export function snapImportedAssetsIntoRegion(
  previousProject: ComposerProject,
  nextProject: ComposerProject,
  regionId: string,
) {
  const region = findRegion(nextProject, regionId);
  if (!region || region.kind !== "free") {
    return nextProject;
  }
  const rect = regionRect(nextProject, region);
  const existingIds = new Set(previousProject.panels.map((panel) => panel.id));
  let offset = 0;
  return normalizeComposerProject({
    ...nextProject,
    panels: nextProject.panels.map((panel) => {
      if (panel.kind !== "asset" || existingIds.has(panel.id)) {
        return panel;
      }
      const centered = centerObjectInRect(panel, rect);
      const placed = {
        ...centered,
        x_mm: centered.x_mm + offset,
        y_mm: centered.y_mm + offset,
        region_id: region.id,
        slot_id: null,
      };
      offset += 2;
      return placed;
    }),
  });
}

export function bindingRegionId(value: string) {
  if (value === "none") {
    return null;
  }
  return value.startsWith("slot:") ? value.slice(5) : value.slice(7);
}

export function bindingRectForValue(project: ComposerProject, value: string) {
  if (value === "none") {
    return null;
  }
  const region = findRegion(project, bindingRegionId(value));
  if (!region) {
    return null;
  }
  return value.startsWith("slot:") ? regionSlotRect(project, region) : regionRect(project, region);
}

export function bindingSlotIdForValue(project: ComposerProject, value: string) {
  if (!value.startsWith("slot:")) {
    return null;
  }
  const region = findRegion(project, bindingRegionId(value));
  return region ? regionSlotId(region) : null;
}
