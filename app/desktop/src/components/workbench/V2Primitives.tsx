import type { ReactNode } from "react";

import { AppIcon, type AppIconName } from "../AppIcon";

type RailItem = {
  id: string;
  label: string;
  icon: AppIconName;
  active?: boolean;
  onSelect(): void;
};

type CommandAction = {
  id: string;
  label: string;
  kind?: "primary" | "ghost";
  disabled?: boolean;
  onSelect(): void;
};

type SegmentOption<T extends string> = {
  id: T;
  label: string;
  disabled?: boolean;
};

type StepRailStatus = "complete" | "current" | "upcoming" | "disabled";

export type StepRailItem = {
  id: string;
  label: string;
  hint: string;
  status: StepRailStatus;
  onSelect?: (() => void) | null;
};

export function WorkbenchShell({
  rail,
  commandBar,
  content,
  statusBar,
  className = "",
}: {
  rail: ReactNode;
  commandBar: ReactNode;
  content: ReactNode;
  statusBar?: ReactNode;
  className?: string;
}) {
  return (
    <div className={`app-shell-v2 ${className}`.trim()}>
      {rail}
      <div className="wb-workspace">
        {commandBar}
        {content}
        {statusBar}
      </div>
    </div>
  );
}

export function ContentPane({
  className = "",
  children,
}: {
  className?: string;
  children: ReactNode;
}) {
  return <main className={`wb-content-pane wb-scroll-root ${className}`.trim()}>{children}</main>;
}

export function SectionHeader({
  kicker,
  title,
  description,
  actions,
}: {
  kicker?: string;
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <header className="wb-section-header">
      <div className="wb-section-copy">
        {kicker ? <span className="wb-panel-kicker">{kicker}</span> : null}
        <h2>{title}</h2>
        {description ? <p>{description}</p> : null}
      </div>
      {actions ? <div className="wb-section-actions">{actions}</div> : null}
    </header>
  );
}

export function IconRail({
  brandLabel,
  railLabel = "Workbench navigation",
  items,
  footer,
  onBrandSelect,
  variant = "icon",
}: {
  brandLabel: string;
  railLabel?: string;
  items: RailItem[];
  footer?: ReactNode;
  onBrandSelect(): void;
  variant?: "icon" | "text";
}) {
  const showLabels = variant === "text";
  return (
    <aside className={`wb-icon-rail ${showLabels ? "text" : ""}`.trim()} aria-label={railLabel}>
      <button
        className={`wb-rail-brand ${showLabels ? "text" : ""}`.trim()}
        onClick={onBrandSelect}
        title={brandLabel}
        type="button"
      >
        <span className="wb-rail-brand-mark">
          <AppIcon name="spark" />
        </span>
        {showLabels ? <span className="wb-rail-label">{brandLabel}</span> : <span className="wb-sr-only">{brandLabel}</span>}
      </button>

      <nav className="wb-rail-nav" aria-label="Modules">
        {items.map((item) => (
          <button
            aria-current={item.active ? "page" : undefined}
            className={`wb-rail-item ${showLabels ? "text" : ""} ${item.active ? "active" : ""}`.trim()}
            key={item.id}
            onClick={item.onSelect}
            title={item.label}
            type="button"
          >
            <AppIcon name={item.icon} />
            {showLabels ? <span className="wb-rail-label">{item.label}</span> : <span className="wb-sr-only">{item.label}</span>}
          </button>
        ))}
      </nav>

      {footer && <div className="wb-rail-footer">{footer}</div>}
    </aside>
  );
}

export function CommandBar({
  moduleLabel,
  moduleTitle,
  objectLabel,
  objectValue,
  sessionLabel,
  actions,
  runtimeStatusLabel,
  runtimeTone = "neutral",
}: {
  moduleLabel: string;
  moduleTitle: string;
  objectLabel: string;
  objectValue: string;
  sessionLabel?: string;
  actions: CommandAction[];
  runtimeStatusLabel: string;
  runtimeTone?: "good" | "warn" | "neutral";
}) {
  return (
    <header className="wb-command-bar">
      <div className="wb-command-leading">
        <div className="wb-command-module">
          <span className="wb-command-meta">{moduleLabel}</span>
          <strong>{moduleTitle}</strong>
        </div>
        <div className="wb-command-context">
          <span className="wb-command-meta">{objectLabel}</span>
          <strong title={objectValue}>{objectValue}</strong>
          {sessionLabel ? <span className="wb-command-subtle">{sessionLabel}</span> : null}
        </div>
      </div>

      <div className="wb-command-actions">
        {actions.map((action) => (
          <button
            className={action.kind === "primary" ? "primary-button" : "ghost-button"}
            disabled={action.disabled}
            key={action.id}
            onClick={action.onSelect}
            type="button"
          >
            {action.label}
          </button>
        ))}
        <span className={`wb-runtime-pill ${runtimeTone}`}>{runtimeStatusLabel}</span>
      </div>
    </header>
  );
}

export function CompactToolbar({
  label,
  children,
}: {
  label?: string;
  children: ReactNode;
}) {
  return (
    <div aria-label={label} className="wb-toolbar" role={label ? "toolbar" : undefined}>
      {children}
    </div>
  );
}

export function InspectorPanel({
  title,
  kicker,
  extra,
  children,
  className = "",
}: {
  title: string;
  kicker?: string;
  extra?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={`wb-inspector ${className}`.trim()}>
      <div className="wb-inspector-head">
        <div>
          {kicker ? <span className="wb-panel-kicker">{kicker}</span> : null}
          <h3>{title}</h3>
        </div>
        {extra}
      </div>
      <div className="wb-inspector-body">{children}</div>
    </section>
  );
}

export function CompactListRow({
  title,
  subtitle,
  right,
  onSelect,
  disabled = false,
}: {
  title: string;
  subtitle?: string;
  right?: ReactNode;
  onSelect?: () => void;
  disabled?: boolean;
}) {
  const content = (
    <>
      <div className="wb-list-copy">
        <strong title={title}>{title}</strong>
        {subtitle ? <span title={subtitle}>{subtitle}</span> : null}
      </div>
      {right ? <div className="wb-list-right">{right}</div> : null}
    </>
  );

  if (!onSelect) {
    return <div className="wb-list-row">{content}</div>;
  }

  return (
    <button
      className="wb-list-row interactive"
      disabled={disabled}
      onClick={onSelect}
      type="button"
    >
      {content}
    </button>
  );
}

export function SegmentedControl<T extends string>({
  label,
  options,
  value,
  onChange,
}: {
  label?: string;
  options: Array<SegmentOption<T>>;
  value: T;
  onChange(value: T): void;
}) {
  return (
    <div
      aria-label={label}
      className="wb-segmented"
      role={label ? "radiogroup" : undefined}
    >
      {options.map((option) => (
        <button
          aria-checked={value === option.id}
          className={`wb-segment ${value === option.id ? "active" : ""}`}
          disabled={option.disabled}
          key={option.id}
          onClick={() => onChange(option.id)}
          role={label ? "radio" : undefined}
          type="button"
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

export function StepRail({
  ariaLabel = "Workflow steps",
  steps,
}: {
  ariaLabel?: string;
  steps: StepRailItem[];
}) {
  return (
    <div aria-label={ariaLabel} className="wb-step-rail" role="list">
      {steps.map((step, index) => {
        const interactive = step.status === "complete" && typeof step.onSelect === "function";
        return (
          <div className={`wb-step-row ${step.status}`} key={step.id} role="listitem">
            <button
              aria-label={`Plot step ${step.label}`}
              aria-current={step.status === "current" ? "step" : undefined}
              className="wb-step-button"
              disabled={!interactive}
              onClick={interactive ? (step.onSelect as () => void) : undefined}
              title={step.hint}
              type="button"
            >
              <span className="wb-step-index">{String(index + 1).padStart(2, "0")}</span>
              <span className="wb-step-copy">
                <strong>{step.label}</strong>
                <span>{step.hint}</span>
              </span>
            </button>
          </div>
        );
      })}
    </div>
  );
}

export function SettingsRow({
  label,
  description,
  control,
}: {
  label: string;
  description?: string;
  control: ReactNode;
}) {
  return (
    <div className="wb-settings-row">
      <div className="wb-settings-copy">
        <strong>{label}</strong>
        {description ? <span>{description}</span> : null}
      </div>
      <div className="wb-settings-control">{control}</div>
    </div>
  );
}

export function StatusBar({
  left,
  right,
}: {
  left: ReactNode;
  right?: ReactNode;
}) {
  return (
    <footer className="wb-status-bar">
      <div className="wb-status-left">{left}</div>
      {right ? <div className="wb-status-right">{right}</div> : null}
    </footer>
  );
}

export function EmptyState({
  title,
  description,
}: {
  title: string;
  description?: string;
}) {
  return (
    <div className="wb-empty-state">
      <strong>{title}</strong>
      {description ? <span>{description}</span> : null}
    </div>
  );
}
