import type { HTMLAttributes, ReactNode } from "react";

import { classNames } from "./utils";

type MacPanelProps = HTMLAttributes<HTMLElement> & {
  as?: "article" | "aside" | "section" | "div";
  tone?: "default" | "emphasis" | "preview";
  children: ReactNode;
};

export function MacPanel({
  as = "article",
  tone = "default",
  className,
  children,
  ...props
}: MacPanelProps) {
  const Component = as;
  return (
    <Component
      className={classNames(
        "surface-card",
        tone === "emphasis" && "emphasis-card",
        tone === "preview" && "preview-card",
        className,
      )}
      {...props}
    >
      {children}
    </Component>
  );
}
