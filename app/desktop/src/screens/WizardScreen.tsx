import { useEffect, useMemo, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { PreviewPane } from "../components/PreviewPane";
import { exportRender, inspectFile, openPath } from "../lib/api";
import { applyInspectionToWizard, loadWizardDataFile } from "../lib/project-io";
import { useWizardStore, useWorkbenchStore } from "../lib/store";
import { openDialog } from "../lib/tauri-dialog";
import type { TemplateName, WorkbenchMeta } from "../lib/types";
import {
  compatibleTemplateChoices,
  confirmReplaceWizardSession,
  formatLeaf,
  getErrorMessage,
  incompatibleTemplateChoices,
  isTensileCurveModel,
  publicPaletteChoices,
  publicStyleChoices,
  sizeChoices,
  styleLabel,
  templateLabel,
  toDialogPaths,
} from "../lib/workbench";
import {
  areRenderOptionsEqual,
  mergeRenderOptions,
  sanitizeRenderOptions,
  sanitizeTemplateId,
  selectionFromInspection,
  templateMeta as wizardTemplateMeta,
} from "../lib/wizard";
import { WizardExportSection } from "./wizard/WizardExportSection";
import {
  deriveWizardStep,
  getExpectedWizardOutputs,
  getWizardStatusChip,
} from "./wizard/helpers";
import { WizardOptionsSection } from "./wizard/WizardOptionsSection";
import { useWizardPreflight } from "./wizard/useWizardPreflight";
import { useWizardPreview } from "./wizard/useWizardPreview";
import { WizardTemplatesSection } from "./wizard/WizardTemplatesSection";

export function WizardScreen({ meta }: { meta: WorkbenchMeta | null }) {
  const wizard = useWizardStore(
    useShallow((state) => ({
      busy: state.busy,
      error: state.error,
      inputPath: state.inputPath,
      inspection: state.inspection,
      options: state.options,
      outputs: state.outputs,
      exportResult: state.exportResult,
      preflight: state.preflight,
      previewIndex: state.previewIndex,
      previews: state.previews,
      reset: state.reset,
      setBusy: state.setBusy,
      setError: state.setError,
      setInputPath: state.setInputPath,
      setInspection: state.setInspection,
      setOptions: state.setOptions,
      setOutputs: state.setOutputs,
      setExportResult: state.setExportResult,
      setPreflight: state.setPreflight,
      setPreviewIndex: state.setPreviewIndex,
      setPreviews: state.setPreviews,
      setSheet: state.setSheet,
      setSheetNames: state.setSheetNames,
      setStep: state.setStep,
      setSubmissionReport: state.setSubmissionReport,
      setTemplate: state.setTemplate,
      sheet: state.sheet,
      sheetNames: state.sheetNames,
      sidecarReady: state.sidecarReady,
      step: state.step,
      submissionReport: state.submissionReport,
      template: state.template,
    })),
  );
  const rememberProject = useWorkbenchStore((state) => state.rememberProject);
  const [showAllTemplates, setShowAllTemplates] = useState(false);

  const recommendation = wizard.inspection?.recommendation ?? null;
  const tensileCurveMode = isTensileCurveModel(wizard.inspection?.model);
  const sizeOptions = sizeChoices(meta, wizard.template);
  const styleOptions = publicStyleChoices(meta, wizard.template);
  const paletteOptions = publicPaletteChoices(meta, wizard.template);
  const currentTemplate = useMemo(
    () => wizardTemplateMeta(meta, wizard.template),
    [meta, wizard.template],
  );
  const compatibleTemplates = useMemo(
    () => compatibleTemplateChoices(meta, wizard.inspection?.model),
    [meta, wizard.inspection?.model],
  );
  const incompatibleTemplates = useMemo(
    () => incompatibleTemplateChoices(meta, wizard.inspection?.model),
    [meta, wizard.inspection?.model],
  );
  const recommendedSelection = useMemo(
    () => (wizard.inspection ? selectionFromInspection(meta, wizard.inspection) : null),
    [meta, wizard.inspection],
  );
  const recommendationApplied =
    recommendedSelection != null &&
    wizard.template === recommendedSelection.template &&
    areRenderOptionsEqual(wizard.options, recommendedSelection.options);

  const invalidateRenderState = () => {
    wizard.setPreflight(null);
    wizard.setOutputs([]);
    wizard.setExportResult(null);
    wizard.setSubmissionReport(null);
  };

  const showDialogError = (error: unknown) => {
    wizard.setError(getErrorMessage(error));
  };

  const applyRecommendedSelection = () => {
    if (!recommendedSelection) {
      return;
    }
    invalidateRenderState();
    wizard.setTemplate(recommendedSelection.template);
    wizard.setOptions(recommendedSelection.options);
  };

  const updateWizardTemplate = (value: TemplateName) => {
    const nextTemplate = sanitizeTemplateId(
      meta,
      value,
      recommendation?.template ?? wizard.template,
    );
    if (!nextTemplate) {
      return;
    }
    invalidateRenderState();
    wizard.setTemplate(nextTemplate);
    wizard.setOptions(
      sanitizeRenderOptions(meta, nextTemplate, wizard.options, wizard.inspection?.model),
    );
  };

  const updateWizardOptions = (value: Partial<typeof wizard.options>) => {
    if (!wizard.template) {
      return;
    }
    invalidateRenderState();
    wizard.setOptions(
      mergeRenderOptions(meta, wizard.template, wizard.options, value, wizard.inspection?.model),
    );
  };

  useEffect(() => {
    const nextTemplate = sanitizeTemplateId(
      meta,
      wizard.template,
      recommendation?.template ?? null,
    );
    if (nextTemplate !== wizard.template) {
      wizard.setTemplate(nextTemplate);
    }
    const nextOptions = sanitizeRenderOptions(
      meta,
      nextTemplate,
      wizard.options,
      wizard.inspection?.model,
    );
    if (!areRenderOptionsEqual(nextOptions, wizard.options)) {
      wizard.setOptions(nextOptions);
    }
  }, [
    meta,
    recommendation?.template,
    wizard.inspection?.model,
    wizard.options,
    wizard.setOptions,
    wizard.setTemplate,
    wizard.template,
  ]);

  useEffect(() => {
    setShowAllTemplates(false);
  }, [wizard.inputPath, wizard.inspection?.model]);

  const {
    busy: previewBusy,
    error: previewError,
    activity: previewActivity,
  } = useWizardPreview({
    inputPath: wizard.inputPath,
    sheet: wizard.sheet,
    template: wizard.template,
    options: wizard.options,
    onPreviews: wizard.setPreviews,
  });

  const {
    busy: preflightBusy,
    error: preflightRequestError,
    activity: preflightActivity,
  } = useWizardPreflight({
    inputPath: wizard.inputPath,
    sheet: wizard.sheet,
    template: wizard.template,
    options: wizard.options,
    onPreflight: wizard.setPreflight,
    onSubmissionReport: wizard.setSubmissionReport,
  });

  const blockingErrors = wizard.preflight?.errors ?? [];
  const hasBlockingErrors = blockingErrors.length > 0 || Boolean(preflightRequestError);
  const hasInput = Boolean(wizard.inputPath);
  const hasInspection = wizard.inspection != null;
  const hasTemplate = Boolean(wizard.template);
  const showReviewStage =
    hasTemplate &&
    (wizard.preflight != null ||
      preflightBusy ||
      Boolean(preflightRequestError) ||
      wizard.outputs.length > 0);
  const wizardStage: "empty" | "edit" | "review" = !hasInput
    ? "empty"
    : showReviewStage
      ? "review"
      : "edit";
  const canExport =
    hasInput &&
    hasTemplate &&
    wizard.sidecarReady &&
    !wizard.busy &&
    !previewBusy &&
    !preflightBusy &&
    !hasBlockingErrors &&
    wizard.preflight !== null;

  useEffect(() => {
    const nextStep = deriveWizardStep({
      inputPath: wizard.inputPath,
      inspectionReady: wizard.inspection != null,
      template: wizard.template,
      autoChecking: previewBusy || preflightBusy,
      preflightReady: wizard.preflight != null,
      outputsCount: wizard.outputs.length,
    });
    if (wizard.step !== nextStep) {
      wizard.setStep(nextStep);
    }
  }, [
    preflightBusy,
    previewBusy,
    wizard.inputPath,
    wizard.inspection,
    wizard.outputs.length,
    wizard.preflight,
    wizard.setStep,
    wizard.step,
    wizard.template,
  ]);

  const statusChip = useMemo(
    () =>
      getWizardStatusChip({
        inputPath: wizard.inputPath,
        busy: wizard.busy,
        previewBusy,
        preflightBusy,
        previewActivity,
        preflightActivity,
        hasBlockingErrors,
        outputsCount: wizard.outputs.length,
        preflightReady: wizard.preflight != null,
        inspectionReady: wizard.inspection != null,
      }),
    [
      hasBlockingErrors,
      preflightBusy,
      preflightActivity,
      previewBusy,
      previewActivity,
      wizard.busy,
      wizard.inputPath,
      wizard.inspection,
      wizard.outputs.length,
      wizard.preflight,
    ],
  );

  const expectedOutputs = getExpectedWizardOutputs(wizard.outputs, wizard.preflight);
  const selectedStyleLabel = styleLabel(
    meta,
    wizard.options.style_preset ?? meta?.default_style ?? null,
  );

  const openDataFile = async () => {
    let path: string | undefined;
    wizard.setError(null);
    try {
      const selected = await openDialog({
        multiple: false,
        filters: [
          {
            name: "Data",
            extensions: ["csv", "txt", "tsv", "xlsx", "xlsm"],
          },
        ],
      });
      path = toDialogPaths(selected, 1)[0];
    } catch (error) {
      showDialogError(error);
      return;
    }
    if (!path) {
      return;
    }
    if (
      !confirmReplaceWizardSession(
        {
          inputPath: wizard.inputPath,
          inspection: wizard.inspection,
          template: wizard.template,
          outputs: wizard.outputs,
          exportResult: wizard.exportResult,
        },
        formatLeaf(path),
        path,
      )
    ) {
      return;
    }

    wizard.setBusy(true);
    try {
      const inspected = await loadWizardDataFile(wizard, meta, path);
      rememberProject({
        mode: "wizard",
        kind: "data",
        path: inspected.input_path,
        title: formatLeaf(inspected.input_path),
        detail: `Data file · ${inspected.sheet_names.length} sheets · ${templateLabel(meta, inspected.inspection.recommendation.template)}`,
      });
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  const rerunInspect = async (sheetValue: string | number) => {
    if (!wizard.inputPath) {
      return;
    }

    wizard.setError(null);
    wizard.setBusy(true);
    try {
      const inspected = await inspectFile(wizard.inputPath, sheetValue);
      applyInspectionToWizard(wizard, meta, inspected, { nextStep: "inspect" });
      invalidateRenderState();
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  const runExport = async () => {
    if (!wizard.inputPath || !wizard.template || !wizard.preflight || hasBlockingErrors) {
      return;
    }

    wizard.setError(null);
    wizard.setBusy(true);
    try {
      const response = await exportRender(
        wizard.inputPath,
        wizard.sheet,
        wizard.template,
        wizard.options,
      );
      wizard.setOutputs(response.outputs);
      wizard.setExportResult(response);
      wizard.setSubmissionReport(response.submission_report ?? wizard.submissionReport);
      wizard.setStep("export");
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  const openOutputFolder = async () => {
    const target = wizard.exportResult?.output_dir;
    if (!target) {
      return;
    }
    wizard.setError(null);
    try {
      await openPath(target);
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    }
  };

  const summaryRows = [
    {
      label: "Sheet",
      value:
        typeof wizard.sheet === "string"
          ? wizard.sheet
          : wizard.sheetNames[wizard.sheet] ?? wizard.sheetNames[0] ?? "-",
    },
    {
      label: "Model",
      value: wizard.inspection?.model_label ?? "Waiting for inspect",
    },
    {
      label: "Recommended",
      value: wizard.inspection
        ? templateLabel(meta, wizard.inspection.recommendation.template)
        : "-",
    },
    {
      label: "Style",
      value: selectedStyleLabel,
    },
  ];

  return (
    <div className="desk-layout wizard-layout">
      <section className="desk-main wizard-main">
        {wizardStage === "empty" ? (
          <div className="wizard-empty-shell">
            <article className="work-card hero-card wizard-empty-card">
              <div className="wizard-empty-copy">
                <div className="card-kicker">Plot</div>
                <h2>Open a data file</h2>
                <p>Start with CSV, TXT, TSV, XLSX, or XLSM data.</p>
              </div>

              <div className="wizard-inline-chips wizard-empty-chips">
                <span className={`status-pill ${wizard.sidecarReady ? "good" : "warn"}`}>
                  {wizard.sidecarReady ? "Sidecar ready" : "Sidecar offline"}
                </span>
                <span className={`status-pill ${statusChip.tone}`}>{statusChip.label}</span>
              </div>

              <div className="step-actions">
                <button className="primary-button" onClick={openDataFile} type="button">
                  Open data
                </button>
              </div>

              {wizard.error && <div className="error-card">{wizard.error}</div>}
              {!wizard.sidecarReady && (
                <div className="warning-card">
                  The Python sidecar is offline. Detection, preview, and export resume
                  once it reconnects.
                </div>
              )}
            </article>
          </div>
        ) : (
          <div className="wizard-stage-shell">
            <article className="work-card wizard-stage-toolbar">
              <div className="panel-heading wizard-stage-toolbar-head">
                <div>
                  <div className="card-kicker">Plot</div>
                  <h2>{formatLeaf(wizard.inputPath)}</h2>
                </div>
                <div className="wizard-inline-chips">
                  {hasTemplate && (
                    <span className="signal-tag">{templateLabel(meta, wizard.template)}</span>
                  )}
                  <span className={`status-pill ${statusChip.tone}`}>{statusChip.label}</span>
                </div>
              </div>

              <div className="wizard-toolbar">
                <button className="primary-button" onClick={openDataFile} type="button">
                  Open data
                </button>
                {wizard.sheetNames.length > 1 && (
                  <label className="wizard-inline-field">
                    <span className="field-label">Sheet</span>
                    <select
                      className="field"
                      value={String(wizard.sheet)}
                      onChange={(event) => void rerunInspect(event.target.value)}
                    >
                      {wizard.sheetNames.map((name, index) => (
                        <option key={name} value={name}>
                          {index + 1}. {name}
                        </option>
                      ))}
                    </select>
                  </label>
                )}
                {!recommendationApplied && wizard.inspection && (
                  <button
                    className="ghost-button"
                    onClick={applyRecommendedSelection}
                    type="button"
                  >
                    Use recommendation
                  </button>
                )}
              </div>
            </article>

            <div className="wizard-stage-grid">
              <div className="wizard-preview-column">
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
              </div>

              <aside className="wizard-rail">
                <article className="context-card wizard-summary-card">
                  <div className="panel-heading">
                    <div>
                      <h3>Summary</h3>
                    </div>
                    <span className={`status-pill ${statusChip.tone}`}>{statusChip.label}</span>
                  </div>

                  <div className="wizard-summary-list">
                    {summaryRows.map((row) => (
                      <div className="wizard-summary-row" key={row.label}>
                        <span>{row.label}</span>
                        <strong>{row.value}</strong>
                      </div>
                    ))}
                  </div>

                  {wizard.error && <div className="error-card">{wizard.error}</div>}
                  {!wizard.sidecarReady && (
                    <div className="warning-card">
                      The Python sidecar is offline. Existing state stays visible, but
                      checks and export are paused.
                    </div>
                  )}

                  {wizard.inspection && (
                    <>
                      <details className="wizard-details" open={wizardStage === "edit"}>
                        <summary>Why this type</summary>
                        <div className="wizard-details-body">
                          {wizard.inspection.recommendation.reason}
                        </div>
                      </details>

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

                      {wizard.inspection.signals.length > 0 && (
                        <details className="wizard-details">
                          <summary>{wizard.inspection.signals.length} detection signal(s)</summary>
                          <ul className="bullet-list">
                            {wizard.inspection.signals.map((item) => (
                              <li key={item}>{item}</li>
                            ))}
                          </ul>
                        </details>
                      )}
                    </>
                  )}
                </article>

                {hasInspection && (
                  <WizardTemplatesSection
                    compatibleTemplates={compatibleTemplates}
                    incompatibleTemplates={incompatibleTemplates}
                    inspection={wizard.inspection}
                    onSelectTemplate={updateWizardTemplate}
                    onToggleShowAllTemplates={() =>
                      setShowAllTemplates((current) => !current)
                    }
                    selectedTemplate={wizard.template}
                    showAllTemplates={showAllTemplates}
                  />
                )}

                {hasTemplate && (
                  <WizardOptionsSection
                    currentTemplate={currentTemplate}
                    meta={meta}
                    onUpdateOptions={updateWizardOptions}
                    options={wizard.options}
                    paletteOptions={paletteOptions}
                    sizeOptions={sizeOptions}
                    styleOptions={styleOptions}
                    template={wizard.template}
                    tensileCurveMode={tensileCurveMode}
                  />
                )}

                {showReviewStage && (
                  <WizardExportSection
                    blockingErrors={blockingErrors}
                    canExport={canExport}
                    exportResult={wizard.exportResult}
                    hasExportedOutputs={wizard.outputs.length > 0}
                    onExport={() => void runExport()}
                    onOpenOutputDir={() => void openOutputFolder()}
                    outputItems={expectedOutputs}
                    preflight={wizard.preflight}
                    preflightActivity={preflightActivity}
                    preflightBusy={preflightBusy}
                    preflightRequestError={preflightRequestError}
                    previewActivity={previewActivity}
                    submissionReport={wizard.submissionReport}
                  />
                )}
              </aside>
            </div>
          </div>
        )}
      </section>
    </div>
  );
}
