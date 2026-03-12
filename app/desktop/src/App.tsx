import { useEffect, useRef, useState } from "react";
import { open, save } from "@tauri-apps/plugin-dialog";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";

import { ComposerCanvas } from "./components/ComposerCanvas";
import { PreviewPane } from "./components/PreviewPane";
import {
  composeExport,
  importComposerPanels,
  composePreview,
  healthcheck,
  inspectFile,
  openProject,
  panelThumbnail,
  preflightRender,
  renderPreview,
  saveProject,
  exportRender,
  threeUp,
  twoUpEditorial,
} from "./lib/api";
import { useComposerStore, useWizardStore } from "./lib/store";
import type {
  ComposerProject,
  PalettePreset,
  RenderOptionsPayload,
  SizePreset,
  TemplateName,
  WizardStep,
  WizardProject,
} from "./lib/types";

const steps: { id: WizardStep; label: string }[] = [
  { id: "file", label: "文件" },
  { id: "sheet", label: "Sheet" },
  { id: "inspect", label: "识别" },
  { id: "template", label: "图型" },
  { id: "options", label: "参数" },
  { id: "preflight", label: "检查" },
  { id: "export", label: "导出" },
];

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

function Stepper({ current }: { current: WizardStep }) {
  const currentIndex = steps.findIndex((step) => step.id === current);
  return (
    <div className="stepper">
      {steps.map((step, index) => (
        <div className="stepper-item" key={step.id}>
          <div
            className={`stepper-dot ${index <= currentIndex ? "active" : ""} ${index === currentIndex ? "current" : ""}`}
          >
            {index + 1}
          </div>
          <div className="stepper-label">{step.label}</div>
        </div>
      ))}
    </div>
  );
}

function WizardPane() {
  const wizard = useWizardStore();
  const [previewBusy, setPreviewBusy] = useState(false);
  const [previewError, setPreviewError] = useState<string | null>(null);

  const currentPreview = wizard.previews;

  useEffect(() => {
    let cancelled = false;
    async function checkSidecar() {
      const ok = await healthcheck();
      if (!cancelled) {
        wizard.setSidecarReady(ok);
      }
    }
    void checkSidecar();
    return () => {
      cancelled = true;
    };
  }, [wizard]);

  useEffect(() => {
    if (!wizard.inputPath || !wizard.template) {
      return;
    }
    const template = wizard.template;
    let cancelled = false;
    const handle = window.setTimeout(async () => {
      setPreviewBusy(true);
      setPreviewError(null);
      try {
        const payload = await renderPreview(wizard.inputPath, wizard.sheet, template, wizard.options);
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
    }, 240);
    return () => {
      cancelled = true;
      window.clearTimeout(handle);
    };
  }, [wizard.inputPath, wizard.sheet, wizard.template, wizard.options, wizard]);

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
    wizard.setBusy(true);
    try {
      const response = await preflightRender(wizard.inputPath, wizard.sheet, wizard.template, wizard.options);
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
    wizard.setBusy(true);
    try {
      const response = await exportRender(wizard.inputPath, wizard.sheet, wizard.template, wizard.options);
      wizard.setOutputs(response.outputs);
      wizard.setStep("export");
    } catch (error) {
      wizard.setError(error instanceof Error ? error.message : String(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  return (
    <div className="wizard-shell">
      <div className="wizard-column">
        <div className="wizard-topbar">
          <div className="wizard-title">
            <div className="eyebrow">CodeGod</div>
            <h1>绘图精灵</h1>
          </div>
          <div className="wizard-topbar-actions">
            <button className="ghost-button compact-button" onClick={openWizardProject} type="button">
              打开项目
            </button>
          </div>
        </div>

        {(wizard.inputPath || wizard.sheetNames.length > 0) && (
          <div className="wizard-filebar">
            <div className="file-chip">
              <span className="file-chip-label">文件</span>
              <strong>{wizard.inputPath ? wizard.inputPath.split("/").pop() : "未选择"}</strong>
            </div>
            {wizard.sheetNames.length > 0 && (
              <div className="file-chip">
                <span className="file-chip-label">Sheet</span>
                <strong>{String(wizard.sheet)}</strong>
              </div>
            )}
          </div>
        )}

        <Stepper current={wizard.step} />

        <div className="wizard-card">
          {wizard.error && <div className="error-card">{wizard.error}</div>}

          {wizard.step === "file" && (
            <div className="step-block">
              <h2>先给我数据</h2>
              <p>拖文件或者直接打开。程序会先识别输入结构，再推荐最可能正确的出图方式。</p>
              <div className="step-actions">
                <button className="primary-button" onClick={openDataFile} type="button">
                  打开数据文件
                </button>
                <button className="ghost-button" onClick={openWizardProject} type="button">
                  打开项目
                </button>
              </div>
              {!wizard.sidecarReady && (
                <div className="warning-card">本地 Python sidecar 尚未连通，稍后会自动重试。</div>
              )}
            </div>
          )}

          {wizard.step === "sheet" && (
            <div className="step-block">
              <h2>选择 sheet</h2>
              <p>这个文件里有多个工作表，先确认当前要出图的那一张。</p>
              <select
                className="field"
                value={String(wizard.sheet)}
                onChange={(event) => void rerunInspect(event.target.value)}
              >
                {wizard.sheetNames.map((name, index) => (
                  <option key={name} value={name}>
                    {index}. {name}
                  </option>
                ))}
              </select>
            </div>
          )}

          {wizard.step === "inspect" && wizard.inspection && (
            <div className="step-block">
              <h2>程序这样判断</h2>
              <p>{wizard.inspection.recommendation.reason}</p>
              <div className="info-grid">
                <div>
                  <span className="field-label">输入模型</span>
                  <strong>{wizard.inspection.model_label}</strong>
                </div>
                <div>
                  <span className="field-label">推荐图型</span>
                  <strong>{wizard.inspection.recommendation.template}</strong>
                </div>
              </div>
              {wizard.inspection.signals.length > 0 && (
                <details>
                  <summary>为什么这样推荐</summary>
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
              <h2>确认图类型</h2>
              <p>如果推荐已经对了，这一步一般不用改。</p>
              <select
                className="field"
                value={wizard.template ?? "curve"}
                onChange={(event) => wizard.setTemplate(event.target.value as TemplateName)}
              >
                {templateChoices.map((template) => (
                  <option key={template} value={template}>
                    {template}
                  </option>
                ))}
              </select>
              <div className="step-actions">
                <button className="ghost-button" onClick={() => wizard.setStep("inspect")} type="button">
                  返回
                </button>
                <button className="primary-button" onClick={() => wizard.setStep("options")} type="button">
                  下一步
                </button>
              </div>
            </div>
          )}

          {wizard.step === "options" && wizard.template && (
            <div className="step-block">
              <h2>调整必要参数</h2>
              <div className="field-grid">
                <label>
                  <span className="field-label">尺寸</span>
                  <select
                    className="field"
                    value={wizard.options.size}
                    onChange={(event) => wizard.setOptions({ size: event.target.value as SizePreset })}
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
                        value={wizard.options.xscale}
                        onChange={(event) => wizard.setOptions({ xscale: event.target.value as "linear" | "log" })}
                      >
                        <option value="linear">linear</option>
                        <option value="log">log</option>
                      </select>
                    </label>
                    <label>
                      <span className="field-label">Y 轴</span>
                      <select
                        className="field"
                        value={wizard.options.yscale}
                        onChange={(event) => wizard.setOptions({ yscale: event.target.value as "linear" | "log" })}
                      >
                        <option value="linear">linear</option>
                        <option value="log">log</option>
                      </select>
                    </label>
                    <label className="toggle-field">
                      <input
                        checked={Boolean(wizard.options.reverse_x)}
                        onChange={(event) => wizard.setOptions({ reverse_x: event.target.checked })}
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
                        onChange={(event) => wizard.setOptions({ reverse_x: event.target.checked })}
                        type="checkbox"
                      />
                      <span>反向 X 轴</span>
                    </label>
                    <label>
                      <span className="field-label">Baseline</span>
                      <select
                        className="field"
                        value={wizard.options.baseline}
                        onChange={(event) =>
                          wizard.setOptions({
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
                      onChange={(event) => wizard.setOptions({ show_colorbar: event.target.checked })}
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
                      value={wizard.options.palette_preset}
                      onChange={(event) =>
                        wizard.setOptions({ palette_preset: event.target.value as PalettePreset })
                      }
                    >
                      {paletteChoices.map((choice) => (
                        <option key={choice} value={choice}>
                          {choice}
                        </option>
                      ))}
                    </select>
                  </label>
                </div>
              </details>
              <div className="step-actions">
                <button className="ghost-button" onClick={() => wizard.setStep("template")} type="button">
                  返回
                </button>
                <button className="primary-button" onClick={() => void runPreflight()} type="button">
                  继续检查
                </button>
              </div>
            </div>
          )}

          {wizard.step === "preflight" && wizard.preflight && (
            <div className="step-block">
              <h2>预检查</h2>
              {wizard.preflight.errors.length > 0 ? (
                <div className="error-card">
                  <strong>当前不能直接出图：</strong>
                  <ul className="bullet-list">
                    {wizard.preflight.errors.map((item) => (
                      <li key={item}>{item}</li>
                    ))}
                  </ul>
                </div>
              ) : (
                <div className="success-card">当前检查通过，可以直接导出。</div>
              )}
              {wizard.preflight.warnings.length > 0 && (
                <details>
                  <summary>建议先注意</summary>
                  <ul className="bullet-list">
                    {wizard.preflight.warnings.map((item) => (
                      <li key={item}>{item}</li>
                    ))}
                  </ul>
                </details>
              )}
              <div className="step-actions">
                <button className="ghost-button" onClick={() => wizard.setStep("options")} type="button">
                  返回修改
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
              <h2>导出完成</h2>
              <p>程序已经按当前图类型和参数导出 PDF。</p>
              <ul className="bullet-list">
                {wizard.outputs.map((output) => (
                  <li key={output}>{output}</li>
                ))}
              </ul>
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
        </div>
      </div>

      <PreviewPane
        busy={previewBusy || wizard.busy}
        error={previewError}
        onChangeIndex={wizard.setPreviewIndex}
        previewIndex={wizard.previewIndex}
        previews={currentPreview}
      />
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
    ? (() => {
        if (!composer.project.auto_labels) {
          return selectedPanel.label ?? "";
        }
        const ordered = [...composer.project.panels].sort((a, b) => {
          if (Math.abs(a.y_mm - b.y_mm) > 0.25) {
            return a.y_mm - b.y_mm;
          }
          if (Math.abs(a.x_mm - b.x_mm) > 0.25) {
            return a.x_mm - b.x_mm;
          }
          return a.id.localeCompare(b.id);
        });
        const index = ordered.findIndex((panel) => panel.id === selectedPanel.id);
        return index >= 0 ? String.fromCharCode("a".charCodeAt(0) + index) : "";
      })()
    : "";

  useEffect(() => {
    projectRef.current = composer.project;
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
  }, [composer.project, composer]);

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
        setExportPath(null);
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
              ? "已导入图 panel。PDF 已自动吸附到 3×3 网格。"
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
        if (event.payload.type === "over") {
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
  }, [composer, pdfImportMode]);

  const importGraphPanels = async () => {
    const selected = await open({
      multiple: true,
      filters: [{ name: "PDF", extensions: ["pdf"] }],
    });
    const paths = Array.isArray(selected) ? selected.filter((item): item is string => typeof item === "string") : [];
    if (paths.length === 0) {
      return;
    }
    setBusy(true);
    try {
      const response = await importComposerPanels(composer.project, paths, "graph");
      composer.setProject({
        ...composer.project,
        panels: response.panels,
      });
      setExportPath(null);
    } finally {
      setBusy(false);
    }
  };

  const importAssetPanels = async () => {
    const selected = await open({
      multiple: true,
      filters: [
        { name: "Visual Assets", extensions: ["pdf", "png", "jpg", "jpeg", "webp", "bmp", "tif", "tiff"] },
      ],
    });
    const paths = Array.isArray(selected) ? selected.filter((item): item is string => typeof item === "string") : [];
    if (paths.length === 0) {
      return;
    }
    setBusy(true);
    try {
      const response = await importComposerPanels(composer.project, paths, "asset");
      composer.setProject({
        ...composer.project,
        panels: response.panels,
      });
      setExportPath(null);
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
      ? selected.filter((item): item is string => typeof item === "string").slice(0, 3)
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
      setExportPath(null);
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
      ? selected.filter((item): item is string => typeof item === "string").slice(0, 2)
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
      setExportPath(null);
      setDropNotice("已按 180 mm 画布生成两图 + 说明区排版。第三列可继续放结构式、示意图、图片或文字。");
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
    setExportPath(null);
  };

  const exportComposer = async () => {
    setBusy(true);
    try {
      const response = await composeExport(composer.project);
      setExportPath(response.output_path);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="composer-shell">
      <div className="composer-sidebar">
        <div className="eyebrow">拼图器</div>
        <h2>180 × 170 mm 画布</h2>
        <p>拖入 PDF 时可按当前模式导入为图 panel 或素材；图片始终作为素材导入。支持文字、三联图排版和 a/b/c 序号。</p>
        <div className="inspector-card">
          <div className="field-label">PDF 导入模式</div>
          <div className="mode-switch">
            <button
              className={`mode-button ${pdfImportMode === "graph" ? "active" : ""}`}
              onClick={() => setPdfImportMode("graph")}
              type="button"
            >
              作为图
            </button>
            <button
              className={`mode-button ${pdfImportMode === "asset" ? "active" : ""}`}
              onClick={() => setPdfImportMode("asset")}
              type="button"
            >
              作为素材
            </button>
          </div>
          <div className="hint-text">
            {pdfImportMode === "graph"
              ? "Graph panel 会吸附到 3×3 网格，不支持缩放。"
              : "Asset 支持 PDF/图片，允许在格子中移动和缩放。"}
          </div>
        </div>
        <div className="sidebar-actions">
          <button className="primary-button" onClick={importGraphPanels} type="button">
            导入图
          </button>
          <button className="ghost-button" onClick={quickThreeUp} type="button">
            三联图
          </button>
          <button className="ghost-button" onClick={quickTwoUpEditorial} type="button">
            两图+说明区
          </button>
          <button className="ghost-button" onClick={importAssetPanels} type="button">
            导入素材
          </button>
          <button className="ghost-button" onClick={openComposerProject} type="button">
            打开项目
          </button>
          <button className="ghost-button" onClick={saveComposerProject} type="button">
            保存项目
          </button>
          <button className="ghost-button" onClick={addText} type="button">
            添加文字
          </button>
          <button className="ghost-button" onClick={exportComposer} type="button">
            导出总图
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
        {selectedPanel && (
          <div className="inspector-card">
            <div className="field-label">选中 panel</div>
            <div className="info-grid compact-grid">
              <div>
                <span className="field-label">类型</span>
                <strong>{selectedPanel.kind === "graph" ? "Graph" : "Asset"}</strong>
              </div>
              <div>
                <span className="field-label">标签</span>
                <strong>{selectedPanelLabel || "-"}</strong>
              </div>
            </div>
            <label>
              <span className="field-label">自定义标签</span>
              <input
                className="field"
                type="text"
                value={selectedPanel.label ?? ""}
                onChange={(event) => updateSelectedPanel({ label: event.target.value || null })}
                disabled={composer.project.auto_labels}
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
              <div>
                <span className="field-label">X / mm</span>
                <strong>{selectedPanel.x_mm.toFixed(1)}</strong>
              </div>
              <div>
                <span className="field-label">Y / mm</span>
                <strong>{selectedPanel.y_mm.toFixed(1)}</strong>
              </div>
              <div>
                <span className="field-label">W / mm</span>
                <strong>{selectedPanel.w_mm.toFixed(1)}</strong>
              </div>
              <div>
                <span className="field-label">H / mm</span>
                <strong>{selectedPanel.h_mm.toFixed(1)}</strong>
              </div>
            </div>
            {selectedPanel.kind === "graph" && (
              <div className="hint-text">Graph panel 会自动吸附到 3×3 网格，不支持手动缩放。</div>
            )}
            {selectedPanel.kind === "asset" && (
              <div className="hint-text">Asset 可自由拖拽和缩放，但仍会避免与其他 panel 重叠。</div>
            )}
            <button className="ghost-button danger-button" onClick={removeSelected} type="button">
              删除 panel
            </button>
          </div>
        )}
        {selectedText && (
          <div className="inspector-card">
            <div className="field-label">选中文字</div>
            <label>
              <span className="field-label">内容</span>
              <input
                className="field"
                type="text"
                value={selectedText.text}
                onChange={(event) => updateSelectedText({ text: event.target.value })}
              />
            </label>
            <label>
              <span className="field-label">字号</span>
              <input
                className="field"
                min={5}
                max={20}
                type="number"
                value={selectedText.font_size_pt}
                onChange={(event) =>
                  updateSelectedText({ font_size_pt: Number(event.target.value) || selectedText.font_size_pt })
                }
              />
            </label>
            <label>
              <span className="field-label">对齐</span>
              <select
                className="field"
                value={selectedText.align}
                onChange={(event) =>
                  updateSelectedText({ align: event.target.value as "left" | "center" | "right" })
                }
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
        {composer.validationError && <div className="warning-card">{composer.validationError}</div>}
        {dropNotice && (
          <div className={dropNotice.includes("未导入") || dropNotice.includes("错误") ? "warning-card" : "success-card"}>
            {dropNotice}
          </div>
        )}
        {exportPath && <div className="success-card">已导出：{exportPath}</div>}
      </div>
      <div className="composer-main">
        <div className={`composer-drop-overlay ${dropActive ? "visible" : ""}`}>
          <div className="composer-drop-card">
            <strong>松开即可导入</strong>
            <span>
              {pdfImportMode === "graph"
                ? "PDF 会作为图 panel 吸附到 3×3 网格，图片会作为素材导入。"
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
                ? "图 panel 会自动吸附到 3×3 网格；素材可自由缩放与移动。"
                : "当前模式会把 PDF 当作素材导入；素材可自由缩放、移动并自动避让。"}
            </span>
          </div>
        )}
        {busy && <div className="composer-status">正在更新…</div>}
      </div>
    </div>
  );
}

export default function App() {
  const [mode, setMode] = useState<"wizard" | "composer">("wizard");

  return (
    <div className="app-shell">
      <aside className="app-rail">
        <div className="rail-brand">
          <div className="brand-mark">CG</div>
          <div>
            <div className="eyebrow">CodeGod</div>
            <div className="rail-title">Plot Studio</div>
          </div>
        </div>

        <div className="rail-section">
          <button
            className={`rail-nav-button ${mode === "wizard" ? "active" : ""}`}
            onClick={() => setMode("wizard")}
            type="button"
          >
            <span className="rail-nav-label">绘图精灵</span>
            <span className="rail-nav-hint">单图出图</span>
          </button>
          <button
            className={`rail-nav-button ${mode === "composer" ? "active" : ""}`}
            onClick={() => setMode("composer")}
            type="button"
          >
            <span className="rail-nav-label">拼图器</span>
            <span className="rail-nav-hint">180 mm 画布</span>
          </button>
        </div>

        <div className="rail-footer">
          <div className="rail-status-dot" />
          <span>本地 sidecar 驱动中</span>
        </div>
      </aside>
      <main className="app-workspace">{mode === "wizard" ? <WizardPane /> : <ComposerPane />}</main>
    </div>
  );
}
  const normalizeComposerProject = (project: ComposerProject): ComposerProject => ({
    ...project,
    panels: project.panels.map((panel) => ({
      ...panel,
      kind: panel.kind ?? "graph",
    })),
  });
