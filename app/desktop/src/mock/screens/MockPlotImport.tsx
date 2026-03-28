import {
  mockImportColumns,
  mockImportCompatibleTemplates,
  mockImportInspectionFacts,
  mockImportInspectionNotes,
  mockImportRows,
  mockImportWorkbook,
} from "../data/mockPlotImportData";

export function MockPlotImport() {
  return (
    <section className="mock-screen mock-import">
      <div className="mock-panel mock-import__toolbar">
        <div className="mock-import__toolbar-group">
          <div className="mock-inline-field">
            <span className="mock-inline-field__label">Source</span>
            <button className="mock-select" type="button">
              <strong>{mockImportWorkbook.source}</strong>
              <span>{mockImportWorkbook.name}</span>
            </button>
          </div>
          <div className="mock-inline-field">
            <span className="mock-inline-field__label">Sheet</span>
            <button className="mock-select" type="button">
              <strong>{mockImportWorkbook.selectedSheet}</strong>
              <span>{mockImportWorkbook.sheets.join(" · ")}</span>
            </button>
          </div>
          <span className="mock-import__toolbar-meta">
            {mockImportRows.length} visible rows · last updated {mockImportWorkbook.modified}
          </span>
        </div>
        <button className="mock-button mock-button--primary" type="button">
          Inspect Dataset
        </button>
      </div>

      <div className="mock-import__layout">
        <div className="mock-panel mock-import__table-panel">
          <div className="mock-panel__header">
            <div>
              <p className="mock-panel__eyebrow">Preview table</p>
              <h3>Workbook rows that will drive the plot recommendation</h3>
            </div>
            <span className="mock-chip">
              {mockImportRows.length} visible rows · updated {mockImportWorkbook.modified}
            </span>
          </div>

          <div className="mock-import__table-wrap">
            <table className="mock-import__table">
              <thead>
                <tr>
                  {mockImportColumns.map((column) => (
                    <th key={column}>{column}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {mockImportRows.map((row, rowIndex) => (
                  <tr key={`${row[0]}-${rowIndex}`}>
                    {row.map((cell, cellIndex) => (
                      <td key={`${mockImportColumns[cellIndex]}-${cell}`}>{cell}</td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div className="mock-panel mock-import__inspection">
          <div className="mock-panel__header">
            <div>
              <p className="mock-panel__eyebrow">Inspection rail</p>
              <h3>Compact structure readout</h3>
            </div>
            <span className="mock-chip mock-chip--accent">Inspection clean</span>
          </div>

          <div className="mock-import__facts">
            {mockImportInspectionFacts.map((fact) => (
              <div key={fact.label} className="mock-import__fact">
                <span>{fact.label}</span>
                <strong>{fact.value}</strong>
              </div>
            ))}
          </div>

          <div className="mock-import__note-block">
            <p className="mock-panel__eyebrow">Readiness notes</p>
            <ul className="mock-bullet-list">
              {mockImportInspectionNotes.map((note) => (
                <li key={note}>{note}</li>
              ))}
            </ul>
          </div>

          <div className="mock-import__template-chips">
            <p className="mock-panel__eyebrow">Compatible templates</p>
            <div className="mock-chip-row">
              {mockImportCompatibleTemplates.map((template) => (
                <span key={template} className="mock-chip mock-chip--subtle">
                  {template}
                </span>
              ))}
            </div>
          </div>
        </div>
      </div>

      <div className="mock-panel mock-import__footer">
        <div className="mock-import__footer-copy">
          <p className="mock-panel__eyebrow">Workflow anchor</p>
          <h3>Inspection is ready. Continue into template selection.</h3>
          <span>
            {mockImportCompatibleTemplates.length} compatible figure directions ·{" "}
            {mockImportRows.length} rows visible in the active preview
          </span>
        </div>
        <a className="mock-button mock-button--primary" href="#/plot-template">
          Continue with Recommended Templates
        </a>
      </div>
    </section>
  );
}
