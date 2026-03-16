import { useEffect, useMemo, useRef, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { PreviewPane } from "../components/PreviewPane";
import {
  exportTensileComparison,
  exportRender,
  inspectFile,
  inspectTensileWorkbook,
  preflightRender,
  preprocessTensileReplicates,
} from "../lib/api";
import { applyInspectionToWizard, loadWizardDataFile } from "../lib/project-io";
import { useWizardStore, useWorkbenchStore } from "../lib/store";
import { openDialog, saveDialog } from "../lib/tauri-dialog";
import {
  tensileComparisonSourceFromPreprocess,
  tensileComparisonSourceFromSummary,
} from "../lib/tensile-comparison";
import type {
  TemplateName,
  TensileReplicateResponse,
  WorkbenchMeta,
  WizardStep,
} from "../lib/types";
import {
  compatibleTemplateChoices,
  defaultSiblingPath,
  formatLeaf,
  formatMetricValue,
  getErrorMessage,
  incompatibleTemplateChoices,
  inferTensileGroupName,
  publicPaletteChoices,
  sizeChoices,
  templateCompatibilityReason,
  templateLabel,
  toDialogPaths,
} from "../lib/workbench";
import {
  areRenderOptionsEqual,
  mergeRenderOptions,
  sanitizeRenderOptions,
  sanitizeTemplateId,
  selectionFromInspection,
  templateMeta as wizardTemplateMeta,
} from "../lib/wizard";
import { useWizardPreview } from "./wizard/useWizardPreview";

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
}

function deriveWizardStep(args: {
  inputPath: string;
  inspectionReady: boolean;
  template: TemplateName | null;
  autoChecking: boolean;
  preflightReady: boolean;
  outputsCount: number;
}): WizardStep {
  if (!args.inputPath) {
    return "file";
  }
  if (args.outputsCount > 0) {
    return "export";
  }
  if (args.autoChecking || args.preflightReady) {
    return "preflight";
  }
  if (args.template) {
    return "options";
  }
  if (args.inspectionReady) {
    return "inspect";
  }
  return "file";
}

export function WizardScreen({ meta }: { meta: WorkbenchMeta | null }) {
  const wizard = useWizardStore(
    useShallow((state) => ({
      busy: state.busy,
      error: state.error,
      inputPath: state.inputPath,
      inspection: state.inspection,
      options: state.options,
      outputs: state.outputs,
      preflight: state.preflight,
      previewIndex: state.previewIndex,
      previews: state.previews,
      reset: state.reset,
      addTensileComparisonSource: state.addTensileComparisonSource,
      clearTensileComparisonSources: state.clearTensileComparisonSources,
      moveTensileComparisonSource: state.moveTensileComparisonSource,
      removeTensileComparisonSource: state.removeTensileComparisonSource,
      setBusy: state.setBusy,
      setError: state.setError,
      setInputPath: state.setInputPath,
      setInspection: state.setInspection,
      setOptions: state.setOptions,
      setOutputs: state.setOutputs,
      setPreflight: state.setPreflight,
      setPreviewIndex: state.setPreviewIndex,
      setPreviews: state.setPreviews,
      setSheet: state.setSheet,
      setSheetNames: state.setSheetNames,
      setStep: state.setStep,
      setTensileComparisonResult: state.setTensileComparisonResult,
      setTemplate: state.setTemplate,
      sheet: state.sheet,
      sheetNames: state.sheetNames,
      sidecarReady: state.sidecarReady,
      step: state.step,
      tensileComparisonResult: state.tensileComparisonResult,
      tensileComparisonSources: state.tensileComparisonSources,
      template: state.template,
    })),
  );
  const rememberProject = useWorkbenchStore((state) => state.rememberProject);
  const [tensileBatchResult, setTensileBatchResult] = useState<TensileReplicateResponse | null>(null);
  const [showAllTemplates, setShowAllTemplates] = useState(false);
  const [preflightBusy, setPreflightBusy] = useState(false);
  const [preflightRequestError, setPreflightRequestError] = useState<string | null>(null);
  const setWizardOptions = wizard.setOptions;
  const setWizardPreviews = wizard.setPreviews;
  const setWizardTemplate = wizard.setTemplate;
  const latestPreflightRef = useRef(0);

  const recommendation = wizard.inspection?.recommendation ?? null;
  const sizeOptions = sizeChoices(meta, wizard.template);
  const paletteOptions = publicPaletteChoices(meta, wizard.template);
  const currentTemplate = useMemo(
    () => wizardTemplateMeta(meta, wizard.template),
    [meta, wizard.template],
  );
  const compatibleTemplates = useMemo(
    () => compatibleTemplateChoices(meta, wizard.inspection?.model),
    [meta, wizard.inspection?.model],
  );
  const incompatibleTemplates = useMemo(
    () => incompatibleTemplateChoices(meta, wizard.inspection?.model),
    [meta, wizard.inspection?.model],
  );
  const recommendedSelection = useMemo(
    () => (wizard.inspection ? selectionFromInspection(meta, wizard.inspection) : null),
    [meta, wizard.inspection],
  );
  const recommendationApplied =
    recommendedSelection != null &&
    wizard.template === recommendedSelection.template &&
    areRenderOptionsEqual(wizard.options, recommendedSelection.options);

  const invalidateRenderState = () => {
    wizard.setPreflight(null);
    wizard.setOutputs([]);
  };

  const showDialogError = (error: unknown) => {
    wizard.setError(getErrorMessage(error));
  };

  const applyRecommendedSelection = () => {
    if (!recommendedSelection) {
      return;
    }
    invalidateRenderState();
    setWizardTemplate(recommendedSelection.template);
    setWizardOptions(recommendedSelection.options);
  };

  const updateWizardTemplate = (value: TemplateName) => {
    const nextTemplate = sanitizeTemplateId(
      meta,
      value,
      recommendation?.template ?? wizard.template,
    );
    if (!nextTemplate) {
      return;
    }
    invalidateRenderState();
    setWizardTemplate(nextTemplate);
    setWizardOptions(sanitizeRenderOptions(meta, nextTemplate, wizard.options));
  };

  const updateWizardOptions = (value: Partial<typeof wizard.options>) => {
    if (!wizard.template) {
      return;
    }
    invalidateRenderState();
    setWizardOptions(mergeRenderOptions(meta, wizard.template, wizard.options, value));
  };

  useEffect(() => {
    const nextTemplate = sanitizeTemplateId(
      meta,
      wizard.template,
      recommendation?.template ?? null,
    );
    if (nextTemplate !== wizard.template) {
      setWizardTemplate(nextTemplate);
    }
    const nextOptions = sanitizeRenderOptions(meta, nextTemplate, wizard.options);
    if (!areRenderOptionsEqual(nextOptions, wizard.options)) {
      setWizardOptions(nextOptions);
    }
  }, [
    meta,
    recommendation?.template,
    setWizardOptions,
    setWizardTemplate,
    wizard.options,
    wizard.template,
  ]);

  useEffect(() => {
    setShowAllTemplates(false);
  }, [wizard.inputPath, wizard.inspection?.model]);

  const { busy: previewBusy, error: previewError } = useWizardPreview({
    inputPath: wizard.inputPath,
    sheet: wizard.sheet,
    template: wizard.template,
    options: wizard.options,
    onPreviews: setWizardPreviews,
  });

  useEffect(() => {
    if (!wizard.inputPath || !wizard.template) {
      setWizardPreviews([]);
      return;
    }
  }, [setWizardPreviews, wizard.inputPath, wizard.template]);

  useEffect(() => {
    if (!wizard.inputPath || !wizard.template) {
      latestPreflightRef.current += 1;
      setPreflightBusy(false);
      setPreflightRequestError(null);
      wizard.setPreflight(null);
      return;
    }

    const requestId = latestPreflightRef.current + 1;
    latestPreflightRef.current = requestId;
    const inputPath = wizard.inputPath;
    const sheet = wizard.sheet;
    const template = wizard.template;
    const options = wizard.options;
    const controller = new AbortController();
    const handle = window.setTimeout(() => {
      setPreflightBusy(true);
      setPreflightRequestError(null);

      void preflightRender(
        inputPath,
        sheet,
        template,
        options,
        { signal: controller.signal },
      )
        .then((response) => {
          if (latestPreflightRef.current !== requestId || controller.signal.aborted) {
            return;
          }
          wizard.setPreflight(response.preflight);
          setPreflightRequestError(null);
        })
        .catch((error) => {
          if (isAbortError(error) || latestPreflightRef.current !== requestId) {
            return;
          }
          wizard.setPreflight(null);
          setPreflightRequestError(getErrorMessage(error));
        })
        .finally(() => {
          if (latestPreflightRef.current === requestId) {
            setPreflightBusy(false);
          }
        });
    }, 220);

    return () => {
      controller.abort();
      window.clearTimeout(handle);
    };
  }, [
    wizard.inputPath,
    wizard.options,
    wizard.setPreflight,
    wizard.sheet,
    wizard.template,
  ]);

  const blockingErrors = wizard.preflight?.errors ?? [];
  const hasBlockingErrors = blockingErrors.length > 0 || Boolean(preflightRequestError);
  const canExport =
    Boolean(wizard.inputPath) &&
    Boolean(wizard.template) &&
    wizard.sidecarReady &&
    !wizard.busy &&
    !previewBusy &&
    !preflightBusy &&
    !hasBlockingErrors &&
    wizard.preflight !== null;

  useEffect(() => {
    const nextStep = deriveWizardStep({
      inputPath: wizard.inputPath,
      inspectionReady: wizard.inspection != null,
      template: wizard.template,
      autoChecking: previewBusy || preflightBusy,
      preflightReady: wizard.preflight != null,
      outputsCount: wizard.outputs.length,
    });
    if (wizard.step !== nextStep) {
      wizard.setStep(nextStep);
    }
  }, [
    preflightBusy,
    previewBusy,
    wizard.inputPath,
    wizard.inspection,
    wizard.outputs.length,
    wizard.preflight,
    wizard.setStep,
    wizard.step,
    wizard.template,
  ]);

  const statusChip = useMemo(() => {
    if (!wizard.inputPath) {
      return { label: "等待输入", tone: "warn" };
    }
    if (wizard.busy) {
      return { label: "载入中", tone: "accent" };
    }
    if (previewBusy || preflightBusy) {
      return { label: "自动检查中", tone: "accent" };
    }
    if (hasBlockingErrors) {
      return { label: "需处理错误", tone: "warn" };
    }
    if (wizard.outputs.length > 0) {
      return { label: "已导出", tone: "good" };
    }
    if (wizard.preflight) {
      return { label: "可导出", tone: "good" };
    }
    if (wizard.inspection) {
      return { label: "已识别", tone: "accent" };
    }
    return { label: "等待输入", tone: "warn" };
  }, [
    hasBlockingErrors,
    preflightBusy,
    previewBusy,
    wizard.busy,
    wizard.inputPath,
    wizard.inspection,
    wizard.outputs.length,
    wizard.preflight,
  ]);

  const expectedOutputs =
    wizard.outputs.length > 0
      ? wizard.outputs
      : (wizard.preflight?.output_filenames ?? []).map((filename) => filename);
  const compareSourceCount = wizard.tensileComparisonSources.length;
  const canExportTensileComparison = compareSourceCount >= 2 && !wizard.busy;

  const openDataFile = async () => {
    let path: string | undefined;
    wizard.setError(null);
    try {
      const selected = await openDialog({
        multiple: false,
        filters: [
          {
            name: "Data",
            extensions: ["csv", "txt", "tsv", "xlsx", "xlsm"],
          },
        ],
      });
      path = toDialogPaths(selected, 1)[0];
    } catch (error) {
      showDialogError(error);
      return;
    }
    if (!path) {
      return;
    }

    setTensileBatchResult(null);
    wizard.setBusy(true);
    try {
      const inspected = await loadWizardDataFile(wizard, meta, path);
      rememberProject({
        mode: "wizard",
        kind: "data",
        path: inspected.input_path,
        title: formatLeaf(inspected.input_path),
        detail: `数据文件 · ${inspected.sheet_names.length} sheet · ${templateLabel(meta, inspected.inspection.recommendation.template)}`,
      });
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  const runTensileReplicatePreprocess = async () => {
    let filePaths: string[] = [];
    wizard.setError(null);
    try {
      const selected = await openDialog({
        multiple: true,
        filters: [{ name: "Tensile CSV", extensions: ["csv", "CSV"] }],
      });
      filePaths = toDialogPaths(selected);
    } catch (error) {
      showDialogError(error);
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
    } catch (error) {
      showDialogError(error);
      return;
    }
    if (typeof destination !== "string") {
      return;
    }

    setTensileBatchResult(null);
    wizard.setBusy(true);
    try {
      const result = await preprocessTensileReplicates(
        filePaths,
        destination,
        inferredGroupName,
      );
      setTensileBatchResult(result);
      wizard.addTensileComparisonSource(tensileComparisonSourceFromPreprocess(result));
      const inspected = await loadWizardDataFile(
        wizard,
        meta,
        result.output_path,
        result.preferred_sheet,
        "inspect",
      );
      rememberProject({
        mode: "wizard",
        kind: "data",
        path: result.output_path,
        title: formatLeaf(result.output_path),
        detail: `拉伸整理 · ${result.sample_count} 个重复样 · ${templateLabel(meta, inspected.inspection.recommendation.template)}`,
      });
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  const addTensileComparisonWorkbooks = async () => {
    let workbookPaths: string[] = [];
    wizard.setError(null);
    try {
      const selected = await openDialog({
        multiple: true,
        filters: [{ name: "Excel Workbook", extensions: ["xlsx", "xlsm"] }],
      });
      workbookPaths = toDialogPaths(selected);
    } catch (error) {
      showDialogError(error);
      return;
    }
    if (workbookPaths.length === 0) {
      return;
    }

    wizard.setBusy(true);
    const failures: string[] = [];
    try {
      for (const workbookPath of workbookPaths) {
        try {
          const summary = await inspectTensileWorkbook(workbookPath);
          wizard.addTensileComparisonSource(tensileComparisonSourceFromSummary(summary));
        } catch (error) {
          failures.push(`${formatLeaf(workbookPath)}：${getErrorMessage(error)}`);
        }
      }
      if (failures.length > 0) {
        wizard.setError(`以下 workbook 未加入对比清单：${failures.join("；")}`);
      }
    } finally {
      wizard.setBusy(false);
    }
  };

  const runTensileComparisonExport = async () => {
    if (wizard.tensileComparisonSources.length < 2) {
      return;
    }

    let outputDir: string | undefined;
    wizard.setError(null);
    try {
      const selected = await openDialog({
        multiple: false,
        directory: true,
      });
      outputDir = toDialogPaths(selected, 1)[0];
    } catch (error) {
      showDialogError(error);
      return;
    }
    if (!outputDir) {
      return;
    }

    wizard.setBusy(true);
    try {
      const result = await exportTensileComparison(
        wizard.tensileComparisonSources.map((item) => item.workbook_path),
        outputDir,
      );
      wizard.setTensileComparisonResult(result);
      rememberProject({
        mode: "wizard",
        kind: "data",
        path: result.comparison_workbook_path,
        title: formatLeaf(result.comparison_workbook_path),
        detail: `拉伸对比 · ${result.labels.length} 组 · ${result.outputs.length} 个结果`,
      });
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  const rerunInspect = async (sheetValue: string | number) => {
    if (!wizard.inputPath) {
      return;
    }

    wizard.setError(null);
    wizard.setBusy(true);
    try {
      const inspected = await inspectFile(wizard.inputPath, sheetValue);
      applyInspectionToWizard(wizard, meta, inspected, { nextStep: "inspect" });
      invalidateRenderState();
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  const runExport = async () => {
    if (!wizard.inputPath || !wizard.template || !wizard.preflight || hasBlockingErrors) {
      return;
    }

    wizard.setError(null);
    wizard.setBusy(true);
    try {
      const response = await exportRender(
        wizard.inputPath,
        wizard.sheet,
        wizard.template,
        wizard.options,
      );
      wizard.setOutputs(response.outputs);
      wizard.setStep("export");
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  return (
    <div className="desk-layout wizard-layout">
      <section className="desk-main wizard-main">
        <article className="work-card section-card wizard-workspace-card">
          <div className="section-head wizard-workspace-head">
            <div>
              <div className="card-kicker">绘图</div>
              <h2>单图自动检查流</h2>
              <p>输入、识别、模板、参数和导出都收在同一块工作区里。</p>
            </div>
            <div className="wizard-inline-chips">
              {wizard.inputPath && <span className="signal-tag">{formatLeaf(wizard.inputPath)}</span>}
              <span className={`status-pill ${statusChip.tone}`}>{statusChip.label}</span>
            </div>
          </div>

          <div className="wizard-toolbar">
            <button className="primary-button" onClick={openDataFile} type="button">
              选择数据
            </button>
            <button
              className="ghost-button"
              onClick={() => void runTensileReplicatePreprocess()}
              type="button"
            >
              整理拉伸重复 CSV
            </button>
            {wizard.sheetNames.length > 1 && (
              <label className="wizard-inline-field">
                <span className="field-label">Sheet</span>
                <select
                  className="field"
                  value={String(wizard.sheet)}
                  onChange={(event) => void rerunInspect(event.target.value)}
                >
                  {wizard.sheetNames.map((name, index) => (
                    <option key={name} value={name}>
                      {index + 1}. {name}
                    </option>
                  ))}
                </select>
              </label>
            )}
          </div>

          {wizard.error && <div className="error-card">{wizard.error}</div>}
          {!wizard.sidecarReady && (
            <div className="warning-card">
              Python sidecar 当前未连通，自动识别、预览和导出会在连接恢复后继续正常工作。
            </div>
          )}
          {tensileBatchResult && (
            <div className="wizard-callout-stack">
              <div className="success-card">
                已整理 {tensileBatchResult.sample_count} 个拉伸重复样，代表曲线来自{" "}
                {tensileBatchResult.representative_filename}，模板工作簿已自动载入。
              </div>
              <div className="summary-grid wizard-tight-grid">
                <div className="stat-tile">
                  <span>输出文件</span>
                  <strong>{formatLeaf(tensileBatchResult.output_path)}</strong>
                </div>
                <div className="stat-tile">
                  <span>默认工作表</span>
                  <strong>{tensileBatchResult.preferred_sheet}</strong>
                </div>
                {tensileBatchResult.metrics.map((metric) => (
                  <div className="stat-tile" key={metric.label}>
                    <span>{metric.label}</span>
                    <strong>
                      {formatMetricValue(metric.mean)} ± {formatMetricValue(metric.std)} {metric.unit}
                    </strong>
                  </div>
                ))}
              </div>
              {tensileBatchResult.warnings.length > 0 && (
                <details>
                  <summary>展开查看被跳过的文件</summary>
                  <ul className="bullet-list">
                    {tensileBatchResult.warnings.map((item) => (
                      <li key={item}>{item}</li>
                    ))}
                  </ul>
                </details>
              )}
            </div>
          )}

          <div className="wizard-callout-stack">
            <div className="focus-panel">
              <strong>拉伸对比清单</strong>
              <span>
                已收集 {compareSourceCount} 组已整理 workbook。达到 2 组后，可直接导出代表曲线、
                Strength / Modulus / Elongation 的箱线图和柱状图。
              </span>
            </div>
            <div className="step-actions">
              <button
                className="ghost-button"
                onClick={() => void addTensileComparisonWorkbooks()}
                type="button"
              >
                补录已整理 workbook
              </button>
              <button
                className="ghost-button"
                disabled={compareSourceCount === 0}
                onClick={() => wizard.clearTensileComparisonSources()}
                type="button"
              >
                清空清单
              </button>
              <button
                className="primary-button"
                disabled={!canExportTensileComparison}
                onClick={() => void runTensileComparisonExport()}
                type="button"
              >
                生成对比图
              </button>
            </div>

            {compareSourceCount === 0 ? (
              <div className="placeholder-card">
                先整理一组拉伸 CSV，或补录至少 2 份已整理 workbook，再生成 7 张对比图。
              </div>
            ) : (
              <div className="wizard-compare-list">
                {wizard.tensileComparisonSources.map((source, index) => (
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
                          disabled={index === 0}
                          onClick={() =>
                            wizard.moveTensileComparisonSource(source.workbook_path, -1)
                          }
                          type="button"
                        >
                          上移
                        </button>
                        <button
                          className="ghost-button"
                          disabled={index === compareSourceCount - 1}
                          onClick={() =>
                            wizard.moveTensileComparisonSource(source.workbook_path, 1)
                          }
                          type="button"
                        >
                          下移
                        </button>
                        <button
                          className="ghost-button"
                          onClick={() => wizard.removeTensileComparisonSource(source.workbook_path)}
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

            {wizard.tensileComparisonResult && (
              <div className="wizard-callout-stack">
                <div className="success-card">
                  已为 {wizard.tensileComparisonResult.labels.length} 组生成{" "}
                  {wizard.tensileComparisonResult.outputs.length} 个对比结果。
                </div>
                <div className="summary-grid wizard-tight-grid">
                  <div className="stat-tile">
                    <span>对比目录</span>
                    <strong>{formatLeaf(wizard.tensileComparisonResult.bundle_dir)}</strong>
                  </div>
                  <div className="stat-tile">
                    <span>汇总 workbook</span>
                    <strong>{formatLeaf(wizard.tensileComparisonResult.comparison_workbook_path)}</strong>
                  </div>
                  <div className="stat-tile">
                    <span>组数</span>
                    <strong>{wizard.tensileComparisonResult.labels.length}</strong>
                  </div>
                  <div className="stat-tile">
                    <span>输出数</span>
                    <strong>{wizard.tensileComparisonResult.outputs.length}</strong>
                  </div>
                </div>
                <div className="focus-panel">
                  <strong>导出文件</strong>
                  <ul className="output-list">
                    {wizard.tensileComparisonResult.outputs.map((item) => (
                      <li key={item}>{formatLeaf(item)}</li>
                    ))}
                  </ul>
                </div>
              </div>
            )}
          </div>

          <div className="wizard-pane-grid">
            <section className="wizard-pane">
              <div className="card-kicker">识别摘要</div>
              <h3>当前输入识别结果</h3>
              {!wizard.inspection ? (
                <div className="placeholder-card">选择数据后，这里会显示输入模型、推荐图型和推荐原因。</div>
              ) : (
                <div className="wizard-section-stack">
                  <div className="info-grid wizard-tight-grid">
                    <div className="stat-tile">
                      <span>输入模型</span>
                      <strong>{wizard.inspection.model_label}</strong>
                    </div>
                    <div className="stat-tile">
                      <span>推荐图型</span>
                      <strong>{templateLabel(meta, wizard.inspection.recommendation.template)}</strong>
                    </div>
                  </div>
                  <div className="focus-panel">
                    <strong>推荐原因</strong>
                    <span>{wizard.inspection.recommendation.reason}</span>
                  </div>
                  {wizard.inspection.warnings.length > 0 && (
                    <div className="warning-card">
                      <strong>输入提醒</strong>
                      <ul className="bullet-list">
                        {wizard.inspection.warnings.map((item) => (
                          <li key={item}>{item}</li>
                        ))}
                      </ul>
                    </div>
                  )}
                  {wizard.inspection.signals.length > 0 && (
                    <details>
                      <summary>展开查看识别信号</summary>
                      <ul className="bullet-list">
                        {wizard.inspection.signals.map((item) => (
                          <li key={item}>{item}</li>
                        ))}
                      </ul>
                    </details>
                  )}
                </div>
              )}
            </section>

            <section className="wizard-pane">
              <div className="card-kicker">图型</div>
              <h3>兼容模板</h3>
              {!wizard.inspection ? (
                <div className="placeholder-card">先载入数据，再根据识别结果显示兼容模板。</div>
              ) : (
                <div className="wizard-section-stack">
                  <div className="wizard-template-grid">
                    {compatibleTemplates.map((template) => (
                      <button
                        className={`wizard-template-chip ${wizard.template === template.id ? "active" : ""}`}
                        key={template.id}
                        onClick={() => updateWizardTemplate(template.id)}
                        type="button"
                      >
                        <strong>{template.label}</strong>
                        <span>{template.description}</span>
                      </button>
                    ))}
                  </div>
                  {incompatibleTemplates.length > 0 && (
                    <>
                      <button
                        className="ghost-button"
                        onClick={() => setShowAllTemplates((current) => !current)}
                        type="button"
                      >
                        {showAllTemplates ? "收起其他图型" : "更多图型"}
                      </button>
                      {showAllTemplates && (
                        <div className="wizard-template-grid">
                          {incompatibleTemplates.map((template) => (
                            <button
                              className="wizard-template-chip disabled"
                              disabled
                              key={template.id}
                              type="button"
                            >
                              <strong>{template.label}</strong>
                              <span>{templateCompatibilityReason(wizard.inspection?.model)}</span>
                            </button>
                          ))}
                        </div>
                      )}
                    </>
                  )}
                </div>
              )}
            </section>

            <section className="wizard-pane">
              <div className="card-kicker">参数</div>
              <h3>关键参数</h3>
              {!wizard.template ? (
                <div className="placeholder-card">确认输入后，这里会显示当前模板可编辑的参数。</div>
              ) : (
                <div className="wizard-section-stack">
                  <div className="field-grid wizard-tight-grid">
                    <label>
                      <span className="field-label">尺寸</span>
                      <select
                        className="field"
                        value={wizard.options.size ?? sizeOptions[0]?.id ?? ""}
                        onChange={(event) => updateWizardOptions({ size: event.target.value })}
                      >
                        {sizeOptions.map((choice) => (
                          <option key={choice.id} value={choice.id}>
                            {choice.id}
                          </option>
                        ))}
                      </select>
                    </label>

                    {currentTemplate?.editable_options.includes("xscale") && (
                      <label>
                        <span className="field-label">X 轴</span>
                        <select
                          className="field"
                          value={wizard.options.xscale ?? "linear"}
                          onChange={(event) =>
                            updateWizardOptions({
                              xscale: event.target.value === "log" ? "log" : "linear",
                            })
                          }
                        >
                          <option value="linear">linear</option>
                          <option value="log">log</option>
                        </select>
                      </label>
                    )}

                    {currentTemplate?.editable_options.includes("yscale") && (
                      <label>
                        <span className="field-label">Y 轴</span>
                        <select
                          className="field"
                          value={wizard.options.yscale ?? "linear"}
                          onChange={(event) =>
                            updateWizardOptions({
                              yscale: event.target.value === "log" ? "log" : "linear",
                            })
                          }
                        >
                          <option value="linear">linear</option>
                          <option value="log">log</option>
                        </select>
                      </label>
                    )}

                    {currentTemplate?.editable_options.includes("reverse_x") && (
                      <label className="toggle-field">
                        <input
                          checked={Boolean(wizard.options.reverse_x)}
                          onChange={(event) =>
                            updateWizardOptions({ reverse_x: event.target.checked })
                          }
                          type="checkbox"
                        />
                        <span>反向 X 轴</span>
                      </label>
                    )}

                    {currentTemplate?.editable_options.includes("baseline") && (
                      <label>
                        <span className="field-label">Baseline</span>
                        <select
                          className="field"
                          value={wizard.options.baseline ?? "none"}
                          onChange={(event) =>
                            updateWizardOptions({
                              baseline:
                                event.target.value === "linear_endpoints"
                                  ? "linear_endpoints"
                                  : "none",
                            })
                          }
                        >
                          <option value="none">none</option>
                          <option value="linear_endpoints">linear_endpoints</option>
                        </select>
                      </label>
                    )}

                    {currentTemplate?.editable_options.includes("show_colorbar") && (
                      <label className="toggle-field">
                        <input
                          checked={Boolean(
                            wizard.options.show_colorbar ??
                              currentTemplate.default_options.show_colorbar ??
                              true,
                          )}
                          onChange={(event) =>
                            updateWizardOptions({ show_colorbar: event.target.checked })
                          }
                          type="checkbox"
                        />
                        <span>显示 colorbar</span>
                      </label>
                    )}
                  </div>

                  {currentTemplate?.editable_options.includes("palette_preset") && (
                    <details>
                      <summary>高级选项</summary>
                      <div className="field-grid compact-grid advanced-grid wizard-tight-grid">
                        <label>
                          <span className="field-label">配色</span>
                          <select
                            className="field"
                            value={wizard.options.palette_preset ?? meta?.default_palette ?? ""}
                            onChange={(event) =>
                              updateWizardOptions({
                                palette_preset: event.target.value,
                              })
                            }
                          >
                            {paletteOptions.map((choice) => (
                              <option key={choice.id} value={choice.id}>
                                {choice.label}
                              </option>
                            ))}
                          </select>
                        </label>
                      </div>
                    </details>
                  )}
                </div>
              )}
            </section>

            <section className="wizard-pane">
              <div className="card-kicker">导出</div>
              <h3>自动检查与导出</h3>
              <div className="wizard-section-stack">
                {preflightRequestError && <div className="error-card">{preflightRequestError}</div>}
                {!preflightRequestError && preflightBusy && (
                  <div className="placeholder-card">正在更新预检结果…</div>
                )}
                {!preflightRequestError && !preflightBusy && wizard.preflight && (
                  <>
                    {blockingErrors.length > 0 ? (
                      <div className="error-card">
                        <strong>当前还不能直接导出：</strong>
                        <ul className="bullet-list">
                          {blockingErrors.map((item) => (
                            <li key={item}>{item}</li>
                          ))}
                        </ul>
                      </div>
                    ) : (
                      <div className="success-card">当前预检通过，可以直接导出。</div>
                    )}
                    {wizard.preflight.warnings.length > 0 && (
                      <details>
                        <summary>展开查看导出前提醒</summary>
                        <ul className="bullet-list">
                          {wizard.preflight.warnings.map((item) => (
                            <li key={item}>{item}</li>
                          ))}
                        </ul>
                      </details>
                    )}
                  </>
                )}
                {!wizard.preflight && !preflightBusy && !preflightRequestError && (
                  <div className="placeholder-card">载入数据并确认模板后，系统会自动生成预检结果。</div>
                )}

                <div className="step-actions">
                  {!recommendationApplied && wizard.inspection && (
                    <button className="ghost-button" onClick={applyRecommendedSelection} type="button">
                      恢复推荐
                    </button>
                  )}
                  <button
                    className="primary-button"
                    disabled={!canExport}
                    onClick={() => void runExport()}
                    type="button"
                  >
                    导出 PDF
                  </button>
                </div>

                <div className="focus-panel">
                  <strong>{wizard.outputs.length > 0 ? "导出结果" : "预计输出"}</strong>
                  {expectedOutputs.length > 0 ? (
                    <ul className="output-list">
                      {expectedOutputs.map((item) => (
                        <li key={item}>{formatLeaf(item)}</li>
                      ))}
                    </ul>
                  ) : (
                    <span>当前还没有可导出的文件列表。</span>
                  )}
                </div>
              </div>
            </section>
          </div>
        </article>
      </section>

      <aside className="desk-context wizard-context">
        <PreviewPane
          busy={previewBusy}
          error={previewError}
          onChangeIndex={wizard.setPreviewIndex}
          previewIndex={wizard.previewIndex}
          previews={wizard.previews}
        />

        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>当前输入</h3>
              <p>把文件、当前模板和自动检查状态收在同一处，避免重复信息卡。</p>
            </div>
          </div>
          <div className="wizard-summary-list">
            <div className="wizard-summary-row">
              <span>文件</span>
              <strong>{wizard.inputPath ? formatLeaf(wizard.inputPath) : "-"}</strong>
            </div>
            <div className="wizard-summary-row">
              <span>Sheet</span>
              <strong>{String(wizard.sheet)}</strong>
            </div>
            <div className="wizard-summary-row">
              <span>当前图型</span>
              <strong>{templateLabel(meta, wizard.template)}</strong>
            </div>
            <div className="wizard-summary-row">
              <span>当前阶段</span>
              <strong>{statusChip.label}</strong>
            </div>
            <div className="wizard-summary-row">
              <span>预览数</span>
              <strong>{wizard.previews.length}</strong>
            </div>
            <div className="wizard-summary-row">
              <span>导出数</span>
              <strong>{wizard.outputs.length}</strong>
            </div>
          </div>

          {(wizard.inspection?.warnings.length ||
            wizard.preflight?.warnings.length ||
            hasBlockingErrors) && (
            <div className="wizard-callout-stack">
              {hasBlockingErrors && (
                <div className="error-card">
                  {preflightRequestError ?? `${blockingErrors.length} 个阻断错误需要先处理。`}
                </div>
              )}
              {wizard.preflight && wizard.preflight.warnings.length > 0 && (
                <div className="warning-card">
                  导出前提醒 {wizard.preflight.warnings.length} 条。
                </div>
              )}
              {wizard.inspection && wizard.inspection.warnings.length > 0 && (
                <div className="warning-card">
                  输入提醒 {wizard.inspection.warnings.length} 条。
                </div>
              )}
            </div>
          )}
        </article>
      </aside>
    </div>
  );
}
