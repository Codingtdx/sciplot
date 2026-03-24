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
  onDuplicateDrawableStart,
  onObjectSelection,
  onProjectChange,
  onSelect,
  onSelectedCellsChange,
}: Props) {
  return (
    <section className="composer-canvas-v2">
      <div className="composer-main">
        <div className={`composer-drop-overlay ${dropActive ? "visible" : ""}`}>
          <div className="composer-drop-card">
            <strong>Drop to import</strong>
            <span>
              {pdfImportMode === "graph"
                ? "Graph PDFs in 60x55, 120x55, or 60x110 mm snap into matching regions."
                : "PDF and raster files import as free assets."}
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

        {project.panels.length === 0 && project.texts.length === 0 && !busy && (
          <div className="composer-empty-hint">Import graph PDFs or assets to start composing.</div>
        )}

        {busy && <div className="composer-status">Updating…</div>}
      </div>
    </section>
  );
}
