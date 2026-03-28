import { useEffect, useState } from "react";

import {
  type MockRouteId,
  mockNavigationItems,
} from "./data/mockNavigationData";
import { MockShell } from "./shell/MockShell";
import { MockPlotImport } from "./screens/MockPlotImport";
import { MockPlotRefine } from "./screens/MockPlotRefine";
import { MockPlotTemplate } from "./screens/MockPlotTemplate";
import { MockStart } from "./screens/MockStart";

const KNOWN_ROUTE_IDS = new Set<MockRouteId>(
  mockNavigationItems.map((item) => item.id),
);

function getRouteFromHash(hash: string): MockRouteId {
  const normalized = hash.replace(/^#\//, "") as MockRouteId;
  return KNOWN_ROUTE_IDS.has(normalized) ? normalized : "start";
}

function readCurrentRoute(): MockRouteId {
  if (typeof window === "undefined") {
    return "start";
  }
  return getRouteFromHash(window.location.hash);
}

function renderRoute(route: MockRouteId) {
  switch (route) {
    case "plot-import":
      return <MockPlotImport />;
    case "plot-template":
      return <MockPlotTemplate />;
    case "plot-refine":
      return <MockPlotRefine />;
    case "start":
    default:
      return <MockStart />;
  }
}

export function MockApp() {
  const [route, setRoute] = useState<MockRouteId>(() => readCurrentRoute());

  useEffect(() => {
    if (!window.location.hash) {
      window.history.replaceState(null, "", "#/start");
      setRoute("start");
    }

    const handleHashChange = () => {
      setRoute(readCurrentRoute());
    };

    window.addEventListener("hashchange", handleHashChange);
    return () => {
      window.removeEventListener("hashchange", handleHashChange);
    };
  }, []);

  return <MockShell currentRoute={route}>{renderRoute(route)}</MockShell>;
}
