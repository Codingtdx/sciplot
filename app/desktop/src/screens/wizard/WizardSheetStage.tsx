type Props = {
  inputPath: string;
  sheet: string | number;
  sheetNames: string[];
  onInspectSheet(sheetValue: string | number): void;
};

export function WizardSheetStage({
  sheet,
  sheetNames,
  onInspectSheet,
}: Props) {
  return (
    <section className="work-card plot-sheet-card plot-sheet-v2">
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
  );
}
