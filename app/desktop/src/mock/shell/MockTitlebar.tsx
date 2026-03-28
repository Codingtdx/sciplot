import { mockRouteMeta, type MockRouteId } from "../data/mockNavigationData";

type MockTitlebarProps = {
  currentRoute: MockRouteId;
};

const WINDOW_CONTROLS = ["close", "minimize", "zoom"] as const;

export function MockTitlebar({ currentRoute }: MockTitlebarProps) {
  const meta = mockRouteMeta[currentRoute];

  return (
    <header className="mock-titlebar">
      <div className="mock-titlebar__controls" aria-hidden="true">
        {WINDOW_CONTROLS.map((control) => (
          <span
            key={control}
            className={`mock-titlebar__control mock-titlebar__control--${control}`}
          />
        ))}
      </div>
      <div className="mock-titlebar__meta">
        <p className="mock-titlebar__eyebrow">SciPlot God Mock Desktop</p>
        <div className="mock-titlebar__titles">
          <strong>{meta.title}</strong>
          <span>{meta.subtitle}</span>
        </div>
      </div>
      <div className="mock-titlebar__status">
        <span className="mock-chip">Static fake data</span>
        <span className="mock-chip mock-chip--accent">{meta.workspaceLabel}</span>
      </div>
    </header>
  );
}

