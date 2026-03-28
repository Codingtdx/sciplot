import {
  mockNavigationItems,
  type MockRouteId,
} from "../data/mockNavigationData";

type MockSidebarProps = {
  currentRoute: MockRouteId;
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
        <div>
          <p className="mock-sidebar__brand-eyebrow">Desktop redesign</p>
          <h1 className="mock-sidebar__brand-title">SciPlot God</h1>
        </div>
      </div>

      <p className="mock-sidebar__group-label">Sections</p>
      <nav className="mock-sidebar__nav" aria-label="Product navigation">
        {mockNavigationItems.map((item) => (
          <a
            key={item.id}
            className={`mock-sidebar__nav-item${
              item.id === currentRoute ? " is-active" : ""
            }`}
            href={item.hash}
          >
            <div className="mock-sidebar__nav-copy">
              <span className="mock-sidebar__nav-eyebrow">{item.eyebrow}</span>
              <strong>{item.label}</strong>
              <span>{item.description}</span>
            </div>
          </a>
        ))}
      </nav>

      <div className="mock-sidebar__focus">
        <p className="mock-sidebar__focus-eyebrow">Pinned workspace</p>
        <strong>Single-figure desktop mock</strong>
        <span>
          Static preview-only shell with local data, stable product sections,
          and no production wiring.
        </span>
      </div>
    </aside>
  );
}
