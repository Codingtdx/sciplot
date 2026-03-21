import { useMemo, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { copyTextToClipboard } from "../lib/clipboard";
import {
  buildCodeConsolePrompt,
  buildCodeConsoleScaffold,
  CODE_CONSOLE_INTENTS,
  codeConsoleBriefPlaceholder,
  codeConsoleIntentHint,
  codeConsoleIntentLabel,
  resolveCodeConsolePalette,
  resolveCodeConsoleSize,
  resolveCodeConsoleStyle,
  resolveCodeConsoleTemplate,
} from "../lib/code-console";
import { useCodeConsoleStore } from "../lib/store";
import type { PlotContract, WorkbenchMeta } from "../lib/types";

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
      intent: state.intent,
      palettePreset: state.palettePreset,
      sizeId: state.sizeId,
      stylePreset: state.stylePreset,
      targetPath: state.targetPath,
      templateId: state.templateId,
    })),
  );
  const {
    setBrief,
    setIntent,
    setPalettePreset,
    setSizeId,
    setStylePreset,
    setTargetPath,
    setTemplateId,
    reset,
  } = useCodeConsoleStore(
    useShallow((state) => ({
      reset: state.reset,
      setBrief: state.setBrief,
      setIntent: state.setIntent,
      setPalettePreset: state.setPalettePreset,
      setSizeId: state.setSizeId,
      setStylePreset: state.setStylePreset,
      setTargetPath: state.setTargetPath,
      setTemplateId: state.setTemplateId,
    })),
  );
  const [copyNotice, setCopyNotice] = useState<string | null>(null);
  const [copyTone, setCopyTone] = useState<"success" | "warning">("success");

  const template = useMemo(
    () => resolveCodeConsoleTemplate(meta, draft.templateId),
    [draft.templateId, meta],
  );
  const size = useMemo(
    () => resolveCodeConsoleSize(meta, template, draft.sizeId),
    [draft.sizeId, meta, template],
  );
  const style = useMemo(
    () => resolveCodeConsoleStyle(meta, template, draft.stylePreset),
    [draft.stylePreset, meta, template],
  );
  const palette = useMemo(
    () => resolveCodeConsolePalette(meta, template, draft.palettePreset),
    [draft.palettePreset, meta, template],
  );
  const promptText = useMemo(
    () =>
      buildCodeConsolePrompt({
        draft: {
          ...draft,
          sizeId: size.id,
          stylePreset: style.id,
          palettePreset: palette.id,
          templateId: template.id,
        },
        meta,
        contract,
      }),
    [contract, draft, meta, palette.id, size.id, style.id, template.id],
  );
  const scaffoldText = useMemo(
    () =>
      buildCodeConsoleScaffold({
        draft: {
          ...draft,
          sizeId: size.id,
          stylePreset: style.id,
          palettePreset: palette.id,
          templateId: template.id,
        },
        meta,
      }),
    [draft, meta, palette.id, size.id, style.id, template.id],
  );

  const availableStyles = meta?.styles.filter((item) => item.public && template.available_styles.includes(item.id)) ?? [];
  const availablePalettes = meta?.palettes.filter((item) => template.available_palettes.includes(item.id)) ?? [];
  const sizeOptions = meta?.sizes.filter((item) => template.allowed_sizes.includes(item.id)) ?? [];

  const handleCopy = async (value: string, label: string) => {
    try {
      await copyTextToClipboard(value);
      setCopyTone("success");
      setCopyNotice(`${label} copied.`);
    } catch (error) {
      setCopyTone("warning");
      setCopyNotice(error instanceof Error ? error.message : String(error));
    }
  };

  const handleReset = () => {
    reset();
    setCopyNotice(null);
  };

  return (
    <div className="desk-layout code-console-layout">
      <section className="desk-main">
        <article className="work-card section-card code-console-builder-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Prompt Builder</div>
              <h2>Generate a repo-native AI prompt for custom plot code</h2>
            </div>
            <span className="signal-tag">{codeConsoleIntentLabel(draft.intent)}</span>
          </div>

          <p className="hint-text">
            This workspace is for asking GPT or another coding model to write plotting code that
            still obeys SciPlot God defaults for size, style, palette, margins, and export
            behavior.
          </p>

          {copyNotice && (
            <div className={copyTone === "warning" ? "warning-card" : "success-card"}>
              {copyNotice}
            </div>
          )}

          {!meta && (
            <div className="warning-card">
              Sidecar metadata is not loaded yet. The prompt will fall back to project defaults
              until metadata becomes available.
            </div>
          )}

          <div className="mode-switch code-console-intent-switch" role="tablist" aria-label="Task mode">
            {CODE_CONSOLE_INTENTS.map((item) => (
              <button
                className={`mode-button ${draft.intent === item.id ? "active-tone" : ""}`}
                key={item.id}
                onClick={() => setIntent(item.id)}
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
                onChange={(event) => setTemplateId(event.target.value)}
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
              <span className="field-label">Panel size</span>
              <select
                className="field"
                onChange={(event) => setSizeId(event.target.value)}
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
                onChange={(event) => setStylePreset(event.target.value)}
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
                onChange={(event) => setPalettePreset(event.target.value)}
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
            <span className="field-label">Preferred target path</span>
            <input
              className="field"
              onChange={(event) => setTargetPath(event.target.value)}
              placeholder="例如：src/rendering/custom_curve_helper.py"
              type="text"
              value={draft.targetPath}
            />
          </label>

          <label>
            <span className="field-label">What should the other AI implement?</span>
            <textarea
              aria-label="Code console brief"
              className="field code-console-brief"
              onChange={(event) => setBrief(event.target.value)}
              placeholder={codeConsoleBriefPlaceholder(draft.intent)}
              rows={6}
              value={draft.brief}
            />
          </label>

          <div className="focus-panel code-console-template-summary">
            <span>
              {template.label} · allowed sizes {template.allowed_sizes.join(", ")} · styles{" "}
              {template.available_styles.join(", ")} · palettes {template.available_palettes.join(", ")}
            </span>
          </div>

          <div className="step-actions">
            <button className="primary-button" onClick={() => void handleCopy(promptText, "AI prompt")} type="button">
              Copy AI prompt
            </button>
            <button className="ghost-button" onClick={() => void handleCopy(scaffoldText, "Python scaffold")} type="button">
              Copy scaffold
            </button>
            <button className="ghost-button" onClick={handleReset} type="button">
              Reset draft
            </button>
          </div>
        </article>

        <article className="work-card section-card code-console-preview-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">AI Prompt</div>
              <h2>Paste this into GPT or another coding model</h2>
            </div>
            <button
              className="ghost-button"
              onClick={() => void handleCopy(promptText, "AI prompt")}
              type="button"
            >
              Copy
            </button>
          </div>

          <pre aria-label="Generated AI prompt" className="code-console-preview">
            {promptText}
          </pre>
        </article>
      </section>

      <aside className="desk-context code-console-context">
        <article className="context-card code-console-defaults-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Current Defaults</div>
              <h3>What this prompt locks to</h3>
            </div>
          </div>

          <div className="context-list">
            <div className="context-row">
              <span>Template</span>
              <strong>{template.label}</strong>
            </div>
            <div className="context-row">
              <span>Size</span>
              <strong>
                {size.width_mm} x {size.height_mm} mm
              </strong>
            </div>
            <div className="context-row">
              <span>Style</span>
              <strong>{style.label}</strong>
            </div>
            <div className="context-row">
              <span>Palette</span>
              <strong>{palette.label}</strong>
            </div>
            <div className="context-row">
              <span>Margins</span>
              <strong>
                L {contract?.global_frame.left_margin_mm ?? meta?.global_frame.left_margin_mm ?? 14} / R{" "}
                {contract?.global_frame.right_margin_mm ?? meta?.global_frame.right_margin_mm ?? 4.5}
              </strong>
            </div>
          </div>

          {palette.swatches.length > 0 && (
            <div className="code-console-swatches" aria-label="Palette swatches">
              {palette.swatches.slice(0, 6).map((swatch) => (
                <span
                  className="code-console-swatch"
                  key={swatch}
                  style={{ background: swatch }}
                  title={swatch}
                />
              ))}
            </div>
          )}
        </article>

        <article className="context-card code-console-sources-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Truth Sources</div>
              <h3>Files the other AI should trust</h3>
            </div>
          </div>

          <ul className="bullet-list code-console-path-list">
            <li>
              <code>src/plot_contract.json</code>
            </li>
            <li>
              <code>docs/plot_contract.md</code>
            </li>
            <li>
              <code>src/plot_style.py</code>
            </li>
            <li>
              <code>src/rendering/options.py</code>
            </li>
            <li>
              <code>src/rendering/render.py</code>
            </li>
            <li>
              <code>make_plot.py</code>
            </li>
          </ul>
        </article>

        <article className="context-card code-console-scaffold-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Scaffold</div>
              <h3>Repo-native starter code</h3>
            </div>
            <button
              className="ghost-button"
              onClick={() => void handleCopy(scaffoldText, "Python scaffold")}
              type="button"
            >
              Copy
            </button>
          </div>

          <pre aria-label="Generated Python scaffold" className="code-console-scaffold">
            {scaffoldText}
          </pre>
        </article>
      </aside>
    </div>
  );
}
