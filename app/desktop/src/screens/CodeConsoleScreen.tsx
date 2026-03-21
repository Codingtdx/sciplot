import { useEffect, useMemo, useState } from "react";
import { useShallow } from "zustand/react/shallow";

import { PreviewPane } from "../components/PreviewPane";
import { openPath, runCodeConsole } from "../lib/api";
import { copyTextToClipboard } from "../lib/clipboard";
import { useWizardStore } from "../lib/store";
import type {
  CodeConsoleRunResponse,
  PlotContract,
  WorkbenchMeta,
  WorkbenchRoute,
} from "../lib/types";
import {
  formatLeaf,
  getErrorMessage,
  paletteLabel,
  plotRoute,
  styleLabel,
  templateLabel,
} from "../lib/workbench";
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
    return "Paste repo-native Python returned by the external AI, then run it inside the repository sandbox.";
  }
  return `Last run: exit ${result.exit_code} · ${result.duration_ms} ms · ${result.generated_files.length} file(s)`;
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
      sidecarReady: state.sidecarReady,
      stage: state.stage,
      template: state.template,
    })),
  );
  const generateState = useCodeConsoleGenerate();
  const [notice, setNotice] = useState<string | null>(null);
  const [noticeTone, setNoticeTone] = useState<"success" | "warning">("success");
  const [code, setCode] = useState(DEFAULT_RUNNER_CODE);
  const [runBusy, setRunBusy] = useState(false);
  const [runError, setRunError] = useState<string | null>(null);
  const [runResult, setRunResult] = useState<CodeConsoleRunResponse | null>(null);
  const [previewIndex, setPreviewIndex] = useState(0);

  const hasBoundData = wizard.inputPath.trim() !== "";
  const hasPlotContext = hasBoundData && wizard.inspection != null && wizard.template != null;
  const hasProjectContext = wizard.projectPath.trim() !== "";
  const returnRoute = hasBoundData ? plotRoute(wizard.stage) : "/plot/import";

  const requestPayload = useMemo(() => {
    if (!wizard.template) {
      return null;
    }
    return {
      intent: "custom_plot" as const,
      brief: "",
      base_template: wizard.template,
      options: wizard.options,
      size: wizard.options.size ?? null,
      style_preset: wizard.options.style_preset ?? null,
      palette_preset: wizard.options.palette_preset ?? null,
      target_path: null,
      input_path: hasBoundData ? wizard.inputPath : null,
      sheet: hasBoundData ? wizard.sheet : null,
      project_path: hasProjectContext ? wizard.projectPath : null,
      include_data_context: true,
      include_inspection_summary: true,
      include_project_context: hasProjectContext,
    };
  }, [
    hasBoundData,
    hasProjectContext,
    wizard.inputPath,
    wizard.options,
    wizard.projectPath,
    wizard.sheet,
    wizard.template,
  ]);

  useEffect(() => {
    if (!wizard.sidecarReady || !hasPlotContext || !requestPayload) {
      generateState.reset();
      return;
    }
    void generateState.generate(requestPayload);
  }, [hasPlotContext, requestPayload, wizard.sidecarReady]);

  useEffect(() => {
    setPreviewIndex(0);
  }, [runResult?.generated_at]);

  const generated = generateState.result;
  const session = generated?.session ?? null;
  const promptText =
    generated?.prompt_text ??
    "Finish the current Plot setup first so Code Console can generate the fixed project prompt.";

  const handleCopyPrompt = async () => {
    try {
      await copyTextToClipboard(promptText);
      setNoticeTone("success");
      setNotice("Project prompt copied.");
    } catch (error) {
      setNoticeTone("warning");
      setNotice(getErrorMessage(error));
    }
  };

  const handleRun = async () => {
    if (!wizard.template || !hasBoundData) {
      return;
    }
    setRunBusy(true);
    setRunError(null);
    try {
      const response = await runCodeConsole({
        code,
        base_template: wizard.template,
        options: wizard.options,
        input_path: wizard.inputPath,
        sheet: wizard.sheet,
        project_path: hasProjectContext ? wizard.projectPath : null,
        include_project_context: hasProjectContext,
      });
      setRunResult(response);
      setNoticeTone("success");
      setNotice("Python snippet finished in the repo-native runner.");
    } catch (error) {
      setRunError(getErrorMessage(error));
      setNoticeTone("warning");
      setNotice(getErrorMessage(error));
    } finally {
      setRunBusy(false);
    }
  };

  const handleOpenPath = async (path: string) => {
    try {
      await openPath(path);
    } catch (error) {
      setNoticeTone("warning");
      setNotice(getErrorMessage(error));
    }
  };

  if (!hasPlotContext) {
    return (
      <div className="plot-workspace">
        <section className="work-card section-card code-console-empty-card">
          <div className="panel-heading">
            <div>
              <div className="card-kicker">Code Console</div>
              <h2>Start from Plot first</h2>
            </div>
          </div>

          <div className="placeholder-card">
            Open a data file in Plot, confirm the current chart type, and come back after the
            current figure has a real session context.
          </div>

          <div className="step-actions">
            <button
              className="primary-button"
              onClick={() => onNavigate(returnRoute)}
              type="button"
            >
              Back to Plot
            </button>
          </div>
        </section>
      </div>
    );
  }

  return (
    <div className="plot-workspace code-console-workspace">
      <section className="work-card section-card code-console-context-card">
        <div className="panel-heading">
          <div>
            <div className="card-kicker">Current plot context</div>
            <h2>Use the active Plot session as the source of truth</h2>
          </div>
          <span className={`status-pill ${wizard.sidecarReady ? "good" : "warn"}`}>
            {wizard.sidecarReady ? "Sidecar Online" : "Sidecar Offline"}
          </span>
        </div>

        <div className="code-console-context-grid">
          <div className="code-console-context-chip">
            <span>Data file</span>
            <strong>{formatLeaf(wizard.inputPath)}</strong>
          </div>
          <div className="code-console-context-chip">
            <span>Sheet</span>
            <strong>{String(session?.sheet ?? wizard.sheet)}</strong>
          </div>
          <div className="code-console-context-chip">
            <span>Template</span>
            <strong>{templateLabel(meta, wizard.template)}</strong>
          </div>
          <div className="code-console-context-chip">
            <span>Size</span>
            <strong>{sizeLabel(meta, session?.size_id ?? wizard.options.size ?? null)}</strong>
          </div>
          <div className="code-console-context-chip">
            <span>Style / palette</span>
            <strong>
              {styleLabel(meta, session?.style_preset ?? wizard.options.style_preset ?? null)} /{" "}
              {paletteLabel(meta, session?.palette_preset ?? wizard.options.palette_preset ?? null)}
            </strong>
          </div>
          <div className="code-console-context-chip">
            <span>Axis scales</span>
            <strong>
              {session?.xscale ?? wizard.options.xscale ?? "linear"} /{" "}
              {session?.yscale ?? wizard.options.yscale ?? "linear"}
            </strong>
          </div>
          <div className="code-console-context-chip">
            <span>Inspect model</span>
            <strong>{generated?.data_context.model_label ?? wizard.inspection?.model_label ?? "-"}</strong>
          </div>
          <div className="code-console-context-chip">
            <span>Recommended template</span>
            <strong>
              {templateLabel(meta, generated?.data_context.recommendation.template ?? wizard.inspection?.recommendation.template)}
            </strong>
          </div>
        </div>
      </section>

      <section className="work-card section-card code-console-prompt-card">
        <div className="panel-heading">
          <div>
            <div className="card-kicker">Project prompt for external AI</div>
            <h2>Copy this fixed prompt, then add your real request outside the app</h2>
          </div>
          <button
            className="ghost-button"
            disabled={generateState.busy || !generated}
            onClick={() => void handleCopyPrompt()}
            type="button"
          >
            Copy prompt
          </button>
        </div>

        <p className="hint-text">
          Main flow: copy the fixed project prompt, ask the external AI for a repo-native change,
          paste the returned Python here, then run it in the repository sandbox.
        </p>

        {!wizard.sidecarReady && (
          <div className="warning-card">
            The sidecar is offline. Prompt generation and the Python runner stay unavailable until
            it reconnects.
          </div>
        )}

        {generateState.error && <div className="warning-card">{generateState.error}</div>}
        {notice && (
          <div className={noticeTone === "warning" ? "warning-card" : "success-card"}>{notice}</div>
        )}

        <pre aria-label="Generated AI prompt" className="code-console-preview">
          {generateState.busy ? "Refreshing the fixed project prompt from the current Plot context…" : promptText}
        </pre>
      </section>

      <details className="context-card wizard-details code-console-details">
        <summary>Context details</summary>

        <div className="wizard-section-stack">
          <div className="context-list">
            <div className="context-row">
              <span>Reverse x</span>
              <strong>{String(session?.reverse_x ?? wizard.options.reverse_x ?? false)}</strong>
            </div>
            <div className="context-row">
              <span>Baseline</span>
              <strong>{session?.baseline ?? wizard.options.baseline ?? "none"}</strong>
            </div>
            <div className="context-row">
              <span>Show colorbar</span>
              <strong>{String(session?.show_colorbar ?? wizard.options.show_colorbar ?? false)}</strong>
            </div>
            <div className="context-row">
              <span>Contract</span>
              <strong>v{contract?.version ?? meta?.version ?? "?"}</strong>
            </div>
          </div>

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

          <div className="code-console-list-block">
            <h4>Inspect summary</h4>
            <div className="wizard-section-stack">
              <div className="focus-panel">
                <span>Reason</span>
                <strong>{generated?.data_context.recommendation.reason ?? wizard.inspection?.recommendation.reason ?? "-"}</strong>
              </div>
              {(generated?.data_context.inspection.signals ?? wizard.inspection?.signals ?? []).length > 0 && (
                <div className="focus-panel">
                  <span>Signals</span>
                  <strong>
                    {(generated?.data_context.inspection.signals ?? wizard.inspection?.signals ?? []).join(" | ")}
                  </strong>
                </div>
              )}
              {(generated?.data_context.inspection.warnings ?? wizard.inspection?.warnings ?? []).length > 0 && (
                <div className="focus-panel">
                  <span>Warnings</span>
                  <strong>
                    {(generated?.data_context.inspection.warnings ?? wizard.inspection?.warnings ?? []).join(" | ")}
                  </strong>
                </div>
              )}
            </div>
          </div>

          <div className="code-console-list-block">
            <h4>Column and role summary</h4>
            <pre className="code-console-scaffold">
              {stringifyContext({
                normalized_columns: generated?.data_context.normalized_columns ?? [],
                interpreted_summary: generated?.data_context.interpreted_summary ?? {},
                recommendation: generated?.data_context.recommendation ?? {},
              })}
            </pre>
          </div>
        </div>
      </details>

      <section className="work-card section-card code-console-terminal-card">
        <div className="panel-heading">
          <div>
            <div className="card-kicker">Code terminal</div>
            <h2>Paste code and run it in the repo-native Python runner</h2>
          </div>
          <span className="signal-tag">20s timeout · OUTPUT_DIR only</span>
        </div>

        <p className="hint-text">
          The runner executes Python from the repository root, captures stdout and stderr, and only
          scans the controlled output directory for generated files and previews.
        </p>

        {runError && <div className="warning-card">{runError}</div>}
        {runResult?.timed_out && (
          <div className="warning-card">
            The last run hit the timeout. Reduce the workload or save fewer outputs per run.
          </div>
        )}

        <label>
          <span className="field-label">Python code</span>
          <textarea
            aria-label="Code console runner input"
            className="field code-console-editor"
            onChange={(event) => setCode(event.target.value)}
            rows={14}
            value={code}
          />
        </label>

        <div className="step-actions">
          <button
            className="primary-button"
            disabled={runBusy || !wizard.sidecarReady}
            onClick={() => void handleRun()}
            type="button"
          >
            {runBusy ? "Running…" : "Run"}
          </button>
          <button
            className="ghost-button"
            onClick={() => setCode(DEFAULT_RUNNER_CODE)}
            type="button"
          >
            Clear code
          </button>
          <button className="ghost-button" onClick={() => setRunResult(null)} type="button">
            Clear output
          </button>
          <button
            className="ghost-button"
            disabled={!runResult}
            onClick={() => runResult && void handleOpenPath(runResult.output_dir)}
            type="button"
          >
            Open output folder
          </button>
        </div>

        <div className="focus-panel">
          <span>Runner status</span>
          <strong>{runSummary(runResult)}</strong>
        </div>

        <div className="code-console-output-grid">
          <div className="code-console-output-card">
            <h4>stdout</h4>
            <pre className="code-console-terminal-pre">{runResult?.stdout || "(empty)"}</pre>
          </div>
          <div className="code-console-output-card">
            <h4>stderr</h4>
            <pre className="code-console-terminal-pre">{runResult?.stderr || "(empty)"}</pre>
          </div>
        </div>

        <div className="code-console-list-block">
          <h4>Generated files</h4>
          {runResult?.generated_files.length ? (
            <div className="launchpad-recent-list">
              {runResult.generated_files.map((file) => (
                <button
                  className="launchpad-recent-row"
                  key={file.path}
                  onClick={() => void handleOpenPath(file.path)}
                  type="button"
                >
                  <strong>{file.filename}</strong>
                  <span>{file.kind} · {formatLeaf(file.path)}</span>
                </button>
              ))}
            </div>
          ) : (
            <div className="placeholder-card">
              Generated files will appear here after the repo-native runner writes into OUTPUT_DIR.
            </div>
          )}
        </div>

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
            Preview images appear after the runner writes PNG or PDF outputs into OUTPUT_DIR.
          </div>
        )}
      </section>
    </div>
  );
}
