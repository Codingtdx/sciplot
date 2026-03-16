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
import type { WorkbenchMeta, WorkbenchScreen } from "../lib/types";
import {
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
      return { label: "处理中", tone: "accent" };
    }
    if (error) {
      return { label: "需处理错误", tone: "warn" };
    }
    if (tensile.comparisonResult) {
      return { label: "对比已导出", tone: "good" };
    }
    if (tensile.preprocessResult) {
      return { label: "已整理", tone: "accent" };
    }
    return { label: "等待输入", tone: "warn" };
  }, [busy, error, tensile.comparisonResult, tensile.preprocessResult]);

  const showDialogError = (cause: unknown) => {
    setError(getErrorMessage(cause));
  };

  const openWorkbookInPlotting = async (workbookPath: string, preferredSheet: string | number) => {
    setError(null);
    setBusy(true);
    try {
      const inspected = await loadWizardDataFile(wizard, meta, workbookPath, preferredSheet, "inspect");
      rememberProject({
        mode: "wizard",
        kind: "data",
        path: workbookPath,
        title: formatLeaf(workbookPath),
        detail: `数据文件 · ${inspected.sheet_names.length} sheet · ${templateLabel(meta, inspected.inspection.recommendation.template)}`,
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
        detail: `拉伸整理 · ${result.sample_count} 个重复样 · 已整理 workbook`,
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
        setError(`以下 workbook 未加入对比清单：${failures.join("；")}`);
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
        detail: `拉伸对比 · ${result.labels.length} 组 · ${result.outputs.length} 个结果`,
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
        <article className="work-card section-card wizard-workspace-card">
          <div className="section-head wizard-workspace-head">
            <div>
              <div className="card-kicker">Tensile</div>
              <h2>拉伸工作台</h2>
              <p>整理 raw tensile CSV、累积已整理 workbook，并一键导出拉伸对比图。</p>
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
              Python sidecar 当前未连通，拉伸整理、校验和对比导出会在连接恢复后继续正常工作。
            </div>
          )}

          <div className="wizard-pane-grid">
            <section className="wizard-pane">
              <div className="card-kicker">整理</div>
              <h3>整理 tensile 数据</h3>
              <p className="hint-text">把多份 raw tensile CSV 整理成 workbook，并在需要时再送去绘图页。</p>
              <div className="step-actions">
                <button
                  className="primary-button"
                  disabled={busy}
                  onClick={() => void runTensilePreprocess()}
                  type="button"
                >
                  整理 tensile 数据
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
                    在绘图中打开
                  </button>
                )}
              </div>

              {!latestPreprocessResult ? (
                <div className="placeholder-card">
                  先选择多份 raw tensile CSV，生成一份可继续绘图和对比的 workbook。
                </div>
              ) : (
                <div className="wizard-callout-stack">
                  <div className="success-card">
                    已整理 {latestPreprocessResult.sample_count} 个拉伸重复样，代表曲线来自{" "}
                    {latestPreprocessResult.representative_filename}。
                  </div>
                  <div className="summary-grid wizard-tight-grid">
                    <div className="stat-tile">
                      <span>输出文件</span>
                      <strong>{formatLeaf(latestPreprocessResult.output_path)}</strong>
                    </div>
                    <div className="stat-tile">
                      <span>默认工作表</span>
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
                      <summary>展开查看被跳过的文件</summary>
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

            <section className="wizard-pane">
              <div className="card-kicker">Compare</div>
              <h3>拉伸对比</h3>
              <div className="focus-panel">
                <strong>已收集 {compareSourceCount} 组</strong>
                <span>达到 2 组后，可固定按 `60x55 mm` 导出 1 张代表曲线和 6 张统计图。</span>
              </div>
              <div className="step-actions">
                <button
                  className="ghost-button"
                  disabled={busy}
                  onClick={() => void addTensileComparisonWorkbooks()}
                  type="button"
                >
                  补录已整理 workbook
                </button>
                <button
                  className="ghost-button"
                  disabled={busy || compareSourceCount === 0}
                  onClick={() => tensile.clearComparisonSources()}
                  type="button"
                >
                  清空清单
                </button>
                <button
                  className="primary-button"
                  disabled={!canExportComparison}
                  onClick={() => void runTensileComparisonExport()}
                  type="button"
                >
                  生成对比图
                </button>
              </div>

              {compareSourceCount === 0 ? (
                <div className="placeholder-card">
                  先整理一组 tensile 数据，或补录至少 2 份已整理 workbook，再生成 7 张对比图。
                </div>
              ) : (
                <div className="wizard-compare-list">
                  {tensile.comparisonSources.map((source, index) => (
                    <div className="wizard-compare-item" key={source.workbook_path}>
                      <div className="wizard-compare-head">
                        <div>
                          <strong>{source.label}</strong>
                          <span>
                            {formatLeaf(source.workbook_path)} · {source.sample_count} 个重复样
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
                            在绘图中打开
                          </button>
                          <button
                            className="ghost-button"
                            disabled={busy || index === 0}
                            onClick={() => tensile.moveComparisonSource(source.workbook_path, -1)}
                            type="button"
                          >
                            上移
                          </button>
                          <button
                            className="ghost-button"
                            disabled={busy || index === compareSourceCount - 1}
                            onClick={() => tensile.moveComparisonSource(source.workbook_path, 1)}
                            type="button"
                          >
                            下移
                          </button>
                          <button
                            className="ghost-button"
                            disabled={busy}
                            onClick={() => tensile.removeComparisonSource(source.workbook_path)}
                            type="button"
                          >
                            移除
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
                    已为 {tensile.comparisonResult.labels.length} 组生成{" "}
                    {tensile.comparisonResult.outputs.length} 个对比结果。
                  </div>
                  <div className="summary-grid wizard-tight-grid">
                    <div className="stat-tile">
                      <span>对比目录</span>
                      <strong>{formatLeaf(tensile.comparisonResult.bundle_dir)}</strong>
                    </div>
                    <div className="stat-tile">
                      <span>汇总 workbook</span>
                      <strong>{formatLeaf(tensile.comparisonResult.comparison_workbook_path)}</strong>
                    </div>
                    <div className="stat-tile">
                      <span>组数</span>
                      <strong>{tensile.comparisonResult.labels.length}</strong>
                    </div>
                    <div className="stat-tile">
                      <span>输出数</span>
                      <strong>{tensile.comparisonResult.outputs.length}</strong>
                    </div>
                  </div>
                  <div className="focus-panel">
                    <strong>导出文件</strong>
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
        </article>
      </section>

      <aside className="desk-context">
        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>当前拉伸现场</h3>
              <p>这里汇总最近一次整理结果和当前对比清单状态。</p>
            </div>
          </div>
          <div className="wizard-summary-list">
            <div className="wizard-summary-row">
              <span>最近整理</span>
              <strong>
                {latestPreprocessResult ? formatLeaf(latestPreprocessResult.output_path) : "-"}
              </strong>
            </div>
            <div className="wizard-summary-row">
              <span>默认工作表</span>
              <strong>{latestPreprocessResult?.preferred_sheet ?? "-"}</strong>
            </div>
            <div className="wizard-summary-row">
              <span>对比组数</span>
              <strong>{compareSourceCount}</strong>
            </div>
            <div className="wizard-summary-row">
              <span>导出数</span>
              <strong>{tensile.comparisonResult?.outputs.length ?? 0}</strong>
            </div>
          </div>
        </article>

        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>使用提示</h3>
              <p>整理和对比都留在这一页，只有你明确点击时才会切到绘图。</p>
            </div>
          </div>
          <ul className="bullet-list">
            <li>整理 raw tensile CSV 后，会自动加入对比清单，但不会抢占绘图页。</li>
            <li>任意组数都能对比，但 7 张导出图固定保持 `60x55 mm`。</li>
            <li>拉伸曲线默认固定使用 linear x/y 坐标，不再走 log。</li>
          </ul>
        </article>
      </aside>
    </div>
  );
}
