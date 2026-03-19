import { InfoTip } from "../../components/InfoTip";
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
          <div className="card-kicker">Detect</div>
          <h3>Input fit</h3>
        </div>
        <InfoTip content="The recommendation comes from the detected table structure, labels, units, and scale behavior." />
      </div>
      {!inspection ? (
        <div className="placeholder-card">
          Load a dataset to see the detected model and recommended template.
        </div>
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
          <div className="focus-panel">
            <strong>Why this fit</strong>
            <span>{inspection.recommendation.reason}</span>
          </div>
          {inspection.warnings.length > 0 && (
            <div className="warning-card">
              <strong>Input warnings</strong>
              <ul className="bullet-list">
                {inspection.warnings.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </div>
          )}
          {inspection.signals.length > 0 && (
            <details>
              <summary>Detection signals</summary>
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
