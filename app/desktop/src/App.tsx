import { Suspense, lazy, useEffect, useMemo, useRef, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { AppIcon } from "./components/AppIcon";
import { getPlotContract, getWorkbenchMeta, healthcheck } from "./lib/api";
import { useComposerStore, useTensileStore, useWizardStore, useWorkbenchStore } from "./lib/store";
import type {
  PlotContract,
  ThemePreference,
  WorkbenchMeta,
  WorkbenchRoute,
  WorkbenchWorkspace,
} from "./lib/types";
import {
  WORKSPACE_ITEMS,
  WORKSPACE_META,
  getPlotStageLabel,
  hasComposerSessionContent,
  hasWizardSessionContent,
  normalizeWorkbenchRoute,
  plotRoute,
  plotStageFromRoute,
  workspaceForRoute,
} from "./lib/workbench";

const LaunchpadScreen = lazy(async () => ({
  default: (await import("./screens/LaunchpadScreen")).LaunchpadScreen,
}));
const TensileScreen = lazy(async () => ({
  default: (await import("./screens/TensileScreen")).TensileScreen,
}));
const WizardScreen = lazy(async () => ({
  default: (await import("./screens/WizardScreen")).WizardScreen,
}));
const ComposerScreen = lazy(async () => ({
  default: (await import("./screens/ComposerScreen")).ComposerScreen,
}));
const ProjectsScreen = lazy(async () => ({
  default: (await import("./screens/ProjectsScreen")).ProjectsScreen,
}));
const SettingsScreen = lazy(async () => ({
  default: (await import("./screens/SettingsScreen")).SettingsScreen,
}));

function describeThemePreference(value: ThemePreference) {
  if (value === "light") {
    return "Light";
  }
  if (value === "dark") {
    return "Dark";
  }
  return "System";
}

function resolvedTheme(preference: ThemePreference, prefersDark: boolean) {
  if (preference === "light" || preference === "dark") {
    return preference;
  }
  return prefersDark ? "dark" : "light";
}

function initialRoute(persistedRoute: WorkbenchRoute, rememberLastScreen: boolean) {
  if (typeof window !== "undefined") {
    const fromLocation = normalizeWorkbenchRoute(window.location.pathname);
    if (fromLocation) {
      return fromLocation;
    }
  }
  return rememberLastScreen ? persistedRoute : "/";
}

export default function App() {
  const persistedRoute = useWorkbenchStore((state) => state.lastRoute);
  const setPersistedRoute = useWorkbenchStore((state) => state.setLastRoute);
  const rememberLastScreen = useWorkbenchStore(
    (state) => state.settings.remember_last_screen,
  );
  const autoStatusPoll = useWorkbenchStore((state) => state.settings.auto_status_poll);
  const themePreference = useWorkbenchStore((state) => state.settings.theme_preference);
  const recentProjectsCount = useWorkbenchStore((state) => state.recentProjects.length);
  const [route, setRoute] = useState<WorkbenchRoute>(() =>
    initialRoute(persistedRoute, rememberLastScreen),
  );
  const [workbenchMeta, setWorkbenchMeta] = useState<WorkbenchMeta | null>(null);
  const [plotContract, setPlotContract] = useState<PlotContract | null>(null);
  const [metaError, setMetaError] = useState<string | null>(null);
  const sidecarReady = useWizardStore((state) => state.sidecarReady);
  const setSidecarReady = useWizardStore((state) => state.setSidecarReady);
  const wizard = useWizardStore(
    useShallow((state) => ({
      exportResult: state.exportResult,
      inputPath: state.inputPath,
      inspection: state.inspection,
      outputsCount: state.outputs.length,
      stage: state.stage,
      template: state.template,
    })),
  );
  const tensileCompareCount = useTensileStore((state) => state.comparisonSources.length);
  const tensileOutputsCount = useTensileStore((state) => state.comparisonResult?.outputs.length ?? 0);
  const composerProject = useComposerStore((state) => state.project);
  const composerPanelCount = composerProject.panels.length;
  const composerTextCount = composerProject.texts.length;
  const workbenchLoadRef = useRef<Promise<void> | null>(null);
  const workbenchStateRef = useRef<{
    meta: WorkbenchMeta | null;
    contract: PlotContract | null;
    metaError: string | null;
  }>({
    meta: null,
    contract: null,
    metaError: null,
  });

  const navigate = (nextRoute: WorkbenchRoute, options?: { replace?: boolean }) => {
    setRoute(nextRoute);
    if (typeof window === "undefined" || window.location.pathname === nextRoute) {
      return;
    }
    if (options?.replace) {
      window.history.replaceState(window.history.state, "", nextRoute);
      return;
    }
    window.history.pushState(window.history.state, "", nextRoute);
  };

  useEffect(() => {
    const handlePopState = () => {
      setRoute(normalizeWorkbenchRoute(window.location.pathname) ?? "/");
    };
    window.addEventListener("popstate", handlePopState);
    return () => {
      window.removeEventListener("popstate", handlePopState);
    };
  }, []);

  useEffect(() => {
    if (rememberLastScreen) {
      setPersistedRoute(route);
      return;
    }
    if (persistedRoute !== "/") {
      setPersistedRoute("/");
    }
  }, [persistedRoute, rememberLastScreen, route, setPersistedRoute]);

  useEffect(() => {
    if (!rememberLastScreen) {
      return;
    }
    const preferredRoute = persistedRoute;
    if (route === preferredRoute) {
      return;
    }
    if (typeof window !== "undefined" && window.location.pathname === "/") {
      navigate(preferredRoute, { replace: true });
    }
  }, [persistedRoute, rememberLastScreen, route]);

  const loadWorkbenchData = () => {
    if (workbenchLoadRef.current) {
      return workbenchLoadRef.current;
    }

    let request: Promise<void>;
    request = Promise.all([getWorkbenchMeta(), getPlotContract()])
      .then(([meta, contract]) => {
        setWorkbenchMeta(meta);
        setPlotContract(contract);
        setMetaError(null);
      })
      .catch((error) => {
        setMetaError(error instanceof Error ? error.message : String(error));
      })
      .finally(() => {
        if (workbenchLoadRef.current === request) {
          workbenchLoadRef.current = null;
        }
      });

    workbenchLoadRef.current = request;
    return request;
  };

  useEffect(() => {
    void loadWorkbenchData();
  }, []);

  useEffect(() => {
    workbenchStateRef.current = {
      meta: workbenchMeta,
      contract: plotContract,
      metaError,
    };
  }, [metaError, plotContract, workbenchMeta]);

  useEffect(() => {
    let cancelled = false;
    let intervalId: number | undefined;

    async function check() {
      const ok = await healthcheck();
      if (!cancelled) {
        setSidecarReady(ok);
        if (ok) {
          const { meta, contract, metaError: currentMetaError } = workbenchStateRef.current;
          if (!meta || !contract || currentMetaError) {
            void loadWorkbenchData();
          }
        }
      }
    }

    void check();
    if (autoStatusPoll) {
      intervalId = window.setInterval(() => {
        void check();
      }, 6000);
    }

    return () => {
      cancelled = true;
      if (intervalId) {
        window.clearInterval(intervalId);
      }
    };
  }, [autoStatusPoll, setSidecarReady]);

  useEffect(() => {
    if (sidecarReady && (!workbenchMeta || !plotContract || metaError)) {
      void loadWorkbenchData();
    }
  }, [metaError, plotContract, sidecarReady, workbenchMeta]);

  useEffect(() => {
    if (typeof window === "undefined" || typeof document === "undefined") {
      return;
    }

    const root = document.documentElement;
    const mediaQuery =
      typeof window.matchMedia === "function"
        ? window.matchMedia("(prefers-color-scheme: dark)")
        : null;

    const applyTheme = () => {
      const theme = resolvedTheme(themePreference, Boolean(mediaQuery?.matches));
      root.dataset.theme = theme;
      root.style.colorScheme = theme;
    };

    applyTheme();
    if (!mediaQuery || themePreference !== "system") {
      return;
    }

    const handleChange = () => {
      applyTheme();
    };

    if (typeof mediaQuery.addEventListener === "function") {
      mediaQuery.addEventListener("change", handleChange);
      return () => {
        mediaQuery.removeEventListener("change", handleChange);
      };
    }

    mediaQuery.addListener(handleChange);
    return () => {
      mediaQuery.removeListener(handleChange);
    };
  }, [themePreference]);

  const workspace = workspaceForRoute(route);
  const meta = WORKSPACE_META[workspace];
  const plotSessionActive = hasWizardSessionContent({
    inputPath: wizard.inputPath,
    inspection: wizard.inspection,
    template: wizard.template,
    outputs: wizard.outputsCount > 0 ? new Array(wizard.outputsCount).fill("") : [],
    exportResult: wizard.exportResult,
  });
  const composerSessionActive = hasComposerSessionContent(composerProject);

  const workspaceLinks = useMemo(
    () =>
      WORKSPACE_ITEMS.map((item) => ({
        ...item,
        route:
          item.workspace === "plot"
            ? plotSessionActive
              ? plotRoute(wizard.stage)
              : "/plot/import"
            : item.workspace === "tensile"
              ? "/tensile"
              : item.workspace === "composer"
                ? "/composer"
                : item.workspace === "recents"
                  ? "/recents"
                  : "/settings",
      })),
    [plotSessionActive, wizard.stage],
  );

  let secondaryStatusLabel = "Focus mode";
  if (workspace === "plot") {
    secondaryStatusLabel =
      wizard.outputsCount > 0
        ? `${getPlotStageLabel(wizard.stage)} / ${wizard.outputsCount} outputs`
        : `${getPlotStageLabel(plotStageFromRoute(route))} stage`;
  } else if (workspace === "tensile") {
    secondaryStatusLabel =
      tensileOutputsCount > 0
        ? `${tensileCompareCount} sources / ${tensileOutputsCount} outputs`
        : `${tensileCompareCount} sources queued`;
  } else if (workspace === "composer") {
    secondaryStatusLabel = `${composerPanelCount + composerTextCount} objects`;
  } else if (workspace === "recents") {
    secondaryStatusLabel = `${recentProjectsCount} recent files`;
  } else if (workspace === "settings") {
    secondaryStatusLabel = `${describeThemePreference(themePreference)} Theme`;
  } else if (plotSessionActive) {
    secondaryStatusLabel = `Plot session · ${getPlotStageLabel(wizard.stage)}`;
  } else if (composerSessionActive) {
    secondaryStatusLabel = "Composer session ready";
  }

  let content = (
    <LaunchpadScreen sidecarReady={sidecarReady} onNavigate={navigate} />
  );

  if (workspace === "plot") {
    content = (
      <WizardScreen
        meta={workbenchMeta}
        onNavigate={navigate}
        routeStage={plotStageFromRoute(route)}
      />
    );
  } else if (workspace === "tensile") {
    content = <TensileScreen meta={workbenchMeta} onNavigate={navigate} />;
  } else if (workspace === "composer") {
    content = <ComposerScreen />;
  } else if (workspace === "recents") {
    content = <ProjectsScreen meta={workbenchMeta} onNavigate={navigate} />;
  } else if (workspace === "settings") {
    content = <SettingsScreen contract={plotContract} meta={workbenchMeta} />;
  }

  return (
    <div className={`app-shell ${workspace === "launchpad" ? "launchpad-mode" : "workspace-mode"}`}>
      <header className="app-topbar">
        <div className="app-topbar-brand">
          <button className="brand-mark" onClick={() => navigate("/")} type="button">
            <AppIcon name="spark" />
          </button>
          <div className="brand-copy">
            <span className="eyebrow">{meta.eyebrow}</span>
            <h1>{meta.title}</h1>
          </div>
        </div>

        <div className="app-topbar-actions">
          {workspace !== "launchpad" && (
            <button className="ghost-button home-button" onClick={() => navigate("/")} type="button">
              <AppIcon name="home" />
              <span>Launchpad</span>
            </button>
          )}

          <div className="workspace-chip-row">
            {workspaceLinks.map((item) => {
              const active = workspace === item.workspace;
              return (
                <button
                  className={`workspace-chip ${active ? "active" : ""}`}
                  key={item.workspace}
                  onClick={() => navigate(item.route)}
                  type="button"
                >
                  <AppIcon name={item.icon} />
                  <span>{item.label}</span>
                </button>
              );
            })}
          </div>

          <div className="status-pills">
            <span className={`status-pill ${sidecarReady ? "good" : "warn"}`}>
              {sidecarReady ? "Sidecar Online" : "Sidecar Offline"}
            </span>
            <span className="status-pill accent">{secondaryStatusLabel}</span>
          </div>
        </div>
      </header>

      {metaError && <div className="warning-card topbar-warning">{metaError}</div>}

      <main className="app-main">
        <Suspense fallback={<div className="placeholder-card">Loading workspace…</div>}>
          {content}
        </Suspense>
      </main>
    </div>
  );
}
