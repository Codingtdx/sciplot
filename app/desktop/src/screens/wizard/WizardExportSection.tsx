import { InfoTip } from "../../components/InfoTip";
import type { PreflightResult } from "../../lib/types";
import { formatLeaf } from "../../lib/workbench";

type Props = {
  preflight: PreflightResult | null;
  preflightBusy: boolean;
  preflightRequestError: string | null;
  blockingErrors: string[];
  canExport: boolean;
  hasExportedOutputs: boolean;
  outputItems: string[];
  onExport(): void;
};

export function WizardExportSection({
  preflight,
  preflightBusy,
  preflightRequestError,
  blockingErrors,
  canExport,
  hasExportedOutputs,
  outputItems,
  onExport,
}: Props) {
  return (
    <section className="work-card section-card wizard-pane">
      <div className="panel-heading">
        <div>
          <div className="card-kicker">Review</div>
          <h3>Preflight and export</h3>
        </div>
        <InfoTip content="Preflight updates automatically after file, sheet, template, or option changes. Only blockers stop export." />
      </div>
      <div className="wizard-section-stack">
        {preflightRequestError && <div className="error-card">{preflightRequestError}</div>}
        {!preflightRequestError && preflightBusy && (
          <div className="placeholder-card">Refreshing preflight results...</div>
        )}
        {!preflightRequestError && !preflightBusy && preflight && (
          <>
            {blockingErrors.length > 0 ? (
              <div className="error-card">
                <strong>Export is blocked</strong>
                <ul className="bullet-list">
                  {blockingErrors.map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
              </div>
            ) : (
              <div className="success-card">
                Preflight passed. This figure is ready to export.
              </div>
            )}
            {preflight.warnings.length > 0 && (
              <details>
                <summary>Preflight warnings</summary>
                <ul className="bullet-list">
                  {preflight.warnings.map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
              </details>
            )}
          </>
        )}
        {!preflight && !preflightBusy && !preflightRequestError && (
          <div className="placeholder-card">
            Preflight starts automatically once the file and template are ready.
          </div>
        )}

        <div className="step-actions">
          <button
            className="primary-button"
            disabled={!canExport}
            onClick={onExport}
            type="button"
          >
            Export PDF
          </button>
        </div>

        <div className="focus-panel">
          <strong>{hasExportedOutputs ? "Output files" : "Expected outputs"}</strong>
          {outputItems.length > 0 ? (
            <ul className="output-list">
              {outputItems.map((item) => (
                <li key={item}>{formatLeaf(item)}</li>
              ))}
            </ul>
          ) : (
            <span>No output files are available yet.</span>
          )}
        </div>
      </div>
    </section>
  );
}
