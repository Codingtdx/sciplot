import { PreviewPane } from "../../components/PreviewPane";
import type {
  ExportResponse,
  InputInspection,
  PlotStage,
  PreflightResult,
  PreviewItem,
  RenderOptionsPayload,
  RequestActivity,
  SubmissionReport,
  TemplateName,
  WorkbenchMeta,
  WorkbenchPalette,
  WorkbenchRoute,
  WorkbenchStyle,
  WorkbenchTemplate,
} from "../../lib/types";
import { formatLeaf, templateLabel } from "../../lib/workbench";
import { WizardExportSection } from "./WizardExportSection";
import { WizardOptionsSection } from "./WizardOptionsSection";
import { WizardTemplatesSection } from "./WizardTemplatesSection";

type SummaryRow = {
  label: string;
  value: string;
};

type WizardView = {
  inputPath: string;
  sheetNames: string[];
  inspection: InputInspection | null;
  template: TemplateName | null;
  options: RenderOptionsPayload;
  preflight: PreflightResult | null;
  previewIndex: number;
  previews: PreviewItem[];
  outputs: string[];
  exportResult: ExportResponse | null;
  submissionReport: SubmissionReport | null;
  setPreviewIndex(value: number): void;
  reset(): void;
};

type Props = {
  routeStage: PlotStage;
  wizard: WizardView;
  meta: WorkbenchMeta | null;
  hasTemplate: boolean;
  summaryRows: SummaryRow[];
  previewBusy: boolean;
  previewError: string | null;
  previewActivity: RequestActivity;
  preflightBusy: boolean;
  preflightActivity: RequestActivity;
  preflightRequestError: string | null;
  blockingErrors: string[];
  canExport: boolean;
  expectedOutputs: string[];
  recommendationApplied: boolean;
  showAllTemplates: boolean;
  tensileCurveMode: boolean;
  currentTemplate: WorkbenchTemplate | null;
  compatibleTemplates: WorkbenchTemplate[];
  incompatibleTemplates: WorkbenchTemplate[];
  sizeOptions: Array<{ id: string; label: string }>;
  styleOptions: WorkbenchStyle[];
  paletteOptions: WorkbenchPalette[];
  onApplyRecommendedSelection(): void;
  onToggleShowAllTemplates(): void;
  onSelectTemplate(value: TemplateName): void;
  onUpdateOptions(value: Partial<RenderOptionsPayload>): void;
  onRunExport(): void;
  onOpenOutputFolder(): void;
  onGoToStage(stage: PlotStage): void;
  onNavigate(route: WorkbenchRoute): void;
};

export function WizardStudioStage({
  routeStage,
  wizard,
  meta,
  hasTemplate,
  summaryRows,
  previewBusy,
  previewError,
  previewActivity,
  preflightBusy,
  preflightActivity,
  preflightRequestError,
  blockingErrors,
  canExport,
  expectedOutputs,
  recommendationApplied,
  showAllTemplates,
  tensileCurveMode,
  currentTemplate,
  compatibleTemplates,
  incompatibleTemplates,
  sizeOptions,
  styleOptions,
  paletteOptions,
  onApplyRecommendedSelection,
  onToggleShowAllTemplates,
  onSelectTemplate,
  onUpdateOptions,
  onRunExport,
  onOpenOutputFolder,
  onGoToStage,
  onNavigate,
}: Props) {
  return (
    <div className="plot-stage-grid plot-studio-grid">
      <section className="plot-preview-column plot-studio-preview">
        <section className="context-card plot-summary-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">File</div>
              <h3>{formatLeaf(wizard.inputPath)}</h3>
            </div>
            <div className="wizard-inline-chips">
              {hasTemplate && (
                <span className="signal-tag">{templateLabel(meta, wizard.template)}</span>
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

          {wizard.sheetNames.length > 1 && (
            <div className="hero-actions">
              <button className="ghost-button" onClick={() => onGoToStage("sheet")} type="button">
                Change sheet
              </button>
            </div>
          )}
        </section>

        {hasTemplate ? (
          <PreviewPane
            busy={previewBusy}
            error={previewError}
            onChangeIndex={wizard.setPreviewIndex}
            previewIndex={wizard.previewIndex}
            previews={wizard.previews}
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

      <aside className="plot-stage-rail">
        {routeStage === "type" && (
          <>
            {wizard.inspection && (
              <article className="context-card">
                <div className="panel-heading">
                  <div>
                    <div className="card-kicker">Detect</div>
                    <h3>Recommendation</h3>
                  </div>
                  {!recommendationApplied && (
                    <button
                      className="ghost-button"
                      onClick={onApplyRecommendedSelection}
                      type="button"
                    >
                      Use recommendation
                    </button>
                  )}
                </div>

                <div className="wizard-details-body">
                  <div>{wizard.inspection.recommendation.reason}</div>
                </div>

                {wizard.inspection.warnings.length > 0 && (
                  <details className="wizard-details">
                    <summary>{wizard.inspection.warnings.length} input warning(s)</summary>
                    <ul className="bullet-list">
                      {wizard.inspection.warnings.map((item) => (
                        <li key={item}>{item}</li>
                      ))}
                    </ul>
                  </details>
                )}
              </article>
            )}

            <WizardTemplatesSection
              compatibleTemplates={compatibleTemplates}
              incompatibleTemplates={incompatibleTemplates}
              inspection={wizard.inspection}
              onSelectTemplate={onSelectTemplate}
              onToggleShowAllTemplates={onToggleShowAllTemplates}
              selectedTemplate={wizard.template}
              showAllTemplates={showAllTemplates}
            />

            <div className="hero-actions">
              <button
                className="primary-button"
                disabled={!hasTemplate}
                onClick={() => onGoToStage("tune")}
                type="button"
              >
                Continue to tune
              </button>
            </div>
          </>
        )}

        {routeStage === "tune" && (
          <>
            <WizardOptionsSection
              currentTemplate={currentTemplate}
              meta={meta}
              onUpdateOptions={onUpdateOptions}
              options={wizard.options}
              paletteOptions={paletteOptions}
              sizeOptions={sizeOptions}
              styleOptions={styleOptions}
              template={wizard.template}
              tensileCurveMode={tensileCurveMode}
            />

            <div className="hero-actions">
              <button className="ghost-button" onClick={() => onGoToStage("type")} type="button">
                Back to type
              </button>
              <button
                className="primary-button"
                disabled={!hasTemplate}
                onClick={() => onGoToStage("review")}
                type="button"
              >
                Continue to review
              </button>
            </div>
          </>
        )}

        {routeStage === "review" && (
          <>
            <WizardExportSection
              blockingErrors={blockingErrors}
              canExport={canExport}
              exportResult={wizard.exportResult}
              hasExportedOutputs={wizard.outputs.length > 0}
              onExport={onRunExport}
              onOpenOutputDir={onOpenOutputFolder}
              outputItems={expectedOutputs}
              preflight={wizard.preflight}
              preflightActivity={preflightActivity}
              preflightBusy={preflightBusy}
              preflightRequestError={preflightRequestError}
              previewActivity={previewActivity}
              submissionReport={wizard.submissionReport}
            />

            <div className="hero-actions">
              <button className="ghost-button" onClick={() => onGoToStage("tune")} type="button">
                Back to tune
              </button>
            </div>
          </>
        )}

        {routeStage === "export" && (
          <>
            <article className="context-card wizard-review-card">
              <div className="panel-heading">
                <div>
                  <div className="card-kicker">Export</div>
                  <h3>Bundle complete</h3>
                </div>
                <span className="status-pill good">Ready</span>
              </div>

              <div className="wizard-section-stack">
                <div className="success-card">
                  Exported {wizard.outputs.length} file(s) to {formatLeaf(wizard.exportResult?.output_dir ?? "output")}.
                </div>

                <div className="step-actions">
                  <button
                    className="primary-button"
                    disabled={!wizard.exportResult?.output_dir}
                    onClick={onOpenOutputFolder}
                    type="button"
                  >
                    Open output folder
                  </button>
                  <button className="ghost-button" onClick={() => onNavigate("/composer")} type="button">
                    Open Composer
                  </button>
                  <button
                    className="ghost-button"
                    onClick={() => {
                      wizard.reset();
                      onGoToStage("import");
                    }}
                    type="button"
                  >
                    Start another plot
                  </button>
                </div>

                <details className="wizard-details" open>
                  <summary>Output files</summary>
                  <ul className="output-list">
                    {wizard.outputs.map((item) => (
                      <li key={item}>{formatLeaf(item)}</li>
                    ))}
                  </ul>
                </details>

                {wizard.submissionReport && (
                  <div className="focus-panel">
                    <strong>Submission review</strong>
                    <span>{wizard.submissionReport.summary}</span>
                  </div>
                )}
              </div>
            </article>

            <div className="hero-actions">
              <button className="ghost-button" onClick={() => onGoToStage("review")} type="button">
                Re-open review
              </button>
            </div>
          </>
        )}
      </aside>
    </div>
  );
}
