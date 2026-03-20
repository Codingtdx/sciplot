import type { InputInspection, WorkbenchMeta } from "../../lib/types";
import { templateLabel } from "../../lib/workbench";

type Props = {
  inspection: InputInspection | null;
  meta: WorkbenchMeta | null;
};

export function WizardDetectSection({ inspection, meta }: Props) {
  return (
    <section className="work-card section-card wizard-pane">
      <div className="panel-heading">
        <div>
          <div className="card-kicker">Detected</div>
          <h3>Input fit</h3>
        </div>
      </div>
      {!inspection ? (
        <div className="placeholder-card">Open data to detect the model.</div>
      ) : (
        <div className="wizard-section-stack">
          <div className="info-grid wizard-tight-grid">
            <div className="stat-tile">
              <span>Detected model</span>
              <strong>{inspection.model_label}</strong>
            </div>
            <div className="stat-tile">
              <span>Recommended</span>
              <strong>{templateLabel(meta, inspection.recommendation.template)}</strong>
            </div>
          </div>
          <details className="wizard-details">
            <summary>Why this choice</summary>
            <div className="wizard-details-body">{inspection.recommendation.reason}</div>
          </details>
          {inspection.warnings.length > 0 && (
            <details className="wizard-details" open>
              <summary>{inspection.warnings.length} input warning(s)</summary>
              <ul className="bullet-list">
                {inspection.warnings.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </details>
          )}
          {inspection.signals.length > 0 && (
            <details className="wizard-details">
              <summary>{inspection.signals.length} detection signal(s)</summary>
              <ul className="bullet-list">
                {inspection.signals.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </details>
          )}
        </div>
      )}
    </section>
  );
}
