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
import { inspectionRecommendationChoices } from "../../lib/wizard";

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
    () => {
      if (!inspection) {
        return [];
      }
      if (inspection.recommendations?.length) {
        return inspectionRecommendationChoices(meta, inspection, 5);
      }
      return compatibleTemplates.slice(0, 5).map((template, index) => ({
        template,
        recommendation: {
          template_id: template.id,
          score: 100 - index,
          why_hard_match:
            index === 0
              ? [inspection.recommendation.reason]
              : [`Compatible with detected model ${inspection.model_label}.`],
          why_soft_prior:
            index === 0 ? [] : [`Compatible with detected model ${inspection.model_label}.`],
          inferred_mapping: {},
          optional_enhancements: [],
          preview_config_summary: {},
        },
      }));
    },
    [compatibleTemplates, inspection, meta],
  );
  const alternatives = useMemo(
    () => {
      const recommendedTemplateIds = new Set(topRecommendations.map((item) => item.template.id));
      return compatibleTemplates.filter((template) => !recommendedTemplateIds.has(template.id));
    },
    [compatibleTemplates, topRecommendations],
  );

  return (
    <div className="plot-type-workspace">
      <header className="plot-type-header">
        <div className="plot-type-header-copy">
          <strong>Template recommendation workspace</strong>
          <p>We inspected your data. Choose the best chart template before tuning.</p>
        </div>
        <div className="plot-type-header-meta">
          <span title={inputPath ?? "No source loaded"}>
            {inputPath ? formatLeaf(inputPath) : "No source loaded"}
          </span>
          {inspection ? <span>{inspection.model_label}</span> : <span>Awaiting inspect</span>}
        </div>
      </header>

      <div className="plot-type-grid">
        <section className="plot-type-recommendations">
          <div className="plot-type-section-head">
            <h3>Top recommendations</h3>
            {!recommendationApplied && inspection && (
              <button className="ghost-button" onClick={onApplyRecommendedSelection} type="button">
                Use recommended
              </button>
            )}
          </div>

          {!inspection ? (
            <div className="placeholder-card">Run inspect first to unlock template recommendations.</div>
          ) : (
            <div className="plot-type-cards">
              {topRecommendations.map(({ template, recommendation }, index) => {
                const selected = selectedTemplate === template.id;
                return (
                  <article
                    className={`plot-type-card ${selected ? "selected" : ""}`}
                    key={template.id}
                  >
                    <div className={`plot-type-card-thumb ${templateMockClass(template.id)}`} />
                    <div className="plot-type-card-copy">
                      <div className="plot-type-card-title-row">
                        <strong>{template.label}</strong>
                        <span>
                          Rank #{index + 1} · Score {recommendation.score.toFixed(1)}
                        </span>
                      </div>
                      <p>{recommendation.why_hard_match[0] ?? "Compatible with detected data."}</p>
                      {recommendation.why_soft_prior[0] && (
                        <div className="wb-inline-meta">{recommendation.why_soft_prior[0]}</div>
                      )}
                      <div className="plot-type-card-meta">
                        <span>Size {template.default_size}</span>
                        <span>{template.category}</span>
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
          )}

          {alternatives.length > 0 && (
            <section className="plot-type-alternatives">
              <div className="plot-type-section-head">
                <h4>Other compatible templates</h4>
              </div>
              <div className="plot-type-alt-list">
                {alternatives.map((template) => (
                  <CompactListRow
                    key={template.id}
                    onSelect={() => onSelectTemplate(template.id)}
                    right={<span className="wb-inline-meta">Compatible</span>}
                    subtitle={template.category}
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
                    {inspection ? templateCompatibilityReason(inspection.model) : "Not compatible with current model."}
                  </div>
                  {incompatibleTemplates.map((template) => (
                    <CompactListRow
                      onSelect={() => onSelectTemplate(template.id)}
                      disabled
                      key={template.id}
                      right={<span className="wb-inline-meta">Not compatible</span>}
                      subtitle={template.category}
                      title={template.label}
                    />
                  ))}
                </div>
              )}
            </section>
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
              Rendered preview
            </button>
          </div>

          <div className="plot-type-preview-surface">
            {previewMode === "compare" ? (
              <div className="plot-type-compare-view">
                <div className="plot-type-compare-focus">
                  <span>Selected template</span>
                  <strong>{hasTemplate ? templateLabel(meta, selectedTemplate) : "Template selection required"}</strong>
                  <p>
                    {inspection
                      ? "Use recommendation cards to compare compatibility before continuing."
                      : "Inspect and template recommendation will appear here after data detection."}
                  </p>
                </div>
                <div className="plot-type-compare-thumbs">
                  {topRecommendations.slice(0, 3).map(({ template }) => (
                    <button
                      className={`plot-type-compare-thumb ${selectedTemplate === template.id ? "selected" : ""}`}
                      key={template.id}
                      onClick={() => onSelectTemplate(template.id)}
                      type="button"
                    >
                      <div className={`plot-type-card-thumb ${templateMockClass(template.id)}`} />
                      <strong>{template.label}</strong>
                    </button>
                  ))}
                </div>
              </div>
            ) : hasTemplate ? (
              <div className="plot-type-rendered-preview">
                {sheetNamesLength > 1 && (
                  <div className="plot-type-preview-toolbar">
                    <button className="ghost-button" onClick={onChangeSheet} type="button">
                      Change sheet
                    </button>
                  </div>
                )}
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
        <button
          className="plot-type-continue"
          disabled={!hasTemplate}
          onClick={onContinueToTune}
          type="button"
        >
          Continue to tune
        </button>
      </footer>
    </div>
  );
}
