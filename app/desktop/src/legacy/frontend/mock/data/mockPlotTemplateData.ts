import { mockRheologyBand, mockRheologySeries } from "./mockChartData";

export const mockPlotTemplateData = {
  datasetLabel: "frequency_sweep_hydrogel_panel.xlsx · Rheology_Master",
  compatibilitySummary: "Frequency sweep bundle with consistent formulation groups and clear storage/loss modulus separation.",
  previewModes: ["Recommended view", "Legend density", "Small panel check"],
  featured: {
    label: "Point + line",
    fit: "97% fit",
    category: "Rheology bundle",
    thumbnail: "point-line" as const,
    title: "Best match for publication-ready frequency sweep comparison.",
    copy:
      "Markers preserve replicate cadence while the line keeps the sweep trend readable at manuscript scale. The layout also keeps the legend compact enough for 60 x 55 mm panels.",
    bullets: [
      "Log-x axis reads cleanly from 0.1 to 64 Hz",
      "Legend fits three formulations without wrapping",
      "Matches the dominant storage modulus story first",
    ],
  },
  alternates: [
    {
      label: "Curve",
      fit: "91% fit",
      category: "Dense overlay",
      thumbnail: "curve" as const,
      reason: "Useful when marker noise feels too busy and you want a more editorial sweep.",
    },
    {
      label: "Replicate band",
      fit: "86% fit",
      category: "Variation emphasis",
      thumbnail: "band" as const,
      reason: "Highlights spread well, but uses more visual weight than the current story needs.",
    },
    {
      label: "Scatter fit",
      fit: "72% fit",
      category: "Analytical view",
      thumbnail: "scatter" as const,
      reason: "Appropriate for regression review, but weaker for full sweep comparison in a figure panel.",
    },
  ],
  unavailable: ["Heatmap", "Grouped bar", "Violin", "Annotated heatmap"],
  preview: {
    title: "Recommended panel preview",
    caption:
      "The main preview stays large enough to judge axis rhythm, marker density, and legend balance before entering Figure Lab.",
    insightChips: [
      "Legend stays within one row",
      "Marker cadence every sample point",
      "Outer padding stays tight on the y axis",
    ],
    series: mockRheologySeries,
    band: mockRheologyBand,
  },
};
