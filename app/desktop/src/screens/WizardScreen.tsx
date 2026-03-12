import { useEffect, useMemo, useState } from "react";
import { open, save } from "@tauri-apps/plugin-dialog";

import { PreviewPane } from "../components/PreviewPane";
import { StepFlow } from "../components/StepFlow";
import {
  exportRender,
  inspectFile,
  preflightRender,
  preprocessTensileReplicates,
  saveProject,
} from "../lib/api";
import { loadWizardDataFile, loadWizardProjectFile, applyInspectionToWizard } from "../lib/project-io";
import { useWizardStore, useWorkbenchStore } from "../lib/store";
import type {
  TemplateName,
  TensileReplicateResponse,
  WizardProject,
  WorkbenchMeta,
} from "../lib/types";
import {
  STEP_COPY,
  defaultSiblingPath,
  formatLeaf,
  formatMetricValue,
  getErrorMessage,
  getWizardStepLabel,
  inferTensileGroupName,
  publicPaletteChoices,
  sizeChoices,
  templateChoices,
  templateLabel,
  toDialogPaths,
} from "../lib/workbench";
import {
  areRenderOptionsEqual,
  mergeRenderOptions,
  sanitizeRenderOptions,
  sanitizeTemplateId,
  templateMeta as wizardTemplateMeta,
} from "../lib/wizard";
import { useWizardPreview } from "./wizard/useWizardPreview";

export function WizardScreen({ meta }: { meta: WorkbenchMeta | null }) {
  const wizard = useWizardStore();
  const rememberProject = useWorkbenchStore((state) => state.rememberProject);
  const [tensileBatchResult, setTensileBatchResult] = useState<TensileReplicateResponse | null>(null);
  const setWizardOptions = wizard.setOptions;
  const setWizardPreviews = wizard.setPreviews;
  const setWizardTemplate = wizard.setTemplate;

  const stepMeta = STEP_COPY[wizard.step];
  const recommendation = wizard.inspection?.recommendation ?? null;
  const templateOptions = templateChoices(meta);
  const sizeOptions = sizeChoices(meta, wizard.template);
  const paletteOptions = publicPaletteChoices(meta, wizard.template);
  const currentTemplate = useMemo(
    () => wizardTemplateMeta(meta, wizard.template),
    [meta, wizard.template],
  );

  const invalidateRenderState = () => {
    wizard.setPreflight(null);
    wizard.setOutputs([]);
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
    setWizardOptions(
      mergeRenderOptions(meta, wizard.template, wizard.options, value),
    );
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
    const nextOptions = sanitizeRenderOptions(
      meta,
      nextTemplate,
      wizard.options,
    );
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

  const openDataFile = async () => {
    const selected = await open({
      multiple: false,
      filters: [
        {
          name: "Data",
          extensions: ["csv", "txt", "tsv", "xlsx", "xlsm"],
        },
      ],
    });
    const path = toDialogPaths(selected, 1)[0];
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

  const openWizardProject = async () => {
    const selected = await open({
      multiple: false,
      filters: [{ name: "CodeGod Project", extensions: ["json"] }],
    });
    const path = toDialogPaths(selected, 1)[0];
    if (!path) {
      return;
    }

    setTensileBatchResult(null);
    wizard.reset();
    wizard.setError(null);
    wizard.setBusy(true);
    try {
      const payload = await loadWizardProjectFile(wizard, meta, path);
      rememberProject({
        mode: "wizard",
        kind: "project",
        path,
        title: formatLeaf(path),
        detail: `绘图项目 · ${formatLeaf(payload.wizard.input_path)} · ${payload.wizard.outputs.length} 个结果`,
      });
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  const saveWizardProject = async () => {
    if (!wizard.inputPath) {
      return;
    }
    const destination = await save({
      defaultPath: "codegod-wizard.plotproject.json",
      filters: [{ name: "CodeGod Project", extensions: ["json"] }],
    });
    if (typeof destination !== "string") {
      return;
    }

    wizard.setError(null);
    const payload: WizardProject = {
      version: 1,
      mode: "wizard",
      wizard: {
        input_path: wizard.inputPath,
        sheet: wizard.sheet,
        template: wizard.template,
        options: wizard.options,
        outputs: wizard.outputs,
      },
    };
    try {
      await saveProject(destination, payload);
      rememberProject({
        mode: "wizard",
        kind: "project",
        path: destination,
        title: formatLeaf(destination),
        detail: `已保存绘图项目 · ${wizard.outputs.length} 个结果`,
      });
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    }
  };

  const runTensileReplicatePreprocess = async () => {
    const selected = await open({
      multiple: true,
      filters: [{ name: "Tensile CSV", extensions: ["csv", "CSV"] }],
    });
    const filePaths = toDialogPaths(selected);
    if (filePaths.length === 0) {
      return;
    }

    const inferredGroupName = inferTensileGroupName(filePaths);
    const destination = await save({
      defaultPath: defaultSiblingPath(
        filePaths[0],
        `${inferredGroupName}_plot_wizard_template.xlsx`,
      ),
      filters: [{ name: "Excel Workbook", extensions: ["xlsx"] }],
    });
    if (typeof destination !== "string") {
      return;
    }

    setTensileBatchResult(null);
    wizard.setError(null);
    wizard.setBusy(true);
    try {
      const result = await preprocessTensileReplicates(
        filePaths,
        destination,
        inferredGroupName,
      );
      setTensileBatchResult(result);
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

  const runPreflight = async () => {
    if (!wizard.inputPath || !wizard.template) {
      return;
    }

    wizard.setError(null);
    wizard.setBusy(true);
    try {
      const response = await preflightRender(
        wizard.inputPath,
        wizard.sheet,
        wizard.template,
        wizard.options,
      );
      wizard.setPreflight(response.preflight);
      wizard.setStep("preflight");
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  const runExport = async () => {
    if (!wizard.inputPath || !wizard.template) {
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
    <div className="desk-layout">
      <section className="desk-main">
        <article className="work-card hero-card">
          <div className="section-head hero-head">
            <div>
              <div className="card-kicker">Single Figure Flow</div>
              <h2>一步一步做决定，不把所有表单一次塞给你</h2>
              <p>
                现在的重点不是堆按钮，而是把识别、调参、预检和导出组织成能快速推进的工作台。
              </p>
            </div>
            <div className="metric-strip">
              <div className="metric-chip">
                <span>当前步骤</span>
                <strong>{getWizardStepLabel(wizard.step)}</strong>
              </div>
              <div className={`metric-chip ${wizard.sidecarReady ? "good" : "warn"}`}>
                <span>Sidecar</span>
                <strong>{wizard.sidecarReady ? "Ready" : "Waiting"}</strong>
              </div>
            </div>
          </div>
          <StepFlow current={wizard.step} />
          <div className="hero-actions">
            <button className="primary-button" onClick={openDataFile} type="button">
              选择数据
            </button>
            <button className="ghost-button" onClick={openWizardProject} type="button">
              打开项目
            </button>
            <button
              className="ghost-button"
              disabled={!wizard.inputPath}
              onClick={() => void saveWizardProject()}
              type="button"
            >
              保存当前项目
            </button>
          </div>
        </article>

        <article className="work-card section-card">
          <div className="section-head">
            <div>
              <div className="card-kicker">当前步骤卡片</div>
              <h2>{stepMeta.title}</h2>
              <p>{stepMeta.description}</p>
            </div>
          </div>

          {wizard.error && <div className="error-card">{wizard.error}</div>}
          {tensileBatchResult && (
            <>
              <div className="success-card">
                已整理 {tensileBatchResult.sample_count} 个拉伸重复样，代表曲线来自 {tensileBatchResult.representative_filename}，模板工作簿已生成并载入当前工作台。
              </div>
              <div className="summary-grid">
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
            </>
          )}

          {wizard.step === "file" && (
            <div className="step-block">
              <div className="focus-panel">
                <strong>拖文件或直接打开</strong>
                <span>支持 CSV、TSV、TXT、XLSX、XLSM。程序会先做结构识别，再给出推荐。</span>
              </div>
              <div className="focus-panel">
                <strong>原始拉伸重复样也可以直接整理</strong>
                <span>一次选择多份仪器导出的拉伸 CSV，程序会自动提取强度/模量/断裂伸长率，计算均值，并找出最接近均值的代表曲线，再导出成绘图精灵可直接读取的模板工作簿。</span>
              </div>
              <div className="step-actions">
                <button className="primary-button" onClick={openDataFile} type="button">
                  打开数据文件
                </button>
                <button className="ghost-button" onClick={() => void runTensileReplicatePreprocess()} type="button">
                  整理拉伸重复 CSV
                </button>
                <button className="ghost-button" onClick={openWizardProject} type="button">
                  打开已有项目
                </button>
              </div>
              {!wizard.sidecarReady && (
                <div className="warning-card">Python sidecar 当前未连通，识别与预览会在连接恢复后继续正常工作。</div>
              )}
            </div>
          )}

          {wizard.step === "sheet" && (
            <div className="step-block">
              <label>
                <span className="field-label">当前文件包含多个工作表</span>
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
            </div>
          )}

          {wizard.step === "inspect" && wizard.inspection && (
            <div className="step-block">
              <div className="info-grid">
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
                <strong>程序判断</strong>
                <span>{wizard.inspection.recommendation.reason}</span>
              </div>
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
              <div className="step-actions">
                {wizard.sheetNames.length > 1 && (
                  <button className="ghost-button" onClick={() => wizard.setStep("sheet")} type="button">
                    改 sheet
                  </button>
                )}
                <button className="ghost-button" onClick={() => wizard.setStep("template")} type="button">
                  改图型
                </button>
                <button className="primary-button" onClick={() => wizard.setStep("options")} type="button">
                  采用推荐
                </button>
              </div>
            </div>
          )}

          {wizard.step === "template" && (
            <div className="step-block">
              {templateOptions.length === 0 ? (
                <div className="placeholder-card">正在载入绘图契约，请稍候再选图型。</div>
              ) : (
                <div className="template-grid">
                  {templateOptions.map((template) => (
                    <button
                      className={`template-tile ${wizard.template === template.id ? "active" : ""}`}
                      key={template.id}
                      onClick={() => updateWizardTemplate(template.id)}
                      type="button"
                    >
                      <strong>{template.label}</strong>
                      <span>{template.id}</span>
                    </button>
                  ))}
                </div>
              )}
              <div className="step-actions">
                <button className="ghost-button" onClick={() => wizard.setStep("inspect")} type="button">
                  返回推荐
                </button>
                <button className="primary-button" onClick={() => wizard.setStep("options")} type="button">
                  用这个图型继续
                </button>
              </div>
            </div>
          )}

          {wizard.step === "options" && wizard.template && (
            <div className="step-block">
              <div className="field-grid">
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
                  <>
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
                  </>
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
                      checked={Boolean(wizard.options.show_colorbar ?? true)}
                      onChange={(event) =>
                        updateWizardOptions({ show_colorbar: event.target.checked })
                      }
                      type="checkbox"
                    />
                    <span>显示 colorbar</span>
                  </label>
                )}
              </div>

              <details>
                <summary>高级选项</summary>
                <div className="field-grid compact-grid advanced-grid">
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

              <div className="step-actions">
                <button className="ghost-button" onClick={() => wizard.setStep("template")} type="button">
                  返回图型
                </button>
                <button className="primary-button" onClick={() => void runPreflight()} type="button">
                  继续检查
                </button>
              </div>
            </div>
          )}

          {wizard.step === "preflight" && wizard.preflight && (
            <div className="step-block">
              {wizard.preflight.errors.length > 0 ? (
                <div className="error-card">
                  <strong>当前还不能直接导出：</strong>
                  <ul className="bullet-list">
                    {wizard.preflight.errors.map((item) => (
                      <li key={item}>{item}</li>
                    ))}
                  </ul>
                </div>
              ) : (
                <div className="success-card">当前预检查通过，可以直接导出。</div>
              )}

              {wizard.preflight.warnings.length > 0 && (
                <details>
                  <summary>展开查看需要留意的问题</summary>
                  <ul className="bullet-list">
                    {wizard.preflight.warnings.map((item) => (
                      <li key={item}>{item}</li>
                    ))}
                  </ul>
                </details>
              )}

              <div className="step-actions">
                <button className="ghost-button" onClick={() => wizard.setStep("options")} type="button">
                  返回修改参数
                </button>
                <button
                  className="primary-button"
                  disabled={wizard.preflight.errors.length > 0}
                  onClick={() => void runExport()}
                  type="button"
                >
                  导出 PDF
                </button>
              </div>
            </div>
          )}

          {wizard.step === "export" && (
            <div className="step-block">
              <div className="success-card">当前参数已完成导出，结果路径保留在下方卡片里。</div>
              <div className="step-actions">
                <button className="ghost-button" onClick={() => void saveWizardProject()} type="button">
                  保存项目
                </button>
                <button className="ghost-button" onClick={() => wizard.setStep("options")} type="button">
                  改参数重画
                </button>
                <button className="primary-button" onClick={openDataFile} type="button">
                  换文件
                </button>
              </div>
            </div>
          )}
        </article>

        {wizard.inspection && recommendation && (
          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">推荐理由卡片</div>
                <h2>{templateLabel(meta, recommendation.template)}</h2>
                <p>{recommendation.reason}</p>
              </div>
            </div>
            <div className="info-grid">
              <div className="stat-tile">
                <span>识别模型</span>
                <strong>{wizard.inspection.model_label}</strong>
              </div>
              <div className="stat-tile">
                <span>建议尺寸</span>
                <strong>{recommendation.size ?? meta?.templates.find((item) => item.id === recommendation.template)?.default_size ?? "60x55"}</strong>
              </div>
              <div className="stat-tile">
                <span>建议 X / Y</span>
                <strong>
                  {(recommendation.xscale ?? "linear").toUpperCase()} / {(recommendation.yscale ?? "linear").toUpperCase()}
                </strong>
              </div>
              <div className="stat-tile">
                <span>建议 sidecar</span>
                <strong>{recommendation.use_sidecar === false ? "关闭" : "自动"}</strong>
              </div>
            </div>
            {wizard.inspection.signals.length > 0 && (
              <div className="tag-cloud">
                {wizard.inspection.signals.map((item) => (
                  <span className="signal-tag" key={item}>
                    {item}
                  </span>
                ))}
              </div>
            )}
          </article>
        )}

        {wizard.preflight && (
          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">Preflight 卡片</div>
                <h2>
                  {wizard.preflight.errors.length > 0 ? "还需要处理问题" : "检查通过"}
                </h2>
                <p>把预检结果固定在工作区里，不用来回切回前一步确认状态。</p>
              </div>
            </div>
            <div className="info-grid">
              <div className={`stat-tile ${wizard.preflight.errors.length > 0 ? "warn-tile" : "good-tile"}`}>
                <span>错误</span>
                <strong>{wizard.preflight.errors.length}</strong>
              </div>
              <div className="stat-tile">
                <span>警告</span>
                <strong>{wizard.preflight.warnings.length}</strong>
              </div>
            </div>
            {wizard.preflight.warnings.length > 0 && (
              <ul className="bullet-list">
                {wizard.preflight.warnings.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            )}
          </article>
        )}

        {wizard.outputs.length > 0 && (
          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">导出结果卡片</div>
                <h2>已经生成 {wizard.outputs.length} 个文件</h2>
                <p>这里保留结果路径，方便你确认产物命名、保存项目或继续二次调整。</p>
              </div>
            </div>
            <ul className="output-list">
              {wizard.outputs.map((output) => (
                <li key={output}>{output}</li>
              ))}
            </ul>
          </article>
        )}
      </section>

      <aside className="desk-context">
        <PreviewPane
          busy={previewBusy || wizard.busy}
          error={previewError}
          onChangeIndex={wizard.setPreviewIndex}
          previewIndex={wizard.previewIndex}
          previews={wizard.previews}
        />

        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>当前上下文</h3>
              <p>把文件、sheet、图型和导出状态压成一眼能扫到的信息。</p>
            </div>
          </div>
          <div className="context-list">
            <div className="context-row">
              <span>文件</span>
              <strong>{wizard.inputPath ? formatLeaf(wizard.inputPath) : "未选择"}</strong>
            </div>
            <div className="context-row">
              <span>Sheet</span>
              <strong>{wizard.sheetNames.length > 0 ? String(wizard.sheet) : "-"}</strong>
            </div>
            <div className="context-row">
              <span>推荐图型</span>
              <strong>{recommendation ? templateLabel(meta, recommendation.template) : "-"}</strong>
            </div>
            <div className="context-row">
              <span>预览数</span>
              <strong>{wizard.previews.length}</strong>
            </div>
            <div className="context-row">
              <span>导出数</span>
              <strong>{wizard.outputs.length}</strong>
            </div>
          </div>
        </article>

        {wizard.inspection && wizard.inspection.warnings.length > 0 && (
          <article className="context-card warn-card">
            <div className="context-card-head">
              <div>
                <h3>输入提醒</h3>
                <p>这些提醒不会阻断流程，但值得在导出前看一眼。</p>
              </div>
            </div>
            <ul className="bullet-list">
              {wizard.inspection.warnings.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </article>
        )}
      </aside>
    </div>
  );
}
