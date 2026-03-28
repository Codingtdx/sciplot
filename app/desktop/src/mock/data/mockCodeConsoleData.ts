export const mockConsoleHeader = {
  title: "Controlled plotting run",
  summary:
    "One focused surface for bound context, repo-native Python, controlled execution, and generated outputs.",
  status: "Run succeeded",
  duration: "4.8 s",
};

export const mockConsoleContextCards = [
  {
    label: "Bound dataset",
    value: "PVA-aging-frequency-sweep.xlsx",
    detail: "Sheet · Sweep_Data",
  },
  {
    label: "Inherited Plot context",
    value: "120 × 55 mm · Journal Calm",
    detail: "palette · Aqua Graphite",
  },
  {
    label: "Managed output dir",
    value: "code-console-runs/2026-03-28-0938",
    detail: "retained for handoff review",
  },
];

export const mockConsoleCode = `from pathlib import Path

from src.plotting import plot_curves

OUTPUT_DIR = Path("OUTPUT_DIR")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

figure = plot_curves(
    data_file="fixtures/pva-aging-frequency-sweep.xlsx",
    sheet_name="Sweep_Data",
    style_preset="journal_calm",
    palette_preset="aqua_graphite",
    size_preset="120x55",
)

figure.savefig(OUTPUT_DIR / "freq_dual_modulus_curve.pdf")
figure.savefig(OUTPUT_DIR / "freq_dual_modulus_curve.png", dpi=220)

print("Wrote figure bundle to managed output directory")`;

export const mockConsoleRunFacts = [
  { label: "Exit code", value: "0" },
  { label: "Stdout lines", value: "12" },
  { label: "Generated files", value: "4" },
];

export const mockConsoleStdout = [
  "[bind] active plot context loaded",
  "[inspect] workbook structure reused from Plot session",
  "[render] twin-modulus curve selected with log-x axis",
  "[write] freq_dual_modulus_curve.pdf",
  "[write] freq_dual_modulus_curve.png",
  "[write] manifest.json",
  "Wrote figure bundle to managed output directory",
];

export const mockConsoleGeneratedFiles = [
  {
    name: "curve.pdf",
    role: "Figure",
    meta: "export bundle",
  },
  {
    name: "curve.png",
    role: "Preview",
    meta: "220 dpi",
  },
  {
    name: "manifest.json",
    role: "Manifest",
    meta: "paths + timing",
  },
  {
    name: "stdout.txt",
    role: "Stdout",
    meta: "captured output",
  },
];

export const mockConsoleHandoff = [
  "Open in Composer",
  "Back to Plot",
  "Attach manifest",
];
