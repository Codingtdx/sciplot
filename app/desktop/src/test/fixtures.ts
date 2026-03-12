import type { PlotContract, WorkbenchMeta } from "../lib/types";

export const TEST_META: WorkbenchMeta = {
  version: 1,
  defaults: {
    style_preset: "default",
    palette_preset: "colorblind_safe",
  },
  global_frame: {
    panel_width_mm: 60,
    panel_height_mm: 55,
    left_margin_mm: 14,
    right_margin_mm: 4.5,
    bottom_margin_mm: 11,
    top_margin_mm: 5.5,
  },
  sizes: [
    { id: "60x55", label: "60 x 55 mm", width_mm: 60, height_mm: 55 },
    { id: "120x55", label: "120 x 55 mm", width_mm: 120, height_mm: 55 },
    { id: "60x110", label: "60 x 110 mm", width_mm: 60, height_mm: 110 },
  ],
  styles: [
    {
      id: "default",
      label: "Default",
      public: true,
      description: "Default",
      hard_constraints: false,
      preset_note: "Default",
    },
    {
      id: "nature",
      label: "Nature",
      public: true,
      description: "Nature",
      hard_constraints: true,
      preset_note: "Nature",
    },
  ],
  palettes: [
    {
      id: "colorblind_safe",
      label: "Colorblind Safe",
      public: true,
      description: "Safe",
      swatches: ["#0173b2"],
    },
    {
      id: "mono",
      label: "Mono",
      public: true,
      description: "Mono",
      swatches: ["#111827"],
    },
  ],
  templates: [
    {
      id: "curve",
      label: "曲线",
      description: "普通单图曲线。",
      category: "single_panel",
      default_size: "60x55",
      allowed_sizes: ["60x55", "120x55"],
      editable_options: ["size", "xscale", "yscale", "reverse_x", "palette_preset"],
      default_options: {
        size: "60x55",
        xscale: "linear",
        yscale: "linear",
        reverse_x: false,
      },
      available_styles: ["default", "nature"],
      available_palettes: ["colorblind_safe", "mono"],
    },
    {
      id: "heatmap",
      label: "热图",
      description: "热图",
      category: "heatmap",
      default_size: "60x55",
      allowed_sizes: ["60x55"],
      editable_options: ["size", "show_colorbar", "palette_preset"],
      default_options: {
        size: "60x55",
        show_colorbar: true,
      },
      available_styles: ["default", "nature"],
      available_palettes: ["colorblind_safe", "mono"],
    },
  ],
  template_ids: ["curve", "heatmap"],
  size_ids: ["60x55", "120x55", "60x110"],
  palette_preset_ids: ["colorblind_safe", "mono"],
  default_style: "default",
  default_palette: "colorblind_safe",
};

export const TEST_CONTRACT: PlotContract = {
  version: 1,
  defaults: {
    style_preset: "default",
    palette_preset: "colorblind_safe",
  },
  global_frame: TEST_META.global_frame,
  size_presets: {
    "60x55": { label: "60 x 55 mm", width_mm: 60, height_mm: 55 },
  },
  special_layouts: {
    wide_nmr: {
      width_mm: 60,
      total_height_mm: 110,
      structure_reserved_mm: 18,
      spectrum_height_mm: 92,
    },
  },
  styles: {},
  palettes: {},
  templates: {},
  validation_rules: {
    single_panel_axis_frame: { severity: "error" },
    wide_nmr_horizontal_alignment: { severity: "error" },
  },
};
