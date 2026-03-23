import { useEffect, useMemo, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { StepFlow } from "../components/StepFlow";
import { useWizardStore, useWorkbenchStore } from "../lib/store";
import type {
  PlotStage,
  TemplateName,
  WorkbenchMeta,
  WorkbenchRoute,
} from "../lib/types";
import {
  PLOT_STAGE_COPY,
  compatibleTemplateChoices,
  formatLeaf,
  getErrorMessage,
  plotRoute,
  publicPaletteChoices,
  publicStyleChoices,
  sizeChoices,
  templateLabel,
  wizardStepForStage,
  incompatibleTemplateChoices,
  isTensileCurveModel,
} from "../lib/workbench";
import {
  areRenderOptionsEqual,
  mergeRenderOptions,
  sanitizeRenderOptions,
  sanitizeTemplateId,
  selectionFromInspection,
  templateMeta as wizardTemplateMeta,
} from "../lib/wizard";
import {
  buildWizardStepFlowItems,
  buildWizardSummaryRows,
  getExpectedWizardOutputs,
  getWizardStatusForPlot,
} from "./wizard/helpers";
import { useWizardActions } from "./wizard/useWizardActions";
import { WizardImportStage } from "./wizard/WizardImportStage";
import { useWizardRecentDataAction } from "./wizard/useWizardRecentDataAction";
import { WizardSheetStage } from "./wizard/WizardSheetStage";
import { WizardStudioStage } from "./wizard/WizardStudioStage";
import { useWizardPreflight } from "./wizard/useWizardPreflight";
import { useWizardPreview } from "./wizard/useWizardPreview";
import { useWizardStageRouting } from "./wizard/useWizardStageRouting";
import { useWizardWorkflowActions } from "./wizard/useWizardWorkflowActions";

export function WizardScreen({
  meta,
  routeStage = useWizardStore.getState().stage,
  onNavigate = () => {},
}: {
  meta: WorkbenchMeta | null;
  routeStage?: PlotStage;
  onNavigate?(route: WorkbenchRoute): void;
}) {
  const wizard = useWizardStore(
    useShallow((state) => ({
      busy: state.busy,
      error: state.error,
      exportResult: state.exportResult,
      inputPath: state.inputPath,
      inspection: state.inspection,
      options: state.options,
      outputs: state.outputs,
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
      setProjectPath: state.setProjectPath,
      setExportResult: state.setExportResult,
      setPreflight: state.setPreflight,
      setPreviewIndex: state.setPreviewIndex,
      setPreviews: state.setPreviews,
      setSheet: state.setSheet,
      setSheetNames: state.setSheetNames,
      setStage: state.setStage,
      setStep: state.setStep,
      setSubmissionReport: state.setSubmissionReport,
      setTemplate: state.setTemplate,
      sheet: state.sheet,
      sheetNames: state.sheetNames,
      sidecarReady: state.sidecarReady,
      stage: state.stage,
      submissionReport: state.submissionReport,
      template: state.template,
    })),
  );
  const rememberProject = useWorkbenchStore((state) => state.rememberProject);
  const recentProjects = useWorkbenchStore((state) => state.recentProjects);
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
  const recentDataFiles = recentProjects.filter((entry) => entry.mode === "wizard" && entry.kind === "data");

  const invalidateRenderState = () => {
    wizard.setPreflight(null);
    wizard.setOutputs([]);
    wizard.setExportResult(null);
    wizard.setSubmissionReport(null);
  };

  const showDialogError = (error: unknown) => {
    wizard.setError(getErrorMessage(error));
  };

  const goToStage = (stage: PlotStage) => {
    wizard.setStage(stage);
    wizard.setStep(wizardStepForStage(stage));
    onNavigate(plotRoute(stage));
  };

  useWizardStageRouting({
    routeStage,
    stage: wizard.stage,
    inputPath: wizard.inputPath,
    sheetNamesLength: wizard.sheetNames.length,
    inspection: wizard.inspection,
    template: wizard.template,
    outputsLength: wizard.outputs.length,
    exportResult: wizard.exportResult,
    setStage: wizard.setStage,
    setStep: wizard.setStep,
    goToStage,
  });

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

  const previewEnabled =
    Boolean(wizard.inputPath) &&
    Boolean(wizard.template) &&
    (routeStage === "type" || routeStage === "tune" || routeStage === "review" || routeStage === "export");
  const preflightEnabled =
    Boolean(wizard.inputPath) &&
    Boolean(wizard.template) &&
    routeStage === "review";

  const {
    busy: previewBusy,
    error: previewError,
    activity: previewActivity,
  } = useWizardPreview({
    enabled: previewEnabled,
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
    enabled: preflightEnabled,
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
  const canExport =
    hasInput &&
    hasTemplate &&
    wizard.sidecarReady &&
    !wizard.busy &&
    !previewBusy &&
    !preflightBusy &&
    !hasBlockingErrors &&
    wizard.preflight !== null;
  const statusChip = getWizardStatusForPlot({
    routeStage,
    busy: wizard.busy,
    previewBusy,
    preflightBusy,
    hasBlockingErrors,
    hasInspection,
    hasInput,
    outputsCount: wizard.outputs.length,
  });
  const stageCopy = PLOT_STAGE_COPY[routeStage];
  const expectedOutputs = getExpectedWizardOutputs(wizard.outputs, wizard.preflight);
  const stepFlowSteps = useMemo(() => buildWizardStepFlowItems({
    routeStage,
    hasInput,
    hasInspection,
    hasTemplate,
    sheetNamesLength: wizard.sheetNames.length,
    preflight: wizard.preflight,
    outputsLength: wizard.outputs.length,
    onSelectStage: goToStage,
  }), [
    hasInput,
    hasInspection,
    hasTemplate,
    routeStage,
    wizard.outputs.length,
    wizard.preflight,
    wizard.sheetNames.length,
  ]);

  const {
    templateFolderBusy,
    templateBuildError,
    templateOpenError,
    latestTemplateFolder,
    openTemplateFolder,
    reopenTemplateFolder,
    openOutputFolder,
  } = useWizardActions({
    exportOutputDir: wizard.exportResult?.output_dir,
    setGlobalError: wizard.setError,
  });
  const { reopenRecentData } = useWizardRecentDataAction({
    wizard,
    meta,
    goToStage,
  });
  const {
    openDataFile,
    rerunInspect,
    runExport,
  } = useWizardWorkflowActions({
    wizard,
    meta,
    hasBlockingErrors,
    rememberProject,
    goToStage,
    invalidateRenderState,
    onDialogError: showDialogError,
  });

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

  const summaryRows = buildWizardSummaryRows({
    inputPath: wizard.inputPath,
    sheet: wizard.sheet,
    sheetNames: wizard.sheetNames,
    inspection: wizard.inspection,
    template: wizard.template,
    meta,
  });

  return (
    <div className={`plot-workspace plot-stage-${routeStage}`}>
      <section className="plot-stage-card work-card section-card">
        <div className="plot-stage-copy">
          <div>
            <div className="card-kicker">Plot</div>
            <h2>{stageCopy.title}</h2>
            <p>{stageCopy.description}</p>
          </div>

          <div className="plot-stage-actions">
            <span className={`status-pill ${statusChip.tone}`}>{statusChip.label}</span>
            {routeStage !== "import" && (
              <button className="ghost-button" onClick={() => goToStage("import")} type="button">
                New file
              </button>
            )}
          </div>
        </div>

        <StepFlow steps={stepFlowSteps} />

        <div className="plot-stage-metrics">
          <div className="stat-tile">
            <span>File</span>
            <strong>{wizard.inputPath ? formatLeaf(wizard.inputPath) : "Waiting for import"}</strong>
          </div>
          <div className="stat-tile">
            <span>Model</span>
            <strong>
              {wizard.inspection ? wizard.inspection.model_label : "Pending inspect"}
            </strong>
          </div>
          <div className="stat-tile">
            <span>Current template</span>
            <strong>{wizard.template ? templateLabel(meta, wizard.template) : "Not selected"}</strong>
          </div>
        </div>

        {wizard.error && <div className="error-card">{wizard.error}</div>}
        {!wizard.sidecarReady && (
          <div className="warning-card">
            The Python sidecar is offline. Detection, preview, and export resume once it
            reconnects.
          </div>
        )}
      </section>

      {routeStage === "import" && (
        <WizardImportStage
          hasInput={hasInput}
          latestTemplateFolder={latestTemplateFolder}
          onBuildTemplateFolder={(variant) => void openTemplateFolder(variant)}
          onOpenDataFile={() => void openDataFile()}
          onReopenRecentData={(path) => void reopenRecentData(path)}
          onReopenTemplateFolder={() => void reopenTemplateFolder()}
          onResumeCurrentSession={() => goToStage("type")}
          recentDataFiles={recentDataFiles}
          summaryRows={summaryRows}
          templateBuildError={templateBuildError}
          templateFolderBusy={templateFolderBusy}
          templateOpenError={templateOpenError}
        />
      )}

      {routeStage === "sheet" && (
        <WizardSheetStage
          inputPath={wizard.inputPath}
          onInspectSheet={(sheetValue) => void rerunInspect(sheetValue)}
          sheet={wizard.sheet}
          sheetNames={wizard.sheetNames}
        />
      )}

      {(routeStage === "type" || routeStage === "tune" || routeStage === "review" || routeStage === "export") && (
        <WizardStudioStage
          blockingErrors={blockingErrors}
          canExport={canExport}
          compatibleTemplates={compatibleTemplates}
          currentTemplate={currentTemplate}
          expectedOutputs={expectedOutputs}
          hasTemplate={hasTemplate}
          incompatibleTemplates={incompatibleTemplates}
          meta={meta}
          onApplyRecommendedSelection={applyRecommendedSelection}
          onGoToStage={goToStage}
          onNavigate={onNavigate}
          onOpenOutputFolder={() => void openOutputFolder()}
          onRunExport={() => void runExport()}
          onSelectTemplate={updateWizardTemplate}
          onToggleShowAllTemplates={() => setShowAllTemplates((current) => !current)}
          onUpdateOptions={updateWizardOptions}
          paletteOptions={paletteOptions}
          preflightActivity={preflightActivity}
          preflightBusy={preflightBusy}
          preflightRequestError={preflightRequestError}
          previewActivity={previewActivity}
          previewBusy={previewBusy}
          previewError={previewError}
          recommendationApplied={recommendationApplied}
          routeStage={routeStage}
          showAllTemplates={showAllTemplates}
          sizeOptions={sizeOptions}
          styleOptions={styleOptions}
          summaryRows={summaryRows}
          tensileCurveMode={tensileCurveMode}
          wizard={wizard}
        />
      )}
    </div>
  );
}
