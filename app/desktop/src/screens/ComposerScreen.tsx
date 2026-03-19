import { useEffect, useMemo, useRef, useState } from "react";
import { flushSync } from "react-dom";
import { useShallow } from "zustand/react/shallow";

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
  distributeDrawables,
  duplicateComposerSelection,
  expandSelectionWithGroups,
  groupDrawables,
  mergeCellsIntoFreeRegion,
  nextTextId,
  nextZIndex,
  normalizeComposerProject,
  pasteComposerClipboard,
  placeDrawableInRect,
  removeRegion,
  reorderDrawable,
  ungroupDrawables,
  type ComposerClipboard,
} from "../lib/composer";
import { loadComposerProjectFile } from "../lib/project-io";
import { openDialog, saveDialog } from "../lib/tauri-dialog";
import { getCodeGodWebviewWindow } from "../lib/tauri-webview";
import type { ComposerPanel, ComposerProject, ComposerText } from "../lib/types";
import { useComposerStore, useWorkbenchStore } from "../lib/store";
import { getErrorMessage, toDialogPaths } from "../lib/workbench";
import { ComposerCanvasSection } from "./composer/ComposerCanvasSection";
import { ComposerInspectPanel } from "./composer/ComposerInspectPanel";
import { ComposerInsertPanel } from "./composer/ComposerInsertPanel";
import { ComposerLayersPanel } from "./composer/ComposerLayersPanel";
import { useComposerKeyboardShortcuts } from "./composer/useComposerKeyboardShortcuts";
import { useComposerPreview } from "./composer/useComposerPreview";
import { useComposerSelectionState } from "./composer/useComposerSelectionState";
import { usePanelThumbnails } from "./composer/usePanelThumbnails";
import {
  bindingRectForValue,
  bindingRegionId,
  bindingSlotIdForValue,
  bindingValueForDrawable,
  boundRectForDrawable,
  centerObjectInRect,
  describeSkippedFiles,
  fitPanelToRect,
  isPdfPath,
  isRasterPath,
  snapImportedAssetsIntoRegion,
  uniqueCells,
  type CellRef,
} from "./composer/utils";

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
  const [dropNoticeTone, setDropNoticeTone] = useState<"success" | "warning">("success");
  const [inspectorTab, setInspectorTab] = useState<"insert" | "inspect" | "layers">("insert");
  const [selectedCells, setSelectedCells] = useState<CellRef[]>([]);
  const [selectedObjectIds, setSelectedObjectIds] = useState<string[]>([]);
  const [clipboardReady, setClipboardReady] = useState(false);
  const projectRef = useRef(composer.project);
  const selectedRegionRef = useRef<string | null>(null);
  const clipboardRef = useRef<ComposerClipboard | null>(null);
  const keepInspectorTabRef = useRef(false);

  const visiblePanels = useMemo(
    () => composer.project.panels.filter((panel) => !panel.hidden),
    [composer.project.panels],
  );
  const thumbnailMap = usePanelThumbnails(visiblePanels);
  const {
    selectedPanel,
    selectedText,
    selectedRegion,
    selectedPanelLabel,
    selectedPanelPositionLocked,
    selectedTextPositionLocked,
    selectedEditableIds,
    hasSelection,
    selectedHighlightRegionIds,
    multiSelectedItems,
    selectedGroupIds,
    selectedHiddenCount,
    selectedLockedCount,
    canGroupSelection,
    canUngroupSelection,
    freeRegions,
    slotRegions,
    layerItems,
  } = useComposerSelectionState(composer.project, composer.selectedId, selectedObjectIds);

  const canCopySelection = hasSelection;
  const canPasteSelection = clipboardReady;
  const selectionSignature = selectedRegion
    ? `region:${selectedRegion.id}`
    : selectedObjectIds.slice().sort().join("|");
  const cropValue = selectedPanel?.crop_rect ?? { x: 0, y: 0, width: 1, height: 1 };
  const selectedDrawableBinding = selectedPanel
    ? bindingValueForDrawable(selectedPanel)
    : selectedText
      ? bindingValueForDrawable(selectedText)
      : "none";

  const showComposerNotice = (message: string, tone: "success" | "warning" = "success") => {
    setDropNotice(message);
    setDropNoticeTone(tone);
  };

  useEffect(() => {
    if (!selectionSignature) {
      keepInspectorTabRef.current = false;
      return;
    }
    if (keepInspectorTabRef.current) {
      keepInspectorTabRef.current = false;
      return;
    }
    if (inspectorTab !== "inspect") {
      setInspectorTab("inspect");
    }
  }, [selectionSignature]);

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
      const unsupported = cleaned.filter((path) => !isPdfPath(path) && !isRasterPath(path));

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
            nextProject = snapImportedAssetsIntoRegion(
              beforeRasters,
              nextProject,
              selectedRegionRef.current,
            );
          }
        }

        composer.setProject(normalizeComposerProject(nextProject));
        composer.setSelectedId(null);
        setSelectedCells([]);
        setSelectedObjectIds([]);

        const skippedNotice = describeSkippedFiles(unsupported);
        if (pdfs.length > 0 && rasters.length > 0) {
          showComposerNotice(
            [
              pdfImportMode === "graph"
                ? "Imported graph containers and free assets. Graph PDFs snapped into the standard grid."
                : "Imported PDF and raster assets. Free assets stay ready for layout, crop, and stacking.",
              skippedNotice,
            ]
              .filter(Boolean)
              .join(" "),
          );
        } else if (pdfs.length > 0) {
          showComposerNotice(
            [
              pdfImportMode === "graph"
                ? "Imported graph PDFs and assigned them to matching regions."
                : "Imported PDF assets for free placement.",
              skippedNotice,
            ]
              .filter(Boolean)
              .join(" "),
          );
        } else if (rasters.length > 0) {
          showComposerNotice(
            ["Imported free assets. Crop, snap, and layer them as needed.", skippedNotice]
              .filter(Boolean)
              .join(" "),
          );
        } else if (skippedNotice) {
          showComposerNotice(skippedNotice, "warning");
        }
      } catch (error) {
        showComposerNotice(getErrorMessage(error), "warning");
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
          showComposerNotice(getErrorMessage(error), "warning");
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
      showComposerNotice(getErrorMessage(error), "warning");
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
      showComposerNotice("Graph PDFs snapped into the 60 x 55 base grid.");
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
      showComposerNotice("Assets imported. They can float, crop, and overlap graph panels.");
    });
  };

  const quickThreeUp = async () => {
    const paths = await readDialogPaths(
      {
        multiple: true,
        filters: [{ name: "PDF", extensions: ["pdf"] }],
      },
      3,
    );
    if (paths.length === 0) {
      return;
    }

    await runComposerTask(async () => {
      const response = await threeUp(paths);
      applyImportedProject(response);
      showComposerNotice("Applied the region-based three-up preset.");
    });
  };

  const quickTwoUpEditorial = async () => {
    const paths = await readDialogPaths(
      {
        multiple: true,
        filters: [{ name: "PDF", extensions: ["pdf"] }],
      },
      2,
    );
    if (paths.length === 0) {
      return;
    }

    await runComposerTask(async () => {
      const response = await twoUpEditorial(paths);
      applyImportedProject(response);
      showComposerNotice("Applied the two-up layout with a free annotation region.");
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
      showComposerNotice("Merged the selected empty cells into one free layout region.");
    } catch (error) {
      showComposerNotice(getErrorMessage(error), "warning");
    }
  };

  const unmergeSelectedRegion = () => {
    if (!selectedRegion || selectedRegion.kind !== "free") {
      return;
    }
    setProject(removeRegion(composer.project, selectedRegion.id));
    composer.setSelectedId(null);
    setSelectedObjectIds([]);
    showComposerNotice("Split the free region back into individual cells.");
  };

  const applyBinding = (value: string) => {
    const targetRect = bindingRectForValue(composer.project, value);
    const regionId = bindingRegionId(value);
    const slotId = bindingSlotIdForValue(composer.project, value);

    if (selectedPanel) {
      if (value === "none") {
        updateSelectedPanel({ region_id: null, slot_id: null });
        return;
      }
      if (!targetRect || !regionId) {
        return;
      }
      updateSelectedPanel({
        ...centerObjectInRect(selectedPanel, targetRect),
        region_id: regionId,
        slot_id: slotId,
      });
      return;
    }

    if (selectedText) {
      if (value === "none") {
        updateSelectedText({ region_id: null, slot_id: null });
        return;
      }
      if (!targetRect || !regionId) {
        return;
      }
      updateSelectedText({
        ...centerObjectInRect(selectedText, targetRect),
        region_id: regionId,
        slot_id: slotId,
      });
    }
  };

  const fitSelectedPanelToBinding = () => {
    if (!selectedPanel) {
      return;
    }
    const targetRect = boundRectForDrawable(composer.project, selectedPanel);
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
      showComposerNotice(`Hidden ${selectedObjectIds.length} selected object(s).`);
    } else if (patch.hidden === false) {
      showComposerNotice(`Revealed ${selectedObjectIds.length} selected object(s).`);
    } else if (patch.locked === true) {
      showComposerNotice(`Locked ${selectedObjectIds.length} selected object(s).`);
    } else if (patch.locked === false) {
      showComposerNotice(`Unlocked ${selectedObjectIds.length} selected object(s).`);
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
    showComposerNotice("Copied the current selection. You can now paste or duplicate it.");
  };

  const pasteSelection = () => {
    if (!clipboardRef.current) {
      return;
    }
    try {
      applyPasteResult(pasteComposerClipboard(composer.project, clipboardRef.current));
      showComposerNotice("Pasted a duplicated selection.");
    } catch (error) {
      showComposerNotice(getErrorMessage(error), "warning");
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
      showComposerNotice("Created a duplicate of the current selection.");
    } catch (error) {
      showComposerNotice(getErrorMessage(error), "warning");
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
    showComposerNotice("Grouped the selected free objects.");
  };

  const ungroupCurrentSelection = () => {
    if (!canUngroupSelection) {
      return;
    }
    const nextProject = ungroupDrawables(composer.project, selectedObjectIds);
    setProject(nextProject);
    setSelectedObjectIds(selectedObjectIds);
    composer.setSelectedId(selectedObjectIds[selectedObjectIds.length - 1] ?? null);
    showComposerNotice("Ungrouped the current selection.");
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
      showComposerNotice(getErrorMessage(error), "warning");
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
        detail: `Composer v2 project · ${composer.project.panels.length} objects`,
      });
      showComposerNotice("Saved the Composer v2 project.");
    });
  };

  const openComposerProject = async () => {
    const path = (
      await readDialogPaths(
        {
          multiple: false,
          filters: [{ name: "CodeGod Project", extensions: ["json"] }],
        },
        1,
      )
    )[0];
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
        detail: `Composer v2 project · ${project.panels.length} objects / ${project.regions.length} regions`,
      });
      showComposerNotice("Loaded the project and restored the current layout.");
      setSelectedCells([]);
      setSelectedObjectIds([]);
      composer.setSelectedId(null);
    });
  };

  const exportComposer = async () => {
    await runComposerTask(async () => {
      const response = await composeExport(composer.project);
      setExportPath(response.output_path);
      showComposerNotice("Exported an editable PDF that stays Illustrator-friendly.");
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

  const selectComposerItem = (
    id: string | null,
    additive = false,
    source: "canvas" | "layers" | "other" = "other",
  ) => {
    keepInspectorTabRef.current = source === "layers" && additive;
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
    keepInspectorTabRef.current = false;
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

  useComposerKeyboardShortcuts({
    canCopySelection,
    canPasteSelection,
    canGroupSelection,
    canUngroupSelection,
    hasSelection,
    project: composer.project,
    selectedObjectIds,
    selectedRegion,
    onCopySelection: copySelection,
    onPasteSelection: pasteSelection,
    onDuplicateSelection: duplicateSelection,
    onGroupCurrentSelection: groupCurrentSelection,
    onUngroupCurrentSelection: ungroupCurrentSelection,
    onRemoveSelected: removeSelected,
    onSelectComposerItem: selectComposerItem,
    onProjectChange: setProject,
  });

  return (
    <div className="desk-layout">
      <section className="desk-main">
        <ComposerCanvasSection
          busy={busy}
          dropActive={dropActive}
          highlightRegionIds={selectedHighlightRegionIds}
          pdfImportMode={pdfImportMode}
          project={composer.project}
          selectedCells={selectedCells}
          selectedId={composer.selectedId}
          selectedObjectIds={selectedObjectIds}
          thumbnails={thumbnailMap}
          onDuplicateDrawableStart={duplicateDrawableForDrag}
          onExportComposer={exportComposer}
          onImportAsset={importAssetPanels}
          onImportGraph={importGraphPanels}
          onObjectSelection={selectComposerObjects}
          onProjectChange={setProject}
          onQuickThreeUp={quickThreeUp}
          onSelect={(id, additive) => selectComposerItem(id, additive, "canvas")}
          onSelectedCellsChange={(cells, options) => {
            setSelectedCells(uniqueCells(cells));
            if (options?.preserveSelection) {
              return;
            }
            composer.setSelectedId(null);
            setSelectedObjectIds([]);
          }}
        />
      </section>

      <aside className="desk-context">
        <article className="context-card composer-tab-card">
          <div className="inspector-tab-strip" role="tablist" aria-label="Composer inspector tabs">
            <button
              aria-selected={inspectorTab === "insert"}
              className={`inspector-tab ${inspectorTab === "insert" ? "active" : ""}`}
              onClick={() => setInspectorTab("insert")}
              role="tab"
              type="button"
            >
              Insert
            </button>
            <button
              aria-selected={inspectorTab === "inspect"}
              className={`inspector-tab ${inspectorTab === "inspect" ? "active" : ""}`}
              onClick={() => setInspectorTab("inspect")}
              role="tab"
              type="button"
            >
              Inspect
            </button>
            <button
              aria-selected={inspectorTab === "layers"}
              className={`inspector-tab ${inspectorTab === "layers" ? "active" : ""}`}
              onClick={() => setInspectorTab("layers")}
              role="tab"
              type="button"
            >
              Layers
            </button>
          </div>
        </article>

        {inspectorTab === "insert" && (
          <ComposerInsertPanel
            autoLabels={composer.project.auto_labels}
            pdfImportMode={pdfImportMode}
            onAddText={addText}
            onAutoLabelsChange={(checked) =>
              composer.setProject({
                ...composer.project,
                auto_labels: checked,
              })
            }
            onImportModeChange={setPdfImportMode}
            onOpenProject={openComposerProject}
            onQuickTwoUpEditorial={quickTwoUpEditorial}
            onSaveProject={saveComposerProject}
          />
        )}

        {inspectorTab === "inspect" && (
          <ComposerInspectPanel
            canCopySelection={canCopySelection}
            canGroupSelection={canGroupSelection}
            canPasteSelection={canPasteSelection}
            canUngroupSelection={canUngroupSelection}
            cropValue={cropValue}
            freeRegions={freeRegions}
            hasSelection={hasSelection}
            multiSelectedCount={multiSelectedItems.length}
            project={composer.project}
            selectedCellsCount={selectedCells.length}
            selectedDrawableBinding={selectedDrawableBinding}
            selectedEditableCount={selectedEditableIds.length}
            selectedGroupCount={selectedGroupIds.length}
            selectedHighlightRegionCount={selectedHighlightRegionIds.length}
            selectedPanel={selectedPanel}
            selectedPanelLabel={selectedPanelLabel}
            selectedRegion={selectedRegion}
            selectedText={selectedText}
            slotRegions={slotRegions}
            onApplyBinding={applyBinding}
            onChangeLayer={changeLayer}
            onCopySelection={copySelection}
            onDuplicateSelection={duplicateSelection}
            onFitSelectedPanelToBinding={fitSelectedPanelToBinding}
            onGroupCurrentSelection={groupCurrentSelection}
            onMergeSelectedEmptyCells={mergeSelectedEmptyCells}
            onPasteSelection={pasteSelection}
            onPlaceSelectedDrawableInBinding={placeSelectedDrawableInBinding}
            onRemoveSelected={removeSelected}
            onRunAlignment={runAlignment}
            onRunDistribution={runDistribution}
            onSetSelectedRegionLocked={(locked) =>
              selectedRegion &&
              setProject({
                ...composer.project,
                regions: composer.project.regions.map((region) =>
                  region.id === selectedRegion.id ? { ...region, locked } : region,
                ),
              })
            }
            onUngroupCurrentSelection={ungroupCurrentSelection}
            onUnmergeSelectedRegion={unmergeSelectedRegion}
            onUpdateSelectedPanel={updateSelectedPanel}
            onUpdateSelectedText={updateSelectedText}
          />
        )}

        {inspectorTab === "layers" && (
          <ComposerLayersPanel
            currentSelectedId={composer.selectedId}
            layerItems={layerItems}
            selectedHiddenCount={selectedHiddenCount}
            selectedLockedCount={selectedLockedCount}
            selectedObjectCount={multiSelectedItems.length}
            selectedObjectIds={selectedObjectIds}
            slotRegionCount={slotRegions.length}
            validationError={composer.validationError}
            onHideSelected={() => updateSelectedDrawableFlags({ hidden: true })}
            onLockSelected={() => updateSelectedDrawableFlags({ locked: true })}
            onSelectItem={(id, type, additive) => {
              if (type === "region") {
                selectComposerItem(id, false, "layers");
                return;
              }
              selectComposerItem(id, additive, "layers");
            }}
            onShowSelected={() => updateSelectedDrawableFlags({ hidden: false })}
            onUnlockSelected={() => updateSelectedDrawableFlags({ locked: false })}
          />
        )}

        {composer.validationError && <div className="warning-card">{composer.validationError}</div>}

        {dropNotice && (
          <div className={dropNoticeTone === "warning" ? "warning-card" : "success-card"}>
            {dropNotice}
          </div>
        )}

        {exportPath && <div className="success-card">Exported: {exportPath}</div>}
      </aside>
    </div>
  );
}
