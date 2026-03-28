import type { AppIconName } from "../components/AppIcon";
import type {
  ComposerPanel,
  PalettePreset,
  PlotStage,
  SizePreset,
  TemplateName,
  WorkbenchMeta,
  WorkbenchRoute,
  WorkbenchTemplate,
  WorkbenchWorkspace,
  WizardStep,
} from "./types";

export const PLOT_STAGE_ORDER: PlotStage[] = [
  "import",
  "sheet",
  "type",
  "tune",
  "review",
  "export",
];

export const PLOT_STAGE_ROUTES: Record<PlotStage, WorkbenchRoute> = {
  import: "/plot/import",
  sheet: "/plot/import",
  type: "/plot/template",
  tune: "/plot/refine",
  review: "/plot/refine",
  export: "/plot/refine",
};

export const APP_ROUTES: WorkbenchRoute[] = [
  "/",
  "/plot/import",
  "/plot/template",
  "/plot/refine",
];

export const WORKSPACE_ITEMS: Array<{
  workspace: WorkbenchWorkspace;
  label: string;
  icon: AppIconName;
}> = [
  { workspace: "launchpad", label: "Start", icon: "start" },
  { workspace: "plot", label: "Plot", icon: "plot" },
];

export const WORKSPACE_META: Record<
  WorkbenchWorkspace,
  {
    eyebrow: string;
    title: string;
    description: string;
  }
> = {
  launchpad: {
    eyebrow: "Plot Workspace",
    title: "Start",
    description: "Open a dataset or resume recent work.",
  },
  plot: {
    eyebrow: "Plot Workspace",
    title: "Plot",
    description: "Import, recommend, refine, and export.",
  },
};

export const PLOT_STAGES: Array<{
  id: PlotStage;
  label: string;
  hint: string;
}> = [
  { id: "import", label: "Plot Import", hint: "Load the dataset" },
  { id: "sheet", label: "Plot Import", hint: "Choose the workbook tab" },
  { id: "type", label: "Plot Template", hint: "Pick the recommended chart family" },
  { id: "tune", label: "Plot Refine", hint: "Adjust the figure" },
  { id: "review", label: "Plot Refine", hint: "Confirm readiness inline" },
  { id: "export", label: "Plot Refine", hint: "Write the bundle inline" },
];

export const PLOT_STAGE_COPY: Record<
  PlotStage,
  {
    title: string;
    description: string;
  }
> = {
  import: {
    title: "Import a dataset",
    description: "Open the file and confirm detected structure.",
  },
  sheet: {
    title: "Choose the source tab",
    description: "Pick the workbook sheet inside Plot Import.",
  },
  type: {
    title: "Choose the plot template",
    description: "Lead with the strongest recommendation first.",
  },
  tune: {
    title: "Refine the chart",
    description: "Adjust the key rendering options inline.",
  },
  review: {
    title: "Check export readiness",
    description: "Keep preview, readiness, and export in one screen.",
  },
  export: {
    title: "Export the bundle",
    description: "Write output and reveal it without leaving Plot Refine.",
  },
};

export function isWorkbenchRoute(value: string): value is WorkbenchRoute {
  return APP_ROUTES.includes(value as WorkbenchRoute);
}

export function normalizeWorkbenchRoute(value: string | null | undefined): WorkbenchRoute | null {
  if (!value) {
    return null;
  }
  if (value === "/plot/sheet") {
    return "/plot/import";
  }
  if (value === "/plot/type") {
    return "/plot/template";
  }
  if (value === "/plot/tune" || value === "/plot/review" || value === "/plot/export") {
    return "/plot/refine";
  }
  return isWorkbenchRoute(value) ? value : null;
}

export function workspaceForRoute(route: WorkbenchRoute): WorkbenchWorkspace {
  if (route === "/") {
    return "launchpad";
  }
  if (route.startsWith("/plot/")) {
    return "plot";
  }
  return "launchpad";
}

export function plotRoute(stage: PlotStage): WorkbenchRoute {
  return PLOT_STAGE_ROUTES[stage];
}

export function plotStageFromRoute(route: WorkbenchRoute): PlotStage {
  if (route === "/plot/import") {
    return "import";
  }
  if (route === "/plot/template") {
    return "type";
  }
  if (route === "/plot/refine") {
    return "tune";
  }
  return "import";
}

export function plotStageForWizardStep(step: WizardStep): PlotStage {
  switch (step) {
    case "sheet":
      return "sheet";
    case "inspect":
    case "template":
      return "type";
    case "options":
      return "tune";
    case "preflight":
      return "review";
    case "export":
      return "export";
    case "file":
    default:
      return "import";
  }
}

export function wizardStepForStage(stage: PlotStage): WizardStep {
  switch (stage) {
    case "sheet":
      return "sheet";
    case "type":
      return "inspect";
    case "tune":
      return "options";
    case "review":
      return "preflight";
    case "export":
      return "export";
    case "import":
    default:
      return "file";
  }
}

export function formatLeaf(path: string) {
  return path.split(/[/\\]/).pop() ?? path;
}

export function getErrorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}

export function toDialogPaths(selected: string | string[] | null, limit?: number) {
  const paths = Array.isArray(selected)
    ? selected.filter((item): item is string => typeof item === "string")
    : typeof selected === "string"
      ? [selected]
      : [];
  return typeof limit === "number" ? paths.slice(0, limit) : paths;
}

export function formatMetricValue(value: number | null) {
  if (value == null || Number.isNaN(value)) {
    return "-";
  }
  return value.toFixed(2);
}

export function inferTensileGroupName(filePaths: string[]) {
  const stems = filePaths.map((path) => formatLeaf(path).replace(/\.[^.]+$/, ""));
  if (stems.length === 0) {
    return "Tensile_Group";
  }
  let prefix = stems[0];
  for (const stem of stems.slice(1)) {
    while (prefix && !stem.startsWith(prefix)) {
      prefix = prefix.slice(0, -1);
    }
  }
  prefix = prefix.replace(/[_\-\s]+$/, "");
  return prefix || stems[0] || "Tensile_Group";
}

export function defaultSiblingPath(filePath: string, filename: string) {
  const parts = filePath.split(/[/\\]/);
  parts[parts.length - 1] = filename;
  return parts.join(filePath.includes("\\") ? "\\" : "/");
}

export function formatRecentTimestamp(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function getWizardStepLabel(step: WizardStep) {
  return getPlotStageLabel(plotStageForWizardStep(step));
}

export function getPlotStageLabel(stage: PlotStage) {
  return PLOT_STAGES.find((item) => item.id === stage)?.label ?? stage;
}

export function templateMeta(meta: WorkbenchMeta | null, template: TemplateName | null | undefined) {
  if (!meta || !template) {
    return null;
  }
  return meta.templates.find((item) => item.id === template) ?? null;
}

export function templateLabel(meta: WorkbenchMeta | null, template: TemplateName | null | undefined) {
  return templateMeta(meta, template)?.label ?? template ?? "-";
}

export function paletteLabel(
  meta: WorkbenchMeta | null,
  palette: PalettePreset | string | null | undefined,
) {
  if (!meta || !palette) {
    return palette ?? "-";
  }
  return meta.palettes.find((item) => item.id === palette)?.label ?? palette;
}

export function styleLabel(meta: WorkbenchMeta | null, style: string | null | undefined) {
  if (!meta || !style) {
    return style ?? "-";
  }
  return meta.styles.find((item) => item.id === style)?.label ?? style;
}

export function visualThemeLabel(meta: WorkbenchMeta | null, visualTheme: string | null | undefined) {
  if (!meta || !visualTheme) {
    return visualTheme ?? "-";
  }
  return meta.visual_themes.find((item) => item.id === visualTheme)?.label ?? visualTheme;
}

export function visualThemeChoices(meta: WorkbenchMeta | null) {
  return meta?.visual_themes ?? [];
}

export function templateChoices(meta: WorkbenchMeta | null) {
  return meta?.templates ?? [];
}

const COMPATIBLE_TEMPLATE_IDS: Record<string, TemplateName[]> = {
  frequency_sweep: ["point_line", "curve"],
  temperature_sweep: ["point_line", "curve"],
  stress_relaxation: ["point_line", "curve"],
  tensile_curve: [
    "curve",
    "point_line",
    "mean_band",
    "replicate_curves_with_band",
    "stacked_curve",
    "segmented_stacked_curve",
    "scatter",
    "bubble_scatter",
    "scatter_fit",
    "scatter_with_fit",
  ],
  curve_table: [
    "curve",
    "point_line",
    "mean_band",
    "replicate_curves_with_band",
    "stacked_curve",
    "segmented_stacked_curve",
    "scatter",
    "bubble_scatter",
    "scatter_fit",
    "scatter_with_fit",
  ],
  replicate_table: [
    "distribution_compare",
    "box_strip",
    "violin_box",
    "point_error",
    "lollipop_error",
    "grouped_bar_error",
    "grouped_bar_compare",
    "histogram_density",
    "box",
    "violin",
    "bar",
  ],
  heatmap_table: ["heatmap", "annotated_heatmap"],
};

export function isTensileCurveModel(model: string | null | undefined) {
  return model === "tensile_curve";
}

export function compatibleTemplateIds(model: string | null | undefined) {
  if (!model) {
    return [] as TemplateName[];
  }
  return COMPATIBLE_TEMPLATE_IDS[model] ?? [];
}

export function compatibleTemplateChoices(
  meta: WorkbenchMeta | null,
  model: string | null | undefined,
) {
  const choices = templateChoices(meta);
  const preferredIds = compatibleTemplateIds(model);
  if (preferredIds.length === 0) {
    return choices;
  }
  return preferredIds
    .map((templateId) => choices.find((item) => item.id === templateId))
    .filter((item): item is WorkbenchTemplate => Boolean(item));
}

export function incompatibleTemplateChoices(
  meta: WorkbenchMeta | null,
  model: string | null | undefined,
) {
  const choices = templateChoices(meta);
  const preferredIds = new Set(compatibleTemplateIds(model));
  if (preferredIds.size === 0) {
    return [] as typeof choices;
  }
  return choices.filter((item) => !preferredIds.has(item.id));
}

export function templateCompatibilityReason(model: string | null | undefined) {
  switch (model) {
    case "frequency_sweep":
    case "temperature_sweep":
    case "stress_relaxation":
      return "This input is a rheology export bundle. Start with point-line or curve.";
    case "tensile_curve":
      return "This input is a tensile stress-strain curve. Start with curve-family templates.";
    case "curve_table":
      return "This input is a paired curve table. Start with curve-family templates.";
    case "replicate_table":
      return "This input is a replicate summary table. Start with distribution, box+strip, violin+box, point+error, lollipop+error, grouped-bar+error, histogram-density, or classic stats templates.";
    case "heatmap_table":
      return "This input is an XYZ heatmap table. Start with heatmap templates.";
    default:
      return "The current input structure is not compatible with this template.";
  }
}

export function sizeChoices(meta: WorkbenchMeta | null, template: TemplateName | null | undefined) {
  const currentTemplate = templateMeta(meta, template);
  if (!currentTemplate || !meta) {
    return [] as Array<{ id: SizePreset; label: string }>;
  }
  return currentTemplate.allowed_sizes
    .map((sizeId) => meta.sizes.find((item) => item.id === sizeId))
    .filter(
      (
        item,
      ): item is { id: SizePreset; label: string; width_mm: number; height_mm: number } =>
        Boolean(item),
    );
}

export function publicPaletteChoices(
  meta: WorkbenchMeta | null,
  template: TemplateName | null | undefined,
) {
  const currentTemplate = templateMeta(meta, template);
  if (!currentTemplate || !meta) {
    return [] as WorkbenchMeta["palettes"];
  }
  return meta.palettes.filter(
    (item) => item.public && currentTemplate.available_palettes.includes(item.id),
  );
}

export function publicStyleChoices(
  meta: WorkbenchMeta | null,
  template: TemplateName | null | undefined,
) {
  const currentTemplate = templateMeta(meta, template);
  if (!currentTemplate || !meta) {
    return [] as WorkbenchMeta["styles"];
  }
  return meta.styles.filter(
    (item) => item.public && currentTemplate.available_styles.includes(item.id),
  );
}

export function orderPanels(panels: ComposerPanel[]) {
  return [...panels].sort((a, b) => {
    if (a.z_index !== b.z_index) {
      return a.z_index - b.z_index;
    }
    return a.id.localeCompare(b.id);
  });
}

type WizardSessionSnapshot = {
  inputPath: string;
  inspection: unknown | null;
  template: string | null | undefined;
  outputs: readonly string[];
  exportResult?: { output_dir?: string | null } | null;
};

type ComposerSessionSnapshot = {
  regions: readonly unknown[];
  panels: readonly unknown[];
  texts: readonly unknown[];
};

function confirmSessionReplacement(message: string) {
  if (typeof window === "undefined" || typeof window.confirm !== "function") {
    return true;
  }
  return window.confirm(message);
}

export function hasWizardSessionContent(session: WizardSessionSnapshot) {
  return Boolean(
    session.inputPath ||
      session.inspection ||
      session.template ||
      session.outputs.length > 0 ||
      session.exportResult?.output_dir,
  );
}

export function hasComposerSessionContent(project: ComposerSessionSnapshot) {
  return project.regions.length > 0 || project.panels.length > 0 || project.texts.length > 0;
}

export function confirmReplaceWizardSession(
  session: WizardSessionSnapshot,
  nextLabel: string,
  nextPath?: string,
) {
  if (!hasWizardSessionContent(session)) {
    return true;
  }
  if (nextPath && session.inputPath && nextPath === session.inputPath) {
    return true;
  }
  return confirmSessionReplacement(
    `Opening ${nextLabel} will replace the current Plot session. Save the current project first if you need to keep it. Continue?`,
  );
}

export function confirmReplaceComposerSession(
  project: ComposerSessionSnapshot,
  nextLabel: string,
) {
  if (!hasComposerSessionContent(project)) {
    return true;
  }
  return confirmSessionReplacement(
    `Opening ${nextLabel} will replace the current Composer layout. Save the current project first if you need to keep it. Continue?`,
  );
}
