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
  WorkbenchWorkspace,
} from "../lib/types";
import {
  WORKSPACE_ITEMS,
  confirmReplaceComposerSession,
  confirmReplaceWizardSession,
  formatLeaf,
  formatRecentTimestamp,
  hasComposerSessionContent,
  hasWizardSessionContent,
  plotRoute,
  templateLabel,
} from "../lib/workbench";

const WORKSPACE_COPY: Record<
  Exclude<WorkbenchWorkspace, "launchpad">,
  {
    eyebrow: string;
    description: string;
    accent: string;
    signal: string;
  }
> = {
  plot: {
    eyebrow: "Guided Flow",
    description: "Import data, confirm the recommended chart family, tune the essentials, and export.",
    accent: "Recommendation-first",
    signal: "Staged figure flow",
  },
  tensile: {
    eyebrow: "Materials Desk",
    description: "Prepare raw CSVs, queue workbook comparisons, and hand the result off to Plot.",
    accent: "Two task cards",
    signal: "Prepare + compare",
  },
  composer: {
    eyebrow: "Canvas Studio",
    description: "Arrange graphs, assets, and text on the 180 x 170 mm composition canvas.",
    accent: "Canvas-first",
    signal: "Studio layout",
  },
  recents: {
    eyebrow: "Asset Browser",
    description: "Browse recent inputs and project files, then reopen them directly from one surface.",
    accent: "Direct reopen",
    signal: "Fast restore",
  },
  settings: {
    eyebrow: "Theme Gallery",
    description: "Switch appearance modes, pick a curated preset, and keep runtime settings tidy.",
    accent: "Curated presets",
    signal: "Appearance control",
  },
};

function launchRouteForWorkspace(
  workspace: WorkbenchWorkspace,
  hasPlotSession: boolean,
  wizardStage: ReturnType<typeof useWizardStore.getState>["stage"],
) {
  if (workspace === "plot") {
    return hasPlotSession ? plotRoute(wizardStage) : "/plot/import";
  }
  if (workspace === "tensile") {
    return "/tensile";
  }
  if (workspace === "composer") {
    return "/composer";
  }
  if (workspace === "recents") {
    return "/recents";
  }
  return "/settings";
}

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

  const launchStats = [
    {
      label: "Appearance",
      value: `${describeAppearanceMode(settings.appearance_mode)} / ${activeThemePresetName}`,
    },
    {
      label: "Sidecar",
      value: sidecarReady ? "Online and ready" : "Offline until Python reconnects",
    },
    {
      label: "Sessions",
      value: `${Number(hasPlotSession) + Number(hasComposerSession)} active`,
    },
    {
      label: "Recents",
      value: `${recentProjects.length} files remembered`,
    },
  ];

  return (
    <div className="launchpad-shell">
      <section className="launchpad-hero hero-card work-card">
        <div className="launchpad-hero-main">
          <div className="launchpad-hero-copy">
            <span className="eyebrow">CodeGod Desktop 6.5</span>
            <h1>Work in focused studios, not crowded admin panels.</h1>
            <p>
              Plot stays recommendation-first. Tensile prepares inputs without hijacking Plot.
              Composer keeps the canvas in the center. The whole desktop now carries a theme
              gallery instead of a single light or dark toggle.
            </p>

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
                  Resume plot
                </button>
              )}
              {hasComposerSession && (
                <button className="ghost-button" onClick={() => onNavigate("/composer")} type="button">
                  Resume composer
                </button>
              )}
              <button className="ghost-button" onClick={() => onNavigate("/settings")} type="button">
                Theme gallery
              </button>
            </div>
          </div>

          <div className="launchpad-hero-visual" aria-hidden="true">
            <div className="launchpad-visual-card launchpad-visual-primary">
              <span className="signal-tag">Plot</span>
              <strong>Import → Type → Tune</strong>
              <div className="launchpad-visual-lines">
                <span />
                <span />
                <span />
              </div>
            </div>
            <div className="launchpad-visual-stack">
              <div className="launchpad-visual-card launchpad-visual-secondary">
                <span className="signal-tag">Tensile</span>
                <strong>Prepare raw CSVs</strong>
              </div>
              <div className="launchpad-visual-card launchpad-visual-tertiary">
                <span className="signal-tag">Composer</span>
                <strong>Canvas-first studio</strong>
              </div>
            </div>
          </div>
        </div>

        <div className="launchpad-stat-grid">
          {launchStats.map((item) => (
            <div className="launchpad-stat-card" key={item.label}>
              <span>{item.label}</span>
              <strong>{item.value}</strong>
            </div>
          ))}
        </div>
      </section>

      <section className="launchpad-grid">
        {WORKSPACE_ITEMS.map((item) => {
          const route = launchRouteForWorkspace(item.workspace, hasPlotSession, wizard.stage);
          const cardCopy = WORKSPACE_COPY[item.workspace as Exclude<WorkbenchWorkspace, "launchpad">];
          return (
            <button
              className="launchpad-card work-card"
              key={item.workspace}
              onClick={() => onNavigate(route)}
              type="button"
            >
              <div className="launchpad-card-preview">
                <div className="launchpad-card-head">
                  <span className="launchpad-card-icon">
                    <AppIcon name={item.icon} />
                  </span>
                  <span className="signal-tag">{cardCopy.eyebrow}</span>
                </div>
                <div className="launchpad-card-sparkline">
                  <span />
                  <span />
                  <span />
                </div>
              </div>

              <div className="launchpad-card-body">
                <strong>{item.label}</strong>
                <span>{cardCopy.description}</span>
              </div>

              <div className="launchpad-card-foot">
                <span>{cardCopy.accent}</span>
                <strong>{cardCopy.signal}</strong>
              </div>
            </button>
          );
        })}
      </section>

      <section className="launchpad-recents context-card">
        <div className="panel-heading">
          <div>
            <div className="card-kicker">Recent Assets</div>
            <h2>Reopen directly from Launchpad</h2>
          </div>
          <div className="step-actions">
            <span className="signal-tag">{recentProjects.length} remembered</span>
            <button className="ghost-button" onClick={() => onNavigate("/recents")} type="button">
              Browse all
            </button>
          </div>
        </div>

        {recentNotice && (
          <div className={recentNoticeTone === "warning" ? "warning-card" : "success-card"}>
            {recentNotice}
          </div>
        )}

        {recentProjects.length === 0 ? (
          <div className="placeholder-card">No recent files yet.</div>
        ) : (
          <div className="launchpad-recent-grid">
            {recentProjects.slice(0, 6).map((entry) => (
              <button
                className="launchpad-recent-item"
                disabled={activeRecentId === entry.id}
                key={entry.id}
                onClick={() => void reopenRecent(entry)}
                type="button"
              >
                <div className="launchpad-recent-head">
                  <strong>{entry.title}</strong>
                  <span className="signal-tag">{recentSignal(entry)}</span>
                </div>
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
