import type { ButtonHTMLAttributes, ReactNode } from "react";

import { classNames } from "./utils";

type MacButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "ghost";
  icon?: ReactNode;
};

export function MacButton({
  children,
  variant = "secondary",
  icon,
  className,
  type = "button",
  ...props
}: MacButtonProps) {
  return (
    <button
      type={type}
      className={classNames("button", `button-${variant}`, className)}
      {...props}
    >
      {icon ? <span className="button-icon">{icon}</span> : null}
      <span>{children}</span>
    </button>
  );
}
