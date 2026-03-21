import type {
  PalettePreset,
  PlotContract,
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
};

export const DEFAULT_CODE_CONSOLE_DRAFT: CodeConsoleDraft = {
  intent: "custom_plot",
  brief: "",
  targetPath: "",
  templateId: "curve",
  sizeId: "60x55",
  stylePreset: "default",
  palettePreset: "colorblind_safe",
};

export const CODE_CONSOLE_INTENTS: Array<{
  id: CodeConsoleIntent;
  label: string;
  hint: string;
}> = [
  {
    id: "custom_plot",
    label: "Special plot",
    hint: "Ask another AI to create a new custom plot while inheriting SciPlot God styling.",
  },
  {
    id: "patch_renderer",
    label: "Patch renderer",
    hint: "Ask it to modify an existing renderer or helper instead of inventing a separate demo.",
  },
  {
    id: "annotation_tweak",
    label: "Annotation tweak",
    hint: "Use this for arrows, callouts, highlights, and small visual edits on top of an existing plot.",
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
      return "例如：在现有 point_line 渲染器里加一条参考区间带，并保持项目默认线宽、字体和尺寸。";
    case "annotation_tweak":
      return "例如：在现有曲线图右上角加一个箭头和 callout 文本，箭头线宽、字号、颜色都继承项目样式。";
    case "custom_plot":
    default:
      return "例如：做一个 broken-axis curve 或两段式 special plot，但底层仍沿用 SciPlot God 的 curve 风格和尺寸规则。";
  }
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

function implementationModeLine(intent: CodeConsoleIntent) {
  switch (intent) {
    case "patch_renderer":
      return "优先修改现有 renderer/helper，而不是额外造一个和项目主链路脱节的 demo 文件。";
    case "annotation_tweak":
      return "优先在现有 figure/axes 上做最小改动，适合箭头、callout、highlight、reference marker 这类微调。";
    case "custom_plot":
    default:
      return "可以新建 custom helper 或 renderer，但视觉规则必须继续服从 SciPlot God。";
  }
}

function implementationBullets(intent: CodeConsoleIntent) {
  const shared = [
    "先复用 `src/rendering/options.py` 的 `resolve_render_options(...)` 解析 size/style/palette，不要自己拼参数。",
    "先调用 `src/plot_style.py` 的 `apply_style(...)`，再创建 figure，不要另写一套 rcParams。",
    "线宽、marker、字体、legend、导出规则从 `get_style_spec(...)` 读取；颜色或 colormap 从 `get_categorical_palette(...)` / `get_sequential_cmap(...)` 读取。",
    "figure 尺寸和物理边距走 `create_panel_figure(...)`，导出走 `save_pdf(...)`。",
  ];

  if (intent === "annotation_tweak") {
    return [
      ...shared,
      "如果要加箭头或注释，箭头线宽请复用 `style.stroke.line_width_pt`，文本字号复用 `style.typography.font_size_pt`。",
      "不要单独发明 annotation palette；优先复用当前 plot 的 categorical palette。",
    ];
  }

  if (intent === "patch_renderer") {
    return [
      ...shared,
      "如果改动会影响现有模板行为，先局部复用已有 renderer 结构，不要把逻辑绕回前端或 CLI 外壳。",
    ];
  }

  return [
    ...shared,
    "如果现有模板无法直接表达该图，请实现一个 Python helper/custom renderer，但不要破坏现有 `src/rendering/` 责任边界。",
  ];
}

export function buildCodeConsolePrompt({
  draft,
  meta,
  contract,
}: {
  draft: CodeConsoleDraft;
  meta: WorkbenchMeta | null;
  contract: PlotContract | null;
}) {
  const template = resolveCodeConsoleTemplate(meta, draft.templateId);
  const size = resolveCodeConsoleSize(meta, template, draft.sizeId);
  const style = resolveCodeConsoleStyle(meta, template, draft.stylePreset);
  const palette = resolveCodeConsolePalette(meta, template, draft.palettePreset);
  const frame = contract?.global_frame ?? meta?.global_frame;
  const publicStyles = meta?.styles.filter((item) => item.public).map((item) => item.id) ?? ["default", "nature"];
  const availablePalettes =
    template.available_palettes.length > 0
      ? template.available_palettes
      : meta?.palette_preset_ids ?? [DEFAULT_CODE_CONSOLE_DRAFT.palettePreset];
  const taskBrief = draft.brief.trim() || "把这里换成我想让你实现的特殊图或图形微调。";
  const targetPath =
    draft.targetPath.trim() ||
    (draft.intent === "annotation_tweak"
      ? "scripts/custom_plot_annotation.py 或对应 renderer/helper"
      : draft.intent === "patch_renderer"
        ? "优先选择已有相关 renderer/helper 文件"
        : `src/rendering/custom_${template.id}_helper.py`);

  return [
    "你现在是在 SciPlot God 仓库里写 Python 绘图代码，不是在写一个独立 matplotlib demo。",
    "",
    "仓库约束：",
    "- 唯一绘图事实源是 `src/plot_contract.json`。",
    "- 标准调用入口优先复用 `src/rendering/` 与 `make_plot.py` 的模式。",
    "- 如果任务需要特殊图或特殊微调，也必须继承 `src/plot_style.py` 的尺寸、字体、线宽、palette 和导出规则。",
    "- 不要在前端加常量，不要把视觉真相源搬回 GUI。",
    "- 不要手写新的线宽、字号、figure size、margin、颜色 hex，除非这些值是从项目 helper 读取出来后再使用。",
    "",
    "当前任务：",
    `- 模式：${codeConsoleIntentLabel(draft.intent)}。`,
    `- 请求：${taskBrief}`,
    `- 基础模板：${template.id} (${template.label})`,
    `- 目标尺寸：${size.id} (${size.width_mm} x ${size.height_mm} mm)`,
    `- style_preset：${style.id}`,
    `- palette_preset：${palette.id}`,
    `- 建议落点：${targetPath}`,
    "",
    "当前项目默认与约束：",
    `- 标准单图 panel：${frame?.panel_width_mm ?? 60} x ${frame?.panel_height_mm ?? 55} mm`,
    `- 全局边距：left ${frame?.left_margin_mm ?? 14} / right ${frame?.right_margin_mm ?? 4.5} / bottom ${frame?.bottom_margin_mm ?? 11} / top ${frame?.top_margin_mm ?? 5.5} mm`,
    `- 该模板允许尺寸：${template.allowed_sizes.join(", ")}`,
    `- 当前公开 style：${publicStyles.join(", ")}`,
    `- 该模板允许 palette：${availablePalettes.join(", ")}`,
    `- 该模板允许 style：${template.available_styles.join(", ")}`,
    "",
    "实现策略：",
    `- ${implementationModeLine(draft.intent)}`,
    ...implementationBullets(draft.intent).map((item) => `- ${item}`),
    "",
    "请优先参考这些文件：",
    "- `src/plot_contract.json`",
    "- `docs/plot_contract.md`",
    "- `src/plot_style.py`",
    "- `src/rendering/__init__.py`",
    "- `src/rendering/options.py`",
    "- `src/rendering/render.py`",
    "- `make_plot.py`",
    "",
    "输出要求：",
    "- 先说明你打算复用哪些项目入口。",
    "- 再给出可直接运行的 Python 代码。",
    "- 代码里要保留 `style_preset` 和 `palette_preset` 参数，默认值与项目一致。",
    "- 给一个最小可运行示例。",
    "- 不要把代码写成项目风格之外的孤立脚本。",
  ].join("\n");
}

export function buildCodeConsoleScaffold({
  draft,
  meta,
}: {
  draft: CodeConsoleDraft;
  meta: WorkbenchMeta | null;
}) {
  const template = resolveCodeConsoleTemplate(meta, draft.templateId);
  const size = resolveCodeConsoleSize(meta, template, draft.sizeId);
  const style = resolveCodeConsoleStyle(meta, template, draft.stylePreset);
  const palette = resolveCodeConsolePalette(meta, template, draft.palettePreset);
  const functionName =
    draft.intent === "annotation_tweak"
      ? "apply_annotation_tweak"
      : draft.intent === "patch_renderer"
        ? "patch_existing_renderer"
        : "render_custom_plot";

  const customBody =
    template.id === "heatmap"
      ? [
          "    cmap = plot_style.get_sequential_cmap(options.palette_preset)",
          "    image = ax.imshow(matrix, cmap=cmap, aspect=\"auto\")",
          "    if options.show_colorbar:",
          "        fig.colorbar(image, ax=ax)",
        ]
      : draft.intent === "annotation_tweak"
        ? [
            "    annotation_color = colors[0]",
            "    ax.plot(x, y, color=annotation_color, linewidth=style.stroke.line_width_pt)",
            "    ax.annotate(",
            "        \"Callout\",",
            "        xy=(x_anchor, y_anchor),",
            "        xytext=(x_text, y_text),",
            "        fontsize=style.typography.font_size_pt,",
            "        color=annotation_color,",
            "        arrowprops={",
            "            \"arrowstyle\": \"->\",",
            "            \"lw\": style.stroke.line_width_pt,",
            "            \"alpha\": style.stroke.line_alpha,",
            "            \"color\": annotation_color,",
            "        },",
            "    )",
          ]
        : [
            "    ax.plot(x, y, color=colors[0], linewidth=style.stroke.line_width_pt)",
            "    # Add the custom plot logic here while keeping project style defaults intact.",
          ];

  return [
    "from __future__ import annotations",
    "",
    "from pathlib import Path",
    "",
    "from src import plot_style",
    "from src.rendering.options import resolve_render_options",
    "",
    "",
    `def ${functionName}(`,
    "    output_path: str | Path,",
    draft.intent === "annotation_tweak" ? "    x, y," : template.id === "heatmap" ? "    matrix," : "    x, y,",
    `    *,`,
    `    size: str = "${size.id}",`,
    `    style_preset: str = "${style.id}",`,
    `    palette_preset: str = "${palette.id}",`,
    "):",
    `    options = resolve_render_options(`,
    `        template="${template.id}",`,
    "        size=size,",
    "        style_preset=style_preset,",
    "        palette_preset=palette_preset,",
    "    )",
    "    plot_style.apply_style(options.style_preset, options.palette_preset)",
    "    style = plot_style.get_style_spec(options.style_preset)",
    "    colors = plot_style.get_categorical_palette(options.palette_preset, n_colors=6)",
    "    fig, ax = plot_style.create_panel_figure(options.width_mm, options.height_mm)",
    "",
    ...customBody,
    "",
    "    plot_style.save_pdf(fig, output_path)",
    "    return Path(output_path)",
  ].join("\n");
}
