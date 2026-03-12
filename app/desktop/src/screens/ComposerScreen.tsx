import { useEffect, useRef, useState } from "react";
import { open, save } from "@tauri-apps/plugin-dialog";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";

import { ComposerCanvas } from "../components/ComposerCanvas";
import {
  composeExport,
  importComposerPanels,
  saveProject,
  threeUp,
  twoUpEditorial,
} from "../lib/api";
import {
  composerLayerTitle,
  describePanelSlot,
  resolveSelectedPanelLabel,
} from "../lib/composer";
import { loadComposerProjectFile } from "../lib/project-io";
import { useComposerStore, useWorkbenchStore } from "../lib/store";
import { getErrorMessage, orderPanels, toDialogPaths } from "../lib/workbench";
import { useComposerPreview } from "./composer/useComposerPreview";
import { usePanelThumbnails } from "./composer/usePanelThumbnails";

const RASTER_EXTENSIONS = new Set([
  ".png",
  ".jpg",
  ".jpeg",
  ".webp",
  ".bmp",
  ".tif",
  ".tiff",
]);

function isPdfPath(path: string): boolean {
  return path.toLowerCase().endsWith(".pdf");
}

function isRasterPath(path: string): boolean {
  const dotIndex = path.lastIndexOf(".");
  if (dotIndex < 0) {
    return false;
  }
  return RASTER_EXTENSIONS.has(path.slice(dotIndex).toLowerCase());
}

function describeSkippedFiles(paths: string[]): string | null {
  if (paths.length === 0) {
    return null;
  }
  const leaves = paths.map((path) => path.split(/[/\\]/).pop() ?? path);
  return `已跳过不支持的文件: ${leaves.join("、")}。`;
}

export function ComposerScreen() {
  const composer = useComposerStore();
  const pdfImportMode = useWorkbenchStore((state) => state.pdfImportMode);
  const setPdfImportMode = useWorkbenchStore((state) => state.setPdfImportMode);
  const rememberProject = useWorkbenchStore((state) => state.rememberProject);
  const [busy, setBusy] = useState(false);
  const [exportPath, setExportPath] = useState<string | null>(null);
  const [dropActive, setDropActive] = useState(false);
  const [dropNotice, setDropNotice] = useState<string | null>(null);
  const projectRef = useRef(composer.project);
  const thumbnailMap = usePanelThumbnails(composer.project.panels);

  const selectedPanel = composer.project.panels.find((item) => item.id === composer.selectedId) ?? null;
  const selectedText = composer.project.texts.find((item) => item.id === composer.selectedId) ?? null;
  const selectedPanelLabel = selectedPanel
    ? resolveSelectedPanelLabel(composer.project, selectedPanel)
    : "";

  const orderedPanels = orderPanels(composer.project.panels);
  const layerItems = [
    ...orderedPanels.map((panel) => ({
      id: panel.id,
      title: composerLayerTitle(composer.project, panel),
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

  useComposerPreview(composer.project, (payload, error) => {
    if (payload) {
      composer.setPreview(payload.png_base64, payload.validation_error ?? null);
      return;
    }
    composer.setPreview(null, error);
  });

  useEffect(() => {
    let disposed = false;
    let unlisten: (() => void) | undefined;

    async function handleDroppedPaths(paths: string[]) {
      const cleaned = paths.filter(Boolean);
      if (cleaned.length === 0) {
        return;
      }

      const pdfs = cleaned.filter(isPdfPath);
      const rasters = cleaned.filter(isRasterPath);
      const unsupported = cleaned.filter(
        (path) => !isPdfPath(path) && !isRasterPath(path),
      );

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
        if (rasters.length > 0) {
          const response = await importComposerPanels(nextProject, rasters, "asset");
          nextProject = {
            ...nextProject,
            panels: response.panels,
          };
        }

        composer.setProject(nextProject);
        composer.setSelectedId(null);

        const skippedNotice = describeSkippedFiles(unsupported);
        if (pdfs.length > 0 && rasters.length > 0) {
          setDropNotice(
            [
              pdfImportMode === "graph"
                ? "已导入图 panel 和素材。PDF 已自动吸附到网格。"
                : "已导入 PDF 素材和图片素材。素材可以继续拖拽、缩放和对齐。",
              skippedNotice,
            ]
              .filter(Boolean)
              .join(" "),
          );
        } else if (pdfs.length > 0) {
          setDropNotice(
            [
              pdfImportMode === "graph"
                ? "已导入图 panel。PDF 已自动吸附到 3x3 网格。"
                : "已导入 PDF 素材。可以继续拖拽、缩放和对齐。",
              skippedNotice,
            ]
              .filter(Boolean)
              .join(" "),
          );
        } else if (rasters.length > 0) {
          setDropNotice(
            ["已导入素材。可以继续拖拽、缩放和对齐。", skippedNotice]
              .filter(Boolean)
              .join(" "),
          );
        } else if (skippedNotice) {
          setDropNotice(skippedNotice);
        }
      } catch (error) {
        setDropNotice(getErrorMessage(error));
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

  const runComposerTask = async (task: () => Promise<void>) => {
    setBusy(true);
    setDropNotice(null);
    try {
      await task();
    } catch (error) {
      setDropNotice(getErrorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const importGraphPanels = async () => {
    const selected = await open({
      multiple: true,
      filters: [{ name: "PDF", extensions: ["pdf"] }],
    });
    const paths = toDialogPaths(selected);
    if (paths.length === 0) {
      return;
    }

    await runComposerTask(async () => {
      const response = await importComposerPanels(composer.project, paths, "graph");
      composer.setProject({
        ...composer.project,
        panels: response.panels,
      });
      composer.setSelectedId(null);
    });
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
    const paths = toDialogPaths(selected);
    if (paths.length === 0) {
      return;
    }

    await runComposerTask(async () => {
      const response = await importComposerPanels(composer.project, paths, "asset");
      composer.setProject({
        ...composer.project,
        panels: response.panels,
      });
      composer.setSelectedId(null);
    });
  };

  const quickThreeUp = async () => {
    const selected = await open({
      multiple: true,
      filters: [{ name: "PDF", extensions: ["pdf"] }],
    });
    const paths = toDialogPaths(selected, 3);
    if (paths.length === 0) {
      return;
    }

    await runComposerTask(async () => {
      const response = await threeUp(paths);
      composer.setProject({
        ...composer.project,
        panels: response.panels,
        texts: [],
      });
      composer.setSelectedId(null);
      setDropNotice("已按 180 mm 画布生成三联图排版。");
    });
  };

  const quickTwoUpEditorial = async () => {
    const selected = await open({
      multiple: true,
      filters: [{ name: "PDF", extensions: ["pdf"] }],
    });
    const paths = toDialogPaths(selected, 2);
    if (paths.length === 0) {
      return;
    }

    await runComposerTask(async () => {
      const response = await twoUpEditorial(paths);
      composer.setProject({
        ...composer.project,
        panels: response.panels,
        texts: [],
      });
      composer.setSelectedId(null);
      setDropNotice("已按 180 mm 画布生成两图 + 说明区排版。");
    });
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

  const updateSelectedPanel = (patch: Partial<typeof composer.project.panels[number]>) => {
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

  const updateSelectedText = (patch: Partial<typeof composer.project.texts[number]>) => {
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
    const path = toDialogPaths(destination, 1)[0];
    if (!path) {
      return;
    }

    await runComposerTask(async () => {
      await saveProject(path, {
        version: 1,
        mode: "composer",
        project: composer.project,
      });
      rememberProject({
        mode: "composer",
        kind: "project",
        path,
        title: path.split(/[/\\]/).pop() ?? path,
        detail: `已保存拼图项目 · ${composer.project.panels.length} 个 panel`,
      });
      setDropNotice("拼图项目已保存。");
    });
  };

  const openComposerProject = async () => {
    const selected = await open({
      multiple: false,
      filters: [{ name: "CodeGod Project", extensions: ["json"] }],
    });
    const path = toDialogPaths(selected, 1)[0];
    if (!path) {
      return;
    }

    await runComposerTask(async () => {
      const project = await loadComposerProjectFile(composer, path);
      rememberProject({
        mode: "composer",
        kind: "project",
        path,
        title: path.split(/[/\\]/).pop() ?? path,
        detail: `拼图项目 · ${project.panels.length} 个 panel / ${project.texts.length} 段文字`,
      });
      setDropNotice("项目已加载，可以继续调整拼图。");
    });
  };

  const exportComposer = async () => {
    await runComposerTask(async () => {
      const response = await composeExport(composer.project);
      setExportPath(response.output_path);
    });
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
              <h3>对象属性</h3>
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
