import type { ReactNode } from "react";

import { PreviewPane } from "../../components/PreviewPane";
import { CompactToolbar } from "../../components/workbench/V2Primitives";
import type {
  PreviewItem,
  TemplateName,
  WorkbenchMeta,
} from "../../lib/types";
import { templateLabel } from "../../lib/workbench";

type Props = {
  sheetNamesLength: number;
  template: TemplateName | null;
  hasTemplate: boolean;
  meta: WorkbenchMeta | null;
  previewBusy: boolean;
  previewError: string | null;
  previewIndex: number;
  previews: PreviewItem[];
  onChangePreviewIndex(value: number): void;
  onChangeSheet(): void;
  railContent: ReactNode;
};

export function WizardStudioStage({
  sheetNamesLength,
  template,
  hasTemplate,
  meta,
  previewBusy,
  previewError,
  previewIndex,
  previews,
  onChangePreviewIndex,
  onChangeSheet,
  railContent,
}: Props) {
  return (
    <div className="plot-studio-v2">
      <section className="plot-studio-controls work-card">
        <div className="panel-heading">
          <div>
            <div className="card-kicker">Step Controls</div>
            <h3>{hasTemplate ? templateLabel(meta, template) : "Template selection required"}</h3>
          </div>
        </div>
        {railContent}
      </section>

      <section className="plot-studio-preview-column">
        <CompactToolbar label="Plot preview controls">
          {sheetNamesLength > 1 && (
            <button className="ghost-button" onClick={onChangeSheet} type="button">
              Change sheet
            </button>
          )}
        </CompactToolbar>

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
    </div>
  );
}
