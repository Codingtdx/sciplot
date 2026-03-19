import type { AppIconName } from "../components/AppIcon";
import type {
  ComposerPanel,
  PalettePreset,
  SizePreset,
  TemplateName,
  WorkbenchTemplate,
  WizardStep,
  WorkbenchMeta,
  WorkbenchScreen,
} from "./types";

export type AppMode = WorkbenchScreen;

export const NAV_ITEMS: Array<{
  id: AppMode;
  label: string;
  icon: AppIconName;
}> = [
  { id: "tensile", label: "Tensile", icon: "tensile" },
  { id: "wizard", label: "Plot", icon: "plot" },
  { id: "composer", label: "Composer", icon: "composer" },
  { id: "projects", label: "Recents", icon: "projects" },
  { id: "settings", label: "Settings", icon: "settings" },
];

export const SCREEN_META: Record<
  AppMode,
  {
    eyebrow: string;
    title: string;
    description: string;
  }
> = {
  tensile: {
    eyebrow: "Material Lab",
    title: "Tensile Workspace",
    description: "Prepare raw tensile runs, queue workbooks, and export comparison figures.",
  },
  wizard: {
    eyebrow: "Figure Flow",
    title: "Plot Builder",
    description: "Import data, review the recommendation, and export polished PDF figures.",
  },
  composer: {
    eyebrow: "Layout Studio",
    title: "Figure Composer",
    description: "Arrange figures, assets, and labels on one editable export canvas.",
  },
  projects: {
    eyebrow: "History",
    title: "Recent Files",
    description: "Jump back into recent plotting inputs, workbooks, and composer projects.",
  },
  settings: {
    eyebrow: "Runtime",
    title: "Settings",
    description: "Check sidecar health, tune preferences, and reset local workspace state.",
  },
};

export const STEPS: Array<{
  id: WizardStep;
  label: string;
  hint: string;
}> = [
  { id: "file", label: "Import", hint: "Pick a file" },
  { id: "sheet", label: "Sheet", hint: "Choose a tab" },
  { id: "inspect", label: "Detect", hint: "Review the fit" },
  { id: "template", label: "Template", hint: "Switch if needed" },
  { id: "options", label: "Options", hint: "Adjust essentials" },
  { id: "preflight", label: "Review", hint: "Resolve blockers" },
  { id: "export", label: "Export", hint: "Make the PDF" },
];

export const STEP_COPY: Record<
  WizardStep,
  {
    title: string;
    description: string;
  }
> = {
  file: {
    title: "Import a data file",
    description: "The app inspects structure first and suggests the best starting template.",
  },
  sheet: {
    title: "Choose a sheet",
    description: "For multi-sheet workbooks, confirm the target tab before continuing.",
  },
  inspect: {
    title: "Review the recommendation",
    description: "Confirm the detected model, suggested template, and major warnings.",
  },
  template: {
    title: "Switch template if needed",
    description: "Change templates only when the recommended path does not fit the data.",
  },
  options: {
    title: "Adjust key options",
    description: "Review size, axes, and a few essential settings before export.",
  },
  preflight: {
    title: "Review before export",
    description: "Clear blockers and warnings before generating the final PDF.",
  },
  export: {
    title: "Export complete",
    description: "Check the outputs, keep iterating, or move to the next dataset.",
  },
};

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
  return STEPS.find((item) => item.id === step)?.label ?? step;
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

export function paletteLabel(meta: WorkbenchMeta | null, palette: PalettePreset | string | null | undefined) {
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

export function templateChoices(meta: WorkbenchMeta | null) {
  return meta?.templates ?? [];
}

const COMPATIBLE_TEMPLATE_IDS: Record<string, TemplateName[]> = {
  frequency_sweep: ["point_line", "curve"],
  temperature_sweep: ["point_line", "curve"],
  stress_relaxation: ["point_line", "curve"],
  tensile_curve: ["curve", "point_line", "stacked_curve", "segmented_stacked_curve", "scatter"],
  curve_table: ["curve", "point_line", "stacked_curve", "segmented_stacked_curve", "scatter"],
  replicate_table: ["bar", "box", "violin"],
  heatmap_table: ["heatmap"],
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
      return "This input is a replicate summary table. Start with bar, box, or violin.";
    case "heatmap_table":
      return "This input is an XYZ heatmap table. Start with the heatmap template.";
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
    .filter((item): item is { id: SizePreset; label: string; width_mm: number; height_mm: number } => Boolean(item));
}

export function publicPaletteChoices(meta: WorkbenchMeta | null, template: TemplateName | null | undefined) {
  const currentTemplate = templateMeta(meta, template);
  if (!currentTemplate || !meta) {
    return [] as WorkbenchMeta["palettes"];
  }
  return meta.palettes.filter(
    (item) =>
      item.public && currentTemplate.available_palettes.includes(item.id),
  );
}

export function publicStyleChoices(meta: WorkbenchMeta | null, template: TemplateName | null | undefined) {
  const currentTemplate = templateMeta(meta, template);
  if (!currentTemplate || !meta) {
    return [] as WorkbenchMeta["styles"];
  }
  return meta.styles.filter(
    (item) =>
      item.public && currentTemplate.available_styles.includes(item.id),
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
  return (
    project.regions.length > 0 ||
    project.panels.length > 0 ||
    project.texts.length > 0
  );
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
    `Opening ${nextLabel} will replace the current Plot Builder session. Save the current project first if you need to keep it. Continue?`,
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
