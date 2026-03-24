import type {
  ExportResponse,
  PreflightResult,
  RequestActivity,
  SubmissionReport,
} from "../../lib/types";
import { CompactToolbar } from "../../components/workbench/V2Primitives";
import { WizardExportSection } from "./WizardExportSection";

type SummaryRow = {
  label: string;
  value: string;
};

type Props = {
  summaryRows: SummaryRow[];
  blockingErrors: string[];
  canExport: boolean;
  exportResult: ExportResponse | null;
  hasExportedOutputs: boolean;
  outputItems: string[];
  preflight: PreflightResult | null;
  preflightActivity: RequestActivity;
  preflightBusy: boolean;
  preflightRequestError: string | null;
  previewActivity: RequestActivity;
  submissionReport: SubmissionReport | null;
  onExport(): void;
  onOpenOutputFolder(): void;
  onBackToTune(): void;
};

export function WizardStudioReviewRail({
  summaryRows,
  blockingErrors,
  canExport,
  exportResult,
  hasExportedOutputs,
  outputItems,
  preflight,
  preflightActivity,
  preflightBusy,
  preflightRequestError,
  previewActivity,
  submissionReport,
  onExport,
  onOpenOutputFolder,
  onBackToTune,
}: Props) {
  return (
    <>
      <article className="context-card wizard-review-context-card">
        <div className="panel-heading">
          <div>
            <div className="card-kicker">Context</div>
            <h3>Selected figure</h3>
          </div>
          <span className="status-pill accent">Ready to review</span>
        </div>

        <div className="wizard-review-context-grid">
          {summaryRows.map((row) => (
            <div className="wizard-review-context-row" key={row.label}>
              <span>{row.label}</span>
              <strong>{row.value}</strong>
            </div>
          ))}
        </div>
      </article>

      <WizardExportSection
        blockingErrors={blockingErrors}
        canExport={canExport}
        exportResult={exportResult}
        hasExportedOutputs={hasExportedOutputs}
        onExport={onExport}
        onOpenOutputDir={onOpenOutputFolder}
        outputItems={outputItems}
        preflight={preflight}
        preflightActivity={preflightActivity}
        preflightBusy={preflightBusy}
        preflightRequestError={preflightRequestError}
        previewActivity={previewActivity}
        submissionReport={submissionReport}
      />

      <CompactToolbar label="Review stage actions">
        <button className="ghost-button" onClick={onBackToTune} type="button">
          Back to tune
        </button>
      </CompactToolbar>
    </>
  );
}
