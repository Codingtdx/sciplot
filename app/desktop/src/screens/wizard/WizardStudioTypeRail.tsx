import type { InputInspection, TemplateName, WorkbenchTemplate } from "../../lib/types";
import { WizardTemplatesSection } from "./WizardTemplatesSection";

type Props = {
  inspection: InputInspection | null;
  recommendationApplied: boolean;
  compatibleTemplates: WorkbenchTemplate[];
  incompatibleTemplates: WorkbenchTemplate[];
  selectedTemplate: TemplateName | null;
  showAllTemplates: boolean;
  hasTemplate: boolean;
  onApplyRecommendedSelection(): void;
  onSelectTemplate(value: TemplateName): void;
  onToggleShowAllTemplates(): void;
  onContinueToTune(): void;
};

export function WizardStudioTypeRail({
  inspection,
  recommendationApplied,
  compatibleTemplates,
  incompatibleTemplates,
  selectedTemplate,
  showAllTemplates,
  hasTemplate,
  onApplyRecommendedSelection,
  onSelectTemplate,
  onToggleShowAllTemplates,
  onContinueToTune,
}: Props) {
  return (
    <>
      {inspection && (
        <article className="context-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Detect</div>
              <h3>Recommendation</h3>
            </div>
            {!recommendationApplied && (
              <button
                className="ghost-button"
                onClick={onApplyRecommendedSelection}
                type="button"
              >
                Use recommendation
              </button>
            )}
          </div>

          <div className="wizard-details-body">
            <div>{inspection.recommendation.reason}</div>
          </div>

          {inspection.warnings.length > 0 && (
            <details className="wizard-details">
              <summary>{inspection.warnings.length} input warning(s)</summary>
              <ul className="bullet-list">
                {inspection.warnings.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </details>
          )}
        </article>
      )}

      <WizardTemplatesSection
        compatibleTemplates={compatibleTemplates}
        incompatibleTemplates={incompatibleTemplates}
        inspection={inspection}
        onSelectTemplate={onSelectTemplate}
        onToggleShowAllTemplates={onToggleShowAllTemplates}
        selectedTemplate={selectedTemplate}
        showAllTemplates={showAllTemplates}
      />

      <div className="hero-actions">
        <button
          className="primary-button"
          disabled={!hasTemplate}
          onClick={onContinueToTune}
          type="button"
        >
          Continue to tune
        </button>
      </div>
    </>
  );
}
