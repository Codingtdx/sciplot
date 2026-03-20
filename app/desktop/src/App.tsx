import { Suspense, lazy, useEffect, useRef, useState } from "react";

import { AppIcon } from "./components/AppIcon";
import { getPlotContract, getWorkbenchMeta, healthcheck } from "./lib/api";
import { useComposerStore, useTensileStore, useWizardStore, useWorkbenchStore } from "./lib/store";
import { AppMode, NAV_ITEMS, SCREEN_META, getWizardStepLabel } from "./lib/workbench";
import type { PlotContract, ThemePreference, WorkbenchMeta } from "./lib/types";

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

export default function App() {
  const persistedScreen = useWorkbenchStore((state) => state.lastScreen);
  const setPersistedScreen = useWorkbenchStore((state) => state.setLastScreen);
  const rememberLastScreen = useWorkbenchStore(
    (state) => state.settings.remember_last_screen,
  );
  const autoStatusPoll = useWorkbenchStore((state) => state.settings.auto_status_poll);
  const themePreference = useWorkbenchStore((state) => state.settings.theme_preference);
  const recentProjectsCount = useWorkbenchStore((state) => state.recentProjects.length);
  const [mode, setMode] = useState<AppMode>(() =>
    rememberLastScreen ? persistedScreen : "wizard",
  );
  const [workbenchMeta, setWorkbenchMeta] = useState<WorkbenchMeta | null>(null);
  const [plotContract, setPlotContract] = useState<PlotContract | null>(null);
  const [metaError, setMetaError] = useState<string | null>(null);
  const sidecarReady = useWizardStore((state) => state.sidecarReady);
  const setSidecarReady = useWizardStore((state) => state.setSidecarReady);
  const wizardStep = useWizardStore((state) => state.step);
  const wizardOutputsCount = useWizardStore((state) => state.outputs.length);
  const tensileCompareCount = useTensileStore((state) => state.comparisonSources.length);
  const tensileOutputsCount = useTensileStore((state) => state.comparisonResult?.outputs.length ?? 0);
  const composerPanelCount = useComposerStore((state) => state.project.panels.length);
  const composerTextCount = useComposerStore((state) => state.project.texts.length);
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

  useEffect(() => {
    if (rememberLastScreen) {
      setMode(persistedScreen);
    }
  }, [persistedScreen, rememberLastScreen]);

  useEffect(() => {
    if (rememberLastScreen) {
      setPersistedScreen(mode);
    }
  }, [mode, rememberLastScreen, setPersistedScreen]);

  useEffect(() => {
    if (!rememberLastScreen && persistedScreen !== "wizard") {
      setPersistedScreen("wizard");
    }
  }, [rememberLastScreen, persistedScreen, setPersistedScreen]);

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

  const meta = SCREEN_META[mode];

  let secondaryStatusLabel = `Step ${getWizardStepLabel(wizardStep)}`;
  if (mode === "tensile") {
    secondaryStatusLabel =
      tensileOutputsCount > 0
        ? `${tensileCompareCount} sources / ${tensileOutputsCount} outputs`
        : `${tensileCompareCount} sources queued`;
  } else if (mode === "composer") {
    secondaryStatusLabel = `${composerPanelCount + composerTextCount} objects`;
  } else if (mode === "projects") {
    secondaryStatusLabel = `${recentProjectsCount} recent files`;
  } else if (mode === "settings") {
    secondaryStatusLabel = `${describeThemePreference(themePreference)} Theme`;
  } else if (wizardOutputsCount > 0) {
    secondaryStatusLabel = `${getWizardStepLabel(wizardStep)} / ${wizardOutputsCount} outputs`;
  }

  return (
    <div className="dashboard-shell">
      <aside className="nav-rail">
        <div className="rail-brand">
          <div className="brand-mark">CG</div>
          <div className="rail-brand-text">
            <strong>CodeGod</strong>
            <span>Desktop 5.0</span>
          </div>
        </div>

        <nav className="nav-cluster">
          {NAV_ITEMS.map((item) => (
            <button
              className={`nav-item ${mode === item.id ? "active" : ""}`}
              key={item.id}
              onClick={() => setMode(item.id)}
              type="button"
            >
              <span className="nav-item-icon">
                <AppIcon name={item.icon} />
              </span>
              <span className="nav-item-label">{item.label}</span>
            </button>
          ))}
        </nav>

        <div className="rail-footer">
          <div className={`rail-status-dot ${sidecarReady ? "online" : "offline"}`} />
          <span>{sidecarReady ? "Sidecar ready" : "Sidecar offline"}</span>
        </div>
      </aside>

      <section className="dashboard-frame">
        <header className="dashboard-topbar">
          <div className="topbar-copy">
            <span className="eyebrow">{meta.eyebrow}</span>
            <h1>{meta.title}</h1>
          </div>

          <div className="status-pills">
            <span className={`status-pill ${sidecarReady ? "good" : "warn"}`}>
              {sidecarReady ? "Sidecar Online" : "Sidecar Offline"}
            </span>
            <span className="status-pill accent">{secondaryStatusLabel}</span>
          </div>
        </header>

        {metaError && <div className="warning-card topbar-warning">{metaError}</div>}

        <main className="dashboard-main">
          <Suspense fallback={<div className="placeholder-card">Loading workspace…</div>}>
            {mode === "tensile" && <TensileScreen meta={workbenchMeta} onNavigate={setMode} />}
            {mode === "wizard" && <WizardScreen meta={workbenchMeta} />}
            {mode === "composer" && <ComposerScreen />}
            {mode === "projects" && (
              <ProjectsScreen meta={workbenchMeta} onNavigate={setMode} />
            )}
            {mode === "settings" && (
              <SettingsScreen contract={plotContract} meta={workbenchMeta} />
            )}
          </Suspense>
        </main>
      </section>
    </div>
  );
}
