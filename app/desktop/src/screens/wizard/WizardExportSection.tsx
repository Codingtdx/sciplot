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

  return (
    <article className="context-card wizard-review-card wizard-export-card">
      <div className="panel-heading">
        <div>
          <div className="card-kicker">Review</div>
          <h3>Ready to deliver</h3>
        </div>
        <span className={`status-pill ${reviewTone}`}>{reviewLabel}</span>
      </div>

      <div className="wizard-review-summary-grid">
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

      <div className="wizard-module-stack">
        <section className="wizard-module-card">
          <div className="wizard-module-head">
            <div>
              <strong>Readiness</strong>
              <span>Final checks stay visible and structured.</span>
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
                <div className="wizard-module-note">
                  <strong>{preflight.warnings.length} warning(s)</strong>
                  <ul className="bullet-list">
                    {preflight.warnings.map((item) => (
                      <li key={item}>{item}</li>
                    ))}
                  </ul>
                </div>
              )}
            </>
          )}

          {!preflight && !preflightBusy && !preflightRequestError && (
            <div className="placeholder-card">
              {previewActivity === "ready" ? "Checks are ready." : "Checks start automatically."}
            </div>
          )}
        </section>

        <section className="wizard-module-card">
          <div className="wizard-module-head">
            <div>
              <strong>Outputs and delivery</strong>
              <span>Export bundle, folder, and generated files.</span>
            </div>
          </div>

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

          <div className="wizard-module-note">
            <strong>{hasExportedOutputs ? "Output files" : "Expected files"}</strong>
            {outputItems.length > 0 ? (
              <ul className="output-list">
                {outputItems.map((item) => (
                  <li key={item}>{formatLeaf(item)}</li>
                ))}
              </ul>
            ) : (
              <span>No files yet.</span>
            )}
          </div>

          {exportResult && (
            <div className="wizard-module-note">
              <strong>Bundle files</strong>
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
            </div>
          )}
        </section>

        {submissionReport && (
          <section className="wizard-module-card">
            <div className="wizard-module-head">
              <div>
                <strong>Submission report</strong>
                <span>Delivery checks and editorial summary.</span>
              </div>
              <span className={`status-pill ${readinessTone}`}>{readinessLabel}</span>
            </div>
            <div className="wizard-module-note">
              <span>{submissionReport.summary}</span>
            </div>
            {highlightedChecks.length > 0 && (
              <div className="wizard-check-list">
                {highlightedChecks.map((check) => (
                  <div className="wizard-check-row" key={check.id}>
                    <strong>{check.status}</strong>
                    <span>{check.message}</span>
                  </div>
                ))}
              </div>
            )}
          </section>
        )}
      </div>
    </article>
  );
}
