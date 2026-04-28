# SciPlot God

SciPlot God is a native macOS scientific figure workflow tool.

The app opens to a native macOS Launcher, which opens or focuses four singleton module windows:

1. Plot
2. Data Studio
3. Composer
4. Code Console

The Launcher is the supported app entry surface. Each module action must call a real workflow entrypoint: Plot import/open project, Data Studio raw import, Composer asset import, or Code Console context binding. Pixelmator-style presentation is treated as interaction grammar only; do not add fake drawing tools.

## Supported Runtime

- Desktop frontend: `app/macos` (SwiftUI)
- Backend: `app/sidecar` (FastAPI)
- Rendering/core: `src/rendering`, `src/data_studio`, `src/composer.py`
- Session async orchestration: shared latest-write-wins coordinators in `app/macos/Sources/Shared/Utilities/WorkspaceBridge.swift`

The historical `app/desktop` and Tauri/mock chain has been removed.

## Canonical Workflows

- Plot: `Import -> Inspect -> Template -> Refine -> Preflight -> Export`
- Data Studio: `Import -> Group Review -> Compare Preview -> Export / Open in Plot`
- Composer: `Assets -> Layout -> Compose -> Inspect -> Export`
- Code Console: `Bind Context -> Inspect Inputs -> Prompt/Code -> Run -> Outputs -> Handoff`

Canonical internal steps can be richer than user-visible UI; only user decision surfaces should stay visible.

## macOS Interaction Conventions

- The macOS scene model is one default Launcher window plus four independent singleton module windows. `Command-1/2/3/4` opens or focuses Plot, Data Studio, Composer, and Code Console respectively; module windows must not bring back the old left-side module switcher or stacked project/module/content headers.
- Global commands route through the focused module window context. Fallback app state exists for compatibility, but visible module switching is no longer a product surface.
- Plot open/import accepts either raw source data (`csv` / `xlsx` / `xlsm`) or a self-contained `.sciplotgod` project bundle. Saving a Plot project embeds the original source file bytes together with durable Plot state, so reopening the project restores the same starting point even if the original source path is gone.
- Plot exposes a `Data` utility affordance that opens `Data Workbook`, a read-only sheet with `Source Data`, `Transformed`, `Variables`, and `Fit` tabs. `Transformed` previews backend-applied typed data transforms, `Variables` shows durable scalar/expression variables, and `Fit` supports `linear`, `polynomial_2`, `polynomial_3`, `exponential`, `logarithmic`, `power_law`, `gaussian`, `logistic`, and bounded `custom_function` models. Fit reports the fitted equation/statistics plus per-point residual rows and shares its selected model with Plot fit overlays.
- Plot uses a dark pro workspace with a Pixelmator-style four-zone layout: left data/plot-type panel, central white figure/page preview, right glass adjustment inspector, and far-right adjustment category rail. The left panel owns import/open, current file, sheet switching, contract/backend-recommended plot types, and `Data Workbook` tab entry points; it must not become a layer/object list again.
- Plot live preview prefers a PNG bitmap payload returned by `/render-preview`, while the same response keeps PDF base64 as the authoritative exact preview/export fallback. Do not duplicate plotting semantics in Swift; the backend renderer remains the preview/export truth source.
- The far-right Plot rail is not a creation tools strip. It switches the right inspector between `Figure`, `Axes`, `Legend`, `Guides`, `Fit`, `Functions`, `Annotations`, and `Advanced Axes`; category buttons do not open popovers. Creation for guides, functions, text, and shapes happens inline inside the matching inspector category. `Data Cursor` stays out until preview hit-testing metadata exists.
- Plot adjustment inspector `Fit` exposes fit overlay controls only for curve-like templates (`curve`, `point_line`, `scatter`). Overlay rendering and `Data Workbook -> Fit` must stay on the same shared backend fit helper.
- Plot adjustment inspector `Advanced Axes` exposes typed `Extra Axes` (`extra x` + `extra y`). These DataGraph-inspired secondary axes travel through preview/export and `.sciplotgod` project persistence via shared render options; `extra x` stays a data/display conversion axis, while `extra y` now also supports DataGraph-style double-Y series assignment for `curve`, `point_line`, and `scatter`, with fit overlays following the assigned axis and without changing frozen `nature` metrics.
- Plot adjustment inspector `Advanced Axes` also exposes typed `Broken Axes` (`x` + `y`) for selected numeric templates. These DataGraph-inspired axis breaks now support both `Compressed` single-axis overlays and `Split` joined multi-panel layouts, stay linear-only, cannot coexist with `Extra Axes`, and only allow one active split axis at a time in the current release. They travel through the same preview/export/project payloads as the rest of Plot's durable render options, so they remain an advanced refinement layer under the recommendation-first quick-plot flow rather than becoming a second authoring model.
- Plot Guide tools create typed `Reference Guides` as exact-input scientific objects (`line` + `region`). Multiple guides can be layered, each guide can target `x`, `primary y`, or `secondary y`, and the whole stack flows through preview/export and `.sciplotgod` project persistence without changing frozen `nature` metrics.
- Plot adjustment inspector `Functions` exposes typed function layers for `function_curve`: bounded analytic function layers (`render_options.analytical_layers`) are sampled by the backend from safe math expressions and persist through preview/export/save/open rather than becoming a free-form command script. Function expressions share the backend expression engine used by data transforms and custom fits.
- Plot `Data Workbook` exposes the typed DataGraph-style data engine: `render_options.data_variables` plus `render_options.data_transforms`. Variables support scalar and expression values; transforms currently cover `derived_column`, `row_filter`, `mask_filter`, `sort_rows`, `select_columns`, `type_cast`, `bin_column`, `aggregate_summary`, `rolling_window`, and `pivot_matrix` (`xyz_long` or matrix materialization). Expressions are evaluated only by the backend safe AST layer, and transformed data is consumed by inspect/recommendation, preview/export/preflight/fit/Data Workbook/project persistence through the same payload.
- Plot inspection/recommendation now recognizes DataGraph-inspired advanced input shapes: XYZ or matrix scalar fields surface `contour_field`, theta/radius curve tables surface `polar_curve`, and compact mixed tables surface `table_figure`. These remain explicit public templates under the recommendation-first Plot flow, not a separate command interpreter.
- Plot Text and Shape tools create typed annotations, then hand editing to the selection inspector. Text notes/callouts and shape annotations (`rectangle`, `ellipse`, `bracket`) travel through the same preview/export/project payload path, reuse broken-axis and secondary-Y coordinate mapping, and stay an opt-in refinement layer under the recommendation-first workflow instead of becoming a second free-form authoring model.
- Data Studio can also save/open `.sciplotgod` project bundles. Data Studio projects embed the current workbook file(s) together with durable compare/filter/figure session state, and reopening routes directly back to Data Studio instead of falling through Plot.
- Data Studio import uses one staged native wizard sheet (`scope -> kind -> resolver -> create/edit template -> preview normalized output -> import`), not chained modal sheets; selecting import kind dismisses the wizard before presenting the native file picker.
- Data Studio user templates are v2 no-code table mappings. The import sheet previews encoding, delimiter, detected segments, row roles, and per-column roles before saving a template; rheology-style UTF-16 tab files can map one `Result` / `Interval data` block per series, while builtin tensile remains the regression baseline.
- Data Studio `Curves` template creation now defaults to raw-column curve preparation (curve-only workbook shape). Users must explicitly enable comparison to generate representative/metric compare sheets, and that mode requires at least one metric column binding.
- Data Studio curve-template exports no longer write a `DataStudio_Metadata` sheet. Curve sample names default to source filename and can be edited per selected Y series in the template editor.
- Data Studio now auto-routes curve-only / no-compare imports to `Plot`: if the rebuilt compare context has no supported recipe, the app invokes the existing `Open in Plot` path on the focused workbook and its preferred sheet.
- Data Studio resolver template adoption is recommendation-driven: the sheet requests ranked matches from sidecar and preselects the top recommendation when available. If no recommendation matches, the resolver keeps template selection empty and requires explicit manual selection (`disabled + help`), instead of silently defaulting to builtin tensile.
- Data Studio exposes an `Analysis` utility sheet with `Focused Workbook` and `Current Figure` scopes. `Source Data` shows paged workbook rows; `Fit` supports the shared Plot fit model surface. Current-figure fitting is limited to curve-like templates (`curve`, `point_line`, `scatter`).
- Export UX is unified around the global toolbar and menu commands. Workbench inspectors may expose `Advanced` output follow-up actions such as reveal/open latest output, but they must not duplicate the primary Import/Export buttons.
- Toolbar `Help` opens one app-level `Quick Help` sheet that maps to the active workbench with concise action-oriented prompts. Per-workbench long-form guide sheets are no longer part of the supported UI surface.
- Plot / Composer / Code Console figure exports always choose `PDF` or `300 dpi TIFF` first, then choose the destination. Single-output exports keep an editable filename; multi-output exports choose one base filename and append deterministic suffixes per figure.
- Code Console export only covers the latest run's generated PDF figure files. Managed run artifacts remain browsable in the Outputs panel, and revealing the managed output folder stays separate from user export destinations.
- Data Studio specimen filter uses one anchored popover entrypoint in the `Focused Group` strip. Do not restore a second left-rail trigger for the same control.
- Default specimen-filter content opens directly to the ranked Auto Keep 5 list: sort by distance from mean, highlight the five kept specimens, and avoid workbook labels, filenames, or representative-curve copy in the default view.
- Specimen identity, manual inclusion overrides, and manual representative-curve selection are Advanced-only via disclosure, with a local draft that does not affect compare/export until explicitly applied.
- `Workbook Groups` may expose one global `Auto Keep 5 All` action in the section header; it applies the committed auto-filter result to every eligible workbook group in the current session.
- Critical actions follow `disabled + help` and must not silently no-op.
- Shared empty/error states should stay concise (`status + next action`) rather than multi-paragraph workflow narration.
- Workbench top bars prioritize document-state feedback: current source, current template/figure, latest output, latest failure.
- Plot/Data Studio key edits support native Undo/Redo via `UndoManager`.
- Inspector keeps high-frequency controls visible and moves low-frequency controls into `DisclosureGroup("Advanced")`.
- Shared `Axis -> Advanced` inspector controls are the only home for smart tick-density and edge-label visibility settings; do not add a second Data Studio-only axis-label UI.
- Categorical statistics templates keep category labels but suppress x-axis tick marks, and standard numeric axes should default to restrained minor-tick density.

## Backend/API Boundaries

- `POST /inspect-file` is the single inspection/recommendation entry. Callers may pass optional `options.data_variables` / `options.data_transforms` when they need transform-aware recommendations; no-options import keeps the fast raw-source recommendation path. When transforms are supplied, recognition is based on the transformed table so derived/pivoted/aggregated data can enter the same ranked recommendation payload instead of requiring the original raw shape to be recognized first.
- `POST /source-table-preview` returns paged raw source-table rows plus detected encoding, delimiter, segments, column profiles, candidate roles, and x/y hints for Plot `Data Workbook`, Data Studio `Analysis`, and the Data Studio import wizard. Callers may pass `encoding`, `delimiter`, `header_row` / `header_row_index`, `unit_row` / `unit_row_index`, `data_start_row` / `data_start_row_index`, `segment_id`, and optional typed `options.data_variables` / `options.data_transforms` preview parameters.
- `POST /data-studio/template-preview` validates an unsaved v2 Data Studio template draft against a source file and returns normalized output counts, missing required roles, segment summaries, and warnings before a template is saved.
- Data Studio v2 `curve_metrics` templates carry `comparison_enabled`. `false` means curve-only workbook output (`All_Curves`); `true` keeps representative/metric compare sheets.
- `POST /data-studio/template-recommendations` returns ranked v2 template matches for a raw source file and is the only auto-adoption input for Data Studio resolver template preselection.
- `POST /fit-analysis` is the shared Plot/Data Studio fit-analysis route. It returns typed summaries plus paged derived rows for `linear`, `polynomial_2`, `polynomial_3`, `exponential`, `logarithmic`, `power_law`, `gaussian`, `logistic`, and bounded `custom_function`, accepts optional `options.data_variables` / `options.data_transforms`, and renderer overlays must use the same backend coefficients/equation helper.
- `POST /render-preview` returns `PreviewItemResponse` entries with `pdf_base64` and optional `png_base64`. Plot should use `png_base64` for live bitmap preview when present, and keep PDF as the export-grade fallback.
- `POST /save-project` and `POST /open-project` are the only supported app-level project-file persistence routes. `.sciplotgod` bundles are zip-based single files with schema validation/normalization at ingress and may embed Plot raw sources and/or Data Studio workbook files depending on the active workbench.
- `POST /data-studio/workbook-preview` serves both baseline specimen-filter analysis (no `specimen_states`) and committed applied preview refreshes (with `specimen_states`); there is no separate auto-filter endpoint.
- Baseline specimen-filter analysis means Auto Keep 5 ranking over the full workbook. Compare/export still consume only committed `specimen_states`, including any manually selected representative curve override.
- After a workbook is imported, Data Studio preview/compare/export read curves and metrics from that workbook only. `source_files` remain provenance metadata and must not be used as a silent fallback data source.
- `POST /data-studio/comparison-export` returns one comparison workbook, one filtered standard workbook per included group, and the selected figure outputs from the same committed compare state. Filtered workbooks stay re-importable; curve sheets keep four decimal places, while specimen / summary / replicate numeric tables stay at two decimal places.
- `POST /code-console/context` returns a stable `context_id` (input signature + mtime).
- `POST /code-console/run` accepts `context_id` fast path and still supports legacy `context`.
- `GET /meta`, `GET /plot-contract`, and `DELETE /data-studio/templates/{id}` use explicit response schemas.
- `POST /data-studio/source-preview` has been removed; Data Studio raw preview must go through `/source-table-preview` and draft parsing must go through `/data-studio/template-preview`.
- Ranked recommendation fields are canonical:
  - `recommendations`
  - `primary_recommendation`
  - `alternative_recommendations`
  - `advanced_templates`
  - `recommendation_confidence`
  - `recommendation_summary`
- Legacy fields/endpoints have been removed:
  - `POST /recommend-render`
  - `inspection.recommendation`
  - `/preprocess-tensile-replicates`
  - `/inspect-tensile-workbook`
  - `/export-tensile-comparison`

## Single Sources Of Truth

- Plot contract: `src/plot_contract.json`
- Contract loader: `src/plot_contract.py`
- Sidecar schema/validation/migration:
  - `app/sidecar/schemas.py`
  - `app/sidecar/schemas_render.py`
  - `app/sidecar/schemas_data_studio.py`
  - `app/sidecar/schemas_code_console.py`
- Data Studio v2 import-template schema and workbook generation:
  - `src/data_studio/models.py`
  - `src/data_studio/import_templates_v2.py`
  - `src/rendering/source_table_preview.py`

When behavior is a contract change, update contract first, regenerate docs, then update Python/sidecar/macOS consumers.

## Plot Contract Semantics

- Public plotting styles are `nature`, `editorial`, `presentation`, and `poster`.
- `nature` remains the frozen publication profile and the default global style.
- Legacy style ids such as `default`, `lab_default`, `science_editorial`, `jacs_analytical`, and `advanced_materials_spacious` are ingress-only compatibility aliases and must normalize immediately to `nature`.
- `style_preset` is the primary visual direction. Each public style now declares contract-owned `recommended_palette_preset` and `recommended_visual_theme_id`, so choosing a style seeds its recommended palette/background pair while still allowing later independent overrides.
- `palette_preset` and `visual_theme_id` remain independent public controls. Templates still publish `default_options`, but those defaults must stay aligned with the selected style's recommended palette/theme bundle instead of drifting into a second recommendation system.
- Public palette/theme catalogs now include the ECharts-inspired `infographic`, `roma`, `macarons`, `shine`, and `vintage` options. `theme` stays a soft visual layer only; hard typography/stroke changes belong to `style_preset`.
- Public curve/stat/template coverage now includes ECharts-inspired `area_curve`, `step_line`, `stacked_area`, and `density_area`, plus DataGraph-inspired `function_curve`, `contour_field`, `polar_curve`, and `table_figure` as explicit public templates.
- Public template/catalog/recommendation surfaces expose only explicit chart templates.
- Legacy template ids such as `scatter_with_fit`, `replicate_curves_with_band`, `grouped_bar_error`, and `grouped_bar_compare` are ingress-only aliases and must normalize immediately to `scatter_fit`, `mean_band`, and `bar`.
- Template presentation metadata such as gallery thumbnail kind must come from `src/plot_contract.json` and `/meta`, not from macOS-local template-id heuristics.
- `distribution_compare` is compatibility-only and must never be emitted as a public template id; resolve it to `box`, `box_strip`, or `violin`, with `box` as the conservative fallback when source inspection is unavailable.
- Shared axis/unit display normalization lives in `src/text_normalization.py`; callers must preserve mathtext exponents for unknown-but-unit-like inputs such as `kJ/m2` instead of leaving superscripts to frontend heuristics.
- `scripts/smoke_check.py` is expected to enforce public-surface guardrails, including contract lint plus a fixed style/theme/template render matrix over representative templates. Any error-level failed validation must fail the command, and `non_blank_pdf` is reserved for real PDF raster sanity checks. Do not weaken that matrix when adding new templates or visual catalogs.

## Engineering Principles

- Start from the minimum necessary state. If a UI string, badge, or button state can be derived from one source of truth, do not store it separately.
- Keep one source of truth per semantic rule. Backend rules live in Python/contract/schema; the macOS frontend consumes and presents them instead of recomputing them.
- Add abstractions only when they reduce real duplication and clarify ownership. Speculative “maybe reusable later” layers are treated as maintenance debt.
- Remove dead helpers, stale branches, and duplicate state wiring in the same round as the feature change. Do not normalize “we’ll clean it later.”
- Prefer small typed payloads and presentation models over scattered booleans, magic strings, and implicit state machines.

## Entrypoints

- CLI: `make_plot.py`
- Sidecar app: `app/sidecar/server.py`
- Native desktop launcher: `Launch_Plotter.command`

## Validation

- Blocking gate (recommended one-command entry):
  - `.venv/bin/python scripts/blocking_gate.py`
  - Inner beta strict path:
    - `.venv/bin/python scripts/manual_smoke_evidence.py validate --input <path> --require-all`
    - `.venv/bin/python scripts/blocking_gate.py --require-manual --manual-evidence <path>`
  - `--manual-check` remains available as a non-strict human assertion path. Under `--require-manual`, checklist flags alone no longer satisfy the inner beta gate; use a complete evidence bundle instead.
  - Only pass a `--manual-check` after that desktop flow was actually completed; capture or save-panel failures should be recorded as blocked/pending in `docs/engineering-handoff.md`.
  - The default overlay evidence sample for inner beta should be a richer Plot project that includes transform + fit + overlay state, not a minimal overlay-only case.
- Clean:
  - `.venv/bin/python scripts/clean_repo.py`
- Ruff:
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`
- Mypy:
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`
- Pytest:
  - `.venv/bin/python -m pytest tests`
- Smoke:
  - `.venv/bin/python scripts/smoke_check.py`
- macOS GUI smoke/fingerprint guardrails:
  - Launcher, independent module-window roots, Plot empty/imported workspace, imported-state Plot inspector, Plot data workbook, and Data Studio figure inspector snapshots are part of the canonical `InspectorLayoutPolicyTests` matrix and should keep exporting xcresult attachments for artifact-based visual QA.
- macOS build:
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`
- macOS test:
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`

## More

- Product architecture: `docs/product-architecture.md`
- Maintenance governance: `docs/maintenance-governance.md`
- Plot contract doc (generated): `docs/plot_contract.md`
- Contributor/agent rules: `AGENTS.md`
- Engineering handoff + runbook: `docs/engineering-handoff.md`

## Handoff / Onboarding

If you are taking over development, use this order:

1. Read `AGENTS.md` for boundaries, invariants, and forbidden legacy restores.
2. Read `docs/maintenance-governance.md` for maintenance method, change taxonomy, review gates, and rollback duties.
3. Read `docs/engineering-handoff.md` for latest change history, risk points, and troubleshooting.
4. Run the full validation matrix once in your machine:
   - `.venv/bin/python scripts/blocking_gate.py`
   - plus one manual smoke round for:
     - Plot import -> preview -> export
     - Data Studio import -> open in Plot
     - Overlay add/select/drag(or nudge) -> save/reopen consistency
   - for inner beta sign-off, record those three flows into an evidence bundle and run:
     - `.venv/bin/python scripts/manual_smoke_evidence.py validate --input <path> --require-all`
     - `.venv/bin/python scripts/blocking_gate.py --require-manual --manual-evidence <path>`
   - the current hard-gated Plot reopen states for inner beta are:
     - `fit`
     - `reference/text/shape overlays`
     - `data variables/transforms`
     - `extra_x_axis / extra_y_axis`
     - `x_axis_breaks / y_axis_breaks`
     - `analytical_layers`
   - Data Studio inner beta readiness also requires trustworthy heterogeneous import behavior: correct recommendation, correct no-recommendation, and consistent preview/build semantics for real raw fixtures.
   - if you prefer explicit commands, run clean/ruff/mypy/pytest/smoke_check/xcodebuild build/test in order
5. Confirm you can execute one complete end-to-end flow in each workbench:
   - Plot
   - Data Studio
   - Composer
   - Code Console
6. Before shipping any change, update the required docs:
   - `AGENTS.md` / `README.md` (if responsibilities, boundaries, workflow, or discoverability changed)
   - `docs/maintenance-governance.md` (if maintenance method, review gates, or documentation duties changed)
   - `docs/engineering-handoff.md` (every round, required)
