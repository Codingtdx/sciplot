import { useEffect, useState } from "react";

import {
  getDefaultRoute,
  getMockRouteHash,
  normalizeMockRoute,
  type MockRoute,
} from "./data/mockNavigationData";
import { MockShell } from "./shell/MockShell";
import { MockCodeConsoleWorkbench } from "./screens/MockCodeConsoleWorkbench";
import { MockComposerWorkbench } from "./screens/MockComposerWorkbench";
import { MockDataCleanupWorkbench } from "./screens/MockDataCleanupWorkbench";
import { MockPlotWorkbench } from "./screens/MockPlotWorkbench";

function readCurrentRoute(): MockRoute {
  if (typeof window === "undefined") {
    return getDefaultRoute();
  }

  return normalizeMockRoute(window.location.hash);
}

function renderRoute(route: MockRoute) {
  switch (route.workbench) {
    case "plot":
      return <MockPlotWorkbench stage={route.stage} />;
    case "cleanup":
      return <MockDataCleanupWorkbench stage={route.stage} />;
    case "composer":
      return <MockComposerWorkbench stage={route.stage} />;
    case "console":
      return <MockCodeConsoleWorkbench stage={route.stage} />;
  }
}

export function MockApp() {
  const [route, setRoute] = useState<MockRoute>(() => readCurrentRoute());

  useEffect(() => {
    const syncRoute = () => {
      const nextRoute = readCurrentRoute();
      const normalizedHash = getMockRouteHash(nextRoute);

      if (window.location.hash !== normalizedHash) {
        window.history.replaceState(null, "", normalizedHash);
      }

      setRoute(nextRoute);
    };

    if (!window.location.hash) {
      window.history.replaceState(null, "", getMockRouteHash(getDefaultRoute()));
    }

    syncRoute();

    window.addEventListener("hashchange", syncRoute);
    return () => {
      window.removeEventListener("hashchange", syncRoute);
    };
  }, []);

  return <MockShell currentRoute={route}>{renderRoute(route)}</MockShell>;
}
