import { describePanelSlot } from "../../lib/composer";
import type { ComposerCropRect, ComposerPanel, ComposerProject, ComposerRegion, ComposerText } from "../../lib/types";
import { boundRectForDrawable } from "./utils";

type AlignmentMode = "left" | "center" | "right" | "top" | "middle" | "bottom";
type DistributionAxis = "horizontal" | "vertical";
type PlacementMode = "top" | "middle" | "bottom" | "center" | "left" | "hcenter" | "right";
type LayerAction = "forward" | "backward" | "front" | "back";

type Props = {
  project: ComposerProject;
  hasSelection: boolean;
  canCopySelection: boolean;
  canPasteSelection: boolean;
  canGroupSelection: boolean;
  canUngroupSelection: boolean;
  selectedCellsCount: number;
  selectedEditableCount: number;
  selectedHighlightRegionCount: number;
  selectedGroupCount: number;
  multiSelectedCount: number;
  selectedRegion: ComposerRegion | null;
  selectedPanel: ComposerPanel | null;
  selectedText: ComposerText | null;
  selectedPanelLabel: string;
  selectedDrawableBinding: string;
  cropValue: ComposerCropRect;
  freeRegions: ComposerRegion[];
  slotRegions: ComposerRegion[];
  onCopySelection: () => void;
  onPasteSelection: () => void;
  onDuplicateSelection: () => void;
  onMergeSelectedEmptyCells: () => void;
  onUnmergeSelectedRegion: () => void;
  onGroupCurrentSelection: () => void;
  onUngroupCurrentSelection: () => void;
  onRunAlignment: (mode: AlignmentMode) => void;
  onRunDistribution: (axis: DistributionAxis) => void;
  onRemoveSelected: () => void;
  onSetSelectedRegionLocked: (locked: boolean) => void;
  onUpdateSelectedPanel: (patch: Partial<ComposerPanel>) => void;
  onUpdateSelectedText: (patch: Partial<ComposerText>) => void;
  onApplyBinding: (value: string) => void;
  onFitSelectedPanelToBinding: () => void;
  onPlaceSelectedDrawableInBinding: (mode: PlacementMode) => void;
  onChangeLayer: (action: LayerAction) => void;
};

const ALIGNMENT_ACTIONS: Array<{ label: string; mode: AlignmentMode }> = [
  { label: "Left", mode: "left" },
  { label: "Center X", mode: "center" },
  { label: "Right", mode: "right" },
  { label: "Top", mode: "top" },
  { label: "Center Y", mode: "middle" },
  { label: "Bottom", mode: "bottom" },
];

const DISTRIBUTION_ACTIONS: Array<{ label: string; axis: DistributionAxis }> = [
  { label: "Distribute X", axis: "horizontal" },
  { label: "Distribute Y", axis: "vertical" },
];

const BINDING_PLACEMENT_ACTIONS: Array<{ label: string; mode: PlacementMode }> = [
  { label: "Left", mode: "left" },
  { label: "Center X", mode: "hcenter" },
  { label: "Right", mode: "right" },
  { label: "Top", mode: "top" },
  { label: "Middle", mode: "middle" },
  { label: "Bottom", mode: "bottom" },
  { label: "Center", mode: "center" },
];

const LAYER_ACTIONS: Array<{ label: string; action: LayerAction }> = [
  { label: "Forward", action: "forward" },
  { label: "Back", action: "backward" },
  { label: "To front", action: "front" },
  { label: "To back", action: "back" },
];

function BindingOptions({
  freeRegions,
  slotRegions,
}: {
  freeRegions: ComposerRegion[];
  slotRegions: ComposerRegion[];
}) {
  return (
    <>
      <option value="none">None</option>
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
    </>
  );
}

function PlacementActions({
  disabled,
  onPlace,
}: {
  disabled: boolean;
  onPlace: (mode: PlacementMode) => void;
}) {
  return (
    <>
      {BINDING_PLACEMENT_ACTIONS.map(({ label, mode }) => (
        <button
          className="ghost-button"
          disabled={disabled}
          key={label}
          onClick={() => onPlace(mode)}
          type="button"
        >
          {label}
        </button>
      ))}
    </>
  );
}

function LayerOrderActions({ onChange }: { onChange: (action: LayerAction) => void }) {
  return (
    <>
      {LAYER_ACTIONS.map(({ label, action }) => (
        <button className="ghost-button" key={label} onClick={() => onChange(action)} type="button">
          {label}
        </button>
      ))}
    </>
  );
}

export function ComposerInspectPanel({
  project,
  hasSelection,
  canCopySelection,
  canPasteSelection,
  canGroupSelection,
  canUngroupSelection,
  selectedCellsCount,
  selectedEditableCount,
  selectedHighlightRegionCount,
  selectedGroupCount,
  multiSelectedCount,
  selectedRegion,
  selectedPanel,
  selectedText,
  selectedPanelLabel,
  selectedDrawableBinding,
  cropValue,
  freeRegions,
  slotRegions,
  onCopySelection,
  onPasteSelection,
  onDuplicateSelection,
  onMergeSelectedEmptyCells,
  onUnmergeSelectedRegion,
  onGroupCurrentSelection,
  onUngroupCurrentSelection,
  onRunAlignment,
  onRunDistribution,
  onRemoveSelected,
  onSetSelectedRegionLocked,
  onUpdateSelectedPanel,
  onUpdateSelectedText,
  onApplyBinding,
  onFitSelectedPanelToBinding,
  onPlaceSelectedDrawableInBinding,
  onChangeLayer,
}: Props) {
  const selectedPanelBoundRect = selectedPanel ? boundRectForDrawable(project, selectedPanel) : null;
  const selectedTextBoundRect = selectedText ? boundRectForDrawable(project, selectedText) : null;

  return (
    <article className="context-card">
      <div className="panel-heading">
        <div>
          <h3>Selection</h3>
        </div>
      </div>

      {!hasSelection && (
        <div className="placeholder-card">Select a region, graph, asset, or text.</div>
      )}

      <div className="stacked-actions">
        <button className="ghost-button" disabled={!canCopySelection} onClick={onCopySelection} type="button">
          Copy
        </button>
        <button className="ghost-button" disabled={!canPasteSelection} onClick={onPasteSelection} type="button">
          Paste
        </button>
        <button className="ghost-button" disabled={!hasSelection} onClick={onDuplicateSelection} type="button">
          Duplicate
        </button>
        <button
          className="ghost-button"
          disabled={selectedCellsCount < 2}
          onClick={onMergeSelectedEmptyCells}
          type="button"
        >
          Merge cells
        </button>
        <button
          className="ghost-button"
          disabled={!selectedRegion || selectedRegion.kind !== "free"}
          onClick={onUnmergeSelectedRegion}
          type="button"
        >
          Split region
        </button>
      </div>

      {multiSelectedCount > 1 && (
        <div className="inspector-stack">
          <div className="info-grid compact-grid">
            <div className="stat-tile">
              <span>Selected</span>
              <strong>{multiSelectedCount}</strong>
            </div>
            <div className="stat-tile">
              <span>Editable</span>
              <strong>{selectedEditableCount}</strong>
            </div>
            <div className="stat-tile">
              <span>Bound regions</span>
              <strong>{selectedHighlightRegionCount}</strong>
            </div>
            <div className="stat-tile">
              <span>Groups</span>
              <strong>{selectedGroupCount}</strong>
            </div>
          </div>

          <div className="stacked-actions">
            <button
              className="ghost-button"
              disabled={!canGroupSelection}
              onClick={onGroupCurrentSelection}
              type="button"
            >
              Group
            </button>
            <button
              className="ghost-button"
              disabled={!canUngroupSelection}
              onClick={onUngroupCurrentSelection}
              type="button"
            >
              Ungroup
            </button>
            {ALIGNMENT_ACTIONS.map(({ label, mode }) => (
              <button
                className="ghost-button"
                disabled={selectedEditableCount < 2}
                key={label}
                onClick={() => onRunAlignment(mode)}
                type="button"
              >
                {label}
              </button>
            ))}
            {DISTRIBUTION_ACTIONS.map(({ label, axis }) => (
              <button
                className="ghost-button"
                disabled={selectedEditableCount < 3}
                key={label}
                onClick={() => onRunDistribution(axis)}
                type="button"
              >
                {label}
              </button>
            ))}
          </div>

          <button className="ghost-button danger-button" onClick={onRemoveSelected} type="button">
            Delete
          </button>
        </div>
      )}

      {selectedRegion && (
        <div className="inspector-stack">
          <div className="info-grid compact-grid">
            <div className="stat-tile">
              <span>Type</span>
              <strong>{selectedRegion.kind === "graph" ? "Graph region" : "Free region"}</strong>
            </div>
            <div className="stat-tile">
              <span>Span</span>
              <strong>
                {selectedRegion.col_span} x {selectedRegion.row_span}
              </strong>
            </div>
            <div className="stat-tile">
              <span>Structure slot</span>
              <strong>{selectedRegion.slot_kind === "structure" ? "Yes" : "No"}</strong>
            </div>
          </div>

          <label className="toggle-field">
            <input
              checked={Boolean(selectedRegion.locked)}
              onChange={(event) => onSetSelectedRegionLocked(event.target.checked)}
              type="checkbox"
            />
            <span>Lock region movement</span>
          </label>

          {selectedRegion.kind === "free" && (
            <button className="ghost-button danger-button" onClick={onUnmergeSelectedRegion} type="button">
              Split region
            </button>
          )}
        </div>
      )}

      {selectedPanel && (
        <div className="inspector-stack">
          <div className="info-grid compact-grid">
            <div className="stat-tile">
              <span>Type</span>
              <strong>{selectedPanel.kind === "graph" ? "Graph" : "Asset"}</strong>
            </div>
            <div className="stat-tile">
              <span>Label</span>
              <strong>{selectedPanelLabel || selectedPanel.label || "-"}</strong>
            </div>
            <div className="stat-tile">
              <span>Placement</span>
              <strong>{describePanelSlot(selectedPanel, project)}</strong>
            </div>
            <div className="stat-tile">
              <span>Layer</span>
              <strong>{selectedPanel.z_index + 1}</strong>
            </div>
          </div>

          <label>
            <span className="field-label">Custom label</span>
            <input
              className="field"
              disabled={project.auto_labels && selectedPanel.kind === "graph"}
              onChange={(event) => onUpdateSelectedPanel({ label: event.target.value || null })}
              type="text"
              value={selectedPanel.label ?? ""}
            />
          </label>

          {selectedPanel.kind === "asset" ? (
            <label>
              <span className="field-label">Binding</span>
              <select
                className="field"
                onChange={(event) => onApplyBinding(event.target.value)}
                value={selectedDrawableBinding}
              >
                <BindingOptions freeRegions={freeRegions} slotRegions={slotRegions} />
              </select>
            </label>
          ) : (
            <div className="hint-text">Graph region binding: {selectedPanel.region_id ?? "Not bound"}</div>
          )}

          <label className="toggle-field">
            <input
              checked={Boolean(selectedPanel.locked)}
              onChange={(event) => onUpdateSelectedPanel({ locked: event.target.checked })}
              type="checkbox"
            />
            <span>Lock position</span>
          </label>

          <label className="toggle-field">
            <input
              checked={Boolean(selectedPanel.hidden)}
              onChange={(event) => onUpdateSelectedPanel({ hidden: event.target.checked })}
              type="checkbox"
            />
            <span>Hide object</span>
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
              <button className="ghost-button" onClick={onFitSelectedPanelToBinding} type="button">
                Fit to binding
              </button>
              <PlacementActions
                disabled={!selectedPanelBoundRect}
                onPlace={onPlaceSelectedDrawableInBinding}
              />
              <LayerOrderActions onChange={onChangeLayer} />
            </div>
          )}

          <div className="info-grid compact-grid">
            <label>
              <span className="field-label">Crop x %</span>
              <input
                className="field"
                max={95}
                min={0}
                onChange={(event) =>
                  onUpdateSelectedPanel({
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
              <span className="field-label">Crop y %</span>
              <input
                className="field"
                max={95}
                min={0}
                onChange={(event) =>
                  onUpdateSelectedPanel({
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
              <span className="field-label">Crop width %</span>
              <input
                className="field"
                max={100}
                min={1}
                onChange={(event) =>
                  onUpdateSelectedPanel({
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
              <span className="field-label">Crop height %</span>
              <input
                className="field"
                max={100}
                min={1}
                onChange={(event) =>
                  onUpdateSelectedPanel({
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

          <button className="ghost-button danger-button" onClick={onRemoveSelected} type="button">
            Delete
          </button>
        </div>
      )}

      {selectedText && (
        <div className="inspector-stack">
          <label>
            <span className="field-label">Content</span>
            <input
              className="field"
              onChange={(event) => onUpdateSelectedText({ text: event.target.value })}
              type="text"
              value={selectedText.text}
            />
          </label>

          <label>
            <span className="field-label">Font size</span>
            <input
              className="field"
              max={20}
              min={5}
              onChange={(event) =>
                onUpdateSelectedText({
                  font_size_pt: Number(event.target.value) || selectedText.font_size_pt,
                })
              }
              type="number"
              value={selectedText.font_size_pt}
            />
          </label>

          <label>
            <span className="field-label">Align</span>
            <select
              className="field"
              onChange={(event) =>
                onUpdateSelectedText({
                  align: event.target.value as "left" | "center" | "right",
                })
              }
              value={selectedText.align}
            >
              <option value="left">Left</option>
              <option value="center">Center</option>
              <option value="right">Right</option>
            </select>
          </label>

          <label>
            <span className="field-label">Binding</span>
            <select
              className="field"
              onChange={(event) => onApplyBinding(event.target.value)}
              value={selectedDrawableBinding}
            >
              <BindingOptions freeRegions={freeRegions} slotRegions={slotRegions} />
            </select>
          </label>

          <label className="toggle-field">
            <input
              checked={Boolean(selectedText.locked)}
              onChange={(event) => onUpdateSelectedText({ locked: event.target.checked })}
              type="checkbox"
            />
            <span>Lock position</span>
          </label>

          <label className="toggle-field">
            <input
              checked={Boolean(selectedText.hidden)}
              onChange={(event) => onUpdateSelectedText({ hidden: event.target.checked })}
              type="checkbox"
            />
            <span>Hide text</span>
          </label>

          <div className="stacked-actions">
            <PlacementActions
              disabled={!selectedTextBoundRect}
              onPlace={onPlaceSelectedDrawableInBinding}
            />
            <LayerOrderActions onChange={onChangeLayer} />
          </div>

          <button className="ghost-button danger-button" onClick={onRemoveSelected} type="button">
            Delete
          </button>
        </div>
      )}
    </article>
  );
}
