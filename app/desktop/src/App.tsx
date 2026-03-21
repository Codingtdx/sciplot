import { Suspense, lazy, useEffect, useMemo, useRef, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { AppIcon } from "./components/AppIcon";
import { getPlotContract, getWorkbenchMeta, healthcheck } from "./lib/api";
import {
  useComposerStore,
  useTensileStore,
  useWizardStore,
  useWorkbenchStore,
} from "./lib/store";
import type {
  PlotContract,
  WorkbenchMeta,
  WorkbenchRoute,
} from "./lib/types";
import {
  describeAppearanceMode,
  resolveAppearance,
  resolveThemePreset,
} from "./lib/themes";
import {
  WORKSPACE_ITEMS,
  WORKSPACE_META,
  formatLeaf,
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
const CodeConsoleScreen = lazy(async () => ({
  default: (await import("./screens/CodeConsoleScreen")).CodeConsoleScreen,
}));
const SettingsScreen = lazy(async () => ({
  default: (await import("./screens/SettingsScreen")).SettingsScreen,
}));

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
  const appearanceMode = useWorkbenchStore((state) => state.settings.appearance_mode);
  const themePresetId = useWorkbenchStore((state) => state.settings.theme_preset_id);
  const [route, setRoute] = useState<WorkbenchRoute>(() =>
    initialRoute(persistedRoute, rememberLastScreen),
  );
  const [prefersDark, setPrefersDark] = useState(false);
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
  const tensileLatestWorkbook = useTensileStore(
    (state) => state.preprocessResult?.output_path ?? "",
  );
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

  const resolvedAppearanceValue = resolveAppearance(appearanceMode, prefersDark);
  const activeThemePreset = resolveThemePreset(themePresetId, resolvedAppearanceValue);

  useEffect(() => {
    if (typeof window === "undefined" || typeof document === "undefined") {
      return;
    }

    const root = document.documentElement;
    const mediaQuery =
      typeof window.matchMedia === "function"
        ? window.matchMedia("(prefers-color-scheme: dark)")
        : null;

    const syncPreference = () => {
      const nextPrefersDark = Boolean(mediaQuery?.matches);
      setPrefersDark(nextPrefersDark);
      const theme = resolveAppearance(appearanceMode, nextPrefersDark);
      const preset = resolveThemePreset(themePresetId, theme);
      root.dataset.theme = theme;
      root.dataset.themePreset = preset.id;
      root.style.colorScheme = theme;
    };

    syncPreference();

    if (!mediaQuery) {
      return;
    }

    const handleChange = () => {
      syncPreference();
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
  }, [appearanceMode, themePresetId]);

  const workspace = workspaceForRoute(route);
  const meta = WORKSPACE_META[workspace];
  const currentPlotStage = plotStageFromRoute(route);
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
                : item.workspace === "code"
                  ? "/code-console"
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
  } else if (workspace === "code") {
    secondaryStatusLabel = wizard.inputPath ? "Current plot context" : "Waiting for Plot session";
  } else if (workspace === "settings") {
    secondaryStatusLabel = `${describeAppearanceMode(appearanceMode)} · ${activeThemePreset.name}`;
  } else if (plotSessionActive) {
    secondaryStatusLabel = `Plot session · ${getPlotStageLabel(wizard.stage)}`;
  } else if (composerSessionActive) {
    secondaryStatusLabel = "Composer session ready";
  }

  let activeItemLabel = "Next action";
  let activeItemValue = "Choose a workspace and start working.";
  if (workspace === "plot") {
    activeItemLabel = "Active file";
    activeItemValue = wizard.inputPath ? formatLeaf(wizard.inputPath) : "No file loaded";
  } else if (workspace === "tensile") {
    activeItemLabel = "Latest workbook";
    activeItemValue = tensileLatestWorkbook ? formatLeaf(tensileLatestWorkbook) : "No workbook prepared";
  } else if (workspace === "composer") {
    activeItemLabel = "Canvas";
    activeItemValue =
      composerPanelCount + composerTextCount > 0
        ? `${composerPanelCount + composerTextCount} visible objects in session`
        : "No composition open";
  } else if (workspace === "code") {
    activeItemLabel = "Bound data";
    activeItemValue = wizard.inputPath ? formatLeaf(wizard.inputPath) : "No data bound";
  } else if (workspace === "settings") {
    activeItemLabel = "Appearance";
    activeItemValue = `${describeAppearanceMode(appearanceMode)} / ${activeThemePreset.name}`;
  } else if (plotSessionActive) {
    activeItemLabel = "Resume";
    activeItemValue = `Plot · ${getPlotStageLabel(wizard.stage)}`;
  } else if (composerSessionActive) {
    activeItemLabel = "Resume";
    activeItemValue = "Composer session ready";
  }

  let content = (
    <LaunchpadScreen
      activeThemePresetName={activeThemePreset.name}
      meta={workbenchMeta}
      sidecarReady={sidecarReady}
      onNavigate={navigate}
    />
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
  } else if (workspace === "code") {
    content = <CodeConsoleScreen contract={plotContract} meta={workbenchMeta} onNavigate={navigate} />;
  } else if (workspace === "settings") {
    content = <SettingsScreen contract={plotContract} meta={workbenchMeta} />;
  }

  return (
    <div className="app-shell" data-workspace={workspace}>
      <aside className="app-sidebar">
        <button
          className={`sidebar-brand ${workspace === "launchpad" ? "active" : ""}`}
          onClick={() => navigate("/")}
          type="button"
        >
          <span className="sidebar-brand-mark">
            <AppIcon name="spark" />
          </span>
          <span className="sidebar-brand-copy">
            <strong>SciPlot God</strong>
            <span>Focused desktop workspace</span>
          </span>
        </button>

        <button
          className={`sidebar-start-link ${workspace === "launchpad" ? "active" : ""}`}
          onClick={() => navigate("/")}
          type="button"
        >
          <AppIcon name="home" />
          <span>Start</span>
        </button>

        <nav className="sidebar-nav" aria-label="Workspaces">
          {workspaceLinks.map((item) => {
            const active = workspace === item.workspace;
            return (
              <button
                className={`sidebar-nav-item ${active ? "active" : ""}`}
                key={item.workspace}
                onClick={() => navigate(item.route)}
                type="button"
              >
                <AppIcon name={item.icon} />
                <span>{item.label}</span>
              </button>
            );
          })}
        </nav>

        <div className="sidebar-footer">
          <span>{plotSessionActive || composerSessionActive ? `${Number(plotSessionActive) + Number(composerSessionActive)} active session(s)` : "No active sessions"}</span>
        </div>
      </aside>

      <div className="app-workspace-shell">
        <header className="workspace-header">
          <div className="workspace-header-copy">
            <span className="eyebrow">{meta.eyebrow}</span>
            <div className="workspace-header-title-row">
              <h1>{meta.title}</h1>
              <span className="workspace-header-inline-status">
                {workspace === "plot"
                  ? `${getPlotStageLabel(currentPlotStage)} stage`
                  : secondaryStatusLabel}
              </span>
            </div>
            <p className="workspace-header-description">{meta.description}</p>
          </div>

          <div className="workspace-header-meta">
            <div className="workspace-header-item">
              <span>{activeItemLabel}</span>
              <strong>{activeItemValue}</strong>
            </div>
            <button
              className="ghost-button titlebar-theme-button"
              onClick={() => navigate("/settings")}
              type="button"
            >
              <span>{activeThemePreset.name}</span>
              <span className="titlebar-theme-subcopy">
                {describeAppearanceMode(appearanceMode)}
              </span>
            </button>
            <span className={`status-pill ${sidecarReady ? "good" : "warn"}`}>
              {sidecarReady ? "Sidecar Online" : "Sidecar Offline"}
            </span>
          </div>
        </header>

        {metaError && <div className="warning-card topbar-warning">{metaError}</div>}

        <main className="app-main" data-scroll-root="workspace">
          <Suspense fallback={<div className="placeholder-card">Loading workspace…</div>}>
            {content}
          </Suspense>
        </main>
      </div>
    </div>
  );
}
