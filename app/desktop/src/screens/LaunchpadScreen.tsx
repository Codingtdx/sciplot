import { useState } from "react";
import { useShallow } from "zustand/react/shallow";

import {
  CompactListRow,
  CompactToolbar,
  EmptyState,
  SectionHeader,
} from "../components/workbench/V2Primitives";
import {
  loadComposerProjectFile,
  loadWizardDataFile,
  loadWizardProjectFile,
} from "../lib/project-io";
import { useComposerStore, useWizardStore, useWorkbenchStore } from "../lib/store";
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
  meta,
  onNavigate,
}: {
  meta: WorkbenchMeta | null;
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

  return (
    <div className="launchpad-v2-home">
      <section className="work-card section-card launchpad-v2-actions">
        <SectionHeader
          kicker="Start"
          title="Quick actions"
          description="Open data or jump directly back into an active workspace."
        />

        {recentNotice && (
          <div className={recentNoticeTone === "warning" ? "warning-card" : "success-card"}>
            {recentNotice}
          </div>
        )}

        <CompactToolbar label="Home quick actions">
          <button className="primary-button prominent" onClick={() => onNavigate("/plot/import")} type="button">
            Open data
          </button>
          <button
            className="ghost-button"
            disabled={!hasPlotSession}
            onClick={() => onNavigate(plotRoute(wizard.stage))}
            type="button"
          >
            Resume last Plot session
          </button>
          <button className="ghost-button" onClick={() => onNavigate("/composer")} type="button">
            Open Composer
          </button>
          <button className="ghost-button" onClick={() => onNavigate("/code-console")} type="button">
            Open Code Console
          </button>
        </CompactToolbar>
      </section>

      <div className="launchpad-v2-grid">
        <section className="work-card section-card launchpad-v2-sessions">
          <SectionHeader
            kicker="Sessions"
            title="Recent sessions"
            description="Continue where you left off."
          />

          {!hasPlotSession && !hasComposerSession && (
            <EmptyState
              description="Start a Plot or Composer workspace to create a resumable session."
              title="No active sessions"
            />
          )}

          {hasPlotSession && (
            <CompactListRow
              onSelect={() => onNavigate(plotRoute(wizard.stage))}
              right={<span className="signal-tag">{wizard.stage}</span>}
              subtitle={wizard.inputPath ? formatLeaf(wizard.inputPath) : "Current plotting session"}
              title={`Plot · ${wizard.template ? templateLabel(meta, wizard.template) : "Template pending"}`}
            />
          )}

          {hasComposerSession && (
            <CompactListRow
              onSelect={() => onNavigate("/composer")}
              right={
                <span className="signal-tag">
                  {composerProject.panels.length + composerProject.texts.length} objects
                </span>
              }
              subtitle={`${composerProject.regions.length} regions · ${composerProject.panels.length} panels · ${composerProject.texts.length} text`}
              title="Composer"
            />
          )}
        </section>

        <section className="work-card section-card launchpad-v2-files">
          <SectionHeader
            kicker="Files"
            title="Recent files"
            description={`${recentProjects.length} remembered`}
          />

          {recentProjects.length === 0 ? (
            <EmptyState
              description="Recent data and project files appear here after opening or exporting."
              title="No recent files"
            />
          ) : (
            <div className="launchpad-v2-list">
              {recentProjects.slice(0, 8).map((entry) => (
                <CompactListRow
                  disabled={activeRecentId === entry.id}
                  key={entry.id}
                  onSelect={() => void reopenRecent(entry)}
                  right={<span className="signal-tag">{recentSignal(entry)}</span>}
                  subtitle={`${entry.detail} · ${formatRecentTimestamp(entry.updated_at)}`}
                  title={entry.title}
                />
              ))}
            </div>
          )}
        </section>
      </div>
    </div>
  );
}
