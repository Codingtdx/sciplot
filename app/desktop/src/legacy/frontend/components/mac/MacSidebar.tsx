import { AppIcon } from "../AppIcon";
import type { ActiveRoute, NavItem } from "../../app-shell";

import { classNames } from "./utils";

export function MacSidebar({
  items,
  activeRoute,
  footer,
  onNavigate,
}: {
  items: NavItem[];
  activeRoute: ActiveRoute;
  footer: string;
  onNavigate: (route: ActiveRoute) => void;
}) {
  return (
    <aside className="app-sidebar">
      <div className="sidebar-header">
        <div className="brand-mark">
          <AppIcon name="spark" />
        </div>
        <div>
          <p className="sidebar-eyebrow">SciPlot</p>
          <h1 className="sidebar-title">Desktop</h1>
        </div>
      </div>
      <nav className="sidebar-nav" aria-label="Primary">
        {items.map((item) => (
          <button
            key={item.route}
            type="button"
            className={classNames("nav-item", activeRoute === item.route && "nav-item-active")}
            onClick={() => onNavigate(item.route)}
          >
            <AppIcon name={item.icon} />
            <span className="nav-copy">
              <strong>{item.label}</strong>
              <small>{item.description}</small>
            </span>
          </button>
        ))}
      </nav>
      <div className="sidebar-footer">
        <p>{footer}</p>
      </div>
    </aside>
  );
}
