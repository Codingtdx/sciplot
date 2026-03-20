import { AppIcon } from "../components/AppIcon";
import { useComposerStore, useWizardStore, useWorkbenchStore } from "../lib/store";
import { useShallow } from "zustand/react/shallow";
import type { WorkbenchRoute } from "../lib/types";
import {
  WORKSPACE_ITEMS,
  formatRecentTimestamp,
  hasComposerSessionContent,
  hasWizardSessionContent,
  plotRoute,
} from "../lib/workbench";

export function LaunchpadScreen({
  sidecarReady,
  onNavigate,
}: {
  sidecarReady: boolean;
  onNavigate(route: WorkbenchRoute): void;
}) {
  const wizard = useWizardStore(
    useShallow((state) => ({
      exportResult: state.exportResult,
      inputPath: state.inputPath,
      inspection: state.inspection,
      outputs: state.outputs,
      stage: state.stage,
      template: state.template,
    })),
  );
  const composerProject = useComposerStore((state) => state.project);
  const recentProjects = useWorkbenchStore((state) => state.recentProjects);
  const settings = useWorkbenchStore((state) => state.settings);
  const updateSettings = useWorkbenchStore((state) => state.updateSettings);

  const hasPlotSession = hasWizardSessionContent({
    inputPath: wizard.inputPath,
    inspection: wizard.inspection,
    template: wizard.template,
    outputs: wizard.outputs,
    exportResult: wizard.exportResult,
  });
  const hasComposerSession = hasComposerSessionContent(composerProject);

  return (
    <div className="launchpad-shell">
      <section className="launchpad-hero hero-card work-card">
        <div className="launchpad-hero-copy">
          <span className="eyebrow">CodeGod Desktop 6.0</span>
          <h1>Start in the right workspace</h1>
          <p>
            Plot now moves step by step, while Tensile and Composer open in their own focused
            studios.
          </p>
        </div>

        <div className="launchpad-meta">
          <div className="workspace-chip-row">
            <span className={`status-pill ${sidecarReady ? "good" : "warn"}`}>
              {sidecarReady ? "Sidecar Online" : "Sidecar Offline"}
            </span>
            <span className="status-pill accent">
              {settings.theme_preference === "system"
                ? "System theme"
                : settings.theme_preference === "dark"
                  ? "Dark theme"
                  : "Light theme"}
            </span>
          </div>

          <div className="launchpad-theme-switch">
            <button
              className={`ghost-button ${settings.theme_preference === "light" ? "active-tone" : ""}`}
              onClick={() => updateSettings({ theme_preference: "light" })}
              type="button"
            >
              Light
            </button>
            <button
              className={`ghost-button ${settings.theme_preference === "dark" ? "active-tone" : ""}`}
              onClick={() => updateSettings({ theme_preference: "dark" })}
              type="button"
            >
              Dark
            </button>
            <button
              className={`ghost-button ${settings.theme_preference === "system" ? "active-tone" : ""}`}
              onClick={() => updateSettings({ theme_preference: "system" })}
              type="button"
            >
              System
            </button>
          </div>

          <div className="hero-actions">
            <button className="primary-button" onClick={() => onNavigate("/plot/import")} type="button">
              New plot
            </button>
            {hasPlotSession && (
              <button
                className="ghost-button"
                onClick={() => onNavigate(plotRoute(wizard.stage))}
                type="button"
              >
                Resume plot session
              </button>
            )}
            {hasComposerSession && (
              <button className="ghost-button" onClick={() => onNavigate("/composer")} type="button">
                Resume composer
              </button>
            )}
          </div>
        </div>
      </section>

      <section className="launchpad-grid">
        {WORKSPACE_ITEMS.map((item) => {
          const route =
            item.workspace === "plot"
              ? hasPlotSession
                ? plotRoute(wizard.stage)
                : "/plot/import"
              : item.workspace === "tensile"
                ? "/tensile"
                : item.workspace === "composer"
                  ? "/composer"
                  : item.workspace === "recents"
                    ? "/recents"
                    : "/settings";
          return (
            <button
              className="launchpad-card work-card"
              key={item.workspace}
              onClick={() => onNavigate(route)}
              type="button"
            >
              <div className="launchpad-card-head">
                <span className="launchpad-card-icon">
                  <AppIcon name={item.icon} />
                </span>
                <span className="signal-tag">{item.label}</span>
              </div>
              <strong>{item.label}</strong>
              <span>
                {item.workspace === "plot" &&
                  "Import data, confirm the chart family, and export a polished figure bundle."}
                {item.workspace === "tensile" &&
                  "Prepare replicate CSVs, queue workbook comparisons, and hand them off to Plot."}
                {item.workspace === "composer" &&
                  "Arrange graphs, assets, and text on the 180 x 170 mm composition canvas."}
                {item.workspace === "recents" &&
                  "Browse recent data files and project files without reopening the full workspace first."}
                {item.workspace === "settings" &&
                  "Change theme, watch runtime health, and clear local workspace state."}
              </span>
            </button>
          );
        })}
      </section>

      <section className="launchpad-recents context-card">
        <div className="panel-heading">
          <div>
            <div className="card-kicker">History</div>
            <h2>Recent files</h2>
          </div>
          <button className="ghost-button" onClick={() => onNavigate("/recents")} type="button">
            Open recents
          </button>
        </div>

        {recentProjects.length === 0 ? (
          <div className="placeholder-card">No recent files yet.</div>
        ) : (
          <div className="launchpad-recent-list">
            {recentProjects.slice(0, 4).map((entry) => (
              <button
                className="launchpad-recent-item"
                key={entry.id}
                onClick={() => onNavigate("/recents")}
                type="button"
              >
                <strong>{entry.title}</strong>
                <span>{entry.detail}</span>
                <span className="recent-meta">{formatRecentTimestamp(entry.updated_at)}</span>
              </button>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
