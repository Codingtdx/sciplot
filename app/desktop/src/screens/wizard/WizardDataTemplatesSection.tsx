import type {
  DataTemplateFolderResponse,
  DataTemplateVariant,
} from "../../lib/types";

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
          <h3>Open an example or blank template folder</h3>
        </div>
      </div>

      <p className="hint-text">
        One click generates a folder of chart-type templates. Open a workbook, paste your data,
        then come back and import it into Plot.
      </p>

      <div className="hero-actions">
        <button
          className="ghost-button"
          disabled={loading}
          onClick={() => onBuildFolder("example")}
          type="button"
        >
          {loading ? "Building…" : "Open example template folder"}
        </button>
        <button
          className="ghost-button"
          disabled={loading}
          onClick={() => onBuildFolder("blank")}
          type="button"
        >
          {loading ? "Building…" : "Open blank template folder"}
        </button>
      </div>

      {buildError && <div className="warning-card">{buildError}</div>}

      {latestTemplateFolder && (
        <div className="wizard-section-stack">
          <div className="focus-panel">
            <span>{variantLabel(latestTemplateFolder.variant)} generated</span>
            <strong>{latestTemplateFolder.folder_name}</strong>
            <span className="wizard-template-folder-path">
              <code>{latestTemplateFolder.folder_path}</code>
            </span>
            <span>{latestTemplateFolder.files.length} template files generated</span>
            <div className="wizard-template-file-list" aria-label="Generated template files">
              {latestTemplateFolder.files.map((templateFile) => (
                <code key={templateFile.file_path}>{templateFile.filename}</code>
              ))}
            </div>
          </div>

          {openError && <div className="warning-card">{openError}</div>}

          <div className="step-actions">
            <button className="primary-button" onClick={onOpenTemplateFolder} type="button">
              Open template folder again
            </button>
          </div>
        </div>
      )}
    </article>
  );
}
