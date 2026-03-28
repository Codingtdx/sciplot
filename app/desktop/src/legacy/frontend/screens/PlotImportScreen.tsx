import type { PlotDatasetPreview } from "../lib/types";

import { AppIcon } from "../components/AppIcon";
import { MacButton } from "../components/mac/MacButton";
import { MacPanel } from "../components/mac/MacPanel";
import { MacSelect } from "../components/mac/MacSelect";
import { MacStatusPill } from "../components/mac/MacStatusPill";

function formatCellValue(value: unknown) {
  if (value == null) {
    return "";
  }
  if (typeof value === "number") {
    return Number.isInteger(value) ? String(value) : value.toFixed(3);
  }
  if (typeof value === "boolean") {
    return value ? "True" : "False";
  }
  return String(value);
}

function DatasetTable({ dataset }: { dataset: PlotDatasetPreview | null }) {
  if (!dataset) {
    return (
      <div className="empty-panel">
        <p>No dataset preview yet.</p>
        <small>Choose a file to inspect the detected columns, sample rows, and quality flags.</small>
      </div>
    );
  }

  const headers = dataset.column_profiles.map((column) => column.name);
  return (
    <div className="table-shell">
      <table className="dataset-table">
        <thead>
          <tr>
            {headers.map((header) => (
              <th key={header}>{header}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {dataset.sample_rows.slice(0, 6).map((row, rowIndex) => (
            <tr key={`${dataset.dataset_id}-${rowIndex}`}>
              {headers.map((_, cellIndex) => (
                <td key={`${rowIndex}-${cellIndex}`}>{formatCellValue(row[cellIndex])}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function PlotImportScreen({
  inputPath,
  sheet,
  sheetNames,
  inspectionModelLabel,
  dataset,
  inspectionSummary,
  importError,
  importBusy,
  onInputPathChange,
  onBrowse,
  onInspect,
  onSelectSheet,
  onContinue,
}: {
  inputPath: string;
  sheet: string | number;
  sheetNames: string[];
  inspectionModelLabel: string | null;
  dataset: PlotDatasetPreview | null;
  inspectionSummary: {
    warnings: string[];
    signals: string[];
    recommendationSummary?: string;
  } | null;
  importError: string | null;
  importBusy: boolean;
  onInputPathChange: (value: string) => void;
  onBrowse: () => void;
  onInspect: () => void;
  onSelectSheet: (value: string) => void;
  onContinue: () => void;
}) {
  return (
    <section className="workspace-screen import-screen">
      <div className="screen-header-row">
        <div>
          <p className="screen-eyebrow">Plot Import</p>
          <h1 className="screen-title">Load a dataset and confirm what SciPlot sees.</h1>
        </div>
        <div className="toolbar-row">
          <MacButton variant="primary" onClick={onContinue} disabled={!dataset}>
            Continue to templates
          </MacButton>
        </div>
      </div>

      <div className="screen-grid import-grid">
        <MacPanel className="content-panel">
          <div className="card-header">
            <MacStatusPill tone="neutral">Dataset source</MacStatusPill>
            <h3>Choose the file and preview the detected table.</h3>
          </div>
          <div className="toolbar-row">
            <label className="field grow">
              <span className="field-label">Data path</span>
              <input
                value={inputPath}
                onChange={(event) => onInputPathChange(event.target.value)}
                placeholder="/path/to/data.csv"
              />
            </label>
            <MacButton variant="secondary" onClick={onBrowse} icon={<AppIcon name="folder" />}>
              Browse
            </MacButton>
            <MacButton variant="primary" onClick={onInspect} disabled={!inputPath || importBusy}>
              {importBusy ? "Inspecting..." : "Inspect dataset"}
            </MacButton>
          </div>
          {sheetNames.length > 1 ? (
            <div className="field-inline">
              <MacSelect
                label="Workbook sheet"
                value={String(sheet)}
                options={sheetNames.map((name) => ({ value: name, label: name }))}
                onChange={(event) => onSelectSheet(event.target.value)}
              />
            </div>
          ) : null}
          {importError ? <div className="inline-error">{importError}</div> : null}
          <DatasetTable dataset={dataset} />
        </MacPanel>

        <div className="stack-column">
          <MacPanel className="inspector-panel">
            <div className="card-header">
              <MacStatusPill tone="accent">Inspection</MacStatusPill>
              <h3>Detection summary</h3>
            </div>
            {inspectionModelLabel ? (
              <>
                <dl className="detail-list">
                  <div>
                    <dt>Detected model</dt>
                    <dd>{inspectionModelLabel}</dd>
                  </div>
                  <div>
                    <dt>Rows x columns</dt>
                    <dd>
                      {dataset?.raw_rows ?? "-"} x {dataset?.raw_cols ?? "-"}
                    </dd>
                  </div>
                </dl>
                {inspectionSummary?.recommendationSummary ? (
                  <p className="support-copy">{inspectionSummary.recommendationSummary}</p>
                ) : null}
              </>
            ) : (
              <div className="empty-panel">
                <p>No inspection yet.</p>
                <small>The right panel will summarize the detected structure after import.</small>
              </div>
            )}
          </MacPanel>

          <MacPanel className="inspector-panel">
            <div className="card-header">
              <MacStatusPill tone="neutral">Signals</MacStatusPill>
              <h3>Dataset quality notes</h3>
            </div>
            {inspectionSummary ? (
              <ul className="bullet-list">
                {inspectionSummary.signals.length > 0
                  ? inspectionSummary.signals.slice(0, 4).map((signal) => <li key={signal}>{signal}</li>)
                  : <li>No special signals reported.</li>}
                {inspectionSummary.warnings.length > 0
                  ? inspectionSummary.warnings.slice(0, 3).map((warning) => <li key={warning}>{warning}</li>)
                  : null}
              </ul>
            ) : (
              <div className="empty-panel">
                <small>Signals and warnings appear after the sidecar inspects the dataset.</small>
              </div>
            )}
          </MacPanel>
        </div>
      </div>
    </section>
  );
}
