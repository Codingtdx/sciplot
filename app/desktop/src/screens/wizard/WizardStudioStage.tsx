import type { ReactNode } from "react";

import { PreviewPane } from "../../components/PreviewPane";
import { CompactToolbar } from "../../components/workbench/V2Primitives";
import type {
  ExportResponse,
  InputInspection,
  PlotStage,
  PreflightResult,
  PreviewItem,
  RenderOptionsPayload,
  SubmissionReport,
  TemplateName,
  WorkbenchMeta,
  WorkbenchPalette,
  WorkbenchStyle,
  WorkbenchTemplate,
} from "../../lib/types";
import { formatLeaf, templateLabel, visualThemeChoices } from "../../lib/workbench";
import { getWizardStatusForPlot } from "./helpers";

type Props = {
  routeStage: PlotStage;
  inputPath: string | null;
  sheetNamesLength: number;
  template: TemplateName | null;
  hasTemplate: boolean;
  meta: WorkbenchMeta | null;
  inspection: InputInspection | null;
  currentTemplate: WorkbenchTemplate | null;
  options: RenderOptionsPayload;
  sizeOptions: Array<{ id: string; label: string }>;
  styleOptions: WorkbenchStyle[];
  paletteOptions: WorkbenchPalette[];
  tensileCurveMode: boolean;
  previewBusy: boolean;
  previewError: string | null;
  previewIndex: number;
  previews: PreviewItem[];
  preflightBusy: boolean;
  preflightRequestError: string | null;
  preflight: PreflightResult | null;
  submissionReport: SubmissionReport | null;
  exportResult: ExportResponse | null;
  outputItems: string[];
  outputsLength: number;
  blockingErrors: string[];
  canExport: boolean;
  hasExportedOutputs: boolean;
  onChangePreviewIndex(value: number): void;
  onChangeSheet(): void;
  onUpdateOptions(value: Partial<RenderOptionsPayload>): void;
  onBackToType(): void;
  onBackToTune(): void;
  onBackToReview(): void;
  onContinueToReview(): void;
  onExport(): void;
  onOpenOutputFolder(): void;
  onOpenComposer(): void;
  onStartAnotherPlot(): void;
};

const STAGE_COPY: Record<
  "tune" | "review" | "export",
  {
    kicker: string;
    title: string;
    description: string;
    previewKicker: string;
    previewTitle: string;
    previewDescription: string;
    footerCopy: string;
  }
> = {
  tune: {
    kicker: "Tune",
    title: "Calm figure refinement",
    description: "Keep the preview dominant while you adjust the small decisions that shape the figure.",
    previewKicker: "Live preview",
    previewTitle: "Figure preview",
    previewDescription: "Preview stays in view while you tune frame, presentation, and axes.",
    footerCopy: "Adjust the essentials before moving on to review.",
  },
  review: {
    kicker: "Review",
    title: "Readiness check",
    description: "Confirm the selected template, contract, and warnings before delivery.",
    previewKicker: "Final preview",
    previewTitle: "Ready-to-export figure",
    previewDescription: "Hold the final figure in view while you confirm readiness and blockers.",
    footerCopy: "Check blockers and readiness before you export.",
  },
  export: {
    kicker: "Export",
    title: "Delivery and outputs",
    description: "Confirm the bundle destination and files before opening the output folder.",
    previewKicker: "Delivery preview",
    previewTitle: "Bundle view",
    previewDescription: "The figure stays visible beside the delivery details for a calm handoff.",
    footerCopy: "Review the output handoff or return to readiness.",
  },
};

function selectedLabel(options: Array<{ id: string; label: string }>, value: string | null | undefined) {
  return options.find((choice) => choice.id === value)?.label ?? value ?? "Pending";
}

function fieldCard({
  label,
  value,
  note,
  primary = false,
}: {
  label: string;
  value: ReactNode;
  note?: ReactNode;
  primary?: boolean;
}) {
  return (
    <article className={`plot-flow-summary-card ${primary ? "primary" : ""}`}>
      <span>{label}</span>
      <strong>{value}</strong>
      {note ? <p>{note}</p> : null}
    </article>
  );
}

function moduleCard({
  kicker,
  title,
  description,
  children,
  tone = "default",
}: {
  kicker: string;
  title: string;
  description: string;
  children: ReactNode;
  tone?: "default" | "soft";
}) {
  return (
    <section className={`plot-flow-module-card ${tone === "soft" ? "soft" : ""}`}>
      <div className="plot-flow-module-head">
        <div>
          <span>{kicker}</span>
          <strong>{title}</strong>
          <p>{description}</p>
        </div>
      </div>
      <div className="plot-flow-module-body">{children}</div>
    </section>
  );
}

export function WizardStudioStage({
  routeStage,
  inputPath,
  sheetNamesLength,
  template,
  hasTemplate,
  meta,
  inspection,
  currentTemplate,
  options,
  sizeOptions,
  styleOptions,
  paletteOptions,
  tensileCurveMode,
  previewBusy,
  previewError,
  previewIndex,
  previews,
  preflightBusy,
  preflightRequestError,
  preflight,
  submissionReport,
  exportResult,
  outputItems,
  outputsLength,
  blockingErrors,
  canExport,
  hasExportedOutputs,
  onChangePreviewIndex,
  onChangeSheet,
  onUpdateOptions,
  onBackToType,
  onBackToTune,
  onBackToReview,
  onContinueToReview,
  onExport,
  onOpenOutputFolder,
  onOpenComposer,
  onStartAnotherPlot,
}: Props) {
  const stageKey: "tune" | "review" | "export" =
    routeStage === "export" ? "export" : routeStage === "review" ? "review" : "tune";
  const stage = STAGE_COPY[stageKey];
  const sourceLabel = formatLeaf(inputPath ?? "No source loaded");
  const templateLabelValue = hasTemplate ? templateLabel(meta, template) : "Template pending";
  const sheetLabel = sheetNamesLength > 1 ? `${sheetNamesLength} sheets` : "Single sheet";
  const statusChip = getWizardStatusForPlot({
    routeStage,
    busy: false,
    previewBusy,
    preflightBusy,
    hasBlockingErrors: blockingErrors.length > 0 || Boolean(preflightRequestError),
    hasInspection: inspection != null,
    hasInput: Boolean(inputPath),
    outputsCount: outputsLength,
  });

  const selectedSizeLabel = selectedLabel(sizeOptions, options.size ?? sizeOptions[0]?.id);
  const selectedStyleLabel = selectedLabel(
    styleOptions.map((choice) => ({ id: choice.id, label: choice.label })),
    options.style_preset ?? meta?.default_style,
  );
  const selectedPaletteLabel = selectedLabel(
    paletteOptions.map((choice) => ({ id: choice.id, label: choice.label })),
    options.palette_preset ?? meta?.default_palette,
  );
  const visualThemes = visualThemeChoices(meta);
  const selectedVisualThemeLabel =
    visualThemes.find((choice) => choice.id === options.visual_theme_id)?.label ?? null;
  const previewStatCards =
    stageKey === "tune"
      ? [
          {
            label: "Template",
            value: templateLabelValue,
            note: inspection?.recommendation.reason ?? "Data-aware guidance will appear after inspect.",
            primary: true,
          },
          {
            label: "Frame",
            value: selectedSizeLabel,
            note:
              options.xscale || options.yscale
                ? `${options.xscale ?? "linear"} x-axis · ${options.yscale ?? "linear"} y-axis`
                : "Frame settings stay calm and compact.",
          },
          {
            label: "Presentation",
            value: selectedStyleLabel,
            note: selectedVisualThemeLabel
              ? `${selectedPaletteLabel} · ${selectedVisualThemeLabel}`
              : selectedPaletteLabel,
          },
        ]
      : stageKey === "review"
        ? [
            {
              label: "Readiness",
              value:
                blockingErrors.length > 0 || preflightRequestError
                  ? "Blocked"
                  : preflight
                    ? "Ready"
                    : "Pending",
              note: submissionReport?.summary ?? "Final checks stay visible and structured.",
              primary: true,
            },
            {
              label: "Warnings",
              value: preflight?.warnings.length ?? 0,
              note: preflightBusy
                ? "Reviewing figure checks"
                : "Warnings stay grouped as product guidance.",
            },
            {
              label: "Blockers",
              value: blockingErrors.length,
              note: hasExportedOutputs ? "Export artifacts are already present." : "Nothing should be hidden here.",
            },
          ]
        : [
            {
              label: "Outputs",
              value: outputItems.length,
              note: hasExportedOutputs ? "Bundle files are already written." : "Expected files will appear after export.",
              primary: true,
            },
            {
              label: "Destination",
              value: exportResult?.output_dir ? formatLeaf(exportResult.output_dir) : "Pending export",
              note: exportResult?.preview_outputs?.length
                ? `${exportResult.preview_outputs.length} preview PNG file(s)`
                : "The handoff folder stays explicit.",
            },
            {
              label: "Manifest",
              value: exportResult?.manifest_path ? formatLeaf(exportResult.manifest_path) : "Pending",
              note: exportResult?.artifact_paths?.length
                ? `${exportResult.artifact_paths.length} artifact file(s)`
                : "Bundle metadata remains organized.",
            },
          ];

  const previewContent: ReactNode =
    hasTemplate ? (
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
          <div className="placeholder-card">Select a compatible chart type to start previewing.</div>
        </div>
      </section>
    );

  const tunePane = (
    <>
      <div className="plot-flow-summary-grid">
        {fieldCard({
          label: "Template",
          value: templateLabelValue,
          note: inspection?.recommendation.reason ?? "Run inspect to unlock data-aware guidance.",
          primary: true,
        })}
        {fieldCard({
          label: "Frame",
          value: selectedSizeLabel,
          note:
            tensileCurveMode
              ? "Tensile curves keep linear x/y scales."
              : `${options.xscale ?? "linear"} x ${options.yscale ?? "linear"} · ${options.reverse_x ? "reversed x" : "standard x"}`,
        })}
        {fieldCard({
          label: "Presentation",
          value: selectedStyleLabel,
          note: selectedVisualThemeLabel
            ? `${selectedPaletteLabel} · ${selectedVisualThemeLabel}`
            : selectedPaletteLabel,
        })}
        {fieldCard({
          label: "Source",
          value: inputPath ? formatLeaf(inputPath) : "No source loaded",
          note: inspection?.model_label ?? "Waiting for inspect",
        })}
      </div>

      {moduleCard({
        kicker: "Figure frame",
        title: "Shape, scale, and axis direction",
        description: "Lock the figure frame before touching presentation details.",
        children: (
          <div className="plot-flow-field-grid">
            <label className="plot-flow-field-card">
              <span className="field-label">Size</span>
              <select
                className="field"
                value={options.size ?? sizeOptions[0]?.id ?? ""}
                onChange={(event) => onUpdateOptions({ size: event.target.value })}
              >
                {sizeOptions.map((choice) => (
                  <option key={choice.id} value={choice.id}>
                    {choice.label}
                  </option>
                ))}
              </select>
            </label>

            {currentTemplate?.editable_options.includes("xscale") && (
              <label className="plot-flow-field-card">
                <span className="field-label">X scale</span>
                <select
                  className="field"
                  disabled={tensileCurveMode}
                  value={options.xscale ?? "linear"}
                  onChange={(event) =>
                    onUpdateOptions({
                      xscale: event.target.value === "log" ? "log" : "linear",
                    })
                  }
                >
                  <option value="linear">Linear</option>
                  {!tensileCurveMode && <option value="log">Log</option>}
                </select>
              </label>
            )}

            {currentTemplate?.editable_options.includes("yscale") && (
              <label className="plot-flow-field-card">
                <span className="field-label">Y scale</span>
                <select
                  className="field"
                  disabled={tensileCurveMode}
                  value={options.yscale ?? "linear"}
                  onChange={(event) =>
                    onUpdateOptions({
                      yscale: event.target.value === "log" ? "log" : "linear",
                    })
                  }
                >
                  <option value="linear">Linear</option>
                  {!tensileCurveMode && <option value="log">Log</option>}
                </select>
              </label>
            )}

            {currentTemplate?.editable_options.includes("reverse_x") && (
              <label className="plot-flow-field-card toggle-field">
                <input
                  checked={Boolean(options.reverse_x)}
                  onChange={(event) => onUpdateOptions({ reverse_x: event.target.checked })}
                  type="checkbox"
                />
                <span>Reverse x-axis</span>
              </label>
            )}
          </div>
        ),
      })}

      {moduleCard({
        kicker: "Presentation",
        title: "Style and palette",
        description: "Keep the submission language calm and consistent.",
        children: (
          <div className="plot-flow-field-grid">
            {currentTemplate?.editable_options.includes("style_preset") && (
              <label className="plot-flow-field-card">
                <span className="field-label">Submission mode</span>
                <select
                  className="field"
                  value={options.style_preset ?? meta?.default_style ?? ""}
                  onChange={(event) =>
                    onUpdateOptions({
                      style_preset: event.target.value,
                    })
                  }
                >
                  {styleOptions.map((choice) => (
                    <option key={choice.id} value={choice.id}>
                      {choice.label}
                    </option>
                  ))}
                </select>
              </label>
            )}

            {currentTemplate?.editable_options.includes("palette_preset") && (
              <label className="plot-flow-field-card">
                <span className="field-label">Palette</span>
                <select
                  className="field"
                  value={options.palette_preset ?? meta?.default_palette ?? ""}
                  onChange={(event) =>
                    onUpdateOptions({
                      palette_preset: event.target.value,
                    })
                  }
                >
                  {paletteOptions.map((choice) => (
                    <option key={choice.id} value={choice.id}>
                      {choice.label}
                    </option>
                  ))}
                </select>
              </label>
            )}

            {visualThemes.length > 0 && (
              <label className="plot-flow-field-card">
                <span className="field-label">Visual theme</span>
                <select
                  className="field"
                  value={options.visual_theme_id ?? ""}
                  onChange={(event) =>
                    onUpdateOptions({
                      visual_theme_id: event.target.value || null,
                    })
                  }
                >
                  <option value="">Publication only</option>
                  {visualThemes.map((choice) => (
                    <option key={choice.id} value={choice.id}>
                      {choice.label}
                    </option>
                  ))}
                </select>
              </label>
            )}
          </div>
        ),
      })}

      {moduleCard({
        kicker: "Advanced",
        title: "Editorial details",
        description: "Only the controls that add real figure value stay visible here.",
        children: (
          <div className="plot-flow-module-body">
            <div className="plot-flow-field-grid">
              {currentTemplate?.editable_options.includes("baseline") && (
                <label className="plot-flow-field-card">
                  <span className="field-label">Baseline</span>
                  <select
                    className="field"
                    value={options.baseline ?? "none"}
                    onChange={(event) =>
                      onUpdateOptions({
                        baseline:
                          event.target.value === "linear_endpoints"
                            ? "linear_endpoints"
                            : "none",
                      })
                    }
                  >
                    <option value="none">None</option>
                    <option value="linear_endpoints">Linear endpoints</option>
                  </select>
                </label>
              )}

              {currentTemplate?.editable_options.includes("show_colorbar") && (
                <label className="plot-flow-field-card toggle-field">
                  <input
                    checked={Boolean(
                      options.show_colorbar ?? currentTemplate.default_options.show_colorbar ?? true,
                    )}
                    onChange={(event) => onUpdateOptions({ show_colorbar: event.target.checked })}
                    type="checkbox"
                  />
                  <span>Show color bar</span>
                </label>
              )}
            </div>

            {tensileCurveMode && (
              <div className="plot-flow-note">Tensile curves keep linear x/y scales.</div>
            )}
          </div>
        ),
        tone: "soft",
      })}
    </>
  );

  const reviewPane = (
    <>
      <div className="plot-flow-summary-grid">
        {fieldCard({
          label: "Selected template",
          value: templateLabelValue,
          note: currentTemplate?.default_size ?? "Template selected",
          primary: true,
        })}
        {fieldCard({
          label: "Data context",
          value: inspection?.model_label ?? "Waiting for inspect",
          note: inspection?.signals[0] ?? "No signals recorded yet.",
        })}
        {fieldCard({
          label: "Theme / contract",
          value: selectedStyleLabel,
          note: selectedPaletteLabel,
        })}
        {fieldCard({
          label: "Sheet",
          value: sheetLabel,
          note: inputPath ? formatLeaf(inputPath) : "No source loaded",
        })}
      </div>

      {moduleCard({
        kicker: "Readiness",
        title: "Blockers and warnings",
        description: "Validation stays structured so you can scan it quickly.",
        children:
          preflightRequestError || preflightBusy || !preflight ? (
            <div className="plot-flow-note">
              {preflightRequestError
                ? preflightRequestError
                : preflightBusy
                  ? "Checking export readiness…"
                  : "Readiness checks start automatically in review."}
            </div>
          ) : (
            <div className="plot-flow-checklist">
              {blockingErrors.length > 0 ? (
                <div className="error-card">
                  <strong>Export is blocked</strong>
                  <ul className="bullet-list">
                    {blockingErrors.map((item) => (
                      <li key={item}>{item}</li>
                    ))}
                  </ul>
                </div>
              ) : (
                <div className="success-card">Ready to export.</div>
              )}

              {preflight.warnings.length > 0 && (
                <div className="plot-flow-note">
                  <strong>{preflight.warnings.length} warning(s)</strong>
                  <ul className="bullet-list">
                    {preflight.warnings.map((item) => (
                      <li key={item}>{item}</li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          ),
      })}

      {moduleCard({
        kicker: "Submission report",
        title: "Editorial summary",
        description: "Final checks, checksums, and bundle state stay productized.",
        children: submissionReport ? (
          <div className="plot-flow-checklist">
            <div className="plot-flow-note">{submissionReport.summary}</div>
            {submissionReport.checks.slice(0, 4).map((check) => (
              <div className="plot-flow-check-row" key={check.id}>
                <strong>{check.status}</strong>
                <span>{check.message}</span>
              </div>
            ))}
          </div>
        ) : (
          <div className="plot-flow-note">Submission summary will appear once preflight finishes.</div>
        ),
        tone: "soft",
      })}
    </>
  );

  const exportPane = (
    <>
      <div className="plot-flow-summary-grid">
        {fieldCard({
          label: "Outputs",
          value: outputItems.length,
          note: hasExportedOutputs ? "Bundle files are already written." : "Expected files will appear after export.",
          primary: true,
        })}
        {fieldCard({
          label: "Destination",
          value: exportResult?.output_dir ? formatLeaf(exportResult.output_dir) : "Pending export",
          note: exportResult?.preview_outputs?.length
            ? `${exportResult.preview_outputs.length} preview PNG file(s)`
            : "The handoff folder stays explicit.",
        })}
        {fieldCard({
          label: "Manifest",
          value: exportResult?.manifest_path ? formatLeaf(exportResult.manifest_path) : "Pending",
          note: exportResult?.artifact_paths?.length
            ? `${exportResult.artifact_paths.length} artifact file(s)`
            : "Bundle metadata remains organized.",
        })}
        {fieldCard({
          label: "Readiness",
          value:
            blockingErrors.length > 0 || preflightRequestError
              ? "Blocked"
              : canExport
                ? "Ready"
                : "Pending",
          note: submissionReport?.summary ?? "The delivery state stays calm and trustworthy.",
        })}
      </div>

      {moduleCard({
        kicker: "Delivery",
        title: "Bundle outputs and destination",
        description: "Keep the handoff explicit so the bundle is easy to trust.",
        children: exportResult ? (
          <div className="plot-flow-checklist">
            <div className="plot-flow-note">
              Exported {exportResult.outputs.length} file(s) to {formatLeaf(exportResult.output_dir)}.
            </div>
            <div className="plot-flow-check-row">
              <strong>Folder</strong>
              <span>{exportResult.output_dir}</span>
            </div>
            {exportResult.preview_outputs?.length ? (
              <div className="plot-flow-check-row">
                <strong>Preview PNG</strong>
                <span>{exportResult.preview_outputs.length} file(s)</span>
              </div>
            ) : null}
            {exportResult.artifact_paths?.length ? (
              <div className="plot-flow-check-row">
                <strong>Artifacts</strong>
                <span>{exportResult.artifact_paths.length} file(s)</span>
              </div>
            ) : null}
            {exportResult.manifest_path ? (
              <div className="plot-flow-check-row">
                <strong>Manifest</strong>
                <span>{formatLeaf(exportResult.manifest_path)}</span>
              </div>
            ) : null}
          </div>
        ) : (
          <div className="plot-flow-note">
            No bundle has been written yet. Export will create the output folder and supporting files.
          </div>
        ),
      })}

      {moduleCard({
        kicker: "Next actions",
        title: "Open the bundle or continue the flow",
        description: "The final move should stay calm and explicit.",
        children: (
          <div className="plot-flow-action-stack">
            <CompactToolbar label="Export actions">
              <button className="primary-button" disabled={!exportResult?.output_dir} onClick={onOpenOutputFolder} type="button">
                Open output folder
              </button>
              <button className="ghost-button" onClick={onOpenComposer} type="button">
                Open Composer
              </button>
              <button className="ghost-button" onClick={onStartAnotherPlot} type="button">
                Start another plot
              </button>
            </CompactToolbar>
          </div>
        ),
        tone: "soft",
      })}
    </>
  );

  const leftPane =
    stageKey === "tune" ? tunePane : stageKey === "review" ? reviewPane : exportPane;

  const footerActions =
    stageKey === "tune" ? (
      <>
        <button className="ghost-button" onClick={onBackToType} type="button">
          Back to type
        </button>
        <button className="plot-type-continue" disabled={!hasTemplate} onClick={onContinueToReview} type="button">
          Continue to review
        </button>
      </>
    ) : stageKey === "review" ? (
      <>
        <button className="ghost-button" onClick={onBackToTune} type="button">
          Back to tune
        </button>
        <button className="plot-type-continue" disabled={!canExport} onClick={onExport} type="button">
          Export bundle
        </button>
      </>
    ) : (
      <>
        <button className="ghost-button" onClick={onBackToReview} type="button">
          Re-open review
        </button>
        <button className="plot-type-continue" disabled={!exportResult?.output_dir} onClick={onOpenOutputFolder} type="button">
          Open output folder
        </button>
      </>
    );

  return (
    <div className={`plot-workspace plot-flow-v2 plot-flow-stage-${routeStage}`}>
      <header className="plot-flow-header">
        <div className="plot-flow-header-copy">
          <span>FIGURE FLOW · {stage.kicker.toUpperCase()}</span>
          <strong>{stage.title}</strong>
          <p>{stage.description}</p>
        </div>
        <span className={`status-pill ${statusChip.tone}`}>{statusChip.label}</span>
      </header>

      <div className="plot-flow-top-strip" aria-label={`${stage.kicker} context`}>
        <span>
          <strong>Source</strong>
          {sourceLabel}
        </span>
        <span>
          <strong>Sheet</strong>
          {sheetLabel}
        </span>
        <span>
          <strong>Template</strong>
          {templateLabelValue}
        </span>
      </div>

      <div className="plot-flow-grid">
        <section className="plot-flow-module-pane context-card">
          <div className="plot-flow-pane-head">
            <span>{stage.kicker}</span>
            <h2>{stage.title}</h2>
            <p>{stage.description}</p>
          </div>
          {leftPane}
        </section>

        <section className="plot-flow-preview-pane">
          <div className="plot-flow-preview-head">
            <div className="plot-flow-preview-copy">
              <span>{stage.previewKicker}</span>
              <strong>{stage.previewTitle}</strong>
              <p>{stage.previewDescription}</p>
            </div>
            <CompactToolbar label="Plot preview controls">
              {sheetNamesLength > 1 && (
                <button className="ghost-button" onClick={onChangeSheet} type="button">
                  Change sheet
                </button>
              )}
            </CompactToolbar>
          </div>

          <div className="plot-flow-preview-stats">
            {previewStatCards.map((card) => (
              <article
                className={`plot-flow-preview-stat ${card.primary ? "primary" : ""}`}
                key={card.label}
              >
                <span>{card.label}</span>
                <strong>{card.value}</strong>
                <p>{card.note}</p>
              </article>
            ))}
          </div>

          <div className="plot-flow-preview-shell">{previewContent}</div>
        </section>
      </div>

      <footer className="plot-flow-footer">
        <span>{stage.footerCopy}</span>
        <div className="plot-flow-footer-actions">{footerActions}</div>
      </footer>
    </div>
  );
}
