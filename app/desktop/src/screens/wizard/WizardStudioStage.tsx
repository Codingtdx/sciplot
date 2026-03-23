import type { ReactNode } from "react";

import { PreviewPane } from "../../components/PreviewPane";
import type {
  PreviewItem,
  TemplateName,
  WorkbenchMeta,
} from "../../lib/types";
import { formatLeaf, templateLabel } from "../../lib/workbench";

type SummaryRow = {
  label: string;
  value: string;
};

type Props = {
  inputPath: string;
  sheetNamesLength: number;
  template: TemplateName | null;
  hasTemplate: boolean;
  meta: WorkbenchMeta | null;
  summaryRows: SummaryRow[];
  previewBusy: boolean;
  previewError: string | null;
  previewIndex: number;
  previews: PreviewItem[];
  onChangePreviewIndex(value: number): void;
  onChangeSheet(): void;
  railContent: ReactNode;
};

export function WizardStudioStage({
  inputPath,
  sheetNamesLength,
  template,
  hasTemplate,
  meta,
  summaryRows,
  previewBusy,
  previewError,
  previewIndex,
  previews,
  onChangePreviewIndex,
  onChangeSheet,
  railContent,
}: Props) {
  return (
    <div className="plot-stage-grid plot-studio-grid">
      <section className="plot-preview-column plot-studio-preview">
        <section className="context-card plot-summary-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">File</div>
              <h3>{formatLeaf(inputPath)}</h3>
            </div>
            <div className="wizard-inline-chips">
              {hasTemplate && (
                <span className="signal-tag">{templateLabel(meta, template)}</span>
              )}
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

          {sheetNamesLength > 1 && (
            <div className="hero-actions">
              <button className="ghost-button" onClick={onChangeSheet} type="button">
                Change sheet
              </button>
            </div>
          )}
        </section>

        {hasTemplate ? (
          <PreviewPane
            busy={previewBusy}
            error={previewError}
            onChangeIndex={onChangePreviewIndex}
            previewIndex={previewIndex}
            previews={previews}
          />
        ) : (
          <section className="preview-pane">
            <div className="preview-toolbar">
              <div className="preview-title">Preview</div>
            </div>
            <div className="preview-surface">
              <div className="placeholder-card">
                Select a compatible chart type to start previewing.
              </div>
            </div>
          </section>
        )}
      </section>

      <aside className="plot-stage-rail">{railContent}</aside>
    </div>
  );
}
