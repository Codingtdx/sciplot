import type { PdfImportMode } from "../../lib/types";

type Props = {
  pdfImportMode: PdfImportMode;
  autoLabels: boolean;
  onImportModeChange: (mode: PdfImportMode) => void;
  onQuickTwoUpEditorial: () => void;
  onQuickThreeUp: () => void;
  onAddText: () => void;
  onOpenProject: () => void;
  onSaveProject: () => void;
  onAutoLabelsChange: (checked: boolean) => void;
};

export function ComposerInsertPanel({
  pdfImportMode,
  autoLabels,
  onImportModeChange,
  onQuickTwoUpEditorial,
  onQuickThreeUp,
  onAddText,
  onOpenProject,
  onSaveProject,
  onAutoLabelsChange,
}: Props) {
  return (
    <article className="context-card">
      <div className="panel-heading">
        <div>
          <h3>Insert</h3>
        </div>
      </div>

      <div className="mode-switch">
        <button
          className={`mode-button ${pdfImportMode === "graph" ? "active" : ""}`}
          onClick={() => onImportModeChange("graph")}
          type="button"
        >
          PDF as graph
        </button>
        <button
          className={`mode-button ${pdfImportMode === "asset" ? "active" : ""}`}
          onClick={() => onImportModeChange("asset")}
          type="button"
        >
          PDF as asset
        </button>
      </div>

      <div className="stacked-actions">
        <button className="ghost-button" onClick={onQuickTwoUpEditorial} type="button">
          2-up + notes
        </button>
        <button className="ghost-button" onClick={onQuickThreeUp} type="button">
          3-up preset
        </button>
        <button className="ghost-button" onClick={onAddText} type="button">
          Text
        </button>
        <button className="ghost-button" onClick={onOpenProject} type="button">
          Open project
        </button>
        <button className="ghost-button" onClick={onSaveProject} type="button">
          Save project
        </button>
      </div>

      <label className="toggle-field">
        <input
          checked={autoLabels}
          onChange={(event) => onAutoLabelsChange(event.target.checked)}
          type="checkbox"
        />
        <span>Auto a/b/c</span>
      </label>
    </article>
  );
}
