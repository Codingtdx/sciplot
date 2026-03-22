import { useEffect, useState } from "react";

import {
  cleanupManagedStorage,
  getManagedStorage,
  healthcheck,
  openPath,
} from "../lib/api";
import {
  useComposerStore,
  useTensileStore,
  useWizardStore,
  useWorkbenchStore,
} from "../lib/store";
import {
  DEFAULT_THEME_PRESET_BY_APPEARANCE,
  THEME_PRESETS,
  themePresetById,
} from "../lib/themes";
import type {
  AppearanceMode,
  ManagedStorageStatus,
  PlotContract,
  ThemePresetId,
  WorkbenchMeta,
} from "../lib/types";
import { getErrorMessage } from "../lib/workbench";

function themePreviewStyle(presetId: ThemePresetId) {
  const preset = themePresetById(presetId);
  if (!preset) {
    return undefined;
  }
  return {
    background: preset.preview.background,
    boxShadow: `0 20px 40px ${preset.preview.glow}`,
  };
}

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
  const [managedStorage, setManagedStorage] = useState<ManagedStorageStatus | null>(null);
  const [storageBusy, setStorageBusy] = useState(false);
  const [storageError, setStorageError] = useState<string | null>(null);

  const validationRuleCount = contract ? Object.keys(contract.validation_rules).length : 0;

  const loadManagedFiles = async () => {
    setStorageBusy(true);
    setStorageError(null);
    try {
      setManagedStorage(await getManagedStorage());
    } catch (error) {
      setStorageError(getErrorMessage(error));
    } finally {
      setStorageBusy(false);
    }
  };

  useEffect(() => {
    if (!sidecarReady) {
      return;
    }
    void loadManagedFiles();
  }, [sidecarReady]);

  const refreshSidecar = async () => {
    setChecking(true);
    try {
      const nextReady = await healthcheck();
      setSidecarReady(nextReady);
      if (nextReady) {
        await loadManagedFiles();
      }
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
      wizard: "Plot session reset.",
      tensile: "Tensile workspace reset.",
      composer: "Composer workspace reset.",
      recent: "Recent file history cleared.",
      all: "Workspace state and recent history cleared.",
    } as const;

    setMaintenanceNotice(labels[action]);
  };

  const selectAppearance = (value: AppearanceMode) => {
    const preset = themePresetById(settings.theme_preset_id);
    if (value === "light" || value === "dark") {
      updateSettings({
        appearance_mode: value,
        theme_preset_id:
          preset?.appearance === value
            ? settings.theme_preset_id
            : DEFAULT_THEME_PRESET_BY_APPEARANCE[value],
      });
      return;
    }
    updateSettings({ appearance_mode: value });
  };

  const openManagedPath = async (path: string) => {
    try {
      await openPath(path);
    } catch (error) {
      setStorageError(getErrorMessage(error));
    }
  };

  const clearManagedFiles = async () => {
    setStorageBusy(true);
    setStorageError(null);
    try {
      const response = await cleanupManagedStorage({ strategy: "all" });
      setManagedStorage(response);
      setMaintenanceNotice(
        `Removed ${response.removed_files} file(s) and ${response.removed_directories} folder(s) from managed storage.`,
      );
    } catch (error) {
      setStorageError(getErrorMessage(error));
    } finally {
      setStorageBusy(false);
    }
  };

  const pruneManagedFiles = async () => {
    setStorageBusy(true);
    setStorageError(null);
    try {
      const response = await cleanupManagedStorage({ strategy: "stale" });
      setManagedStorage(response);
      setMaintenanceNotice(
        `Pruned ${response.removed_files} file(s) and ${response.removed_directories} folder(s) from managed storage.`,
      );
    } catch (error) {
      setStorageError(getErrorMessage(error));
    } finally {
      setStorageBusy(false);
    }
  };

  return (
    <div className="desk-layout settings-layout">
      <section className="desk-main">
        <article className="work-card section-card settings-theme-gallery">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Appearance</div>
              <h2>Theme</h2>
            </div>
          </div>

          <div className="mode-switch theme-mode-switch">
            <button
              className={`mode-button ${settings.appearance_mode === "system" ? "active-tone" : ""}`}
              onClick={() => selectAppearance("system")}
              type="button"
            >
              System
            </button>
            <button
              className={`mode-button ${settings.appearance_mode === "light" ? "active-tone" : ""}`}
              onClick={() => selectAppearance("light")}
              type="button"
            >
              Light
            </button>
            <button
              className={`mode-button ${settings.appearance_mode === "dark" ? "active-tone" : ""}`}
              onClick={() => selectAppearance("dark")}
              type="button"
            >
              Dark
            </button>
          </div>

          <div className="theme-gallery-grid">
            {THEME_PRESETS.map((preset) => {
              const active = settings.theme_preset_id === preset.id;
              return (
                <button
                  className={`theme-preset-card ${active ? "active" : ""}`}
                  key={preset.id}
                  onClick={() =>
                    updateSettings({
                      appearance_mode: preset.appearance,
                      theme_preset_id: preset.id,
                    })
                  }
                  type="button"
                >
                  <div className="theme-preset-preview" style={themePreviewStyle(preset.id)}>
                    <div
                      className="theme-preset-surface"
                      style={{ background: preset.preview.surface }}
                    />
                    <div
                      className="theme-preset-chip"
                      style={{ background: preset.preview.chip }}
                    />
                  </div>
                  <div className="theme-preset-copy">
                    <div className="theme-preset-head">
                      <strong>{preset.name}</strong>
                      <span className="signal-tag">{preset.accent}</span>
                    </div>
                    <span>{preset.description}</span>
                  </div>
                </button>
              );
            })}
          </div>
        </article>

        <article className="work-card section-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Runtime</div>
              <h2>Desktop behavior</h2>
            </div>
            <span className={`status-pill ${sidecarReady ? "good" : "warn"}`}>
              {sidecarReady ? "Sidecar online" : "Sidecar offline"}
            </span>
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
            <div className="context-row">
              <span>Composer canvas</span>
              <strong>
                {composerProject.canvas_width_mm} x {composerProject.canvas_height_mm} mm
              </strong>
            </div>
          </div>

          <div className="step-actions">
            <button
              className="primary-button"
              disabled={checking}
              onClick={() => void refreshSidecar()}
              type="button"
            >
              {checking ? "Checking…" : "Check sidecar"}
            </button>
          </div>

          <div className="summary-grid wizard-tight-grid">
            <label className="toggle-field wizard-option-card">
              <input
                checked={settings.auto_status_poll}
                onChange={(event) =>
                  updateSettings({ auto_status_poll: event.target.checked })
                }
                type="checkbox"
              />
              <span>Auto-refresh sidecar status</span>
            </label>

            <label className="toggle-field wizard-option-card">
              <input
                checked={settings.remember_last_screen}
                onChange={(event) =>
                  updateSettings({ remember_last_screen: event.target.checked })
                }
                type="checkbox"
              />
              <span>Remember last workspace</span>
            </label>
          </div>
        </article>

        <article className="work-card section-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Local Files</div>
              <h2>Managed app files</h2>
            </div>
          </div>

          {storageError && <div className="warning-card">{storageError}</div>}

          {managedStorage ? (
            <>
              <div className="summary-grid wizard-tight-grid">
                <div className="stat-tile">
                  <span>Template files</span>
                  <strong>
                    {managedStorage.example_template_file_count +
                      managedStorage.blank_template_file_count +
                      managedStorage.single_template_file_count}
                  </strong>
                </div>
                <div className="stat-tile">
                  <span>Managed exports</span>
                  <strong>{managedStorage.plot_export_dir_count}</strong>
                </div>
                <div className="stat-tile">
                  <span>Code runs</span>
                  <strong>{managedStorage.code_console_run_dir_count}</strong>
                </div>
                <div className="stat-tile">
                  <span>Status</span>
                  <strong>{storageBusy ? "Working" : "Ready"}</strong>
                </div>
              </div>

              <div className="step-actions">
                <button
                  className="ghost-button"
                  disabled={storageBusy || !sidecarReady}
                  onClick={() => void loadManagedFiles()}
                  type="button"
                >
                  Refresh
                </button>
                <button
                  className="ghost-button"
                  disabled={storageBusy}
                  onClick={() => void openManagedPath(managedStorage.data_root)}
                  type="button"
                >
                  Open app data
                </button>
                <button
                  className="ghost-button"
                  disabled={storageBusy}
                  onClick={() => void openManagedPath(managedStorage.plot_exports_path)}
                  type="button"
                >
                  Open exports
                </button>
                <button
                  className="ghost-button"
                  disabled={storageBusy}
                  onClick={() => void openManagedPath(managedStorage.code_console_runs_path)}
                  type="button"
                >
                  Open run cache
                </button>
                <button
                  className="ghost-button"
                  disabled={storageBusy || !sidecarReady}
                  onClick={() => void pruneManagedFiles()}
                  type="button"
                >
                  Prune stale
                </button>
                <button
                  className="ghost-button danger-button"
                  disabled={storageBusy || !sidecarReady}
                  onClick={() => void clearManagedFiles()}
                  type="button"
                >
                  Clean app files
                </button>
              </div>

              <details className="wizard-details">
                <summary>Managed paths</summary>
                <div className="wizard-details-body">
                  <div>Templates: {managedStorage.example_templates_path}</div>
                  <div>Blank templates: {managedStorage.blank_templates_path}</div>
                  <div>Managed exports: {managedStorage.plot_exports_path}</div>
                  <div>Code runs: {managedStorage.code_console_runs_path}</div>
                </div>
              </details>
            </>
          ) : (
            <div className="placeholder-card">
              {storageBusy
                ? "Loading managed storage…"
                : "Managed file status appears here when the sidecar is available."}
            </div>
          )}
        </article>

        <article className="work-card section-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Maintenance</div>
              <h2>Reset workspace state</h2>
            </div>
          </div>

          {maintenanceNotice && <div className="success-card">{maintenanceNotice}</div>}

          <div className="step-actions">
            <button className="ghost-button" onClick={() => runMaintenance("wizard")} type="button">
              Reset Plot
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
            <button
              className="ghost-button danger-button"
              onClick={() => runMaintenance("all")}
              type="button"
            >
              Reset all
            </button>
          </div>
        </article>
      </section>

      <aside className="desk-context settings-context">
        <article className="context-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Contract</div>
              <h3>Shared frame</h3>
            </div>
          </div>

          <div className="wizard-section-stack">
            <div className="focus-panel">
              <span>Plot frame</span>
              <strong>
                {meta?.global_frame.panel_width_mm ?? 60} x {meta?.global_frame.panel_height_mm ?? 55} mm
              </strong>
              <span>{validationRuleCount} contract-backed validation rule(s).</span>
            </div>
          </div>
        </article>
      </aside>
    </div>
  );
}
