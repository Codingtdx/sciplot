import type { TemplateName, WorkbenchTemplate } from "../lib/types";
import { inspectionRecommendationSections } from "../lib/wizard";

import { MacButton } from "../components/mac/MacButton";
import { MacPanel } from "../components/mac/MacPanel";
import { MacStatusPill } from "../components/mac/MacStatusPill";

function recommendationScore(score: number) {
  return `${score.toFixed(1)}% fit`;
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
    <article className={`template-card${recommended ? " template-card-featured" : ""}`}>
      <div className="card-header">
        <MacStatusPill tone={recommended ? "accent" : "neutral"}>
          {recommended ? "Recommended" : "Alternative"}
        </MacStatusPill>
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
      <MacButton variant={recommended ? "primary" : "secondary"} onClick={() => onSelect(template.id)}>
        {recommended ? "Use this template" : "Choose template"}
      </MacButton>
    </article>
  );
}

export function PlotTemplateScreen({
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
            <MacPanel>
              <div className="empty-panel">
                <p>No recommendation is available yet.</p>
                <small>Go back to Plot Import and inspect a dataset first.</small>
              </div>
            </MacPanel>
          )}
        </div>

        <div className="stack-column">
          <MacPanel className="inspector-panel">
            <div className="card-header">
              <MacStatusPill tone="neutral">Alternatives</MacStatusPill>
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
          </MacPanel>

          <MacPanel className="inspector-panel">
            <div className="card-header">
              <MacStatusPill tone="warning">Unavailable</MacStatusPill>
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
          </MacPanel>
        </div>
      </div>
    </section>
  );
}
