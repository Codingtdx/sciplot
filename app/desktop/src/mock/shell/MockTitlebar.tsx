import type { MockRoute } from "../data/mockNavigationData";

type MockTitlebarProps = {
  currentRoute: MockRoute;
};

const WINDOW_CONTROLS = ["close", "minimize", "zoom"] as const;

export function MockTitlebar({ currentRoute }: MockTitlebarProps) {
  void currentRoute;

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
    </header>
  );
}
