import { useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { AppIcon } from "../components/AppIcon";
import {
  loadComposerProjectFile,
  loadWizardDataFile,
  loadWizardProjectFile,
} from "../lib/project-io";
import { useComposerStore, useWizardStore, useWorkbenchStore } from "../lib/store";
import { describeAppearanceMode } from "../lib/themes";
import type {
  RecentProjectEntry,
  WorkbenchMeta,
  WorkbenchRoute,
} from "../lib/types";
import {
  confirmReplaceComposerSession,
  confirmReplaceWizardSession,
  formatLeaf,
  formatRecentTimestamp,
  hasComposerSessionContent,
  hasWizardSessionContent,
  plotRoute,
  templateLabel,
} from "../lib/workbench";

function recentSignal(entry: RecentProjectEntry) {
  return `${entry.mode === "wizard" ? "Plot" : "Composer"} · ${
    entry.kind === "data" ? "Data file" : "Project file"
  }`;
}

export function LaunchpadScreen({
  activeThemePresetName,
  meta,
  sidecarReady,
  onNavigate,
}: {
  activeThemePresetName: string;
  meta: WorkbenchMeta | null;
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
  const rememberProject = useWorkbenchStore((state) => state.rememberProject);
  const [activeRecentId, setActiveRecentId] = useState<string | null>(null);
  const [recentNotice, setRecentNotice] = useState<string | null>(null);
  const [recentNoticeTone, setRecentNoticeTone] = useState<"success" | "warning">("success");

  const hasPlotSession = hasWizardSessionContent({
    inputPath: wizard.inputPath,
    inspection: wizard.inspection,
    template: wizard.template,
    outputs: wizard.outputs,
    exportResult: wizard.exportResult,
  });
  const hasComposerSession = hasComposerSessionContent(composerProject);
  const latestRecent = recentProjects[0] ?? null;

  const reopenRecent = async (entry: RecentProjectEntry) => {
    const wizardState = useWizardStore.getState();
    const composerState = useComposerStore.getState();
    if (
      entry.mode === "wizard" &&
      !confirmReplaceWizardSession(
        {
          inputPath: wizardState.inputPath,
          inspection: wizardState.inspection,
          template: wizardState.template,
          outputs: wizardState.outputs,
          exportResult: wizardState.exportResult,
        },
        formatLeaf(entry.path),
        entry.kind === "data" ? entry.path : undefined,
      )
    ) {
      return;
    }
    if (
      entry.mode === "composer" &&
      !confirmReplaceComposerSession(composerState.project, formatLeaf(entry.path))
    ) {
      return;
    }

    setActiveRecentId(entry.id);
    setRecentNotice(null);

    try {
      if (entry.mode === "wizard" && entry.kind === "data") {
        const inspected = await loadWizardDataFile(useWizardStore.getState(), meta, entry.path);
        rememberProject({
          mode: "wizard",
          kind: "data",
          path: inspected.input_path,
          title: formatLeaf(inspected.input_path),
          detail: `Data file · ${inspected.sheet_names.length} sheets · ${templateLabel(meta, inspected.inspection.recommendation.template)}`,
        });
        setRecentNoticeTone("success");
        setRecentNotice(`Opened ${formatLeaf(inspected.input_path)} in Plot.`);
        onNavigate(plotRoute(useWizardStore.getState().stage));
        return;
      }

      if (entry.mode === "wizard") {
        const payload = await loadWizardProjectFile(useWizardStore.getState(), meta, entry.path);
        rememberProject({
          mode: "wizard",
          kind: "project",
          path: entry.path,
          title: formatLeaf(entry.path),
          detail: `Plot project · ${formatLeaf(payload.wizard.input_path)} · ${payload.wizard.outputs.length} outputs`,
        });
        setRecentNoticeTone("success");
        setRecentNotice(`Restored ${formatLeaf(entry.path)} into Plot.`);
        onNavigate(plotRoute(useWizardStore.getState().stage));
        return;
      }

      const project = await loadComposerProjectFile(useComposerStore.getState(), entry.path);
      rememberProject({
        mode: "composer",
        kind: "project",
        path: entry.path,
        title: formatLeaf(entry.path),
        detail: `Composer project · ${project.panels.length} panels / ${project.texts.length} text blocks`,
      });
      setRecentNoticeTone("success");
      setRecentNotice(`Restored ${formatLeaf(entry.path)} into Composer.`);
      onNavigate("/composer");
    } catch (error) {
      setRecentNoticeTone("warning");
      setRecentNotice(error instanceof Error ? error.message : String(error));
    } finally {
      setActiveRecentId(null);
    }
  };

  return (
    <div className="desk-layout launchpad-workspace">
      <section className="desk-main">
        <article className="work-card section-card launchpad-start-panel">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Start</div>
              <h2>Begin new work or restore an existing session</h2>
            </div>
            <span className={`status-pill ${sidecarReady ? "good" : "warn"}`}>
              {sidecarReady ? "Sidecar Online" : "Sidecar Offline"}
            </span>
          </div>

          <p className="hint-text">
            Plot opens directly into its staged workflow. Composer opens on canvas. Recent files
            and sessions stay one step away.
          </p>

          {recentNotice && (
            <div className={recentNoticeTone === "warning" ? "warning-card" : "success-card"}>
              {recentNotice}
            </div>
          )}

          <div className="launchpad-primary-actions">
            <button
              className="launchpad-action-card launchpad-action-primary"
              onClick={() => onNavigate("/plot/import")}
              type="button"
            >
              <span className="launchpad-action-icon">
                <AppIcon name="plot" />
              </span>
              <span className="launchpad-action-copy">
                <strong>New Plot</strong>
                <span>Import data and continue through import, type, tune, review, and export.</span>
              </span>
            </button>

            <button
              className="launchpad-action-card"
              onClick={() => onNavigate("/composer")}
              type="button"
            >
              <span className="launchpad-action-icon">
                <AppIcon name="composer" />
              </span>
              <span className="launchpad-action-copy">
                <strong>New Composition</strong>
                <span>Open the canvas workspace and start arranging graph PDFs, assets, and text.</span>
              </span>
            </button>

            <button
              className="launchpad-action-card"
              onClick={() =>
                latestRecent ? void reopenRecent(latestRecent) : onNavigate("/tensile")
              }
              type="button"
            >
              <span className="launchpad-action-icon">
                <AppIcon name={latestRecent ? "projects" : "tensile"} />
              </span>
              <span className="launchpad-action-copy">
                <strong>{latestRecent ? "Open Latest Recent" : "Prepare Tensile"}</strong>
                <span>
                  {latestRecent
                    ? `${latestRecent.title} · ${recentSignal(latestRecent)}`
                    : "Prepare raw CSVs or compare prepared workbooks in the tensile workspace."}
                </span>
              </span>
            </button>
          </div>

          <div className="step-actions">
            <button className="ghost-button" onClick={() => onNavigate("/tensile")} type="button">
              Tensile workspace
            </button>
            <button
              className="ghost-button"
              onClick={() => onNavigate("/code-console")}
              type="button"
            >
              Code Console
            </button>
            <button className="ghost-button" onClick={() => onNavigate("/settings")} type="button">
              Settings
            </button>
          </div>
        </article>

        <article className="work-card section-card launchpad-recents-panel">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Recents</div>
              <h2>Recent files and project restores</h2>
            </div>
            <span className="signal-tag">{recentProjects.length} remembered</span>
          </div>

          {recentProjects.length === 0 ? (
            <div className="placeholder-card">No recent files yet.</div>
          ) : (
            <div className="launchpad-recent-list">
              {recentProjects.slice(0, 6).map((entry) => (
                <button
                  className="launchpad-recent-row"
                  disabled={activeRecentId === entry.id}
                  key={entry.id}
                  onClick={() => void reopenRecent(entry)}
                  type="button"
                >
                  <div className="launchpad-recent-row-head">
                    <strong>{entry.title}</strong>
                    <span className="signal-tag">{recentSignal(entry)}</span>
                  </div>
                  <span>{entry.detail}</span>
                  <span className="recent-meta">{formatRecentTimestamp(entry.updated_at)}</span>
                </button>
              ))}
            </div>
          )}
        </article>
      </section>

      <aside className="desk-context launchpad-context">
        <article className="context-card launchpad-session-panel">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Continue</div>
              <h3>Current workspace sessions</h3>
            </div>
          </div>

          {!hasPlotSession && !hasComposerSession && (
            <div className="placeholder-card">No active Plot or Composer session yet.</div>
          )}

          {hasPlotSession && (
            <button
              className="launchpad-session-item"
              onClick={() => onNavigate(plotRoute(wizard.stage))}
              type="button"
            >
              <div className="launchpad-session-head">
                <strong>Plot</strong>
                <span className="signal-tag">{wizard.stage}</span>
              </div>
              <span>{wizard.inputPath ? formatLeaf(wizard.inputPath) : "Current plotting session"}</span>
              <span className="recent-meta">
                {wizard.template ? templateLabel(meta, wizard.template) : "Template pending"}
              </span>
            </button>
          )}

          {hasComposerSession && (
            <button
              className="launchpad-session-item"
              onClick={() => onNavigate("/composer")}
              type="button"
            >
              <div className="launchpad-session-head">
                <strong>Composer</strong>
                <span className="signal-tag">
                  {composerProject.panels.length + composerProject.texts.length} objects
                </span>
              </div>
              <span>Return to the current composition canvas.</span>
              <span className="recent-meta">
                {composerProject.regions.length} regions · {composerProject.panels.length} panels ·{" "}
                {composerProject.texts.length} text blocks
              </span>
            </button>
          )}
        </article>

        <article className="context-card launchpad-status-panel">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Desk Status</div>
              <h3>Lightweight context</h3>
            </div>
          </div>

          <div className="context-list">
            <div className="context-row">
              <span>Appearance</span>
              <strong>{describeAppearanceMode(settings.appearance_mode)}</strong>
            </div>
            <div className="context-row">
              <span>Theme</span>
              <strong>{activeThemePresetName}</strong>
            </div>
            <div className="context-row">
              <span>Sidecar</span>
              <strong>{sidecarReady ? "Online and ready" : "Waiting for Python"}</strong>
            </div>
            <div className="context-row">
              <span>Recents</span>
              <strong>{recentProjects.length}</strong>
            </div>
          </div>
        </article>
      </aside>
    </div>
  );
}
