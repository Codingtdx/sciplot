export type MockWorkbenchId = "plot" | "cleanup" | "composer" | "console";

export type MockPlotStageId = "import" | "template" | "refine";
export type MockCleanupStageId = "import" | "review" | "compare" | "export";
export type MockComposerStageId = "assets" | "canvas" | "review" | "export";
export type MockConsoleStageId = "context" | "code" | "run" | "outputs";

export type MockStageId =
  | MockPlotStageId
  | MockCleanupStageId
  | MockComposerStageId
  | MockConsoleStageId;

export type MockRoute =
  | { workbench: "plot"; stage: MockPlotStageId }
  | { workbench: "cleanup"; stage: MockCleanupStageId }
  | { workbench: "composer"; stage: MockComposerStageId }
  | { workbench: "console"; stage: MockConsoleStageId };

export type MockPrimaryNavItem = {
  id: MockWorkbenchId;
  label: string;
  eyebrow: string;
  description: string;
  defaultHash: `#/${MockWorkbenchId}/${string}`;
};

export type MockStageNavItem<TStage extends MockStageId = MockStageId> = {
  id: TStage;
  label: string;
  summary: string;
  hash: `#/${MockWorkbenchId}/${string}`;
};

export type MockRouteMeta = {
  title: string;
  subtitle: string;
  workspaceLabel: string;
  focusLabel: string;
};

export const mockPrimaryNavItems: MockPrimaryNavItem[] = [
  {
    id: "plot",
    label: "Plot",
    eyebrow: "Figure workbench",
    description:
      "Import structured data, compare template directions, and refine figure export on one analytical surface.",
    defaultHash: "#/plot/refine",
  },
  {
    id: "cleanup",
    label: "Data Cleanup",
    eyebrow: "Workbook cleanup",
    description:
      "Review intake, normalize tensile outputs, compare QC summaries, and hand cleaned results into Plot.",
    defaultHash: "#/cleanup/review",
  },
  {
    id: "composer",
    label: "Composer",
    eyebrow: "Panel composition",
    description:
      "Arrange graphs, assets, and annotations on a canvas-first multi-panel layout surface.",
    defaultHash: "#/composer/canvas",
  },
  {
    id: "console",
    label: "Code Console",
    eyebrow: "Controlled execution",
    description:
      "Bind current figure context, run repo-native Python, and inspect generated outputs without leaving the app.",
    defaultHash: "#/console/code",
  },
];

export const mockStageNavByWorkbench: {
  plot: MockStageNavItem<MockPlotStageId>[];
  cleanup: MockStageNavItem<MockCleanupStageId>[];
  composer: MockStageNavItem<MockComposerStageId>[];
  console: MockStageNavItem<MockConsoleStageId>[];
} = {
  plot: [
    {
      id: "import",
      label: "Import",
      summary: "Inspect workbook structure and sheet fit.",
      hash: "#/plot/import",
    },
    {
      id: "template",
      label: "Template",
      summary: "Compare recommendation-led figure directions.",
      hash: "#/plot/template",
    },
    {
      id: "refine",
      label: "Refine & Export",
      summary: "Tune preview and keep export attached to it.",
      hash: "#/plot/refine",
    },
  ],
  cleanup: [
    {
      id: "import",
      label: "Import",
      summary: "Intake raw CSV and workbook supplements.",
      hash: "#/cleanup/import",
    },
    {
      id: "review",
      label: "Review & Clean",
      summary: "Normalize the workbook on one main cleanup surface.",
      hash: "#/cleanup/review",
    },
    {
      id: "compare",
      label: "Compare",
      summary: "QC curves and summary statistics before handoff.",
      hash: "#/cleanup/compare",
    },
    {
      id: "export",
      label: "Export / Open in Plot",
      summary: "Bundle the workbook or continue into Plot.",
      hash: "#/cleanup/export",
    },
  ],
  composer: [
    {
      id: "assets",
      label: "Assets",
      summary: "Review graph, text, and image inputs.",
      hash: "#/composer/assets",
    },
    {
      id: "canvas",
      label: "Canvas",
      summary: "Place panels on the dominant composition surface.",
      hash: "#/composer/canvas",
    },
    {
      id: "review",
      label: "Review",
      summary: "Check layer order, overlaps, and annotations.",
      hash: "#/composer/review",
    },
    {
      id: "export",
      label: "Export",
      summary: "Prepare the single-page PDF bundle.",
      hash: "#/composer/export",
    },
  ],
  console: [
    {
      id: "context",
      label: "Context",
      summary: "Bind the active dataset, figure, and run target.",
      hash: "#/console/context",
    },
    {
      id: "code",
      label: "Code",
      summary: "Edit the controlled Python snippet.",
      hash: "#/console/code",
    },
    {
      id: "run",
      label: "Run",
      summary: "Execute against the managed output directory.",
      hash: "#/console/run",
    },
    {
      id: "outputs",
      label: "Outputs",
      summary: "Inspect generated files and handoff options.",
      hash: "#/console/outputs",
    },
  ],
};

const DEFAULT_ROUTE_BY_WORKBENCH: Record<MockWorkbenchId, MockRoute> = {
  plot: { workbench: "plot", stage: "refine" },
  cleanup: { workbench: "cleanup", stage: "review" },
  composer: { workbench: "composer", stage: "canvas" },
  console: { workbench: "console", stage: "code" },
};

const ROUTE_META: Record<string, MockRouteMeta> = {
  "plot/import": {
    title: "Plot Import",
    subtitle: "Workbook-first intake with inspection kept inside the local Plot flow.",
    workspaceLabel: "Plot",
    focusLabel: "Import",
  },
  "plot/template": {
    title: "Plot Template",
    subtitle: "Recommendation-led figure selection on the active dataset.",
    workspaceLabel: "Plot",
    focusLabel: "Template",
  },
  "plot/refine": {
    title: "Plot Refine & Export",
    subtitle: "Preview-first figure tuning with export attached to the active surface.",
    workspaceLabel: "Plot",
    focusLabel: "Refine & Export",
  },
  "cleanup/import": {
    title: "Data Cleanup Intake",
    subtitle: "Bring raw tensile CSV and structured workbook supplements into one cleanup workspace.",
    workspaceLabel: "Data Cleanup",
    focusLabel: "Import",
  },
  "cleanup/review": {
    title: "Data Cleanup Review & Clean",
    subtitle: "One coherent cleanup surface for normalization, QC, and representative workbook review.",
    workspaceLabel: "Data Cleanup",
    focusLabel: "Review & Clean",
  },
  "cleanup/compare": {
    title: "Data Cleanup Compare",
    subtitle: "Cross-check cleaned summaries and representative curves without leaving the cleanup surface.",
    workspaceLabel: "Data Cleanup",
    focusLabel: "Compare",
  },
  "cleanup/export": {
    title: "Data Cleanup Export & Plot Handoff",
    subtitle: "Keep export and Plot handoff adjacent to the cleaned workbook review.",
    workspaceLabel: "Data Cleanup",
    focusLabel: "Export / Open in Plot",
  },
  "composer/assets": {
    title: "Composer Assets",
    subtitle: "Stage graph PDFs, micrographs, and annotations around the composition canvas.",
    workspaceLabel: "Composer",
    focusLabel: "Assets",
  },
  "composer/canvas": {
    title: "Composer Canvas",
    subtitle: "Canvas-first panel composition with assets and review kept secondary.",
    workspaceLabel: "Composer",
    focusLabel: "Canvas",
  },
  "composer/review": {
    title: "Composer Review",
    subtitle: "Check layer order, panel bounds, and annotation placement without shrinking the canvas.",
    workspaceLabel: "Composer",
    focusLabel: "Review",
  },
  "composer/export": {
    title: "Composer Export",
    subtitle: "Prepare the single-page export bundle while keeping the canvas dominant.",
    workspaceLabel: "Composer",
    focusLabel: "Export",
  },
  "console/context": {
    title: "Code Console Context",
    subtitle: "Bind dataset, plot session, and runtime constraints before editing code.",
    workspaceLabel: "Code Console",
    focusLabel: "Context",
  },
  "console/code": {
    title: "Code Console",
    subtitle: "A focused code-and-output surface for controlled scientific scripting.",
    workspaceLabel: "Code Console",
    focusLabel: "Code",
  },
  "console/run": {
    title: "Code Console Run",
    subtitle: "Keep execution status and output logs attached to the same dominant coding surface.",
    workspaceLabel: "Code Console",
    focusLabel: "Run",
  },
  "console/outputs": {
    title: "Code Console Outputs",
    subtitle: "Inspect generated files and hand off results without turning the console into a dashboard.",
    workspaceLabel: "Code Console",
    focusLabel: "Outputs",
  },
};

export function isMockWorkbenchId(value: string): value is MockWorkbenchId {
  return value === "plot" || value === "cleanup" || value === "composer" || value === "console";
}

export function getDefaultRoute(workbench: MockWorkbenchId = "plot"): MockRoute {
  return DEFAULT_ROUTE_BY_WORKBENCH[workbench];
}

export function getMockRouteHash(route: MockRoute): `#/${MockWorkbenchId}/${string}` {
  return `#/${route.workbench}/${route.stage}` as `#/${MockWorkbenchId}/${string}`;
}

export function getDefaultHashForWorkbench(
  workbench: MockWorkbenchId,
): `#/${MockWorkbenchId}/${string}` {
  return getMockRouteHash(getDefaultRoute(workbench));
}

export function normalizeMockRoute(hash: string): MockRoute {
  const normalized = hash.replace(/^#\//, "");
  const [workbench, stage] = normalized.split("/");

  if (!isMockWorkbenchId(workbench)) {
    return getDefaultRoute();
  }

  switch (workbench) {
    case "plot": {
      let normalizedStage: MockPlotStageId = "refine";
      if (stage === "import" || stage === "template" || stage === "refine") {
        normalizedStage = stage as MockPlotStageId;
      }
      return {
        workbench,
        stage: normalizedStage,
      };
    }
    case "cleanup": {
      let normalizedStage: MockCleanupStageId = "review";
      if (
        stage === "import" ||
        stage === "review" ||
        stage === "compare" ||
        stage === "export"
      ) {
        normalizedStage = stage as MockCleanupStageId;
      }
      return {
        workbench,
        stage: normalizedStage,
      };
    }
    case "composer": {
      let normalizedStage: MockComposerStageId = "canvas";
      if (
        stage === "assets" ||
        stage === "canvas" ||
        stage === "review" ||
        stage === "export"
      ) {
        normalizedStage = stage as MockComposerStageId;
      }
      return {
        workbench,
        stage: normalizedStage,
      };
    }
    case "console": {
      let normalizedStage: MockConsoleStageId = "code";
      if (
        stage === "context" ||
        stage === "code" ||
        stage === "run" ||
        stage === "outputs"
      ) {
        normalizedStage = stage as MockConsoleStageId;
      }
      return {
        workbench,
        stage: normalizedStage,
      };
    }
  }
}

export function getMockRouteMeta(route: MockRoute): MockRouteMeta {
  return ROUTE_META[`${route.workbench}/${route.stage}`];
}
