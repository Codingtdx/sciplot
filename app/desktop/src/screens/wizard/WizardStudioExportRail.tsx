import type { SubmissionReport } from "../../lib/types";
import { CompactToolbar } from "../../components/workbench/V2Primitives";
import { formatLeaf } from "../../lib/workbench";

type Props = {
  outputs: string[];
  outputDir: string | null;
  submissionReport: SubmissionReport | null;
  onOpenOutputFolder(): void;
  onOpenComposer(): void;
  onStartAnotherPlot(): void;
  onReopenReview(): void;
};

export function WizardStudioExportRail({
  outputs,
  outputDir,
  submissionReport,
  onOpenOutputFolder,
  onOpenComposer,
  onStartAnotherPlot,
  onReopenReview,
}: Props) {
  const outputCount = outputs.length;
  return (
    <>
      <article className="context-card wizard-review-card wizard-export-card">
        <div className="panel-heading">
          <div>
            <div className="card-kicker">Export</div>
            <h3>Delivery complete</h3>
          </div>
          <span className="status-pill good">Ready</span>
        </div>

        <div className="wizard-review-summary-grid">
          <div className="stat-tile">
            <span>Outputs</span>
            <strong>{outputCount}</strong>
          </div>
          <div className="stat-tile">
            <span>Destination</span>
            <strong>{formatLeaf(outputDir ?? "output")}</strong>
          </div>
          <div className="stat-tile">
            <span>Status</span>
            <strong>Delivered</strong>
          </div>
          <div className="stat-tile">
            <span>Next</span>
            <strong>Open folder or start again</strong>
          </div>
        </div>

        <div className="wizard-module-stack">
          <section className="wizard-module-card">
            <div className="wizard-module-head">
              <div>
                <strong>Destination</strong>
                <span>Keep the handoff calm and explicit.</span>
              </div>
            </div>
            <div className="success-card">
              Exported {outputCount} file(s) to {formatLeaf(outputDir ?? "output")}.
            </div>
            <div className="wizard-module-note">
              <strong>Folder</strong>
              <span>{outputDir ?? "Pending export"}</span>
            </div>
          </section>

          <section className="wizard-module-card">
            <div className="wizard-module-head">
              <div>
                <strong>Bundle contents</strong>
                <span>What was generated and where it lives.</span>
              </div>
            </div>
            <div className="wizard-delivery-list">
              {outputs.map((item) => (
                <div className="wizard-delivery-row" key={item}>
                  <strong>{formatLeaf(item)}</strong>
                  <span>{item}</span>
                </div>
              ))}
            </div>
            {submissionReport && (
              <div className="wizard-module-note">
                <strong>Submission report</strong>
                <span>{submissionReport.summary}</span>
              </div>
            )}
          </section>

          <section className="wizard-module-card">
            <div className="wizard-module-head">
              <div>
                <strong>Next actions</strong>
                <span>Open the output folder, continue in Composer, or start a new plot.</span>
              </div>
            </div>
            <CompactToolbar label="Export stage actions">
              <button
                className="primary-button"
                disabled={!outputDir}
                onClick={onOpenOutputFolder}
                type="button"
              >
                Open output folder
              </button>
              <button className="ghost-button" onClick={onOpenComposer} type="button">
                Open Composer
              </button>
              <button className="ghost-button" onClick={onStartAnotherPlot} type="button">
                Start another plot
              </button>
            </CompactToolbar>
          </section>
        </div>
      </article>

      <CompactToolbar label="Export stage navigation">
        <button className="ghost-button" onClick={onReopenReview} type="button">
          Re-open review
        </button>
      </CompactToolbar>
    </>
  );
}
