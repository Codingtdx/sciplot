import { AppIcon } from "../components/AppIcon";
import { MacButton } from "../components/mac/MacButton";
import { MacPanel } from "../components/mac/MacPanel";
import { MacStatusPill } from "../components/mac/MacStatusPill";
import { formatRecentTimestamp } from "../lib/workbench";

export function StartScreen({
  recentItems,
  onOpenDataset,
  onOpenRecentDataset,
  onRevealTemplateFolder,
  actionMessage,
}: {
  recentItems: Array<{
    id: string;
    title: string;
    detail: string;
    path: string;
    updated_at: string;
  }>;
  onOpenDataset: () => void;
  onOpenRecentDataset: (path: string) => void;
  onRevealTemplateFolder: (variant: "example" | "blank") => void;
  actionMessage: string | null;
}) {
  return (
    <section className="workspace-screen start-screen">
      <div className="screen-hero">
        <div>
          <p className="screen-eyebrow">Start</p>
          <h1 className="screen-title">Launch directly into a plotting session.</h1>
          <p className="screen-description">
            Open a dataset, reveal template folders, or jump back into a recent file without
            walking through a dashboard.
          </p>
        </div>
        <div className="hero-actions">
          <MacButton variant="primary" onClick={onOpenDataset} icon={<AppIcon name="import" />}>
            Open dataset
          </MacButton>
          <MacButton
            variant="secondary"
            onClick={() => onRevealTemplateFolder("example")}
            icon={<AppIcon name="folder" />}
          >
            Reveal example templates
          </MacButton>
          <MacButton
            variant="secondary"
            onClick={() => onRevealTemplateFolder("blank")}
            icon={<AppIcon name="folder" />}
          >
            Reveal blank templates
          </MacButton>
        </div>
      </div>

      {actionMessage ? <div className="inline-message">{actionMessage}</div> : null}

      <div className="start-layout">
        <MacPanel tone="emphasis">
          <div className="card-header">
            <MacStatusPill tone="accent">Primary action</MacStatusPill>
            <h3>Start with a real dataset</h3>
          </div>
          <p>
            Plot Import is the first active workspace. It loads the file, confirms dataset
            structure, and carries the result forward into template recommendations and chart
            refinement.
          </p>
          <div className="feature-list">
            <span><AppIcon name="table" /> Large dataset preview</span>
            <span><AppIcon name="template" /> Recommendation-first next step</span>
            <span><AppIcon name="export" /> Inline export in Plot Refine</span>
          </div>
        </MacPanel>

        <MacPanel>
          <div className="card-header">
            <MacStatusPill tone="neutral">Recent datasets</MacStatusPill>
            <h3>Continue from where you left off</h3>
          </div>
          {recentItems.length === 0 ? (
            <div className="empty-panel">
              <p>No recent datasets yet.</p>
              <small>Imported files will appear here once you start using the new plot path.</small>
            </div>
          ) : (
            <div className="recent-list" role="list">
              {recentItems.map((item) => (
                <button
                  key={item.id}
                  type="button"
                  className="recent-item"
                  onClick={() => onOpenRecentDataset(item.path)}
                >
                  <span className="recent-main">
                    <strong>{item.title}</strong>
                    <small>{item.detail || item.path}</small>
                  </span>
                  <span className="recent-meta">
                    <small>{formatRecentTimestamp(item.updated_at)}</small>
                    <AppIcon name="chevron-right" />
                  </span>
                </button>
              ))}
            </div>
          )}
        </MacPanel>
      </div>
    </section>
  );
}
