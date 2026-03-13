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
  icon: string;
}> = [
  { id: "wizard", label: "绘图", icon: "WZ" },
  { id: "composer", label: "拼图", icon: "CP" },
  { id: "projects", label: "最近", icon: "RC" },
  { id: "settings", label: "设置", icon: "ST" },
];

export const SCREEN_META: Record<
  AppMode,
  {
    eyebrow: string;
    title: string;
    description: string;
  }
> = {
  wizard: {
    eyebrow: "Plot",
    title: "绘图精灵工作台",
    description: "导入数据、确认推荐并导出 PDF。",
  },
  composer: {
    eyebrow: "Layout",
    title: "拼图器工作台",
    description: "导入图和素材，排版后导出单页可编辑 PDF。",
  },
  projects: {
    eyebrow: "Recent",
    title: "最近记录",
    description: "快速回到最近打开的数据或拼图文件。",
  },
  settings: {
    eyebrow: "Settings",
    title: "设置与运行状态",
    description: "检查连接状态，切换主题，并调整常用偏好。",
  },
};

export const STEPS: Array<{
  id: WizardStep;
  label: string;
  hint: string;
}> = [
  { id: "file", label: "文件", hint: "选输入" },
  { id: "sheet", label: "Sheet", hint: "选工作表" },
  { id: "inspect", label: "识别", hint: "看推荐" },
  { id: "template", label: "图型", hint: "必要时改" },
  { id: "options", label: "参数", hint: "只调关键项" },
  { id: "preflight", label: "检查", hint: "拦截风险" },
  { id: "export", label: "导出", hint: "拿结果" },
];

export const STEP_COPY: Record<
  WizardStep,
  {
    title: string;
    description: string;
  }
> = {
  file: {
    title: "导入数据文件",
    description: "选择数据后，程序会先识别结构并给出推荐图型。",
  },
  sheet: {
    title: "确认工作表",
    description: "多 sheet 文件先选对目标页，再继续后续步骤。",
  },
  inspect: {
    title: "查看推荐结果",
    description: "确认识别结果、推荐图型和关键提醒。",
  },
  template: {
    title: "必要时切换图型",
    description: "如果推荐不适合当前数据，可以在这里改成其他图型。",
  },
  options: {
    title: "调整关键参数",
    description: "先确认尺寸、坐标轴和常用选项，再进入检查。",
  },
  preflight: {
    title: "检查后再导出",
    description: "先处理错误和警告，再生成最终 PDF。",
  },
  export: {
    title: "导出完成",
    description: "查看结果路径，继续调整参数，或直接换下一份数据。",
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
  return date.toLocaleString("zh-CN", {
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

export function templateChoices(meta: WorkbenchMeta | null) {
  return meta?.templates ?? [];
}

const COMPATIBLE_TEMPLATE_IDS: Record<string, TemplateName[]> = {
  frequency_sweep: ["point_line", "curve"],
  temperature_sweep: ["point_line", "curve"],
  stress_relaxation: ["point_line", "curve"],
  curve_table: ["curve", "point_line", "stacked_curve", "segmented_stacked_curve", "scatter"],
  replicate_table: ["bar", "box", "violin"],
  heatmap_table: ["heatmap"],
};

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
      return "当前输入是流变导出表，先用点线或曲线。";
    case "curve_table":
      return "当前输入是成对曲线表，先用曲线家族。";
    case "replicate_table":
      return "当前输入是重复值统计表，先用 bar / box / violin。";
    case "heatmap_table":
      return "当前输入是 XYZ 热图表，先用热图。";
    default:
      return "当前输入结构和这个图型不兼容。";
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

export function orderPanels(panels: ComposerPanel[]) {
  return [...panels].sort((a, b) => {
    if (a.z_index !== b.z_index) {
      return a.z_index - b.z_index;
    }
    return a.id.localeCompare(b.id);
  });
}
