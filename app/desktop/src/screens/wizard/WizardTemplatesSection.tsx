import type { InputInspection, TemplateName, WorkbenchTemplate } from "../../lib/types";
import { templateCompatibilityReason } from "../../lib/workbench";

type Props = {
  inspection: InputInspection | null;
  selectedTemplate: TemplateName | null;
  compatibleTemplates: WorkbenchTemplate[];
  incompatibleTemplates: WorkbenchTemplate[];
  showAllTemplates: boolean;
  onSelectTemplate(template: TemplateName): void;
  onToggleShowAllTemplates(): void;
};

export function WizardTemplatesSection({
  inspection,
  selectedTemplate,
  compatibleTemplates,
  incompatibleTemplates,
  showAllTemplates,
  onSelectTemplate,
  onToggleShowAllTemplates,
}: Props) {
  return (
    <section className="context-card wizard-pane">
      <div className="panel-heading">
        <div>
          <div className="card-kicker">Template</div>
          <h3>Chart type</h3>
        </div>
      </div>
      {!inspection ? (
        <div className="placeholder-card">Templates appear after inspect.</div>
      ) : (
        <div className="wizard-section-stack">
          <button
            className={`wizard-recommendation-card ${
              selectedTemplate === inspection.recommendation.template ? "active" : ""
            }`}
            onClick={() => onSelectTemplate(inspection.recommendation.template)}
            type="button"
          >
            <div className="wizard-recommendation-copy">
              <span className="signal-tag">Recommended</span>
              <strong>{compatibleTemplates.find((template) => template.id === inspection.recommendation.template)?.label ?? inspection.recommendation.template}</strong>
              <span>{inspection.recommendation.reason}</span>
            </div>
            <span className="wizard-recommendation-action">Use this chart</span>
          </button>

          <div className="wizard-template-grid wizard-template-gallery">
            {compatibleTemplates.map((template) => (
              <button
                className={`wizard-template-chip ${selectedTemplate === template.id ? "active" : ""}`}
                key={template.id}
                onClick={() => onSelectTemplate(template.id)}
                type="button"
              >
                <strong>{template.label}</strong>
                <span>
                  {template.id === inspection.recommendation.template
                    ? "Recommended"
                    : "Compatible"}
                </span>
                <div className="wizard-template-chip-line" />
              </button>
            ))}
          </div>
          {incompatibleTemplates.length > 0 && (
            <>
              <button className="ghost-button" onClick={onToggleShowAllTemplates} type="button">
                {showAllTemplates ? "Hide more types" : "More types"}
              </button>
              {showAllTemplates && (
                <div className="wizard-section-stack">
                  <div className="hint-text">
                    {templateCompatibilityReason(inspection.model)}
                  </div>
                  <div className="wizard-template-grid">
                    {incompatibleTemplates.map((template) => (
                      <button
                        className="wizard-template-chip disabled"
                        disabled
                        key={template.id}
                        type="button"
                      >
                        <strong>{template.label}</strong>
                        <span>Not compatible</span>
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </>
          )}
        </div>
      )}
    </section>
  );
}
