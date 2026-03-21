import { useState } from "react";

import { loadComposerProjectFile, loadWizardDataFile, loadWizardProjectFile } from "../lib/project-io";
import { useComposerStore, useWizardStore, useWorkbenchStore } from "../lib/store";
import type { RecentProjectEntry, WorkbenchMeta, WorkbenchRoute } from "../lib/types";
import {
  confirmReplaceComposerSession,
  confirmReplaceWizardSession,
  formatLeaf,
  formatRecentTimestamp,
  getErrorMessage,
  getWizardStepLabel,
  plotRoute,
  templateLabel,
} from "../lib/workbench";

export function ProjectsScreen({
  meta,
  onNavigate,
}: {
  meta: WorkbenchMeta | null;
  onNavigate(route: WorkbenchRoute): void;
}) {
  const wizard = useWizardStore();
  const composer = useComposerStore();
  const recentProjects = useWorkbenchStore((state) => state.recentProjects);
  const rememberProject = useWorkbenchStore((state) => state.rememberProject);
  const [activeRecentId, setActiveRecentId] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [noticeTone, setNoticeTone] = useState<"success" | "warning">("success");
  const latestOutput = wizard.outputs[wizard.outputs.length - 1] ?? null;

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
    setNotice(null);

    try {
      if (entry.mode === "wizard" && entry.kind === "data") {
        const inspected = await loadWizardDataFile(
          useWizardStore.getState(),
          meta,
          entry.path,
        );
        rememberProject({
          mode: "wizard",
          kind: "data",
          path: inspected.input_path,
          title: formatLeaf(inspected.input_path),
          detail: `Data file · ${inspected.sheet_names.length} sheets · ${templateLabel(meta, inspected.inspection.recommendation.template)}`,
        });
        setNoticeTone("success");
        setNotice(`Reopened data file: ${formatLeaf(inspected.input_path)}`);
        onNavigate(plotRoute(useWizardStore.getState().stage));
        return;
      }

      if (entry.mode === "wizard") {
        const payload = await loadWizardProjectFile(
          useWizardStore.getState(),
          meta,
          entry.path,
        );
        rememberProject({
          mode: "wizard",
          kind: "project",
          path: entry.path,
          title: formatLeaf(entry.path),
          detail: `Plot project · ${formatLeaf(payload.wizard.input_path)} · ${payload.wizard.outputs.length} outputs`,
        });
        setNoticeTone("success");
        setNotice(`Reopened plot project: ${formatLeaf(entry.path)}`);
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
      setNoticeTone("success");
      setNotice(`Reopened composer project: ${formatLeaf(entry.path)}`);
      onNavigate("/composer");
    } catch (error) {
      setNoticeTone("warning");
      setNotice(getErrorMessage(error));
    } finally {
      setActiveRecentId(null);
    }
  };

  return (
    <div className="desk-layout recents-layout">
      <section className="desk-main">
        <article className="work-card section-card recents-browser-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Recents</div>
              <h2>Restore work directly from recent files and project sessions</h2>
            </div>
            <span className="signal-tag">{recentProjects.length} remembered</span>
          </div>

          {notice && (
            <div className={noticeTone === "success" ? "success-card" : "warning-card"}>
              {notice}
            </div>
          )}

          <div className="layer-list recents-browser-grid">
            {recentProjects.length === 0 && (
              <div className="placeholder-card">No recent files yet.</div>
            )}

            {recentProjects.map((entry) => (
              <button
                className="layer-item recent-item recent-browser-item"
                disabled={activeRecentId === entry.id}
                key={entry.id}
                onClick={() => void reopenRecent(entry)}
                type="button"
              >
                <strong>{entry.title}</strong>
                <span>{entry.detail}</span>
                <span className="recent-meta">
                  {entry.mode === "wizard" ? "Plot" : "Composer"} ·{" "}
                  {entry.kind === "data" ? "Data file" : "Project file"} · {formatRecentTimestamp(entry.updated_at)}
                </span>
              </button>
            ))}
          </div>
        </article>
      </section>

      <aside className="desk-context recents-context">
        <article className="context-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Current Sessions</div>
              <h3>What is already open</h3>
            </div>
          </div>

          <div className="context-list">
            <div className="context-row">
              <span>Plot file</span>
              <strong>{wizard.inputPath ? formatLeaf(wizard.inputPath) : "Not loaded"}</strong>
            </div>
            <div className="context-row">
              <span>Plot step</span>
              <strong>{getWizardStepLabel(wizard.step)}</strong>
            </div>
            <div className="context-row">
              <span>Composer objects</span>
              <strong>{composer.project.panels.length + composer.project.texts.length}</strong>
            </div>
            <div className="context-row">
              <span>Remembered recents</span>
              <strong>{recentProjects.length}</strong>
            </div>
          </div>
        </article>

        <article className="context-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Latest Export</div>
              <h3>Plot output attached to this session</h3>
            </div>
          </div>

          {latestOutput ? (
            <div className="focus-panel">
              <strong>{formatLeaf(latestOutput)}</strong>
              <span>{wizard.outputs.length} output file(s) remain attached to the current Plot session.</span>
            </div>
          ) : (
            <div className="placeholder-card">No exported plot attached to the current session.</div>
          )}
        </article>
      </aside>
    </div>
  );
}
