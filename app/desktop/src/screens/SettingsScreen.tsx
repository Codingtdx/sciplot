import { healthcheck } from "../lib/api";
import { InfoTip } from "../components/InfoTip";
import { useComposerStore, useTensileStore, useWizardStore, useWorkbenchStore } from "../lib/store";
import type { PlotContract, WorkbenchMeta } from "../lib/types";
import { useState } from "react";

export function SettingsScreen({
  meta,
  contract,
}: {
  meta: WorkbenchMeta | null;
  contract: PlotContract | null;
}) {
  const sidecarReady = useWizardStore((state) => state.sidecarReady);
  const setSidecarReady = useWizardStore((state) => state.setSidecarReady);
  const resetWizard = useWizardStore((state) => state.reset);
  const resetComposer = useComposerStore((state) => state.reset);
  const resetTensile = useTensileStore((state) => state.reset);
  const composerProject = useComposerStore((state) => state.project);
  const pdfImportMode = useWorkbenchStore((state) => state.pdfImportMode);
  const recentProjects = useWorkbenchStore((state) => state.recentProjects);
  const settings = useWorkbenchStore((state) => state.settings);
  const updateSettings = useWorkbenchStore((state) => state.updateSettings);
  const clearRecentProjects = useWorkbenchStore((state) => state.clearRecentProjects);
  const [checking, setChecking] = useState(false);
  const [maintenanceNotice, setMaintenanceNotice] = useState<string | null>(null);

  const refreshSidecar = async () => {
    setChecking(true);
    try {
      setSidecarReady(await healthcheck());
    } finally {
      setChecking(false);
    }
  };

  const runMaintenance = (action: "wizard" | "tensile" | "composer" | "recent" | "all") => {
    if (action === "wizard" || action === "all") {
      resetWizard();
    }
    if (action === "tensile" || action === "all") {
      resetTensile();
    }
    if (action === "composer" || action === "all") {
      resetComposer();
    }
    if (action === "recent" || action === "all") {
      clearRecentProjects();
    }

    const labels = {
      wizard: "Plot Builder session reset.",
      tensile: "Tensile workspace reset.",
      composer: "Composer workspace reset.",
      recent: "Recent file history cleared.",
      all: "All workspace state and recent history cleared.",
    } as const;

    setMaintenanceNotice(labels[action]);
  };

  const validationRuleCount = contract ? Object.keys(contract.validation_rules).length : 0;

  return (
    <div className="desk-layout single-column">
      <section className="desk-main">
        <div className="summary-grid">
          <article className="work-card section-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Runtime</div>
                <h2>{sidecarReady ? "Python sidecar is online" : "Python sidecar is offline"}</h2>
              </div>
              <InfoTip content="Detection, preview, and export all depend on the sidecar. Recheck here when the desktop app starts before the backend is ready." />
            </div>
            <div className="step-actions">
              <button
                className="primary-button"
                disabled={checking}
                onClick={() => void refreshSidecar()}
                type="button"
              >
                {checking ? "Checking…" : "Check again"}
              </button>
            </div>
            <div className="context-list">
              <div className="context-row">
                <span>Recents</span>
                <strong>{recentProjects.length}</strong>
              </div>
              <div className="context-row">
                <span>PDF import mode</span>
                <strong>{pdfImportMode === "graph" ? "Graph" : "Asset"}</strong>
              </div>
            </div>
          </article>

          <article className="work-card section-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Composer</div>
                <h2>
                  {composerProject.canvas_width_mm} x {composerProject.canvas_height_mm} mm
                </h2>
              </div>
              <InfoTip content="This reflects the current composer project canvas and grid setup." />
            </div>
          </article>

          <article className="work-card section-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Plot frame</div>
                <h2>
                  {meta?.global_frame.panel_width_mm ?? 60} x {meta?.global_frame.panel_height_mm ?? 55} mm standard frame
                </h2>
              </div>
              <InfoTip content="The plot frame is shared by the standard single-panel figure family and is served directly from the plot contract." />
            </div>
            <div className="context-list">
              <div className="context-row">
                <span>Left / right</span>
                <strong>
                  {meta?.global_frame.left_margin_mm ?? 14} / {meta?.global_frame.right_margin_mm ?? 4.5} mm
                </strong>
              </div>
              <div className="context-row">
                <span>Bottom / top</span>
                <strong>
                  {meta?.global_frame.bottom_margin_mm ?? 11} / {meta?.global_frame.top_margin_mm ?? 5.5} mm
                </strong>
              </div>
              <div className="context-row">
                <span>Validation rules</span>
                <strong>{validationRuleCount}</strong>
              </div>
            </div>
          </article>

          <article className="work-card section-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Preferences</div>
                <h2>Theme and defaults</h2>
              </div>
              <InfoTip content="These preferences are stored locally and restored when the desktop app opens again." />
            </div>

            <div className="inspector-stack">
              <label>
                <span className="field-label">Theme</span>
                <select
                  className="field"
                  onChange={(event) =>
                    updateSettings({
                      theme_preference:
                        event.target.value === "light" || event.target.value === "dark"
                          ? event.target.value
                          : "system",
                    })
                  }
                  value={settings.theme_preference}
                >
                  <option value="system">Follow system</option>
                  <option value="light">Light</option>
                  <option value="dark">Dark</option>
                </select>
              </label>

              <label className="toggle-field">
                <input
                  checked={settings.auto_status_poll}
                  onChange={(event) =>
                    updateSettings({ auto_status_poll: event.target.checked })
                  }
                  type="checkbox"
                />
                <span>Auto-refresh sidecar status</span>
              </label>

              <label className="toggle-field">
                <input
                  checked={settings.remember_last_screen}
                  onChange={(event) =>
                    updateSettings({ remember_last_screen: event.target.checked })
                  }
                  type="checkbox"
                />
                <span>Remember last screen</span>
              </label>

              <div className="context-list">
                <div className="context-row">
                  <span>Theme</span>
                  <strong>
                    {settings.theme_preference === "system"
                      ? "Follow system"
                      : settings.theme_preference === "light"
                        ? "Light"
                        : "Dark"}
                  </strong>
                </div>
                <div className="context-row">
                  <span>Auto-refresh</span>
                  <strong>{settings.auto_status_poll ? "On" : "Off"}</strong>
                </div>
                <div className="context-row">
                  <span>Remember screen</span>
                  <strong>{settings.remember_last_screen ? "On" : "Off"}</strong>
                </div>
              </div>
            </div>
          </article>

          <article className="work-card section-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Maintenance</div>
                <h2>Reset local state</h2>
              </div>
              <InfoTip content="These actions only reset the desktop app state and recent history. They do not modify source data or exported files on disk." />
            </div>

            {maintenanceNotice && <div className="success-card">{maintenanceNotice}</div>}

            <div className="step-actions">
              <button className="ghost-button" onClick={() => runMaintenance("wizard")} type="button">
                Reset Plot Builder
              </button>
              <button className="ghost-button" onClick={() => runMaintenance("tensile")} type="button">
                Reset Tensile
              </button>
              <button className="ghost-button" onClick={() => runMaintenance("composer")} type="button">
                Reset Composer
              </button>
              <button className="ghost-button" onClick={() => runMaintenance("recent")} type="button">
                Clear recents
              </button>
              <button className="ghost-button danger-button" onClick={() => runMaintenance("all")} type="button">
                Reset everything
              </button>
            </div>
          </article>
        </div>
      </section>
    </div>
  );
}
