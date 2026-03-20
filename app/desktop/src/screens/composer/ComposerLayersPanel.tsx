import type { ComposerLayerItem } from "./useComposerSelectionState";

type Props = {
  currentSelectedId: string | null;
  selectedObjectIds: string[];
  selectedObjectCount: number;
  selectedHiddenCount: number;
  selectedLockedCount: number;
  slotRegionCount: number;
  validationError: string | null | undefined;
  layerItems: ComposerLayerItem[];
  onSelectItem: (id: string, type: ComposerLayerItem["type"], additive: boolean) => void;
  onLockSelected: () => void;
  onUnlockSelected: () => void;
  onHideSelected: () => void;
  onShowSelected: () => void;
};

export function ComposerLayersPanel({
  currentSelectedId,
  selectedObjectIds,
  selectedObjectCount,
  selectedHiddenCount,
  selectedLockedCount,
  slotRegionCount,
  validationError,
  layerItems,
  onSelectItem,
  onLockSelected,
  onUnlockSelected,
  onHideSelected,
  onShowSelected,
}: Props) {
  return (
    <article className="context-card">
      <div className="panel-heading">
        <div>
          <h3>Layers</h3>
        </div>
      </div>

      <div className="context-list">
        <div className="context-row">
          <span>Base cell</span>
          <strong>60 x 55 mm</strong>
        </div>
        <div className="context-row">
          <span>Structure slots</span>
          <strong>{slotRegionCount}</strong>
        </div>
        <div className="context-row">
          <span>Validation</span>
          <strong>{validationError ? "Issues" : "Clear"}</strong>
        </div>
      </div>

      {selectedObjectCount > 0 && (
        <div className="inspector-stack">
          <div className="hint-text">
            {selectedObjectCount} selected · {selectedHiddenCount} hidden · {selectedLockedCount} locked
          </div>
          <div className="stacked-actions">
            <button
              className="ghost-button"
              disabled={selectedLockedCount === selectedObjectCount}
              onClick={onLockSelected}
              type="button"
            >
              Lock selected
            </button>
            <button
              className="ghost-button"
              disabled={selectedLockedCount === 0}
              onClick={onUnlockSelected}
              type="button"
            >
              Unlock selected
            </button>
            <button
              className="ghost-button"
              disabled={selectedHiddenCount === selectedObjectCount}
              onClick={onHideSelected}
              type="button"
            >
              Hide selected
            </button>
            <button
              className="ghost-button"
              disabled={selectedHiddenCount === 0}
              onClick={onShowSelected}
              type="button"
            >
              Show selected
            </button>
          </div>
        </div>
      )}

      <div className="layer-list">
        {layerItems.length === 0 && (
          <div className="placeholder-card">No layers yet. Import graph PDFs or assets to populate the stack.</div>
        )}
        {layerItems.map((item) => (
          <button
            className={`layer-item ${
              currentSelectedId === item.id || selectedObjectIds.includes(item.id) ? "active" : ""
            }`}
            key={item.id}
            onClick={(event) => {
              const additive = Boolean(event.shiftKey || event.metaKey || event.ctrlKey);
              onSelectItem(item.id, item.type, additive);
            }}
            type="button"
          >
            <strong>{item.title}</strong>
            <span>{item.detail}</span>
          </button>
        ))}
      </div>
    </article>
  );
}
