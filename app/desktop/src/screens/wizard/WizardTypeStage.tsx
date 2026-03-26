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
import {
  inspectionRecommendationSections,
} from "../../lib/wizard";

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
  recommendedTemplateIds: Set<string>,
  overrideReason?: string,
) {
  if (overrideReason) {
    return overrideReason;
  }
  if (!inspection) {
    return "Run inspect to get data-aware template guidance.";
  }
  if (
    recommendedTemplateIds.has(template.id) ||
    inspection.recommendation.template === template.id
  ) {
    return inspection.recommendation.reason;
  }
  return `Compatible with detected model ${inspection.model_label}.`;
}

function templateHint(
  template: WorkbenchTemplate,
  inspection: InputInspection | null,
  recommendedTemplateIds: Set<string>,
) {
  const category = templateCategoryLabel(template);
  if (!inspection) {
    return `${template.default_size} · ${category}`;
  }
  if (
    recommendedTemplateIds.has(template.id) ||
    inspection.recommendation.template === template.id
  ) {
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
  const fallbackRecommendations = useMemo(
    () =>
      compatibleTemplates.slice(0, 5).map((template, index) => ({
        template,
        rank: index + 1,
        score: 100 - index,
        reason: undefined as string | undefined,
        suitabilityHint: undefined as string | undefined,
      })),
    [compatibleTemplates],
  );
  const recommendationSections = useMemo(
    () => (inspection ? inspectionRecommendationSections(meta, inspection) : null),
    [inspection, meta],
  );
  const primaryRecommendations = recommendationSections?.primary ?? [];
  const alternativeRecommendations = recommendationSections?.alternatives ?? [];
  const advancedRecommendations = recommendationSections?.advanced ?? [];
  const visibleRecommendations = useMemo(
    () =>
      recommendationSections
        ? [...primaryRecommendations, ...alternativeRecommendations]
        : fallbackRecommendations,
    [alternativeRecommendations, fallbackRecommendations, primaryRecommendations, recommendationSections],
  );
  const recommendedTemplateIds = useMemo(
    () => new Set(primaryRecommendations.map((item) => item.template.id)),
    [primaryRecommendations],
  );
  const sourceLabel = inputPath ? formatLeaf(inputPath) : "No source loaded";
  const activeTemplate =
    selectedTemplate ?? visibleRecommendations[0]?.template.id ?? inspection?.recommendation.template ?? null;
  const activeTemplateLabel = hasTemplate ? templateLabel(meta, selectedTemplate) : "Suggested template";
  const primaryTemplateId =
    primaryRecommendations[0]?.template.id ??
    inspection?.recommendation.template ??
    visibleRecommendations[0]?.template.id ??
    null;
  const primaryTemplateIds = new Set(
    primaryRecommendations.map((item) => item.template.id),
  );

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
        </div>
      </header>

      <div className="plot-type-studio-grid">
        <section className="plot-type-recommendation-pane">
          <div className="plot-type-pane-head">
            <span>Recommended templates</span>
            <h2>Choose the chart family</h2>
            <p>These cards are ranked from the strongest fit to broader compatible alternatives.</p>
            <div className="plot-type-supported-types">
              {inspection
                ? `Detected ${inspection.model_label} · Confidence ${(inspection.recommendation_confidence ?? 0).toFixed(1)}`
                : "Run inspect to unlock template guidance."}
            </div>
            {inspection?.recommendation_summary ? (
              <div className="wb-inline-meta">{inspection.recommendation_summary}</div>
            ) : null}
          </div>

          {!inspection ? (
            <div className="placeholder-card">Run inspect first to unlock template recommendations.</div>
          ) : (
            <>
              {primaryRecommendations.length > 0 && (
                <section className="plot-type-primary-recommendations">
                  <div className="plot-type-section-head">
                    <h3>{primaryRecommendations.length > 1 ? "Primary recommendations" : "Primary recommendation"}</h3>
                    <p>
                      {primaryRecommendations.length > 1
                        ? "These choices are close enough to present together as co-primary."
                        : "This is the strongest product choice for the detected data."}
                    </p>
                  </div>
                  <div className="plot-type-recommendation-stack">
                    {primaryRecommendations.map((item, index) => {
                      const { template } = item;
                      const selected = selectedTemplate === template.id;
                      const rankLabel = item.recommendation.rank ?? index + 1;
                      return (
                        <article
                          className={`plot-type-recommendation-card ${selected ? "selected" : ""} ${
                            template.id === primaryTemplateId ? "primary" : ""
                          }`}
                          key={template.id}
                        >
                          <div className={`plot-type-card-thumb ${templateMockClass(template.id)}`} aria-hidden="true" />
                          <div className="plot-type-recommendation-copy">
                            <div className="plot-type-recommendation-title-row">
                              <strong>{template.label}</strong>
                              <span>
                                {primaryTemplateIds.has(template.id)
                                  ? template.id === primaryTemplateId
                                    ? "Primary recommendation"
                                    : "Co-primary"
                                  : "Recommended"}
                              </span>
                            </div>
                            <div className="wb-inline-meta">
                              Rank #{rankLabel} · Score {item.recommendation.score.toFixed(1)}
                            </div>
                            <p>
                              {recommendationReason(
                                template,
                                inspection,
                                recommendedTemplateIds,
                                item.recommendation.reason,
                              )}
                            </p>
                            {item.recommendation.suitability_hint ? (
                              <div className="wb-inline-meta">{item.recommendation.suitability_hint}</div>
                            ) : null}
                            <div className="plot-type-recommendation-hint">
                              {templateHint(template, inspection, recommendedTemplateIds)}
                            </div>
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
                </section>
              )}

              {alternativeRecommendations.length > 0 && (
                <section className="plot-type-alternatives">
                  <div className="plot-type-section-head">
                    <h3>Alternative recommendations</h3>
                    <p>These are high-quality nearby choices that stay visible without crowding the primary lane.</p>
                  </div>
                  <div className="plot-type-alt-list">
                    {alternativeRecommendations.map((item) => (
                      <CompactListRow
                        key={item.template.id}
                        onSelect={() => onSelectTemplate(item.template.id)}
                        right={<span className="wb-inline-meta">Alternative</span>}
                        subtitle={`${templateCategoryLabel(item.template)} · ${item.template.default_size} · Score ${item.recommendation.score.toFixed(1)}`}
                        title={item.template.label}
                      />
                    ))}
                  </div>
                </section>
              )}

              {advancedRecommendations.length > 0 && (
                <section className="plot-type-alternatives">
                  <div className="plot-type-section-head">
                    <h3>Advanced templates</h3>
                    <p>Technically valid templates that stay out of the default visible shortlist.</p>
                  </div>
                  <div className="plot-type-alt-list">
                    {advancedRecommendations.map((item) => (
                      <CompactListRow
                        key={item.template.id}
                        onSelect={() => onSelectTemplate(item.template.id)}
                        right={<span className="wb-inline-meta">Advanced</span>}
                        subtitle={`${templateCategoryLabel(item.template)} · ${item.template.default_size} · Score ${item.recommendation.score.toFixed(1)}`}
                        title={item.template.label}
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
                <div className="plot-type-compare-stage">
                  <div className="plot-type-compare-stage-head">
                    <span>Shortlist</span>
                    <strong>Compare the top three quickly</strong>
                  </div>
                  <div className="plot-type-compare-thumbs">
                    {visibleRecommendations.slice(0, 3).map((item) => {
                      const { template } = item;
                      return (
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
                    );
                    })}
                  </div>
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
