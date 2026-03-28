export type MockTemplateOption = {
  id: string;
  name: string;
  badge: string;
  confidence: string;
  summary: string;
  rationale: string[];
  metrics: { label: string; value: string }[];
};

export const mockTemplateHeader = {
  datasetName: "PVA-aging-frequency-sweep.xlsx",
  sheetName: "Sweep_Data",
  recommendationSummary:
    "A dual-modulus sweep view best preserves the relationship between G', G'' and frequency while keeping the figure dense and readable.",
};

export const mockTemplateOptions: MockTemplateOption[] = [
  {
    id: "twin-modulus-curve",
    name: "Twin-modulus curve",
    badge: "Recommended",
    confidence: "0.92 match",
    summary: "Two synchronized curves with restrained labeling and a preview-first legend.",
    rationale: [
      "Supports positive logarithmic x values without visual crowding.",
      "Keeps both G' and G'' legible as primary analytical signals.",
      "Matches the compact single-figure density expected for rheology sweeps.",
    ],
    metrics: [
      { label: "Series", value: "2 visible" },
      { label: "Legend", value: "Inline" },
      { label: "Scale", value: "log x" },
    ],
  },
  {
    id: "point-line-comparison",
    name: "Point-line comparison",
    badge: "Alternate",
    confidence: "0.81 match",
    summary: "Marker-led comparison for datasets where replicate identity matters more strongly.",
    rationale: [
      "Good for quick visual validation of per-point measurement spacing.",
      "Slightly denser than the recommended curve view.",
    ],
    metrics: [
      { label: "Markers", value: "Visible" },
      { label: "Legend", value: "Compact" },
      { label: "Scale", value: "log x" },
    ],
  },
  {
    id: "band-summary",
    name: "Band summary curve",
    badge: "Alternate",
    confidence: "0.74 match",
    summary: "Highlights mean behavior with a confidence band and simplified annotations.",
    rationale: [
      "Better for narrative summary than raw point inspection.",
      "Uses more visual area for uncertainty than direct trace comparison.",
    ],
    metrics: [
      { label: "Band", value: "One shaded" },
      { label: "Legend", value: "Minimal" },
      { label: "Scale", value: "log x" },
    ],
  },
  {
    id: "scatter-sweep",
    name: "Scatter sweep",
    badge: "Alternate",
    confidence: "0.68 match",
    summary: "A looser analytical view that emphasizes raw measurement distribution.",
    rationale: [
      "Useful when validating outliers and spacing before presentation polish.",
      "Less publication-like than the top two recommendations.",
    ],
    metrics: [
      { label: "Markers", value: "High" },
      { label: "Legend", value: "Separated" },
      { label: "Scale", value: "log x" },
    ],
  },
];

