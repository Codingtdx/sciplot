import { useEffect, useState } from "react";

import { getPlotContract, getWorkbenchMeta, healthcheck } from "./lib/api";
import { useComposerStore, useWizardStore, useWorkbenchStore } from "./lib/store";
import { ComposerScreen } from "./screens/ComposerScreen";
import { ProjectsScreen } from "./screens/ProjectsScreen";
import { SettingsScreen } from "./screens/SettingsScreen";
import { WizardScreen } from "./screens/WizardScreen";
import { AppMode, NAV_ITEMS, SCREEN_META, getWizardStepLabel } from "./lib/workbench";
import type { PlotContract, WorkbenchMeta } from "./lib/types";

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

  useEffect(() => {
    let cancelled = false;

    async function loadWorkbenchData() {
      try {
        const [meta, contract] = await Promise.all([getWorkbenchMeta(), getPlotContract()]);
        if (!cancelled) {
          setWorkbenchMeta(meta);
          setPlotContract(contract);
          setMetaError(null);
        }
      } catch (error) {
        if (!cancelled) {
          setMetaError(error instanceof Error ? error.message : String(error));
        }
      }
    }

    void loadWorkbenchData();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    let intervalId: number | undefined;

    async function check() {
      const ok = await healthcheck();
      if (!cancelled) {
        setSidecarReady(ok);
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
          {mode === "wizard" && <WizardScreen meta={workbenchMeta} />}
          {mode === "composer" && <ComposerScreen />}
          {mode === "projects" && (
            <ProjectsScreen meta={workbenchMeta} onNavigate={setMode} />
          )}
          {mode === "settings" && (
            <SettingsScreen contract={plotContract} meta={workbenchMeta} />
          )}
        </main>
      </section>
    </div>
  );
}
