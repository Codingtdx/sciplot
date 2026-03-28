import type { ReactNode } from "react";

import { classNames } from "./utils";

export function MacStatusPill({
  tone,
  children,
}: {
  tone: "neutral" | "accent" | "success" | "warning";
  children: ReactNode;
}) {
  return <span className={classNames("status-pill", `status-pill-${tone}`)}>{children}</span>;
}
