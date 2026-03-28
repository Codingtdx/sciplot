import type { ReactNode } from "react";

export function MacInspectorSection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="inspector-section">
      <h4>{title}</h4>
      {children}
    </section>
  );
}
