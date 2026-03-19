import type {
  EditableRenderOption,
  PalettePreset,
  PlotContract,
  RenderOptionsPayload,
  SizePreset,
  StylePreset,
  TemplateName,
  WorkbenchMeta,
  WorkbenchPalette,
  WorkbenchSize,
  WorkbenchStyle,
  WorkbenchTemplate,
} from "./types";

const EDITABLE_OPTION_KEYS: EditableRenderOption[] = [
  "size",
  "xscale",
  "yscale",
  "reverse_x",
  "baseline",
  "show_colorbar",
  "style_preset",
  "palette_preset",
  "use_sidecar",
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireRecord(value: unknown, label: string): Record<string, unknown> {
  if (!isRecord(value)) {
    throw new Error(`${label} is not a valid object.`);
  }
  return value;
}

function requireString(value: unknown, label: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${label} is missing or invalid.`);
  }
  return value;
}

function requireNumber(value: unknown, label: string): number {
  if (typeof value !== "number" || Number.isNaN(value)) {
    throw new Error(`${label} is missing or invalid.`);
  }
  return value;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() !== "" ? value : undefined;
}

function optionalBoolean(value: unknown): boolean | undefined {
  return typeof value === "boolean" ? value : undefined;
}

function optionalScale(value: unknown): "linear" | "log" | undefined {
  return value === "linear" || value === "log" ? value : undefined;
}

function optionalBaseline(value: unknown): "none" | "linear_endpoints" | undefined {
  return value === "none" || value === "linear_endpoints" ? value : undefined;
}

function requireStringArray(value: unknown, label: string): string[] {
  if (!Array.isArray(value)) {
    throw new Error(`${label} is not a valid list.`);
  }
  return value.map((item, index) => requireString(item, `${label}[${index}]`));
}

function readRenderOptions(
  value: unknown,
  label: string,
): RenderOptionsPayload {
  const record = requireRecord(value, label);
  const next: RenderOptionsPayload = {};
  const xscale = optionalScale(record.xscale);
  const yscale = optionalScale(record.yscale);
  const baseline = optionalBaseline(record.baseline);

  if (optionalString(record.size)) {
    next.size = record.size as SizePreset;
  }
  if (xscale) {
    next.xscale = xscale;
  }
  if (yscale) {
    next.yscale = yscale;
  }
  if (optionalBoolean(record.reverse_x) !== undefined) {
    next.reverse_x = record.reverse_x as boolean;
  }
  if (baseline) {
    next.baseline = baseline;
  }
  if (optionalBoolean(record.show_colorbar) !== undefined) {
    next.show_colorbar = record.show_colorbar as boolean;
  }
  if (optionalString(record.style_preset)) {
    next.style_preset = record.style_preset as StylePreset;
  }
  if (optionalString(record.palette_preset)) {
    next.palette_preset = record.palette_preset as PalettePreset;
  }
  if (
    optionalBoolean(record.use_sidecar) !== undefined ||
    record.use_sidecar === null
  ) {
    next.use_sidecar = record.use_sidecar as boolean | null;
  }

  return next;
}

function readEditableOptions(value: unknown, label: string): EditableRenderOption[] {
  return requireStringArray(value, label).filter(
    (item): item is EditableRenderOption =>
      EDITABLE_OPTION_KEYS.includes(item as EditableRenderOption),
  );
}

function readWorkbenchSize(value: unknown, index: number): WorkbenchSize {
  const record = requireRecord(value, `Workbench size ${index}`);
  return {
    id: requireString(record.id, `Workbench size ${index}.id`),
    label: requireString(record.label, `Workbench size ${index}.label`),
    width_mm: requireNumber(record.width_mm, `Workbench size ${index}.width_mm`),
    height_mm: requireNumber(record.height_mm, `Workbench size ${index}.height_mm`),
  };
}

function readWorkbenchStyle(value: unknown, index: number): WorkbenchStyle {
  const record = requireRecord(value, `Workbench style ${index}`);
  return {
    id: requireString(record.id, `Workbench style ${index}.id`) as StylePreset,
    label: requireString(record.label, `Workbench style ${index}.label`),
    public: Boolean(record.public),
    description: requireString(record.description, `Workbench style ${index}.description`),
    hard_constraints: Boolean(record.hard_constraints),
    preset_note: requireString(record.preset_note, `Workbench style ${index}.preset_note`),
  };
}

function readWorkbenchPalette(value: unknown, index: number): WorkbenchPalette {
  const record = requireRecord(value, `Workbench palette ${index}`);
  return {
    id: requireString(record.id, `Workbench palette ${index}.id`) as PalettePreset,
    label: requireString(record.label, `Workbench palette ${index}.label`),
    public: Boolean(record.public),
    description: requireString(record.description, `Workbench palette ${index}.description`),
    swatches: requireStringArray(record.swatches ?? [], `Workbench palette ${index}.swatches`),
  };
}

function readWorkbenchTemplate(value: unknown, index: number): WorkbenchTemplate {
  const record = requireRecord(value, `Workbench template ${index}`);
  return {
    id: requireString(record.id, `Workbench template ${index}.id`) as TemplateName,
    label: requireString(record.label, `Workbench template ${index}.label`),
    description: requireString(record.description, `Workbench template ${index}.description`),
    category: requireString(record.category, `Workbench template ${index}.category`),
    default_size: requireString(record.default_size, `Workbench template ${index}.default_size`) as SizePreset,
    allowed_sizes: requireStringArray(
      record.allowed_sizes,
      `Workbench template ${index}.allowed_sizes`,
    ) as SizePreset[],
    editable_options: readEditableOptions(
      record.editable_options,
      `Workbench template ${index}.editable_options`,
    ),
    default_options: readRenderOptions(
      record.default_options ?? {},
      `Workbench template ${index}.default_options`,
    ),
    available_styles: requireStringArray(
      record.available_styles,
      `Workbench template ${index}.available_styles`,
    ) as StylePreset[],
    available_palettes: requireStringArray(
      record.available_palettes,
      `Workbench template ${index}.available_palettes`,
    ) as PalettePreset[],
  };
}

function readLooseRecordMap(value: unknown, label: string): Record<string, Record<string, unknown>> {
  const record = requireRecord(value, label);
  const next: Record<string, Record<string, unknown>> = {};
  for (const [key, entry] of Object.entries(record)) {
    next[key] = requireRecord(entry, `${label}.${key}`);
  }
  return next;
}

function readSizePresetMap(
  value: unknown,
  label: string,
): Record<string, { label: string; width_mm: number; height_mm: number }> {
  const record = requireRecord(value, label);
  const next: Record<string, { label: string; width_mm: number; height_mm: number }> = {};
  for (const [key, entry] of Object.entries(record)) {
    const spec = requireRecord(entry, `${label}.${key}`);
    next[key] = {
      label: requireString(spec.label, `${label}.${key}.label`),
      width_mm: requireNumber(spec.width_mm, `${label}.${key}.width_mm`),
      height_mm: requireNumber(spec.height_mm, `${label}.${key}.height_mm`),
    };
  }
  return next;
}

function readSpecialLayoutMap(
  value: unknown,
  label: string,
): Record<string, Record<string, number | string | boolean>> {
  const record = requireRecord(value, label);
  const next: Record<string, Record<string, number | string | boolean>> = {};
  for (const [key, entry] of Object.entries(record)) {
    const spec = requireRecord(entry, `${label}.${key}`);
    next[key] = Object.entries(spec).reduce<Record<string, number | string | boolean>>(
      (result, [specKey, specValue]) => {
        if (
          typeof specValue === "number" ||
          typeof specValue === "string" ||
          typeof specValue === "boolean"
        ) {
          result[specKey] = specValue;
        }
        return result;
      },
      {},
    );
  }
  return next;
}

function readQaProfileMap(
  value: unknown,
  label: string,
): Record<string, Record<string, number | string | boolean | string[]>> {
  const record = requireRecord(value, label);
  const next: Record<string, Record<string, number | string | boolean | string[]>> = {};
  for (const [key, entry] of Object.entries(record)) {
    const spec = requireRecord(entry, `${label}.${key}`);
    next[key] = Object.entries(spec).reduce<Record<string, number | string | boolean | string[]>>(
      (result, [specKey, specValue]) => {
        if (
          typeof specValue === "number" ||
          typeof specValue === "string" ||
          typeof specValue === "boolean"
        ) {
          result[specKey] = specValue;
        } else if (Array.isArray(specValue) && specValue.every((item) => typeof item === "string")) {
          result[specKey] = [...specValue];
        }
        return result;
      },
      {},
    );
  }
  return next;
}

export function coerceWorkbenchMeta(value: unknown): WorkbenchMeta {
  const record = requireRecord(value, "Workbench meta");
  const defaults = requireRecord(record.defaults, "Workbench meta.defaults");
  const globalFrame = requireRecord(record.global_frame, "Workbench meta.global_frame");
  const sizes = Array.isArray(record.sizes)
    ? record.sizes.map(readWorkbenchSize)
    : [];
  const styles = Array.isArray(record.styles)
    ? record.styles.map(readWorkbenchStyle)
    : [];
  const palettes = Array.isArray(record.palettes)
    ? record.palettes.map(readWorkbenchPalette)
    : [];
  const templates = Array.isArray(record.templates)
    ? record.templates.map(readWorkbenchTemplate)
    : [];

  const templateIds = Array.isArray(record.template_ids)
    ? requireStringArray(record.template_ids, "Workbench meta.template_ids")
    : templates.map((template) => template.id);
  const sizeIds = Array.isArray(record.size_ids)
    ? requireStringArray(record.size_ids, "Workbench meta.size_ids")
    : sizes.map((size) => size.id);
  const paletteIds = Array.isArray(record.palette_preset_ids)
    ? requireStringArray(record.palette_preset_ids, "Workbench meta.palette_preset_ids")
    : palettes.map((palette) => palette.id);

  return {
    version: requireNumber(record.version, "Workbench meta.version"),
    defaults: {
      style_preset: requireString(defaults.style_preset, "Workbench meta.defaults.style_preset") as StylePreset,
      palette_preset: requireString(defaults.palette_preset, "Workbench meta.defaults.palette_preset") as PalettePreset,
    },
    global_frame: {
      panel_width_mm: requireNumber(globalFrame.panel_width_mm, "Workbench meta.global_frame.panel_width_mm"),
      panel_height_mm: requireNumber(globalFrame.panel_height_mm, "Workbench meta.global_frame.panel_height_mm"),
      left_margin_mm: requireNumber(globalFrame.left_margin_mm, "Workbench meta.global_frame.left_margin_mm"),
      right_margin_mm: requireNumber(globalFrame.right_margin_mm, "Workbench meta.global_frame.right_margin_mm"),
      bottom_margin_mm: requireNumber(globalFrame.bottom_margin_mm, "Workbench meta.global_frame.bottom_margin_mm"),
      top_margin_mm: requireNumber(globalFrame.top_margin_mm, "Workbench meta.global_frame.top_margin_mm"),
    },
    sizes,
    styles,
    palettes,
    templates,
    template_ids: templateIds as TemplateName[],
    size_ids: sizeIds as SizePreset[],
    palette_preset_ids: paletteIds as PalettePreset[],
    default_style: (optionalString(record.default_style) ?? requireString(defaults.style_preset, "Workbench meta.default_style")) as StylePreset,
    default_palette: (optionalString(record.default_palette) ?? requireString(defaults.palette_preset, "Workbench meta.default_palette")) as PalettePreset,
  };
}

export function coercePlotContract(value: unknown): PlotContract {
  const record = requireRecord(value, "Plot contract");
  const defaults = requireRecord(record.defaults, "Plot contract.defaults");
  const globalFrame = requireRecord(record.global_frame, "Plot contract.global_frame");

  return {
    version: requireNumber(record.version, "Plot contract.version"),
    defaults: {
      style_preset: requireString(defaults.style_preset, "Plot contract.defaults.style_preset") as StylePreset,
      palette_preset: requireString(defaults.palette_preset, "Plot contract.defaults.palette_preset") as PalettePreset,
    },
    global_frame: {
      panel_width_mm: requireNumber(globalFrame.panel_width_mm, "Plot contract.global_frame.panel_width_mm"),
      panel_height_mm: requireNumber(globalFrame.panel_height_mm, "Plot contract.global_frame.panel_height_mm"),
      left_margin_mm: requireNumber(globalFrame.left_margin_mm, "Plot contract.global_frame.left_margin_mm"),
      right_margin_mm: requireNumber(globalFrame.right_margin_mm, "Plot contract.global_frame.right_margin_mm"),
      bottom_margin_mm: requireNumber(globalFrame.bottom_margin_mm, "Plot contract.global_frame.bottom_margin_mm"),
      top_margin_mm: requireNumber(globalFrame.top_margin_mm, "Plot contract.global_frame.top_margin_mm"),
    },
    size_presets: readSizePresetMap(record.size_presets ?? {}, "Plot contract.size_presets"),
    special_layouts: readSpecialLayoutMap(record.special_layouts ?? {}, "Plot contract.special_layouts"),
    qa_profiles: readQaProfileMap(record.qa_profiles ?? {}, "Plot contract.qa_profiles"),
    styles: readLooseRecordMap(record.styles ?? {}, "Plot contract.styles"),
    palettes: readLooseRecordMap(record.palettes ?? {}, "Plot contract.palettes"),
    templates: readLooseRecordMap(record.templates ?? {}, "Plot contract.templates"),
    validation_rules: readLooseRecordMap(record.validation_rules ?? {}, "Plot contract.validation_rules"),
  };
}
