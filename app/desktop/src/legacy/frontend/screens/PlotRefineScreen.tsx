import { AppIcon } from "../components/AppIcon";
import { MacButton } from "../components/mac/MacButton";
import { MacInspectorSection } from "../components/mac/MacInspectorSection";
import { MacPanel } from "../components/mac/MacPanel";
import { MacSegmentedControl } from "../components/mac/MacSegmentedControl";
import { MacSelect } from "../components/mac/MacSelect";
import { MacStatusPill } from "../components/mac/MacStatusPill";
import { formatLeaf, paletteLabel, publicPaletteChoices, publicStyleChoices, sizeChoices, styleLabel, templateLabel } from "../lib/workbench";
import { templateMeta } from "../lib/wizard";
import type { PreviewItem, RenderOptionsPayload, TemplateName, WorkbenchMeta } from "../lib/types";

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
          <MacStatusPill tone="neutral">Preview</MacStatusPill>
          <strong>{preview?.filename ?? "No preview yet"}</strong>
        </div>
        {previews.length > 1 ? (
          <MacSegmentedControl
            label="Preview variants"
            value={String(previewIndex)}
            options={previews.map((item, index) => ({
              value: String(index),
              label: item.filename.replace(/\.pdf$/i, "") || String(index + 1),
            }))}
            onChange={(value) => onSelectPreview(Number(value))}
          />
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

export function PlotRefineScreen({
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
          <MacButton variant="secondary" onClick={onCheckReadiness} disabled={!template || readinessBusy}>
            {readinessBusy ? "Checking..." : "Check readiness"}
          </MacButton>
          <MacButton variant="primary" onClick={onExport} disabled={!template || exportBusy}>
            {exportBusy ? "Exporting..." : "Export bundle"}
          </MacButton>
        </div>
      </div>

      <div className="screen-grid refine-grid">
        <MacPanel tone="preview">
          <PreviewPanel
            previews={previews}
            previewIndex={previewIndex}
            onSelectPreview={onSelectPreview}
            previewBusy={previewBusy}
            previewError={previewError}
          />
        </MacPanel>

        <MacPanel as="aside" className="inspector-panel refine-inspector">
          <div className="card-header">
            <MacStatusPill tone="accent">Inspector</MacStatusPill>
            <h3>{templateLabel(meta, template)}</h3>
          </div>

          <MacInspectorSection title="Template summary">
            <p className="support-copy">
              {currentTemplate?.description ?? "Choose a template from Plot Template first."}
            </p>
          </MacInspectorSection>

          {editable.has("size") && sizes.length > 0 ? (
            <MacInspectorSection title="Figure size">
              <MacSelect
                label="Preset"
                value={options.size ?? sizes[0]?.id ?? ""}
                options={sizes.map((size) => ({ value: size.id, label: size.label }))}
                onChange={(event) => onOptionChange({ size: event.target.value })}
              />
            </MacInspectorSection>
          ) : null}

          {editable.has("xscale") || editable.has("yscale") || editable.has("reverse_x") ? (
            <MacInspectorSection title="Axes and scales">
              {editable.has("xscale") ? (
                <MacSegmentedControl
                  label="X scale"
                  value={options.xscale ?? "linear"}
                  options={[
                    { value: "linear", label: "Linear" },
                    { value: "log", label: "Log" },
                  ]}
                  onChange={(value) => onOptionChange({ xscale: value })}
                />
              ) : null}
              {editable.has("yscale") ? (
                <MacSegmentedControl
                  label="Y scale"
                  value={options.yscale ?? "linear"}
                  options={[
                    { value: "linear", label: "Linear" },
                    { value: "log", label: "Log" },
                  ]}
                  onChange={(value) => onOptionChange({ yscale: value })}
                />
              ) : null}
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
            </MacInspectorSection>
          ) : null}

          {editable.has("style_preset") || editable.has("palette_preset") ? (
            <MacInspectorSection title="Style and palette">
              {editable.has("style_preset") && styles.length > 0 ? (
                <MacSelect
                  label="Style preset"
                  value={options.style_preset ?? styles[0]?.id ?? ""}
                  options={styles.map((style) => ({ value: style.id, label: style.label }))}
                  onChange={(event) => onOptionChange({ style_preset: event.target.value })}
                />
              ) : null}
              {editable.has("palette_preset") && palettes.length > 0 ? (
                <MacSelect
                  label="Palette preset"
                  value={options.palette_preset ?? palettes[0]?.id ?? ""}
                  options={palettes.map((palette) => ({ value: String(palette.id), label: palette.label }))}
                  onChange={(event) => onOptionChange({ palette_preset: event.target.value })}
                />
              ) : null}
            </MacInspectorSection>
          ) : null}

          {editable.has("show_colorbar") ? (
            <MacInspectorSection title="Heatmap options">
              <label className="checkbox-row">
                <input
                  type="checkbox"
                  checked={Boolean(options.show_colorbar)}
                  onChange={(event) => onOptionChange({ show_colorbar: event.target.checked })}
                />
                <span>Show colorbar</span>
              </label>
            </MacInspectorSection>
          ) : null}

          <MacInspectorSection title="Export">
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
              <MacButton variant="secondary" onClick={onOpenOutputDir} icon={<AppIcon name="folder" />}>
                Reveal output folder
              </MacButton>
            ) : null}
            {exportOutputs.length > 0 ? (
              <ul className="bullet-list compact">
                {exportOutputs.slice(0, 4).map((output) => (
                  <li key={output}>{formatLeaf(output)}</li>
                ))}
              </ul>
            ) : null}
          </MacInspectorSection>

          <MacInspectorSection title="Submission report">
            {submissionChecks.length > 0 ? (
              <ul className="check-list">
                {submissionChecks.slice(0, 5).map((check) => (
                  <li key={check.id}>
                    <MacStatusPill
                      tone={
                        check.status === "pass"
                          ? "success"
                          : check.status === "warning" || check.status === "critical"
                            ? "warning"
                            : "neutral"
                      }
                    >
                      {check.status}
                    </MacStatusPill>
                    <span>{check.message}</span>
                  </li>
                ))}
              </ul>
            ) : (
              <div className="empty-panel compact">
                <small>Run readiness check to populate inline export feedback.</small>
              </div>
            )}
          </MacInspectorSection>
        </MacPanel>
      </div>
    </section>
  );
}
