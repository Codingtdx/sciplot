import type { ReactNode } from "react";

export function MacWindowShell({
  sidebar,
  titlebar,
  children,
}: {
  sidebar: ReactNode;
  titlebar: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="desktop-root">
      <div className="desktop-backdrop" />
      <div className="desktop-window">
        {sidebar}
        <main className="app-main">
          {titlebar}
          <div className="workspace-sheet">{children}</div>
        </main>
      </div>
    </div>
  );
}
