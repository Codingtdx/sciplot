import { useMemo, useState } from "react";

import { InfoTip } from "../components/InfoTip";
import { healthcheck } from "../lib/api";
import { useComposerStore, useTensileStore, useWizardStore, useWorkbenchStore } from "../lib/store";
import {
  DEFAULT_THEME_PRESET_BY_APPEARANCE,
  THEME_PRESETS,
  describeAppearanceMode,
  themePresetById,
} from "../lib/themes";
import type {
  AppearanceMode,
  PlotContract,
  ThemePresetId,
  WorkbenchMeta,
} from "../lib/types";

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

  const validationRuleCount = contract ? Object.keys(contract.validation_rules).length : 0;
  const activePreset = themePresetById(settings.theme_preset_id) ?? THEME_PRESETS[0];
  const appearanceSummary = useMemo(
    () => `${describeAppearanceMode(settings.appearance_mode)} appearance`,
    [settings.appearance_mode],
  );

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
      wizard: "Plot session reset.",
      tensile: "Tensile workspace reset.",
      composer: "Composer workspace reset.",
      recent: "Recent file history cleared.",
      all: "All workspace state and recent history cleared.",
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

  return (
    <div className="desk-layout single-column settings-layout">
      <section className="desk-main">
        <article className="work-card hero-card settings-hero-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Preferences</div>
              <h2>Theme gallery and runtime controls</h2>
            </div>
            <div className="wizard-inline-chips">
              <span className="signal-tag">{activePreset.name}</span>
              <span className={`status-pill ${sidecarReady ? "good" : "warn"}`}>
                {sidecarReady ? "Sidecar Online" : "Sidecar Offline"}
              </span>
            </div>
          </div>

          <div className="settings-hero-grid">
            <div className="focus-panel">
              <span>Current preset</span>
              <strong>{activePreset.name}</strong>
              <span>{activePreset.description}</span>
            </div>
            <div className="focus-panel">
              <span>Appearance</span>
              <strong>{appearanceSummary}</strong>
              <span>Curated presets are stored locally and restored on the next launch.</span>
            </div>
            <div className="focus-panel">
              <span>Plot frame</span>
              <strong>
                {meta?.global_frame.panel_width_mm ?? 60} x {meta?.global_frame.panel_height_mm ?? 55} mm
              </strong>
              <span>{validationRuleCount} contract-backed validation rule(s).</span>
            </div>
          </div>
        </article>

        <div className="summary-grid settings-summary-grid">
          <article className="work-card section-card settings-theme-gallery">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Theme Gallery</div>
                <h2>Curated presets</h2>
              </div>
              <InfoTip content="Appearance mode chooses light, dark, or system. Theme presets add a curated material language on top." />
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
                <h2>Health and defaults</h2>
              </div>
              <InfoTip content="These controls affect local desktop behavior only. They do not change the plot contract or backend defaults." />
            </div>

            <div className="inspector-stack">
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
                <span>Remember last workspace</span>
              </label>
            </div>
          </article>

          <article className="work-card section-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Maintenance</div>
                <h2>Reset local state</h2>
              </div>
              <InfoTip content="These actions clear local desktop state only. Source data and exported files on disk are untouched." />
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
