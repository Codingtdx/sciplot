import type {
  CodeConsoleColumnSummary,
  CodeConsoleContractSummary,
  CodeConsoleDataContext,
  CodeConsoleDefaultsPanel,
  CodeConsoleExportResponse,
  CodeConsoleGeneratedFile,
  CodeConsoleGenerateResponse,
  CodeConsoleInspectionSummary,
  CodeConsoleLightweightBundle,
  CodeConsoleReasonedValue,
  CodeConsoleRecommendationSummary,
  CodeConsoleRunResponse,
  CodeConsoleSessionSummary,
  CodeConsoleTruthSource,
  DataTemplateCatalogItem,
  DataTemplateCatalogResponse,
  DataTemplateFolderFile,
  DataTemplateFolderResponse,
  DataTemplateMaterializeResponse,
  ManagedStorageCleanupResponse,
  ManagedStorageStatus,
  EditableRenderOption,
  PalettePreset,
  PlotContract,
  PreviewItem,
  RenderOptionsPayload,
  SizePreset,
  StylePreset,
  TemplateName,
  WorkbenchMeta,
  WorkbenchPalette,
  WorkbenchVisualTheme,
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
  "visual_theme_id",
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

function requireBoolean(value: unknown, label: string): boolean {
  if (typeof value !== "boolean") {
    throw new Error(`${label} is missing or invalid.`);
  }
  return value;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() !== "" ? value : undefined;
}

function optionalNumber(value: unknown): number | undefined {
  return typeof value === "number" && !Number.isNaN(value) ? value : undefined;
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

function readWorkbenchVisualTheme(value: unknown, index: number): WorkbenchVisualTheme {
  const record = requireRecord(value, `Workbench visual theme ${index}`);
  return {
    id: requireString(record.id, `Workbench visual theme ${index}.id`),
    label: requireString(record.label, `Workbench visual theme ${index}.label`),
    description: requireString(record.description, `Workbench visual theme ${index}.description`),
  };
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
  const visualThemeId = optionalString(record.visual_theme_id);
  if (visualThemeId) {
    next.visual_theme_id = visualThemeId;
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
  const canonicalId = optionalString(record.canonical_id);
  const role = optionalString(record.role);
  const lifecyclePolicy = optionalString(record.lifecycle_policy);
  const implementationId = optionalString(record.implementation_id);
  return {
    id: requireString(record.id, `Workbench template ${index}.id`) as TemplateName,
    canonical_id: canonicalId ? (canonicalId as TemplateName) : undefined,
    role: role === "alias" || role === "canonical" ? role : undefined,
    lifecycle_policy: lifecyclePolicy ?? undefined,
    implementation_id: implementationId ? (implementationId as TemplateName) : undefined,
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

function readStringMatrix(value: unknown, label: string): unknown[][] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.map((row, rowIndex) => {
    if (!Array.isArray(row)) {
      throw new Error(`${label}[${rowIndex}] is not a valid row.`);
    }
    return [...row];
  });
}

function readNumberRecord(value: unknown, label: string): Record<string, number> {
  const record = requireRecord(value, label);
  const next: Record<string, number> = {};
  for (const [key, item] of Object.entries(record)) {
    if (typeof item === "number" && !Number.isNaN(item)) {
      next[key] = item;
    }
  }
  return next;
}

function readLooseUnknownRecord(value: unknown, label: string): Record<string, unknown> {
  return { ...requireRecord(value, label) };
}

function readCodeConsoleReasonedValue(value: unknown, label: string): CodeConsoleReasonedValue {
  const record = requireRecord(value, label);
  return {
    label: requireString(record.label, `${label}.label`),
    value: requireString(record.value, `${label}.value`),
    reason: requireString(record.reason, `${label}.reason`),
  };
}

function readCodeConsoleTruthSource(value: unknown, label: string): CodeConsoleTruthSource {
  const record = requireRecord(value, label);
  return {
    id: requireString(record.id, `${label}.id`),
    label: requireString(record.label, `${label}.label`),
    path: record.path === null ? null : optionalString(record.path),
    display_path: record.display_path === null ? null : optionalString(record.display_path),
    kind: requireString(record.kind, `${label}.kind`),
    available: requireBoolean(record.available, `${label}.available`),
    reason: requireString(record.reason, `${label}.reason`),
  };
}

function readCodeConsoleColumnSummary(value: unknown, label: string): CodeConsoleColumnSummary {
  const record = requireRecord(value, label);
  const headerPreview = Array.isArray(record.header_preview)
    ? record.header_preview.map((item, index) => {
        if (item === null) {
          return null;
        }
        return requireString(item, `${label}.header_preview[${index}]`);
      })
    : [];
  return {
    name: requireString(record.name, `${label}.name`),
    inferred_type: requireString(record.inferred_type, `${label}.inferred_type`),
    non_empty_count: requireNumber(record.non_empty_count, `${label}.non_empty_count`),
    missing_count: requireNumber(record.missing_count, `${label}.missing_count`),
    header_preview: headerPreview,
    min_value: record.min_value === null ? null : optionalNumber(record.min_value),
    max_value: record.max_value === null ? null : optionalNumber(record.max_value),
  };
}

function readCodeConsoleInspectionSummary(
  value: unknown,
  label: string,
): CodeConsoleInspectionSummary {
  const record = requireRecord(value, label);
  return {
    warnings: requireStringArray(record.warnings ?? [], `${label}.warnings`),
    signals: requireStringArray(record.signals ?? [], `${label}.signals`),
  };
}

function readCodeConsoleRecommendationSummary(
  value: unknown,
  label: string,
): CodeConsoleRecommendationSummary {
  const record = requireRecord(value, label);
  return {
    template: requireString(record.template, `${label}.template`) as TemplateName,
    reason: requireString(record.reason, `${label}.reason`),
    size: record.size === null ? null : optionalString(record.size),
    style_preset:
      record.style_preset === null ? null : (optionalString(record.style_preset) as StylePreset | undefined),
    palette_preset:
      record.palette_preset === null
        ? null
        : (optionalString(record.palette_preset) as PalettePreset | undefined),
  };
}

function readCodeConsoleDataContext(value: unknown, label: string): CodeConsoleDataContext {
  const record = requireRecord(value, label);
  const columnSummaries = Array.isArray(record.column_summaries)
    ? record.column_summaries.map((item, index) =>
        readCodeConsoleColumnSummary(item, `${label}.column_summaries[${index}]`),
      )
    : [];
  return {
    available: requireBoolean(record.available, `${label}.available`),
    model: record.model === null ? null : optionalString(record.model),
    model_label: requireString(record.model_label, `${label}.model_label`),
    raw_row_count: requireNumber(record.raw_row_count, `${label}.raw_row_count`),
    raw_column_count: requireNumber(record.raw_column_count, `${label}.raw_column_count`),
    column_names: requireStringArray(record.column_names ?? [], `${label}.column_names`),
    normalized_columns: requireStringArray(
      record.normalized_columns ?? [],
      `${label}.normalized_columns`,
    ),
    column_summaries: columnSummaries,
    sample_rows: readStringMatrix(record.sample_rows ?? [], `${label}.sample_rows`),
    normalized_preview_rows: readStringMatrix(
      record.normalized_preview_rows ?? [],
      `${label}.normalized_preview_rows`,
    ),
    missing_summary: readNumberRecord(record.missing_summary ?? {}, `${label}.missing_summary`),
    inspection: readCodeConsoleInspectionSummary(record.inspection ?? {}, `${label}.inspection`),
    recommendation: readCodeConsoleRecommendationSummary(
      record.recommendation ?? {},
      `${label}.recommendation`,
    ),
    interpreted_summary: readLooseUnknownRecord(
      record.interpreted_summary ?? {},
      `${label}.interpreted_summary`,
    ),
    full_data_rows: requireNumber(record.full_data_rows, `${label}.full_data_rows`),
    full_data_columns: requireNumber(record.full_data_columns, `${label}.full_data_columns`),
  };
}

function readPreviewItem(value: unknown, label: string): PreviewItem {
  const record = requireRecord(value, label);
  return {
    filename: requireString(record.filename, `${label}.filename`),
    png_base64: requireString(record.png_base64, `${label}.png_base64`),
    qa: null,
  };
}

function readDataTemplateCatalogItem(value: unknown, label: string): DataTemplateCatalogItem {
  const record = requireRecord(value, label);
  return {
    chart_type: requireString(record.chart_type, `${label}.chart_type`),
    label: requireString(record.label, `${label}.label`),
    filename_stem: requireString(record.filename_stem, `${label}.filename_stem`),
    template_id: requireString(record.template_id, `${label}.template_id`),
    input_model: requireString(record.input_model, `${label}.input_model`),
    source_template_id: requireString(
      record.source_template_id,
      `${label}.source_template_id`,
    ),
    format_summary: requireString(record.format_summary, `${label}.format_summary`),
  };
}

function readDataTemplateFolderFile(value: unknown, label: string): DataTemplateFolderFile {
  const record = requireRecord(value, label);
  return {
    chart_type: requireString(record.chart_type, `${label}.chart_type`),
    label: requireString(record.label, `${label}.label`),
    template_id: requireString(record.template_id, `${label}.template_id`),
    filename: requireString(record.filename, `${label}.filename`),
    file_path: requireString(record.file_path, `${label}.file_path`),
    input_model: requireString(record.input_model, `${label}.input_model`),
    source_template_id: requireString(record.source_template_id, `${label}.source_template_id`),
    format_summary: requireString(record.format_summary, `${label}.format_summary`),
  };
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
  const visualThemes = Array.isArray(record.visual_themes)
    ? record.visual_themes.map(readWorkbenchVisualTheme)
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
    visual_themes: visualThemes,
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

export function coerceDataTemplateCatalog(value: unknown): DataTemplateCatalogResponse {
  const record = requireRecord(value, "Data template catalog response");
  return {
    templates: Array.isArray(record.templates)
      ? record.templates.map((item, index) =>
          readDataTemplateCatalogItem(item, `Data template catalog response.templates[${index}]`),
        )
      : [],
  };
}

export function coerceDataTemplateMaterializeResponse(
  value: unknown,
): DataTemplateMaterializeResponse {
  const record = requireRecord(value, "Materialize data template response");
  const variant = requireString(record.variant, "Materialize data template response.variant");
  if (variant !== "example" && variant !== "blank") {
    throw new Error("Materialize data template response.variant is missing or invalid.");
  }
  return {
    template_id: requireString(
      record.template_id,
      "Materialize data template response.template_id",
    ),
    variant,
    label: requireString(record.label, "Materialize data template response.label"),
    input_model: requireString(
      record.input_model,
      "Materialize data template response.input_model",
    ),
    typical_families: requireStringArray(
      record.typical_families ?? [],
      "Materialize data template response.typical_families",
    ),
    format_summary: requireString(
      record.format_summary,
      "Materialize data template response.format_summary",
    ),
    file_path: requireString(
      record.file_path,
      "Materialize data template response.file_path",
    ),
    filename: requireString(record.filename, "Materialize data template response.filename"),
    sheet_name: requireString(
      record.sheet_name,
      "Materialize data template response.sheet_name",
    ),
  };
}

export function coerceDataTemplateFolderResponse(value: unknown): DataTemplateFolderResponse {
  const record = requireRecord(value, "Materialize data template folder response");
  const variant = requireString(
    record.variant,
    "Materialize data template folder response.variant",
  );
  if (variant !== "example" && variant !== "blank") {
    throw new Error("Materialize data template folder response.variant is missing or invalid.");
  }
  return {
    variant,
    folder_path: requireString(
      record.folder_path,
      "Materialize data template folder response.folder_path",
    ),
    folder_name: requireString(
      record.folder_name,
      "Materialize data template folder response.folder_name",
    ),
    chart_types: requireStringArray(
      record.chart_types ?? [],
      "Materialize data template folder response.chart_types",
    ),
    files: Array.isArray(record.files)
      ? record.files.map((item, index) =>
          readDataTemplateFolderFile(
            item,
            `Materialize data template folder response.files[${index}]`,
          ),
        )
      : [],
  };
}

function readManagedStorageStatus(
  value: unknown,
  label: string,
): ManagedStorageStatus {
  const record = requireRecord(value, label);
  return {
    root_path: requireString(record.root_path, `${label}.root_path`),
    data_root: requireString(record.data_root, `${label}.data_root`),
    cache_root: requireString(record.cache_root, `${label}.cache_root`),
    example_templates_path: requireString(
      record.example_templates_path,
      `${label}.example_templates_path`,
    ),
    blank_templates_path: requireString(
      record.blank_templates_path,
      `${label}.blank_templates_path`,
    ),
    single_example_templates_path: requireString(
      record.single_example_templates_path,
      `${label}.single_example_templates_path`,
    ),
    single_blank_templates_path: requireString(
      record.single_blank_templates_path,
      `${label}.single_blank_templates_path`,
    ),
    plot_exports_path: requireString(
      record.plot_exports_path,
      `${label}.plot_exports_path`,
    ),
    code_console_runs_path: requireString(
      record.code_console_runs_path,
      `${label}.code_console_runs_path`,
    ),
    example_template_file_count: requireNumber(
      record.example_template_file_count,
      `${label}.example_template_file_count`,
    ),
    blank_template_file_count: requireNumber(
      record.blank_template_file_count,
      `${label}.blank_template_file_count`,
    ),
    single_template_file_count: requireNumber(
      record.single_template_file_count,
      `${label}.single_template_file_count`,
    ),
    plot_export_dir_count: requireNumber(
      record.plot_export_dir_count,
      `${label}.plot_export_dir_count`,
    ),
    code_console_run_dir_count: requireNumber(
      record.code_console_run_dir_count,
      `${label}.code_console_run_dir_count`,
    ),
  };
}

export function coerceManagedStorageStatus(value: unknown): ManagedStorageStatus {
  return readManagedStorageStatus(value, "Managed storage status");
}

export function coerceManagedStorageCleanupResponse(
  value: unknown,
): ManagedStorageCleanupResponse {
  const record = requireRecord(value, "Managed storage cleanup response");
  const strategy = requireString(
    record.strategy,
    "Managed storage cleanup response.strategy",
  );
  if (strategy !== "all" && strategy !== "stale") {
    throw new Error("Managed storage cleanup response.strategy is missing or invalid.");
  }
  return {
    ...readManagedStorageStatus(record, "Managed storage cleanup response"),
    strategy,
    removed_files: requireNumber(
      record.removed_files,
      "Managed storage cleanup response.removed_files",
    ),
    removed_directories: requireNumber(
      record.removed_directories,
      "Managed storage cleanup response.removed_directories",
    ),
  };
}

export function coerceCodeConsoleGenerateResponse(value: unknown): CodeConsoleGenerateResponse {
  const record = requireRecord(value, "Code Console generate response");
  const contract = requireRecord(record.contract, "Code Console generate response.contract");
  const session = requireRecord(record.session, "Code Console generate response.session");
  const defaultsPanel = requireRecord(
    record.defaults_panel,
    "Code Console generate response.defaults_panel",
  );
  const truthSources = Array.isArray(record.truth_sources)
    ? record.truth_sources.map((item, index) =>
        readCodeConsoleTruthSource(item, `Code Console generate response.truth_sources[${index}]`),
      )
    : [];
  const lockedByContract = Array.isArray(defaultsPanel.locked_by_contract)
    ? defaultsPanel.locked_by_contract.map((item, index) =>
        readCodeConsoleReasonedValue(
          item,
          `Code Console generate response.defaults_panel.locked_by_contract[${index}]`,
        ),
      )
    : [];
  const userSelectable = Array.isArray(defaultsPanel.user_selectable)
    ? defaultsPanel.user_selectable.map((item, index) =>
        readCodeConsoleReasonedValue(
          item,
          `Code Console generate response.defaults_panel.user_selectable[${index}]`,
        ),
      )
    : [];
  const derivedFromSession = Array.isArray(defaultsPanel.derived_from_session)
    ? defaultsPanel.derived_from_session.map((item, index) =>
        readCodeConsoleReasonedValue(
          item,
          `Code Console generate response.defaults_panel.derived_from_session[${index}]`,
        ),
      )
    : [];
  const lightweightBundleRecord = requireRecord(
    record.lightweight_bundle,
    "Code Console generate response.lightweight_bundle",
  );

  const contractSummary: CodeConsoleContractSummary = {
    version: requireNumber(contract.version, "Code Console generate response.contract.version"),
    sha256: requireString(contract.sha256, "Code Console generate response.contract.sha256"),
    default_style: requireString(
      contract.default_style,
      "Code Console generate response.contract.default_style",
    ) as StylePreset,
    default_palette: requireString(
      contract.default_palette,
      "Code Console generate response.contract.default_palette",
    ) as PalettePreset,
  };

  const sessionSummary: CodeConsoleSessionSummary = {
    session_id: requireString(session.session_id, "Code Console generate response.session.session_id"),
    session_source: requireString(
      session.session_source,
      "Code Console generate response.session.session_source",
    ),
    project_id: session.project_id === null ? null : optionalString(session.project_id),
    project_path: session.project_path === null ? null : optionalString(session.project_path),
    project_mode: session.project_mode === null ? null : optionalString(session.project_mode),
    input_path: session.input_path === null ? null : optionalString(session.input_path),
    input_display_path:
      session.input_display_path === null ? null : optionalString(session.input_display_path),
    input_filename: session.input_filename === null ? null : optionalString(session.input_filename),
    sheet:
      session.sheet === null
        ? null
        : typeof session.sheet === "string" || typeof session.sheet === "number"
          ? session.sheet
          : null,
    sheet_names: requireStringArray(
      session.sheet_names ?? [],
      "Code Console generate response.session.sheet_names",
    ),
    template: requireString(session.template, "Code Console generate response.session.template") as TemplateName,
    size_label: requireString(session.size_label, "Code Console generate response.session.size_label"),
    size_id: requireString(session.size_id, "Code Console generate response.session.size_id") as SizePreset,
    style_preset: requireString(
      session.style_preset,
      "Code Console generate response.session.style_preset",
    ) as StylePreset,
    palette_preset: requireString(
      session.palette_preset,
      "Code Console generate response.session.palette_preset",
    ) as PalettePreset,
    xscale: optionalScale(session.xscale) ?? "linear",
    yscale: optionalScale(session.yscale) ?? "linear",
    reverse_x: requireBoolean(
      session.reverse_x,
      "Code Console generate response.session.reverse_x",
    ),
    baseline: optionalBaseline(session.baseline) ?? "none",
    show_colorbar: requireBoolean(
      session.show_colorbar,
      "Code Console generate response.session.show_colorbar",
    ),
    intent: requireString(session.intent, "Code Console generate response.session.intent"),
    target_path: requireString(session.target_path, "Code Console generate response.session.target_path"),
  };

  const defaultsPanelSummary: CodeConsoleDefaultsPanel = {
    locked_by_contract: lockedByContract,
    user_selectable: userSelectable,
    derived_from_session: derivedFromSession,
  };

  const lightweightBundle: CodeConsoleLightweightBundle = {
    text: requireString(
      lightweightBundleRecord.text,
      "Code Console generate response.lightweight_bundle.text",
    ),
    includes_data_context: requireBoolean(
      lightweightBundleRecord.includes_data_context,
      "Code Console generate response.lightweight_bundle.includes_data_context",
    ),
    includes_inspection_summary: requireBoolean(
      lightweightBundleRecord.includes_inspection_summary,
      "Code Console generate response.lightweight_bundle.includes_inspection_summary",
    ),
    includes_project_context: requireBoolean(
      lightweightBundleRecord.includes_project_context,
      "Code Console generate response.lightweight_bundle.includes_project_context",
    ),
    includes_full_data: requireBoolean(
      lightweightBundleRecord.includes_full_data,
      "Code Console generate response.lightweight_bundle.includes_full_data",
    ),
  };

  return {
    bundle_version: requireNumber(record.bundle_version, "Code Console generate response.bundle_version"),
    generated_at: requireString(record.generated_at, "Code Console generate response.generated_at"),
    contract: contractSummary,
    session: sessionSummary,
    defaults_panel: defaultsPanelSummary,
    truth_sources: truthSources,
    data_context: readCodeConsoleDataContext(
      record.data_context ?? {},
      "Code Console generate response.data_context",
    ),
    prompt_text: requireString(record.prompt_text, "Code Console generate response.prompt_text"),
    scaffold_text: requireString(
      record.scaffold_text,
      "Code Console generate response.scaffold_text",
    ),
    lightweight_bundle: lightweightBundle,
  };
}

export function coerceCodeConsoleExportResponse(value: unknown): CodeConsoleExportResponse {
  const record = requireRecord(value, "Code Console export response");
  const truthSources = Array.isArray(record.truth_sources)
    ? record.truth_sources.map((item, index) =>
        readCodeConsoleTruthSource(item, `Code Console export response.truth_sources[${index}]`),
      )
    : [];
  return {
    bundle_dir: requireString(record.bundle_dir, "Code Console export response.bundle_dir"),
    zip_path: requireString(record.zip_path, "Code Console export response.zip_path"),
    manifest_path: requireString(
      record.manifest_path,
      "Code Console export response.manifest_path",
    ),
    exported_files: requireStringArray(
      record.exported_files ?? [],
      "Code Console export response.exported_files",
    ),
    includes_full_data: requireBoolean(
      record.includes_full_data,
      "Code Console export response.includes_full_data",
    ),
    truth_sources: truthSources,
  };
}

export function coerceCodeConsoleRunResponse(value: unknown): CodeConsoleRunResponse {
  const record = requireRecord(value, "Code Console run response");
  const generatedFiles = Array.isArray(record.generated_files)
    ? record.generated_files.map((item, index): CodeConsoleGeneratedFile => {
        const file = requireRecord(item, `Code Console run response.generated_files[${index}]`);
        return {
          path: requireString(file.path, `Code Console run response.generated_files[${index}].path`),
          filename: requireString(
            file.filename,
            `Code Console run response.generated_files[${index}].filename`,
          ),
          kind: requireString(file.kind, `Code Console run response.generated_files[${index}].kind`),
        };
      })
    : [];
  const previews = Array.isArray(record.previews)
    ? record.previews.map((item, index) =>
        readPreviewItem(item, `Code Console run response.previews[${index}]`),
      )
    : [];
  return {
    generated_at: requireString(record.generated_at, "Code Console run response.generated_at"),
    output_dir: requireString(record.output_dir, "Code Console run response.output_dir"),
    stdout: typeof record.stdout === "string" ? record.stdout : "",
    stderr: typeof record.stderr === "string" ? record.stderr : "",
    exit_code: requireNumber(record.exit_code, "Code Console run response.exit_code"),
    timed_out: requireBoolean(record.timed_out, "Code Console run response.timed_out"),
    duration_ms: requireNumber(record.duration_ms, "Code Console run response.duration_ms"),
    generated_files: generatedFiles,
    previews,
  };
}
