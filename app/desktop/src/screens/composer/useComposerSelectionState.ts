import { useMemo } from "react";

import {
  composerLayerTitle,
  describePanelSlot,
  editableSelectionIds,
  findRegion,
  orderDrawables,
  resolveSelectedPanelLabel,
  selectedRegionIdsForObjects,
} from "../../lib/composer";
import type { ComposerPanel, ComposerProject, ComposerRegion, ComposerText } from "../../lib/types";

export type ComposerLayerItem = {
  id: string;
  type: "region" | "panel" | "text";
  title: string;
  detail: string;
};

export function useComposerSelectionState(
  project: ComposerProject,
  selectedId: string | null,
  selectedObjectIds: string[],
) {
  const primaryObjectId = selectedObjectIds.length === 1 ? selectedObjectIds[0] : null;

  const selectedPanel = useMemo(
    () => project.panels.find((item) => item.id === primaryObjectId) ?? null,
    [primaryObjectId, project.panels],
  );
  const selectedText = useMemo(
    () => project.texts.find((item) => item.id === primaryObjectId) ?? null,
    [primaryObjectId, project.texts],
  );
  const selectedRegion = useMemo(
    () =>
      selectedObjectIds.length === 0
        ? project.regions.find((item) => item.id === selectedId) ?? null
        : null,
    [project.regions, selectedId, selectedObjectIds],
  );

  const selectedPanelLabel = useMemo(
    () => (selectedPanel ? resolveSelectedPanelLabel(project, selectedPanel) : ""),
    [project, selectedPanel],
  );

  const selectedPanelPositionLocked = useMemo(
    () =>
      Boolean(
        selectedPanel &&
          (selectedPanel.locked ||
            (selectedPanel.kind === "graph" &&
              findRegion(project, selectedPanel.region_id)?.locked)),
      ),
    [project, selectedPanel],
  );
  const selectedTextPositionLocked = Boolean(selectedText?.locked);

  const selectedEditableIds = useMemo(
    () => editableSelectionIds(project, selectedObjectIds),
    [project, selectedObjectIds],
  );
  const hasSelection = Boolean(selectedRegion) || selectedObjectIds.length > 0;
  const selectedHighlightRegionIds = useMemo(
    () =>
      Array.from(
        new Set([
          ...(selectedRegion ? [selectedRegion.id] : []),
          ...selectedRegionIdsForObjects(project, selectedObjectIds),
        ]),
      ),
    [project, selectedObjectIds, selectedRegion],
  );

  const multiSelectedItems = useMemo(
    () =>
      selectedObjectIds
        .map(
          (id) =>
            project.panels.find((item) => item.id === id) ??
            project.texts.find((item) => item.id === id) ??
            null,
        )
        .filter((item): item is ComposerPanel | ComposerText => item != null),
    [project.panels, project.texts, selectedObjectIds],
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

  const freeRegions = useMemo(
    () => project.regions.filter((region) => region.kind === "free"),
    [project.regions],
  );
  const slotRegions = useMemo(
    () => project.regions.filter((region) => region.slot_kind === "structure"),
    [project.regions],
  );

  const orderedDrawables = useMemo(() => orderDrawables(project), [project]);
  const layerItems = useMemo<ComposerLayerItem[]>(
    () => [
      ...project.regions.map((region) => ({
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
          const panel = project.panels.find((entry) => entry.id === item.id)!;
          return {
            id: panel.id,
            type: "panel" as const,
            title: composerLayerTitle(project, panel),
            detail:
              panel.kind === "graph"
                ? `Graph · ${describePanelSlot(panel, project)}${panel.group_id ? ` · ${panel.group_id}` : ""}${panel.hidden ? " · Hidden" : ""}${panel.locked ? " · Locked" : ""}`
                : `Asset · ${panel.w_mm.toFixed(1)} x ${panel.h_mm.toFixed(1)} mm${panel.group_id ? ` · ${panel.group_id}` : ""}${panel.hidden ? " · Hidden" : ""}${panel.locked ? " · Locked" : ""}`,
          };
        }
        const text = project.texts.find((entry) => entry.id === item.id)!;
        return {
          id: text.id,
          type: "text" as const,
          title: text.text || "Text",
          detail: `Text · ${text.font_size_pt} pt${text.group_id ? ` · ${text.group_id}` : ""}${text.hidden ? " · Hidden" : ""}${text.locked ? " · Locked" : ""}`,
        };
      }),
    ],
    [orderedDrawables, project],
  );

  return {
    selectedPanel,
    selectedText,
    selectedRegion: selectedRegion as ComposerRegion | null,
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
  };
}
