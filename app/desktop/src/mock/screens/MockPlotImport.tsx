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
          Inspect
        </button>
      </div>

      <div className="mock-import__layout">
        <div className="mock-panel mock-import__table-panel">
          <div className="mock-panel__header">
            <div>
              <h3>{mockImportWorkbook.name}</h3>
            </div>
            <span className="mock-import__toolbar-meta">{mockImportWorkbook.selectedSheet}</span>
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
              <h3>Inspect</h3>
            </div>
            <span className="mock-import__toolbar-meta">Ready</span>
          </div>

          <div className="mock-import__facts">
            {mockImportInspectionFacts.map((fact) => (
              <div key={fact.label} className="mock-import__fact">
                <span>{fact.label}</span>
                <strong>{fact.value}</strong>
              </div>
            ))}
          </div>

          <div className="mock-import__template-chips">
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
        <a className="mock-button mock-button--primary" href="#/plot/template">
          Continue
        </a>
      </div>
    </section>
  );
}
