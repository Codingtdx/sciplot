import { useEffect, useMemo, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { useWizardStore, useWorkbenchStore } from "../lib/store";
import type {
  PlotStage,
  TemplateName,
  WorkbenchMeta,
  WorkbenchRoute,
} from "../lib/types";
import {
  compatibleTemplateChoices,
  getErrorMessage,
  plotRoute,
  publicPaletteChoices,
  publicStyleChoices,
  sizeChoices,
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
  getExpectedWizardOutputs,
} from "./wizard/helpers";
import { useWizardActions } from "./wizard/useWizardActions";
import { WizardImportStage } from "./wizard/WizardImportStage";
import { useWizardRecentDataAction } from "./wizard/useWizardRecentDataAction";
import { WizardSheetStage } from "./wizard/WizardSheetStage";
import { WizardStudioStage } from "./wizard/WizardStudioStage";
import { WizardTypeStage } from "./wizard/WizardTypeStage";
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
  const expectedOutputs = getExpectedWizardOutputs(wizard.outputs, wizard.preflight);

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

  if (routeStage === "type") {
    return (
      <div className="plot-workspace plot-stage-type plot-type-route-v2">
        <WizardTypeStage
          compatibleTemplates={compatibleTemplates}
          hasTemplate={hasTemplate}
          incompatibleTemplates={incompatibleTemplates}
          inputPath={wizard.inputPath}
          inspection={wizard.inspection}
          meta={meta}
          onApplyRecommendedSelection={applyRecommendedSelection}
          onChangePreviewIndex={wizard.setPreviewIndex}
          onChangeSheet={() => goToStage("sheet")}
          onContinueToTune={() => goToStage("tune")}
          onSelectTemplate={updateWizardTemplate}
          onToggleShowAllTemplates={() => setShowAllTemplates((current) => !current)}
          previewBusy={previewBusy}
          previewError={previewError}
          previewIndex={wizard.previewIndex}
          previews={wizard.previews}
          recommendationApplied={recommendationApplied}
          selectedTemplate={wizard.template}
          sheetNamesLength={wizard.sheetNames.length}
          showAllTemplates={showAllTemplates}
        />
      </div>
    );
  }

  if (routeStage === "import") {
    return (
      <div className="plot-workspace plot-stage-import plot-import-route-v2">
        <WizardImportStage
          error={wizard.error}
          hasInput={hasInput}
          inputPath={wizard.inputPath}
          latestTemplateFolder={latestTemplateFolder}
          onBuildTemplateFolder={(variant) => void openTemplateFolder(variant)}
          onOpenDataFile={() => void openDataFile()}
          onReopenRecentData={(path) => void reopenRecentData(path)}
          onReopenTemplateFolder={() => void reopenTemplateFolder()}
          onResumeCurrentSession={() => goToStage("type")}
          recentDataFiles={recentDataFiles}
          sidecarReady={wizard.sidecarReady}
          templateBuildError={templateBuildError}
          templateFolderBusy={templateFolderBusy}
          templateOpenError={templateOpenError}
        />
      </div>
    );
  }

  if (routeStage === "sheet") {
    return (
      <div className="plot-workspace plot-stage-sheet plot-sheet-v2">
        <WizardSheetStage
          inputPath={wizard.inputPath}
          onInspectSheet={(sheetValue) => void rerunInspect(sheetValue)}
          sheet={wizard.sheet}
          sheetNames={wizard.sheetNames}
        />
      </div>
    );
  }

  return (
    <WizardStudioStage
      blockingErrors={blockingErrors}
      canExport={canExport}
      currentTemplate={currentTemplate}
      exportResult={wizard.exportResult}
      hasExportedOutputs={wizard.outputs.length > 0}
      hasTemplate={hasTemplate}
      inputPath={wizard.inputPath}
      inspection={wizard.inspection}
      meta={meta}
      onBackToReview={() => goToStage("review")}
      onBackToTune={() => goToStage("tune")}
      onBackToType={() => goToStage("type")}
      onChangePreviewIndex={wizard.setPreviewIndex}
      onChangeSheet={() => goToStage("sheet")}
      onContinueToReview={() => goToStage("review")}
      onExport={() => void runExport()}
      onOpenComposer={() => onNavigate("/composer")}
      onOpenOutputFolder={() => void openOutputFolder()}
      onStartAnotherPlot={() => {
        wizard.reset();
        goToStage("import");
      }}
      onUpdateOptions={updateWizardOptions}
      options={wizard.options}
      outputItems={expectedOutputs}
      outputsLength={wizard.outputs.length}
      paletteOptions={paletteOptions}
      preflight={wizard.preflight}
      preflightBusy={preflightBusy}
      preflightRequestError={preflightRequestError}
      previewBusy={previewBusy}
      previewError={previewError}
      previewIndex={wizard.previewIndex}
      previews={wizard.previews}
      routeStage={routeStage}
      sheetNamesLength={wizard.sheetNames.length}
      sizeOptions={sizeOptions}
      styleOptions={styleOptions}
      submissionReport={wizard.submissionReport}
      template={wizard.template}
      tensileCurveMode={tensileCurveMode}
    />
  );
}
