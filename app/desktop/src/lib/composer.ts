import type { ComposerPanel, ComposerProject } from "./types";
import { formatLeaf, orderPanels } from "./workbench";

export const EMPTY_COMPOSER_PROJECT: ComposerProject = {
  version: 1,
  mode: "composer",
  canvas_width_mm: 180,
  canvas_height_mm: 170,
  grid_mm: 0.5,
  panels: [],
  texts: [],
  auto_labels: true,
};

export function resolveSelectedPanelLabel(project: ComposerProject, panel: ComposerPanel) {
  if (!project.auto_labels) {
    return panel.label ?? "";
  }
  const ordered = orderPanels(project.panels);
  const index = ordered.findIndex((item) => item.id === panel.id);
  return index >= 0 ? String.fromCharCode("a".charCodeAt(0) + index) : "";
}

export function describePanelSlot(panel: ComposerPanel, canvasHeightMm: number) {
  if (panel.kind !== "graph") {
    return "自由素材";
  }
  const rowHeight = canvasHeightMm / 3;
  const column = Math.round(panel.x_mm / 60) + 1;
  const row = Math.round(panel.y_mm / rowHeight) + 1;
  return `C${column} / R${row}`;
}

export function normalizeComposerProject(project: ComposerProject): ComposerProject {
  return {
    ...EMPTY_COMPOSER_PROJECT,
    ...project,
    panels: (project.panels ?? []).map((panel) => ({
      ...panel,
      kind: panel.kind ?? "graph",
    })),
    texts: project.texts ?? [],
    auto_labels: project.auto_labels ?? true,
  };
}

export function extractComposerProject(payload: unknown): ComposerProject {
  if (!payload || typeof payload !== "object") {
    throw new Error("这不是可识别的拼图器项目文件。");
  }

  const candidate = payload as { mode?: unknown; project?: unknown };
  if ("project" in candidate && candidate.project) {
    if (candidate.mode != null && candidate.mode !== "composer") {
      throw new Error("这不是可识别的拼图器项目文件。");
    }
    return candidate.project as ComposerProject;
  }

  if ("mode" in candidate && candidate.mode !== "composer") {
    throw new Error("这不是可识别的拼图器项目文件。");
  }

  return candidate as ComposerProject;
}

export function composerLayerTitle(project: ComposerProject, panel: ComposerPanel) {
  return panel.kind === "graph"
    ? `图 ${resolveSelectedPanelLabel(project, panel) || panel.id}`
    : panel.label || formatLeaf(panel.file_path);
}
