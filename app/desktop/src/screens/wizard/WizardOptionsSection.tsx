import type {
  RenderOptionsPayload,
  TemplateName,
  WorkbenchMeta,
  WorkbenchPalette,
  WorkbenchStyle,
  WorkbenchTemplate,
} from "../../lib/types";

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
  const selectedStyle =
    styleOptions.find((choice) => choice.id === (options.style_preset ?? meta?.default_style)) ??
    styleOptions[0] ??
    null;

  return (
    <section className="work-card section-card wizard-pane">
      <div className="panel-heading">
        <div>
          <div className="card-kicker">Adjust</div>
          <h3>Key controls</h3>
        </div>
      </div>
      {!template ? (
        <div className="placeholder-card">Pick a template.</div>
      ) : (
        <div className="wizard-section-stack">
          <div className="field-grid wizard-options-grid wizard-tight-grid">
            <label>
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
              <label>
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
              <label>
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
              <label>
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

            {currentTemplate?.editable_options.includes("reverse_x") && (
              <label className="toggle-field">
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

            {currentTemplate?.editable_options.includes("baseline") && (
              <label>
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
              <label className="toggle-field">
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
          </div>

          {tensileCurveMode && (
            <div className="hint-text">Tensile curves keep linear x/y scales.</div>
          )}

          {selectedStyle && (
            <details className="wizard-details">
              <summary>{selectedStyle.label}</summary>
              <div className="wizard-details-body">
                <div>{selectedStyle.preset_note}</div>
                <div>
                  {selectedStyle.hard_constraints
                    ? "Tighter editorial constraints stay on."
                    : "Uses the most forgiving defaults."}
                </div>
              </div>
            </details>
          )}

          {currentTemplate?.editable_options.includes("palette_preset") && (
            <details className="wizard-details">
              <summary>Palette</summary>
              <div className="field-grid compact-grid advanced-grid wizard-tight-grid">
                <label>
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
              </div>
            </details>
          )}
        </div>
      )}
    </section>
  );
}
