import { useState } from "react";

import { AppIcon } from "../../components/AppIcon";
import { mockPlotImportData } from "../data/mockPlotImportData";

export function MockPlotImport() {
  const [sheet, setSheet] = useState(mockPlotImportData.selectedSheet);

  return (
    <section className="mock-screen">
      <header className="mock-screen-header">
        <div>
          <p className="mock-kicker">Dataset browser</p>
          <h1 className="mock-screen-title">Table-first import workspace with a compact inspection rail.</h1>
          <p className="mock-screen-copy">
            The dataset remains the dominant object on screen. Source controls stay at the top,
            inspection stays in a tight rail, and the continue action sits on the workflow floor.
          </p>
        </div>
      </header>

      <div className="mock-import-layout">
        <article className="mock-panel mock-table-panel">
          <div className="mock-source-toolbar">
            <span className="mock-pill">{mockPlotImportData.sourceLabel}</span>
            <div className="mock-source-path">
              <AppIcon name="folder" />
              <span>{mockPlotImportData.filePath}</span>
            </div>
            <label className="mock-sheet-field">
              <span>Sheet</span>
              <select value={sheet} onChange={(event) => setSheet(event.target.value)}>
                {mockPlotImportData.sheets.map((item) => (
                  <option key={item} value={item}>
                    {item}
                  </option>
                ))}
              </select>
            </label>
            <button type="button" className="mock-button is-primary">
              <AppIcon name="refresh" />
              Inspect dataset
            </button>
          </div>

          <div className="mock-table-summary">
            <strong>{mockPlotImportData.fileName}</strong>
            <span>
              {mockPlotImportData.rowCount} rows · {mockPlotImportData.columnCount} columns · {mockPlotImportData.inspectedAt}
            </span>
            <div className="mock-chip-row">
              {mockPlotImportData.schemaBadges.map((item) => (
                <span key={item} className="mock-chip">
                  {item}
                </span>
              ))}
            </div>
          </div>

          <div className="mock-data-table-shell">
            <table className="mock-data-table">
              <thead>
                <tr>
                  {mockPlotImportData.headers.map((header) => (
                    <th key={header}>{header}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {mockPlotImportData.rows.map((row) => (
                  <tr key={row.join("-")}>
                    {row.map((cell, index) => (
                      <td key={`${cell}-${index}`}>{cell}</td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </article>

        <aside className="mock-inspection-rail">
          <article className="mock-panel">
            <div className="mock-panel-head">
              <div>
                <span className="mock-pill is-accent">Inspection</span>
                <h2>{mockPlotImportData.inspection.model}</h2>
              </div>
              <span className="mock-panel-meta">{mockPlotImportData.inspection.confidence}</span>
            </div>
            <p className="mock-panel-copy">{mockPlotImportData.inspection.summary}</p>

            <dl className="mock-role-list">
              {mockPlotImportData.inspection.columnRoles.map((item) => (
                <div key={item.name}>
                  <dt>{item.name}</dt>
                  <dd>{item.role}</dd>
                </div>
              ))}
            </dl>
          </article>

          {mockPlotImportData.inspection.signalGroups.map((group) => (
            <article key={group.label} className="mock-panel">
              <div className="mock-panel-head compact">
                <div>
                  <span className="mock-pill">{group.label}</span>
                </div>
              </div>
              <ul className="mock-bullet-list">
                {group.items.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </article>
          ))}
        </aside>

        <footer className="mock-action-floor">
          <div>
            <p className="mock-kicker">Next</p>
            <strong>Continue into Template Studio with this inspected dataset.</strong>
          </div>
          <button type="button" className="mock-button is-primary">
            Continue to template recommendations
          </button>
        </footer>
      </div>
    </section>
  );
}
