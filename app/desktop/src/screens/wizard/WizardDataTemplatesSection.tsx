import type {
  DataTemplateFolderResponse,
  DataTemplateVariant,
} from "../../lib/types";
import { CompactToolbar } from "../../components/workbench/V2Primitives";

type Props = {
  loading: boolean;
  buildError: string | null;
  openError: string | null;
  latestTemplateFolder: DataTemplateFolderResponse | null;
  onBuildFolder(variant: DataTemplateVariant): void;
  onOpenTemplateFolder(): void;
};

function variantLabel(variant: DataTemplateVariant | null) {
  if (variant === "example") {
    return "Example template folder";
  }
  if (variant === "blank") {
    return "Blank template folder";
  }
  return "Template folder";
}

export function WizardDataTemplatesSection({
  loading,
  buildError,
  openError,
  latestTemplateFolder,
  onBuildFolder,
  onOpenTemplateFolder,
}: Props) {
  return (
    <article className="context-card wizard-data-template-card">
      <div className="panel-heading">
        <div>
          <div className="card-kicker">Templates</div>
          <h3>Template files</h3>
        </div>
      </div>

      <CompactToolbar label="Template folder actions">
        <button
          className="ghost-button"
          disabled={loading}
          onClick={() => onBuildFolder("example")}
          type="button"
        >
          {loading ? "Refreshing…" : "Open example folder"}
        </button>
        <button
          className="ghost-button"
          disabled={loading}
          onClick={() => onBuildFolder("blank")}
          type="button"
        >
          {loading ? "Refreshing…" : "Open blank folder"}
        </button>
      </CompactToolbar>

      {buildError && <div className="warning-card">{buildError}</div>}

      {latestTemplateFolder && (
        <div className="wizard-section-stack">
          <div className="focus-panel">
            <span>{variantLabel(latestTemplateFolder.variant)} generated</span>
            <strong>{latestTemplateFolder.folder_name}</strong>
            <span className="wizard-template-folder-path">
              <code>{latestTemplateFolder.folder_path}</code>
            </span>
            <span>{latestTemplateFolder.files.length} template files ready</span>
            <div className="wizard-template-file-list" aria-label="Generated template files">
              {latestTemplateFolder.files.map((templateFile) => (
                <code key={templateFile.file_path}>{templateFile.filename}</code>
              ))}
            </div>
          </div>

          {openError && <div className="warning-card">{openError}</div>}

          <CompactToolbar label="Template folder reopen action">
            <button className="primary-button" onClick={onOpenTemplateFolder} type="button">
              Open folder again
            </button>
          </CompactToolbar>
        </div>
      )}
    </article>
  );
}
