import { useState } from "react";
import type {
  DataTemplateFolderResponse,
  DataTemplateVariant,
  RecentProjectEntry,
} from "../../lib/types";
import { CompactListRow } from "../../components/workbench/V2Primitives";
import { formatLeaf } from "../../lib/workbench";

type Props = {
  inputPath: string | null;
  hasInput: boolean;
  sidecarReady: boolean;
  error: string | null;
  recentDataFiles: RecentProjectEntry[];
  templateFolderBusy: boolean;
  templateBuildError: string | null;
  templateOpenError: string | null;
  latestTemplateFolder: DataTemplateFolderResponse | null;
  onOpenDataFile(): void;
  onResumeCurrentSession(): void;
  onBuildTemplateFolder(variant: DataTemplateVariant): void;
  onReopenTemplateFolder(): void;
  onReopenRecentData(path: string): void;
};

export function WizardImportStage({
  inputPath,
  hasInput,
  sidecarReady,
  error,
  recentDataFiles,
  templateFolderBusy,
  templateBuildError,
  templateOpenError,
  latestTemplateFolder,
  onOpenDataFile,
  onResumeCurrentSession,
  onBuildTemplateFolder,
  onReopenTemplateFolder,
  onReopenRecentData,
}: Props) {
  const [activePreviewTab, setActivePreviewTab] = useState<
    "preview" | "inspect" | "mapping" | "template" | "logs"
  >("preview");
  const statusText = !sidecarReady
    ? "Sidecar offline. Import and inspect will resume when runtime is available."
    : hasInput
      ? "Data source loaded. Continue to choose chart type."
      : "Your app requires data to generate plots.";
  const sourceLabel = formatLeaf(inputPath ?? recentDataFiles[0]?.path ?? "No source loaded");

  return (
    <div className="plot-import-studio">
      <header className="plot-import-header">
        <div className="plot-import-header-copy">
          <strong>Data intake workspace</strong>
          <p>Load a source file, inspect structure, then continue to chart selection.</p>
        </div>
        {hasInput && (
          <div className="plot-import-header-source">
            <span>Source</span>
            <strong title={sourceLabel}>{sourceLabel}</strong>
          </div>
        )}
      </header>

      <div className="plot-import-studio-grid">
        <section className="plot-import-source-pane">
          <div className="plot-import-pane-head">
            <span>Data source</span>
            <h2>Import a data file</h2>
            <p>
              Choose a data source for your plot. Upload a file or open recent data.
            </p>
            <div className="plot-import-supported-types">
              Supported: CSV, TSV, TXT, XLSX, XLSM
            </div>
          </div>

          <div className="plot-import-dropzone" role="group" aria-label="Data upload area">
            <p className="plot-import-dropzone-title">Drag &amp; drop file here or click to upload</p>
            <p className="plot-import-dropzone-subtitle">
              CSV / TXT / TSV / XLSX / XLSM · max 200 MB
            </p>
            <button
              className="plot-import-upload-button"
              onClick={onOpenDataFile}
              type="button"
            >
              Open data
            </button>
          </div>

          <div className="plot-import-helper-actions">
            <button
              className="plot-import-inline-action"
              disabled={templateFolderBusy}
              onClick={() => onBuildTemplateFolder("example")}
              type="button"
            >
              {templateFolderBusy ? "Refreshing…" : "Open example folder"}
            </button>
            <button
              className="plot-import-inline-action"
              disabled={templateFolderBusy}
              onClick={() => onBuildTemplateFolder("blank")}
              type="button"
            >
              {templateFolderBusy ? "Refreshing…" : "Open blank folder"}
            </button>
            {hasInput && (
              <button
                className="plot-import-inline-action"
                onClick={onResumeCurrentSession}
                type="button"
              >
                Resume current session
              </button>
            )}
          </div>

          {templateBuildError && <div className="warning-card">{templateBuildError}</div>}
          {templateOpenError && <div className="warning-card">{templateOpenError}</div>}
          {error && <div className="error-card">{error}</div>}

          {latestTemplateFolder && (
            <div className="plot-import-template-summary">
              <div className="plot-import-template-head">
                <strong>{latestTemplateFolder.folder_name}</strong>
                <button className="plot-import-inline-action" onClick={onReopenTemplateFolder} type="button">
                  Open folder again
                </button>
              </div>
              <span>{latestTemplateFolder.folder_path}</span>
              <span>{latestTemplateFolder.files.length} template files ready</span>
              <div className="plot-import-template-files">
                {latestTemplateFolder.files.map((templateFile) => (
                  <code key={templateFile.file_path}>{templateFile.filename}</code>
                ))}
              </div>
            </div>
          )}

          <div className="plot-import-recent-section">
            <strong>Recent data</strong>
            {recentDataFiles.length === 0 ? (
              <div className="plot-import-empty-row">No recent data files yet.</div>
            ) : (
              <div className="plot-import-recent-list">
                {recentDataFiles.slice(0, 4).map((entry) => (
                  <CompactListRow
                    key={entry.id}
                    onSelect={() => onReopenRecentData(entry.path)}
                    subtitle={entry.detail}
                    title={entry.title}
                  />
                ))}
              </div>
            )}
          </div>
        </section>

        <section className="plot-import-preview-pane">
          <div className="plot-import-preview-tabs" role="tablist" aria-label="Import preview tabs">
            {[
              { id: "preview", label: "Preview" },
              { id: "inspect", label: "Inspect" },
              { id: "mapping", label: "Mapping" },
              { id: "template", label: "Template" },
              { id: "logs", label: "Logs" },
            ].map((tab) => (
              <button
                aria-selected={activePreviewTab === tab.id}
                className={`plot-import-preview-tab ${activePreviewTab === tab.id ? "active" : ""}`}
                key={tab.id}
                onClick={() =>
                  setActivePreviewTab(tab.id as "preview" | "inspect" | "mapping" | "template" | "logs")
                }
                role="tab"
                type="button"
              >
                {tab.label}
              </button>
            ))}
          </div>

          <div className="plot-import-preview-surface">
            {!hasInput ? (
              <div className="plot-import-preview-workspace empty">
                <div className="plot-import-preview-meta-strip">
                  <span>Rows —</span>
                  <span>Columns —</span>
                  <span>Sheet —</span>
                </div>
                <div className="plot-import-preview-layout">
                  <div className="plot-import-preview-table-placeholder">
                    <div className="plot-import-preview-table-head">
                      <span>Column</span>
                      <span>Type</span>
                      <span>Unit</span>
                    </div>
                    <div className="plot-import-preview-table-row" />
                    <div className="plot-import-preview-table-row" />
                    <div className="plot-import-preview-table-row" />
                  </div>
                  <div className="plot-import-preview-chart-placeholder">
                    <div className="plot-import-preview-chart-grid" />
                  </div>
                </div>
                <div className="plot-import-preview-readiness">
                  <strong>Next after import</strong>
                  <div className="plot-import-preview-readiness-items">
                    <span>Detect data model</span>
                    <span>Recommend compatible templates</span>
                    <span>Initialize mapping and preview context</span>
                  </div>
                </div>
                <p className="plot-import-preview-note">
                  Import a source to inspect detected fields, mappings, and preview readiness.
                </p>
              </div>
            ) : (
              <div className="plot-import-preview-workspace ready">
                <div className="plot-import-preview-meta-strip">
                  <span>Rows pending inspect</span>
                  <span>Columns pending inspect</span>
                  <span>{formatLeaf(inputPath ?? "")}</span>
                </div>
                <div className="plot-import-preview-layout">
                  <div className="plot-import-preview-loaded-card">
                    <strong>Loaded source</strong>
                    <span>{sourceLabel}</span>
                    <span>Continue to Type to run compatibility and template recommendation.</span>
                  </div>
                  <div className="plot-import-preview-chart-placeholder active">
                    <div className="plot-import-preview-chart-grid" />
                  </div>
                </div>
                <div className="plot-import-preview-readiness ready">
                  <strong>Import state</strong>
                  <div className="plot-import-preview-readiness-items">
                    <span>Source attached</span>
                    <span>Ready for model detection</span>
                    <span>Ready to continue to Type</span>
                  </div>
                </div>
              </div>
            )}
          </div>
        </section>
      </div>

      <footer className="plot-import-studio-footer">
        <span>{statusText}</span>
        <div className="plot-import-footer-actions">
          <button
            className="plot-import-continue"
            disabled={!hasInput}
            onClick={onResumeCurrentSession}
            type="button"
          >
            Continue
          </button>
        </div>
      </footer>
    </div>
  );
}
