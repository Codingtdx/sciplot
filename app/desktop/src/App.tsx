import { useEffect, useRef, useState } from "react";
import { open, save } from "@tauri-apps/plugin-dialog";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";

import { ComposerCanvas } from "./components/ComposerCanvas";
import { PreviewPane } from "./components/PreviewPane";
import {
  composeExport,
  composePreview,
  exportRender,
  healthcheck,
  importComposerPanels,
  inspectFile,
  openProject,
  panelThumbnail,
  preflightRender,
  renderPreview,
  saveProject,
  threeUp,
  twoUpEditorial,
} from "./lib/api";
import { useComposerStore, useWizardStore } from "./lib/store";
import type {
  ComposerPanel,
  ComposerProject,
  PalettePreset,
  SizePreset,
  TemplateName,
  WizardProject,
  WizardStep,
} from "./lib/types";

type AppMode = "wizard" | "composer" | "projects" | "settings";

const NAV_ITEMS: Array<{
  id: AppMode;
  label: string;
  icon: string;
}> = [
  { id: "wizard", label: "绘图", icon: "WZ" },
  { id: "composer", label: "拼图", icon: "CP" },
  { id: "projects", label: "项目", icon: "PJ" },
  { id: "settings", label: "设置", icon: "ST" },
];

const SCREEN_META: Record<
  AppMode,
  {
    eyebrow: string;
    title: string;
    description: string;
  }
> = {
  wizard: {
    eyebrow: "Plot Wizard",
    title: "绘图精灵工作台",
    description: "把选文件、识别、调参、预检和导出收束成清楚的单步卡片流。",
  },
  composer: {
    eyebrow: "Composer",
    title: "拼图器工作台",
    description: "让画布成为主舞台，把图层、属性和对齐信息放回右侧上下文面板。",
  },
  projects: {
    eyebrow: "Projects",
    title: "项目总览",
    description: "从这里看当前会话的绘图和拼图进度，再决定回到哪条工作流继续推进。",
  },
  settings: {
    eyebrow: "Workbench",
    title: "设置与运行状态",
    description: "展示 sidecar、画布约定和 4.x 工作台的当前行为，不把不成熟的开关硬塞进界面。",
  },
};

const STEPS: Array<{
  id: WizardStep;
  label: string;
  hint: string;
}> = [
  { id: "file", label: "文件", hint: "选输入" },
  { id: "sheet", label: "Sheet", hint: "选工作表" },
  { id: "inspect", label: "识别", hint: "看推荐" },
  { id: "template", label: "图型", hint: "必要时改" },
  { id: "options", label: "参数", hint: "只调关键项" },
  { id: "preflight", label: "检查", hint: "拦截风险" },
  { id: "export", label: "导出", hint: "拿结果" },
];

const STEP_COPY: Record<
  WizardStep,
  {
    title: string;
    description: string;
  }
> = {
  file: {
    title: "先把输入数据放进来",
    description: "文件进来后会先做结构识别，再给出最可能正确的图型和参数建议。",
  },
  sheet: {
    title: "确认当前使用的工作表",
    description: "多 sheet 文件先选对目标页，后面的识别、推荐和预览才有意义。",
  },
  inspect: {
    title: "看程序为什么这样判断",
    description: "这里不是黑箱推荐，而是把推断理由、模型标签和信号都摊开给你看。",
  },
  template: {
    title: "必要时改图型，不强迫一步到底",
    description: "推荐大多数时候会对，但如果你知道业务语义不一样，可以在这里改。",
  },
  options: {
    title: "只暴露真正值得你决定的参数",
    description: "先调尺寸、坐标和关键开关，把低频选项留在收起区域里。",
  },
  preflight: {
    title: "先预检，再决定要不要导出",
    description: "让错误在导出前暴露，避免白跑一轮渲染或生成不可靠结果。",
  },
  export: {
    title: "结果已经产出",
    description: "这里保留导出路径和后续动作，你可以存项目、回去改参数，或者直接换文件继续。",
  },
};

const TEMPLATE_LABELS: Record<TemplateName, string> = {
  curve: "曲线",
  point_line: "点线",
  stacked_curve: "堆叠曲线",
  segmented_stacked_curve: "分段堆叠曲线",
  bar: "柱状",
  box: "箱线",
  violin: "小提琴",
  scatter: "散点",
  heatmap: "热图",
};

const PALETTE_LABELS: Record<PalettePreset, string> = {
  colorblind_safe: "Colorblind Safe",
  deep: "Deep",
  muted: "Muted",
  mono: "Mono",
};

const paletteChoices: PalettePreset[] = ["colorblind_safe", "deep", "muted", "mono"];
const templateChoices: TemplateName[] = [
  "curve",
  "point_line",
  "stacked_curve",
  "segmented_stacked_curve",
  "bar",
  "box",
  "violin",
  "scatter",
  "heatmap",
];
const sizeChoices: SizePreset[] = ["60x55", "120x55", "60x110"];

const EMPTY_COMPOSER_PROJECT: ComposerProject = {
  version: 1,
  mode: "composer",
  canvas_width_mm: 180,
  canvas_height_mm: 170,
  grid_mm: 0.5,
  panels: [],
  texts: [],
  auto_labels: true,
};

function formatLeaf(path: string) {
  return path.split(/[/\\]/).pop() ?? path;
}

function getWizardStepLabel(step: WizardStep) {
  return STEPS.find((item) => item.id === step)?.label ?? step;
}

function orderPanels(panels: ComposerPanel[]) {
  return [...panels].sort((a, b) => {
    if (Math.abs(a.y_mm - b.y_mm) > 0.25) {
      return a.y_mm - b.y_mm;
    }
    if (Math.abs(a.x_mm - b.x_mm) > 0.25) {
      return a.x_mm - b.x_mm;
    }
    return a.id.localeCompare(b.id);
  });
}

function resolveSelectedPanelLabel(project: ComposerProject, panel: ComposerPanel) {
  if (!project.auto_labels) {
    return panel.label ?? "";
  }
  const ordered = orderPanels(project.panels);
  const index = ordered.findIndex((item) => item.id === panel.id);
  return index >= 0 ? String.fromCharCode("a".charCodeAt(0) + index) : "";
}

function describePanelSlot(panel: ComposerPanel, canvasHeightMm: number) {
  if (panel.kind !== "graph") {
    return "自由素材";
  }
  const rowHeight = canvasHeightMm / 3;
  const column = Math.round(panel.x_mm / 60) + 1;
  const row = Math.round(panel.y_mm / rowHeight) + 1;
  return `C${column} / R${row}`;
}

function normalizeComposerProject(project: ComposerProject): ComposerProject {
  return {
    ...EMPTY_COMPOSER_PROJECT,
    ...project,
    panels: (project.panels ?? []).map((panel) => ({
      ...panel,
      kind: panel.kind ?? "graph",
    })),
    texts: project.texts ?? [],
    auto_labels: project.auto_labels ?? true,
  };
}

function StepFlow({ current }: { current: WizardStep }) {
  const currentIndex = STEPS.findIndex((step) => step.id === current);

  return (
    <div className="flow-strip">
      {STEPS.map((step, index) => {
        const status =
          index < currentIndex ? "complete" : index === currentIndex ? "current" : "upcoming";
        return (
          <div className={`flow-step ${status}`} key={step.id}>
            <span className="flow-step-index">{String(index + 1).padStart(2, "0")}</span>
            <div className="flow-step-body">
              <strong>{step.label}</strong>
              <span>{step.hint}</span>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function WizardPane() {
  const wizard = useWizardStore();
  const [previewBusy, setPreviewBusy] = useState(false);
  const [previewError, setPreviewError] = useState<string | null>(null);

  const stepMeta = STEP_COPY[wizard.step];
  const recommendation = wizard.inspection?.recommendation ?? null;

  const invalidateRenderState = () => {
    wizard.setPreflight(null);
    wizard.setOutputs([]);
  };

  const updateWizardTemplate = (value: TemplateName) => {
    invalidateRenderState();
    wizard.setTemplate(value);
  };

  const updateWizardOptions = (value: Parameters<typeof wizard.setOptions>[0]) => {
    invalidateRenderState();
    wizard.setOptions(value);
  };

  useEffect(() => {
    if (!wizard.inputPath || !wizard.template) {
      setPreviewBusy(false);
      setPreviewError(null);
      wizard.setPreviews([]);
      return;
    }

    let cancelled = false;
    const handle = window.setTimeout(async () => {
      setPreviewBusy(true);
      setPreviewError(null);
      try {
        const payload = await renderPreview(
          wizard.inputPath,
          wizard.sheet,
          wizard.template,
          wizard.options,
        );
        if (!cancelled) {
          wizard.setPreviews(payload.previews);
        }
      } catch (error) {
        if (!cancelled) {
          setPreviewError(error instanceof Error ? error.message : String(error));
          wizard.setPreviews([]);
        }
      } finally {
        if (!cancelled) {
          setPreviewBusy(false);
        }
      }
    }, 220);

    return () => {
      cancelled = true;
      window.clearTimeout(handle);
    };
  }, [wizard.inputPath, wizard.options, wizard.sheet, wizard.template]);

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
    if (typeof selected !== "string") {
      return;
    }

    wizard.reset();
    wizard.setError(null);
    wizard.setInputPath(selected);
    wizard.setStep("file");
    try {
      const inspected = await inspectFile(selected, 0);
      wizard.setInputPath(inspected.input_path);
      wizard.setSheet(inspected.sheet);
      wizard.setSheetNames(inspected.sheet_names);
      wizard.setInspection(inspected.inspection);
      wizard.setTemplate(inspected.inspection.recommendation.template);
      wizard.setOptions({
        size: inspected.inspection.recommendation.size,
        xscale: inspected.inspection.recommendation.xscale,
        yscale: inspected.inspection.recommendation.yscale,
        reverse_x: inspected.inspection.recommendation.reverse_x,
        baseline: inspected.inspection.recommendation.baseline,
        show_colorbar: inspected.inspection.recommendation.show_colorbar,
        use_sidecar: inspected.inspection.recommendation.use_sidecar,
      });
      wizard.setStep(inspected.sheet_names.length > 1 ? "sheet" : "inspect");
    } catch (error) {
      wizard.setError(error instanceof Error ? error.message : String(error));
    }
  };

  const openWizardProject = async () => {
    const selected = await open({
      multiple: false,
      filters: [{ name: "CodeGod Project", extensions: ["json"] }],
    });
    if (typeof selected !== "string") {
      return;
    }

    wizard.reset();
    wizard.setError(null);
    wizard.setBusy(true);
    try {
      const payload = (await openProject(selected)) as WizardProject;
      if (!payload || payload.mode !== "wizard") {
        throw new Error("这不是可识别的绘图精灵项目文件。");
      }
      const { input_path, options, outputs, sheet, template } = payload.wizard;
      const inspected = await inspectFile(input_path, sheet);
      wizard.setInputPath(inspected.input_path);
      wizard.setSheet(inspected.sheet);
      wizard.setSheetNames(inspected.sheet_names);
      wizard.setInspection(inspected.inspection);
      wizard.setTemplate(template ?? inspected.inspection.recommendation.template);
      wizard.setOptions({
        size: inspected.inspection.recommendation.size,
        xscale: inspected.inspection.recommendation.xscale,
        yscale: inspected.inspection.recommendation.yscale,
        reverse_x: inspected.inspection.recommendation.reverse_x,
        baseline: inspected.inspection.recommendation.baseline,
        show_colorbar: inspected.inspection.recommendation.show_colorbar,
        use_sidecar: inspected.inspection.recommendation.use_sidecar,
        ...options,
      });
      wizard.setOutputs(outputs ?? []);
      wizard.setStep(outputs && outputs.length > 0 ? "export" : "options");
    } catch (error) {
      wizard.setError(error instanceof Error ? error.message : String(error));
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
    await saveProject(destination, payload);
  };

  const rerunInspect = async (sheetValue: string | number) => {
    if (!wizard.inputPath) {
      return;
    }

    wizard.setError(null);
    wizard.setBusy(true);
    try {
      const inspected = await inspectFile(wizard.inputPath, sheetValue);
      wizard.setSheet(inspected.sheet);
      wizard.setSheetNames(inspected.sheet_names);
      wizard.setInspection(inspected.inspection);
      wizard.setTemplate(inspected.inspection.recommendation.template);
      wizard.setOptions({
        size: inspected.inspection.recommendation.size,
        xscale: inspected.inspection.recommendation.xscale,
        yscale: inspected.inspection.recommendation.yscale,
        reverse_x: inspected.inspection.recommendation.reverse_x,
        baseline: inspected.inspection.recommendation.baseline,
        show_colorbar: inspected.inspection.recommendation.show_colorbar,
        use_sidecar: inspected.inspection.recommendation.use_sidecar,
      });
      invalidateRenderState();
      wizard.setStep("inspect");
    } catch (error) {
      wizard.setError(error instanceof Error ? error.message : String(error));
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
      wizard.setError(error instanceof Error ? error.message : String(error));
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
      wizard.setError(error instanceof Error ? error.message : String(error));
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

          {wizard.step === "file" && (
            <div className="step-block">
              <div className="focus-panel">
                <strong>拖文件或直接打开</strong>
                <span>支持 CSV、TSV、TXT、XLSX、XLSM。程序会先做结构识别，再给出推荐。</span>
              </div>
              <div className="step-actions">
                <button className="primary-button" onClick={openDataFile} type="button">
                  打开数据文件
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
                  <strong>{TEMPLATE_LABELS[wizard.inspection.recommendation.template]}</strong>
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
              <div className="template-grid">
                {templateChoices.map((template) => (
                  <button
                    className={`template-tile ${wizard.template === template ? "active" : ""}`}
                    key={template}
                    onClick={() => updateWizardTemplate(template)}
                    type="button"
                  >
                    <strong>{TEMPLATE_LABELS[template]}</strong>
                    <span>{template}</span>
                  </button>
                ))}
              </div>
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
                    value={wizard.options.size ?? "60x55"}
                    onChange={(event) =>
                      updateWizardOptions({ size: event.target.value as SizePreset })
                    }
                  >
                    {sizeChoices.map((choice) => (
                      <option key={choice} value={choice}>
                        {choice}
                      </option>
                    ))}
                  </select>
                </label>

                {["curve", "point_line", "scatter"].includes(wizard.template) && (
                  <>
                    <label>
                      <span className="field-label">X 轴</span>
                      <select
                        className="field"
                        value={wizard.options.xscale ?? "linear"}
                        onChange={(event) =>
                          updateWizardOptions({
                            xscale: event.target.value as "linear" | "log",
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
                            yscale: event.target.value as "linear" | "log",
                          })
                        }
                      >
                        <option value="linear">linear</option>
                        <option value="log">log</option>
                      </select>
                    </label>
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
                  </>
                )}

                {["stacked_curve", "segmented_stacked_curve"].includes(wizard.template) && (
                  <>
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
                    <label>
                      <span className="field-label">Baseline</span>
                      <select
                        className="field"
                        value={wizard.options.baseline ?? "none"}
                        onChange={(event) =>
                          updateWizardOptions({
                            baseline: event.target.value as "none" | "linear_endpoints",
                          })
                        }
                      >
                        <option value="none">none</option>
                        <option value="linear_endpoints">linear_endpoints</option>
                      </select>
                    </label>
                  </>
                )}

                {wizard.template === "heatmap" && (
                  <label className="toggle-field">
                    <input
                      checked={Boolean(wizard.options.show_colorbar)}
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
                      value={wizard.options.palette_preset ?? "colorblind_safe"}
                      onChange={(event) =>
                        updateWizardOptions({
                          palette_preset: event.target.value as PalettePreset,
                        })
                      }
                    >
                      {paletteChoices.map((choice) => (
                        <option key={choice} value={choice}>
                          {PALETTE_LABELS[choice]}
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
                <h2>{TEMPLATE_LABELS[recommendation.template]}</h2>
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
                <strong>{recommendation.size ?? "60x55"}</strong>
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
              <strong>{recommendation ? TEMPLATE_LABELS[recommendation.template] : "-"}</strong>
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

function ComposerPane() {
  const composer = useComposerStore();
  const [thumbnailMap, setThumbnailMap] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [exportPath, setExportPath] = useState<string | null>(null);
  const [dropActive, setDropActive] = useState(false);
  const [dropNotice, setDropNotice] = useState<string | null>(null);
  const [pdfImportMode, setPdfImportMode] = useState<"graph" | "asset">("graph");
  const projectRef = useRef(composer.project);

  const selectedPanel = composer.project.panels.find((item) => item.id === composer.selectedId) ?? null;
  const selectedText = composer.project.texts.find((item) => item.id === composer.selectedId) ?? null;
  const selectedPanelLabel = selectedPanel
    ? resolveSelectedPanelLabel(composer.project, selectedPanel)
    : "";

  const orderedPanels = orderPanels(composer.project.panels);
  const layerItems = [
    ...orderedPanels.map((panel) => ({
      id: panel.id,
      title:
        panel.kind === "graph"
          ? `图 ${resolveSelectedPanelLabel(composer.project, panel) || panel.id}`
          : panel.label || formatLeaf(panel.file_path),
      detail:
        panel.kind === "graph"
          ? `Graph · ${describePanelSlot(panel, composer.project.canvas_height_mm)}`
          : `Asset · ${panel.w_mm.toFixed(1)} x ${panel.h_mm.toFixed(1)} mm`,
    })),
    ...composer.project.texts.map((text) => ({
      id: text.id,
      title: text.text || "Text",
      detail: `Text · ${text.font_size_pt} pt`,
    })),
  ];

  useEffect(() => {
    projectRef.current = composer.project;
  }, [composer.project]);

  useEffect(() => {
    setExportPath(null);
  }, [composer.project]);

  useEffect(() => {
    let cancelled = false;

    async function refreshPreview() {
      try {
        const response = await composePreview(composer.project);
        if (!cancelled) {
          composer.setPreview(response.png_base64, response.validation_error ?? null);
        }
      } catch (error) {
        if (!cancelled) {
          composer.setPreview(null, error instanceof Error ? error.message : String(error));
        }
      }
    }

    void refreshPreview();

    return () => {
      cancelled = true;
    };
  }, [composer.project]);

  useEffect(() => {
    let cancelled = false;

    async function loadThumbs() {
      const next: Record<string, string> = {};
      for (const panel of composer.project.panels) {
        try {
          next[panel.id] = `data:image/png;base64,${await panelThumbnail(panel.file_path, panel.page_index)}`;
        } catch {
          continue;
        }
      }
      if (!cancelled) {
        setThumbnailMap(next);
      }
    }

    void loadThumbs();

    return () => {
      cancelled = true;
    };
  }, [composer.project.panels]);

  useEffect(() => {
    let disposed = false;
    let unlisten: (() => void) | undefined;

    async function handleDroppedPaths(paths: string[]) {
      const cleaned = paths.filter(Boolean);
      if (cleaned.length === 0) {
        return;
      }

      const pdfs = cleaned.filter((path) => path.toLowerCase().endsWith(".pdf"));
      const assets = cleaned.filter((path) => !path.toLowerCase().endsWith(".pdf"));

      setBusy(true);
      setDropNotice(null);
      try {
        let nextProject = projectRef.current;
        if (pdfs.length > 0) {
          const response = await importComposerPanels(nextProject, pdfs, pdfImportMode);
          nextProject = {
            ...nextProject,
            panels: response.panels,
          };
        }
        if (assets.length > 0) {
          const response = await importComposerPanels(nextProject, assets, "asset");
          nextProject = {
            ...nextProject,
            panels: response.panels,
          };
        }

        composer.setProject(nextProject);
        composer.setSelectedId(null);

        const unsupported = cleaned.length - pdfs.length - assets.length;
        if (unsupported > 0) {
          setDropNotice("部分文件格式未导入。PDF 会按当前模式导入，图片会作为素材导入。");
        } else if (pdfs.length > 0 && assets.length > 0) {
          setDropNotice(
            pdfImportMode === "graph"
              ? "已导入图 panel 和素材。PDF 已自动吸附到网格。"
              : "已导入 PDF 素材和图片素材。素材可以继续拖拽、缩放和对齐。",
          );
        } else if (pdfs.length > 0) {
          setDropNotice(
            pdfImportMode === "graph"
              ? "已导入图 panel。PDF 已自动吸附到 3x3 网格。"
              : "已导入 PDF 素材。可以继续拖拽、缩放和对齐。",
          );
        } else {
          setDropNotice("已导入素材。可以继续拖拽、缩放和对齐。");
        }
      } catch (error) {
        setDropNotice(error instanceof Error ? error.message : String(error));
      } finally {
        setBusy(false);
      }
    }

    async function attach() {
      const webview = getCurrentWebviewWindow();
      unlisten = await webview.onDragDropEvent((event) => {
        if (disposed) {
          return;
        }
        if (event.payload.type === "enter") {
          setDropActive(true);
          return;
        }
        if (event.payload.type === "leave") {
          setDropActive(false);
          return;
        }
        if (event.payload.type === "drop") {
          setDropActive(false);
          void handleDroppedPaths(event.payload.paths);
        }
      });
    }

    void attach();

    return () => {
      disposed = true;
      setDropActive(false);
      void unlisten?.();
    };
  }, [pdfImportMode]);

  const importGraphPanels = async () => {
    const selected = await open({
      multiple: true,
      filters: [{ name: "PDF", extensions: ["pdf"] }],
    });
    const paths = Array.isArray(selected)
      ? selected.filter((item): item is string => typeof item === "string")
      : [];
    if (paths.length === 0) {
      return;
    }

    setBusy(true);
    setDropNotice(null);
    try {
      const response = await importComposerPanels(composer.project, paths, "graph");
      composer.setProject({
        ...composer.project,
        panels: response.panels,
      });
      composer.setSelectedId(null);
    } finally {
      setBusy(false);
    }
  };

  const importAssetPanels = async () => {
    const selected = await open({
      multiple: true,
      filters: [
        {
          name: "Visual Assets",
          extensions: ["pdf", "png", "jpg", "jpeg", "webp", "bmp", "tif", "tiff"],
        },
      ],
    });
    const paths = Array.isArray(selected)
      ? selected.filter((item): item is string => typeof item === "string")
      : [];
    if (paths.length === 0) {
      return;
    }

    setBusy(true);
    setDropNotice(null);
    try {
      const response = await importComposerPanels(composer.project, paths, "asset");
      composer.setProject({
        ...composer.project,
        panels: response.panels,
      });
      composer.setSelectedId(null);
    } finally {
      setBusy(false);
    }
  };

  const quickThreeUp = async () => {
    const selected = await open({
      multiple: true,
      filters: [{ name: "PDF", extensions: ["pdf"] }],
    });
    const paths = Array.isArray(selected)
      ? selected
          .filter((item): item is string => typeof item === "string")
          .slice(0, 3)
      : [];
    if (paths.length === 0) {
      return;
    }

    setBusy(true);
    setDropNotice(null);
    try {
      const response = await threeUp(paths);
      composer.setProject({
        ...composer.project,
        panels: response.panels,
        texts: [],
      });
      composer.setSelectedId(null);
      setDropNotice("已按 180 mm 画布生成三联图排版。");
    } catch (error) {
      setDropNotice(error instanceof Error ? error.message : String(error));
    } finally {
      setBusy(false);
    }
  };

  const quickTwoUpEditorial = async () => {
    const selected = await open({
      multiple: true,
      filters: [{ name: "PDF", extensions: ["pdf"] }],
    });
    const paths = Array.isArray(selected)
      ? selected
          .filter((item): item is string => typeof item === "string")
          .slice(0, 2)
      : [];
    if (paths.length === 0) {
      return;
    }

    setBusy(true);
    setDropNotice(null);
    try {
      const response = await twoUpEditorial(paths);
      composer.setProject({
        ...composer.project,
        panels: response.panels,
        texts: [],
      });
      composer.setSelectedId(null);
      setDropNotice("已按 180 mm 画布生成两图 + 说明区排版。");
    } catch (error) {
      setDropNotice(error instanceof Error ? error.message : String(error));
    } finally {
      setBusy(false);
    }
  };

  const addText = () => {
    composer.updateTexts([
      ...composer.project.texts,
      {
        id: `text-${Date.now()}`,
        text: "Text",
        x_mm: 8,
        y_mm: 8,
        font_size_pt: 8,
        align: "left",
      },
    ]);
  };

  const updateSelectedPanel = (patch: Partial<ComposerProject["panels"][number]>) => {
    if (!selectedPanel) {
      return;
    }
    composer.updatePanels(
      composer.project.panels.map((item) =>
        item.id === selectedPanel.id
          ? {
              ...item,
              ...patch,
            }
          : item,
      ),
    );
  };

  const updateSelectedText = (patch: Partial<ComposerProject["texts"][number]>) => {
    if (!selectedText) {
      return;
    }
    composer.updateTexts(
      composer.project.texts.map((item) =>
        item.id === selectedText.id
          ? {
              ...item,
              ...patch,
            }
          : item,
      ),
    );
  };

  const removeSelected = () => {
    if (selectedPanel) {
      composer.updatePanels(composer.project.panels.filter((item) => item.id !== selectedPanel.id));
      composer.setSelectedId(null);
      return;
    }
    if (selectedText) {
      composer.updateTexts(composer.project.texts.filter((item) => item.id !== selectedText.id));
      composer.setSelectedId(null);
    }
  };

  const saveComposerProject = async () => {
    const destination = await save({
      defaultPath: "codegod-composer.plotproject.json",
      filters: [{ name: "CodeGod Project", extensions: ["json"] }],
    });
    if (typeof destination !== "string") {
      return;
    }

    await saveProject(destination, {
      version: 1,
      mode: "composer",
      project: composer.project,
    });
  };

  const openComposerProject = async () => {
    const selected = await open({
      multiple: false,
      filters: [{ name: "CodeGod Project", extensions: ["json"] }],
    });
    if (typeof selected !== "string") {
      return;
    }

    const payload = (await openProject(selected)) as
      | { version?: number; mode?: string; project?: ComposerProject }
      | ComposerProject;
    const project =
      "project" in payload && payload.project ? payload.project : (payload as ComposerProject);
    composer.setProject(normalizeComposerProject(project));
    composer.setSelectedId(null);
    setDropNotice("项目已加载，可以继续调整拼图。");
  };

  const exportComposer = async () => {
    setBusy(true);
    setDropNotice(null);
    try {
      const response = await composeExport(composer.project);
      setExportPath(response.output_path);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="desk-layout">
      <section className="desk-main">
        <article className="work-card canvas-shell-card">
          <div className="section-head">
            <div>
              <div className="card-kicker">Canvas Workspace</div>
              <h2>画布是主角，操作条只保留高频动作</h2>
              <p>导入、快速排版和导出放到画布上方，低频设置和对象细节交给右侧上下文面板。</p>
            </div>
            <div className="metric-strip">
              <div className="metric-chip">
                <span>画布</span>
                <strong>
                  {composer.project.canvas_width_mm} x {composer.project.canvas_height_mm} mm
                </strong>
              </div>
              <div className="metric-chip">
                <span>对象</span>
                <strong>
                  {composer.project.panels.length} / {composer.project.texts.length}
                </strong>
              </div>
            </div>
          </div>

          <div className="canvas-toolbar">
            <button className="primary-button" onClick={importGraphPanels} type="button">
              导入图
            </button>
            <button className="ghost-button" onClick={importAssetPanels} type="button">
              导入素材
            </button>
            <button className="ghost-button" onClick={quickThreeUp} type="button">
              三联图
            </button>
            <button className="ghost-button" onClick={exportComposer} type="button">
              导出总图
            </button>
          </div>

          <div className="composer-main">
            <div className={`composer-drop-overlay ${dropActive ? "visible" : ""}`}>
              <div className="composer-drop-card">
                <strong>松开即可导入</strong>
                <span>
                  {pdfImportMode === "graph"
                    ? "PDF 会作为图 panel 吸附到 3x3 网格，图片会作为素材导入。"
                    : "PDF 和图片都会作为素材导入，可拖拽、缩放并吸附到网格。"}
                </span>
              </div>
            </div>

            <ComposerCanvas
              autoLabels={composer.project.auto_labels}
              heightMm={composer.project.canvas_height_mm}
              onPanelsChange={composer.updatePanels}
              onTextsChange={composer.updateTexts}
              onSelect={composer.setSelectedId}
              panels={composer.project.panels}
              selectedId={composer.selectedId}
              texts={composer.project.texts}
              thumbnails={thumbnailMap}
              widthMm={composer.project.canvas_width_mm}
            />

            {composer.project.panels.length === 0 && !busy && (
              <div className="composer-empty-state">
                <strong>先拖入图或素材开始拼图</strong>
                <span>
                  {pdfImportMode === "graph"
                    ? "图 panel 会自动吸附到 3x3 网格；素材可自由缩放与移动。"
                    : "当前模式会把 PDF 当作素材导入；素材可自由缩放、移动并自动避让。"}
                </span>
              </div>
            )}

            {busy && <div className="composer-status">正在更新…</div>}
          </div>
        </article>
      </section>

      <aside className="desk-context">
        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>拼图动作</h3>
              <p>把模式、项目操作和低频动作放在这里，不挤占主画布。</p>
            </div>
          </div>

          <div className="mode-switch">
            <button
              className={`mode-button ${pdfImportMode === "graph" ? "active" : ""}`}
              onClick={() => setPdfImportMode("graph")}
              type="button"
            >
              PDF 作为图
            </button>
            <button
              className={`mode-button ${pdfImportMode === "asset" ? "active" : ""}`}
              onClick={() => setPdfImportMode("asset")}
              type="button"
            >
              PDF 作为素材
            </button>
          </div>

          <div className="stacked-actions">
            <button className="ghost-button" onClick={quickTwoUpEditorial} type="button">
              两图 + 说明区
            </button>
            <button className="ghost-button" onClick={addText} type="button">
              添加文字
            </button>
            <button className="ghost-button" onClick={openComposerProject} type="button">
              打开项目
            </button>
            <button className="ghost-button" onClick={saveComposerProject} type="button">
              保存项目
            </button>
          </div>

          <label className="toggle-field">
            <input
              checked={composer.project.auto_labels}
              onChange={(event) =>
                composer.setProject({
                  ...composer.project,
                  auto_labels: event.target.checked,
                })
              }
              type="checkbox"
            />
            <span>自动 a/b/c 编号</span>
          </label>
        </article>

        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>{selectedPanel || selectedText ? "对象属性" : "对象属性"}</h3>
              <p>
                {selectedPanel || selectedText
                  ? "当前选中对象的关键信息和可编辑项。"
                  : "先在画布里选中一个 panel 或文字，这里会切成对应属性面板。"}
              </p>
            </div>
          </div>

          {!selectedPanel && !selectedText && (
            <div className="placeholder-card">还没有选中对象。先点一下画布里的 panel 或文字。</div>
          )}

          {selectedPanel && (
            <div className="inspector-stack">
              <div className="info-grid compact-grid">
                <div className="stat-tile">
                  <span>类型</span>
                  <strong>{selectedPanel.kind === "graph" ? "Graph" : "Asset"}</strong>
                </div>
                <div className="stat-tile">
                  <span>标签</span>
                  <strong>{selectedPanelLabel || "-"}</strong>
                </div>
                <div className="stat-tile">
                  <span>对齐位</span>
                  <strong>
                    {describePanelSlot(selectedPanel, composer.project.canvas_height_mm)}
                  </strong>
                </div>
                <div className="stat-tile">
                  <span>锁定</span>
                  <strong>{selectedPanel.locked ? "是" : "否"}</strong>
                </div>
              </div>

              <label>
                <span className="field-label">自定义标签</span>
                <input
                  className="field"
                  disabled={composer.project.auto_labels}
                  onChange={(event) =>
                    updateSelectedPanel({ label: event.target.value || null })
                  }
                  type="text"
                  value={selectedPanel.label ?? ""}
                />
              </label>

              <label className="toggle-field">
                <input
                  checked={Boolean(selectedPanel.locked)}
                  onChange={(event) => updateSelectedPanel({ locked: event.target.checked })}
                  type="checkbox"
                />
                <span>锁定位置</span>
              </label>

              <div className="info-grid compact-grid">
                <div className="stat-tile">
                  <span>X / mm</span>
                  <strong>{selectedPanel.x_mm.toFixed(1)}</strong>
                </div>
                <div className="stat-tile">
                  <span>Y / mm</span>
                  <strong>{selectedPanel.y_mm.toFixed(1)}</strong>
                </div>
                <div className="stat-tile">
                  <span>W / mm</span>
                  <strong>{selectedPanel.w_mm.toFixed(1)}</strong>
                </div>
                <div className="stat-tile">
                  <span>H / mm</span>
                  <strong>{selectedPanel.h_mm.toFixed(1)}</strong>
                </div>
              </div>

              <div className="hint-text">
                {selectedPanel.kind === "graph"
                  ? "Graph panel 会自动吸附到 3x3 网格，不支持手动缩放。"
                  : "Asset 可自由拖拽和缩放，但仍会自动避让其他 panel。"}
              </div>

              <button className="ghost-button danger-button" onClick={removeSelected} type="button">
                删除 panel
              </button>
            </div>
          )}

          {selectedText && (
            <div className="inspector-stack">
              <label>
                <span className="field-label">内容</span>
                <input
                  className="field"
                  onChange={(event) => updateSelectedText({ text: event.target.value })}
                  type="text"
                  value={selectedText.text}
                />
              </label>

              <label>
                <span className="field-label">字号</span>
                <input
                  className="field"
                  max={20}
                  min={5}
                  onChange={(event) =>
                    updateSelectedText({
                      font_size_pt: Number(event.target.value) || selectedText.font_size_pt,
                    })
                  }
                  type="number"
                  value={selectedText.font_size_pt}
                />
              </label>

              <label>
                <span className="field-label">对齐</span>
                <select
                  className="field"
                  onChange={(event) =>
                    updateSelectedText({
                      align: event.target.value as "left" | "center" | "right",
                    })
                  }
                  value={selectedText.align}
                >
                  <option value="left">left</option>
                  <option value="center">center</option>
                  <option value="right">right</option>
                </select>
              </label>

              <button className="ghost-button danger-button" onClick={removeSelected} type="button">
                删除文字
              </button>
            </div>
          )}
        </article>

        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>图层与对齐</h3>
              <p>右侧专门留给图层浏览和对齐信息，而不是把全部按钮塞到左边。</p>
            </div>
          </div>

          <div className="context-list">
            <div className="context-row">
              <span>网格</span>
              <strong>3 x 3</strong>
            </div>
            <div className="context-row">
              <span>自动编号</span>
              <strong>{composer.project.auto_labels ? "开启" : "关闭"}</strong>
            </div>
            <div className="context-row">
              <span>预检状态</span>
              <strong>{composer.validationError ? "有提醒" : "正常"}</strong>
            </div>
          </div>

          <div className="layer-list">
            {layerItems.length === 0 && (
              <div className="placeholder-card">还没有图层。导入 PDF 或素材后，这里会出现对象列表。</div>
            )}
            {layerItems.map((item) => (
              <button
                className={`layer-item ${composer.selectedId === item.id ? "active" : ""}`}
                key={item.id}
                onClick={() => composer.setSelectedId(item.id)}
                type="button"
              >
                <strong>{item.title}</strong>
                <span>{item.detail}</span>
              </button>
            ))}
          </div>
        </article>

        {composer.validationError && <div className="warning-card">{composer.validationError}</div>}

        {dropNotice && (
          <div className={dropNotice.includes("未导入") ? "warning-card" : "success-card"}>
            {dropNotice}
          </div>
        )}

        {exportPath && <div className="success-card">已导出：{exportPath}</div>}
      </aside>
    </div>
  );
}

function ProjectsPane({ onNavigate }: { onNavigate(mode: AppMode): void }) {
  const inputPath = useWizardStore((state) => state.inputPath);
  const wizardStep = useWizardStore((state) => state.step);
  const wizardOutputs = useWizardStore((state) => state.outputs);
  const composerProject = useComposerStore((state) => state.project);

  return (
    <div className="desk-layout">
      <section className="desk-main">
        <article className="work-card hero-card">
          <div className="section-head hero-head">
            <div>
              <div className="card-kicker">Project Overview</div>
              <h2>把两个核心工作流都收进一个项目视角</h2>
              <p>先看到当前会话里已经做到哪一步，再决定回哪一个工作台继续推进。</p>
            </div>
          </div>
        </article>

        <div className="summary-grid">
          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">绘图精灵</div>
                <h2>{inputPath ? formatLeaf(inputPath) : "还没有加载数据"}</h2>
                <p>当前步骤是 {getWizardStepLabel(wizardStep)}，导出文件数为 {wizardOutputs.length}。</p>
              </div>
            </div>
            <div className="step-actions">
              <button className="primary-button" onClick={() => onNavigate("wizard")} type="button">
                回到绘图精灵
              </button>
            </div>
          </article>

          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">拼图器</div>
                <h2>
                  {composerProject.panels.length} 个 panel / {composerProject.texts.length} 段文字
                </h2>
                <p>
                  当前画布 {composerProject.canvas_width_mm} x {composerProject.canvas_height_mm} mm，
                  自动编号 {composerProject.auto_labels ? "已开启" : "已关闭"}。
                </p>
              </div>
            </div>
            <div className="step-actions">
              <button className="primary-button" onClick={() => onNavigate("composer")} type="button">
                回到拼图器
              </button>
            </div>
          </article>
        </div>
      </section>

      <aside className="desk-context">
        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>4.x 项目观</h3>
              <p>这里先做成轻项目页，用来承接状态和跳转，不提前伪造复杂的项目管理器。</p>
            </div>
          </div>
          <ul className="bullet-list">
            <li>单图出图走绘图精灵。</li>
            <li>拼版与画布编辑走拼图器。</li>
            <li>真正的“最近项目列表”下一步可以接持久化记录。</li>
          </ul>
        </article>
      </aside>
    </div>
  );
}

function SettingsPane() {
  const sidecarReady = useWizardStore((state) => state.sidecarReady);
  const setSidecarReady = useWizardStore((state) => state.setSidecarReady);
  const composerProject = useComposerStore((state) => state.project);
  const [checking, setChecking] = useState(false);

  const refreshSidecar = async () => {
    setChecking(true);
    try {
      setSidecarReady(await healthcheck());
    } finally {
      setChecking(false);
    }
  };

  return (
    <div className="desk-layout">
      <section className="desk-main">
        <div className="summary-grid">
          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">运行状态</div>
                <h2>{sidecarReady ? "Python sidecar 已连通" : "Python sidecar 暂未连通"}</h2>
                <p>绘图精灵的识别、预检和渲染都依赖 sidecar，这里给一个明确的健康状态反馈。</p>
              </div>
            </div>
            <div className="step-actions">
              <button
                className="primary-button"
                disabled={checking}
                onClick={() => void refreshSidecar()}
                type="button"
              >
                {checking ? "检查中…" : "重新检查"}
              </button>
            </div>
          </article>

          <article className="work-card section-card">
            <div className="section-head">
              <div>
                <div className="card-kicker">画布约定</div>
                <h2>
                  {composerProject.canvas_width_mm} x {composerProject.canvas_height_mm} mm
                </h2>
                <p>当前拼图器遵循 3x3 网格和 0.5 mm 步进，这是 4.x 版桌面工作台的默认结构。</p>
              </div>
            </div>
          </article>
        </div>
      </section>

      <aside className="desk-context">
        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>当前原则</h3>
              <p>设置页先用来说明行为边界，不把还不稳定的配置项伪装成正式能力。</p>
            </div>
          </div>
          <ul className="bullet-list">
            <li>左侧保持轻导航，不承担主要操作。</li>
            <li>绘图精灵按单步卡片流推进。</li>
            <li>拼图器把对象属性、图层和对齐信息收在右侧。</li>
          </ul>
        </article>
      </aside>
    </div>
  );
}

export default function App() {
  const [mode, setMode] = useState<AppMode>("wizard");
  const sidecarReady = useWizardStore((state) => state.sidecarReady);
  const setSidecarReady = useWizardStore((state) => state.setSidecarReady);
  const wizardStep = useWizardStore((state) => state.step);
  const wizardOutputsCount = useWizardStore((state) => state.outputs.length);
  const composerPanelCount = useComposerStore((state) => state.project.panels.length);
  const composerTextCount = useComposerStore((state) => state.project.texts.length);

  useEffect(() => {
    let cancelled = false;

    async function check() {
      const ok = await healthcheck();
      if (!cancelled) {
        setSidecarReady(ok);
      }
    }

    void check();
    const intervalId = window.setInterval(() => {
      void check();
    }, 6000);

    return () => {
      cancelled = true;
      window.clearInterval(intervalId);
    };
  }, [setSidecarReady]);

  const meta = SCREEN_META[mode];

  let secondaryStatusLabel = `Step ${getWizardStepLabel(wizardStep)}`;
  if (mode === "composer") {
    secondaryStatusLabel = `${composerPanelCount} 图层 / ${composerTextCount} 文字`;
  } else if (mode === "projects") {
    secondaryStatusLabel = `${wizardOutputsCount} 个导出结果`;
  } else if (mode === "settings") {
    secondaryStatusLabel = "Workbench Rules";
  }

  return (
    <div className="dashboard-shell">
      <aside className="nav-rail">
        <div className="rail-brand">
          <div className="brand-mark">CG</div>
          <div className="rail-brand-text">
            <strong>CodeGod</strong>
            <span>4.x</span>
          </div>
        </div>

        <nav className="nav-cluster">
          {NAV_ITEMS.map((item) => (
            <button
              className={`nav-item ${mode === item.id ? "active" : ""}`}
              key={item.id}
              onClick={() => setMode(item.id)}
              type="button"
            >
              <span className="nav-item-icon">{item.icon}</span>
              <span className="nav-item-label">{item.label}</span>
            </button>
          ))}
        </nav>

        <div className="rail-footer">
          <div className={`rail-status-dot ${sidecarReady ? "online" : "offline"}`} />
          <span>{sidecarReady ? "Sidecar Ready" : "Waiting"}</span>
        </div>
      </aside>

      <section className="dashboard-frame">
        <header className="dashboard-topbar">
          <div className="topbar-copy">
            <span className="eyebrow">{meta.eyebrow}</span>
            <h1>{meta.title}</h1>
            <p>{meta.description}</p>
          </div>

          <div className="status-pills">
            <span className="status-pill accent">4.x Workbench</span>
            <span className={`status-pill ${sidecarReady ? "good" : "warn"}`}>
              {sidecarReady ? "Sidecar Online" : "Sidecar Offline"}
            </span>
            <span className="status-pill">{secondaryStatusLabel}</span>
          </div>
        </header>

        <main className="dashboard-main">
          {mode === "wizard" && <WizardPane />}
          {mode === "composer" && <ComposerPane />}
          {mode === "projects" && <ProjectsPane onNavigate={setMode} />}
          {mode === "settings" && <SettingsPane />}
        </main>
      </section>
    </div>
  );
}
