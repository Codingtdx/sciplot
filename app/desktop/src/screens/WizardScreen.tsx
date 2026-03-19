import { useEffect, useMemo, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { PreviewPane } from "../components/PreviewPane";
import { StepFlow } from "../components/StepFlow";
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
import { WizardDetectSection } from "./wizard/WizardDetectSection";
import { WizardExportSection } from "./wizard/WizardExportSection";
import {
  deriveWizardStep,
  getExpectedWizardOutputs,
  getWizardStatusChip,
} from "./wizard/helpers";
import { WizardOptionsSection } from "./wizard/WizardOptionsSection";
import { useWizardPreflight } from "./wizard/useWizardPreflight";
import { useWizardPreview } from "./wizard/useWizardPreview";
import { WizardSessionCard } from "./wizard/WizardSessionCard";
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
  const canExport =
    Boolean(wizard.inputPath) &&
    Boolean(wizard.template) &&
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

  return (
    <div className="desk-layout wizard-layout">
      <section className="desk-main wizard-main">
        <article className="work-card hero-card wizard-workspace-card">
          <div className="section-head wizard-workspace-head">
            <div>
              <div className="card-kicker">Plot Flow</div>
              <h2>Single-figure workflow</h2>
              <p>
                Import, review, tune essentials, and export from one focused
                workspace.
              </p>
            </div>
            <div className="wizard-inline-chips">
              {wizard.inputPath && <span className="signal-tag">{formatLeaf(wizard.inputPath)}</span>}
              <span className={`status-pill ${statusChip.tone}`}>{statusChip.label}</span>
            </div>
          </div>

          <StepFlow current={wizard.step} />

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

          {wizard.error && <div className="error-card">{wizard.error}</div>}
          {!wizard.sidecarReady && (
            <div className="warning-card">
              The Python sidecar is offline. Detection, preview, and export resume
              as soon as it reconnects.
            </div>
          )}
        </article>

        <div className="wizard-content-grid">
          <div className="wizard-main-stack">
            <WizardDetectSection inspection={wizard.inspection} meta={meta} />

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
          </div>

          <aside className="desk-context wizard-context">
            <PreviewPane
              busy={previewBusy}
              error={previewError}
              onChangeIndex={wizard.setPreviewIndex}
              previewIndex={wizard.previewIndex}
              previews={wizard.previews}
            />

            <WizardSessionCard
              blockingErrorsCount={blockingErrors.length}
              hasBlockingErrors={hasBlockingErrors}
              inputPath={wizard.inputPath}
              inspectionWarningsCount={wizard.inspection?.warnings.length ?? 0}
              meta={meta}
              outputsCount={wizard.outputs.length}
              preflightRequestError={preflightRequestError}
              preflightActivity={preflightActivity}
              preflightWarningsCount={wizard.preflight?.warnings.length ?? 0}
              previewActivity={previewActivity}
              previewsCount={wizard.previews.length}
              sheet={wizard.sheet}
              statusChip={statusChip}
              stylePreset={wizard.options.style_preset ?? meta?.default_style ?? null}
              submissionReport={wizard.submissionReport}
              template={wizard.template}
            />
          </aside>
        </div>
      </section>
    </div>
  );
}
