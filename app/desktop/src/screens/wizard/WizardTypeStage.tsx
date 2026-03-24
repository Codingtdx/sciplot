import { useMemo, useState } from "react";

import { PreviewPane } from "../../components/PreviewPane";
import { CompactListRow } from "../../components/workbench/V2Primitives";
import type {
  InputInspection,
  PreviewItem,
  TemplateName,
  WorkbenchMeta,
  WorkbenchTemplate,
} from "../../lib/types";
import {
  formatLeaf,
  templateCompatibilityReason,
  templateLabel,
} from "../../lib/workbench";

type Props = {
  inputPath: string | null;
  inspection: InputInspection | null;
  recommendationApplied: boolean;
  compatibleTemplates: WorkbenchTemplate[];
  incompatibleTemplates: WorkbenchTemplate[];
  selectedTemplate: TemplateName | null;
  showAllTemplates: boolean;
  hasTemplate: boolean;
  meta: WorkbenchMeta | null;
  previewBusy: boolean;
  previewError: string | null;
  previewIndex: number;
  previews: PreviewItem[];
  sheetNamesLength: number;
  onChangePreviewIndex(value: number): void;
  onChangeSheet(): void;
  onApplyRecommendedSelection(): void;
  onSelectTemplate(value: TemplateName): void;
  onToggleShowAllTemplates(): void;
  onContinueToTune(): void;
};

function templateMockClass(templateId: TemplateName) {
  if (templateId.includes("heat")) {
    return "heat";
  }
  if (templateId.includes("bar") || templateId.includes("box") || templateId.includes("violin")) {
    return "bar";
  }
  if (templateId.includes("scatter")) {
    return "scatter";
  }
  return "curve";
}

function templateCategoryLabel(template: WorkbenchTemplate) {
  return template.category.replace(/_/g, " ");
}

function recommendationReason(
  template: WorkbenchTemplate,
  inspection: InputInspection | null,
) {
  if (!inspection) {
    return "Run inspect to get data-aware template guidance.";
  }
  if (inspection.recommendation.template === template.id) {
    return inspection.recommendation.reason;
  }
  return `Compatible with detected model ${inspection.model_label}.`;
}

function templateHint(template: WorkbenchTemplate, inspection: InputInspection | null) {
  const category = templateCategoryLabel(template);
  if (!inspection) {
    return `${template.default_size} · ${category}`;
  }
  if (inspection.recommendation.template === template.id) {
    return `${template.default_size} · best fit for ${inspection.model_label}`;
  }
  return `${template.default_size} · compatible with ${inspection.model_label}`;
}

export function WizardTypeStage({
  inputPath,
  inspection,
  recommendationApplied,
  compatibleTemplates,
  incompatibleTemplates,
  selectedTemplate,
  showAllTemplates,
  hasTemplate,
  meta,
  previewBusy,
  previewError,
  previewIndex,
  previews,
  sheetNamesLength,
  onChangePreviewIndex,
  onChangeSheet,
  onApplyRecommendedSelection,
  onSelectTemplate,
  onToggleShowAllTemplates,
  onContinueToTune,
}: Props) {
  const [previewMode, setPreviewMode] = useState<"compare" | "preview">("compare");
  const topRecommendations = useMemo(
    () => compatibleTemplates.slice(0, 5),
    [compatibleTemplates],
  );
  const alternatives = useMemo(
    () => compatibleTemplates.slice(5),
    [compatibleTemplates],
  );
  const sourceLabel = inputPath ? formatLeaf(inputPath) : "No source loaded";
  const activeTemplate = selectedTemplate ?? inspection?.recommendation.template ?? topRecommendations[0]?.id ?? null;
  const activeTemplateLabel = hasTemplate ? templateLabel(meta, selectedTemplate) : "Suggested template";

  return (
    <div className="plot-type-studio">
      <header className="plot-type-header">
        <div className="plot-type-header-copy">
          <strong>Template recommendation workspace</strong>
          <p>We inspected your data and are helping choose the best chart template.</p>
        </div>
        <div className="plot-type-header-source">
          <span>Source</span>
          <strong title={sourceLabel}>{sourceLabel}</strong>
          <span title={inspection?.model_label ?? "Awaiting inspect"}>
            {inspection ? inspection.model_label : "Awaiting inspect"}
          </span>
        </div>
      </header>

      <div className="plot-type-studio-grid">
        <section className="plot-type-recommendation-pane">
          <div className="plot-type-pane-head">
            <span>Recommended templates</span>
            <h2>Choose the chart family</h2>
            <p>These cards are ranked from the strongest fit to broader compatible alternatives.</p>
            <div className="plot-type-supported-types">
              {inspection ? `Detected ${inspection.model_label}` : "Run inspect to unlock template guidance."}
            </div>
          </div>

          {!inspection ? (
            <div className="placeholder-card">Run inspect first to unlock template recommendations.</div>
          ) : (
            <>
              <div className="plot-type-recommendation-stack">
                {topRecommendations.map((template) => {
                  const selected = selectedTemplate === template.id;
                  const recommended = inspection.recommendation.template === template.id;
                  return (
                    <article
                      className={`plot-type-recommendation-card ${selected ? "selected" : ""} ${recommended ? "recommended" : ""}`}
                      key={template.id}
                    >
                      <div className={`plot-type-card-thumb ${templateMockClass(template.id)}`} aria-hidden="true" />
                      <div className="plot-type-recommendation-copy">
                        <div className="plot-type-recommendation-title-row">
                          <strong>{template.label}</strong>
                          <span>{recommended ? "Recommended" : "Compatible"}</span>
                        </div>
                        <p>{recommendationReason(template, inspection)}</p>
                        <div className="plot-type-recommendation-hint">{templateHint(template, inspection)}</div>
                        <div className="plot-type-recommendation-meta">
                          <span>{template.default_size}</span>
                          <span>{templateCategoryLabel(template)}</span>
                        </div>
                      </div>
                      <button
                        className={selected ? "primary-button" : "ghost-button"}
                        onClick={() => onSelectTemplate(template.id)}
                        type="button"
                      >
                        {selected ? "Selected" : "Select"}
                      </button>
                    </article>
                  );
                })}
              </div>

              {alternatives.length > 0 && (
                <section className="plot-type-alternatives">
                  <div className="plot-type-section-head">
                    <h3>Other compatible templates</h3>
                  </div>
                  <div className="plot-type-alt-list">
                    {alternatives.map((template) => (
                      <CompactListRow
                        key={template.id}
                        onSelect={() => onSelectTemplate(template.id)}
                        right={<span className="wb-inline-meta">Compatible</span>}
                        subtitle={`${templateCategoryLabel(template)} · ${template.default_size}`}
                        title={template.label}
                      />
                    ))}
                  </div>
                </section>
              )}

              {incompatibleTemplates.length > 0 && (
                <section className="plot-type-incompatible">
                  <button className="ghost-button" onClick={onToggleShowAllTemplates} type="button">
                    {showAllTemplates ? "Hide more types" : "More types"}
                  </button>
                  {showAllTemplates && (
                    <div className="plot-type-incompatible-list">
                      <div className="hint-text">
                        {inspection
                          ? templateCompatibilityReason(inspection.model)
                          : "Not compatible with current model."}
                      </div>
                      {incompatibleTemplates.map((template) => (
                        <CompactListRow
                          onSelect={() => onSelectTemplate(template.id)}
                          disabled
                          key={template.id}
                          right={<span className="wb-inline-meta">Not compatible</span>}
                          subtitle={`${templateCategoryLabel(template)} · ${template.default_size}`}
                          title={template.label}
                        />
                      ))}
                    </div>
                  )}
                </section>
              )}
            </>
          )}
        </section>

        <section className="plot-type-preview-pane">
          <div className="plot-type-preview-tabs" role="tablist" aria-label="Type stage preview tabs">
            <button
              aria-selected={previewMode === "compare"}
              className={`plot-type-preview-tab ${previewMode === "compare" ? "active" : ""}`}
              onClick={() => setPreviewMode("compare")}
              role="tab"
              type="button"
            >
              Compare
            </button>
            <button
              aria-selected={previewMode === "preview"}
              className={`plot-type-preview-tab ${previewMode === "preview" ? "active" : ""}`}
              onClick={() => setPreviewMode("preview")}
              role="tab"
              type="button"
            >
              Preview
            </button>
          </div>

          <div className="plot-type-preview-surface">
            {previewMode === "compare" ? (
              <div className="plot-type-compare-view">
                <div className="plot-type-compare-focus">
                  <span>{hasTemplate ? "Selected template" : "Suggested template"}</span>
                  <strong>
                    {activeTemplate ? templateLabel(meta, activeTemplate) : "Template selection required"}
                  </strong>
                  <p>
                    {inspection
                      ? "Compare the leading cards here before continuing to Tune."
                      : "Inspect and template recommendation will appear here after data detection."}
                  </p>
                  <div className="plot-type-compare-hints">
                    <span>{inspection?.recommendation.size ?? "Size"}</span>
                    <span>{inspection ? inspection.model_label : "Awaiting inspect"}</span>
                    <span>{hasTemplate ? "Ready to tune" : "Choose one"}</span>
                  </div>
                </div>
                <div className="plot-type-compare-thumbs">
                  {topRecommendations.slice(0, 3).map((template) => (
                    <button
                      className={`plot-type-compare-thumb ${selectedTemplate === template.id ? "selected" : ""}`}
                      key={template.id}
                      onClick={() => onSelectTemplate(template.id)}
                      type="button"
                    >
                      <div className={`plot-type-card-thumb ${templateMockClass(template.id)}`} />
                      <strong>{template.label}</strong>
                      <span>{template.default_size}</span>
                    </button>
                  ))}
                </div>
              </div>
            ) : hasTemplate ? (
              <div className="plot-type-rendered-preview">
                <div className="plot-type-preview-toolbar">
                  <span className="plot-type-preview-toolbar-label">{activeTemplateLabel}</span>
                  {sheetNamesLength > 1 && (
                    <button className="ghost-button" onClick={onChangeSheet} type="button">
                      Change sheet
                    </button>
                  )}
                </div>
                <PreviewPane
                  busy={previewBusy}
                  error={previewError}
                  onChangeIndex={onChangePreviewIndex}
                  previewIndex={previewIndex}
                  previews={previews}
                />
              </div>
            ) : (
              <div className="placeholder-card">Select a compatible template to render preview.</div>
            )}
          </div>
        </section>
      </div>

      <footer className="plot-type-footer">
        <span>
          {hasTemplate
            ? `${templateLabel(meta, selectedTemplate)} selected. Continue to Tune to adjust render options.`
            : "Select a template to continue to Tune."}
        </span>
        <div className="plot-type-footer-actions">
          {!recommendationApplied && inspection ? (
            <button className="ghost-button" onClick={onApplyRecommendedSelection} type="button">
              Use recommendation
            </button>
          ) : null}
          <button
            className="plot-type-continue"
            disabled={!hasTemplate}
            onClick={onContinueToTune}
            type="button"
          >
            Continue to tune
          </button>
        </div>
      </footer>
    </div>
  );
}
