import type { ReactNode } from "react";

import { type MockRouteId } from "../data/mockNavigationData";
import { MockSidebar } from "./MockSidebar";
import { MockTitlebar } from "./MockTitlebar";

type MockShellProps = {
  currentRoute: MockRouteId;
  children: ReactNode;
};

export function MockShell({ currentRoute, children }: MockShellProps) {
  return (
    <div className="mock-desktop">
      <div className="mock-desktop__window">
        <MockTitlebar currentRoute={currentRoute} />
        <div className="mock-desktop__body">
          <MockSidebar currentRoute={currentRoute} />
          <main className="mock-desktop__workspace">{children}</main>
        </div>
      </div>
    </div>
  );
}

