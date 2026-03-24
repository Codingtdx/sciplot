import { useMemo, useState } from "react";
import { useShallow } from "zustand/react/shallow";

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
import {
  CompactListRow,
  CompactToolbar,
  SectionHeader,
} from "../components/workbench/V2Primitives";

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
  const [rawCsvQueue, setRawCsvQueue] = useState<string[]>([]);

  const compareSourceCount = tensile.comparisonSources.length;
  const canPrepareWorkbook = rawCsvQueue.length > 0 && !busy;
  const canExportComparison = compareSourceCount >= 2 && !busy;
  const latestPreprocessResult = tensile.preprocessResult;
  const latestComparisonResult = tensile.comparisonResult;
  const handoffTarget =
    latestPreprocessResult?.output_path ??
    tensile.comparisonSources[0]?.workbook_path ??
    wizard.inputPath;
  const statusChip = useMemo(() => {
    if (busy) {
      return { label: "Processing", tone: "accent" as const };
    }
    if (error) {
      return { label: "Needs attention", tone: "warn" as const };
    }
    if (tensile.comparisonResult) {
      return { label: "Comparison exported", tone: "good" as const };
    }
    if (tensile.preprocessResult) {
      return { label: "Workbook prepared", tone: "accent" as const };
    }
    if (rawCsvQueue.length > 0) {
      return { label: "Queue ready", tone: "accent" as const };
    }
    return { label: "Waiting for input", tone: "warn" as const };
  }, [busy, error, rawCsvQueue.length, tensile.comparisonResult, tensile.preprocessResult]);

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

  const importRawCsvs = async () => {
    setError(null);
    try {
      const selected = await openDialog({
        multiple: true,
        filters: [{ name: "Tensile CSV", extensions: ["csv", "CSV"] }],
      });
      const filePaths = toDialogPaths(selected);
      if (filePaths.length === 0) {
        return;
      }
      setRawCsvQueue(filePaths);
    } catch (cause) {
      showDialogError(cause);
    }
  };

  const prepareQueuedCsvs = async () => {
    if (rawCsvQueue.length === 0) {
      return;
    }
    const inferredGroupName = inferTensileGroupName(rawCsvQueue);
    let destination: string | null = null;
    setError(null);
    try {
      destination = await saveDialog({
        defaultPath: defaultSiblingPath(
          rawCsvQueue[0],
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
      const result = await preprocessTensileReplicates(rawCsvQueue, destination, inferredGroupName);
      tensile.setPreprocessResult(result);
      tensile.addComparisonSource(tensileComparisonSourceFromPreprocess(result));
      rememberProject({
        mode: "wizard",
        kind: "data",
        path: result.output_path,
        title: formatLeaf(result.output_path),
        detail: `Tensile prep · ${result.sample_count} replicates · Prepared workbook`,
      });
      setRawCsvQueue([]);
    } catch (cause) {
      setError(getErrorMessage(cause));
    } finally {
      setBusy(false);
    }
  };

  const addPreparedWorkbooks = async () => {
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

  const nextActionText = (() => {
    if (rawCsvQueue.length > 0) {
      return "Prepare queued CSV files into one workbook.";
    }
    if (compareSourceCount >= 2) {
      return "Export comparison set for the queued workbooks.";
    }
    if (latestPreprocessResult) {
      return "Open the prepared workbook in Plot or add more prepared workbooks.";
    }
    return "Import raw tensile CSV files to start a prep queue.";
  })();

  return (
    <div className="tensile-v2-page">
      <section className="work-card section-card tensile-v2-hero">
        <SectionHeader
          actions={<span className={`status-pill ${statusChip.tone}`}>{statusChip.label}</span>}
          kicker="Tensile"
          title="Queue-oriented prep workbench"
          description="Build comparison bundles from raw CSV intake to prepared export."
        />

        <div className="tensile-v2-summary-grid" aria-label="Tensile session summary">
          <div className="tensile-v2-summary-card">
            <span>Raw intake</span>
            <strong>{rawCsvQueue.length} queued CSV</strong>
            <p>{rawCsvQueue.length > 0 ? "Ready for preprocess." : "Import raw files to start."}</p>
          </div>
          <div className="tensile-v2-summary-card">
            <span>Prepared queue</span>
            <strong>{compareSourceCount} workbook source(s)</strong>
            <p>{compareSourceCount >= 2 ? "Ready to export comparison set." : "Queue at least two sources."}</p>
          </div>
          <div className="tensile-v2-summary-card">
            <span>Latest output</span>
            <strong>{latestComparisonResult?.outputs.length ?? 0} comparison file(s)</strong>
            <p>{latestPreprocessResult ? formatLeaf(latestPreprocessResult.output_path) : "No workbook prepared yet."}</p>
          </div>
          <div className="tensile-v2-summary-card">
            <span>Plot handoff</span>
            <strong>{handoffTarget ? formatLeaf(handoffTarget) : "Idle"}</strong>
            <p>Open any prepared workbook directly in Plot.</p>
          </div>
        </div>

        <CompactToolbar label="Tensile action bar">
          <button className="ghost-button" disabled={busy} onClick={() => void importRawCsvs()} type="button">
            Import CSVs
          </button>
          <button
            className="primary-button"
            disabled={!canPrepareWorkbook}
            onClick={() => void prepareQueuedCsvs()}
            type="button"
          >
            Prepare workbook
          </button>
          <button className="ghost-button" disabled={busy} onClick={() => void addPreparedWorkbooks()} type="button">
            Add prepared workbook
          </button>
          <button
            className="primary-button"
            disabled={!canExportComparison}
            onClick={() => void runTensileComparisonExport()}
            type="button"
          >
            Export comparison set
          </button>
        </CompactToolbar>

        {error && <div className="error-card">{error}</div>}
        {!wizard.sidecarReady && (
          <div className="warning-card">
            The Python sidecar is offline. Prepare, inspect, and compare actions resume once it reconnects.
          </div>
        )}
      </section>

      <div className="tensile-v2-workflow">
        <section className="work-card section-card tensile-v2-stage-card">
          <SectionHeader
            kicker="Step 1"
            title="Intake raw CSV queue"
            description={`${rawCsvQueue.length} file(s) queued for preprocessing`}
          />

          <CompactToolbar label="Raw queue actions">
            <button className="ghost-button" disabled={busy} onClick={() => setRawCsvQueue([])} type="button">
              Clear queue
            </button>
            <button
              className="ghost-button"
              disabled={!canPrepareWorkbook}
              onClick={() => void prepareQueuedCsvs()}
              type="button"
            >
              Run prepare
            </button>
          </CompactToolbar>

          {rawCsvQueue.length === 0 ? (
            <div className="placeholder-card">No raw CSV files queued.</div>
          ) : (
            <div className="launchpad-v2-list">
              {rawCsvQueue.map((path) => (
                <CompactListRow
                  key={path}
                  onSelect={() => setRawCsvQueue((current) => current.filter((item) => item !== path))}
                  right={<span className="signal-tag">Remove</span>}
                  subtitle={path}
                  title={formatLeaf(path)}
                />
              ))}
            </div>
          )}

          {latestPreprocessResult && (
            <details className="wizard-details">
              <summary>Latest prepared workbook</summary>
              <div className="wizard-section-stack">
                <div className="context-list">
                  <div className="context-row">
                    <span>Workbook</span>
                    <strong>{formatLeaf(latestPreprocessResult.output_path)}</strong>
                  </div>
                  <div className="context-row">
                    <span>Preferred sheet</span>
                    <strong>{latestPreprocessResult.preferred_sheet}</strong>
                  </div>
                  <div className="context-row">
                    <span>Samples</span>
                    <strong>{latestPreprocessResult.sample_count}</strong>
                  </div>
                </div>
                <CompactToolbar label="Prepared workbook actions">
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
                    Open latest in Plot
                  </button>
                </CompactToolbar>
              </div>
            </details>
          )}
        </section>

        <section className="work-card section-card tensile-v2-stage-card">
          <SectionHeader
            kicker="Step 2"
            title="Prepared workbook comparison queue"
            description={`${compareSourceCount} source(s) queued`}
          />

          <CompactToolbar label="Prepared queue actions">
            <button className="ghost-button" disabled={busy} onClick={() => void addPreparedWorkbooks()} type="button">
              Add prepared workbook
            </button>
            <button
              className="ghost-button"
              disabled={busy || compareSourceCount === 0}
              onClick={() => tensile.clearComparisonSources()}
              type="button"
            >
              Clear queue
            </button>
          </CompactToolbar>

          {compareSourceCount === 0 ? (
            <div className="placeholder-card">Queue at least two prepared workbooks to export.</div>
          ) : (
            <div className="launchpad-v2-list">
              {tensile.comparisonSources.map((source, index) => (
                <article className="tensile-v2-queue-row" key={source.workbook_path}>
                  <CompactListRow
                    right={<span className="signal-tag">{source.sample_count} replicates</span>}
                    subtitle={source.workbook_path}
                    title={source.label}
                  />
                  <CompactToolbar label={`Queue actions for ${source.label}`}>
                    <button
                      className="ghost-button"
                      disabled={busy}
                      onClick={() =>
                        void openWorkbookInPlotting(
                          source.workbook_path,
                          source.sheet_names.includes("Representative_Curve")
                            ? "Representative_Curve"
                            : (source.sheet_names[0] ?? 0),
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
                  </CompactToolbar>
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
                </article>
              ))}
            </div>
          )}

          {latestComparisonResult && (
            <details className="wizard-details">
              <summary>Latest comparison export</summary>
              <div className="wizard-section-stack">
                <div className="context-list">
                  <div className="context-row">
                    <span>Bundle folder</span>
                    <strong>{formatLeaf(latestComparisonResult.bundle_dir)}</strong>
                  </div>
                  <div className="context-row">
                    <span>Summary workbook</span>
                    <strong>{formatLeaf(latestComparisonResult.comparison_workbook_path)}</strong>
                  </div>
                  <div className="context-row">
                    <span>Outputs</span>
                    <strong>{latestComparisonResult.outputs.length}</strong>
                  </div>
                </div>
              </div>
            </details>
          )}
        </section>
      </div>

      <section className="work-card section-card tensile-v2-next">
        <SectionHeader
          kicker="Step 3"
          title="Export and handoff"
          description="Next actions stay in the same queue workspace so flow remains continuous."
        />
        <div className="tensile-v2-next-grid">
          <div className="focus-panel">
            <strong>{nextActionText}</strong>
            <span>Backward navigation and Plot handoff preserve current state.</span>
          </div>
          <div className="context-list">
            <div className="context-row">
              <span>Queued CSV files</span>
              <strong>{rawCsvQueue.length}</strong>
            </div>
            <div className="context-row">
              <span>Queued workbooks</span>
              <strong>{compareSourceCount}</strong>
            </div>
            <div className="context-row">
              <span>Comparison outputs</span>
              <strong>{latestComparisonResult?.outputs.length ?? 0}</strong>
            </div>
            <div className="context-row">
              <span>Handoff target</span>
              <strong>{handoffTarget ? formatLeaf(handoffTarget) : "Idle"}</strong>
            </div>
          </div>
        </div>
        <CompactToolbar label="Next action shortcuts">
          {rawCsvQueue.length > 0 && (
            <button
              className="primary-button"
              disabled={!canPrepareWorkbook}
              onClick={() => void prepareQueuedCsvs()}
              type="button"
            >
              Prepare workbook
            </button>
          )}
          {rawCsvQueue.length === 0 && !latestPreprocessResult && (
            <button className="primary-button" disabled={busy} onClick={() => void importRawCsvs()} type="button">
              Import CSVs
            </button>
          )}
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
              Continue in Plot
            </button>
          )}
          {compareSourceCount >= 2 && (
            <button
              className="primary-button"
              disabled={!canExportComparison}
              onClick={() => void runTensileComparisonExport()}
              type="button"
            >
              Export comparison set
            </button>
          )}
        </CompactToolbar>
      </section>

      <footer className="plot-flow-footer tensile-v2-footer">
        <span>{rawCsvQueue.length} CSV file(s) in intake queue</span>
        <span>{compareSourceCount} prepared workbook source(s)</span>
        <span>{latestComparisonResult ? `${latestComparisonResult.outputs.length} output(s) exported` : "No comparison export yet"}</span>
      </footer>
    </div>
  );
}
