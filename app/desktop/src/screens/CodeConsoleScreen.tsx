import { useEffect, useMemo, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { PreviewPane } from "../components/PreviewPane";
import {
  CompactListRow,
  CompactToolbar,
  InspectorPanel,
  SectionHeader,
  SegmentedControl,
} from "../components/workbench/V2Primitives";
import { inspectFile, openPath, runCodeConsole } from "../lib/api";
import { copyTextToClipboard } from "../lib/clipboard";
import { useWizardStore } from "../lib/store";
import { openDialog } from "../lib/tauri-dialog";
import type {
  CodeConsoleRunResponse,
  InputInspection,
  PlotContract,
  RenderOptionsPayload,
  TemplateName,
  WorkbenchMeta,
  WorkbenchRoute,
} from "../lib/types";
import {
  compatibleTemplateChoices,
  formatLeaf,
  getErrorMessage,
  incompatibleTemplateChoices,
  paletteLabel,
  publicPaletteChoices,
  publicStyleChoices,
  sizeChoices,
  styleLabel,
  templateCompatibilityReason,
  templateLabel,
  toDialogPaths,
} from "../lib/workbench";
import {
  mergeRenderOptions,
  sanitizeRenderOptions,
  selectionFromInspection,
} from "../lib/wizard";
import { useCodeConsoleGenerate } from "./code-console/useCodeConsoleGenerate";

const DEFAULT_RUNNER_CODE = [
  "# Paste repo-native Python returned by the external AI here.",
  "# Available globals:",
  "# - OUTPUT_DIR",
  "# - INPUT_PATH",
  "# - CURRENT_SHEET",
  "# - CURRENT_TEMPLATE",
  "# - CURRENT_OPTIONS",
  "# - CURRENT_INSPECTION",
  "# - CURRENT_RECOMMENDATION",
  "# - CURRENT_DATA_CONTEXT",
  "# - output_path('filename.ext')",
].join("\n");

type BindingSource = "plot" | "local";

function stringifyContext(value: unknown) {
  return JSON.stringify(value, null, 2);
}

function sizeLabel(meta: WorkbenchMeta | null, sizeId: string | null | undefined) {
  if (!meta || !sizeId) {
    return sizeId ?? "-";
  }
  return meta.sizes.find((item) => item.id === sizeId)?.label ?? sizeId;
}

function runSummary(result: CodeConsoleRunResponse | null) {
  if (!result) {
    return "Paste code and run it in the repo-native sandbox.";
  }
  return `Last run: exit ${result.exit_code} · ${result.duration_ms} ms · ${result.generated_files.length} file(s)`;
}

function boundSheetLabel(sheet: string | number, sheetNames: string[]) {
  if (typeof sheet === "string") {
    return sheet;
  }
  return sheetNames[sheet] ?? sheetNames[0] ?? String(sheet);
}

export function CodeConsoleScreen({
  meta,
  contract,
  onNavigate = () => {},
}: {
  meta: WorkbenchMeta | null;
  contract: PlotContract | null;
  onNavigate?(route: WorkbenchRoute): void;
}) {
  const wizard = useWizardStore(
    useShallow((state) => ({
      inputPath: state.inputPath,
      inspection: state.inspection,
      options: state.options,
      projectPath: state.projectPath,
      sheet: state.sheet,
      sheetNames: state.sheetNames,
      sidecarReady: state.sidecarReady,
      stage: state.stage,
      template: state.template,
    })),
  );

  const wizardPlotReady =
    wizard.inputPath.trim() !== "" &&
    wizard.inspection != null &&
    wizard.template != null;

  const [bindingSource, setBindingSource] = useState<BindingSource | null>(
    wizardPlotReady ? "plot" : null,
  );
  const [inputPath, setInputPath] = useState(wizardPlotReady ? wizard.inputPath : "");
  const [sheet, setSheet] = useState<string | number>(wizardPlotReady ? wizard.sheet : 0);
  const [sheetNames, setSheetNames] = useState<string[]>(
    wizardPlotReady ? wizard.sheetNames : [],
  );
  const [inspection, setInspection] = useState<InputInspection | null>(
    wizardPlotReady ? wizard.inspection : null,
  );
  const [template, setTemplate] = useState<TemplateName | null>(
    wizardPlotReady ? wizard.template : null,
  );
  const [options, setOptions] = useState<RenderOptionsPayload>(
    wizardPlotReady ? wizard.options : {},
  );
  const [bindingBusy, setBindingBusy] = useState(false);
  const [bindingError, setBindingError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [noticeTone, setNoticeTone] = useState<"success" | "warning">("success");
  const [code, setCode] = useState(DEFAULT_RUNNER_CODE);
  const [runBusy, setRunBusy] = useState(false);
  const [runError, setRunError] = useState<string | null>(null);
  const [runResult, setRunResult] = useState<CodeConsoleRunResponse | null>(null);
  const [previewIndex, setPreviewIndex] = useState(0);
  const [outputTab, setOutputTab] = useState<"logs" | "artifacts" | "previews">("logs");
  const [showPrompt, setShowPrompt] = useState(false);
  const [showMoreTemplates, setShowMoreTemplates] = useState(false);
  const {
    busy: generateBusy,
    error: generateError,
    generate,
    reset: resetGenerate,
    result: generated,
  } = useCodeConsoleGenerate();

  useEffect(() => {
    if (!wizardPlotReady) {
      if (bindingSource === "plot") {
        setBindingSource(null);
        setInputPath("");
        setSheet(0);
        setSheetNames([]);
        setInspection(null);
        setTemplate(null);
        setOptions({});
      }
      return;
    }
    if (bindingSource !== "plot") {
      return;
    }
    setInputPath(wizard.inputPath);
    setSheet(wizard.sheet);
    setSheetNames(wizard.sheetNames);
    setInspection(wizard.inspection);
    setTemplate(wizard.template);
    setOptions(wizard.options);
  }, [
    bindingSource,
    wizard.inputPath,
    wizard.inspection,
    wizard.options,
    wizard.sheet,
    wizard.sheetNames,
    wizard.template,
    wizardPlotReady,
  ]);

  useEffect(() => {
    setPreviewIndex(0);
  }, [runResult?.generated_at]);

  const compatibleTemplates = useMemo(
    () => compatibleTemplateChoices(meta, inspection?.model),
    [inspection?.model, meta],
  );
  const incompatibleTemplates = useMemo(
    () => incompatibleTemplateChoices(meta, inspection?.model),
    [inspection?.model, meta],
  );
  const sizeOptions = useMemo(() => sizeChoices(meta, template), [meta, template]);
  const styleOptions = useMemo(
    () => publicStyleChoices(meta, template),
    [meta, template],
  );
  const paletteOptions = useMemo(
    () => publicPaletteChoices(meta, template),
    [meta, template],
  );
  const bindingReady =
    inputPath.trim() !== "" && inspection != null && template != null;
  const recommendedTemplate = inspection?.recommendation.template ?? null;
  const projectPath =
    bindingSource === "plot" && wizard.projectPath.trim() !== ""
      ? wizard.projectPath
      : null;

  const requestPayload = useMemo(() => {
    if (!bindingReady || !template) {
      return null;
    }
    return {
      intent: "custom_plot" as const,
      brief: "",
      base_template: template,
      options,
      size: options.size ?? null,
      style_preset: options.style_preset ?? null,
      palette_preset: options.palette_preset ?? null,
      target_path: null,
      input_path: inputPath,
      sheet,
      project_path: projectPath,
      include_data_context: true,
      include_inspection_summary: true,
      include_project_context: Boolean(projectPath),
    };
  }, [bindingReady, inputPath, options, projectPath, sheet, template]);

  useEffect(() => {
    resetGenerate();
    if (!showPrompt || !requestPayload || !wizard.sidecarReady) {
      return;
    }
    void generate(requestPayload);
  }, [generate, requestPayload, resetGenerate, showPrompt, wizard.sidecarReady]);

  const session = generated?.session ?? null;
  const promptText = (generated?.prompt_text ?? "").trim();
  const promptReady = promptText.length > 0;
  const promptError =
    generateError ??
    (!generateBusy && generated && !promptReady
      ? "The prompt resolved empty. Refresh the current data context and try again."
      : null);

  const resetGeneratedState = () => {
    resetGenerate();
    setRunResult(null);
    setRunError(null);
  };

  const applyInspection = (
    inspected: {
      input_path: string;
      sheet: string | number;
      sheet_names: string[];
      inspection: InputInspection;
    },
    source: BindingSource,
  ) => {
    const selection = selectionFromInspection(meta, inspected.inspection);
    setBindingSource(source);
    setInputPath(inspected.input_path);
    setSheet(inspected.sheet);
    setSheetNames(inspected.sheet_names);
    setInspection(inspected.inspection);
    setTemplate(selection.template);
    setOptions(selection.options);
    setShowMoreTemplates(false);
    resetGeneratedState();
  };

  const usePlotContext = () => {
    if (!wizardPlotReady) {
      return;
    }
    setBindingError(null);
    setBindingSource("plot");
    setInputPath(wizard.inputPath);
    setSheet(wizard.sheet);
    setSheetNames(wizard.sheetNames);
    setInspection(wizard.inspection);
    setTemplate(wizard.template);
    setOptions(wizard.options);
    resetGeneratedState();
  };

  const openDataFile = async () => {
    let path: string | undefined;
    setBindingError(null);
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
      setBindingError(getErrorMessage(error));
      return;
    }
    if (!path) {
      return;
    }

    setBindingBusy(true);
    try {
      const inspected = await inspectFile(path, 0);
      applyInspection(inspected, "local");
      setNoticeTone("success");
      setNotice(`Bound ${formatLeaf(inspected.input_path)} in Code Console.`);
    } catch (error) {
      setBindingError(getErrorMessage(error));
    } finally {
      setBindingBusy(false);
    }
  };

  const rerunInspect = async (sheetValue: string | number) => {
    if (!inputPath) {
      return;
    }
    setBindingError(null);
    setBindingBusy(true);
    try {
      const inspected = await inspectFile(inputPath, sheetValue);
      applyInspection(inspected, "local");
    } catch (error) {
      setBindingError(getErrorMessage(error));
    } finally {
      setBindingBusy(false);
    }
  };

  const ensurePromptGenerated = async () => {
    if (!requestPayload || !wizard.sidecarReady) {
      return null;
    }
    return generate(requestPayload);
  };

  const handleCopyPrompt = async () => {
    const response = await ensurePromptGenerated();
    const nextPrompt = (response?.prompt_text ?? generated?.prompt_text ?? "").trim();
    if (!nextPrompt) {
      setNoticeTone("warning");
      setNotice("Prompt generation failed. Refresh the current data context and try again.");
      return;
    }
    try {
      await copyTextToClipboard(nextPrompt);
      setNoticeTone("success");
      setNotice("Prompt copied.");
    } catch (error) {
      setNoticeTone("warning");
      setNotice(getErrorMessage(error));
    }
  };

  const togglePrompt = () => {
    setShowPrompt((current) => !current);
  };

  const updateTemplate = (value: TemplateName) => {
    if (!inspection) {
      return;
    }
    setTemplate(value);
    setOptions((current) =>
      sanitizeRenderOptions(meta, value, current, inspection.model),
    );
    resetGeneratedState();
  };

  const updateFigureContext = (patch: Partial<RenderOptionsPayload>) => {
    if (!template) {
      return;
    }
    setOptions((current) =>
      mergeRenderOptions(meta, template, current, patch, inspection?.model),
    );
    resetGeneratedState();
  };

  const handleRun = async () => {
    if (!template || !bindingReady) {
      return;
    }
    setRunBusy(true);
    setRunError(null);
    try {
      const response = await runCodeConsole({
        code,
        base_template: template,
        options,
        input_path: inputPath,
        sheet,
        project_path: projectPath,
        include_project_context: Boolean(projectPath),
      });
      setRunResult(response);
      setNoticeTone("success");
      setNotice("Python snippet finished.");
    } catch (error) {
      const detail = getErrorMessage(error);
      setRunError(detail);
      setNoticeTone("warning");
      setNotice(detail);
    } finally {
      setRunBusy(false);
    }
  };

  const handleInspectAction = async () => {
    if (!wizard.sidecarReady) {
      return;
    }
    if (!inputPath) {
      await openDataFile();
      return;
    }
    await rerunInspect(sheet);
  };

  const handleOpenPath = async (path: string) => {
    try {
      await openPath(path);
    } catch (error) {
      setNoticeTone("warning");
      setNotice(getErrorMessage(error));
    }
  };

  const currentSizeLabel = sizeLabel(
    meta,
    session?.size_id ?? options.size ?? inspection?.recommendation.size ?? null,
  );
  const currentStyleLabel = styleLabel(
    meta,
    session?.style_preset ??
      options.style_preset ??
      inspection?.recommendation.style_preset ??
      null,
  );
  const currentPaletteLabel = paletteLabel(
    meta,
    session?.palette_preset ??
      options.palette_preset ??
      inspection?.recommendation.palette_preset ??
      null,
  );
  const currentSheetLabel = boundSheetLabel(sheet, sheetNames);
  const bindingSourceLabel =
    bindingSource === "plot"
      ? "From Plot"
      : bindingSource === "local"
        ? "Loaded here"
        : "Not bound";
  const runnerReady = bindingReady && wizard.sidecarReady;

  return (
    <div className="code-console-v2-layout">
      {!wizard.sidecarReady && (
        <div className="warning-card">
          The sidecar is offline. Inspect, prompt generation, and the local runner resume once it reconnects.
        </div>
      )}

      {notice && (
        <div className={noticeTone === "warning" ? "warning-card" : "success-card"}>
          {notice}
        </div>
      )}

      <section className="work-card section-card code-console-v2-topbar">
        <CompactToolbar label="Code Console toolbar">
          <button
            className="ghost-button"
            disabled={bindingBusy || !wizard.sidecarReady}
            onClick={() => void openDataFile()}
            type="button"
          >
            {bindingBusy ? "Inspecting…" : "Open data"}
          </button>
          <button
            className="ghost-button"
            disabled={!wizardPlotReady}
            onClick={usePlotContext}
            type="button"
          >
            Use Plot data
          </button>
          <button
            className="ghost-button"
            disabled={!wizard.sidecarReady}
            onClick={() => void handleInspectAction()}
            type="button"
          >
            Inspect
          </button>
          <button
            className="primary-button"
            disabled={!bindingReady || !wizard.sidecarReady}
            onClick={() => void handleCopyPrompt()}
            type="button"
          >
            Copy prompt
          </button>
          <button
            className="ghost-button"
            disabled={!bindingReady || !wizard.sidecarReady}
            onClick={togglePrompt}
            type="button"
          >
            {showPrompt ? "Hide prompt" : "Show prompt"}
          </button>
          <button
            className="primary-button"
            disabled={!runnerReady || runBusy}
            onClick={() => void handleRun()}
            type="button"
          >
            {runBusy ? "Running…" : "Run"}
          </button>
          <button
            aria-label="Open output folder"
            className="ghost-button"
            disabled={!runResult}
            onClick={() => runResult && void handleOpenPath(runResult.output_dir)}
            type="button"
          >
            Reveal output folder
          </button>
          {wizardPlotReady && (
            <button
              className="ghost-button"
              onClick={() => onNavigate(`/plot/${wizard.stage}` as WorkbenchRoute)}
              type="button"
            >
              Back to Plot
            </button>
          )}
        </CompactToolbar>
      </section>

      {promptError && <div className="warning-card">{promptError}</div>}

      {showPrompt && (
        <section className="work-card section-card code-console-v2-prompt-drawer">
          <SectionHeader
            kicker="Prompt drawer"
            title="Generated AI prompt"
          />
          <pre aria-label="Generated AI prompt" className="code-console-preview">
            {generateBusy
              ? "Refreshing prompt…"
              : promptReady
                ? promptText
                : "Prompt will appear here after generation."}
          </pre>
        </section>
      )}

      <div className="code-console-v2-grid">
        <aside className="code-console-v2-left">
          <InspectorPanel
            extra={<span className={`status-pill ${bindingReady ? "good" : "warn"}`}>{bindingReady ? "Ready" : "Waiting"}</span>}
            kicker="Data context"
            title="Bound data and figure context"
          >
            {bindingError && <div className="warning-card">{bindingError}</div>}
            <div className="context-list">
              <div className="context-row">
                <span>Source</span>
                <strong>{bindingSourceLabel}</strong>
              </div>
              <div className="context-row">
                <span>File</span>
                <strong>{inputPath ? formatLeaf(inputPath) : "No file bound"}</strong>
              </div>
              <div className="context-row">
                <span>Sheet</span>
                <strong>{bindingReady ? currentSheetLabel : "-"}</strong>
              </div>
              <div className="context-row">
                <span>Inspect model</span>
                <strong>{inspection?.model_label ?? "Pending inspect"}</strong>
              </div>
              <div className="context-row">
                <span>Chart family</span>
                <strong>{template ? templateLabel(meta, template) : "Not selected"}</strong>
              </div>
              <div className="context-row">
                <span>Figure context</span>
                <strong>
                  {currentSizeLabel} / {currentStyleLabel} / {currentPaletteLabel}
                </strong>
              </div>
              <div className="context-row">
                <span>Contract</span>
                <strong>v{contract?.version ?? meta?.version ?? "?"}</strong>
              </div>
            </div>

            {sheetNames.length > 1 && (
              <label className="code-console-sheet-row">
                <span className="field-label">Sheet</span>
                <select
                  className="field"
                  disabled={bindingBusy}
                  onChange={(event) => void rerunInspect(event.target.value)}
                  value={currentSheetLabel}
                >
                  {sheetNames.map((item) => (
                    <option key={item} value={item}>
                      {item}
                    </option>
                  ))}
                </select>
              </label>
            )}
          </InspectorPanel>

          <InspectorPanel kicker="Chart family" title="Template and options">
            {!inspection ? (
              <div className="placeholder-card">Load data to see recommendations.</div>
            ) : (
              <div className="wizard-section-stack">
                <button
                  className={`wizard-recommendation-card ${template === recommendedTemplate ? "active" : ""}`}
                  onClick={() => recommendedTemplate && updateTemplate(recommendedTemplate)}
                  type="button"
                >
                  <div className="wizard-recommendation-copy">
                    <span className="signal-tag">Recommended</span>
                    <strong>{templateLabel(meta, recommendedTemplate)}</strong>
                    <span>{inspection.recommendation.reason}</span>
                  </div>
                  <span className="wizard-recommendation-action">Use this type</span>
                </button>

                <div className="wizard-template-grid wizard-template-gallery">
                  {compatibleTemplates.map((item) => (
                    <button
                      className={`wizard-template-chip ${template === item.id ? "active" : ""}`}
                      key={item.id}
                      onClick={() => updateTemplate(item.id)}
                      type="button"
                    >
                      <strong>{item.label}</strong>
                      <span>{item.id === recommendedTemplate ? "Recommended" : "Compatible"}</span>
                      <div className="wizard-template-chip-line" />
                    </button>
                  ))}
                </div>

                {incompatibleTemplates.length > 0 && (
                  <>
                    <button
                      className="ghost-button"
                      onClick={() => setShowMoreTemplates((current) => !current)}
                      type="button"
                    >
                      {showMoreTemplates ? "Hide more types" : "More types"}
                    </button>
                    {showMoreTemplates && (
                      <div className="wizard-section-stack">
                        <div className="hint-text">{templateCompatibilityReason(inspection.model)}</div>
                        <div className="wizard-template-grid">
                          {incompatibleTemplates.map((item) => (
                            <button className="wizard-template-chip disabled" disabled key={item.id} type="button">
                              <strong>{item.label}</strong>
                              <span>Not compatible</span>
                            </button>
                          ))}
                        </div>
                      </div>
                    )}
                  </>
                )}

                {(sizeOptions.length > 1 || styleOptions.length > 1 || paletteOptions.length > 1) && (
                  <details className="wizard-details">
                    <summary>Figure context</summary>
                    <div className="field-grid compact-grid wizard-tight-grid">
                      {sizeOptions.length > 1 && (
                        <label className="wizard-option-card">
                          <span className="field-label">Size</span>
                          <select
                            className="field"
                            onChange={(event) => updateFigureContext({ size: event.target.value })}
                            value={options.size ?? sizeOptions[0]?.id ?? ""}
                          >
                            {sizeOptions.map((item) => (
                              <option key={item.id} value={item.id}>
                                {item.label}
                              </option>
                            ))}
                          </select>
                        </label>
                      )}

                      {styleOptions.length > 1 && (
                        <label className="wizard-option-card">
                          <span className="field-label">Style</span>
                          <select
                            className="field"
                            onChange={(event) => updateFigureContext({ style_preset: event.target.value })}
                            value={options.style_preset ?? meta?.default_style ?? ""}
                          >
                            {styleOptions.map((item) => (
                              <option key={item.id} value={item.id}>
                                {item.label}
                              </option>
                            ))}
                          </select>
                        </label>
                      )}

                      {paletteOptions.length > 1 && (
                        <label className="wizard-option-card">
                          <span className="field-label">Palette</span>
                          <select
                            className="field"
                            onChange={(event) => updateFigureContext({ palette_preset: event.target.value })}
                            value={options.palette_preset ?? meta?.default_palette ?? ""}
                          >
                            {paletteOptions.map((item) => (
                              <option key={item.id} value={item.id}>
                                {item.label}
                              </option>
                            ))}
                          </select>
                        </label>
                      )}
                    </div>
                  </details>
                )}
              </div>
            )}
          </InspectorPanel>

          <details className="work-card section-card wizard-details">
            <summary>Inspect details</summary>
            <div className="wizard-section-stack">
              {(generated?.truth_sources ?? []).length > 0 && (
                <div className="code-console-list-block">
                  <h4>Truth sources</h4>
                  <ul className="bullet-list code-console-source-list">
                    {(generated?.truth_sources ?? []).map((source) => (
                      <li key={source.id}>
                        <strong>{source.label}</strong>
                        <br />
                        <code>{source.display_path ?? source.label}</code>
                        <br />
                        <span className="hint-text">{source.reason}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
              {(generated?.data_context.available ?? false) && (
                <pre className="code-console-scaffold">
                  {stringifyContext({
                    normalized_columns: generated?.data_context.normalized_columns ?? [],
                    interpreted_summary: generated?.data_context.interpreted_summary ?? {},
                    recommendation: generated?.data_context.recommendation ?? {},
                  })}
                </pre>
              )}
            </div>
          </details>
        </aside>

        <section className="code-console-v2-main">
          <section className="work-card section-card code-console-v2-editor-card">
            <SectionHeader
              actions={<span className="code-console-v2-run-meta">20s timeout · OUTPUT_DIR only</span>}
              kicker="Editor"
              title="Repo-native Python"
            />
            <label>
              <span className="field-label">Python code</span>
              <textarea
                aria-label="Code console runner input"
                className="field code-console-editor code-console-v2-editor"
                onChange={(event) => setCode(event.target.value)}
                rows={16}
                value={code}
              />
            </label>
            <CompactToolbar label="Editor actions">
              <button className="ghost-button" onClick={() => setCode(DEFAULT_RUNNER_CODE)} type="button">
                Clear code
              </button>
              <button
                className="ghost-button"
                onClick={() => {
                  setRunError(null);
                  setRunResult(null);
                }}
                type="button"
              >
                Clear output
              </button>
            </CompactToolbar>
          </section>

          <section className="work-card section-card code-console-v2-output-card">
            <SectionHeader
              actions={<span className="code-console-v2-run-meta">{runSummary(runResult)}</span>}
              kicker="Output"
              title="Logs and artifacts"
            />

            {runError && <div className="warning-card">{runError}</div>}
            {runResult?.timed_out && (
              <div className="warning-card">
                The last run hit the timeout. Reduce the workload or save fewer outputs per run.
              </div>
            )}

            <SegmentedControl<"logs" | "artifacts" | "previews">
              label="Code console output tabs"
              onChange={(value) => setOutputTab(value)}
              options={[
                { id: "logs", label: "Logs" },
                { id: "artifacts", label: "Artifacts" },
                { id: "previews", label: "Previews" },
              ]}
              value={outputTab}
            />

            {outputTab === "logs" && (
              <div className="wizard-section-stack">
                <div className="code-console-output-grid">
                  <div className="code-console-output-card">
                    <h4>stdout</h4>
                    <pre className="code-console-terminal-pre code-console-v2-terminal">
                      {runResult?.stdout || "(empty)"}
                    </pre>
                  </div>
                  <div className="code-console-output-card">
                    <h4>stderr</h4>
                    <pre className="code-console-terminal-pre code-console-v2-terminal">
                      {runResult?.stderr || "(empty)"}
                    </pre>
                  </div>
                </div>
                <div className="code-console-list-block">
                  <h4>Recent artifacts</h4>
                  {runResult?.generated_files.length ? (
                    <div className="launchpad-v2-list">
                      {runResult.generated_files.map((file) => (
                        <CompactListRow
                          key={file.path}
                          onSelect={() => void handleOpenPath(file.path)}
                          subtitle={`${file.kind} · ${formatLeaf(file.path)}`}
                          title={file.filename}
                        />
                      ))}
                    </div>
                  ) : (
                    <div className="placeholder-card">Run to generate files.</div>
                  )}
                </div>
              </div>
            )}

            {outputTab === "artifacts" && (
              <div className="code-console-list-block">
                <h4>Generated files</h4>
                {runResult?.generated_files.length ? (
                  <div className="launchpad-v2-list">
                    {runResult.generated_files.map((file) => (
                      <CompactListRow
                        key={file.path}
                        onSelect={() => void handleOpenPath(file.path)}
                        subtitle={`${file.kind} · ${formatLeaf(file.path)}`}
                        title={file.filename}
                      />
                    ))}
                  </div>
                ) : (
                  <div className="placeholder-card">Generated files appear here after a successful run.</div>
                )}
              </div>
            )}

            {outputTab === "previews" && (
              <>
                {runResult?.previews.length ? (
                  <PreviewPane
                    busy={false}
                    error={null}
                    onChangeIndex={setPreviewIndex}
                    previewIndex={previewIndex}
                    previews={runResult.previews}
                  />
                ) : (
                  <div className="placeholder-card">
                    Preview images appear here after the runner writes PNG or PDF outputs.
                  </div>
                )}
              </>
            )}
          </section>
        </section>
      </div>
    </div>
  );
}
