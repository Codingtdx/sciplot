import { InfoTip } from "../../components/InfoTip";
import type { PdfImportMode } from "../../lib/types";

type Props = {
  pdfImportMode: PdfImportMode;
  autoLabels: boolean;
  onImportModeChange: (mode: PdfImportMode) => void;
  onQuickTwoUpEditorial: () => void;
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
  onAddText,
  onOpenProject,
  onSaveProject,
  onAutoLabelsChange,
}: Props) {
  return (
    <article className="context-card">
      <div className="panel-heading">
        <div>
          <h3>Insert and presets</h3>
        </div>
        <InfoTip content="Use graph mode for CodeGod-standard graph PDFs. Use asset mode for PDFs and images that should stay free-form." />
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
          Two-up + notes
        </button>
        <button className="ghost-button" onClick={onAddText} type="button">
          Add text
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
        <span>Auto a/b/c labels</span>
      </label>
    </article>
  );
}
