export const mockImportWorkbook = {
  name: "PVA-aging-frequency-sweep.xlsx",
  source: "Local workbook",
  modified: "Today, 09:38",
  sheets: ["Sweep_Data", "Summary", "Protocol"],
  selectedSheet: "Sweep_Data",
};

export const mockImportColumns = [
  "Sample",
  "Frequency (Hz)",
  "Storage modulus G' (MPa)",
  "Loss modulus G'' (MPa)",
  "tan δ",
  "Temperature (°C)",
  "Replicate",
  "Operator note",
];

export const mockImportRows = [
  ["PVA-0h", "0.10", "0.84", "0.14", "0.17", "25.0", "R1", "baseline"],
  ["PVA-0h", "0.32", "1.21", "0.22", "0.18", "25.0", "R1", "baseline"],
  ["PVA-0h", "1.00", "1.89", "0.36", "0.19", "25.0", "R1", "baseline"],
  ["PVA-24h", "0.10", "1.46", "0.23", "0.16", "25.0", "R2", "aged"],
  ["PVA-24h", "0.32", "2.05", "0.34", "0.17", "25.0", "R2", "aged"],
  ["PVA-24h", "1.00", "2.96", "0.53", "0.18", "25.0", "R2", "aged"],
  ["PVA-72h", "0.10", "2.10", "0.32", "0.15", "25.0", "R3", "aged"],
  ["PVA-72h", "0.32", "2.88", "0.46", "0.16", "25.0", "R3", "aged"],
  ["PVA-72h", "1.00", "4.21", "0.70", "0.17", "25.0", "R3", "aged"],
  ["PVA-72h", "3.20", "5.60", "0.94", "0.17", "25.0", "R3", "aged"],
  ["PVA-120h", "0.10", "2.92", "0.43", "0.15", "25.0", "R4", "crosslinked"],
  ["PVA-120h", "1.00", "5.18", "0.81", "0.16", "25.0", "R4", "crosslinked"],
];

export const mockImportInspectionFacts = [
  { label: "Detected structure", value: "Rheology sweep bundle" },
  { label: "Rows scanned", value: "128 rows" },
  { label: "Numeric columns", value: "5 / 8" },
  { label: "Primary x candidate", value: "Frequency (Hz)" },
  { label: "Signal columns", value: "G', G'', tan δ" },
  { label: "Value span", value: "0.10 to 100.0 Hz" },
];

export const mockImportInspectionNotes = [
  "Frequency is strictly positive and spans multiple decades.",
  "Storage and loss modulus remain well-formed across the active sheet.",
  "Operator notes are sparse and do not block plot generation.",
];

export const mockImportCompatibleTemplates = [
  "Curve",
  "Point-line",
  "Scatter",
  "Replicate curves with band",
];

