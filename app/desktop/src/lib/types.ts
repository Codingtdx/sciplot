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
