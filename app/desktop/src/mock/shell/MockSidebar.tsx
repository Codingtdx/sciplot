import {
  getDefaultHashForWorkbench,
  mockPrimaryNavItems,
  type MockRoute,
} from "../data/mockNavigationData";

type MockSidebarProps = {
  currentRoute: MockRoute;
};

export function MockSidebar({ currentRoute }: MockSidebarProps) {
  return (
    <aside className="mock-sidebar">
      <div className="mock-sidebar__brand">
        <div className="mock-sidebar__brand-mark" aria-hidden="true">
          <span />
          <span />
          <span />
        </div>
        <h1 className="mock-sidebar__brand-title">SciPlot God</h1>
      </div>

      <div className="mock-sidebar__section">
        <nav className="mock-sidebar__nav" aria-label="Primary workbench navigation">
          {mockPrimaryNavItems.map((item) => (
            <a
              key={item.id}
              className={`mock-sidebar__nav-item mock-sidebar__nav-item--${item.id}${
                item.id === currentRoute.workbench ? " is-active" : ""
              }`}
              href={getDefaultHashForWorkbench(item.id)}
              aria-label={item.label}
            >
              <span className="mock-sidebar__nav-icon" aria-hidden="true" />
              <strong>{item.label}</strong>
            </a>
          ))}
        </nav>
      </div>
    </aside>
  );
}
