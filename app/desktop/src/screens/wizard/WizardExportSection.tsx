import { InfoTip } from "../../components/InfoTip";
import type {
  ExportResponse,
  PreflightResult,
  RequestActivity,
  SubmissionReport,
} from "../../lib/types";
import { formatLeaf } from "../../lib/workbench";

type Props = {
  preflight: PreflightResult | null;
  preflightBusy: boolean;
  preflightActivity: RequestActivity;
  previewActivity: RequestActivity;
  preflightRequestError: string | null;
  blockingErrors: string[];
  canExport: boolean;
  hasExportedOutputs: boolean;
  outputItems: string[];
  exportResult: ExportResponse | null;
  submissionReport: SubmissionReport | null;
  onExport(): void;
  onOpenOutputDir(): void;
};

function groupArtifacts(exportResult: ExportResponse | null) {
  const artifactPaths = exportResult?.artifact_paths ?? [];
  return {
    reportArtifacts: artifactPaths.filter((path) => path.endsWith(".json")),
    previewOutputs: exportResult?.preview_outputs ?? [],
  };
}

export function WizardExportSection({
  preflight,
  preflightBusy,
  preflightActivity,
  previewActivity,
  preflightRequestError,
  blockingErrors,
  canExport,
  hasExportedOutputs,
  outputItems,
  exportResult,
  submissionReport,
  onExport,
  onOpenOutputDir,
}: Props) {
  const highlightedChecks =
    submissionReport?.checks.filter((check) => check.status !== "pass").slice(0, 4) ?? [];
  const readinessLabel =
    submissionReport?.readiness === "blocked"
      ? "Blocked"
      : submissionReport?.readiness === "ready"
        ? "Ready"
        : submissionReport?.readiness === "review"
          ? "Review"
          : "Pending";
  const readinessTone =
    submissionReport?.readiness === "blocked"
      ? "warn"
      : submissionReport?.readiness === "ready"
        ? "good"
        : "accent";
  const outputDirectory = exportResult?.output_dir ?? null;
  const manifestPath = exportResult?.manifest_path ?? null;
  const artifacts = groupArtifacts(exportResult);

  return (
    <section className="work-card section-card wizard-pane">
      <div className="panel-heading">
        <div>
          <div className="card-kicker">Review</div>
          <h3>Submission review and export</h3>
        </div>
        <InfoTip content="Preview and preflight refresh automatically. Export writes the final PDF together with a manuscript-ready support bundle." />
      </div>
      <div className="wizard-section-stack">
        {preflightRequestError && <div className="error-card">{preflightRequestError}</div>}
        {!preflightRequestError && preflightBusy && (
          <div className="placeholder-card">
            {preflightActivity === "scheduled"
              ? "Queueing preflight..."
              : "Refreshing preflight results..."}
          </div>
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

        <div className="focus-panel">
          <strong>Auto-check status</strong>
          <span>
            Preview: {previewActivity}. Preflight: {preflightActivity}.
          </span>
          <span>
            Only hard blockers stop export. Editorial checks stay visible as review guidance.
          </span>
        </div>

        <div className="step-actions">
          <button
            className="primary-button"
            disabled={!canExport}
            onClick={onExport}
            type="button"
          >
            Export submission bundle
          </button>
          {outputDirectory && (
            <button className="ghost-button" onClick={onOpenOutputDir} type="button">
              Open output folder
            </button>
          )}
        </div>

        <div className="focus-panel">
          <strong>{hasExportedOutputs ? "Final PDF outputs" : "Expected outputs"}</strong>
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

        {submissionReport && (
          <div className="focus-panel">
            <strong>Submission review</strong>
            <span className={`status-pill ${readinessTone}`}>{readinessLabel}</span>
            <span>{submissionReport.summary}</span>
            {highlightedChecks.length > 0 && (
              <ul className="bullet-list">
                {highlightedChecks.map((check) => (
                  <li key={check.id}>{check.message}</li>
                ))}
              </ul>
            )}
          </div>
        )}

        {exportResult && (
          <div className="focus-panel">
            <strong>Submission package</strong>
            {outputDirectory && <span>Folder: {outputDirectory}</span>}
            {artifacts.previewOutputs.length > 0 && (
              <span>{artifacts.previewOutputs.length} preview PNG file(s) were written next to the PDFs.</span>
            )}
            {manifestPath && <span>Manifest: {formatLeaf(manifestPath)}</span>}
            {artifacts.reportArtifacts.length > 0 && (
              <ul className="bullet-list">
                {artifacts.reportArtifacts.map((item) => (
                  <li key={item}>{formatLeaf(item)}</li>
                ))}
              </ul>
            )}
          </div>
        )}
      </div>
    </section>
  );
}
