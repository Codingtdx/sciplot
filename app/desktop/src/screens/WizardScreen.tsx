import { useEffect, useMemo, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { StepFlow } from "../components/StepFlow";
import { PreviewPane } from "../components/PreviewPane";
import { exportRender, inspectFile, openPath } from "../lib/api";
import { applyInspectionToWizard, loadWizardDataFile } from "../lib/project-io";
import { useWizardStore, useWorkbenchStore } from "../lib/store";
import type { PlotStage, TemplateName, WorkbenchMeta, WorkbenchRoute } from "../lib/types";
import { openDialog } from "../lib/tauri-dialog";
import {
  PLOT_STAGE_COPY,
  compatibleTemplateChoices,
  confirmReplaceWizardSession,
  formatLeaf,
  getErrorMessage,
  plotRoute,
  publicPaletteChoices,
  publicStyleChoices,
  sizeChoices,
  styleLabel,
  templateLabel,
  toDialogPaths,
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
import { WizardExportSection } from "./wizard/WizardExportSection";
import { WizardOptionsSection } from "./wizard/WizardOptionsSection";
import { WizardTemplatesSection } from "./wizard/WizardTemplatesSection";
import { useWizardPreflight } from "./wizard/useWizardPreflight";
import { useWizardPreview } from "./wizard/useWizardPreview";

function statusForPlot(args: {
  routeStage: PlotStage;
  busy: boolean;
  previewBusy: boolean;
  preflightBusy: boolean;
  hasBlockingErrors: boolean;
  hasInspection: boolean;
  hasInput: boolean;
  outputsCount: number;
}) {
  if (!args.hasInput) {
    return { label: "Waiting for a file", tone: "warn" as const };
  }
  if (args.busy) {
    return { label: "Loading file", tone: "accent" as const };
  }
  if (args.preflightBusy) {
    return { label: "Checking readiness", tone: "accent" as const };
  }
  if (args.previewBusy) {
    return { label: "Refreshing preview", tone: "accent" as const };
  }
  if (args.outputsCount > 0 && args.routeStage === "export") {
    return { label: "Export complete", tone: "good" as const };
  }
  if (args.hasBlockingErrors) {
    return { label: "Fix blockers", tone: "warn" as const };
  }
  if (args.routeStage === "review" && args.hasInspection) {
    return { label: "Reviewing export", tone: "accent" as const };
  }
  if (args.routeStage === "type" && args.hasInspection) {
    return { label: "Recommendation ready", tone: "good" as const };
  }
  return { label: "In progress", tone: "accent" as const };
}

function outputItems(outputs: string[], expectedFilenames: string[]) {
  if (outputs.length > 0) {
    return outputs;
  }
  return expectedFilenames;
}

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

  useEffect(() => {
    if (wizard.stage !== routeStage) {
      wizard.setStage(routeStage);
      wizard.setStep(wizardStepForStage(routeStage));
    }
  }, [routeStage, wizard.setStage, wizard.setStep, wizard.stage]);

  useEffect(() => {
    if (!wizard.inputPath && routeStage !== "import") {
      goToStage("import");
      return;
    }
    if (wizard.inputPath && wizard.sheetNames.length <= 1 && routeStage === "sheet") {
      goToStage("type");
      return;
    }
    if (!wizard.inspection && (routeStage === "type" || routeStage === "tune" || routeStage === "review")) {
      goToStage("import");
      return;
    }
    if (!wizard.template && (routeStage === "tune" || routeStage === "review")) {
      goToStage("type");
      return;
    }
    if (routeStage === "export" && wizard.outputs.length === 0 && !wizard.exportResult) {
      goToStage("review");
    }
  }, [
    routeStage,
    wizard.exportResult,
    wizard.inputPath,
    wizard.inspection,
    wizard.outputs.length,
    wizard.sheetNames.length,
    wizard.template,
  ]);

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
  const statusChip = statusForPlot({
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
  const expectedOutputs = outputItems(
    wizard.outputs,
    (wizard.preflight?.output_filenames ?? []).map((filename) => filename),
  );
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
      goToStage(inspected.sheet_names.length > 1 ? "sheet" : "type");
    } catch (error) {
      wizard.setError(getErrorMessage(error));
    } finally {
      wizard.setBusy(false);
    }
  };

  const reopenRecentData = async (path: string) => {
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
    wizard.setError(null);
    try {
      const inspected = await loadWizardDataFile(wizard, meta, path);
      goToStage(inspected.sheet_names.length > 1 ? "sheet" : "type");
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
      applyInspectionToWizard(wizard, meta, inspected, { nextStage: "type" });
      invalidateRenderState();
      goToStage("type");
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
      goToStage("export");
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

  const summaryRows = [
    {
      label: "File",
      value: wizard.inputPath ? formatLeaf(wizard.inputPath) : "No file selected",
    },
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
      label: "Template",
      value: wizard.template ? templateLabel(meta, wizard.template) : "Not selected",
    },
    {
      label: "Style",
      value: selectedStyleLabel,
    },
  ];

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

        <StepFlow current={routeStage} />

        <div className="plot-stage-metrics">
          <div className="focus-panel">
            <span>File</span>
            <strong>{wizard.inputPath ? formatLeaf(wizard.inputPath) : "Waiting for import"}</strong>
          </div>
          <div className="focus-panel">
            <span>Recommended type</span>
            <strong>
              {wizard.inspection
                ? templateLabel(meta, wizard.inspection.recommendation.template)
                : "Pending inspect"}
            </strong>
          </div>
          <div className="focus-panel">
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
        <div className="plot-stage-grid import-stage">
          <section className="work-card plot-import-card plot-import-canvas">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Start</div>
                <h3>Open a data file</h3>
              </div>
            </div>

            <p className="hint-text">
              Start with CSV, TXT, TSV, XLSX, or XLSM data. Multi-sheet workbooks move to the
              sheet selector next.
            </p>

            <div className="hero-actions plot-import-actions">
              <button className="primary-button" onClick={openDataFile} type="button">
                Open data
              </button>
              {hasInput && (
                <button className="ghost-button" onClick={() => goToStage("type")} type="button">
                  Resume current session
                </button>
              )}
            </div>

            <div className="plot-import-format-strip">
              <span className="signal-tag">CSV / TXT / TSV</span>
              <span className="signal-tag">XLSX / XLSM</span>
              <span className="signal-tag">Inspect runs automatically</span>
            </div>
          </section>

          <aside className="plot-stage-rail">
            <article className="context-card plot-session-overview-card">
              <div className="panel-heading">
                <div>
                  <div className="card-kicker">Session</div>
                  <h3>Current plot session</h3>
                </div>
              </div>
              <div className="wizard-summary-list">
                {summaryRows.map((row) => (
                  <div className="wizard-summary-row" key={row.label}>
                    <span>{row.label}</span>
                    <strong>{row.value}</strong>
                  </div>
                ))}
              </div>
            </article>

            <article className="context-card plot-import-recents-card">
              <div className="panel-heading">
                <div>
                  <div className="card-kicker">Recent</div>
                  <h3>Recent data files</h3>
                </div>
              </div>

              {recentDataFiles.length === 0 ? (
                <div className="placeholder-card">No recent data files yet.</div>
              ) : (
                <div className="launchpad-recent-list plot-import-recent-list">
                  {recentDataFiles.slice(0, 4).map((entry) => (
                    <button
                      className="launchpad-recent-row"
                      key={entry.id}
                      onClick={() => void reopenRecentData(entry.path)}
                      type="button"
                    >
                      <strong>{entry.title}</strong>
                      <span>{entry.detail}</span>
                    </button>
                  ))}
                </div>
              )}
            </article>
          </aside>
        </div>
      )}

      {routeStage === "sheet" && (
        <div className="plot-stage-grid">
          <section className="work-card plot-sheet-card">
            <div className="panel-heading">
              <div>
                <div className="card-kicker">Sheet</div>
                <h3>Select the workbook tab</h3>
              </div>
            </div>

              <div className="sheet-choice-list">
                {wizard.sheetNames.map((name) => {
                  const active =
                    wizard.sheet === name ||
                    (typeof wizard.sheet === "number" && wizard.sheetNames[wizard.sheet] === name);
                  return (
                  <button
                    className={`sheet-choice ${active ? "active" : ""}`}
                    key={name}
                    onClick={() => void rerunInspect(name)}
                    type="button"
                  >
                    <strong>{name}</strong>
                    <span>{active ? "Current sheet" : "Inspect this sheet"}</span>
                  </button>
                );
              })}
            </div>
          </section>

          <aside className="plot-stage-rail">
            <article className="context-card">
              <div className="panel-heading">
                <div>
                  <div className="card-kicker">Workbook</div>
                  <h3>{formatLeaf(wizard.inputPath)}</h3>
                </div>
              </div>
              <div className="wizard-summary-list">
                <div className="wizard-summary-row">
                  <span>Sheets</span>
                  <strong>{wizard.sheetNames.length}</strong>
                </div>
                <div className="wizard-summary-row">
                  <span>Current</span>
                  <strong>
                    {typeof wizard.sheet === "string"
                      ? wizard.sheet
                      : wizard.sheetNames[wizard.sheet] ?? wizard.sheetNames[0] ?? "-"}
                  </strong>
                </div>
              </div>
            </article>
          </aside>
        </div>
      )}

      {(routeStage === "type" || routeStage === "tune" || routeStage === "review" || routeStage === "export") && (
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
                  <span className={`status-pill ${statusChip.tone}`}>{statusChip.label}</span>
                </div>
              </div>

              <div className="wizard-summary-list">
                {summaryRows.map((row) => (
                  <div className="wizard-summary-row" key={row.label}>
                    <span>{row.label}</span>
                    <strong>{row.value}</strong>
                  </div>
                ))}
              </div>

              {wizard.sheetNames.length > 1 && (
                <div className="hero-actions">
                  <button className="ghost-button" onClick={() => goToStage("sheet")} type="button">
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
                        <h3>Why this chart type</h3>
                      </div>
                      {!recommendationApplied && (
                        <button
                          className="ghost-button"
                          onClick={applyRecommendedSelection}
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
                  onSelectTemplate={updateWizardTemplate}
                  onToggleShowAllTemplates={() =>
                    setShowAllTemplates((current) => !current)
                  }
                  selectedTemplate={wizard.template}
                  showAllTemplates={showAllTemplates}
                />

                <div className="hero-actions">
                  <button
                    className="primary-button"
                    disabled={!hasTemplate}
                    onClick={() => goToStage("tune")}
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
                  onUpdateOptions={updateWizardOptions}
                  options={wizard.options}
                  paletteOptions={paletteOptions}
                  sizeOptions={sizeOptions}
                  styleOptions={styleOptions}
                  template={wizard.template}
                  tensileCurveMode={tensileCurveMode}
                />

                <div className="hero-actions">
                  <button className="ghost-button" onClick={() => goToStage("type")} type="button">
                    Back to type
                  </button>
                  <button
                    className="primary-button"
                    disabled={!hasTemplate}
                    onClick={() => goToStage("review")}
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

                <div className="hero-actions">
                  <button className="ghost-button" onClick={() => goToStage("tune")} type="button">
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
                        onClick={() => void openOutputFolder()}
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
                          goToStage("import");
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
                  <button className="ghost-button" onClick={() => goToStage("review")} type="button">
                    Re-open review
                  </button>
                </div>
              </>
            )}
          </aside>
        </div>
      )}
    </div>
  );
}
