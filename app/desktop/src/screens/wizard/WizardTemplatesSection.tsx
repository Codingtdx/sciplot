import { InfoTip } from "../../components/InfoTip";
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
    <section className="work-card section-card wizard-pane">
      <div className="panel-heading">
        <div>
          <div className="card-kicker">Templates</div>
          <h3>Compatible templates</h3>
        </div>
        <InfoTip content="Only templates that match the detected input stay in the primary list. Incompatible templates remain disabled in the overflow list." />
      </div>
      {!inspection ? (
        <div className="placeholder-card">
          Template choices appear after the file has been inspected.
        </div>
      ) : (
        <div className="wizard-section-stack">
          <div className="wizard-template-grid">
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
                    : template.category.replace(/_/g, " ")}
                </span>
              </button>
            ))}
          </div>
          {incompatibleTemplates.length > 0 && (
            <>
              <button className="ghost-button" onClick={onToggleShowAllTemplates} type="button">
                {showAllTemplates ? "Hide incompatible templates" : "Browse all templates"}
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
                        <span>{template.category.replace(/_/g, " ")}</span>
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
