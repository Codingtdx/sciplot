import type {
  DataTemplateFolderResponse,
  DataTemplateVariant,
  RecentProjectEntry,
} from "../../lib/types";
import { WizardDataTemplatesSection } from "./WizardDataTemplatesSection";

type SummaryRow = {
  label: string;
  value: string;
};

type Props = {
  hasInput: boolean;
  summaryRows: SummaryRow[];
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
  hasInput,
  summaryRows,
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
  return (
    <div className="plot-stage-grid import-stage">
      <section className="work-card plot-import-card plot-import-canvas">
        <div className="panel-heading">
          <div>
            <div className="card-kicker">Start</div>
            <h3>Open a data file</h3>
          </div>
        </div>

        <div className="hero-actions plot-import-actions">
          <button className="primary-button" onClick={onOpenDataFile} type="button">
            Open data
          </button>
          {hasInput && (
            <button className="ghost-button" onClick={onResumeCurrentSession} type="button">
              Resume current session
            </button>
          )}
        </div>

        <div className="plot-import-format-strip">
          <span className="signal-tag">CSV / TXT / TSV</span>
          <span className="signal-tag">XLSX / XLSM</span>
          <span className="signal-tag">Inspect runs automatically</span>
        </div>

        <WizardDataTemplatesSection
          buildError={templateBuildError}
          openError={templateOpenError}
          latestTemplateFolder={latestTemplateFolder}
          loading={templateFolderBusy}
          onBuildFolder={onBuildTemplateFolder}
          onOpenTemplateFolder={onReopenTemplateFolder}
        />
      </section>

      <aside className="plot-stage-rail">
        <article className="context-card plot-session-overview-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Session</div>
              <h3>Current session</h3>
            </div>
          </div>
          <div className="summary-grid wizard-tight-grid">
            {summaryRows.map((row) => (
              <div className="stat-tile" key={row.label}>
                <span>{row.label}</span>
                <strong>{row.value}</strong>
              </div>
            ))}
          </div>
        </article>

        <article className="context-card plot-import-recents-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Recent</div>
              <h3>Recent data</h3>
            </div>
          </div>

          {recentDataFiles.length === 0 ? (
            <div className="placeholder-card">No recent data files yet.</div>
          ) : (
            <div className="launchpad-recent-list plot-import-recent-list">
              {recentDataFiles.slice(0, 4).map((entry) => (
                <button
                  className="launchpad-recent-row"
                  key={entry.id}
                  onClick={() => onReopenRecentData(entry.path)}
                  type="button"
                >
                  <strong>{entry.title}</strong>
                  <span>{entry.detail}</span>
                </button>
              ))}
            </div>
          )}
        </article>
      </aside>
    </div>
  );
}
