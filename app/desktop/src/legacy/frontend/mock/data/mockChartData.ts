export type MockPoint = {
  x: number;
  y: number;
};

export type MockLineSeries = {
  label: string;
  color: string;
  points: MockPoint[];
  dashed?: boolean;
  markers?: boolean;
};

export type MockBand = {
  color: string;
  lower: MockPoint[];
  upper: MockPoint[];
};

export type MockScatterSeries = {
  label: string;
  color: string;
  points: MockPoint[];
  trend: MockPoint[];
};

const frequencyAxis = [0.1, 0.25, 0.5, 1, 2, 4, 8, 16, 32, 64];

function points(values: number[]) {
  return frequencyAxis.map((x, index) => ({ x, y: values[index] ?? values[values.length - 1] ?? 0 }));
}

export const mockRheologySeries: MockLineSeries[] = [
  {
    label: "GelMA 12%",
    color: "#2563ff",
    markers: true,
    points: points([1450, 1620, 1810, 2140, 2620, 3290, 3980, 4740, 5510, 6250]),
  },
  {
    label: "GelMA 16%",
    color: "#63b4ff",
    markers: true,
    points: points([1120, 1280, 1490, 1780, 2190, 2820, 3480, 4160, 4890, 5610]),
  },
  {
    label: "GelMA + HA",
    color: "#0c225d",
    dashed: true,
    points: points([930, 1060, 1220, 1450, 1810, 2310, 2860, 3520, 4240, 5070]),
  },
];

export const mockRheologyBand: MockBand = {
  color: "rgba(37, 99, 255, 0.18)",
  lower: points([1320, 1480, 1640, 1960, 2380, 3010, 3650, 4400, 5150, 5890]),
  upper: points([1580, 1770, 1970, 2320, 2840, 3560, 4310, 5080, 5860, 6630]),
};

export const mockScatterSeries: MockScatterSeries[] = [
  {
    label: "Storage modulus fit",
    color: "#1d4fff",
    points: [
      { x: 0.5, y: 1.3 },
      { x: 0.8, y: 1.55 },
      { x: 1.2, y: 1.92 },
      { x: 1.6, y: 2.14 },
      { x: 2.1, y: 2.55 },
      { x: 2.8, y: 2.88 },
      { x: 3.3, y: 3.21 },
      { x: 3.8, y: 3.44 },
    ],
    trend: [
      { x: 0.4, y: 1.12 },
      { x: 1.2, y: 1.88 },
      { x: 2.1, y: 2.53 },
      { x: 3.0, y: 3.07 },
      { x: 3.9, y: 3.52 },
    ],
  },
];
