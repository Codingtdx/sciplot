import { InfoTip } from "../../components/InfoTip";
import type {
  RequestActivity,
  SubmissionReport,
  TemplateName,
  WorkbenchMeta,
} from "../../lib/types";
import { formatLeaf, styleLabel, templateLabel } from "../../lib/workbench";

import type { WizardStatusChip } from "./helpers";

type Props = {
  meta: WorkbenchMeta | null;
  inputPath: string;
  sheet: string | number;
  template: TemplateName | null;
  stylePreset: string | null;
  statusChip: WizardStatusChip;
  previewActivity: RequestActivity;
  preflightActivity: RequestActivity;
  submissionReport: SubmissionReport | null;
  previewsCount: number;
  outputsCount: number;
  inspectionWarningsCount: number;
  preflightWarningsCount: number;
  hasBlockingErrors: boolean;
  blockingErrorsCount: number;
  preflightRequestError: string | null;
};

export function WizardSessionCard({
  meta,
  inputPath,
  sheet,
  template,
  stylePreset,
  statusChip,
  previewActivity,
  preflightActivity,
  submissionReport,
  previewsCount,
  outputsCount,
  inspectionWarningsCount,
  preflightWarningsCount,
  hasBlockingErrors,
  blockingErrorsCount,
  preflightRequestError,
}: Props) {
  return (
    <article className="context-card wizard-status-card">
      <div className="panel-heading">
        <div>
          <h3>Session</h3>
        </div>
        <InfoTip content="This compact summary replaces the old duplicate status cards. Critical blockers still stay visible in the main flow." />
      </div>
      <div className="wizard-summary-list">
        <div className="wizard-summary-row">
          <span>File</span>
          <strong>{inputPath ? formatLeaf(inputPath) : "-"}</strong>
        </div>
        <div className="wizard-summary-row">
          <span>Sheet</span>
          <strong>{String(sheet)}</strong>
        </div>
        <div className="wizard-summary-row">
          <span>Template</span>
          <strong>{templateLabel(meta, template)}</strong>
        </div>
        <div className="wizard-summary-row">
          <span>Mode</span>
          <strong>{styleLabel(meta, stylePreset)}</strong>
        </div>
        <div className="wizard-summary-row">
          <span>Status</span>
          <strong>{statusChip.label}</strong>
        </div>
        <div className="wizard-summary-row">
          <span>Preview</span>
          <strong>{previewActivity}</strong>
        </div>
        <div className="wizard-summary-row">
          <span>Preflight</span>
          <strong>{preflightActivity}</strong>
        </div>
        <div className="wizard-summary-row">
          <span>Readiness</span>
          <strong>{submissionReport?.readiness ?? "-"}</strong>
        </div>
        <div className="wizard-summary-row">
          <span>Previews</span>
          <strong>{previewsCount}</strong>
        </div>
        <div className="wizard-summary-row">
          <span>Exports</span>
          <strong>{outputsCount}</strong>
        </div>
      </div>

      {(inspectionWarningsCount || preflightWarningsCount || hasBlockingErrors) && (
        <div className="wizard-callout-stack">
          {hasBlockingErrors && (
            <div className="error-card">
              {preflightRequestError ??
                `${blockingErrorsCount} blocking issue(s) still need attention.`}
            </div>
          )}
          {preflightWarningsCount > 0 && (
            <div className="warning-card">
              {preflightWarningsCount} preflight warning(s) are still visible.
            </div>
          )}
          {inspectionWarningsCount > 0 && (
            <div className="warning-card">
              {inspectionWarningsCount} input warning(s) were detected.
            </div>
          )}
        </div>
      )}
    </article>
  );
}
