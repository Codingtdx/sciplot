export type MockRouteId =
  | "start"
  | "plot-import"
  | "plot-template"
  | "plot-refine";

export type MockNavigationItem = {
  id: MockRouteId;
  label: string;
  eyebrow: string;
  description: string;
  hash: `#/${MockRouteId}`;
};

export type MockRouteMeta = {
  title: string;
  subtitle: string;
  workspaceLabel: string;
};

export const mockNavigationItems: MockNavigationItem[] = [
  {
    id: "start",
    label: "Home",
    eyebrow: "Workspace hub",
    description: "Open recent materials and launch a new local figure workspace.",
    hash: "#/start",
  },
  {
    id: "plot-import",
    label: "Datasets",
    eyebrow: "Data library",
    description: "Review workbook structure and inspect the active table surface.",
    hash: "#/plot-import",
  },
  {
    id: "plot-template",
    label: "Templates",
    eyebrow: "Figure styles",
    description: "Compare recommendation-led figure layouts on the active dataset.",
    hash: "#/plot-template",
  },
  {
    id: "plot-refine",
    label: "Studio",
    eyebrow: "Preview workspace",
    description: "Tune the active figure preview and keep export attached to it.",
    hash: "#/plot-refine",
  },
];

export const mockRouteMeta: Record<MockRouteId, MockRouteMeta> = {
  start: {
    title: "Workspace Home",
    subtitle: "A calm launch surface for starting or reopening a figure session.",
    workspaceLabel: "Home",
  },
  "plot-import": {
    title: "Datasets",
    subtitle: "Table-first workbook review with a narrow analytical inspection rail.",
    workspaceLabel: "Datasets",
  },
  "plot-template": {
    title: "Templates",
    subtitle: "Recommendation-first figure selection with analytical previews.",
    workspaceLabel: "Templates",
  },
  "plot-refine": {
    title: "Figure Studio",
    subtitle: "Preview-dominant figure tuning with a denser professional inspector.",
    workspaceLabel: "Studio",
  },
};
