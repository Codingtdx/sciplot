export type TemplateName = string;

export type SizePreset = string;

export type PalettePreset = string;

export type StylePreset = string;

export type WizardStep =
  | "file"
  | "sheet"
  | "inspect"
  | "template"
  | "options"
  | "preflight"
  | "export";

export type PlotStage = "import" | "sheet" | "type" | "tune" | "review" | "export";

export type RequestActivity = "idle" | "scheduled" | "running" | "ready" | "error";

export type WorkbenchWorkspace =
  | "launchpad"
  | "plot"
  | "tensile"
  | "composer"
  | "code"
  | "settings";
export type WorkbenchRoute =
  | "/"
  | "/plot/import"
  | "/plot/sheet"
  | "/plot/type"
  | "/plot/tune"
  | "/plot/review"
  | "/plot/export"
  | "/tensile"
  | "/composer"
  | "/code-console"
  | "/settings";
export type PdfImportMode = "graph" | "asset";
export type AppearanceMode = "system" | "light" | "dark";

export type ThemePreference = AppearanceMode;

export type ResolvedAppearance = "light" | "dark";

export type ThemePresetId = string;

export type ThemePresetPreview = {
  background: string;
  surface: string;
  glow: string;
  chip: string;
};

export type ThemePreset = {
  id: ThemePresetId;
  name: string;
  appearance: ResolvedAppearance;
  accent: string;
  description: string;
  preview: ThemePresetPreview;
};

export type PreviewItem = {
  filename: string;
  png_base64: string;
  qa?: QAReport | null;
};

export type QAIssue = {
  id: string;
  severity: string;
  metric_value?: number | string | null;
  target?: number | string | null;
  message: string;
};

export type QAReport = {
  score: number;
  grade: "excellent" | "solid" | "needs_cleanup";
  issues: QAIssue[];
  autofixes_applied: string[];
};

export type SubmissionCheck = {
  id: string;
  status: "pass" | "advisory" | "warning" | "critical" | "pending" | string;
  message: string;
  metric_value?: number | string | null;
  target?: number | string | null;
  source?: string | null;
};

export type SubmissionReport = {
  context: string;
  readiness: "ready" | "review" | "blocked" | string;
  summary: string;
  template?: string | null;
  style_preset?: StylePreset | null;
  palette_preset?: PalettePreset | null;
  output_count: number;
  output_filenames: string[];
  blockers: string[];
  checks: SubmissionCheck[];
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
  style_preset?: StylePreset;
  palette_preset?: PalettePreset;
  use_sidecar?: boolean;
};

export type TemplateRecommendation = {
  template_id: TemplateName;
  score: number;
  why_hard_match: string[];
  why_soft_prior: string[];
  inferred_mapping: Record<string, string>;
  optional_enhancements: string[];
  preview_config_summary: Record<string, unknown>;
};

export type InputInspection = {
  model: string;
  model_label: string;
  recommendation: Recommendation;
  recommendations?: TemplateRecommendation[];
  warnings: string[];
  signals: string[];
};

export type PreflightResult = {
  template: TemplateName;
  warnings: string[];
  errors: string[];
  output_filenames: string[];
  submission_report?: SubmissionReport | null;
};

export type RenderOptionsPayload = {
  size?: SizePreset;
  xscale?: "linear" | "log";
  yscale?: "linear" | "log";
  reverse_x?: boolean;
  baseline?: "none" | "linear_endpoints";
  show_colorbar?: boolean;
  style_preset?: StylePreset;
  palette_preset?: PalettePreset;
  use_sidecar?: boolean | null;
  visual_theme_id?: string | null;
};

export type EditableRenderOption = keyof RenderOptionsPayload;

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
  submission_report?: SubmissionReport | null;
};

export type ExportResponse = {
  outputs: string[];
  output_dir: string;
  preview_outputs?: string[];
  artifact_paths?: string[];
  manifest_path?: string | null;
  submission_report?: SubmissionReport | null;
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

export type TensileWorkbookSummary = {
  workbook_path: string;
  label: string;
  sheet_names: string[];
  sample_count: number;
  representative_filename: string;
  metrics: TensileMetricSummary[];
};

export type TensileComparisonSource = TensileWorkbookSummary;

export type TensileComparisonExportResponse = {
  bundle_dir: string;
  comparison_workbook_path: string;
  labels: string[];
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
  hidden?: boolean;
  label?: string | null;
  kind: "graph" | "asset";
  z_index: number;
  group_id?: string | null;
  region_id?: string | null;
  slot_id?: string | null;
  crop_rect: ComposerCropRect;
};

export type ComposerText = {
  id: string;
  text: string;
  x_mm: number;
  y_mm: number;
  font_size_pt: number;
  align: "left" | "center" | "right";
  z_index: number;
  locked?: boolean;
  hidden?: boolean;
  group_id?: string | null;
  region_id?: string | null;
  slot_id?: string | null;
};

export type ComposerCropRect = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export type ComposerLayoutGrid = {
  columns: number;
  rows: number;
  cell_width_mm: number;
  cell_height_mm: number;
  frame_x_mm: number;
  frame_y_mm: number;
  frame_width_mm: number;
  frame_height_mm: number;
};

export type ComposerRegion = {
  id: string;
  kind: "graph" | "free";
  col: number;
  row: number;
  col_span: number;
  row_span: number;
  label?: string | null;
  locked?: boolean;
  slot_kind?: "structure" | null;
};

export type ComposerProject = {
  version: number;
  mode: "composer";
  canvas_width_mm: number;
  canvas_height_mm: number;
  grid_mm: number;
  layout_grid: ComposerLayoutGrid;
  regions: ComposerRegion[];
  panels: ComposerPanel[];
  texts: ComposerText[];
  auto_labels: boolean;
};

export type ComposerSuggestedPatch = {
  kind: "panel" | "text";
  id: string;
  patch: Record<string, unknown>;
};

export type ComposerPreviewResponse = {
  valid: boolean;
  validation_error: string | null;
  png_base64: string;
  qa?: QAReport | null;
  submission_report?: SubmissionReport | null;
  suggested_project_patch?: ComposerSuggestedPatch[];
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
  appearance_mode: AppearanceMode;
  theme_preset_id: ThemePresetId;
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
  id: StylePreset;
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

export type WorkbenchVisualTheme = {
  id: string;
  label: string;
  description: string;
};

export type WorkbenchTemplate = {
  id: TemplateName;
  label: string;
  description: string;
  category: string;
  default_size: SizePreset;
  allowed_sizes: SizePreset[];
  editable_options: EditableRenderOption[];
  default_options: RenderOptionsPayload & { size?: SizePreset };
  available_styles: StylePreset[];
  available_palettes: PalettePreset[];
};

export type WorkbenchMeta = {
  version: number;
  defaults: {
    style_preset: StylePreset;
    palette_preset: PalettePreset;
  };
  global_frame: GlobalFrame;
  sizes: WorkbenchSize[];
  styles: WorkbenchStyle[];
  palettes: WorkbenchPalette[];
  visual_themes: WorkbenchVisualTheme[];
  templates: WorkbenchTemplate[];
  template_ids: TemplateName[];
  size_ids: SizePreset[];
  palette_preset_ids: PalettePreset[];
  default_style: StylePreset;
  default_palette: PalettePreset;
};

export type DataTemplateVariant = "example" | "blank";

export type DataTemplateCatalogItem = {
  chart_type: string;
  label: string;
  filename_stem: string;
  template_id: string;
  input_model: string;
  source_template_id: string;
  format_summary: string;
};

export type DataTemplateCatalogResponse = {
  templates: DataTemplateCatalogItem[];
};

export type DataTemplateFolderFile = {
  chart_type: string;
  label: string;
  template_id: string;
  filename: string;
  file_path: string;
  input_model: string;
  source_template_id: string;
  format_summary: string;
};

export type DataTemplateMaterializeResponse = {
  template_id: string;
  variant: DataTemplateVariant;
  label: string;
  input_model: string;
  typical_families: string[];
  format_summary: string;
  file_path: string;
  filename: string;
  sheet_name: string;
};

export type DataTemplateFolderResponse = {
  variant: DataTemplateVariant;
  folder_path: string;
  folder_name: string;
  chart_types: string[];
  files: DataTemplateFolderFile[];
};

export type ManagedStorageStatus = {
  root_path: string;
  data_root: string;
  cache_root: string;
  example_templates_path: string;
  blank_templates_path: string;
  single_example_templates_path: string;
  single_blank_templates_path: string;
  plot_exports_path: string;
  code_console_runs_path: string;
  example_template_file_count: number;
  blank_template_file_count: number;
  single_template_file_count: number;
  plot_export_dir_count: number;
  code_console_run_dir_count: number;
};

export type ManagedStorageCleanupResponse = ManagedStorageStatus & {
  strategy: "all" | "stale";
  removed_files: number;
  removed_directories: number;
};

export type PlotContract = {
  version: number;
  defaults: {
    style_preset: StylePreset;
    palette_preset: PalettePreset;
  };
  global_frame: GlobalFrame;
  size_presets: Record<string, { label: string; width_mm: number; height_mm: number }>;
  special_layouts: Record<string, Record<string, number | string | boolean>>;
  qa_profiles: Record<string, Record<string, number | string | boolean | string[]>>;
  styles: Record<string, Record<string, unknown>>;
  palettes: Record<string, Record<string, unknown>>;
  templates: Record<string, Record<string, unknown>>;
  validation_rules: Record<string, Record<string, unknown>>;
};

export type CodeConsoleReasonedValue = {
  label: string;
  value: string;
  reason: string;
};

export type CodeConsoleTruthSource = {
  id: string;
  label: string;
  path?: string | null;
  display_path?: string | null;
  kind: string;
  available: boolean;
  reason: string;
};

export type CodeConsoleContractSummary = {
  version: number;
  sha256: string;
  default_style: StylePreset;
  default_palette: PalettePreset;
};

export type CodeConsoleSessionSummary = {
  session_id: string;
  session_source: string;
  project_id?: string | null;
  project_path?: string | null;
  project_mode?: string | null;
  input_path?: string | null;
  input_display_path?: string | null;
  input_filename?: string | null;
  sheet?: string | number | null;
  sheet_names: string[];
  template: TemplateName;
  size_label: string;
  size_id: SizePreset;
  style_preset: StylePreset;
  palette_preset: PalettePreset;
  xscale: "linear" | "log";
  yscale: "linear" | "log";
  reverse_x: boolean;
  baseline: "none" | "linear_endpoints";
  show_colorbar: boolean;
  intent: string;
  target_path: string;
};

export type CodeConsoleColumnSummary = {
  name: string;
  inferred_type: string;
  non_empty_count: number;
  missing_count: number;
  header_preview: Array<string | null>;
  min_value?: number | null;
  max_value?: number | null;
};

export type CodeConsoleInspectionSummary = {
  warnings: string[];
  signals: string[];
};

export type CodeConsoleRecommendationSummary = {
  template: TemplateName;
  reason: string;
  size?: SizePreset | null;
  style_preset?: StylePreset | null;
  palette_preset?: PalettePreset | null;
};

export type CodeConsoleDataContext = {
  available: boolean;
  model?: string | null;
  model_label: string;
  raw_row_count: number;
  raw_column_count: number;
  column_names: string[];
  normalized_columns: string[];
  column_summaries: CodeConsoleColumnSummary[];
  sample_rows: unknown[][];
  normalized_preview_rows: unknown[][];
  missing_summary: Record<string, number>;
  inspection: CodeConsoleInspectionSummary;
  recommendation: CodeConsoleRecommendationSummary;
  interpreted_summary: Record<string, unknown>;
  full_data_rows: number;
  full_data_columns: number;
};

export type CodeConsoleDefaultsPanel = {
  locked_by_contract: CodeConsoleReasonedValue[];
  user_selectable: CodeConsoleReasonedValue[];
  derived_from_session: CodeConsoleReasonedValue[];
};

export type CodeConsoleLightweightBundle = {
  text: string;
  includes_data_context: boolean;
  includes_inspection_summary: boolean;
  includes_project_context: boolean;
  includes_full_data: boolean;
};

export type CodeConsoleGenerateResponse = {
  bundle_version: number;
  generated_at: string;
  contract: CodeConsoleContractSummary;
  session: CodeConsoleSessionSummary;
  defaults_panel: CodeConsoleDefaultsPanel;
  truth_sources: CodeConsoleTruthSource[];
  data_context: CodeConsoleDataContext;
  prompt_text: string;
  scaffold_text: string;
  lightweight_bundle: CodeConsoleLightweightBundle;
};

export type CodeConsoleExportResponse = {
  bundle_dir: string;
  zip_path: string;
  manifest_path: string;
  exported_files: string[];
  includes_full_data: boolean;
  truth_sources: CodeConsoleTruthSource[];
};

export type CodeConsoleGeneratedFile = {
  path: string;
  filename: string;
  kind: string;
};

export type CodeConsoleRunResponse = {
  generated_at: string;
  output_dir: string;
  stdout: string;
  stderr: string;
  exit_code: number;
  timed_out: boolean;
  duration_ms: number;
  generated_files: CodeConsoleGeneratedFile[];
  previews: PreviewItem[];
};
