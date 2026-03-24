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
import {
  CompactToolbar,
  InspectorPanel,
  SectionHeader,
  SettingsRow,
} from "../components/workbench/V2Primitives";

type SettingsCategory =
  | "appearance"
  | "workspace"
  | "runtime"
  | "sidecar"
  | "files"
  | "advanced";

const SETTINGS_CATEGORIES: Array<{
  id: SettingsCategory;
  label: string;
  description: string;
}> = [
  { id: "appearance", label: "Appearance", description: "Theme and visual mode" },
  { id: "workspace", label: "Workspace", description: "Session defaults and recents" },
  { id: "runtime", label: "Runtime", description: "Desktop behavior toggles" },
  { id: "sidecar", label: "Sidecar", description: "Service health and contract info" },
  { id: "files", label: "Files", description: "Managed local files and cache" },
  { id: "advanced", label: "Advanced", description: "Reset and destructive actions" },
];

function themePreviewStyle(presetId: ThemePresetId) {
  const preset = themePresetById(presetId);
  if (!preset) {
    return undefined;
  }
  return {
    background: preset.preview.background,
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
  const [category, setCategory] = useState<SettingsCategory>("appearance");
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
    <div className="settings-v2-layout">
      <aside className="settings-v2-nav">
        <InspectorPanel kicker="Categories" title="Settings">
          <div className="settings-v2-nav-list">
            {SETTINGS_CATEGORIES.map((item) => (
              <button
                className={`settings-v2-nav-item ${category === item.id ? "active" : ""}`}
                key={item.id}
                onClick={() => setCategory(item.id)}
                type="button"
              >
                <strong>{item.label}</strong>
                <span>{item.description}</span>
              </button>
            ))}
          </div>
        </InspectorPanel>
      </aside>

      <section className="settings-v2-detail">
        {category === "appearance" && (
          <section className="work-card section-card">
            <SectionHeader
              kicker="Appearance"
              title="Theme and visual mode"
              description="Compact preset previews and color mode selection."
            />

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

            <div className="settings-v2-theme-list">
              {THEME_PRESETS.map((preset) => {
                const active = settings.theme_preset_id === preset.id;
                return (
                  <button
                    className={`settings-v2-theme-item ${active ? "active" : ""}`}
                    key={preset.id}
                    onClick={() =>
                      updateSettings({
                        appearance_mode: preset.appearance,
                        theme_preset_id: preset.id,
                      })
                    }
                    type="button"
                  >
                    <div className="settings-v2-theme-preview" style={themePreviewStyle(preset.id)}>
                      <div className="settings-v2-theme-surface" style={{ background: preset.preview.surface }} />
                      <div className="settings-v2-theme-chip" style={{ background: preset.preview.chip }} />
                    </div>
                    <div className="settings-v2-theme-copy">
                      <strong>{preset.name}</strong>
                      <span>{preset.description}</span>
                    </div>
                    <span className="signal-tag">{preset.accent}</span>
                  </button>
                );
              })}
            </div>
          </section>
        )}

        {category === "workspace" && (
          <section className="work-card section-card">
            <SectionHeader
              kicker="Workspace"
              title="Session defaults and recents"
              description="Control how workspaces restore between launches."
            />

            <div className="wizard-section-stack">
              <SettingsRow
                control={
                  <input
                    checked={settings.remember_last_screen}
                    onChange={(event) => updateSettings({ remember_last_screen: event.target.checked })}
                    type="checkbox"
                  />
                }
                description="Reopen the last active module on launch."
                label="Remember last workspace"
              />
              <SettingsRow
                control={<strong>{recentProjects.length}</strong>}
                description="Saved data/project entries available in Start."
                label="Recent records"
              />
              <CompactToolbar label="Workspace actions">
                <button className="ghost-button" onClick={() => runMaintenance("recent")} type="button">
                  Clear recents
                </button>
              </CompactToolbar>
            </div>
          </section>
        )}

        {category === "runtime" && (
          <section className="work-card section-card">
            <SectionHeader
              kicker="Runtime"
              title="Desktop behavior"
              description="Compact runtime toggles and state."
            />

            <div className="wizard-section-stack">
              <SettingsRow
                control={
                  <input
                    checked={settings.auto_status_poll}
                    onChange={(event) => updateSettings({ auto_status_poll: event.target.checked })}
                    type="checkbox"
                  />
                }
                description="Refresh sidecar status periodically."
                label="Auto-refresh sidecar status"
              />
              <SettingsRow
                control={<strong>{pdfImportMode === "graph" ? "Graph" : "Asset"}</strong>}
                description="Default Composer PDF import behavior."
                label="Composer PDF import mode"
              />
              <SettingsRow
                control={
                  <strong>
                    {composerProject.canvas_width_mm} x {composerProject.canvas_height_mm} mm
                  </strong>
                }
                description="Current Composer canvas size."
                label="Composer canvas"
              />
            </div>
          </section>
        )}

        {category === "sidecar" && (
          <section className="work-card section-card">
            <SectionHeader
              actions={
                <span className={`status-pill ${sidecarReady ? "good" : "warn"}`}>
                  {sidecarReady ? "Sidecar online" : "Sidecar offline"}
                </span>
              }
              kicker="Sidecar"
              title="Health and contract context"
              description="Service status, refresh control, and shared contract frame."
            />

            <CompactToolbar label="Sidecar actions">
              <button
                className="primary-button"
                disabled={checking}
                onClick={() => void refreshSidecar()}
                type="button"
              >
                {checking ? "Checking…" : "Check sidecar"}
              </button>
            </CompactToolbar>
            <div className="focus-panel">
              <span>Plot frame</span>
              <strong>
                {meta?.global_frame.panel_width_mm ?? 60} x {meta?.global_frame.panel_height_mm ?? 55} mm
              </strong>
              <span>{validationRuleCount} contract-backed validation rule(s).</span>
            </div>
          </section>
        )}

        {category === "files" && (
          <section className="work-card section-card">
            <SectionHeader
              kicker="Files"
              title="Managed local files"
              description="Inspect app-managed templates, exports, and run cache."
            />

            {storageError && <div className="warning-card">{storageError}</div>}

            {managedStorage ? (
              <div className="wizard-section-stack">
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

                <CompactToolbar label="Managed file actions">
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
                </CompactToolbar>
              </div>
            ) : (
              <div className="placeholder-card">
                {storageBusy
                  ? "Loading managed storage…"
                  : "Managed file status appears here when the sidecar is available."}
              </div>
            )}
          </section>
        )}

        {category === "advanced" && (
          <section className="work-card section-card">
            <SectionHeader
              kicker="Advanced"
              title="Maintenance and destructive actions"
              description="Reset states and run full managed-file cleanup."
            />

            {maintenanceNotice && <div className="success-card">{maintenanceNotice}</div>}
            {storageError && <div className="warning-card">{storageError}</div>}

            <div className="wizard-section-stack">
              <SettingsRow
                control={
                  <button className="ghost-button" onClick={() => runMaintenance("wizard")} type="button">
                    Reset Plot
                  </button>
                }
                description="Clear current Plot workspace state."
                label="Plot state"
              />
              <SettingsRow
                control={
                  <button className="ghost-button" onClick={() => runMaintenance("tensile")} type="button">
                    Reset Tensile
                  </button>
                }
                description="Clear current Tensile queue/session state."
                label="Tensile state"
              />
              <SettingsRow
                control={
                  <button className="ghost-button" onClick={() => runMaintenance("composer")} type="button">
                    Reset Composer
                  </button>
                }
                description="Clear current Composer canvas state."
                label="Composer state"
              />

              <CompactToolbar label="Danger actions">
                <button
                  className="ghost-button danger-button"
                  disabled={storageBusy || !sidecarReady}
                  onClick={() => void clearManagedFiles()}
                  type="button"
                >
                  Clean app files
                </button>
                <button
                  className="ghost-button danger-button"
                  onClick={() => runMaintenance("all")}
                  type="button"
                >
                  Reset all
                </button>
              </CompactToolbar>
            </div>
          </section>
        )}
      </section>
    </div>
  );
}
