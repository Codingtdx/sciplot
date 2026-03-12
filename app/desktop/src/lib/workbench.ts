import type {
  ComposerPanel,
  PalettePreset,
  SizePreset,
  TemplateName,
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
  { id: "projects", label: "项目", icon: "PJ" },
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
    eyebrow: "Plot Wizard",
    title: "绘图精灵工作台",
    description: "把选文件、识别、调参、预检和导出收束成清楚的单步卡片流。",
  },
  composer: {
    eyebrow: "Composer",
    title: "拼图器工作台",
    description: "让画布成为主舞台，把图层、属性和对齐信息放回右侧上下文面板。",
  },
  projects: {
    eyebrow: "Projects",
    title: "项目总览",
    description: "从这里看当前会话的绘图和拼图进度，再决定回到哪条工作流继续推进。",
  },
  settings: {
    eyebrow: "Workbench",
    title: "设置与运行状态",
    description: "展示 sidecar、画布约定和 4.x 工作台的当前行为，不把不成熟的开关硬塞进界面。",
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
    title: "先把输入数据放进来",
    description: "文件进来后会先做结构识别，再给出最可能正确的图型和参数建议。",
  },
  sheet: {
    title: "确认当前使用的工作表",
    description: "多 sheet 文件先选对目标页，后面的识别、推荐和预览才有意义。",
  },
  inspect: {
    title: "看程序为什么这样判断",
    description: "这里不是黑箱推荐，而是把推断理由、模型标签和信号都摊开给你看。",
  },
  template: {
    title: "必要时改图型，不强迫一步到底",
    description: "推荐大多数时候会对，但如果你知道业务语义不一样，可以在这里改。",
  },
  options: {
    title: "只暴露真正值得你决定的参数",
    description: "先调尺寸、坐标和关键开关，把低频选项留在收起区域里。",
  },
  preflight: {
    title: "先预检，再决定要不要导出",
    description: "让错误在导出前暴露，避免白跑一轮渲染或生成不可靠结果。",
  },
  export: {
    title: "结果已经产出",
    description: "这里保留导出路径和后续动作，你可以存项目、回去改参数，或者直接换文件继续。",
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
    if (Math.abs(a.y_mm - b.y_mm) > 0.25) {
      return a.y_mm - b.y_mm;
    }
    if (Math.abs(a.x_mm - b.x_mm) > 0.25) {
      return a.x_mm - b.x_mm;
    }
    return a.id.localeCompare(b.id);
  });
}
