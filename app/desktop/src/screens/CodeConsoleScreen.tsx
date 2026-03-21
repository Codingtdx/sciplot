import { useMemo, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { openPath } from "../lib/api";
import { copyTextToClipboard } from "../lib/clipboard";
import {
  backfillCodeConsoleOptions,
  CODE_CONSOLE_INTENTS,
  codeConsoleBriefPlaceholder,
  codeConsoleIntentHint,
  codeConsoleIntentLabel,
  defaultCodeConsoleTargetPath,
  resolveCodeConsolePalette,
  resolveCodeConsoleSize,
  resolveCodeConsoleStyle,
  resolveCodeConsoleTemplate,
} from "../lib/code-console";
import { useCodeConsoleStore, useWizardStore } from "../lib/store";
import { openDialog } from "../lib/tauri-dialog";
import type {
  CodeConsoleDefaultsPanel,
  CodeConsoleGenerateResponse,
  CodeConsoleTruthSource,
  PlotContract,
  WorkbenchMeta,
} from "../lib/types";
import { formatLeaf } from "../lib/workbench";
import { useCodeConsoleBundleExport } from "./code-console/useCodeConsoleBundleExport";
import { useCodeConsoleGenerate } from "./code-console/useCodeConsoleGenerate";

function previewSnippet(value: string, lineCount = 14) {
  const lines = value.split("\n");
  if (lines.length <= lineCount) {
    return value;
  }
  return `${lines.slice(0, lineCount).join("\n")}\n...`;
}

function resolveDialogSelection(value: string | string[] | null) {
  if (Array.isArray(value)) {
    return value[0] ?? null;
  }
  return value;
}

function fallbackTruthSources(args: {
  inputPath: string;
  projectPath: string;
  sheet: string | number;
  inspectionModelLabel: string | null;
  exportPath?: string | null;
}): CodeConsoleTruthSource[] {
  const sources: CodeConsoleTruthSource[] = [
    {
      id: "plot_contract",
      label: "Plot contract",
      path: "src/plot_contract.json",
      display_path: "src/plot_contract.json",
      kind: "contract",
      available: true,
      reason: "Canonical plotting contract. Template, size, style, and palette legality are resolved from here.",
    },
    {
      id: "plot_style",
      label: "Plot style helper",
      path: "src/plot_style.py",
      display_path: "src/plot_style.py",
      kind: "style_helper",
      available: true,
      reason: "Shared helper for style-backed typography, margins, palettes, and export behavior.",
    },
    {
      id: "rendering_service",
      label: "Rendering service",
      path: "src/rendering/",
      display_path: "src/rendering/",
      kind: "service_entry",
      available: true,
      reason: "Repo-native render logic belongs in the rendering service layer, not in the GUI or a detached demo.",
    },
    {
      id: "make_plot",
      label: "CLI compatibility entry",
      path: "make_plot.py",
      display_path: "make_plot.py",
      kind: "entry_point",
      available: true,
      reason: "Shows the supported invocation shape for project-native plotting flows.",
    },
  ];

  if (args.inputPath) {
    sources.push({
      id: "current_data",
      label: "Current data file",
      path: args.inputPath,
      display_path: args.inputPath,
      kind: "data",
      available: true,
      reason: "This is the file currently bound to the active plot session.",
    });
    sources.push({
      id: "current_sheet",
      label: "Current sheet",
      path: null,
      display_path: String(args.sheet),
      kind: "sheet",
      available: true,
      reason: "This is the sheet selection currently used by the active plot session.",
    });
  }

  if (args.inspectionModelLabel) {
    sources.push({
      id: "current_inspection",
      label: "Current inspect summary",
      path: null,
      display_path: args.inspectionModelLabel,
      kind: "inspection",
      available: true,
      reason: "This summary comes from the same sidecar inspect flow that powers recommendation and preview.",
    });
  }

  if (args.projectPath) {
    sources.push({
      id: "current_project",
      label: "Current project file",
      path: args.projectPath,
      display_path: args.projectPath,
      kind: "project",
      available: true,
      reason: "When attached, this path points to a validated SciPlot God project document.",
    });
  }

  if (args.exportPath) {
    sources.push({
      id: "generated_bundle",
      label: "Generated AI bundle",
      path: args.exportPath,
      display_path: args.exportPath,
      kind: "bundle",
      available: true,
      reason: "This is the sidecar-generated bundle directory to hand to an external AI when deeper context is needed.",
    });
  }

  return sources;
}

function fallbackDefaultsPanel(args: {
  templateLabel: string;
  sizeLabel: string;
  styleLabel: string;
  paletteLabel: string;
  contract: PlotContract | null;
  inputPath: string;
  sheet: string | number;
  inspectionModelLabel: string | null;
  projectPath: string;
}): CodeConsoleDefaultsPanel {
  const globalFrame = args.contract?.global_frame;
  return {
    locked_by_contract: [
      {
        label: "Axis frame",
        value: `${globalFrame?.panel_width_mm ?? 60} x ${globalFrame?.panel_height_mm ?? 55} mm`,
        reason: "Shared panel geometry comes from contract-backed metadata, not local GUI constants.",
      },
      {
        label: "Margins",
        value: `L ${globalFrame?.left_margin_mm ?? 14} / R ${globalFrame?.right_margin_mm ?? 4.5} / B ${globalFrame?.bottom_margin_mm ?? 11} / T ${globalFrame?.top_margin_mm ?? 5.5} mm`,
        reason: "Physical plot margins remain owned by the style system and contract payloads.",
      },
    ],
    user_selectable: [
      {
        label: "Base template",
        value: args.templateLabel,
        reason: "The user can change the requested implementation target, but the selection is still validated by sidecar helpers.",
      },
      {
        label: "Target size / style / palette",
        value: `${args.sizeLabel} / ${args.styleLabel} / ${args.paletteLabel}`,
        reason: "Selections are editable here, then normalized by the rendering option resolver on generate/export.",
      },
    ],
    derived_from_session: [
      {
        label: "Bound data",
        value: args.inputPath || "No data bound",
        reason: "Inherited from the current plot session if a data file is open.",
      },
      {
        label: "Bound sheet",
        value: args.inputPath ? String(args.sheet) : "-",
        reason: "Inherited from the current sheet selection when data is present.",
      },
      {
        label: "Detected model",
        value: args.inspectionModelLabel ?? "-",
        reason: "Comes from the current inspect state until a richer sidecar payload is generated.",
      },
      {
        label: "Project context",
        value: args.projectPath || "Not attached",
        reason: "Only available when the current session came from a validated project file.",
      },
    ],
  };
}

function contextNote(result: CodeConsoleGenerateResponse | null, hasData: boolean) {
  if (result) {
    return `Generated ${result.generated_at} · bundle v${result.bundle_version}`;
  }
  if (hasData) {
    return "Ready to generate a lightweight context bundle from the current plot session.";
  }
  return "No current data file is bound. You can still generate a repo-native prompt and scaffold.";
}

export function CodeConsoleScreen({
  meta,
  contract,
}: {
  meta: WorkbenchMeta | null;
  contract: PlotContract | null;
}) {
  const draft = useCodeConsoleStore(
    useShallow((state) => ({
      brief: state.brief,
      includeDataContext: state.includeDataContext,
      includeFullDataBundle: state.includeFullDataBundle,
      includeInspectionSummary: state.includeInspectionSummary,
      includeProjectContext: state.includeProjectContext,
      intent: state.intent,
      palettePreset: state.palettePreset,
      sizeId: state.sizeId,
      stylePreset: state.stylePreset,
      targetPath: state.targetPath,
      templateId: state.templateId,
    })),
  );
  const codeConsoleActions = useCodeConsoleStore(
    useShallow((state) => ({
      reset: state.reset,
      setBrief: state.setBrief,
      setIncludeDataContext: state.setIncludeDataContext,
      setIncludeFullDataBundle: state.setIncludeFullDataBundle,
      setIncludeInspectionSummary: state.setIncludeInspectionSummary,
      setIncludeProjectContext: state.setIncludeProjectContext,
      setIntent: state.setIntent,
      setPalettePreset: state.setPalettePreset,
      setSizeId: state.setSizeId,
      setStylePreset: state.setStylePreset,
      setTargetPath: state.setTargetPath,
      setTemplateId: state.setTemplateId,
    })),
  );
  const wizard = useWizardStore(
    useShallow((state) => ({
      inputPath: state.inputPath,
      inspection: state.inspection,
      options: state.options,
      projectPath: state.projectPath,
      sheet: state.sheet,
      sidecarReady: state.sidecarReady,
      template: state.template,
    })),
  );
  const generateState = useCodeConsoleGenerate();
  const exportState = useCodeConsoleBundleExport();
  const [notice, setNotice] = useState<string | null>(null);
  const [noticeTone, setNoticeTone] = useState<"success" | "warning">("success");

  const sessionBackfill = backfillCodeConsoleOptions(draft, {
    templateId: wizard.template,
    options: wizard.options,
  });
  const template = useMemo(
    () => resolveCodeConsoleTemplate(meta, sessionBackfill.templateId),
    [meta, sessionBackfill.templateId],
  );
  const size = useMemo(
    () => resolveCodeConsoleSize(meta, template, sessionBackfill.sizeId),
    [meta, sessionBackfill.sizeId, template],
  );
  const style = useMemo(
    () => resolveCodeConsoleStyle(meta, template, sessionBackfill.stylePreset),
    [meta, sessionBackfill.stylePreset, template],
  );
  const palette = useMemo(
    () => resolveCodeConsolePalette(meta, template, sessionBackfill.palettePreset),
    [meta, sessionBackfill.palettePreset, template],
  );
  const targetPath = draft.targetPath.trim() || defaultCodeConsoleTargetPath(draft.intent, template.id);

  const hasData = wizard.inputPath.trim() !== "";
  const hasProjectContext = wizard.projectPath.trim() !== "";
  const includeFullDataExport = draft.includeFullDataBundle && hasData;
  const inputLeaf = hasData ? formatLeaf(wizard.inputPath) : "No data";
  const availableStyles =
    meta?.styles.filter((item) => item.public && template.available_styles.includes(item.id)) ?? [];
  const availablePalettes =
    meta?.palettes.filter((item) => template.available_palettes.includes(item.id)) ?? [];
  const sizeOptions = meta?.sizes.filter((item) => template.allowed_sizes.includes(item.id)) ?? [];

  const requestPayload = useMemo(
    () => ({
      intent: draft.intent,
      brief: draft.brief,
      base_template: template.id,
      size: size.id,
      style_preset: style.id,
      palette_preset: palette.id,
      target_path: targetPath,
      input_path: hasData ? wizard.inputPath : null,
      sheet: hasData ? wizard.sheet : null,
      project_path: hasProjectContext ? wizard.projectPath : null,
      include_data_context: draft.includeDataContext && hasData,
      include_inspection_summary:
        draft.includeInspectionSummary && hasData && wizard.inspection != null,
      include_project_context: draft.includeProjectContext && hasProjectContext,
    }),
    [
      draft.brief,
      draft.includeDataContext,
      draft.includeInspectionSummary,
      draft.includeProjectContext,
      draft.intent,
      hasData,
      hasProjectContext,
      palette.id,
      size.id,
      style.id,
      targetPath,
      template.id,
      wizard.inputPath,
      wizard.inspection,
      wizard.projectPath,
      wizard.sheet,
    ],
  );

  const generated = generateState.result;
  const exportedBundle = exportState.result;
  const defaultsPanel =
    generated?.defaults_panel ??
    fallbackDefaultsPanel({
      templateLabel: template.label,
      sizeLabel: size.label,
      styleLabel: style.label,
      paletteLabel: palette.label,
      contract,
      inputPath: hasData ? wizard.inputPath : "",
      sheet: wizard.sheet,
      inspectionModelLabel: wizard.inspection?.model_label ?? null,
      projectPath: hasProjectContext ? wizard.projectPath : "",
    });
  const truthSources =
    generated?.truth_sources ??
    fallbackTruthSources({
      inputPath: hasData ? wizard.inputPath : "",
      projectPath: hasProjectContext ? wizard.projectPath : "",
      sheet: wizard.sheet,
      inspectionModelLabel: wizard.inspection?.model_label ?? null,
      exportPath: exportedBundle?.bundle_dir ?? null,
    });

  const handleCopy = async (value: string, label: string) => {
    try {
      await copyTextToClipboard(value);
      setNoticeTone("success");
      setNotice(`${label} copied.`);
    } catch (error) {
      setNoticeTone("warning");
      setNotice(error instanceof Error ? error.message : String(error));
    }
  };

  const handleGenerate = async () => {
    const response = await generateState.generate(requestPayload);
    if (!response) {
      return;
    }
    setNoticeTone("success");
    setNotice("AI bridge context generated from the current selections.");
  };

  const handleExport = async () => {
    try {
      const selectedPath = resolveDialogSelection(
        await openDialog({
          defaultPath: hasData ? wizard.inputPath : undefined,
          directory: true,
          multiple: false,
          title: includeFullDataExport ? "Export full-data AI bundle" : "Export AI bundle",
        }),
      );
      if (!selectedPath) {
        return;
      }

      const response = await exportState.exportBundle({
        ...requestPayload,
        output_dir: selectedPath,
        include_full_data: includeFullDataExport,
      });
      if (!response) {
        return;
      }

      setNoticeTone("success");
      setNotice(
        includeFullDataExport
          ? "Full-data AI bundle exported."
          : "Lightweight AI bundle exported.",
      );
    } catch (error) {
      setNoticeTone("warning");
      setNotice(error instanceof Error ? error.message : String(error));
    }
  };

  const handleReveal = async (path: string | null | undefined) => {
    if (!path) {
      return;
    }
    try {
      await openPath(path);
    } catch (error) {
      setNoticeTone("warning");
      setNotice(error instanceof Error ? error.message : String(error));
    }
  };

  const handleReset = () => {
    codeConsoleActions.reset();
    generateState.reset();
    setNotice(null);
    setNoticeTone("success");
  };

  return (
    <div className="plot-workspace">
      <section className="work-card section-card code-console-context-bar">
        <div className="panel-heading">
          <div>
            <div className="card-kicker">AI Bridge</div>
            <h2>Build a repo-native prompt, scaffold, and AI context bundle</h2>
          </div>
          <span className={`status-pill ${wizard.sidecarReady ? "good" : "warn"}`}>
            {wizard.sidecarReady ? "Sidecar Online" : "Sidecar Offline"}
          </span>
        </div>

        <div className="code-console-context-grid">
          <div className="code-console-context-chip">
            <span>Mode</span>
            <strong>{codeConsoleIntentLabel(draft.intent)}</strong>
          </div>
          <div className="code-console-context-chip">
            <span>Template</span>
            <strong>{template.label}</strong>
          </div>
          <div className="code-console-context-chip">
            <span>Size / Style / Palette</span>
            <strong>
              {size.id} / {style.id} / {palette.id}
            </strong>
          </div>
          <div className="code-console-context-chip">
            <span>Bound data</span>
            <strong>{inputLeaf}</strong>
          </div>
          <div className="code-console-context-chip">
            <span>Sheet</span>
            <strong>{hasData ? String(wizard.sheet) : "-"}</strong>
          </div>
          <div className="code-console-context-chip">
            <span>Contract</span>
            <strong>v{contract?.version ?? meta?.version ?? "?"}</strong>
          </div>
        </div>

        <p className="hint-text">{contextNote(generated, hasData)}</p>
      </section>

      <div className="desk-layout code-console-layout">
        <section className="desk-main">
          <article className="work-card section-card code-console-builder-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Prompt Builder</div>
                <h2>Describe the repository task for the external AI</h2>
              </div>
              <span className="signal-tag">{codeConsoleIntentLabel(draft.intent)}</span>
            </div>

            {notice && (
              <div className={noticeTone === "warning" ? "warning-card" : "success-card"}>
                {notice}
              </div>
            )}

            {!hasData && (
              <div className="warning-card">
                No current data file is bound to Plot. Code Console can still generate a repo-native
                prompt and scaffold, but data context and full-data export stay unavailable.
              </div>
            )}

            {!wizard.sidecarReady && (
              <div className="warning-card">
                Sidecar is offline. Generate and export actions will fail until the sidecar comes
                back.
              </div>
            )}

            {(generateState.error || exportState.error) && (
              <div className="warning-card">{generateState.error ?? exportState.error}</div>
            )}

            <div className="mode-switch code-console-intent-switch" role="tablist" aria-label="Task mode">
              {CODE_CONSOLE_INTENTS.map((item) => (
                <button
                  className={`mode-button ${draft.intent === item.id ? "active-tone" : ""}`}
                  key={item.id}
                  onClick={() => codeConsoleActions.setIntent(item.id)}
                  type="button"
                >
                  {item.label}
                </button>
              ))}
            </div>

            <div className="focus-panel code-console-intent-panel">
              <span>{codeConsoleIntentHint(draft.intent)}</span>
            </div>

            <div className="field-grid code-console-field-grid">
              <label>
                <span className="field-label">Base template</span>
                <select
                  className="field"
                  onChange={(event) => codeConsoleActions.setTemplateId(event.target.value)}
                  value={template.id}
                >
                  {(meta?.templates ?? [template]).map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.label}
                    </option>
                  ))}
                </select>
              </label>

              <label>
                <span className="field-label">Target size</span>
                <select
                  className="field"
                  onChange={(event) => codeConsoleActions.setSizeId(event.target.value)}
                  value={size.id}
                >
                  {(sizeOptions.length > 0 ? sizeOptions : [size]).map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.label}
                    </option>
                  ))}
                </select>
              </label>

              <label>
                <span className="field-label">Style preset</span>
                <select
                  className="field"
                  onChange={(event) => codeConsoleActions.setStylePreset(event.target.value)}
                  value={style.id}
                >
                  {(availableStyles.length > 0
                    ? availableStyles
                    : [{ id: style.id, label: style.label }]).map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.label}
                    </option>
                  ))}
                </select>
              </label>

              <label>
                <span className="field-label">Palette preset</span>
                <select
                  className="field"
                  onChange={(event) => codeConsoleActions.setPalettePreset(event.target.value)}
                  value={palette.id}
                >
                  {(availablePalettes.length > 0
                    ? availablePalettes
                    : [{ id: palette.id, label: palette.label }]).map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.label}
                    </option>
                  ))}
                </select>
              </label>
            </div>

            <label>
              <span className="field-label">Suggested target path</span>
              <input
                className="field"
                onChange={(event) => codeConsoleActions.setTargetPath(event.target.value)}
                placeholder={defaultCodeConsoleTargetPath(draft.intent, template.id)}
                type="text"
                value={draft.targetPath}
              />
            </label>

            <label>
              <span className="field-label">What should the external AI implement?</span>
              <textarea
                aria-label="Code console brief"
                className="field code-console-brief"
                onChange={(event) => codeConsoleActions.setBrief(event.target.value)}
                placeholder={codeConsoleBriefPlaceholder(draft.intent)}
                rows={6}
                value={draft.brief}
              />
            </label>

            <div className="focus-panel code-console-template-summary">
              <span>
                Session-backed default: {template.label} · allowed sizes {template.allowed_sizes.join(", ")} ·
                styles {template.available_styles.join(", ")} · palettes{" "}
                {template.available_palettes.join(", ")}
              </span>
            </div>

            <div className="code-console-check-grid">
              <label className="toggle-card">
                <input
                  aria-label="Attach current data context"
                  checked={draft.includeDataContext}
                  disabled={!hasData}
                  onChange={(event) =>
                    codeConsoleActions.setIncludeDataContext(event.target.checked)
                  }
                  type="checkbox"
                />
                <span>
                  <strong>Attach current data context</strong>
                  <small>Include lightweight schema, column summary, and sample rows from sidecar.</small>
                </span>
              </label>

              <label className="toggle-card">
                <input
                  aria-label="Attach inspect / recommendation summary"
                  checked={draft.includeInspectionSummary}
                  disabled={!hasData || wizard.inspection == null}
                  onChange={(event) =>
                    codeConsoleActions.setIncludeInspectionSummary(event.target.checked)
                  }
                  type="checkbox"
                />
                <span>
                  <strong>Attach inspect / recommendation summary</strong>
                  <small>Bring in the current inspect signals and recommendation hints.</small>
                </span>
              </label>

              <label className="toggle-card">
                <input
                  aria-label="Attach current project context"
                  checked={draft.includeProjectContext}
                  disabled={!hasProjectContext}
                  onChange={(event) =>
                    codeConsoleActions.setIncludeProjectContext(event.target.checked)
                  }
                  type="checkbox"
                />
                <span>
                  <strong>Attach current project context</strong>
                  <small>Only available when the current plot session came from a validated project file.</small>
                </span>
              </label>

              <label className="toggle-card">
                <input
                  aria-label="Opt in to full-data export"
                  checked={draft.includeFullDataBundle}
                  disabled={!hasData}
                  onChange={(event) =>
                    codeConsoleActions.setIncludeFullDataBundle(event.target.checked)
                  }
                  type="checkbox"
                />
                <span>
                  <strong>Opt in to full-data export</strong>
                  <small>Default generate stays lightweight. Full-data bundle export is explicit and sidecar-driven.</small>
                </span>
              </label>
            </div>

            <div className="step-actions">
              <button
                className="primary-button"
                disabled={generateState.busy || !wizard.sidecarReady}
                onClick={() => void handleGenerate()}
                type="button"
              >
                {generateState.busy ? "Generating…" : "Generate AI bridge"}
              </button>
              <button
                  className="ghost-button"
                  disabled={exportState.busy || !wizard.sidecarReady}
                  onClick={() => void handleExport()}
                  type="button"
                >
                  {includeFullDataExport ? "Export full-data bundle" : "Export AI bundle"}
                </button>
              <button className="ghost-button" onClick={handleReset} type="button">
                Reset draft
              </button>
            </div>
          </article>

          <article className="work-card section-card code-console-preview-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Repo-native AI Prompt</div>
                <h2>Prompt text generated by sidecar</h2>
              </div>
              <button
                className="ghost-button"
                disabled={!generated}
                onClick={() => generated && void handleCopy(generated.prompt_text, "AI prompt")}
                type="button"
              >
                Copy AI prompt
              </button>
            </div>

            <pre aria-label="Generated AI prompt" className="code-console-preview">
              {generated?.prompt_text ??
                "Generate AI bridge to produce the final repo-native prompt from sidecar."}
            </pre>
          </article>

          <article className="work-card section-card code-console-preview-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Starter Scaffold</div>
                <h2>Project-native scaffold generated by sidecar</h2>
              </div>
              <button
                className="ghost-button"
                disabled={!generated}
                onClick={() =>
                  generated && void handleCopy(generated.scaffold_text, "Starter scaffold")
                }
                type="button"
              >
                Copy scaffold
              </button>
            </div>

            <pre aria-label="Generated Python scaffold" className="code-console-preview">
              {generated?.scaffold_text ??
                "Generate AI bridge to produce a scaffold that still reuses SciPlot God helpers."}
            </pre>
          </article>

          <article className="work-card section-card code-console-preview-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">AI Context Bundle</div>
                <h2>Lightweight context summary and bundle export</h2>
              </div>
              <button
                className="ghost-button"
                disabled={!generated}
                onClick={() =>
                  generated &&
                  void handleCopy(generated.lightweight_bundle.text, "Lightweight AI context")
                }
                type="button"
              >
                Copy context
              </button>
            </div>

            <pre aria-label="Generated AI context bundle" className="code-console-preview">
              {generated?.lightweight_bundle.text ??
                "Generate AI bridge to build the lightweight context bundle from the current session."}
            </pre>

            <div className="code-console-export-summary">
              <div className="context-row">
                <span>Export mode</span>
                <strong>{includeFullDataExport ? "Full data (opt-in)" : "Lightweight only"}</strong>
              </div>
              <div className="context-row">
                <span>Latest bundle</span>
                <strong>{exportedBundle ? formatLeaf(exportedBundle.bundle_dir) : "Not exported yet"}</strong>
              </div>
              <div className="step-actions">
                <button
                  className="ghost-button"
                  disabled={!exportedBundle}
                  onClick={() => void handleReveal(exportedBundle?.bundle_dir)}
                  type="button"
                >
                  Reveal generated folder
                </button>
                <button
                  className="ghost-button"
                  disabled={!exportedBundle}
                  onClick={() => void handleReveal(exportedBundle?.zip_path)}
                  type="button"
                >
                  Reveal zip
                </button>
                <button
                  className="ghost-button"
                  disabled={!exportedBundle}
                  onClick={() => exportedBundle && void handleCopy(exportedBundle.manifest_path, "Manifest path")}
                  type="button"
                >
                  Copy manifest path
                </button>
              </div>
            </div>
          </article>
        </section>

        <aside className="desk-context code-console-context">
          <article className="context-card code-console-defaults-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Current Defaults</div>
                <h3>Contract locks and session-derived values</h3>
              </div>
            </div>

            <div className="code-console-list-block">
              <h4>Locked by contract</h4>
              <ul className="bullet-list">
                {defaultsPanel.locked_by_contract.map((item) => (
                  <li key={`${item.label}-${item.value}`}>
                    <strong>{item.label}:</strong> {item.value}
                    <br />
                    <span className="hint-text">{item.reason}</span>
                  </li>
                ))}
              </ul>
            </div>

            <div className="code-console-list-block">
              <h4>User selectable</h4>
              <ul className="bullet-list">
                {defaultsPanel.user_selectable.map((item) => (
                  <li key={`${item.label}-${item.value}`}>
                    <strong>{item.label}:</strong> {item.value}
                    <br />
                    <span className="hint-text">{item.reason}</span>
                  </li>
                ))}
              </ul>
            </div>

            <div className="code-console-list-block">
              <h4>Derived from session</h4>
              <ul className="bullet-list">
                {defaultsPanel.derived_from_session.map((item) => (
                  <li key={`${item.label}-${item.value}`}>
                    <strong>{item.label}:</strong> {item.value}
                    <br />
                    <span className="hint-text">{item.reason}</span>
                  </li>
                ))}
              </ul>
            </div>
          </article>

          <article className="context-card code-console-sources-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Truth Sources</div>
                <h3>Trusted inputs for the external AI</h3>
              </div>
            </div>

            <ul className="bullet-list code-console-source-list">
              {truthSources.map((source) => (
                <li key={source.id}>
                  <strong>{source.label}</strong>
                  <br />
                  <code>{source.display_path ?? source.label}</code>
                  <br />
                  <span className="hint-text">{source.reason}</span>
                </li>
              ))}
            </ul>
          </article>

          <article className="context-card code-console-sources-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Current Data Context</div>
                <h3>Session-linked data summary</h3>
              </div>
            </div>

            {generated ? (
              <>
                <div className="context-list">
                  <div className="context-row">
                    <span>Detected model</span>
                    <strong>{generated.data_context.model_label}</strong>
                  </div>
                  <div className="context-row">
                    <span>Raw rows / columns</span>
                    <strong>
                      {generated.data_context.raw_row_count} / {generated.data_context.raw_column_count}
                    </strong>
                  </div>
                  <div className="context-row">
                    <span>Missing cells</span>
                    <strong>{generated.data_context.missing_summary.empty_cells ?? 0}</strong>
                  </div>
                  <div className="context-row">
                    <span>Recommended template</span>
                    <strong>{generated.data_context.recommendation.template}</strong>
                  </div>
                </div>

                <div className="code-console-list-block">
                  <h4>Columns</h4>
                  <ul className="bullet-list">
                    {generated.data_context.column_summaries.slice(0, 8).map((column) => (
                      <li key={column.name}>
                        <strong>{column.name}</strong> · {column.inferred_type} · non-empty{" "}
                        {column.non_empty_count}
                      </li>
                    ))}
                  </ul>
                </div>
              </>
            ) : (
              <div className="placeholder-card">
                {hasData
                  ? `Current file: ${formatLeaf(wizard.inputPath)} · ${wizard.inspection?.model_label ?? "Inspect ready"}`
                  : "No bound data yet. Generate later after opening a plot session to pull sidecar-backed data context."}
              </div>
            )}
          </article>

          <article className="context-card code-console-scaffold-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Scaffold Preview</div>
                <h3>Quick copy of the generated starter code</h3>
              </div>
              <button
                className="ghost-button"
                disabled={!generated}
                onClick={() => generated && void handleCopy(generated.scaffold_text, "Starter scaffold")}
                type="button"
              >
                Copy scaffold
              </button>
            </div>

            <pre aria-label="Generated scaffold preview" className="code-console-scaffold">
              {generated
                ? previewSnippet(generated.scaffold_text)
                : "Generate AI bridge to preview the sidecar-generated scaffold here."}
            </pre>
          </article>
        </aside>
      </div>
    </div>
  );
}
