import type {
  PalettePreset,
  RenderOptionsPayload,
  SizePreset,
  StylePreset,
  WorkbenchMeta,
  WorkbenchSize,
  WorkbenchTemplate,
} from "./types";

export type CodeConsoleIntent = "custom_plot" | "patch_renderer" | "annotation_tweak";

export type CodeConsoleDraft = {
  intent: CodeConsoleIntent;
  brief: string;
  targetPath: string;
  templateId: string;
  sizeId: SizePreset;
  stylePreset: StylePreset;
  palettePreset: PalettePreset;
  includeDataContext: boolean;
  includeInspectionSummary: boolean;
  includeProjectContext: boolean;
  includeFullDataBundle: boolean;
};

export const DEFAULT_CODE_CONSOLE_DRAFT: CodeConsoleDraft = {
  intent: "custom_plot",
  brief: "",
  targetPath: "",
  templateId: "curve",
  sizeId: "60x55",
  stylePreset: "default",
  palettePreset: "colorblind_safe",
  includeDataContext: true,
  includeInspectionSummary: true,
  includeProjectContext: false,
  includeFullDataBundle: false,
};

export const CODE_CONSOLE_INTENTS: Array<{
  id: CodeConsoleIntent;
  label: string;
  hint: string;
}> = [
  {
    id: "custom_plot",
    label: "Special plot",
    hint: "Ask another AI to implement a new plot path that still behaves like SciPlot God code.",
  },
  {
    id: "patch_renderer",
    label: "Patch renderer",
    hint: "Modify an existing renderer/helper instead of spinning up a detached demo flow.",
  },
  {
    id: "annotation_tweak",
    label: "Annotation tweak",
    hint: "Apply a small, style-backed visual change on top of an existing plotting path.",
  },
];

const FALLBACK_TEMPLATE: WorkbenchTemplate = {
  id: "curve",
  label: "Curve",
  description: "Standard single-panel curve plot.",
  category: "single_panel",
  default_size: "60x55",
  allowed_sizes: ["60x55", "120x55"],
  editable_options: ["size", "xscale", "yscale", "reverse_x", "style_preset", "palette_preset"],
  default_options: {
    size: "60x55",
    xscale: "linear",
    yscale: "linear",
    reverse_x: false,
    style_preset: "default",
    palette_preset: "colorblind_safe",
  },
  available_styles: ["default", "nature"],
  available_palettes: ["colorblind_safe", "mono"],
};

const FALLBACK_SIZE: WorkbenchSize = {
  id: "60x55",
  label: "60 x 55 mm",
  width_mm: 60,
  height_mm: 55,
};

function formatIdLabel(value: string) {
  return value
    .split(/[_-]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

export function codeConsoleIntentLabel(intent: CodeConsoleIntent) {
  return CODE_CONSOLE_INTENTS.find((item) => item.id === intent)?.label ?? "Special plot";
}

export function codeConsoleIntentHint(intent: CodeConsoleIntent) {
  return (
    CODE_CONSOLE_INTENTS.find((item) => item.id === intent)?.hint ??
    "Ask another AI to write repository-native Python plotting code."
  );
}

export function codeConsoleBriefPlaceholder(intent: CodeConsoleIntent) {
  switch (intent) {
    case "patch_renderer":
      return "例如：在现有 point_line 渲染器里加一条参考区间带，并继续走项目默认尺寸、字体和导出规则。";
    case "annotation_tweak":
      return "例如：在现有曲线图右上角加一个箭头和 callout，但箭头线宽、字号、颜色都继承项目样式。";
    case "custom_plot":
    default:
      return "例如：实现一个 broken-axis curve 或两段式 special plot，但代码仍然复用 SciPlot God 的 helper 和 renderer 入口。";
  }
}

export function defaultCodeConsoleTargetPath(intent: CodeConsoleIntent, templateId: string) {
  switch (intent) {
    case "annotation_tweak":
      return "scripts/custom_plot_annotation.py or the relevant renderer/helper";
    case "patch_renderer":
      return "The most relevant existing renderer/helper file under src/rendering/";
    case "custom_plot":
    default:
      return `src/rendering/custom_${templateId}_helper.py`;
  }
}

export function backfillCodeConsoleValue<T extends string>(
  draftValue: T,
  sessionValue: T | null | undefined,
  fallbackValue: T,
): T {
  if ((draftValue === "" || draftValue === fallbackValue) && sessionValue) {
    return sessionValue;
  }
  return draftValue || sessionValue || fallbackValue;
}

export function backfillCodeConsoleOptions(
  draft: CodeConsoleDraft,
  session: {
    templateId?: string | null;
    options?: RenderOptionsPayload | null;
  },
): Pick<CodeConsoleDraft, "templateId" | "sizeId" | "stylePreset" | "palettePreset"> {
  return {
    templateId: backfillCodeConsoleValue(
      draft.templateId,
      session.templateId ?? undefined,
      DEFAULT_CODE_CONSOLE_DRAFT.templateId,
    ),
    sizeId: backfillCodeConsoleValue(
      draft.sizeId,
      session.options?.size ?? undefined,
      DEFAULT_CODE_CONSOLE_DRAFT.sizeId,
    ),
    stylePreset: backfillCodeConsoleValue(
      draft.stylePreset,
      session.options?.style_preset ?? undefined,
      DEFAULT_CODE_CONSOLE_DRAFT.stylePreset,
    ),
    palettePreset: backfillCodeConsoleValue(
      draft.palettePreset,
      session.options?.palette_preset ?? undefined,
      DEFAULT_CODE_CONSOLE_DRAFT.palettePreset,
    ),
  };
}

export function resolveCodeConsoleTemplate(meta: WorkbenchMeta | null, templateId: string) {
  if (!meta?.templates.length) {
    return FALLBACK_TEMPLATE;
  }
  return meta.templates.find((item) => item.id === templateId) ?? meta.templates[0] ?? FALLBACK_TEMPLATE;
}

export function resolveCodeConsoleSize(
  meta: WorkbenchMeta | null,
  template: WorkbenchTemplate,
  sizeId: SizePreset,
) {
  const fallbackSizeId = template.default_size || DEFAULT_CODE_CONSOLE_DRAFT.sizeId;
  const resolvedSizeId = template.allowed_sizes.includes(sizeId) ? sizeId : fallbackSizeId;
  return (
    meta?.sizes.find((item) => item.id === resolvedSizeId) ??
    meta?.sizes.find((item) => item.id === fallbackSizeId) ??
    FALLBACK_SIZE
  );
}

export function resolveCodeConsoleStyle(
  meta: WorkbenchMeta | null,
  template: WorkbenchTemplate,
  stylePreset: StylePreset,
) {
  const fallback = template.available_styles[0] ?? meta?.default_style ?? DEFAULT_CODE_CONSOLE_DRAFT.stylePreset;
  const resolvedId = template.available_styles.includes(stylePreset) ? stylePreset : fallback;
  const record = meta?.styles.find((item) => item.id === resolvedId);
  return {
    id: resolvedId,
    label: record?.label ?? formatIdLabel(resolvedId),
  };
}

export function resolveCodeConsolePalette(
  meta: WorkbenchMeta | null,
  template: WorkbenchTemplate,
  palettePreset: PalettePreset,
) {
  const fallback =
    template.available_palettes[0] ?? meta?.default_palette ?? DEFAULT_CODE_CONSOLE_DRAFT.palettePreset;
  const resolvedId = template.available_palettes.includes(palettePreset) ? palettePreset : fallback;
  const record = meta?.palettes.find((item) => item.id === resolvedId);
  return {
    id: resolvedId,
    label: record?.label ?? formatIdLabel(resolvedId),
    swatches: record?.swatches ?? [],
  };
}
