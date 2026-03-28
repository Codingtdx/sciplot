export type MockSeriesPoint = {
  x: number;
  y: number;
};

export type MockSeries = {
  id: string;
  label: string;
  color: string;
  points: MockSeriesPoint[];
};

export const mockRefineHeader = {
  figureName: "freq_sweep_dual_modulus_curve",
  datasetName: "PVA-aging-frequency-sweep.xlsx",
  status: "Preview ready",
  lastUpdated: "Updated 12 seconds ago",
};

export const mockRefineSeries: MockSeries[] = [
  {
    id: "storage",
    label: "Storage modulus G'",
    color: "#1565d8",
    points: [
      { x: 0.1, y: 0.82 },
      { x: 0.32, y: 1.18 },
      { x: 1, y: 1.92 },
      { x: 3.2, y: 2.88 },
      { x: 10, y: 3.71 },
      { x: 32, y: 4.52 },
      { x: 100, y: 5.08 },
    ],
  },
  {
    id: "loss",
    label: "Loss modulus G''",
    color: "#62b8f6",
    points: [
      { x: 0.1, y: 0.14 },
      { x: 0.32, y: 0.21 },
      { x: 1, y: 0.34 },
      { x: 3.2, y: 0.47 },
      { x: 10, y: 0.62 },
      { x: 32, y: 0.76 },
      { x: 100, y: 0.92 },
    ],
  },
];

export const mockRefineInspectorSections = [
  {
    title: "Style",
    items: [
      { label: "Preset", value: "Journal Calm" },
      { label: "Palette", value: "Aqua Graphite" },
      { label: "Canvas size", value: "120 x 55 mm" },
    ],
  },
  {
    title: "Axes",
    items: [
      { label: "x scale", value: "Logarithmic" },
      { label: "y scale", value: "Linear" },
      { label: "Legend", value: "Inside upper right" },
    ],
  },
  {
    title: "Labels",
    items: [
      { label: "x label", value: "Frequency (Hz)" },
      { label: "y label", value: "Modulus (MPa)" },
      { label: "Annotation", value: "Aging shifts G' upward across the sweep." },
    ],
  },
];

export const mockRefineExportFormats = ["PDF", "SVG", "PNG"];

