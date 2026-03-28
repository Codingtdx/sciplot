import {
  mockStartHero,
  mockStartQuickActions,
  mockStartRecentFiles,
} from "../data/mockStartData";

const START_SPARKLINES = [
  "M14 112 C42 96 54 84 72 60 C88 40 118 34 142 38 C162 42 180 54 202 76 C220 94 236 100 250 94",
  "M16 94 C40 102 56 102 78 86 C96 72 114 52 134 48 C154 46 176 56 196 72 C216 86 230 88 250 76",
];

function StartPreviewGraphic() {
  return (
    <div className="mock-start-graphic">
      <div className="mock-start-graphic__cards" aria-hidden="true">
        <div className="mock-start-graphic__mini-card">
          <span>Current dataset</span>
          <strong>PVA-aging-frequency-sweep.xlsx</strong>
        </div>
        <div className="mock-start-graphic__mini-card">
          <span>Best-fit figure</span>
          <strong>Twin-modulus curve</strong>
        </div>
      </div>
      <svg
        className="mock-start-graphic__plot"
        viewBox="0 0 280 160"
        role="img"
        aria-label="Preview of two analytical curves"
      >
        <rect x="0" y="0" width="280" height="160" rx="28" />
        <g className="mock-start-graphic__grid">
          <line x1="28" y1="34" x2="252" y2="34" />
          <line x1="28" y1="70" x2="252" y2="70" />
          <line x1="28" y1="106" x2="252" y2="106" />
          <line x1="52" y1="22" x2="52" y2="132" />
          <line x1="120" y1="22" x2="120" y2="132" />
          <line x1="188" y1="22" x2="188" y2="132" />
        </g>
        {START_SPARKLINES.map((sparkline, index) => (
          <path
            key={sparkline}
            d={sparkline}
            className={`mock-start-graphic__line mock-start-graphic__line--${
              index === 0 ? "primary" : "secondary"
            }`}
          />
        ))}
        <circle cx="142" cy="38" r="4.5" className="mock-start-graphic__dot" />
        <circle cx="196" cy="72" r="4.5" className="mock-start-graphic__dot mock-start-graphic__dot--secondary" />
      </svg>
    </div>
  );
}

function StartRecentFileList() {
  return (
      <div className="mock-panel mock-start__recent-panel">
      <div className="mock-panel__header">
        <div>
          <p className="mock-panel__eyebrow">Recent files</p>
          <h3>Continue where your last figure left off</h3>
        </div>
      </div>
      <div className="mock-start__recent-list">
        {mockStartRecentFiles.map((file) => (
          <div key={file.name} className="mock-start__recent-row">
            <div className="mock-start__recent-copy">
              <strong>{file.name}</strong>
              <span>
                {file.location} · {file.updated}
              </span>
            </div>
            <div className="mock-start__recent-meta">
              <span>{file.size}</span>
              <span className="mock-chip mock-chip--subtle">{file.status}</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export function MockStart() {
  return (
    <section className="mock-screen mock-start">
      <div className="mock-start__grid">
        <div className="mock-panel mock-start__hero">
          <div className="mock-start__hero-copy">
            <p className="mock-panel__eyebrow">{mockStartHero.eyebrow}</p>
            <h2>{mockStartHero.title}</h2>
            <p className="mock-start__hero-description">{mockStartHero.description}</p>
            <div className="mock-start__actions">
              <a className="mock-button mock-button--primary" href="#/plot/refine">
                {mockStartHero.primaryAction}
              </a>
              <a className="mock-button" href="#/plot/template">
                {mockStartHero.secondaryAction}
              </a>
            </div>
            <div className="mock-start__secondary-actions">
              <p className="mock-panel__eyebrow">Support actions</p>
              <div className="mock-start__quick-actions">
              {mockStartQuickActions.map((action) => (
                <div key={action.label} className="mock-start__quick-action">
                  <strong>{action.label}</strong>
                  <span>{action.description}</span>
                </div>
              ))}
            </div>
            </div>
          </div>
          <StartPreviewGraphic />
        </div>

        <StartRecentFileList />
      </div>
    </section>
  );
}
