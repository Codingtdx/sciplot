import { AppIcon } from "../../components/AppIcon";
import { mockStartData } from "../data/mockStartData";

export function MockStart() {
  const { entry, recentFiles } = mockStartData;

  return (
    <section className="mock-screen">
      <header className="mock-screen-header">
        <div>
          <p className="mock-kicker">Workspace home</p>
          <h1 className="mock-screen-title">Calm entry point for opening a new figure session.</h1>
          <p className="mock-screen-copy">
            The home screen stays compact and desktop-like: one dominant launch surface and a dense
            recent-file panel beside it.
          </p>
        </div>
      </header>

      <div className="mock-start-grid">
        <article className="mock-panel mock-entry-panel">
          <div className="mock-panel-head">
            <div>
              <span className="mock-pill is-accent">{entry.sourceBadge}</span>
              <h2>{entry.title}</h2>
            </div>
            <span className="mock-panel-meta">Default landing: Dataset Browser</span>
          </div>

          <p className="mock-panel-copy">{entry.description}</p>

          <div className="mock-launch-surface">
            <div className="mock-launch-copy">
              <div className="mock-launch-icon">
                <AppIcon name="import" />
              </div>
              <div>
                <h3>Open workbook from current review folder</h3>
                <p>{entry.defaultFolder}</p>
              </div>
            </div>

            <div className="mock-button-row">
              <button type="button" className="mock-button is-primary">
                <AppIcon name="folder" />
                {entry.quickActions[0]}
              </button>
              <button type="button" className="mock-button">
                <AppIcon name="template" />
                {entry.quickActions[1]}
              </button>
            </div>

            <div className="mock-chip-row">
              {entry.supportedTypes.map((item) => (
                <span key={item} className="mock-chip">
                  {item}
                </span>
              ))}
            </div>

            <div className="mock-launch-peek">
              <div className="mock-mini-table">
                <div className="mock-mini-table-head">
                  {entry.datasetPeekColumns.map((header) => (
                    <span key={header}>{header}</span>
                  ))}
                </div>
                {entry.datasetPeekRows.map((row) => (
                  <div key={row.join("-")} className="mock-mini-table-row">
                    {row.map((cell) => (
                      <span key={cell}>{cell}</span>
                    ))}
                  </div>
                ))}
              </div>

              <div className="mock-ready-list">
                <p className="mock-sidebar-label">Ready when opened</p>
                <ul>
                  {entry.readyWhenOpened.map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
              </div>
            </div>
          </div>
        </article>

        <aside className="mock-panel mock-recent-panel">
          <div className="mock-panel-head">
            <div>
              <span className="mock-pill">Recent files</span>
              <h2>Return to active datasets without a dashboard detour.</h2>
            </div>
            <span className="mock-panel-meta">{recentFiles.length} items</span>
          </div>

          <div className="mock-recent-list" role="list">
            {recentFiles.map((item) => (
              <button key={item.path} type="button" className="mock-recent-item">
                <span className="mock-recent-main">
                  <strong>{item.title}</strong>
                  <small>{item.subtitle}</small>
                  <span>{item.path}</span>
                </span>
                <span className="mock-recent-meta">
                  <small>{item.meta}</small>
                  <AppIcon name="chevron-right" />
                </span>
              </button>
            ))}
          </div>
        </aside>
      </div>
    </section>
  );
}
