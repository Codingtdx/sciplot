export const MOCK_ROUTE_IDS = ["start", "import", "template", "refine"] as const;

export type MockRouteId = (typeof MOCK_ROUTE_IDS)[number];

export type MockRouteDefinition = {
  id: MockRouteId;
  path: string;
  navLabel: string;
  navDescription: string;
  title: string;
  eyebrow: string;
  icon: "start" | "import" | "template" | "refine";
};

export const MOCK_ROUTES: MockRouteDefinition[] = [
  {
    id: "start",
    path: "/mock/start",
    navLabel: "Home",
    navDescription: "Entry workspace for new desktop figure sessions.",
    title: "Workspace Home",
    eyebrow: "Static Mock Build",
    icon: "start",
  },
  {
    id: "import",
    path: "/mock/import",
    navLabel: "Dataset Browser",
    navDescription: "Dense table import workspace with inspection rail.",
    title: "Dataset Browser",
    eyebrow: "Static Mock Build",
    icon: "import",
  },
  {
    id: "template",
    path: "/mock/template",
    navLabel: "Template Studio",
    navDescription: "Recommendation-led chart selection with preview.",
    title: "Template Studio",
    eyebrow: "Static Mock Build",
    icon: "template",
  },
  {
    id: "refine",
    path: "/mock/refine",
    navLabel: "Figure Lab",
    navDescription: "Preview-dominant figure tuning and export flow.",
    title: "Figure Lab",
    eyebrow: "Static Mock Build",
    icon: "refine",
  },
];

const ROUTE_MAP = new Map<MockRouteId, MockRouteDefinition>(
  MOCK_ROUTES.map((route) => [route.id, route]),
);

export function mockRouteById(routeId: MockRouteId) {
  return ROUTE_MAP.get(routeId) ?? ROUTE_MAP.get("start")!;
}

export function mockRouteFromPath(pathname: string): MockRouteId {
  const matched = MOCK_ROUTES.find((route) => pathname === route.path);
  return matched?.id ?? "start";
}

export function pathForMockRoute(routeId: MockRouteId) {
  return mockRouteById(routeId).path;
}

export function documentTitleForMockRoute(routeId: MockRouteId) {
  const route = mockRouteById(routeId);
  return `SciPlot God Mock - ${route.title}`;
}
