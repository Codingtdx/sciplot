export const mockStartData = {
  entry: {
    title: "Open a workbook and land in a dense figure workspace.",
    description:
      "This mock pass keeps the entry compact: one primary launch area, a realistic dataset glimpse, and enough context to feel like a desktop tool instead of a dashboard.",
    sourceBadge: "Local file source",
    defaultFolder: "/Users/design/research/hydrogels/q2-review",
    supportedTypes: [".xlsx workbook", ".csv dataset", ".tsv assay export"],
    quickActions: ["Open dataset", "Reveal sample bundle"],
    datasetPeekColumns: ["Frequency (Hz)", "G' (Pa)", "G'' (Pa)", "tanδ"],
    datasetPeekRows: [
      ["0.10", "1450", "210", "0.145"],
      ["1.00", "2140", "318", "0.149"],
      ["8.00", "3980", "577", "0.145"],
      ["64.0", "6250", "924", "0.148"],
    ],
    readyWhenOpened: [
      "Sheet routing defaults to Rheology_Master",
      "Dataset preview starts with 14 visible rows",
      "Template Studio opens with a point-line recommendation first",
    ],
  },
  recentFiles: [
    {
      title: "frequency_sweep_hydrogel_panel.xlsx",
      subtitle: "Frequency sweep · Rheology_Master · 18 columns",
      meta: "12 min ago",
      path: "/Users/design/research/hydrogels/frequency_sweep_hydrogel_panel.xlsx",
    },
    {
      title: "stress_relaxation_sigma_bundle.xlsx",
      subtitle: "Stress relaxation · Sigma_Normalized · 16 columns",
      meta: "48 min ago",
      path: "/Users/design/research/hydrogels/stress_relaxation_sigma_bundle.xlsx",
    },
    {
      title: "tensile_replicates_week7.csv",
      subtitle: "Replicate table · Strength/Modulus · 9 columns",
      meta: "Yesterday",
      path: "/Users/design/research/mechanics/tensile_replicates_week7.csv",
    },
    {
      title: "thermal_sweep_gelma_v3.xlsx",
      subtitle: "Temperature sweep · CoolingRamp_01 · 15 columns",
      meta: "Yesterday",
      path: "/Users/design/research/hydrogels/thermal_sweep_gelma_v3.xlsx",
    },
    {
      title: "annotated_heatmap_cell_viability.csv",
      subtitle: "Heatmap table · Replicate merged map · 6 columns",
      meta: "2 days ago",
      path: "/Users/design/research/cell/annotated_heatmap_cell_viability.csv",
    },
  ],
};
