import { mockRheologyBand, mockRheologySeries } from "./mockChartData";

export const mockPlotRefineData = {
  figureLabel: "Point + line · frequency_sweep_hydrogel_panel.xlsx",
  templateLabel: "Point + line",
  datasetSummary: "Frequency sweep · Rheology_Master · 384 rows",
  previewModes: ["Figure", "Legend crop", "Small panel"],
  exportSummary: {
    outputPath: "/Users/design/mock-exports/frequency_sweep_hydrogel_panel",
    preset: "Journal 60 x 55 mm",
    bundleNote: "Preview PNG, PDF, normalized options, inspection summary",
  },
  inspector: {
    size: "60 x 55 mm",
    style: "Editorial clean",
    palette: "Ocean lab",
    xScale: "Log",
    yScale: "Linear",
    markerMode: "Every point",
    legendPlacement: "Upper right",
  },
  readinessChecks: [
    "Axis labels align with small-panel profile",
    "Legend width stays under 32 mm",
    "No clipped markers at right edge",
    "Preview and export bundle settings are in sync",
  ],
  preview: {
    title: "Figure preview",
    note:
      "The preview dominates the workspace and the export controls stay attached below it so the whole screen reads like a figure workstation.",
    series: mockRheologySeries,
    band: mockRheologyBand,
  },
  filmstrip: [
    { label: "Figure", mode: "point-line" as const },
    { label: "Curve only", mode: "curve" as const },
    { label: "Replicate band", mode: "band" as const },
  ],
};
