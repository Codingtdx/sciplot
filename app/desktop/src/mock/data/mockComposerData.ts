export const mockComposerHeader = {
  compositionName: "Barrier study multi-panel layout",
  summary:
    "Canvas-first composition for a publication sheet that mixes graph PDFs, SEM imagery, and layered callouts.",
  status: "Canvas in review",
  exportNote: "Single-page PDF · OCG layers preserved",
};

export const mockComposerStats = [
  { label: "Regions", value: "5 active" },
  { label: "Graphs", value: "3 linked" },
  { label: "Assets", value: "2 placed" },
  { label: "Texts", value: "4 annotations" },
];

export const mockComposerAssets = [
  {
    type: "Graph",
    name: "Dual modulus graph",
    meta: "Graph",
  },
  {
    type: "Graph",
    name: "Strength box",
    meta: "Graph",
  },
  {
    type: "Graph",
    name: "Elongation bar",
    meta: "Graph",
  },
  {
    type: "Image",
    name: "SEM detail",
    meta: "Asset",
  },
  {
    type: "Text",
    name: "Figure label",
    meta: "Text",
  },
];

export const mockComposerLayers = [
  "Graph",
  "Panel",
  "SEM asset",
  "Callout",
  "Figure 3",
];

export const mockComposerReviewNotes = [
  "Grid aligned",
  "Asset secondary",
  "Labels separate",
];

export const mockComposerExportBundle = [
  "Single-page PDF",
  "Review PNG",
  "Layer manifest",
];
