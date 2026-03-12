export type TemplateName =
  | "curve"
  | "point_line"
  | "stacked_curve"
  | "segmented_stacked_curve"
  | "bar"
  | "box"
  | "violin"
  | "scatter"
  | "heatmap";

export type SizePreset = "60x55" | "120x55" | "60x110";

export type PalettePreset = "colorblind_safe" | "deep" | "muted" | "mono";

export type WizardStep =
  | "file"
  | "sheet"
  | "inspect"
  | "template"
  | "options"
  | "preflight"
  | "export";

export type WorkbenchScreen = "wizard" | "composer" | "projects" | "settings";
export type PdfImportMode = "graph" | "asset";

export type PreviewItem = {
  filename: string;
  png_base64: string;
};

export type Recommendation = {
  template: TemplateName;
  reason: string;
  size?: SizePreset;
  xscale?: "linear" | "log";
  yscale?: "linear" | "log";
  reverse_x?: boolean;
  baseline?: "none" | "linear_endpoints";
  show_colorbar?: boolean;
  use_sidecar?: boolean;
};

export type InputInspection = {
  model: string;
  model_label: string;
  recommendation: Recommendation;
  warnings: string[];
  signals: string[];
};

export type PreflightResult = {
  template: TemplateName;
  warnings: string[];
  errors: string[];
  output_filenames: string[];
};

export type RenderOptionsPayload = {
  size?: SizePreset;
  xscale?: "linear" | "log";
  yscale?: "linear" | "log";
  reverse_x?: boolean;
  baseline?: "none" | "linear_endpoints";
  show_colorbar?: boolean;
  palette_preset?: PalettePreset;
  use_sidecar?: boolean | null;
};

export type InspectResponse = {
  input_path: string;
  sheet: string | number;
  sheet_names: string[];
  inspection: InputInspection;
};

export type PreflightResponse = {
  input_path: string;
  template: TemplateName;
  sheet: string | number;
  options: RenderOptionsPayload;
  preflight: PreflightResult;
};

export type RenderPreviewResponse = {
  template: TemplateName;
  sheet: string | number;
  previews: PreviewItem[];
};

export type ExportResponse = {
  outputs: string[];
};

export type TensileMetricSummary = {
  label: string;
  unit: string;
  mean: number | null;
  std: number | null;
};

export type TensileReplicateResponse = {
  output_path: string;
  group_name: string;
  preferred_sheet: string;
  sheet_names: string[];
  sample_count: number;
  representative_filename: string;
  metrics: TensileMetricSummary[];
  warnings: string[];
};

export type ComposerPanel = {
  id: string;
  file_path: string;
  page_index: number;
  x_mm: number;
  y_mm: number;
  w_mm: number;
  h_mm: number;
  locked?: boolean;
  label?: string | null;
  kind: "graph" | "asset";
};

export type ComposerText = {
  id: string;
  text: string;
  x_mm: number;
  y_mm: number;
  font_size_pt: number;
  align: "left" | "center" | "right";
};

export type ComposerProject = {
  version: number;
  mode: "composer";
  canvas_width_mm: number;
  canvas_height_mm: number;
  grid_mm: number;
  panels: ComposerPanel[];
  texts: ComposerText[];
  auto_labels: boolean;
};

export type WizardProject = {
  version: number;
  mode: "wizard";
  wizard: {
    input_path: string;
    sheet: string | number;
    template: TemplateName | null;
    options: RenderOptionsPayload;
    outputs: string[];
  };
};

export type RecentEntryKind = "data" | "project";

export type RecentProjectEntry = {
  id: string;
  mode: "wizard" | "composer";
  kind: RecentEntryKind;
  path: string;
  title: string;
  detail: string;
  updated_at: string;
};

export type WorkbenchSettings = {
  auto_status_poll: boolean;
  remember_last_screen: boolean;
};

export type GlobalFrame = {
  panel_width_mm: number;
  panel_height_mm: number;
  left_margin_mm: number;
  right_margin_mm: number;
  bottom_margin_mm: number;
  top_margin_mm: number;
};

export type WorkbenchSize = {
  id: SizePreset;
  label: string;
  width_mm: number;
  height_mm: number;
};

export type WorkbenchStyle = {
  id: string;
  label: string;
  public: boolean;
  description: string;
  hard_constraints: boolean;
  preset_note: string;
};

export type WorkbenchPalette = {
  id: PalettePreset | string;
  label: string;
  public: boolean;
  description: string;
  swatches: string[];
};

export type WorkbenchTemplate = {
  id: TemplateName;
  label: string;
  description: string;
  category: string;
  default_size: SizePreset;
  allowed_sizes: SizePreset[];
  editable_options: Array<keyof RenderOptionsPayload | "size">;
  default_options: RenderOptionsPayload & { size?: SizePreset };
  available_styles: string[];
  available_palettes: Array<PalettePreset | string>;
};

export type WorkbenchMeta = {
  version: number;
  defaults: {
    style_preset: string;
    palette_preset: PalettePreset | string;
  };
  global_frame: GlobalFrame;
  sizes: WorkbenchSize[];
  styles: WorkbenchStyle[];
  palettes: WorkbenchPalette[];
  templates: WorkbenchTemplate[];
  template_ids: TemplateName[];
  size_ids: SizePreset[];
  palette_preset_ids: Array<PalettePreset | string>;
  default_style: string;
  default_palette: PalettePreset | string;
};

export type PlotContract = {
  version: number;
  defaults: {
    style_preset: string;
    palette_preset: string;
  };
  global_frame: GlobalFrame;
  size_presets: Record<string, { label: string; width_mm: number; height_mm: number }>;
  special_layouts: Record<string, Record<string, number | string | boolean>>;
  styles: Record<string, Record<string, unknown>>;
  palettes: Record<string, Record<string, unknown>>;
  templates: Record<string, Record<string, unknown>>;
  validation_rules: Record<string, Record<string, unknown>>;
};
