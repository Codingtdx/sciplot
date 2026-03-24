import type {
  ExportResponse,
  PreflightResult,
  RequestActivity,
  SubmissionReport,
} from "../../lib/types";
import { CompactToolbar } from "../../components/workbench/V2Primitives";
import { WizardExportSection } from "./WizardExportSection";

type Props = {
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
