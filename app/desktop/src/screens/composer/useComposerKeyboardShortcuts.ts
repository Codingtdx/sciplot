import { useEffect } from "react";

import { moveGraphSelectionByCells, moveRegion, nudgeDrawables } from "../../lib/composer";
import type { ComposerProject, ComposerRegion } from "../../lib/types";

type Args = {
  canCopySelection: boolean;
  canPasteSelection: boolean;
  canGroupSelection: boolean;
  canUngroupSelection: boolean;
  hasSelection: boolean;
  project: ComposerProject;
  selectedObjectIds: string[];
  selectedRegion: ComposerRegion | null;
  onCopySelection: () => void;
  onPasteSelection: () => void;
  onDuplicateSelection: () => void;
  onGroupCurrentSelection: () => void;
  onUngroupCurrentSelection: () => void;
  onRemoveSelected: () => void;
  onSelectComposerItem: (id: string | null) => void;
  onProjectChange: (project: ComposerProject) => void;
};

export function useComposerKeyboardShortcuts({
  canCopySelection,
  canPasteSelection,
  canGroupSelection,
  canUngroupSelection,
  hasSelection,
  project,
  selectedObjectIds,
  selectedRegion,
  onCopySelection,
  onPasteSelection,
  onDuplicateSelection,
  onGroupCurrentSelection,
  onUngroupCurrentSelection,
  onRemoveSelected,
  onSelectComposerItem,
  onProjectChange,
}: Args) {
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
        onSelectComposerItem(null);
        return;
      }

      const shortcut = event.metaKey || event.ctrlKey;
      const shortcutKey = event.key.toLowerCase();
      if (shortcut && shortcutKey === "c" && canCopySelection) {
        event.preventDefault();
        onCopySelection();
        return;
      }
      if (shortcut && shortcutKey === "v" && canPasteSelection) {
        event.preventDefault();
        onPasteSelection();
        return;
      }
      if (shortcut && shortcutKey === "d" && hasSelection) {
        event.preventDefault();
        onDuplicateSelection();
        return;
      }
      if (shortcut && !event.shiftKey && shortcutKey === "g" && canGroupSelection) {
        event.preventDefault();
        onGroupCurrentSelection();
        return;
      }
      if (shortcut && event.shiftKey && shortcutKey === "g" && canUngroupSelection) {
        event.preventDefault();
        onUngroupCurrentSelection();
        return;
      }

      if ((event.key === "Backspace" || event.key === "Delete") && (selectedObjectIds.length > 0 || selectedRegion)) {
        event.preventDefault();
        onRemoveSelected();
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
          onProjectChange(
            moveRegion(project, selectedRegion.id, selectedRegion.col + delta.dx, selectedRegion.row + delta.dy),
          );
        }
        return;
      }

      event.preventDefault();
      const graphIds = selectedObjectIds.filter((id) =>
        project.panels.some((panel) => panel.id === id && panel.kind === "graph"),
      );
      const freeIds = selectedObjectIds.filter((id) => !graphIds.includes(id));

      let nextProject = project;
      if (freeIds.length > 0) {
        const step = event.shiftKey ? 2 : 0.5;
        nextProject = nudgeDrawables(nextProject, freeIds, delta.dx * step, delta.dy * step);
      }
      if (graphIds.length > 0) {
        nextProject = moveGraphSelectionByCells(nextProject, graphIds, delta.dx, delta.dy);
      }
      onProjectChange(nextProject);
    }

    window.addEventListener("keydown", handleKeydown);
    return () => {
      window.removeEventListener("keydown", handleKeydown);
    };
  }, [
    canCopySelection,
    canGroupSelection,
    canPasteSelection,
    canUngroupSelection,
    hasSelection,
    onCopySelection,
    onDuplicateSelection,
    onGroupCurrentSelection,
    onPasteSelection,
    onProjectChange,
    onRemoveSelected,
    onSelectComposerItem,
    onUngroupCurrentSelection,
    project,
    selectedObjectIds,
    selectedRegion,
  ]);
}
