import { useEffect, useState } from "react";

import { MockShell } from "./components/MockShell";
import {
  documentTitleForMockRoute,
  mockRouteFromPath,
  pathForMockRoute,
  type MockRouteId,
} from "./mock-routes";
import { MockPlotImport } from "./screens/MockPlotImport";
import { MockPlotRefine } from "./screens/MockPlotRefine";
import { MockPlotTemplate } from "./screens/MockPlotTemplate";
import { MockStart } from "./screens/MockStart";

import "./mock.css";

function currentRoute() {
  if (typeof window === "undefined") {
    return "start" as MockRouteId;
  }
  return mockRouteFromPath(window.location.pathname);
}

export function MockApp() {
  const [route, setRoute] = useState<MockRouteId>(() => currentRoute());

  useEffect(() => {
    document.title = documentTitleForMockRoute(route);

    if (typeof window !== "undefined" && window.location.pathname !== pathForMockRoute(route)) {
      window.history.replaceState({}, "", pathForMockRoute(route));
    }
  }, [route]);

  useEffect(() => {
    if (typeof window === "undefined") {
      return undefined;
    }
    const onPopState = () => setRoute(currentRoute());
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  }, []);

  const navigate = (nextRoute: MockRouteId) => {
    if (typeof window !== "undefined" && window.location.pathname !== pathForMockRoute(nextRoute)) {
      window.history.pushState({}, "", pathForMockRoute(nextRoute));
    }
    setRoute(nextRoute);
  };

  let screen = <MockStart />;
  if (route === "import") {
    screen = <MockPlotImport />;
  } else if (route === "template") {
    screen = <MockPlotTemplate />;
  } else if (route === "refine") {
    screen = <MockPlotRefine />;
  }

  return (
    <MockShell activeRoute={route} onNavigate={navigate}>
      {screen}
    </MockShell>
  );
}
