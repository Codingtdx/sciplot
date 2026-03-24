import type {
  RenderOptionsPayload,
  TemplateName,
  WorkbenchMeta,
  WorkbenchPalette,
  WorkbenchStyle,
  WorkbenchTemplate,
} from "../../lib/types";
import { visualThemeChoices } from "../../lib/workbench";

type Props = {
  meta: WorkbenchMeta | null;
  template: TemplateName | null;
  currentTemplate: WorkbenchTemplate | null;
  options: RenderOptionsPayload;
  sizeOptions: Array<{ id: string; label: string }>;
  styleOptions: WorkbenchStyle[];
  paletteOptions: WorkbenchPalette[];
  tensileCurveMode: boolean;
  onUpdateOptions(value: Partial<RenderOptionsPayload>): void;
};

export function WizardOptionsSection({
  meta,
  template,
  currentTemplate,
  options,
  sizeOptions,
  styleOptions,
  paletteOptions,
  tensileCurveMode,
  onUpdateOptions,
}: Props) {
  const visualThemes = visualThemeChoices(meta);
  const selectedStyle =
    styleOptions.find((choice) => choice.id === (options.style_preset ?? meta?.default_style)) ??
    styleOptions[0] ??
    null;
  const selectedVisualTheme =
    visualThemes.find((choice) => choice.id === options.visual_theme_id) ?? null;

  return (
    <section className="context-card wizard-pane">
      <div className="panel-heading">
        <div>
          <div className="card-kicker">Adjust</div>
          <h3>Controls</h3>
        </div>
      </div>
      {!template ? (
        <div className="placeholder-card">Pick a template.</div>
      ) : (
        <div className="wizard-section-stack">
          <div className="wizard-options-core">
            <div className="wizard-options-heading">
              <strong>Core controls</strong>
              <span>Adjust only what matters.</span>
            </div>

            <div className="field-grid wizard-options-grid wizard-tight-grid">
              <label className="wizard-option-card">
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
                <label className="wizard-option-card">
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
                <label className="wizard-option-card">
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

              {currentTemplate?.editable_options.includes("style_preset") && (
                <label className="wizard-option-card">
                  <span className="field-label">Publication profile</span>
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

              {visualThemes.length > 0 && (
                <label className="wizard-option-card">
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

              {currentTemplate?.editable_options.includes("reverse_x") && (
                <label className="toggle-field wizard-option-card">
                  <input
                    checked={Boolean(options.reverse_x)}
                    onChange={(event) =>
                      onUpdateOptions({ reverse_x: event.target.checked })
                    }
                    type="checkbox"
                  />
                  <span>Reverse x-axis</span>
                </label>
              )}
            </div>
          </div>

          {tensileCurveMode && (
            <div className="hint-text">Tensile curves keep linear x/y scales.</div>
          )}

          {selectedStyle && (
            <details className="wizard-details">
              <summary>Current publication profile</summary>
              <div className="wizard-details-body">
                <div>
                  <strong>{selectedStyle.label}</strong>
                </div>
                <div>{selectedStyle.preset_note}</div>
                <div>
                  {selectedStyle.hard_constraints
                    ? "Editorial constraints stay on."
                    : "Uses the default relaxed mode."}
                </div>
              </div>
            </details>
          )}

          {selectedVisualTheme && (
            <div className="wb-inline-meta">
              Visual theme: {selectedVisualTheme.label} - {selectedVisualTheme.description}
            </div>
          )}

          <details className="wizard-details">
            <summary>Advanced options</summary>
            <div className="field-grid compact-grid advanced-grid wizard-tight-grid">
              {currentTemplate?.editable_options.includes("baseline") && (
                <label className="wizard-option-card">
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
                <label className="toggle-field wizard-option-card">
                  <input
                    checked={Boolean(
                      options.show_colorbar ??
                        currentTemplate.default_options.show_colorbar ??
                        true,
                    )}
                    onChange={(event) =>
                      onUpdateOptions({ show_colorbar: event.target.checked })
                    }
                    type="checkbox"
                  />
                  <span>Show color bar</span>
                </label>
              )}

              {currentTemplate?.editable_options.includes("palette_preset") && (
                <label className="wizard-option-card">
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
            </div>
          </details>
        </div>
      )}
    </section>
  );
}
