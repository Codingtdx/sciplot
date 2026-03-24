import type {
  ExportResponse,
  PreflightResult,
  RequestActivity,
  SubmissionReport,
} from "../../lib/types";
import { CompactToolbar } from "../../components/workbench/V2Primitives";
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
  const reviewLabel =
    blockingErrors.length > 0 || preflightRequestError
      ? "Fix blockers"
      : hasExportedOutputs
        ? "Exported"
        : preflight
          ? "Ready"
          : preflightBusy
            ? "Checking"
            : "Pending";
  const reviewTone =
    blockingErrors.length > 0 || preflightRequestError
      ? "warn"
      : hasExportedOutputs || preflight
        ? "good"
        : "accent";
  const outputDirectory = exportResult?.output_dir ?? null;
  const manifestPath = exportResult?.manifest_path ?? null;
  const artifacts = groupArtifacts(exportResult);
  const autoOpen =
    Boolean(preflightRequestError) ||
    blockingErrors.length > 0 ||
    preflight !== null ||
    hasExportedOutputs;

  return (
    <article className="context-card wizard-review-card wizard-export-card">
      <details className="wizard-review-details" open={autoOpen}>
        <summary className="wizard-review-summary">
          <span>Review and export</span>
          <span className={`status-pill ${reviewTone}`}>{reviewLabel}</span>
        </summary>

        <div className="wizard-section-stack">
          <div className="wizard-export-summary-grid">
            <div className="stat-tile">
              <span>Readiness</span>
              <strong>{readinessLabel}</strong>
            </div>
            <div className="stat-tile">
              <span>Blockers</span>
              <strong>{blockingErrors.length}</strong>
            </div>
            <div className="stat-tile">
              <span>Expected files</span>
              <strong>{outputItems.length}</strong>
            </div>
            <div className="stat-tile">
              <span>Bundle folder</span>
              <strong>{outputDirectory ? formatLeaf(outputDirectory) : "Pending export"}</strong>
            </div>
          </div>

          {preflightRequestError && <div className="error-card">{preflightRequestError}</div>}

          {!preflightRequestError && preflightBusy && (
            <div className="placeholder-card">
              {preflightActivity === "scheduled" ? "Queueing checks…" : "Refreshing checks…"}
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
                <div className="success-card">Ready to export.</div>
              )}

              {preflight.warnings.length > 0 && (
                <details className="wizard-details">
                  <summary>{preflight.warnings.length} preflight warning(s)</summary>
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
              {previewActivity === "ready" ? "Checks are ready." : "Checks start automatically."}
            </div>
          )}

          <CompactToolbar label="Review export actions">
            <button
              className="primary-button"
              disabled={!canExport}
              onClick={onExport}
              type="button"
            >
              Export bundle
            </button>
            {outputDirectory && (
              <button className="ghost-button" onClick={onOpenOutputDir} type="button">
                Open output folder
              </button>
            )}
          </CompactToolbar>

          <details className="wizard-details">
            <summary>{hasExportedOutputs ? "Output files" : "Expected files"}</summary>
            {outputItems.length > 0 ? (
              <ul className="output-list">
                {outputItems.map((item) => (
                  <li key={item}>{formatLeaf(item)}</li>
                ))}
              </ul>
            ) : (
              <div className="wizard-details-body">No files yet.</div>
            )}
          </details>

          {submissionReport && (
            <div className="focus-panel wizard-readiness-panel">
              <strong>Submission review</strong>
              <span className={`status-pill ${readinessTone}`}>{readinessLabel}</span>
              <span>{submissionReport.summary}</span>
              {highlightedChecks.length > 0 && (
                <details className="wizard-details">
                  <summary>{highlightedChecks.length} flagged check(s)</summary>
                  <ul className="bullet-list">
                    {highlightedChecks.map((check) => (
                      <li key={check.id}>{check.message}</li>
                    ))}
                  </ul>
                </details>
              )}
            </div>
          )}

          {exportResult && (
            <details className="wizard-details">
              <summary>Bundle files</summary>
              <div className="wizard-details-body">
                {outputDirectory && <div>Folder: {outputDirectory}</div>}
                {artifacts.previewOutputs.length > 0 && (
                  <div>{artifacts.previewOutputs.length} preview PNG file(s).</div>
                )}
                {manifestPath && <div>Manifest: {formatLeaf(manifestPath)}</div>}
              </div>
              {artifacts.reportArtifacts.length > 0 && (
                <ul className="bullet-list">
                  {artifacts.reportArtifacts.map((item) => (
                    <li key={item}>{formatLeaf(item)}</li>
                  ))}
                </ul>
              )}
            </details>
          )}
        </div>
      </details>
    </article>
  );
}
