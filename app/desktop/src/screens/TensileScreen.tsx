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
import type { WorkbenchMeta, WorkbenchScreen } from "../lib/types";
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
  onNavigate(mode: WorkbenchScreen): void;
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
      const inspected = await loadWizardDataFile(wizard, meta, workbookPath, preferredSheet, "inspect");
      rememberProject({
        mode: "wizard",
        kind: "data",
        path: workbookPath,
        title: formatLeaf(workbookPath),
        detail: `Data file · ${inspected.sheet_names.length} sheets · ${templateLabel(meta, inspected.inspection.recommendation.template)}`,
      });
      onNavigate("wizard");
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
    <div className="desk-layout">
      <section className="desk-main">
        <article className="work-card hero-card wizard-workspace-card">
          <div className="section-head wizard-workspace-head">
            <div>
              <div className="card-kicker">Material Lab</div>
              <h2>Tensile queue</h2>
            </div>
            <div className="wizard-inline-chips">
              {tensile.preprocessResult && (
                <span className="signal-tag">{formatLeaf(tensile.preprocessResult.output_path)}</span>
              )}
              <span className={`status-pill ${statusChip.tone}`}>{statusChip.label}</span>
            </div>
          </div>

          {error && <div className="error-card">{error}</div>}
          {!wizard.sidecarReady && (
            <div className="warning-card">
              The Python sidecar is offline. Prepare, inspect, and compare actions resume once it reconnects.
            </div>
          )}
        </article>

        <div className="wizard-content-grid tensile-content-grid">
          <div className="wizard-main-stack">
            <section className="work-card section-card wizard-pane">
              <div className="panel-heading">
                <div>
                  <div className="card-kicker">Prepare</div>
                  <h3>Build workbook</h3>
                </div>
                <InfoTip content="Preparing creates a workbook that can be reopened in Plot Builder or added to the comparison queue without switching screens automatically." />
              </div>
              <div className="step-actions">
                <button
                  className="primary-button"
                  disabled={busy}
                  onClick={() => void runTensilePreprocess()}
                  type="button"
                >
                  Prepare tensile data
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
                    Open in Plot Builder
                  </button>
                )}
              </div>

              {!latestPreprocessResult ? (
                <div className="placeholder-card">Select raw CSV files to generate one workbook.</div>
              ) : (
                <div className="wizard-callout-stack">
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
                    <details>
                      <summary>Skipped files</summary>
                      <ul className="bullet-list">
                        {latestPreprocessResult.warnings.map((item) => (
                          <li key={item}>{item}</li>
                        ))}
                      </ul>
                    </details>
                  )}
                </div>
              )}
            </section>

            <section className="work-card section-card wizard-pane">
              <div className="panel-heading">
                <div>
                  <div className="card-kicker">Compare</div>
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
                  Add prepared workbooks
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
                    <div className="wizard-compare-item" key={source.workbook_path}>
                      <div className="wizard-compare-head">
                        <div>
                          <strong>{source.label}</strong>
                          <span>
                            {formatLeaf(source.workbook_path)} · {source.sample_count} replicates
                          </span>
                        </div>
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
                            Open in Plot Builder
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
                      </div>
                      <div className="summary-grid wizard-tight-grid">
                        {source.metrics.map((metric) => (
                          <div className="stat-tile" key={`${source.workbook_path}:${metric.label}`}>
                            <span>{metric.label}</span>
                            <strong>
                              {formatMetricValue(metric.mean)} ± {formatMetricValue(metric.std)} {metric.unit}
                            </strong>
                          </div>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              )}

              {tensile.comparisonResult && (
                <div className="wizard-callout-stack">
                  <div className="success-card">
                    Exported {tensile.comparisonResult.outputs.length} outputs for{" "}
                    {tensile.comparisonResult.labels.length} sources.
                  </div>
                  <div className="summary-grid wizard-tight-grid">
                    <div className="stat-tile">
                      <span>Bundle folder</span>
                      <strong>{formatLeaf(tensile.comparisonResult.bundle_dir)}</strong>
                    </div>
                    <div className="stat-tile">
                      <span>Summary workbook</span>
                      <strong>{formatLeaf(tensile.comparisonResult.comparison_workbook_path)}</strong>
                    </div>
                    <div className="stat-tile">
                      <span>Sources</span>
                      <strong>{tensile.comparisonResult.labels.length}</strong>
                    </div>
                    <div className="stat-tile">
                      <span>Outputs</span>
                      <strong>{tensile.comparisonResult.outputs.length}</strong>
                    </div>
                  </div>
                  <div className="focus-panel">
                    <strong>Output files</strong>
                    <ul className="output-list">
                      {tensile.comparisonResult.outputs.map((item) => (
                        <li key={item}>{formatLeaf(item)}</li>
                      ))}
                    </ul>
                  </div>
                </div>
              )}
            </section>
          </div>

          <aside className="desk-context tensile-context">
            <article className="context-card">
              <div className="panel-heading">
                <div>
                  <h3>Session</h3>
                </div>
              </div>
              <div className="wizard-summary-list">
                <div className="wizard-summary-row">
                  <span>Latest workbook</span>
                  <strong>
                    {latestPreprocessResult ? formatLeaf(latestPreprocessResult.output_path) : "-"}
                  </strong>
                </div>
                <div className="wizard-summary-row">
                  <span>Preferred sheet</span>
                  <strong>{latestPreprocessResult?.preferred_sheet ?? "-"}</strong>
                </div>
                <div className="wizard-summary-row">
                  <span>Queued sources</span>
                  <strong>{compareSourceCount}</strong>
                </div>
                <div className="wizard-summary-row">
                  <span>Exports</span>
                  <strong>{tensile.comparisonResult?.outputs.length ?? 0}</strong>
                </div>
              </div>
            </article>
          </aside>
        </div>
      </section>
    </div>
  );
}
