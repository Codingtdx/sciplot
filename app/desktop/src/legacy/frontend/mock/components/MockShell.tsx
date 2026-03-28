import type { ReactNode } from "react";

import { AppIcon } from "../../components/AppIcon";
import { mockPinnedCollections, mockSidebarNotes, mockTitlebarShortcuts } from "../data/mockNavigationData";
import { MOCK_ROUTES, type MockRouteId, mockRouteById } from "../mock-routes";

export function MockShell({
  activeRoute,
  onNavigate,
  children,
}: {
  activeRoute: MockRouteId;
  onNavigate: (routeId: MockRouteId) => void;
  children: ReactNode;
}) {
  const active = mockRouteById(activeRoute);

  return (
    <div className="mock-desktop">
      <div className="mock-desktop-wallpaper" />
      <div className="mock-window-frame">
        <aside className="mock-sidebar">
          <div className="mock-brand">
            <div className="mock-brand-mark">
              <AppIcon name="spark" />
            </div>
            <div>
              <p className="mock-kicker">SciPlot God</p>
              <h1 className="mock-brand-title">Design Review</h1>
            </div>
          </div>

          <div className="mock-sidebar-group">
            <p className="mock-sidebar-label">Workspaces</p>
            <nav className="mock-sidebar-nav" aria-label="Mock workspaces">
              {MOCK_ROUTES.map((route) => (
                <button
                  key={route.id}
                  type="button"
                  className={`mock-nav-item${route.id === activeRoute ? " is-active" : ""}`}
                  onClick={() => onNavigate(route.id)}
                >
                  <span className="mock-nav-icon">
                    <AppIcon name={route.icon} />
                  </span>
                  <span className="mock-nav-copy">
                    <strong>{route.navLabel}</strong>
                    <small>{route.navDescription}</small>
                  </span>
                </button>
              ))}
            </nav>
          </div>

          <div className="mock-sidebar-group">
            <p className="mock-sidebar-label">Pinned context</p>
            <div className="mock-sidebar-card-list">
              {mockPinnedCollections.map((item) => (
                <article key={item.label} className="mock-sidebar-card">
                  <span>{item.label}</span>
                  <strong>{item.value}</strong>
                </article>
              ))}
            </div>
          </div>

          <div className="mock-sidebar-footer">
            {mockSidebarNotes.map((item) => (
              <p key={item}>{item}</p>
            ))}
          </div>
        </aside>

        <div className="mock-main">
          <header className="mock-titlebar">
            <div className="mock-traffic-lights" aria-hidden="true">
              <span className="mock-traffic-light close" />
              <span className="mock-traffic-light minimize" />
              <span className="mock-traffic-light zoom" />
            </div>
            <div className="mock-titlebar-copy">
              <span className="mock-kicker">{active.eyebrow}</span>
              <h2>{active.title}</h2>
            </div>
            <div className="mock-titlebar-search">
              <AppIcon name="refresh" />
              <span>{mockTitlebarShortcuts.join("  ·  ")}</span>
            </div>
            <div className="mock-titlebar-chips">
              <span className="mock-chip is-accent">High-fidelity mock</span>
              <span className="mock-chip">Static data</span>
            </div>
          </header>

          <main className="mock-workspace">{children}</main>
        </div>
      </div>
    </div>
  );
}
