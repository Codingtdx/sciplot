import { useMemo, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { InfoTip } from "../components/InfoTip";
import {
  exportTensileComparison,
  inspectTensileWorkbook,
  preprocessTensileReplicates,
} from "../lib/api";
import { loadWizardDataFile } from "../lib/project-io";
import { useTensileStore, useWizardStore, useWorkbenchStore } from "../lib/store";
import { openDialog, saveDialog } from "../lib/tauri-dialog";
import {
  tensileComparisonSourceFromPreprocess,
  tensileComparisonSourceFromSummary,
} from "../lib/tensile-comparison";
import type { WorkbenchMeta, WorkbenchRoute } from "../lib/types";
import {
  confirmReplaceWizardSession,
  defaultSiblingPath,
  formatLeaf,
  formatMetricValue,
  getErrorMessage,
  inferTensileGroupName,
  templateLabel,
  toDialogPaths,
} from "../lib/workbench";

function representativeSheetName(sheetNames: string[]) {
  return sheetNames.includes("Representative_Curve") ? "Representative_Curve" : (sheetNames[0] ?? 0);
}

export function TensileScreen({
  meta,
  onNavigate,
}: {
  meta: WorkbenchMeta | null;
  onNavigate(route: WorkbenchRoute): void;
}) {
  const tensile = useTensileStore(
    useShallow((state) => ({
      addComparisonSource: state.addComparisonSource,
      clearComparisonSources: state.clearComparisonSources,
      comparisonResult: state.comparisonResult,
      comparisonSources: state.comparisonSources,
      moveComparisonSource: state.moveComparisonSource,
      preprocessResult: state.preprocessResult,
      removeComparisonSource: state.removeComparisonSource,
      setComparisonResult: state.setComparisonResult,
      setPreprocessResult: state.setPreprocessResult,
    })),
  );
  const wizard = useWizardStore();
  const rememberProject = useWorkbenchStore((state) => state.rememberProject);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const compareSourceCount = tensile.comparisonSources.length;
  const canExportComparison = compareSourceCount >= 2 && !busy;
  const latestPreprocessResult = tensile.preprocessResult;
  const latestComparisonResult = tensile.comparisonResult;
  const statusChip = useMemo(() => {
    if (busy) {
      return { label: "Processing", tone: "accent" };
    }
    if (error) {
      return { label: "Needs attention", tone: "warn" };
    }
    if (tensile.comparisonResult) {
      return { label: "Comparison exported", tone: "good" };
    }
    if (tensile.preprocessResult) {
      return { label: "Workbook prepared", tone: "accent" };
    }
    return { label: "Waiting for input", tone: "warn" };
  }, [busy, error, tensile.comparisonResult, tensile.preprocessResult]);

  const showDialogError = (cause: unknown) => {
    setError(getErrorMessage(cause));
  };

  const openWorkbookInPlotting = async (workbookPath: string, preferredSheet: string | number) => {
    if (
      !confirmReplaceWizardSession(
        {
          inputPath: wizard.inputPath,
          inspection: wizard.inspection,
          template: wizard.template,
          outputs: wizard.outputs,
          exportResult: wizard.exportResult,
        },
        formatLeaf(workbookPath),
        workbookPath,
      )
    ) {
      return;
    }
    setError(null);
    setBusy(true);
    try {
      const inspected = await loadWizardDataFile(wizard, meta, workbookPath, preferredSheet, "type");
      rememberProject({
        mode: "wizard",
        kind: "data",
        path: workbookPath,
        title: formatLeaf(workbookPath),
        detail: `Data file · ${inspected.sheet_names.length} sheets · ${templateLabel(meta, inspected.inspection.recommendation.template)}`,
      });
      onNavigate("/plot/type");
    } catch (cause) {
      setError(getErrorMessage(cause));
    } finally {
      setBusy(false);
    }
  };

  const runTensilePreprocess = async () => {
    let filePaths: string[] = [];
    setError(null);
    try {
      const selected = await openDialog({
        multiple: true,
        filters: [{ name: "Tensile CSV", extensions: ["csv", "CSV"] }],
      });
      filePaths = toDialogPaths(selected);
    } catch (cause) {
      showDialogError(cause);
      return;
    }
    if (filePaths.length === 0) {
      return;
    }

    const inferredGroupName = inferTensileGroupName(filePaths);
    let destination: string | null = null;
    try {
      destination = await saveDialog({
        defaultPath: defaultSiblingPath(
          filePaths[0],
          `${inferredGroupName}_plot_wizard_template.xlsx`,
        ),
        filters: [{ name: "Excel Workbook", extensions: ["xlsx"] }],
      });
    } catch (cause) {
      showDialogError(cause);
      return;
    }
    if (typeof destination !== "string") {
      return;
    }

    tensile.setPreprocessResult(null);
    setBusy(true);
    try {
      const result = await preprocessTensileReplicates(filePaths, destination, inferredGroupName);
      tensile.setPreprocessResult(result);
      tensile.addComparisonSource(tensileComparisonSourceFromPreprocess(result));
      rememberProject({
        mode: "wizard",
        kind: "data",
        path: result.output_path,
        title: formatLeaf(result.output_path),
        detail: `Tensile prep · ${result.sample_count} replicates · Prepared workbook`,
      });
    } catch (cause) {
      setError(getErrorMessage(cause));
    } finally {
      setBusy(false);
    }
  };

  const addTensileComparisonWorkbooks = async () => {
    let workbookPaths: string[] = [];
    setError(null);
    try {
      const selected = await openDialog({
        multiple: true,
        filters: [{ name: "Excel Workbook", extensions: ["xlsx", "xlsm"] }],
      });
      workbookPaths = toDialogPaths(selected);
    } catch (cause) {
      showDialogError(cause);
      return;
    }
    if (workbookPaths.length === 0) {
      return;
    }

    setBusy(true);
    const failures: string[] = [];
    try {
      for (const workbookPath of workbookPaths) {
        try {
          const summary = await inspectTensileWorkbook(workbookPath);
          tensile.addComparisonSource(tensileComparisonSourceFromSummary(summary));
        } catch (cause) {
          failures.push(`${formatLeaf(workbookPath)}：${getErrorMessage(cause)}`);
        }
      }
      if (failures.length > 0) {
        setError(`These workbooks could not be added to the queue: ${failures.join("; ")}`);
      }
    } finally {
      setBusy(false);
    }
  };

  const runTensileComparisonExport = async () => {
    if (tensile.comparisonSources.length < 2) {
      return;
    }

    let outputDir: string | undefined;
    setError(null);
    try {
      const selected = await openDialog({
        multiple: false,
        directory: true,
      });
      outputDir = toDialogPaths(selected, 1)[0];
    } catch (cause) {
      showDialogError(cause);
      return;
    }
    if (!outputDir) {
      return;
    }

    setBusy(true);
    try {
      const result = await exportTensileComparison(
        tensile.comparisonSources.map((item) => item.workbook_path),
        outputDir,
      );
      tensile.setComparisonResult(result);
      rememberProject({
        mode: "wizard",
        kind: "data",
        path: result.comparison_workbook_path,
        title: formatLeaf(result.comparison_workbook_path),
        detail: `Tensile compare · ${result.labels.length} sources · ${result.outputs.length} outputs`,
      });
    } catch (cause) {
      setError(getErrorMessage(cause));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="desk-layout tensile-layout">
      <section className="desk-main">
        <article className="work-card section-card tensile-command-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Tensile</div>
              <h2>Prepare raw CSVs, compare prepared workbooks, then hand off to Plot</h2>
            </div>
            <div className="wizard-inline-chips">
              <span className="signal-tag">{compareSourceCount} source(s)</span>
              <span className={`status-pill ${statusChip.tone}`}>{statusChip.label}</span>
            </div>
          </div>

          {error && <div className="error-card">{error}</div>}
          {!wizard.sidecarReady && (
            <div className="warning-card">
              The Python sidecar is offline. Prepare, inspect, and compare actions resume once it reconnects.
            </div>
          )}

          <div className="tensile-task-grid">
            <article className="focus-panel tensile-task-card">
              <span>Prepare raw CSV</span>
              <strong>Generate one workbook from replicate CSV files.</strong>
              <span>
                Use this when you want a clean tensile workbook with representative curves and
                metrics before handing it to Plot.
              </span>
              <div className="step-actions">
                <button
                  className="primary-button"
                  disabled={busy}
                  onClick={() => void runTensilePreprocess()}
                  type="button"
                >
                  Prepare CSVs
                </button>
                {latestPreprocessResult && (
                  <button
                    className="ghost-button"
                    disabled={busy}
                    onClick={() =>
                      void openWorkbookInPlotting(
                        latestPreprocessResult.output_path,
                        latestPreprocessResult.preferred_sheet,
                      )
                    }
                    type="button"
                  >
                    Open latest in Plot
                  </button>
                )}
              </div>
            </article>

            <article className="focus-panel tensile-task-card">
              <span>Compare workbooks</span>
              <strong>Queue prepared workbooks and export the comparison bundle.</strong>
              <span>
                Comparison export unlocks when at least two sources are queued and keeps the fixed
                60 x 55 mm figure size.
              </span>
              <div className="step-actions">
                <button
                  className="ghost-button"
                  disabled={busy}
                  onClick={() => void addTensileComparisonWorkbooks()}
                  type="button"
                >
                  Queue workbooks
                </button>
                <button
                  className="primary-button"
                  disabled={!canExportComparison}
                  onClick={() => void runTensileComparisonExport()}
                  type="button"
                >
                  Export queue
                </button>
              </div>
            </article>
          </div>
        </article>

        {latestPreprocessResult ? (
          <article className="work-card section-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Prepared Workbook</div>
                <h3>Latest output</h3>
              </div>
              <span className="signal-tag">{latestPreprocessResult.sample_count} replicates</span>
            </div>

            <div className="wizard-section-stack">
              <div className="success-card">
                Prepared {latestPreprocessResult.sample_count} samples from{" "}
                {latestPreprocessResult.representative_filename}.
              </div>
              <div className="summary-grid wizard-tight-grid">
                <div className="stat-tile">
                  <span>Workbook</span>
                  <strong>{formatLeaf(latestPreprocessResult.output_path)}</strong>
                </div>
                <div className="stat-tile">
                  <span>Preferred sheet</span>
                  <strong>{latestPreprocessResult.preferred_sheet}</strong>
                </div>
                {latestPreprocessResult.metrics.map((metric) => (
                  <div className="stat-tile" key={metric.label}>
                    <span>{metric.label}</span>
                    <strong>
                      {formatMetricValue(metric.mean)} ± {formatMetricValue(metric.std)} {metric.unit}
                    </strong>
                  </div>
                ))}
              </div>
              {latestPreprocessResult.warnings.length > 0 && (
                <details className="wizard-details">
                  <summary>Skipped files</summary>
                  <ul className="bullet-list">
                    {latestPreprocessResult.warnings.map((item) => (
                      <li key={item}>{item}</li>
                    ))}
                  </ul>
                </details>
              )}
            </div>
          </article>
        ) : (
          <article className="work-card section-card">
            <div className="placeholder-card">
              Select raw CSV files to generate one prepared workbook.
            </div>
          </article>
        )}

        <section className="work-card section-card wizard-pane">
          <div className="wizard-section-stack">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Queue</div>
                <h3>Compare workbooks</h3>
              </div>
              <InfoTip content="Two or more prepared workbooks are required. The compare export always keeps the fixed 60 x 55 mm figure size." />
            </div>

            <div className="focus-panel">
              <strong>{compareSourceCount} source(s) queued</strong>
              <span>Export unlocks when at least two are queued.</span>
            </div>

            <div className="step-actions">
              <button
                className="ghost-button"
                disabled={busy}
                onClick={() => void addTensileComparisonWorkbooks()}
                type="button"
              >
                Add workbooks
              </button>
              <button
                className="ghost-button"
                disabled={busy || compareSourceCount === 0}
                onClick={() => tensile.clearComparisonSources()}
                type="button"
              >
                Clear queue
              </button>
              <button
                className="primary-button"
                disabled={!canExportComparison}
                onClick={() => void runTensileComparisonExport()}
                type="button"
              >
                Export comparison set
              </button>
            </div>

            {compareSourceCount === 0 ? (
              <div className="placeholder-card">Queue at least two workbooks to export.</div>
            ) : (
              <div className="wizard-compare-list">
                {tensile.comparisonSources.map((source, index) => (
                  <details className="wizard-compare-item" key={source.workbook_path}>
                    <summary className="wizard-compare-head">
                      <div>
                        <strong>{source.label}</strong>
                        <span>
                          {formatLeaf(source.workbook_path)} · {source.sample_count} replicates
                        </span>
                      </div>
                    </summary>

                    <div className="wizard-section-stack">
                      <div className="step-actions">
                        <button
                          className="ghost-button"
                          disabled={busy}
                          onClick={() =>
                            void openWorkbookInPlotting(
                              source.workbook_path,
                              representativeSheetName(source.sheet_names),
                            )
                          }
                          type="button"
                        >
                          Open in Plot
                        </button>
                        <button
                          className="ghost-button"
                          disabled={busy || index === 0}
                          onClick={() => tensile.moveComparisonSource(source.workbook_path, -1)}
                          type="button"
                        >
                          Move up
                        </button>
                        <button
                          className="ghost-button"
                          disabled={busy || index === compareSourceCount - 1}
                          onClick={() => tensile.moveComparisonSource(source.workbook_path, 1)}
                          type="button"
                        >
                          Move down
                        </button>
                        <button
                          className="ghost-button"
                          disabled={busy}
                          onClick={() => tensile.removeComparisonSource(source.workbook_path)}
                          type="button"
                        >
                          Remove
                        </button>
                      </div>

                      <div className="summary-grid wizard-tight-grid">
                        {source.metrics.map((metric) => (
                          <div
                            className="stat-tile"
                            key={`${source.workbook_path}:${metric.label}`}
                          >
                            <span>{metric.label}</span>
                            <strong>
                              {formatMetricValue(metric.mean)} ± {formatMetricValue(metric.std)}{" "}
                              {metric.unit}
                            </strong>
                          </div>
                        ))}
                      </div>
                    </div>
                  </details>
                ))}
              </div>
            )}

            {latestComparisonResult && (
              <details className="wizard-details">
                <summary>Latest comparison export</summary>
                <div className="wizard-callout-stack">
                  <div className="success-card">
                    Exported {latestComparisonResult.outputs.length} outputs for{" "}
                    {latestComparisonResult.labels.length} sources.
                  </div>
                  <div className="summary-grid wizard-tight-grid">
                    <div className="stat-tile">
                      <span>Bundle folder</span>
                      <strong>{formatLeaf(latestComparisonResult.bundle_dir)}</strong>
                    </div>
                    <div className="stat-tile">
                      <span>Summary workbook</span>
                      <strong>{formatLeaf(latestComparisonResult.comparison_workbook_path)}</strong>
                    </div>
                    <div className="stat-tile">
                      <span>Sources</span>
                      <strong>{latestComparisonResult.labels.length}</strong>
                    </div>
                    <div className="stat-tile">
                      <span>Outputs</span>
                      <strong>{latestComparisonResult.outputs.length}</strong>
                    </div>
                  </div>
                  <details className="wizard-details">
                    <summary>Output files</summary>
                    <ul className="output-list">
                      {latestComparisonResult.outputs.map((item) => (
                        <li key={item}>{formatLeaf(item)}</li>
                      ))}
                    </ul>
                  </details>
                </div>
              </details>
            )}
          </div>
        </section>
      </section>

      <aside className="desk-context tensile-context">
        <article className="context-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Status</div>
              <h3>Current tensile session</h3>
            </div>
            <span className={`status-pill ${statusChip.tone}`}>{statusChip.label}</span>
          </div>

          <div className="context-list">
            <div className="context-row">
              <span>Prepared workbook</span>
              <strong>
                {latestPreprocessResult ? formatLeaf(latestPreprocessResult.output_path) : "Not prepared"}
              </strong>
            </div>
            <div className="context-row">
              <span>Queued sources</span>
              <strong>{compareSourceCount}</strong>
            </div>
            <div className="context-row">
              <span>Comparison outputs</span>
              <strong>{latestComparisonResult?.outputs.length ?? 0}</strong>
            </div>
            <div className="context-row">
              <span>Plot handoff</span>
              <strong>{wizard.inputPath ? formatLeaf(wizard.inputPath) : "Idle"}</strong>
            </div>
          </div>
        </article>

        <article className="context-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Next Step</div>
              <h3>Move a prepared workbook into Plot</h3>
            </div>
          </div>

          {latestPreprocessResult ? (
            <div className="wizard-section-stack">
              <div className="focus-panel">
                <strong>{formatLeaf(latestPreprocessResult.output_path)}</strong>
                <span>
                  Use the preferred sheet to continue with inspect, preflight, preview, and export in
                  Plot.
                </span>
              </div>
              <div className="step-actions">
                <button
                  className="primary-button"
                  disabled={busy}
                  onClick={() =>
                    void openWorkbookInPlotting(
                      latestPreprocessResult.output_path,
                      latestPreprocessResult.preferred_sheet,
                    )
                  }
                  type="button"
                >
                  Continue in Plot
                </button>
              </div>
            </div>
          ) : (
            <div className="placeholder-card">
              Prepare one workbook first, then continue in Plot only when you choose to.
            </div>
          )}
        </article>
      </aside>
    </div>
  );
}
