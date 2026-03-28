import type { AppIconName } from "./components/AppIcon";

export const ACTIVE_ROUTES = ["/", "/plot/import", "/plot/template", "/plot/refine"] as const;

export type ActiveRoute = (typeof ACTIVE_ROUTES)[number];

export type NavItem = {
  route: ActiveRoute;
  label: string;
  icon: AppIconName;
  description: string;
};

export const NAV_ITEMS: NavItem[] = [
  {
    route: "/",
    label: "Start",
    icon: "start",
    description: "Open a dataset or resume recent work.",
  },
  {
    route: "/plot/import",
    label: "Plot Import",
    icon: "import",
    description: "Load data and confirm what SciPlot detected.",
  },
  {
    route: "/plot/template",
    label: "Plot Template",
    icon: "template",
    description: "Choose the strongest recommendation first.",
  },
  {
    route: "/plot/refine",
    label: "Plot Refine",
    icon: "refine",
    description: "Tune the chart and export inline.",
  },
];

function isActiveRoute(value: string): value is ActiveRoute {
  return (ACTIVE_ROUTES as readonly string[]).includes(value);
}

export function normalizeActiveRoute(value: string | null | undefined): ActiveRoute {
  if (!value) {
    return "/";
  }
  if (isActiveRoute(value)) {
    return value;
  }
  if (value.startsWith("/plot/")) {
    if (value === "/plot/import" || value === "/plot/sheet") {
      return "/plot/import";
    }
    if (value === "/plot/type") {
      return "/plot/template";
    }
    return "/plot/refine";
  }
  return "/";
}

export function currentPathname() {
  if (typeof window === "undefined") {
    return "/";
  }
  return normalizeActiveRoute(window.location.pathname);
}

export function documentTitleForRoute(route: ActiveRoute) {
  switch (route) {
    case "/plot/import":
      return "SciPlot God - Plot Import";
    case "/plot/template":
      return "SciPlot God - Plot Template";
    case "/plot/refine":
      return "SciPlot God - Plot Refine";
    case "/":
    default:
      return "SciPlot God - Start";
  }
}
