import type { ComposerProject, PdfImportMode } from "../../lib/types";
import { ComposerCanvas } from "../../components/ComposerCanvas";
import type { CellRef } from "./utils";

type Props = {
  project: ComposerProject;
  pdfImportMode: PdfImportMode;
  busy: boolean;
  dropActive: boolean;
  selectedCells: CellRef[];
  selectedId: string | null;
  selectedObjectIds: string[];
  highlightRegionIds: string[];
  thumbnails: Record<string, string>;
  onImportGraph: () => void;
  onImportAsset: () => void;
  onQuickThreeUp: () => void;
  onExportComposer: () => void;
  onDuplicateDrawableStart: (id: string) => string | null;
  onObjectSelection: (ids: string[], additive?: boolean) => void;
  onProjectChange: (project: ComposerProject) => void;
  onSelect: (id: string | null, additive?: boolean) => void;
  onSelectedCellsChange: (cells: CellRef[], options?: { preserveSelection?: boolean }) => void;
};

export function ComposerCanvasSection({
  project,
  pdfImportMode,
  busy,
  dropActive,
  selectedCells,
  selectedId,
  selectedObjectIds,
  highlightRegionIds,
  thumbnails,
  onImportGraph,
  onImportAsset,
  onQuickThreeUp,
  onExportComposer,
  onDuplicateDrawableStart,
  onObjectSelection,
  onProjectChange,
  onSelect,
  onSelectedCellsChange,
}: Props) {
  return (
    <article className="work-card canvas-shell-card hero-card">
      <div className="section-head">
        <div>
          <div className="card-kicker">Layout Studio</div>
          <h2>Arrange one editable figure sheet</h2>
          <p>Graph PDFs snap into regions. Assets and text stay flexible on top of the layout grid.</p>
        </div>
        <div className="metric-strip">
          <div className="metric-chip">
            <span>Layout frame</span>
            <strong>180 x 165 mm</strong>
          </div>
          <div className="metric-chip">
            <span>Regions / objects</span>
            <strong>
              {project.regions.length} / {project.panels.length + project.texts.length}
            </strong>
          </div>
        </div>
      </div>

      <div className="canvas-toolbar">
        <button className="primary-button" onClick={onImportGraph} type="button">
          Import graph
        </button>
        <button className="ghost-button" onClick={onImportAsset} type="button">
          Import asset
        </button>
        <button className="ghost-button" onClick={onQuickThreeUp} type="button">
          Three-up preset
        </button>
        <button className="ghost-button" onClick={onExportComposer} type="button">
          Export editable PDF
        </button>
      </div>

      <div className="composer-main">
        <div className={`composer-drop-overlay ${dropActive ? "visible" : ""}`}>
          <div className="composer-drop-card">
            <strong>Drop to import</strong>
            <span>
              {pdfImportMode === "graph"
                ? "CodeGod graph PDFs in 60x55, 120x55, or 60x110 mm snap into matching grid regions."
                : "PDF and raster files import as free assets that can crop, snap, stack, and export as editable content."}
            </span>
          </div>
        </div>

        <ComposerCanvas
          highlightRegionIds={highlightRegionIds}
          project={project}
          selectedCells={selectedCells}
          selectedId={selectedId}
          selectedObjectIds={selectedObjectIds}
          thumbnails={thumbnails}
          onDuplicateDrawableStart={onDuplicateDrawableStart}
          onObjectSelection={onObjectSelection}
          onProjectChange={onProjectChange}
          onSelect={onSelect}
          onSelectedCellsChange={onSelectedCellsChange}
        />

        {project.panels.length === 0 && !busy && (
          <div className="composer-empty-state">
            <strong>Start by importing graph PDFs or assets</strong>
            <span>
              Graph PDFs occupy grid-backed regions. Assets and text remain free-form and still export as editable layers.
            </span>
          </div>
        )}

        {busy && <div className="composer-status">Updating…</div>}
      </div>
    </article>
  );
}
