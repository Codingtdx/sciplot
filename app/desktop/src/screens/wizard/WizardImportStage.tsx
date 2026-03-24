import type {
  DataTemplateFolderResponse,
  DataTemplateVariant,
  RecentProjectEntry,
} from "../../lib/types";
import { CompactListRow, CompactToolbar } from "../../components/workbench/V2Primitives";
import { WizardDataTemplatesSection } from "./WizardDataTemplatesSection";

type Props = {
  hasInput: boolean;
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
    <section className="work-card plot-import-card plot-import-v2">
      <div className="panel-heading">
        <div>
          <div className="card-kicker">Import</div>
          <h3>Open a data file</h3>
        </div>
      </div>

      <CompactToolbar label="Plot import actions">
        <button className="primary-button prominent" onClick={onOpenDataFile} type="button">
          Open data
        </button>
        {hasInput && (
          <button className="ghost-button" onClick={onResumeCurrentSession} type="button">
            Resume current session
          </button>
        )}
      </CompactToolbar>

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

      <div className="wizard-section-stack">
        <strong className="field-label">Recent data</strong>
        {recentDataFiles.length === 0 ? (
          <div className="placeholder-card">No recent data files yet.</div>
        ) : (
          recentDataFiles.slice(0, 4).map((entry) => (
            <CompactListRow
              key={entry.id}
              onSelect={() => onReopenRecentData(entry.path)}
              subtitle={entry.detail}
              title={entry.title}
            />
          ))
        )}
      </div>
    </section>
  );
}
