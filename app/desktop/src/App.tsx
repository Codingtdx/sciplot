import {
  startTransition,
  useDeferredValue,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

import { AppIcon } from "./components/AppIcon";
import {
  exportRender,
  getWorkbenchMeta,
  inspectFile,
  materializeDataTemplateFolder,
  openPath,
  preflightRender,
  renderPreview,
} from "./lib/api";
import { useWizardStore, useWorkbenchStore } from "./lib/store";
import { openDialog } from "./lib/tauri-dialog";
import type {
  PlotDatasetPreview,
  PreviewItem,
  RenderOptionsPayload,
  TemplateName,
  WorkbenchMeta,
  WorkbenchTemplate,
} from "./lib/types";
import {
  compatibleTemplateChoices,
  confirmReplaceWizardSession,
  formatLeaf,
  formatRecentTimestamp,
  getErrorMessage,
  incompatibleTemplateChoices,
  paletteLabel,
  publicPaletteChoices,
  publicStyleChoices,
  sizeChoices,
  styleLabel,
  templateCompatibilityReason,
  templateLabel,
} from "./lib/workbench";
import {
  inspectionRecommendationSections,
  mergeRenderOptions,
  sanitizeRenderOptions,
  selectionFromInspection,
  templateMeta,
} from "./lib/wizard";

const ACTIVE_ROUTES = ["/", "/plot/import", "/plot/template", "/plot/refine"] as const;

type ActiveRoute = (typeof ACTIVE_ROUTES)[number];

type NavItem = {
  route: ActiveRoute;
  label: string;
  icon: "start" | "import" | "template" | "refine";
  description: string;
};

const NAV_ITEMS: NavItem[] = [
  {
    route: "/",
    label: "Start",
    icon: "start",
    description: "Open a dataset or resume recent work.",
  },
  {
    route: "/plot/import",
    label: "Plot Import",
    icon: "import",
    description: "Load data and confirm what SciPlot detected.",
  },
  {
    route: "/plot/template",
    label: "Plot Template",
    icon: "template",
    description: "Choose the strongest recommendation first.",
  },
  {
    route: "/plot/refine",
    label: "Plot Refine",
    icon: "refine",
    description: "Tune the chart and export inline.",
  },
];

function isActiveRoute(value: string): value is ActiveRoute {
  return (ACTIVE_ROUTES as readonly string[]).includes(value);
}

function normalizeActiveRoute(value: string | null | undefined): ActiveRoute {
  if (!value) {
    return "/";
  }
  if (isActiveRoute(value)) {
    return value;
  }
  if (value.startsWith("/plot/")) {
    if (value === "/plot/import" || value === "/plot/sheet") {
      return "/plot/import";
    }
    if (value === "/plot/type") {
      return "/plot/template";
    }
    return "/plot/refine";
  }
  return "/";
}

function currentPathname() {
  if (typeof window === "undefined") {
    return "/";
  }
  return normalizeActiveRoute(window.location.pathname);
}

function documentTitleForRoute(route: ActiveRoute) {
  switch (route) {
    case "/plot/import":
      return "SciPlot God - Plot Import";
    case "/plot/template":
      return "SciPlot God - Plot Template";
    case "/plot/refine":
      return "SciPlot God - Plot Refine";
    case "/":
    default:
      return "SciPlot God - Start";
  }
}

function classNames(...parts: Array<string | false | null | undefined>) {
  return parts.filter(Boolean).join(" ");
}

function recommendationScore(score: number) {
  return `${score.toFixed(1)}% fit`;
}

function formatCellValue(value: unknown) {
  if (value == null) {
    return "";
  }
  if (typeof value === "number") {
    return Number.isInteger(value) ? String(value) : value.toFixed(3);
  }
  if (typeof value === "boolean") {
    return value ? "True" : "False";
  }
  return String(value);
}

function renderScaleOptions(
  label: string,
  value: "linear" | "log" | undefined,
  onChange: (next: "linear" | "log") => void,
) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      <select value={value ?? "linear"} onChange={(event) => onChange(event.target.value as "linear" | "log")}>
        <option value="linear">Linear</option>
        <option value="log">Log</option>
      </select>
    </label>
  );
}

function Button({
  children,
  onClick,
  variant = "secondary",
  disabled = false,
  icon,
}: {
  children: ReactNode;
  onClick?: () => void;
  variant?: "primary" | "secondary" | "ghost";
  disabled?: boolean;
  icon?: ReactNode;
}) {
  return (
    <button
      type="button"
      className={classNames("button", `button-${variant}`)}
      onClick={onClick}
      disabled={disabled}
    >
      {icon ? <span className="button-icon">{icon}</span> : null}
      <span>{children}</span>
    </button>
  );
}

function StatusPill({
  tone,
  children,
}: {
  tone: "neutral" | "accent" | "success" | "warning";
  children: ReactNode;
}) {
  return <span className={classNames("status-pill", `status-pill-${tone}`)}>{children}</span>;
}

function SidebarNav({
  route,
  onNavigate,
}: {
  route: ActiveRoute;
  onNavigate: (next: ActiveRoute) => void;
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
        {NAV_ITEMS.map((item) => (
          <button
            key={item.route}
            type="button"
            className={classNames("nav-item", route === item.route && "nav-item-active")}
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
        <p>SciPlot now ships a single plot-first desktop path.</p>
      </div>
    </aside>
  );
}

function Titlebar({
  route,
  sidecarReady,
  onRetryMeta,
}: {
  route: ActiveRoute;
  sidecarReady: boolean;
  onRetryMeta: () => void;
}) {
  const navItem = NAV_ITEMS.find((item) => item.route === route) ?? NAV_ITEMS[0];
  return (
    <header className="app-titlebar">
      <div className="traffic-lights" aria-hidden="true">
        <span className="traffic-light traffic-close" />
        <span className="traffic-light traffic-minimize" />
        <span className="traffic-light traffic-zoom" />
      </div>
      <div className="titlebar-copy">
        <span className="titlebar-eyebrow">Plot Workspace</span>
        <h2>{navItem.label}</h2>
      </div>
      <div className="titlebar-actions">
        <StatusPill tone={sidecarReady ? "success" : "warning"}>
          {sidecarReady ? "Sidecar connected" : "Sidecar unavailable"}
        </StatusPill>
        <Button variant="ghost" onClick={onRetryMeta} icon={<AppIcon name="refresh" />}>
          Refresh
        </Button>
      </div>
    </header>
  );
}

function StartScreen({
  recentItems,
  onOpenDataset,
  onOpenRecentDataset,
  onRevealTemplateFolder,
  actionMessage,
}: {
  recentItems: Array<{
    id: string;
    title: string;
    detail: string;
    path: string;
    updated_at: string;
  }>;
  onOpenDataset: () => void;
  onOpenRecentDataset: (path: string) => void;
  onRevealTemplateFolder: (variant: "example" | "blank") => void;
  actionMessage: string | null;
}) {
  return (
    <section className="workspace-screen start-screen">
      <div className="screen-hero">
        <div>
          <p className="screen-eyebrow">Start</p>
          <h1 className="screen-title">Launch directly into a plotting session.</h1>
          <p className="screen-description">
            Open a dataset, reveal template folders, or jump back into a recent file without
            walking through a dashboard.
          </p>
        </div>
        <div className="hero-actions">
          <Button variant="primary" onClick={onOpenDataset} icon={<AppIcon name="import" />}>
            Open dataset
          </Button>
          <Button variant="secondary" onClick={() => onRevealTemplateFolder("example")} icon={<AppIcon name="folder" />}>
            Reveal example templates
          </Button>
          <Button variant="secondary" onClick={() => onRevealTemplateFolder("blank")} icon={<AppIcon name="folder" />}>
            Reveal blank templates
          </Button>
        </div>
      </div>

      {actionMessage ? <div className="inline-message">{actionMessage}</div> : null}

      <div className="start-layout">
        <article className="surface-card emphasis-card">
          <div className="card-header">
            <StatusPill tone="accent">Primary action</StatusPill>
            <h3>Start with a real dataset</h3>
          </div>
          <p>
            Plot Import is the first active workspace. It loads the file, confirms dataset
            structure, and carries the result forward into template recommendations and chart
            refinement.
          </p>
          <div className="feature-list">
            <span><AppIcon name="table" /> Large dataset preview</span>
            <span><AppIcon name="template" /> Recommendation-first next step</span>
            <span><AppIcon name="export" /> Inline export in Plot Refine</span>
          </div>
        </article>

        <article className="surface-card recent-card">
          <div className="card-header">
            <StatusPill tone="neutral">Recent datasets</StatusPill>
            <h3>Continue from where you left off</h3>
          </div>
          {recentItems.length === 0 ? (
            <div className="empty-panel">
              <p>No recent datasets yet.</p>
              <small>Imported files will appear here once you start using the new plot path.</small>
            </div>
          ) : (
            <div className="recent-list" role="list">
              {recentItems.map((item) => (
                <button
                  key={item.id}
                  type="button"
                  className="recent-item"
                  onClick={() => onOpenRecentDataset(item.path)}
                >
                  <span className="recent-main">
                    <strong>{item.title}</strong>
                    <small>{item.detail || item.path}</small>
                  </span>
                  <span className="recent-meta">
                    <small>{formatRecentTimestamp(item.updated_at)}</small>
                    <AppIcon name="chevron-right" />
                  </span>
                </button>
              ))}
            </div>
          )}
        </article>
      </div>
    </section>
  );
}

function DatasetTable({ dataset }: { dataset: PlotDatasetPreview | null }) {
  if (!dataset) {
    return (
      <div className="empty-panel">
        <p>No dataset preview yet.</p>
        <small>Choose a file to inspect the detected columns, sample rows, and quality flags.</small>
      </div>
    );
  }

  const headers = dataset.column_profiles.map((column) => column.name);
  return (
    <div className="table-shell">
      <table className="dataset-table">
        <thead>
          <tr>
            {headers.map((header) => (
              <th key={header}>{header}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {dataset.sample_rows.slice(0, 6).map((row, rowIndex) => (
            <tr key={`${dataset.dataset_id}-${rowIndex}`}>
              {headers.map((_, cellIndex) => (
                <td key={`${rowIndex}-${cellIndex}`}>{formatCellValue(row[cellIndex])}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function PlotImportScreen({
  inputPath,
  sheet,
  sheetNames,
  inspectionModelLabel,
  dataset,
  inspectionSummary,
  importError,
  importBusy,
  onInputPathChange,
  onBrowse,
  onInspect,
  onSelectSheet,
  onContinue,
}: {
  inputPath: string;
  sheet: string | number;
  sheetNames: string[];
  inspectionModelLabel: string | null;
  dataset: PlotDatasetPreview | null;
  inspectionSummary: {
    warnings: string[];
    signals: string[];
    recommendationSummary?: string;
  } | null;
  importError: string | null;
  importBusy: boolean;
  onInputPathChange: (value: string) => void;
  onBrowse: () => void;
  onInspect: () => void;
  onSelectSheet: (value: string) => void;
  onContinue: () => void;
}) {
  return (
    <section className="workspace-screen import-screen">
      <div className="screen-header-row">
        <div>
          <p className="screen-eyebrow">Plot Import</p>
          <h1 className="screen-title">Load a dataset and confirm what SciPlot sees.</h1>
        </div>
        <div className="toolbar-row">
          <Button variant="primary" onClick={onContinue} disabled={!dataset}>
            Continue to templates
          </Button>
        </div>
      </div>

      <div className="screen-grid import-grid">
        <div className="surface-card content-panel">
          <div className="card-header">
            <StatusPill tone="neutral">Dataset source</StatusPill>
            <h3>Choose the file and preview the detected table.</h3>
          </div>
          <div className="toolbar-row">
            <label className="field grow">
              <span className="field-label">Data path</span>
              <input
                value={inputPath}
                onChange={(event) => onInputPathChange(event.target.value)}
                placeholder="/path/to/data.csv"
              />
            </label>
            <Button variant="secondary" onClick={onBrowse} icon={<AppIcon name="folder" />}>
              Browse
            </Button>
            <Button variant="primary" onClick={onInspect} disabled={!inputPath || importBusy}>
              {importBusy ? "Inspecting..." : "Inspect dataset"}
            </Button>
          </div>
          {sheetNames.length > 1 ? (
            <label className="field field-inline">
              <span className="field-label">Workbook sheet</span>
              <select value={String(sheet)} onChange={(event) => onSelectSheet(event.target.value)}>
                {sheetNames.map((name) => (
                  <option key={name} value={name}>
                    {name}
                  </option>
                ))}
              </select>
            </label>
          ) : null}
          {importError ? <div className="inline-error">{importError}</div> : null}
          <DatasetTable dataset={dataset} />
        </div>

        <div className="stack-column">
          <article className="surface-card inspector-panel">
            <div className="card-header">
              <StatusPill tone="accent">Inspection</StatusPill>
              <h3>Detection summary</h3>
            </div>
            {inspectionModelLabel ? (
              <>
                <dl className="detail-list">
                  <div>
                    <dt>Detected model</dt>
                    <dd>{inspectionModelLabel}</dd>
                  </div>
                  <div>
                    <dt>Rows x columns</dt>
                    <dd>
                      {dataset?.raw_rows ?? "-"} x {dataset?.raw_cols ?? "-"}
                    </dd>
                  </div>
                </dl>
                {inspectionSummary?.recommendationSummary ? (
                  <p className="support-copy">{inspectionSummary.recommendationSummary}</p>
                ) : null}
              </>
            ) : (
              <div className="empty-panel">
                <p>No inspection yet.</p>
                <small>The right panel will summarize the detected structure after import.</small>
              </div>
            )}
          </article>

          <article className="surface-card inspector-panel">
            <div className="card-header">
              <StatusPill tone="neutral">Signals</StatusPill>
              <h3>Dataset quality notes</h3>
            </div>
            {inspectionSummary ? (
              <ul className="bullet-list">
                {inspectionSummary.signals.length > 0
                  ? inspectionSummary.signals.slice(0, 4).map((signal) => <li key={signal}>{signal}</li>)
                  : <li>No special signals reported.</li>}
                {inspectionSummary.warnings.length > 0
                  ? inspectionSummary.warnings.slice(0, 3).map((warning) => <li key={warning}>{warning}</li>)
                  : null}
              </ul>
            ) : (
              <div className="empty-panel">
                <small>Signals and warnings appear after the sidecar inspects the dataset.</small>
              </div>
            )}
          </article>
        </div>
      </div>
    </section>
  );
}

function TemplateCard({
  template,
  reason,
  score,
  hint,
  recommended,
  onSelect,
}: {
  template: WorkbenchTemplate;
  reason?: string;
  score: number;
  hint?: string;
  recommended?: boolean;
  onSelect: (templateId: TemplateName) => void;
}) {
  return (
    <article className={classNames("template-card", recommended && "template-card-featured")}>
      <div className="card-header">
        <StatusPill tone={recommended ? "accent" : "neutral"}>
          {recommended ? "Recommended" : "Alternative"}
        </StatusPill>
        <h3>{template.label}</h3>
      </div>
      <p>{template.description}</p>
      <dl className="detail-list compact">
        <div>
          <dt>Fit</dt>
          <dd>{recommendationScore(score)}</dd>
        </div>
        <div>
          <dt>Category</dt>
          <dd>{template.category}</dd>
        </div>
      </dl>
      {hint ? <p className="support-copy">{hint}</p> : null}
      {reason ? <p className="support-copy">{reason}</p> : null}
      <Button variant={recommended ? "primary" : "secondary"} onClick={() => onSelect(template.id)}>
        {recommended ? "Use this template" : "Choose template"}
      </Button>
    </article>
  );
}

function PlotTemplateScreen({
  templateSections,
  incompatibleTemplates,
  inspectionSummary,
  onSelectTemplate,
}: {
  templateSections: ReturnType<typeof inspectionRecommendationSections>;
  incompatibleTemplates: WorkbenchTemplate[];
  inspectionSummary: { compatibility: string } | null;
  onSelectTemplate: (templateId: TemplateName) => void;
}) {
  return (
    <section className="workspace-screen template-screen">
      <div className="screen-header-row">
        <div>
          <p className="screen-eyebrow">Plot Template</p>
          <h1 className="screen-title">Follow the strongest template recommendation first.</h1>
          <p className="screen-description">
            Keep the choice set tight, lead with the best match, and push the chart straight into
            refinement.
          </p>
        </div>
      </div>
      <div className="screen-grid template-grid">
        <div className="stack-column">
          {templateSections.primary.length > 0 ? (
            templateSections.primary.map((item, index) => (
              <TemplateCard
                key={item.template.id}
                template={item.template}
                reason={item.recommendation.reason}
                score={item.recommendation.score}
                hint={item.recommendation.suitability_hint}
                recommended={index === 0}
                onSelect={onSelectTemplate}
              />
            ))
          ) : (
            <div className="surface-card empty-panel">
              <p>No recommendation is available yet.</p>
              <small>Go back to Plot Import and inspect a dataset first.</small>
            </div>
          )}
        </div>

        <div className="stack-column">
          <article className="surface-card inspector-panel">
            <div className="card-header">
              <StatusPill tone="neutral">Alternatives</StatusPill>
              <h3>Other compatible templates</h3>
            </div>
            {templateSections.alternatives.length > 0 ? (
              <div className="template-list">
                {templateSections.alternatives.map((item) => (
                  <TemplateCard
                    key={item.template.id}
                    template={item.template}
                    reason={item.recommendation.reason}
                    score={item.recommendation.score}
                    hint={item.recommendation.suitability_hint}
                    onSelect={onSelectTemplate}
                  />
                ))}
              </div>
            ) : (
              <div className="empty-panel">
                <small>No secondary compatible templates were returned.</small>
              </div>
            )}
          </article>

          <article className="surface-card inspector-panel">
            <div className="card-header">
              <StatusPill tone="warning">Unavailable</StatusPill>
              <h3>Disabled for this dataset shape</h3>
            </div>
            {inspectionSummary ? (
              <p className="support-copy">{inspectionSummary.compatibility}</p>
            ) : null}
            <div className="disabled-template-list">
              {incompatibleTemplates.slice(0, 6).map((template) => (
                <span key={template.id} className="disabled-chip">
                  {template.label}
                </span>
              ))}
            </div>
          </article>
        </div>
      </div>
    </section>
  );
}

function PreviewPanel({
  previews,
  previewIndex,
  onSelectPreview,
  previewBusy,
  previewError,
}: {
  previews: PreviewItem[];
  previewIndex: number;
  onSelectPreview: (index: number) => void;
  previewBusy: boolean;
  previewError: string | null;
}) {
  const preview = previews[previewIndex] ?? null;
  return (
    <div className="preview-panel">
      <div className="preview-toolbar">
        <div className="preview-toolbar-copy">
          <StatusPill tone="neutral">Preview</StatusPill>
          <strong>{preview?.filename ?? "No preview yet"}</strong>
        </div>
        {previews.length > 1 ? (
          <div className="preview-tabs" role="tablist" aria-label="Preview variants">
            {previews.map((item, index) => (
              <button
                key={item.filename}
                type="button"
                className={classNames("preview-tab", index === previewIndex && "preview-tab-active")}
                onClick={() => onSelectPreview(index)}
              >
                {index + 1}
              </button>
            ))}
          </div>
        ) : null}
      </div>
      <div className="preview-stage">
        {previewBusy ? (
          <div className="empty-panel">
            <p>Rendering preview…</p>
            <small>Plot Refine keeps the preview as the dominant workspace.</small>
          </div>
        ) : previewError ? (
          <div className="empty-panel">
            <p>{previewError}</p>
            <small>Fix the current settings or try refreshing the preview.</small>
          </div>
        ) : preview ? (
          <img
            className="preview-image"
            src={`data:image/png;base64,${preview.png_base64}`}
            alt={preview.filename}
          />
        ) : (
          <div className="empty-panel">
            <p>No preview has been rendered.</p>
            <small>Select a template to let SciPlot generate the live chart preview.</small>
          </div>
        )}
      </div>
    </div>
  );
}

function PlotRefineScreen({
  meta,
  template,
  options,
  previews,
  previewIndex,
  previewBusy,
  previewError,
  readinessBusy,
  exportBusy,
  submissionChecks,
  exportOutputs,
  lastOutputDir,
  onSelectPreview,
  onOptionChange,
  onCheckReadiness,
  onExport,
  onOpenOutputDir,
}: {
  meta: WorkbenchMeta | null;
  template: TemplateName | null;
  options: RenderOptionsPayload;
  previews: PreviewItem[];
  previewIndex: number;
  previewBusy: boolean;
  previewError: string | null;
  readinessBusy: boolean;
  exportBusy: boolean;
  submissionChecks: Array<{ id: string; status: string; message: string }>;
  exportOutputs: string[];
  lastOutputDir: string | null;
  onSelectPreview: (index: number) => void;
  onOptionChange: (patch: Partial<RenderOptionsPayload>) => void;
  onCheckReadiness: () => void;
  onExport: () => void;
  onOpenOutputDir: () => void;
}) {
  const currentTemplate = templateMeta(meta, template);
  const styles = publicStyleChoices(meta, template);
  const palettes = publicPaletteChoices(meta, template);
  const sizes = sizeChoices(meta, template);
  const editable = new Set(currentTemplate?.editable_options ?? []);

  return (
    <section className="workspace-screen refine-screen">
      <div className="screen-header-row">
        <div>
          <p className="screen-eyebrow">Plot Refine</p>
          <h1 className="screen-title">Refine the chart in place and export inline.</h1>
        </div>
        <div className="toolbar-row">
          <Button variant="secondary" onClick={onCheckReadiness} disabled={!template || readinessBusy}>
            {readinessBusy ? "Checking..." : "Check readiness"}
          </Button>
          <Button variant="primary" onClick={onExport} disabled={!template || exportBusy}>
            {exportBusy ? "Exporting..." : "Export bundle"}
          </Button>
        </div>
      </div>

      <div className="screen-grid refine-grid">
        <div className="surface-card preview-card">
          <PreviewPanel
            previews={previews}
            previewIndex={previewIndex}
            onSelectPreview={onSelectPreview}
            previewBusy={previewBusy}
            previewError={previewError}
          />
        </div>

        <aside className="surface-card inspector-panel refine-inspector">
          <div className="card-header">
            <StatusPill tone="accent">Inspector</StatusPill>
            <h3>{templateLabel(meta, template)}</h3>
          </div>

          <section className="inspector-section">
            <h4>Template summary</h4>
            <p className="support-copy">
              {currentTemplate?.description ?? "Choose a template from Plot Template first."}
            </p>
          </section>

          {editable.has("size") && sizes.length > 0 ? (
            <section className="inspector-section">
              <h4>Figure size</h4>
              <label className="field">
                <span className="field-label">Preset</span>
                <select value={options.size ?? sizes[0]?.id ?? ""} onChange={(event) => onOptionChange({ size: event.target.value })}>
                  {sizes.map((size) => (
                    <option key={size.id} value={size.id}>
                      {size.label}
                    </option>
                  ))}
                </select>
              </label>
            </section>
          ) : null}

          {editable.has("xscale") || editable.has("yscale") || editable.has("reverse_x") ? (
            <section className="inspector-section">
              <h4>Axes and scales</h4>
              {editable.has("xscale")
                ? renderScaleOptions("X scale", options.xscale, (next) => onOptionChange({ xscale: next }))
                : null}
              {editable.has("yscale")
                ? renderScaleOptions("Y scale", options.yscale, (next) => onOptionChange({ yscale: next }))
                : null}
              {editable.has("reverse_x") ? (
                <label className="checkbox-row">
                  <input
                    type="checkbox"
                    checked={Boolean(options.reverse_x)}
                    onChange={(event) => onOptionChange({ reverse_x: event.target.checked })}
                  />
                  <span>Reverse X axis</span>
                </label>
              ) : null}
            </section>
          ) : null}

          {editable.has("style_preset") || editable.has("palette_preset") ? (
            <section className="inspector-section">
              <h4>Style and palette</h4>
              {editable.has("style_preset") && styles.length > 0 ? (
                <label className="field">
                  <span className="field-label">Style preset</span>
                  <select
                    value={options.style_preset ?? styles[0]?.id ?? ""}
                    onChange={(event) => onOptionChange({ style_preset: event.target.value })}
                  >
                    {styles.map((style) => (
                      <option key={style.id} value={style.id}>
                        {style.label}
                      </option>
                    ))}
                  </select>
                </label>
              ) : null}
              {editable.has("palette_preset") && palettes.length > 0 ? (
                <label className="field">
                  <span className="field-label">Palette preset</span>
                  <select
                    value={options.palette_preset ?? palettes[0]?.id ?? ""}
                    onChange={(event) => onOptionChange({ palette_preset: event.target.value })}
                  >
                    {palettes.map((palette) => (
                      <option key={palette.id} value={palette.id}>
                        {palette.label}
                      </option>
                    ))}
                  </select>
                </label>
              ) : null}
            </section>
          ) : null}

          {editable.has("show_colorbar") ? (
            <section className="inspector-section">
              <h4>Heatmap options</h4>
              <label className="checkbox-row">
                <input
                  type="checkbox"
                  checked={Boolean(options.show_colorbar)}
                  onChange={(event) => onOptionChange({ show_colorbar: event.target.checked })}
                />
                <span>Show colorbar</span>
              </label>
            </section>
          ) : null}

          <section className="inspector-section">
            <h4>Export</h4>
            <dl className="detail-list compact">
              <div>
                <dt>Style</dt>
                <dd>{styleLabel(meta, options.style_preset)}</dd>
              </div>
              <div>
                <dt>Palette</dt>
                <dd>{paletteLabel(meta, options.palette_preset)}</dd>
              </div>
            </dl>
            {lastOutputDir ? (
              <Button variant="secondary" onClick={onOpenOutputDir} icon={<AppIcon name="folder" />}>
                Reveal output folder
              </Button>
            ) : null}
            {exportOutputs.length > 0 ? (
              <ul className="bullet-list compact">
                {exportOutputs.slice(0, 4).map((output) => (
                  <li key={output}>{formatLeaf(output)}</li>
                ))}
              </ul>
            ) : null}
          </section>

          <section className="inspector-section">
            <h4>Submission report</h4>
            {submissionChecks.length > 0 ? (
              <ul className="check-list">
                {submissionChecks.slice(0, 5).map((check) => (
                  <li key={check.id}>
                    <StatusPill
                      tone={
                        check.status === "pass"
                          ? "success"
                          : check.status === "warning" || check.status === "critical"
                            ? "warning"
                            : "neutral"
                      }
                    >
                      {check.status}
                    </StatusPill>
                    <span>{check.message}</span>
                  </li>
                ))}
              </ul>
            ) : (
              <div className="empty-panel compact">
                <small>Run readiness check to populate inline export feedback.</small>
              </div>
            )}
          </section>
        </aside>
      </div>
    </section>
  );
}

export function App() {
  const wizard = useWizardStore();
  const workbench = useWorkbenchStore();

  const [route, setRoute] = useState<ActiveRoute>(() => {
    const current = currentPathname();
    if (current !== "/") {
      return current;
    }
    return normalizeActiveRoute(workbench.lastRoute);
  });
  const [meta, setMeta] = useState<WorkbenchMeta | null>(null);
  const [metaError, setMetaError] = useState<string | null>(null);
  const [metaBusy, setMetaBusy] = useState(true);
  const [importBusy, setImportBusy] = useState(false);
  const [previewBusy, setPreviewBusy] = useState(false);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [readinessBusy, setReadinessBusy] = useState(false);
  const [exportBusy, setExportBusy] = useState(false);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [pathDraft, setPathDraft] = useState(wizard.inputPath);

  const deferredOptions = useDeferredValue(wizard.options);
  const recentDatasets = useMemo(
    () => workbench.recentProjects.filter((item) => item.mode === "wizard" && item.kind === "data"),
    [workbench.recentProjects],
  );

  useEffect(() => {
    document.title = documentTitleForRoute(route);
  }, [route]);

  useEffect(() => {
    if (typeof window === "undefined") {
      return undefined;
    }
    const onPopState = () => {
      setRoute(currentPathname());
    };
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  }, []);

  useEffect(() => {
    setPathDraft(wizard.inputPath);
  }, [wizard.inputPath]);

  useEffect(() => {
    let cancelled = false;
    async function loadMeta() {
      setMetaBusy(true);
      setMetaError(null);
      try {
        const nextMeta = await getWorkbenchMeta();
        if (cancelled) {
          return;
        }
        setMeta(nextMeta);
        wizard.setSidecarReady(true);
        if (!wizard.options.style_preset || !wizard.options.palette_preset) {
          wizard.setOptions(
            sanitizeRenderOptions(
              nextMeta,
              wizard.template,
              {
                ...wizard.options,
                style_preset: wizard.options.style_preset ?? nextMeta.default_style,
                palette_preset: wizard.options.palette_preset ?? nextMeta.default_palette,
              },
              wizard.inspection?.model,
            ),
          );
        }
      } catch (error) {
        if (cancelled) {
          return;
        }
        wizard.setSidecarReady(false);
        setMetaError(getErrorMessage(error));
      } finally {
        if (!cancelled) {
          setMetaBusy(false);
        }
      }
    }
    void loadMeta();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (route !== "/plot/refine" || !wizard.inputPath || !wizard.template) {
      return;
    }
    const controller = new AbortController();
    let cancelled = false;
    const templateId = wizard.template;

    async function loadPreview() {
      setPreviewBusy(true);
      setPreviewError(null);
      try {
        const response = await renderPreview(
          wizard.inputPath,
          wizard.sheet,
          templateId,
          deferredOptions,
          { signal: controller.signal },
        );
        if (cancelled) {
          return;
        }
        wizard.setPreviews(response.previews);
        wizard.setSubmissionReport(response.submission_report ?? null);
      } catch (error) {
        if (cancelled || controller.signal.aborted) {
          return;
        }
        wizard.setPreviews([]);
        setPreviewError(getErrorMessage(error));
      } finally {
        if (!cancelled) {
          setPreviewBusy(false);
        }
      }
    }

    void loadPreview();
    return () => {
      cancelled = true;
      controller.abort();
    };
  }, [route, wizard.inputPath, wizard.sheet, wizard.template, deferredOptions]);

  const navigate = (next: ActiveRoute) => {
    startTransition(() => {
      setRoute(next);
      workbench.setLastRoute(next as never);
      if (typeof window !== "undefined" && window.location.pathname !== next) {
        window.history.pushState({}, "", next);
      }
    });
  };

  const retryMeta = () => {
    setMetaBusy(true);
    setMetaError(null);
    void getWorkbenchMeta()
      .then((nextMeta) => {
        setMeta(nextMeta);
        wizard.setSidecarReady(true);
      })
      .catch((error) => {
        wizard.setSidecarReady(false);
        setMetaError(getErrorMessage(error));
      })
      .finally(() => {
        setMetaBusy(false);
      });
  };

  const rememberDataset = (path: string, detail: string) => {
    workbench.rememberProject({
      mode: "wizard",
      kind: "data",
      path,
      title: formatLeaf(path),
      detail,
    });
  };

  const resetPlotSession = (nextPath: string) => {
    wizard.setInputPath(nextPath);
    wizard.setProjectPath("");
    wizard.setSheet(0);
    wizard.setSheetNames([]);
    wizard.setInspection(null);
    wizard.setDataset(null);
    wizard.setTemplate(null);
    wizard.setPreflight(null);
    wizard.setPreviews([]);
    wizard.setPreviewIndex(0);
    wizard.setOutputs([]);
    wizard.setExportResult(null);
    wizard.setSubmissionReport(null);
    wizard.setStage("import");
    wizard.setStep("file");
    wizard.setError(null);
    if (meta) {
      wizard.setOptions(
        sanitizeRenderOptions(meta, null, {
          style_preset: meta.default_style,
          palette_preset: meta.default_palette,
        }),
      );
    } else {
      wizard.setOptions({});
    }
  };

  const inspectDataset = async (nextPath: string, nextSheet: string | number = wizard.sheet || 0) => {
    if (!nextPath.trim()) {
      wizard.setError("Choose a dataset path first.");
      return;
    }
    if (
      !confirmReplaceWizardSession(
        {
          inputPath: wizard.inputPath,
          inspection: wizard.inspection,
          template: wizard.template,
          outputs: wizard.outputs,
          exportResult: wizard.exportResult,
        },
        formatLeaf(nextPath),
        nextPath,
      )
    ) {
      return;
    }

    setImportBusy(true);
    wizard.setError(null);
    setActionMessage(null);
    resetPlotSession(nextPath);
    try {
      const response = await inspectFile(nextPath, nextSheet);
      const selection = selectionFromInspection(meta, response.inspection);
      wizard.setInputPath(response.input_path);
      wizard.setSheet(response.sheet);
      wizard.setSheetNames(response.sheet_names);
      wizard.setInspection(response.inspection);
      wizard.setDataset(response.dataset ?? null);
      wizard.setTemplate(selection.template);
      wizard.setOptions(selection.options);
      wizard.setStage("type");
      wizard.setStep("inspect");
      rememberDataset(response.input_path, response.inspection.model_label);
      navigate("/plot/import");
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      setImportBusy(false);
    }
  };

  const openDatasetDialog = async () => {
    try {
      const selected = await openDialog({
        multiple: false,
        directory: false,
        filters: [
          {
            name: "Datasets",
            extensions: ["csv", "txt", "tsv", "xlsx", "xls"],
          },
        ],
      });
      if (typeof selected === "string" && selected.trim()) {
        setPathDraft(selected);
        await inspectDataset(selected, 0);
      }
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    }
  };

  const revealTemplateFolder = async (variant: "example" | "blank") => {
    try {
      setActionMessage(null);
      const response = await materializeDataTemplateFolder({ variant });
      await openPath(response.folder_path);
      setActionMessage(
        `${variant === "example" ? "Example" : "Blank"} template folder ready at ${response.folder_path}`,
      );
    } catch (error) {
      setActionMessage(getErrorMessage(error));
    }
  };

  const selectTemplate = (templateId: TemplateName) => {
    if (!meta || !wizard.inspection) {
      return;
    }
    const selection = selectionFromInspection(meta, wizard.inspection, {
      template: templateId,
      options: wizard.options,
    });
    wizard.setTemplate(selection.template);
    wizard.setOptions(selection.options);
    wizard.setStage("tune");
    wizard.setStep("options");
    navigate("/plot/refine");
  };

  const updateRenderOptions = (patch: Partial<RenderOptionsPayload>) => {
    wizard.setOptions(
      mergeRenderOptions(meta, wizard.template, wizard.options, patch, wizard.inspection?.model),
    );
  };

  const checkReadiness = async () => {
    if (!wizard.inputPath || !wizard.template) {
      return;
    }
    setReadinessBusy(true);
    wizard.setError(null);
    try {
      const response = await preflightRender(
        wizard.inputPath,
        wizard.sheet,
        wizard.template,
        wizard.options,
      );
      wizard.setPreflight(response.preflight);
      wizard.setSubmissionReport(response.preflight.submission_report ?? null);
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      setReadinessBusy(false);
    }
  };

  const runExport = async () => {
    if (!wizard.inputPath || !wizard.template) {
      return;
    }
    setExportBusy(true);
    wizard.setError(null);
    try {
      const response = await exportRender({
        input_path: wizard.inputPath,
        sheet: wizard.sheet,
        template: wizard.template,
        options: wizard.options,
        output_dir: null,
      });
      wizard.setOutputs(response.outputs);
      wizard.setExportResult(response);
      wizard.setSubmissionReport(response.submission_report ?? wizard.submissionReport);
      wizard.setStage("export");
      wizard.setStep("export");
      rememberDataset(
        wizard.inputPath,
        `${templateLabel(meta, wizard.template)} exported to ${formatLeaf(response.output_dir)}`,
      );
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      setExportBusy(false);
    }
  };

  const openOutputDirectory = async () => {
    const target = wizard.exportResult?.output_dir;
    if (!target) {
      return;
    }
    try {
      await openPath(target);
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    }
  };

  const templateSections = inspectionRecommendationSections(meta, wizard.inspection);
  const compatibleTemplates = compatibleTemplateChoices(meta, wizard.inspection?.model);
  const incompatibleTemplates = incompatibleTemplateChoices(meta, wizard.inspection?.model);

  return (
    <div className="desktop-root">
      <div className="desktop-backdrop" />
      <div className="desktop-window">
        <SidebarNav route={route} onNavigate={navigate} />
        <main className="app-main">
          <Titlebar route={route} sidecarReady={wizard.sidecarReady} onRetryMeta={retryMeta} />
          <div className="workspace-sheet">
            {metaBusy ? (
              <div className="empty-screen">
                <p>Loading SciPlot desktop workspace…</p>
                <small>Fetching current sidecar metadata and plot contract choices.</small>
              </div>
            ) : metaError ? (
              <div className="empty-screen">
                <p>{metaError}</p>
                <small>Reconnect the sidecar to continue using the active Plot path.</small>
              </div>
            ) : route === "/" ? (
              <StartScreen
                recentItems={recentDatasets}
                onOpenDataset={() => {
                  navigate("/plot/import");
                  void openDatasetDialog();
                }}
                onOpenRecentDataset={(path) => {
                  navigate("/plot/import");
                  void inspectDataset(path, 0);
                }}
                onRevealTemplateFolder={(variant) => {
                  void revealTemplateFolder(variant);
                }}
                actionMessage={actionMessage}
              />
            ) : route === "/plot/import" ? (
              <PlotImportScreen
                inputPath={pathDraft}
                sheet={wizard.sheet}
                sheetNames={wizard.sheetNames}
                inspectionModelLabel={wizard.inspection?.model_label ?? null}
                dataset={wizard.dataset}
                inspectionSummary={
                  wizard.inspection
                    ? {
                        warnings: wizard.inspection.warnings,
                        signals: wizard.inspection.signals,
                        recommendationSummary: wizard.inspection.recommendation_summary,
                      }
                    : null
                }
                importError={wizard.error}
                importBusy={importBusy}
                onInputPathChange={(value) => {
                  setPathDraft(value);
                  wizard.setError(null);
                }}
                onBrowse={() => {
                  void openDatasetDialog();
                }}
                onInspect={() => {
                  void inspectDataset(pathDraft, wizard.sheet || 0);
                }}
                onSelectSheet={(value) => {
                  void inspectDataset(wizard.inputPath || pathDraft, value);
                }}
                onContinue={() => navigate("/plot/template")}
              />
            ) : route === "/plot/template" ? (
              <PlotTemplateScreen
                templateSections={templateSections}
                incompatibleTemplates={
                  incompatibleTemplates.length > 0 ? incompatibleTemplates : compatibleTemplates.slice(3)
                }
                inspectionSummary={
                  wizard.inspection
                    ? {
                        compatibility: templateCompatibilityReason(wizard.inspection.model),
                      }
                    : null
                }
                onSelectTemplate={selectTemplate}
              />
            ) : (
              <PlotRefineScreen
                meta={meta}
                template={wizard.template}
                options={wizard.options}
                previews={wizard.previews}
                previewIndex={wizard.previewIndex}
                previewBusy={previewBusy}
                previewError={previewError ?? wizard.error}
                readinessBusy={readinessBusy}
                exportBusy={exportBusy}
                submissionChecks={
                  wizard.submissionReport?.checks.map((check) => ({
                    id: check.id,
                    status: check.status,
                    message: check.message,
                  })) ?? []
                }
                exportOutputs={wizard.outputs}
                lastOutputDir={wizard.exportResult?.output_dir ?? null}
                onSelectPreview={(index) => wizard.setPreviewIndex(index)}
                onOptionChange={updateRenderOptions}
                onCheckReadiness={() => {
                  void checkReadiness();
                }}
                onExport={() => {
                  void runExport();
                }}
                onOpenOutputDir={() => {
                  void openOutputDirectory();
                }}
              />
            )}
          </div>
        </main>
      </div>
    </div>
  );
}
