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
  return (
    <>
      <article className="context-card wizard-review-card">
        <div className="panel-heading">
          <div>
            <div className="card-kicker">Export</div>
            <h3>Bundle complete</h3>
          </div>
          <span className="status-pill good">Ready</span>
        </div>

        <div className="wizard-section-stack">
          <div className="success-card">
            Exported {outputs.length} file(s) to {formatLeaf(outputDir ?? "output")}.
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
            <button
              className="ghost-button"
              onClick={onStartAnotherPlot}
              type="button"
            >
              Start another plot
            </button>
          </CompactToolbar>

          <details className="wizard-details" open>
            <summary>Output files</summary>
            <ul className="output-list">
              {outputs.map((item) => (
                <li key={item}>{formatLeaf(item)}</li>
              ))}
            </ul>
          </details>

          {submissionReport && (
            <div className="focus-panel">
              <strong>Submission review</strong>
              <span>{submissionReport.summary}</span>
            </div>
          )}
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
