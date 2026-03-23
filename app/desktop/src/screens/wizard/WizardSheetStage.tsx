import { formatLeaf } from "../../lib/workbench";

type Props = {
  inputPath: string;
  sheet: string | number;
  sheetNames: string[];
  onInspectSheet(sheetValue: string | number): void;
};

export function WizardSheetStage({
  inputPath,
  sheet,
  sheetNames,
  onInspectSheet,
}: Props) {
  return (
    <div className="plot-stage-grid">
      <section className="work-card plot-sheet-card">
        <div className="panel-heading">
          <div>
            <div className="card-kicker">Sheet</div>
            <h3>Select the workbook tab</h3>
          </div>
        </div>

        <div className="sheet-choice-list">
          {sheetNames.map((name) => {
            const active =
              sheet === name ||
              (typeof sheet === "number" && sheetNames[sheet] === name);
            return (
              <button
                className={`sheet-choice ${active ? "active" : ""}`}
                key={name}
                onClick={() => onInspectSheet(name)}
                type="button"
              >
                <strong>{name}</strong>
                <span>{active ? "Current sheet" : "Inspect this sheet"}</span>
              </button>
            );
          })}
        </div>
      </section>

      <aside className="plot-stage-rail">
        <article className="context-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Workbook</div>
              <h3>{formatLeaf(inputPath)}</h3>
            </div>
          </div>
          <div className="wizard-summary-list">
            <div className="wizard-summary-row">
              <span>Sheets</span>
              <strong>{sheetNames.length}</strong>
            </div>
            <div className="wizard-summary-row">
              <span>Current</span>
              <strong>
                {typeof sheet === "string"
                  ? sheet
                  : sheetNames[sheet] ?? sheetNames[0] ?? "-"}
              </strong>
            </div>
          </div>
        </article>
      </aside>
    </div>
  );
}
