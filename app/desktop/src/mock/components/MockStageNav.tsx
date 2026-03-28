import {
  mockStageNavByWorkbench,
  type MockRoute,
} from "../data/mockNavigationData";

type MockStageNavProps = {
  currentRoute: MockRoute;
  compact?: boolean;
};

export function MockStageNav({
  currentRoute,
  compact = false,
}: MockStageNavProps) {
  const items = mockStageNavByWorkbench[currentRoute.workbench];

  return (
    <div className={`mock-stage-nav${compact ? " is-compact" : ""}`}>
      <div className="mock-stage-nav__items" role="tablist" aria-label="Workbench stages">
        {items.map((item) => (
          <a
            key={item.hash}
            className={`mock-stage-nav__item${
              item.id === currentRoute.stage ? " is-active" : ""
            }`}
            href={item.hash}
            aria-label={item.label}
          >
            <strong>{item.label}</strong>
          </a>
        ))}
      </div>
    </div>
  );
}
