import { useEffect, useMemo, useRef, useState } from "react";
import { flushSync } from "react-dom";
import { useShallow } from "zustand/react/shallow";

import { ComposerCanvas } from "../components/ComposerCanvas";
import {
  composeExport,
  importComposerPanels,
  saveProject,
  threeUp,
  twoUpEditorial,
} from "../lib/api";
import {
  alignDrawables,
  buildComposerClipboard,
  composerLayerTitle,
  describePanelSlot,
  duplicateComposerSelection,
  expandSelectionWithGroups,
  distributeDrawables,
  editableSelectionIds,
  findRegion,
  groupDrawables,
  mergeCellsIntoFreeRegion,
  moveGraphSelectionByCells,
  moveRegion,
  nextTextId,
  nextZIndex,
  nudgeDrawables,
  placeDrawableInRect,
  normalizeComposerProject,
  orderDrawables,
  pasteComposerClipboard,
  regionRect,
  regionSlotId,
  regionSlotRect,
  removeRegion,
  reorderDrawable,
  resolveSelectedPanelLabel,
  selectedRegionIdsForObjects,
  type ComposerClipboard,
  ungroupDrawables,
} from "../lib/composer";
import { loadComposerProjectFile } from "../lib/project-io";
import { openDialog, saveDialog } from "../lib/tauri-dialog";
import { getCodeGodWebviewWindow } from "../lib/tauri-webview";
import type { ComposerPanel, ComposerProject, ComposerText } from "../lib/types";
import { useComposerStore, useWorkbenchStore } from "../lib/store";
import { getErrorMessage, toDialogPaths } from "../lib/workbench";
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

type CellRef = { col: number; row: number };

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

function centerObjectInRect<T extends { x_mm: number; y_mm: number; w_mm?: number; h_mm?: number }>(
  target: T,
  rect: { x_mm: number; y_mm: number; w_mm: number; h_mm: number },
) {
  const width = "w_mm" in target ? target.w_mm ?? 0 : 0;
  const height = "h_mm" in target ? target.h_mm ?? 0 : 0;
  return {
    ...target,
    x_mm: rect.x_mm + (rect.w_mm - width) / 2,
    y_mm: rect.y_mm + (rect.h_mm - height) / 2,
  };
}

function fitPanelToRect(
  panel: ComposerPanel,
  rect: { x_mm: number; y_mm: number; w_mm: number; h_mm: number },
) {
  return {
    ...panel,
    x_mm: rect.x_mm,
    y_mm: rect.y_mm,
    w_mm: rect.w_mm,
    h_mm: rect.h_mm,
  };
}

function boundRectForDrawable(
  project: ComposerProject,
  drawable: ComposerPanel | ComposerText,
) {
  if (!drawable.region_id) {
    return null;
  }
  const region = findRegion(project, drawable.region_id);
  if (!region) {
    return null;
  }
  return drawable.slot_id ? regionSlotRect(project, region) : regionRect(project, region);
}

function bindingValueForDrawable(drawable: ComposerPanel | ComposerText) {
  if (drawable.slot_id && drawable.region_id) {
    return `slot:${drawable.region_id}`;
  }
  if (drawable.region_id) {
    return `region:${drawable.region_id}`;
  }
  return "none";
}

function uniqueCells(cells: CellRef[]) {
  return Array.from(new Map(cells.map((cell) => [`${cell.col}:${cell.row}`, cell])).values());
}

function snapImportedAssetsIntoRegion(
  previousProject: ComposerProject,
  nextProject: ComposerProject,
  regionId: string,
) {
  const region = findRegion(nextProject, regionId);
  if (!region || region.kind !== "free") {
    return nextProject;
  }
  const rect = regionRect(nextProject, region);
  const existingIds = new Set(previousProject.panels.map((panel) => panel.id));
  let offset = 0;
  return normalizeComposerProject({
    ...nextProject,
    panels: nextProject.panels.map((panel) => {
      if (panel.kind !== "asset" || existingIds.has(panel.id)) {
        return panel;
      }
      const centered = centerObjectInRect(panel, rect);
      const placed = {
        ...centered,
        x_mm: centered.x_mm + offset,
        y_mm: centered.y_mm + offset,
        region_id: region.id,
        slot_id: null,
      };
      offset += 2;
      return placed;
    }),
  });
}

export function ComposerScreen() {
  const composer = useComposerStore(
    useShallow((state) => ({
      project: state.project,
      selectedId: state.selectedId,
      setPreview: state.setPreview,
      setProject: state.setProject,
      setSelectedId: state.setSelectedId,
      updatePanels: state.updatePanels,
      updateTexts: state.updateTexts,
      validationError: state.validationError,
    })),
  );
  const pdfImportMode = useWorkbenchStore((state) => state.pdfImportMode);
  const setPdfImportMode = useWorkbenchStore((state) => state.setPdfImportMode);
  const rememberProject = useWorkbenchStore((state) => state.rememberProject);
  const [busy, setBusy] = useState(false);
  const [exportPath, setExportPath] = useState<string | null>(null);
  const [dropActive, setDropActive] = useState(false);
  const [dropNotice, setDropNotice] = useState<string | null>(null);
  const [selectedCells, setSelectedCells] = useState<CellRef[]>([]);
  const [selectedObjectIds, setSelectedObjectIds] = useState<string[]>([]);
  const [clipboardReady, setClipboardReady] = useState(false);
  const projectRef = useRef(composer.project);
  const selectedRegionRef = useRef<string | null>(null);
  const clipboardRef = useRef<ComposerClipboard | null>(null);
  const visiblePanels = useMemo(
    () => composer.project.panels.filter((panel) => !panel.hidden),
    [composer.project.panels],
  );
  const thumbnailMap = usePanelThumbnails(visiblePanels);

  const primaryObjectId = selectedObjectIds.length === 1 ? selectedObjectIds[0] : null;
  const selectedPanel = composer.project.panels.find((item) => item.id === primaryObjectId) ?? null;
  const selectedText = composer.project.texts.find((item) => item.id === primaryObjectId) ?? null;
  const selectedRegion =
    selectedObjectIds.length === 0
      ? composer.project.regions.find((item) => item.id === composer.selectedId) ?? null
      : null;
  const selectedPanelLabel = selectedPanel
    ? resolveSelectedPanelLabel(composer.project, selectedPanel)
    : "";
  const selectedPanelPositionLocked = Boolean(
    selectedPanel &&
      (selectedPanel.locked ||
        (selectedPanel.kind === "graph" &&
          findRegion(composer.project, selectedPanel.region_id)?.locked)),
  );
  const selectedTextPositionLocked = Boolean(selectedText?.locked);
  const selectedEditableIds = useMemo(
    () => editableSelectionIds(composer.project, selectedObjectIds),
    [composer.project, selectedObjectIds],
  );
  const hasSelection = Boolean(selectedRegion) || selectedObjectIds.length > 0;
  const canCopySelection = hasSelection;
  const canPasteSelection = clipboardReady;
  const selectedHighlightRegionIds = useMemo(
    () => [
      ...(selectedRegion ? [selectedRegion.id] : []),
      ...selectedRegionIdsForObjects(composer.project, selectedObjectIds),
    ],
    [composer.project, selectedObjectIds, selectedRegion],
  );
  const multiSelectedItems = useMemo(
    () =>
      selectedObjectIds
        .map((id) => composer.project.panels.find((item) => item.id === id) ?? composer.project.texts.find((item) => item.id === id) ?? null)
        .filter((item): item is ComposerPanel | ComposerText => item != null),
    [composer.project.panels, composer.project.texts, selectedObjectIds],
  );
  const selectedGroupIds = useMemo(
    () =>
      Array.from(
        new Set(
          multiSelectedItems
            .map((item) => item.group_id)
            .filter((value): value is string => Boolean(value)),
        ),
      ),
    [multiSelectedItems],
  );
  const selectedHiddenCount = useMemo(
    () => multiSelectedItems.filter((item) => Boolean(item.hidden)).length,
    [multiSelectedItems],
  );
  const selectedLockedCount = useMemo(
    () => multiSelectedItems.filter((item) => Boolean(item.locked)).length,
    [multiSelectedItems],
  );
  const canGroupSelection = selectedEditableIds.length >= 2;
  const canUngroupSelection = selectedGroupIds.length > 0;

  const readDialogPaths = async (
    options: Parameters<typeof openDialog>[0],
    limit?: number,
  ) => {
    try {
      return toDialogPaths(await openDialog(options), limit);
    } catch (error) {
      setDropNotice(getErrorMessage(error));
      return [];
    }
  };

  const readSavePath = async (options: Parameters<typeof saveDialog>[0]) => {
    try {
      return toDialogPaths(await saveDialog(options), 1)[0] ?? null;
    } catch (error) {
      setDropNotice(getErrorMessage(error));
      return null;
    }
  };

  const freeRegions = useMemo(
    () => composer.project.regions.filter((region) => region.kind === "free"),
    [composer.project.regions],
  );
  const slotRegions = useMemo(
    () => composer.project.regions.filter((region) => region.slot_kind === "structure"),
    [composer.project.regions],
  );

  const orderedDrawables = useMemo(() => orderDrawables(composer.project), [composer.project]);
  const layerItems = useMemo(
    () => [
      ...composer.project.regions.map((region) => ({
        id: region.id,
        type: "region" as const,
        title: region.kind === "graph" ? `Graph Region ${region.id}` : region.label || `Free Region ${region.id}`,
        detail:
          region.kind === "graph"
            ? `${region.col_span} x ${region.row_span} grid${region.locked ? " · Locked" : ""}`
            : `Free ${region.col_span} x ${region.row_span} region${region.locked ? " · Locked" : ""}`,
      })),
      ...orderedDrawables.map((item) => {
        if (item.type === "panel") {
          const panel = composer.project.panels.find((entry) => entry.id === item.id)!;
          return {
            id: panel.id,
            type: "panel" as const,
            title: composerLayerTitle(composer.project, panel),
            detail:
              panel.kind === "graph"
                ? `Graph · ${describePanelSlot(panel, composer.project)}${panel.group_id ? ` · ${panel.group_id}` : ""}${panel.hidden ? " · Hidden" : ""}${panel.locked ? " · Locked" : ""}`
                : `Asset · ${panel.w_mm.toFixed(1)} x ${panel.h_mm.toFixed(1)} mm${panel.group_id ? ` · ${panel.group_id}` : ""}${panel.hidden ? " · Hidden" : ""}${panel.locked ? " · Locked" : ""}`,
          };
        }
        const text = composer.project.texts.find((entry) => entry.id === item.id)!;
        return {
          id: text.id,
          type: "text" as const,
          title: text.text || "Text",
          detail: `Text · ${text.font_size_pt} pt${text.group_id ? ` · ${text.group_id}` : ""}${text.hidden ? " · Hidden" : ""}${text.locked ? " · Locked" : ""}`,
        };
      }),
    ],
    [composer.project, orderedDrawables],
  );

  useEffect(() => {
    projectRef.current = composer.project;
  }, [composer.project]);

  useEffect(() => {
    selectedRegionRef.current = selectedRegion?.kind === "free" ? selectedRegion.id : null;
  }, [selectedRegion]);

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
          nextProject = await importComposerPanels(nextProject, pdfs, pdfImportMode);
        }
        if (rasters.length > 0) {
          const beforeRasters = nextProject;
          nextProject = await importComposerPanels(nextProject, rasters, "asset");
          if (selectedRegionRef.current) {
            nextProject = snapImportedAssetsIntoRegion(beforeRasters, nextProject, selectedRegionRef.current);
          }
        }

        composer.setProject(normalizeComposerProject(nextProject));
        composer.setSelectedId(null);
        setSelectedCells([]);

        const skippedNotice = describeSkippedFiles(unsupported);
        if (pdfs.length > 0 && rasters.length > 0) {
          setDropNotice(
            [
              pdfImportMode === "graph"
                ? "已导入图容器和自由素材。Graph PDF 会自动占据标准网格区域。"
                : "已导入 PDF 素材和图片素材。素材可以继续自由布局、裁边和叠放。",
              skippedNotice,
            ]
              .filter(Boolean)
              .join(" "),
          );
        } else if (pdfs.length > 0) {
          setDropNotice(
            [
              pdfImportMode === "graph"
                ? "已导入 graph PDF，并自动占据对应区域。"
                : "已导入 PDF 素材，可继续自由布局。",
              skippedNotice,
            ]
              .filter(Boolean)
              .join(" "),
          );
        } else if (rasters.length > 0) {
          setDropNotice(
            ["已导入自由素材，可继续裁边、吸附和叠放。", skippedNotice]
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
      try {
        const webview = getCodeGodWebviewWindow();
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
      } catch (error) {
        if (!disposed) {
          setDropNotice(getErrorMessage(error));
        }
      }
    }

    void attach();

    return () => {
      disposed = true;
      setDropActive(false);
      void unlisten?.();
    };
  }, [composer, pdfImportMode]);

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

  const applyImportedProject = (nextProject: ComposerProject) => {
    composer.setProject(normalizeComposerProject(nextProject));
    composer.setSelectedId(null);
    setSelectedCells([]);
    setSelectedObjectIds([]);
  };

  const importGraphPanels = async () => {
    const paths = await readDialogPaths({
      multiple: true,
      filters: [{ name: "PDF", extensions: ["pdf"] }],
    });
    if (paths.length === 0) {
      return;
    }

    await runComposerTask(async () => {
      const response = await importComposerPanels(composer.project, paths, "graph");
      applyImportedProject(response);
      setDropNotice("Graph PDF 已按尺寸自动占据 60x55 基础网格。");
    });
  };

  const importAssetPanels = async () => {
    const paths = await readDialogPaths({
      multiple: true,
      filters: [
        {
          name: "Visual Assets",
          extensions: ["pdf", "png", "jpg", "jpeg", "webp", "bmp", "tif", "tiff"],
        },
      ],
    });
    if (paths.length === 0) {
      return;
    }

    await runComposerTask(async () => {
      const response = await importComposerPanels(composer.project, paths, "asset");
      const nextProject =
        selectedRegion?.kind === "free"
          ? snapImportedAssetsIntoRegion(composer.project, response, selectedRegion.id)
          : response;
      applyImportedProject(nextProject);
      setDropNotice("素材已导入，可自由布局、裁边和覆盖 graph。");
    });
  };

  const quickThreeUp = async () => {
    const paths = await readDialogPaths({
      multiple: true,
      filters: [{ name: "PDF", extensions: ["pdf"] }],
    }, 3);
    if (paths.length === 0) {
      return;
    }

    await runComposerTask(async () => {
      const response = await threeUp(paths);
      applyImportedProject(response);
      setDropNotice("已按 region-based 三联图预设排版。");
    });
  };

  const quickTwoUpEditorial = async () => {
    const paths = await readDialogPaths({
      multiple: true,
      filters: [{ name: "PDF", extensions: ["pdf"] }],
    }, 2);
    if (paths.length === 0) {
      return;
    }

    await runComposerTask(async () => {
      const response = await twoUpEditorial(paths);
      applyImportedProject(response);
      setDropNotice("已生成两图 + 自由说明区预设。");
    });
  };

  const addText = () => {
    composer.updateTexts([
      ...composer.project.texts,
      {
        id: nextTextId(composer.project),
        text: "Text",
        x_mm: 8,
        y_mm: 8,
        font_size_pt: 8,
        align: "left",
        z_index: nextZIndex(composer.project),
        region_id: null,
        slot_id: null,
      },
    ]);
    composer.setSelectedId(null);
    setSelectedObjectIds([]);
  };

  const setProject = (project: ComposerProject) => {
    composer.setProject(normalizeComposerProject(project));
  };

  const filterLockedPanelPatch = (patch: Partial<ComposerPanel>) => {
    if (!selectedPanelPositionLocked) {
      return patch;
    }
    const nextPatch: Partial<ComposerPanel> = {};
    if ("label" in patch) {
      nextPatch.label = patch.label;
    }
    if ("locked" in patch) {
      nextPatch.locked = patch.locked;
    }
    if ("hidden" in patch) {
      nextPatch.hidden = patch.hidden;
    }
    if ("crop_rect" in patch) {
      nextPatch.crop_rect = patch.crop_rect;
    }
    return nextPatch;
  };

  const filterLockedTextPatch = (patch: Partial<ComposerText>) => {
    if (!selectedTextPositionLocked) {
      return patch;
    }
    const nextPatch: Partial<ComposerText> = {};
    if ("text" in patch) {
      nextPatch.text = patch.text;
    }
    if ("font_size_pt" in patch) {
      nextPatch.font_size_pt = patch.font_size_pt;
    }
    if ("align" in patch) {
      nextPatch.align = patch.align;
    }
    if ("locked" in patch) {
      nextPatch.locked = patch.locked;
    }
    if ("hidden" in patch) {
      nextPatch.hidden = patch.hidden;
    }
    return nextPatch;
  };

  const applyPasteResult = (result: {
    project: ComposerProject;
    selectedId: string | null;
    selectedObjectIds: string[];
  }) => {
    setProject(result.project);
    setSelectedCells([]);
    setSelectedObjectIds(result.selectedObjectIds);
    composer.setSelectedId(result.selectedId);
  };

  const updateSelectedPanel = (patch: Partial<ComposerPanel>) => {
    if (!selectedPanel) {
      return;
    }
    setProject({
      ...composer.project,
      panels: composer.project.panels.map((item) =>
        item.id === selectedPanel.id
          ? {
              ...item,
              ...filterLockedPanelPatch(patch),
            }
          : item,
      ),
    });
  };

  const updateSelectedText = (patch: Partial<ComposerText>) => {
    if (!selectedText) {
      return;
    }
    setProject({
      ...composer.project,
      texts: composer.project.texts.map((item) =>
        item.id === selectedText.id
          ? {
              ...item,
              ...filterLockedTextPatch(patch),
            }
          : item,
      ),
    });
  };

  const mergeSelectedEmptyCells = () => {
    try {
      const next = mergeCellsIntoFreeRegion(composer.project, selectedCells);
      setProject(next);
      const newRegion = next.regions[next.regions.length - 1] ?? null;
      if (newRegion) {
        composer.setSelectedId(newRegion.id);
      }
      setSelectedCells([]);
      setSelectedObjectIds([]);
      setDropNotice("空白格已合并成自由布局区域。");
    } catch (error) {
      setDropNotice(getErrorMessage(error));
    }
  };

  const unmergeSelectedRegion = () => {
    if (!selectedRegion || selectedRegion.kind !== "free") {
      return;
    }
    setProject(removeRegion(composer.project, selectedRegion.id));
    composer.setSelectedId(null);
    setSelectedObjectIds([]);
    setDropNotice("自由区域已拆回单格。");
  };

  const applyBinding = (value: string) => {
    const targetRect =
      value === "none"
        ? null
        : value.startsWith("slot:")
          ? regionSlotRect(composer.project, findRegion(composer.project, value.slice(5))!)
          : regionRect(composer.project, findRegion(composer.project, value.slice(7))!);

    if (selectedPanel) {
      if (value === "none") {
        updateSelectedPanel({ region_id: null, slot_id: null });
        return;
      }
      if (!targetRect) {
        return;
      }
      updateSelectedPanel({
        ...centerObjectInRect(selectedPanel, targetRect),
        region_id: value.startsWith("slot:") ? value.slice(5) : value.slice(7),
        slot_id: value.startsWith("slot:")
          ? regionSlotId(findRegion(composer.project, value.slice(5))!)
          : null,
      });
      return;
    }
    if (selectedText) {
      if (value === "none") {
        updateSelectedText({ region_id: null, slot_id: null });
        return;
      }
      if (!targetRect) {
        return;
      }
      updateSelectedText({
        ...centerObjectInRect(selectedText, targetRect),
        region_id: value.startsWith("slot:") ? value.slice(5) : value.slice(7),
        slot_id: value.startsWith("slot:")
          ? regionSlotId(findRegion(composer.project, value.slice(5))!)
          : null,
      });
    }
  };

  const fitSelectedPanelToBinding = () => {
    if (!selectedPanel) {
      return;
    }
    const region =
      selectedPanel.region_id != null
        ? findRegion(composer.project, selectedPanel.region_id)
        : null;
    if (!region) {
      return;
    }
    const targetRect = selectedPanel.slot_id
      ? regionSlotRect(composer.project, region)
      : regionRect(composer.project, region);
    if (!targetRect) {
      return;
    }
    updateSelectedPanel(fitPanelToRect(selectedPanel, targetRect));
  };

  const placeSelectedDrawableInBinding = (
    mode: "top" | "middle" | "bottom" | "center" | "left" | "hcenter" | "right",
  ) => {
    if (selectedPanel) {
      const targetRect = boundRectForDrawable(composer.project, selectedPanel);
      if (!targetRect) {
        return;
      }
      setProject(placeDrawableInRect(composer.project, selectedPanel.id, targetRect, mode));
      return;
    }
    if (selectedText) {
      const targetRect = boundRectForDrawable(composer.project, selectedText);
      if (!targetRect) {
        return;
      }
      setProject(placeDrawableInRect(composer.project, selectedText.id, targetRect, mode));
    }
  };

  const updateSelectedDrawableFlags = (patch: {
    locked?: boolean;
    hidden?: boolean;
  }) => {
    if (selectedObjectIds.length === 0) {
      return;
    }
    const targetIds = new Set(selectedObjectIds);
    const nextProject = normalizeComposerProject({
      ...composer.project,
      panels: composer.project.panels.map((panel) =>
        targetIds.has(panel.id)
          ? {
              ...panel,
              ...patch,
            }
          : panel,
      ),
      texts: composer.project.texts.map((text) =>
        targetIds.has(text.id)
          ? {
              ...text,
              ...patch,
            }
          : text,
      ),
    });
    setProject(nextProject);
    if (patch.hidden === true) {
      setDropNotice(`已隐藏 ${selectedObjectIds.length} 个选中对象。`);
    } else if (patch.hidden === false) {
      setDropNotice(`已显示 ${selectedObjectIds.length} 个选中对象。`);
    } else if (patch.locked === true) {
      setDropNotice(`已锁定 ${selectedObjectIds.length} 个选中对象。`);
    } else if (patch.locked === false) {
      setDropNotice(`已解锁 ${selectedObjectIds.length} 个选中对象。`);
    }
  };

  const copySelection = () => {
    const clipboard = buildComposerClipboard(
      composer.project,
      selectedRegion?.id ?? null,
      selectedObjectIds,
    );
    if (!clipboard) {
      return;
    }
    clipboardRef.current = clipboard;
    setClipboardReady(true);
    setDropNotice("已复制当前选中对象，可继续粘贴或重复。");
  };

  const pasteSelection = () => {
    if (!clipboardRef.current) {
      return;
    }
    try {
      applyPasteResult(pasteComposerClipboard(composer.project, clipboardRef.current));
      setDropNotice("已粘贴对象副本。");
    } catch (error) {
      setDropNotice(getErrorMessage(error));
    }
  };

  const duplicateSelection = () => {
    if (!hasSelection) {
      return;
    }
    try {
      applyPasteResult(
        duplicateComposerSelection(composer.project, selectedRegion?.id ?? null, selectedObjectIds),
      );
      setDropNotice("已创建选中对象副本。");
    } catch (error) {
      setDropNotice(getErrorMessage(error));
    }
  };

  const groupCurrentSelection = () => {
    if (!canGroupSelection) {
      return;
    }
    const nextProject = groupDrawables(composer.project, selectedObjectIds);
    const nextSelection = expandSelectionWithGroups(nextProject, selectedObjectIds);
    setProject(nextProject);
    setSelectedObjectIds(nextSelection);
    composer.setSelectedId(nextSelection[nextSelection.length - 1] ?? null);
    setDropNotice("已把选中自由对象编成一组。");
  };

  const ungroupCurrentSelection = () => {
    if (!canUngroupSelection) {
      return;
    }
    const nextProject = ungroupDrawables(composer.project, selectedObjectIds);
    setProject(nextProject);
    setSelectedObjectIds(selectedObjectIds);
    composer.setSelectedId(selectedObjectIds[selectedObjectIds.length - 1] ?? null);
    setDropNotice("已解组当前选中对象。");
  };

  const duplicateDrawableForDrag = (id: string) => {
    try {
      const sourceIds = selectedObjectIds.includes(id)
        ? selectedObjectIds
        : expandSelectionWithGroups(composer.project, [id]);
      const result = duplicateComposerSelection(composer.project, null, sourceIds, {
        freeOffsetMm: 0,
      });
      flushSync(() => {
        applyPasteResult(result);
      });
      return result.selectedObjectIds[0] ?? null;
    } catch (error) {
      setDropNotice(getErrorMessage(error));
      return null;
    }
  };

  const removeSelected = () => {
    if (selectedObjectIds.length > 1) {
      let nextProject = composer.project;
      for (const id of selectedObjectIds) {
        const panel = nextProject.panels.find((item) => item.id === id);
        if (panel) {
          if (panel.kind === "graph" && panel.region_id) {
            const withoutRegion = removeRegion(nextProject, panel.region_id);
            nextProject = normalizeComposerProject({
              ...withoutRegion,
              panels: withoutRegion.panels.filter((item) => item.id !== panel.id),
            });
          } else {
            nextProject = normalizeComposerProject({
              ...nextProject,
              panels: nextProject.panels.filter((item) => item.id !== panel.id),
            });
          }
          continue;
        }
        nextProject = normalizeComposerProject({
          ...nextProject,
          texts: nextProject.texts.filter((item) => item.id !== id),
        });
      }
      setProject(nextProject);
      setSelectedObjectIds([]);
      composer.setSelectedId(null);
      return;
    }

    if (selectedRegion) {
      if (selectedRegion.kind === "free") {
        unmergeSelectedRegion();
      }
      return;
    }
    if (selectedPanel) {
      if (selectedPanel.kind === "graph" && selectedPanel.region_id) {
        const nextProject = removeRegion(composer.project, selectedPanel.region_id);
        setProject({
          ...nextProject,
          panels: nextProject.panels.filter((item) => item.id !== selectedPanel.id),
        });
      } else {
        composer.updatePanels(composer.project.panels.filter((item) => item.id !== selectedPanel.id));
      }
      composer.setSelectedId(null);
      setSelectedObjectIds([]);
      return;
    }
    if (selectedText) {
      composer.updateTexts(composer.project.texts.filter((item) => item.id !== selectedText.id));
      composer.setSelectedId(null);
      setSelectedObjectIds([]);
    }
  };

  const saveComposerProject = async () => {
    const path = await readSavePath({
      defaultPath: "codegod-composer-v2.plotproject.json",
      filters: [{ name: "CodeGod Project", extensions: ["json"] }],
    });
    if (!path) {
      return;
    }

    await runComposerTask(async () => {
      await saveProject(path, {
        version: 2,
        mode: "composer",
        project: composer.project,
      });
      rememberProject({
        mode: "composer",
        kind: "project",
        path,
        title: path.split(/[/\\]/).pop() ?? path,
        detail: `Composer v2 项目 · ${composer.project.panels.length} 个对象`,
      });
      setDropNotice("Composer v2 项目已保存。");
    });
  };

  const openComposerProject = async () => {
    const path = (await readDialogPaths({
      multiple: false,
      filters: [{ name: "CodeGod Project", extensions: ["json"] }],
    }, 1))[0];
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
        detail: `Composer v2 项目 · ${project.panels.length} 个对象 / ${project.regions.length} 个区域`,
      });
      setDropNotice("项目已加载，可以继续区域化排版。");
      setSelectedCells([]);
      setSelectedObjectIds([]);
      composer.setSelectedId(null);
    });
  };

  const exportComposer = async () => {
    await runComposerTask(async () => {
      const response = await composeExport(composer.project);
      setExportPath(response.output_path);
      setDropNotice("已导出 Illustrator 友好的可编辑 PDF。");
    });
  };

  const changeLayer = (action: "forward" | "backward" | "front" | "back") => {
    if (selectedPanel) {
      setProject(reorderDrawable(composer.project, selectedPanel.id, "panel", action));
      return;
    }
    if (selectedText) {
      setProject(reorderDrawable(composer.project, selectedText.id, "text", action));
    }
  };

  const cropValue = selectedPanel?.crop_rect ?? { x: 0, y: 0, width: 1, height: 1 };
  const selectedDrawableBinding = selectedPanel
    ? bindingValueForDrawable(selectedPanel)
    : selectedText
      ? bindingValueForDrawable(selectedText)
      : "none";

  const selectComposerItem = (id: string | null, additive = false) => {
    if (id == null) {
      composer.setSelectedId(null);
      setSelectedCells([]);
      setSelectedObjectIds([]);
      return;
    }

    const region = composer.project.regions.find((item) => item.id === id);
    if (region) {
      composer.setSelectedId(region.id);
      setSelectedCells([]);
      setSelectedObjectIds([]);
      return;
    }

    setSelectedCells([]);
    const groupedIds = expandSelectionWithGroups(composer.project, [id]);
    if (!additive) {
      composer.setSelectedId(groupedIds[groupedIds.length - 1] ?? id);
      setSelectedObjectIds(groupedIds);
      return;
    }

    const next = groupedIds.every((groupedId) => selectedObjectIds.includes(groupedId))
      ? selectedObjectIds.filter((item) => !groupedIds.includes(item))
      : expandSelectionWithGroups(composer.project, [...selectedObjectIds, ...groupedIds]);
    setSelectedObjectIds(next);
    composer.setSelectedId(next.length > 0 ? next[next.length - 1] : null);
  };

  const selectComposerObjects = (ids: string[], additive = false) => {
    const known = ids.filter(
      (id) =>
        composer.project.panels.some((item) => item.id === id) ||
        composer.project.texts.some((item) => item.id === id),
    );

    if (known.length === 0) {
      if (!additive) {
        selectComposerItem(null);
      }
      return;
    }

    setSelectedCells([]);
    if (!additive) {
      const expanded = expandSelectionWithGroups(composer.project, known);
      setSelectedObjectIds(expanded);
      composer.setSelectedId(expanded[expanded.length - 1] ?? null);
      return;
    }

    const merged = expandSelectionWithGroups(
      composer.project,
      Array.from(new Set([...selectedObjectIds, ...known])),
    );
    setSelectedObjectIds(merged);
    composer.setSelectedId(merged[merged.length - 1] ?? null);
  };

  const runAlignment = (mode: Parameters<typeof alignDrawables>[2]) => {
    setProject(alignDrawables(composer.project, selectedObjectIds, mode));
  };

  const runDistribution = (axis: Parameters<typeof distributeDrawables>[2]) => {
    setProject(distributeDrawables(composer.project, selectedObjectIds, axis));
  };

  useEffect(() => {
    function handleKeydown(event: KeyboardEvent) {
      const target = event.target as HTMLElement | null;
      const tagName = target?.tagName ?? "";
      if (
        target?.isContentEditable ||
        tagName === "INPUT" ||
        tagName === "TEXTAREA" ||
        tagName === "SELECT"
      ) {
        return;
      }

      if (event.key === "Escape") {
        selectComposerItem(null);
        return;
      }

      const shortcut = event.metaKey || event.ctrlKey;
      const shortcutKey = event.key.toLowerCase();
      if (shortcut && shortcutKey === "c" && canCopySelection) {
        event.preventDefault();
        copySelection();
        return;
      }
      if (shortcut && shortcutKey === "v" && canPasteSelection) {
        event.preventDefault();
        pasteSelection();
        return;
      }
      if (shortcut && shortcutKey === "d" && hasSelection) {
        event.preventDefault();
        duplicateSelection();
        return;
      }
      if (shortcut && !event.shiftKey && shortcutKey === "g" && canGroupSelection) {
        event.preventDefault();
        groupCurrentSelection();
        return;
      }
      if (shortcut && event.shiftKey && shortcutKey === "g" && canUngroupSelection) {
        event.preventDefault();
        ungroupCurrentSelection();
        return;
      }

      if ((event.key === "Backspace" || event.key === "Delete") && (selectedObjectIds.length > 0 || selectedRegion)) {
        event.preventDefault();
        removeSelected();
        return;
      }

      const deltaByKey: Record<string, { dx: number; dy: number }> = {
        ArrowLeft: { dx: -1, dy: 0 },
        ArrowRight: { dx: 1, dy: 0 },
        ArrowUp: { dx: 0, dy: -1 },
        ArrowDown: { dx: 0, dy: 1 },
      };
      const delta = deltaByKey[event.key];
      if (!delta) {
        return;
      }

      if (selectedObjectIds.length === 0) {
        if (selectedRegion) {
          event.preventDefault();
          setProject(
            moveRegion(
              composer.project,
              selectedRegion.id,
              selectedRegion.col + delta.dx,
              selectedRegion.row + delta.dy,
            ),
          );
        }
        return;
      }

      event.preventDefault();
      const graphIds = selectedObjectIds.filter((id) =>
        composer.project.panels.some((panel) => panel.id === id && panel.kind === "graph"),
      );
      const freeIds = selectedObjectIds.filter((id) => !graphIds.includes(id));

      let nextProject = composer.project;
      if (freeIds.length > 0) {
        const step = event.shiftKey ? 2 : 0.5;
        nextProject = nudgeDrawables(nextProject, freeIds, delta.dx * step, delta.dy * step);
      }
      if (graphIds.length > 0) {
        nextProject = moveGraphSelectionByCells(nextProject, graphIds, delta.dx, delta.dy);
      }
      setProject(nextProject);
    }

    window.addEventListener("keydown", handleKeydown);
    return () => {
      window.removeEventListener("keydown", handleKeydown);
    };
  }, [
    canCopySelection,
    canGroupSelection,
    canPasteSelection,
    composer.project,
    copySelection,
    duplicateSelection,
    groupCurrentSelection,
    hasSelection,
    pasteSelection,
    removeSelected,
    selectedObjectIds,
    selectedRegion,
    canUngroupSelection,
    ungroupCurrentSelection,
  ]);

  return (
    <div className="desk-layout">
      <section className="desk-main">
        <article className="work-card canvas-shell-card">
          <div className="section-head">
            <div>
              <div className="card-kicker">拼图</div>
              <h2>拼版、调整并导出单页 PDF</h2>
              <p>Graph PDF 会按标准尺寸落位，其他素材和文字可以继续自由排版。</p>
            </div>
            <div className="metric-strip">
              <div className="metric-chip">
                <span>布局区</span>
                <strong>180 x 165 mm</strong>
              </div>
              <div className="metric-chip">
                <span>Region / 对象</span>
                <strong>
                  {composer.project.regions.length} / {composer.project.panels.length + composer.project.texts.length}
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
              导出可编辑 PDF
            </button>
          </div>

          <div className="composer-main">
            <div className={`composer-drop-overlay ${dropActive ? "visible" : ""}`}>
              <div className="composer-drop-card">
                <strong>松开即可导入</strong>
                <span>
                  {pdfImportMode === "graph"
                    ? "60x55 / 120x55 / 60x110 的 CodeGod PDF 会自动占格，其他 PDF 请切到素材模式。"
                    : "PDF、图片都会作为自由素材导入，可裁边、吸附、叠放并导出为可编辑 PDF。"}
                </span>
              </div>
            </div>

            <ComposerCanvas
              highlightRegionIds={selectedHighlightRegionIds}
              project={composer.project}
              selectedCells={selectedCells}
              selectedId={composer.selectedId}
              selectedObjectIds={selectedObjectIds}
              thumbnails={thumbnailMap}
              onDuplicateDrawableStart={duplicateDrawableForDrag}
              onObjectSelection={selectComposerObjects}
              onProjectChange={setProject}
              onSelect={selectComposerItem}
              onSelectedCellsChange={(cells, options) => {
                setSelectedCells(uniqueCells(cells));
                if (options?.preserveSelection) {
                  return;
                }
                composer.setSelectedId(null);
                setSelectedObjectIds([]);
              }}
            />

            {composer.project.panels.length === 0 && !busy && (
              <div className="composer-empty-state">
                <strong>先拖入图或素材开始拼图</strong>
                <span>
                  Graph PDF 会自动占据标准格区；其他 PDF、图片和文字都可以在格内自由布局，并保留可编辑导出。
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
              <p>切换导入方式、快速生成预设布局，或保存当前项目。</p>
            </div>
          </div>

          <div className="mode-switch">
            <button
              className={`mode-button ${pdfImportMode === "graph" ? "active" : ""}`}
              onClick={() => setPdfImportMode("graph")}
              type="button"
            >
              PDF 作为 Graph
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
            <button
              className="ghost-button"
              disabled={!canCopySelection}
              onClick={copySelection}
              type="button"
            >
              复制选中
            </button>
            <button
              className="ghost-button"
              disabled={!canPasteSelection}
              onClick={pasteSelection}
              type="button"
            >
              粘贴副本
            </button>
            <button
              className="ghost-button"
              disabled={!hasSelection}
              onClick={duplicateSelection}
              type="button"
            >
              重复选中
            </button>
            <button
              className="ghost-button"
              disabled={selectedCells.length < 2}
              onClick={mergeSelectedEmptyCells}
              type="button"
            >
              合并选中空格
            </button>
            <button
              className="ghost-button"
              disabled={!selectedRegion || selectedRegion.kind !== "free"}
              onClick={unmergeSelectedRegion}
              type="button"
            >
              拆分自由区域
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
                {hasSelection
                  ? "当前选中对象或区域的可编辑项。"
                  : "先选中区域、图或文字，再在这里调整属性。"}
              </p>
            </div>
          </div>

          {!hasSelection && (
            <div className="placeholder-card">
              还没有选中对象。点击 graph、素材、文字，或者按住 Shift 选空白格后合并成区域。
            </div>
          )}

          {multiSelectedItems.length > 1 && (
            <div className="inspector-stack">
              <div className="info-grid compact-grid">
                <div className="stat-tile">
                  <span>多选对象</span>
                  <strong>{multiSelectedItems.length}</strong>
                </div>
                <div className="stat-tile">
                  <span>可对齐对象</span>
                  <strong>{selectedEditableIds.length}</strong>
                </div>
                <div className="stat-tile">
                  <span>绑定区域</span>
                  <strong>{selectedHighlightRegionIds.length}</strong>
                </div>
                <div className="stat-tile">
                  <span>对象组</span>
                  <strong>{selectedGroupIds.length}</strong>
                </div>
              </div>

              <div className="hint-text">
                Shift 可继续增减选择；同组对象会一起被选中。方向键微调自由对象，Graph 仍按整格移动。对齐和分布只会作用于 asset / text。
              </div>

              <div className="stacked-actions">
                <button
                  className="ghost-button"
                  disabled={!canGroupSelection}
                  onClick={groupCurrentSelection}
                  type="button"
                >
                  成组
                </button>
                <button
                  className="ghost-button"
                  disabled={!canUngroupSelection}
                  onClick={ungroupCurrentSelection}
                  type="button"
                >
                  解组
                </button>
                <button
                  className="ghost-button"
                  disabled={selectedEditableIds.length < 2}
                  onClick={() => runAlignment("left")}
                  type="button"
                >
                  左对齐
                </button>
                <button
                  className="ghost-button"
                  disabled={selectedEditableIds.length < 2}
                  onClick={() => runAlignment("center")}
                  type="button"
                >
                  水平居中
                </button>
                <button
                  className="ghost-button"
                  disabled={selectedEditableIds.length < 2}
                  onClick={() => runAlignment("right")}
                  type="button"
                >
                  右对齐
                </button>
                <button
                  className="ghost-button"
                  disabled={selectedEditableIds.length < 2}
                  onClick={() => runAlignment("top")}
                  type="button"
                >
                  上对齐
                </button>
                <button
                  className="ghost-button"
                  disabled={selectedEditableIds.length < 2}
                  onClick={() => runAlignment("middle")}
                  type="button"
                >
                  垂直居中
                </button>
                <button
                  className="ghost-button"
                  disabled={selectedEditableIds.length < 2}
                  onClick={() => runAlignment("bottom")}
                  type="button"
                >
                  下对齐
                </button>
                <button
                  className="ghost-button"
                  disabled={selectedEditableIds.length < 3}
                  onClick={() => runDistribution("horizontal")}
                  type="button"
                >
                  水平分布
                </button>
                <button
                  className="ghost-button"
                  disabled={selectedEditableIds.length < 3}
                  onClick={() => runDistribution("vertical")}
                  type="button"
                >
                  垂直分布
                </button>
              </div>

              <button className="ghost-button danger-button" onClick={removeSelected} type="button">
                删除选中对象
              </button>
            </div>
          )}

          {selectedRegion && (
            <div className="inspector-stack">
              <div className="info-grid compact-grid">
                <div className="stat-tile">
                  <span>类型</span>
                  <strong>{selectedRegion.kind === "graph" ? "Graph Region" : "Free Region"}</strong>
                </div>
                <div className="stat-tile">
                  <span>占格</span>
                  <strong>
                    {selectedRegion.col_span} x {selectedRegion.row_span}
                  </strong>
                </div>
                <div className="stat-tile">
                  <span>结构位</span>
                  <strong>{selectedRegion.slot_kind === "structure" ? "有" : "无"}</strong>
                </div>
              </div>

              <div className="hint-text">
                {selectedRegion.kind === "graph"
                  ? "Graph region 只能整格移动，尺寸由契约 PDF 自动决定；方向键同样按整格移动。"
                  : "Free region 只占格，不会直接导出；你可以把素材和文字吸附到里面，也能用方向键整格移动。"}
              </div>

              <label className="toggle-field">
                <input
                  checked={Boolean(selectedRegion.locked)}
                  onChange={(event) =>
                    setProject({
                      ...composer.project,
                      regions: composer.project.regions.map((region) =>
                        region.id === selectedRegion.id
                          ? { ...region, locked: event.target.checked }
                          : region,
                      ),
                    })
                  }
                  type="checkbox"
                />
                <span>锁定区域移动</span>
              </label>

              {selectedRegion.kind === "free" && (
                <button className="ghost-button danger-button" onClick={unmergeSelectedRegion} type="button">
                  拆分这个区域
                </button>
              )}
            </div>
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
                  <strong>{selectedPanelLabel || selectedPanel.label || "-"}</strong>
                </div>
                <div className="stat-tile">
                  <span>位置</span>
                  <strong>{describePanelSlot(selectedPanel, composer.project)}</strong>
                </div>
                <div className="stat-tile">
                  <span>层级</span>
                  <strong>{selectedPanel.z_index + 1}</strong>
                </div>
              </div>

              <label>
                <span className="field-label">自定义标签</span>
                <input
                  className="field"
                  disabled={composer.project.auto_labels && selectedPanel.kind === "graph"}
                  onChange={(event) =>
                    updateSelectedPanel({ label: event.target.value || null })
                  }
                  type="text"
                  value={selectedPanel.label ?? ""}
                />
              </label>

              {selectedPanel.kind === "asset" ? (
                <label>
                  <span className="field-label">绑定区域</span>
                  <select
                    className="field"
                    onChange={(event) => applyBinding(event.target.value)}
                    value={selectedDrawableBinding}
                  >
                    <option value="none">无</option>
                    {freeRegions.map((region) => (
                      <option key={region.id} value={`region:${region.id}`}>
                        Free Region {region.id}
                      </option>
                    ))}
                    {slotRegions.map((region) => (
                      <option key={`${region.id}:slot`} value={`slot:${region.id}`}>
                        Structure Slot {region.id}
                      </option>
                    ))}
                  </select>
                </label>
              ) : (
                <div className="hint-text">
                  Graph panel 绑定到 region：{selectedPanel.region_id ?? "未绑定"}
                </div>
              )}

              <label className="toggle-field">
                <input
                  checked={Boolean(selectedPanel.locked)}
                  onChange={(event) => updateSelectedPanel({ locked: event.target.checked })}
                  type="checkbox"
                />
                <span>锁定位置</span>
              </label>

              <label className="toggle-field">
                <input
                  checked={Boolean(selectedPanel.hidden)}
                  onChange={(event) => updateSelectedPanel({ hidden: event.target.checked })}
                  type="checkbox"
                />
                <span>隐藏对象（预览和导出都忽略）</span>
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

              {selectedPanel.kind === "asset" && (
                <div className="stacked-actions">
                  <button className="ghost-button" onClick={fitSelectedPanelToBinding} type="button">
                    适配到绑定区域
                  </button>
                  <button
                    className="ghost-button"
                    disabled={!boundRectForDrawable(composer.project, selectedPanel)}
                    onClick={() => placeSelectedDrawableInBinding("left")}
                    type="button"
                  >
                    贴到区域左侧
                  </button>
                  <button
                    className="ghost-button"
                    disabled={!boundRectForDrawable(composer.project, selectedPanel)}
                    onClick={() => placeSelectedDrawableInBinding("hcenter")}
                    type="button"
                  >
                    水平居中到区域
                  </button>
                  <button
                    className="ghost-button"
                    disabled={!boundRectForDrawable(composer.project, selectedPanel)}
                    onClick={() => placeSelectedDrawableInBinding("right")}
                    type="button"
                  >
                    贴到区域右侧
                  </button>
                  <button
                    className="ghost-button"
                    disabled={!boundRectForDrawable(composer.project, selectedPanel)}
                    onClick={() => placeSelectedDrawableInBinding("top")}
                    type="button"
                  >
                    贴到区域顶部
                  </button>
                  <button
                    className="ghost-button"
                    disabled={!boundRectForDrawable(composer.project, selectedPanel)}
                    onClick={() => placeSelectedDrawableInBinding("middle")}
                    type="button"
                  >
                    吸附到区域中线
                  </button>
                  <button
                    className="ghost-button"
                    disabled={!boundRectForDrawable(composer.project, selectedPanel)}
                    onClick={() => placeSelectedDrawableInBinding("bottom")}
                    type="button"
                  >
                    贴到区域底部
                  </button>
                  <button
                    className="ghost-button"
                    disabled={!boundRectForDrawable(composer.project, selectedPanel)}
                    onClick={() => placeSelectedDrawableInBinding("center")}
                    type="button"
                  >
                    完全居中到区域
                  </button>
                  <button className="ghost-button" onClick={() => changeLayer("forward")} type="button">
                    上移一层
                  </button>
                  <button className="ghost-button" onClick={() => changeLayer("backward")} type="button">
                    下移一层
                  </button>
                  <button className="ghost-button" onClick={() => changeLayer("front")} type="button">
                    置于最前
                  </button>
                  <button className="ghost-button" onClick={() => changeLayer("back")} type="button">
                    置于最后
                  </button>
                </div>
              )}

              <div className="info-grid compact-grid">
                <label>
                  <span className="field-label">裁边 X %</span>
                  <input
                    className="field"
                    max={95}
                    min={0}
                    onChange={(event) =>
                      updateSelectedPanel({
                        crop_rect: {
                          ...cropValue,
                          x: Number(event.target.value) / 100,
                        },
                      })
                    }
                    type="number"
                    value={Math.round(cropValue.x * 100)}
                  />
                </label>
                <label>
                  <span className="field-label">裁边 Y %</span>
                  <input
                    className="field"
                    max={95}
                    min={0}
                    onChange={(event) =>
                      updateSelectedPanel({
                        crop_rect: {
                          ...cropValue,
                          y: Number(event.target.value) / 100,
                        },
                      })
                    }
                    type="number"
                    value={Math.round(cropValue.y * 100)}
                  />
                </label>
                <label>
                  <span className="field-label">裁框 W %</span>
                  <input
                    className="field"
                    max={100}
                    min={1}
                    onChange={(event) =>
                      updateSelectedPanel({
                        crop_rect: {
                          ...cropValue,
                          width: Number(event.target.value) / 100,
                        },
                      })
                    }
                    type="number"
                    value={Math.round(cropValue.width * 100)}
                  />
                </label>
                <label>
                  <span className="field-label">裁框 H %</span>
                  <input
                    className="field"
                    max={100}
                    min={1}
                    onChange={(event) =>
                      updateSelectedPanel({
                        crop_rect: {
                          ...cropValue,
                          height: Number(event.target.value) / 100,
                        },
                      })
                    }
                    type="number"
                    value={Math.round(cropValue.height * 100)}
                  />
                </label>
              </div>

              <div className="hint-text">
                {selectedPanel.kind === "graph"
                  ? "Graph panel 只允许整格移动，不允许脱格自由缩放；可用 crop 做非破坏性裁边。"
                  : "Asset 可自由移动、缩放、裁边，并允许覆盖 graph；绑定到 region/slot 后会跟随区域一起移动，也能一键贴左/中/右/顶/底。"}
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

              <label>
                <span className="field-label">绑定区域</span>
                <select
                  className="field"
                  onChange={(event) => applyBinding(event.target.value)}
                  value={selectedDrawableBinding}
                >
                  <option value="none">无</option>
                  {freeRegions.map((region) => (
                    <option key={region.id} value={`region:${region.id}`}>
                      Free Region {region.id}
                    </option>
                  ))}
                  {slotRegions.map((region) => (
                    <option key={`${region.id}:slot`} value={`slot:${region.id}`}>
                      Structure Slot {region.id}
                    </option>
                  ))}
                </select>
              </label>

              <label className="toggle-field">
                <input
                  checked={Boolean(selectedText.locked)}
                  onChange={(event) => updateSelectedText({ locked: event.target.checked })}
                  type="checkbox"
                />
                <span>锁定位置</span>
              </label>

              <label className="toggle-field">
                <input
                  checked={Boolean(selectedText.hidden)}
                  onChange={(event) => updateSelectedText({ hidden: event.target.checked })}
                  type="checkbox"
                />
                <span>隐藏文字（预览和导出都忽略）</span>
              </label>

              <div className="stacked-actions">
                <button
                  className="ghost-button"
                  disabled={!boundRectForDrawable(composer.project, selectedText)}
                  onClick={() => placeSelectedDrawableInBinding("left")}
                  type="button"
                >
                  贴到区域左侧
                </button>
                <button
                  className="ghost-button"
                  disabled={!boundRectForDrawable(composer.project, selectedText)}
                  onClick={() => placeSelectedDrawableInBinding("hcenter")}
                  type="button"
                >
                  水平居中到区域
                </button>
                <button
                  className="ghost-button"
                  disabled={!boundRectForDrawable(composer.project, selectedText)}
                  onClick={() => placeSelectedDrawableInBinding("right")}
                  type="button"
                >
                  贴到区域右侧
                </button>
                <button
                  className="ghost-button"
                  disabled={!boundRectForDrawable(composer.project, selectedText)}
                  onClick={() => placeSelectedDrawableInBinding("top")}
                  type="button"
                >
                  贴到区域顶部
                </button>
                <button
                  className="ghost-button"
                  disabled={!boundRectForDrawable(composer.project, selectedText)}
                  onClick={() => placeSelectedDrawableInBinding("middle")}
                  type="button"
                >
                  吸附到区域中线
                </button>
                <button
                  className="ghost-button"
                  disabled={!boundRectForDrawable(composer.project, selectedText)}
                  onClick={() => placeSelectedDrawableInBinding("bottom")}
                  type="button"
                >
                  贴到区域底部
                </button>
                <button
                  className="ghost-button"
                  disabled={!boundRectForDrawable(composer.project, selectedText)}
                  onClick={() => placeSelectedDrawableInBinding("center")}
                  type="button"
                >
                  完全居中到区域
                </button>
                <button className="ghost-button" onClick={() => changeLayer("forward")} type="button">
                  上移一层
                </button>
                <button className="ghost-button" onClick={() => changeLayer("backward")} type="button">
                  下移一层
                </button>
                <button className="ghost-button" onClick={() => changeLayer("front")} type="button">
                  置于最前
                </button>
                <button className="ghost-button" onClick={() => changeLayer("back")} type="button">
                  置于最后
                </button>
              </div>

              <button className="ghost-button danger-button" onClick={removeSelected} type="button">
                删除文字
              </button>
            </div>
          )}
        </article>

        <article className="context-card">
          <div className="context-card-head">
            <div>
              <h3>图层与区域</h3>
              <p>这里列出占位区域和导出对象，方便选中、排序和批量处理。</p>
            </div>
          </div>

          <div className="context-list">
            <div className="context-row">
              <span>基础格</span>
              <strong>60 x 55 mm</strong>
            </div>
            <div className="context-row">
              <span>结构位</span>
              <strong>{slotRegions.length}</strong>
            </div>
            <div className="context-row">
              <span>预检状态</span>
              <strong>{composer.validationError ? "有提醒" : "正常"}</strong>
            </div>
            <div className="context-row">
              <span>快捷键</span>
              <strong>Shift 复选 / Alt 拖拽复制 / Cmd-C,V,D,G / 方向键</strong>
            </div>
          </div>

          {selectedObjectIds.length > 0 && (
            <div className="inspector-stack">
              <div className="hint-text">
                当前图层多选：{selectedObjectIds.length} 个对象，其中 {selectedHiddenCount} 个已隐藏，{selectedLockedCount} 个已锁定。
              </div>
              <div className="stacked-actions">
                <button
                  className="ghost-button"
                  disabled={selectedLockedCount === multiSelectedItems.length}
                  onClick={() => updateSelectedDrawableFlags({ locked: true })}
                  type="button"
                >
                  锁定选中
                </button>
                <button
                  className="ghost-button"
                  disabled={selectedLockedCount === 0}
                  onClick={() => updateSelectedDrawableFlags({ locked: false })}
                  type="button"
                >
                  解锁选中
                </button>
                <button
                  className="ghost-button"
                  disabled={selectedHiddenCount === multiSelectedItems.length}
                  onClick={() => updateSelectedDrawableFlags({ hidden: true })}
                  type="button"
                >
                  隐藏选中
                </button>
                <button
                  className="ghost-button"
                  disabled={selectedHiddenCount === 0}
                  onClick={() => updateSelectedDrawableFlags({ hidden: false })}
                  type="button"
                >
                  显示选中
                </button>
              </div>
            </div>
          )}

          <div className="layer-list">
            {layerItems.length === 0 && (
              <div className="placeholder-card">还没有对象。导入 graph 或素材后，这里会出现区域和图层列表。</div>
            )}
            {layerItems.map((item) => (
              <button
                className={`layer-item ${
                  composer.selectedId === item.id || selectedObjectIds.includes(item.id) ? "active" : ""
                }`}
                key={item.id}
                onClick={(event) => {
                  if (item.type === "region") {
                    selectComposerItem(item.id, false);
                    return;
                  }
                  selectComposerItem(item.id, Boolean(event.shiftKey || event.metaKey));
                }}
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
          <div className={dropNotice.includes("仅支持") || dropNotice.includes("跳过") ? "warning-card" : "success-card"}>
            {dropNotice}
          </div>
        )}

        {exportPath && <div className="success-card">已导出：{exportPath}</div>}
      </aside>
    </div>
  );
}
