import type { ReactNode } from "react";

import { type MockRoute } from "../data/mockNavigationData";
import { MockSidebar } from "./MockSidebar";
import { MockTitlebar } from "./MockTitlebar";

type MockShellProps = {
  currentRoute: MockRoute;
  children: ReactNode;
};

export function MockShell({ currentRoute, children }: MockShellProps) {
  return (
    <div className="mock-desktop">
      <div className="mock-desktop__window" data-workbench={currentRoute.workbench}>
        <MockTitlebar currentRoute={currentRoute} />
        <div className="mock-desktop__body">
          <MockSidebar currentRoute={currentRoute} />
          <main className="mock-desktop__workspace">{children}</main>
        </div>
      </div>
    </div>
  );
}
