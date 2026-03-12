import { Suspense, lazy, useEffect, useRef, useState } from "react";

import { getPlotContract, getWorkbenchMeta, healthcheck } from "./lib/api";
import { useComposerStore, useWizardStore, useWorkbenchStore } from "./lib/store";
import { AppMode, NAV_ITEMS, SCREEN_META, getWizardStepLabel } from "./lib/workbench";
import type { PlotContract, WorkbenchMeta } from "./lib/types";

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

export default function App() {
  const persistedScreen = useWorkbenchStore((state) => state.lastScreen);
  const setPersistedScreen = useWorkbenchStore((state) => state.setLastScreen);
  const rememberLastScreen = useWorkbenchStore(
    (state) => state.settings.remember_last_screen,
  );
  const autoStatusPoll = useWorkbenchStore((state) => state.settings.auto_status_poll);
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

  const meta = SCREEN_META[mode];

  let secondaryStatusLabel = `Step ${getWizardStepLabel(wizardStep)}`;
  if (mode === "composer") {
    secondaryStatusLabel = `${composerPanelCount} 图层 / ${composerTextCount} 文字`;
  } else if (mode === "projects") {
    secondaryStatusLabel = `${recentProjectsCount} 条最近记录`;
  } else if (mode === "settings") {
    secondaryStatusLabel = autoStatusPoll ? "Auto Polling" : "Manual Polling";
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
            <span>4.x</span>
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
              <span className="nav-item-icon">{item.icon}</span>
              <span className="nav-item-label">{item.label}</span>
            </button>
          ))}
        </nav>

        <div className="rail-footer">
          <div className={`rail-status-dot ${sidecarReady ? "online" : "offline"}`} />
          <span>{sidecarReady ? "Sidecar Ready" : "Waiting"}</span>
        </div>
      </aside>

      <section className="dashboard-frame">
        <header className="dashboard-topbar">
          <div className="topbar-copy">
            <span className="eyebrow">{meta.eyebrow}</span>
            <h1>{meta.title}</h1>
            <p>{meta.description}</p>
          </div>

          <div className="status-pills">
            <span className="status-pill accent">4.x Workbench</span>
            <span className={`status-pill ${sidecarReady ? "good" : "warn"}`}>
              {sidecarReady ? "Sidecar Online" : "Sidecar Offline"}
            </span>
            <span className="status-pill">{secondaryStatusLabel}</span>
          </div>
        </header>

        {metaError && <div className="warning-card topbar-warning">{metaError}</div>}

        <main className="dashboard-main">
          <Suspense fallback={<div className="placeholder-card">正在载入工作台…</div>}>
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
