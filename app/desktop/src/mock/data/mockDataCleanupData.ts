export const mockCleanupHeader = {
  sessionName: "Hydrogel tensile cleanup session",
  summary:
    "One cleanup workspace for raw tensile intake, representative workbook review, QC comparison, and handoff into Plot.",
  status: "QC compare aligned",
  preferredSheet: "Preferred sheet · Cleaned_Representative",
};

export const mockCleanupSummary = [
  { label: "Raw files", value: "6 CSV" },
  { label: "Workbook supplements", value: "3 sheets" },
  { label: "Representative groups", value: "4 cohorts" },
  { label: "Plot handoff", value: "Ready" },
];

export const mockCleanupSources = [
  {
    name: "Hydrogel-raw-tensile-R1.csv",
    role: "Raw intake",
    status: "Parsed",
  },
  {
    name: "Hydrogel-raw-tensile-R2.csv",
    role: "Raw intake",
    status: "Trimmed",
  },
  {
    name: "Hydrogel-raw-tensile-R3.csv",
    role: "Raw intake",
    status: "Parsed",
  },
  {
    name: "Hydrogel-cleanup-notes.xlsx",
    role: "Workbook supplement",
    status: "Mapped",
  },
];

export const mockCleanupColumns = [
  "Group",
  "Thickness (mm)",
  "Strength (MPa)",
  "Modulus (MPa)",
  "Elongation (%)",
  "Preferred curve",
  "QC note",
];

export const mockCleanupRows = [
  ["Control", "0.87", "42.8", "8.2", "318", "R1", "baseline aligned"],
  ["Annealed", "0.89", "48.6", "9.7", "292", "R3", "minor tail trim"],
  ["Crosslinked", "0.92", "55.2", "11.9", "244", "R2", "grip slip removed"],
  ["Aged 72 h", "0.91", "58.4", "12.7", "228", "R3", "ready for compare"],
];

export const mockCleanupTransforms = [
  {
    title: "Detect and normalize",
    description: "Raw tensile CSV merged into one canonical cleanup sheet with force and strain axes aligned.",
  },
  {
    title: "Replicate curation",
    description: "Slip-heavy tail removed from R2 before representative curve selection.",
  },
  {
    title: "Workbook shaping",
    description: "Summary metrics and representative curves now point to the same preferred sheet.",
  },
];

export const mockCleanupIssues = [
  {
    title: "Grip slip trimmed",
    severity: "Review",
    description: "Crosslinked R2 loses stability after 238% elongation and is clipped before compare.",
  },
  {
    title: "Thickness backfilled",
    severity: "Resolved",
    description: "Annealed specimen thickness restored from workbook supplement and normalized to mm.",
  },
  {
    title: "Preferred curve pinned",
    severity: "Ready",
    description: "Aged 72 h now points to R3 for Plot handoff and box/bar exports.",
  },
];

export const mockCleanupCompareCards = [
  {
    title: "Strength box",
    eyebrow: "QC compare",
    summary: "Median strength shifts upward after crosslinking and aging.",
    values: [
      { label: "Control", value: 42 },
      { label: "Annealed", value: 49 },
      { label: "Crosslinked", value: 55 },
      { label: "Aged 72 h", value: 58 },
    ],
  },
  {
    title: "Representative curve",
    eyebrow: "Open in Plot",
    summary: "Preferred curves stay aligned with the cleaned workbook and can reopen directly in Plot.",
    values: [
      { label: "Control", value: 28 },
      { label: "Annealed", value: 42 },
      { label: "Crosslinked", value: 61 },
      { label: "Aged 72 h", value: 72 },
    ],
  },
];

export const mockCleanupHandoff = [
  {
    label: "Workbook export",
    detail: "Hydrogel-cleaned-representative.xlsx with preferred sheet and compare summaries.",
    action: "Ready",
  },
  {
    label: "Open in Plot",
    detail: "Representative curves and summary stats prepared for Plot inspect/template/refine flow.",
    action: "Linked",
  },
];
