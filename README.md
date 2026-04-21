# SciPlot God

SciPlot God is a native macOS scientific figure workflow tool.

The app has four primary workbenches:

1. Plot
2. Data Studio
3. Composer
4. Code Console

These four are the only app-level primary destinations.

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

- Data Studio import uses one staged native wizard sheet (`scope -> kind -> resolver -> create template`), not chained modal sheets; selecting import kind dismisses the wizard before presenting the native file picker.
- Export UX is unified around the Data Studio inspector pattern: toolbar `Export` remains the global entrypoint, while workbench inspectors expose `Section("Actions")` with a primary export action and an `Advanced` disclosure for `Reveal Output` plus `Latest Export`.
- Plot / Composer / Code Console figure exports always choose `PDF` or `300 dpi TIFF` first, then choose the destination. Single-output exports keep an editable filename; multi-output exports choose one base filename and append deterministic suffixes per figure.
- Code Console export only covers the latest run's generated PDF figure files. Managed run artifacts remain browsable in the Outputs panel, and revealing the managed output folder stays separate from user export destinations.
- Data Studio specimen filter uses one anchored popover entrypoint in the `Focused Group` strip. Do not restore a second left-rail trigger for the same control.
- Default specimen-filter content opens directly to the ranked Auto Keep 5 list: sort by distance from mean, highlight the five kept specimens, and avoid workbook labels, filenames, or representative-curve copy in the default view.
- Specimen identity, manual inclusion overrides, and manual representative-curve selection are Advanced-only via disclosure, with a local draft that does not affect compare/export until explicitly applied.
- `Workbook Groups` may expose one global `Auto Keep 5 All` action in the section header; it applies the committed auto-filter result to every eligible workbook group in the current session.
- Critical actions follow `disabled + help` and must not silently no-op.
- Workbench top bars prioritize document-state feedback: current source, current template/figure, latest output, latest failure.
- Plot/Data Studio key edits support native Undo/Redo via `UndoManager`.
- Inspector keeps high-frequency controls visible and moves low-frequency controls into `DisclosureGroup("Advanced")`.
- Shared `Axis -> Advanced` inspector controls are the only home for smart tick-density and edge-label visibility settings; do not add a second Data Studio-only axis-label UI.
- Categorical statistics templates keep category labels but suppress x-axis tick marks, and standard numeric axes should default to restrained minor-tick density.

## Backend/API Boundaries

- `POST /inspect-file` is the single inspection/recommendation entry.
- `POST /data-studio/workbook-preview` serves both baseline specimen-filter analysis (no `specimen_states`) and committed applied preview refreshes (with `specimen_states`); there is no separate auto-filter endpoint.
- Baseline specimen-filter analysis means Auto Keep 5 ranking over the full workbook. Compare/export still consume only committed `specimen_states`, including any manually selected representative curve override.
- After a workbook is imported, Data Studio preview/compare/export read curves and metrics from that workbook only. `source_files` remain provenance metadata and must not be used as a silent fallback data source.
- `POST /data-studio/comparison-export` returns one comparison workbook, one filtered standard workbook per included group, and the selected figure outputs from the same committed compare state. Filtered workbooks stay re-importable; curve sheets keep four decimal places, while specimen / summary / replicate numeric tables stay at two decimal places.
- `POST /code-console/context` returns a stable `context_id` (input signature + mtime).
- `POST /code-console/run` accepts `context_id` fast path and still supports legacy `context`.
- `GET /meta`, `GET /plot-contract`, and `DELETE /data-studio/templates/{id}` use explicit response schemas.
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

When behavior is a contract change, update contract first, regenerate docs, then update Python/sidecar/macOS consumers.

## Plot Contract Semantics

- Public plotting styles are `nature`, `editorial`, `presentation`, and `poster`.
- `nature` remains the frozen publication profile and the default global style.
- Legacy style ids such as `default`, `lab_default`, `science_editorial`, `jacs_analytical`, and `advanced_materials_spacious` are ingress-only compatibility aliases and must normalize immediately to `nature`.
- `palette_preset` and `visual_theme_id` are independent public controls. Templates may recommend defaults for `style_preset`, `palette_preset`, and `visual_theme_id` through contract `default_options`, but user edits to one control must not silently rewrite the others.
- Public palette/theme catalogs now include the ECharts-inspired `infographic`, `roma`, `macarons`, `shine`, and `vintage` options. `theme` stays a soft visual layer only; hard typography/stroke changes belong to `style_preset`.
- Public curve/stat template coverage now includes ECharts-inspired `area_curve`, `step_line`, `stacked_area`, and `density_area` alongside the existing explicit templates.
- Public template/catalog/recommendation surfaces expose only explicit chart templates.
- Legacy template ids such as `scatter_with_fit`, `replicate_curves_with_band`, `grouped_bar_error`, and `grouped_bar_compare` are ingress-only aliases and must normalize immediately to `scatter_fit`, `mean_band`, and `bar`.
- Template presentation metadata such as gallery thumbnail kind must come from `src/plot_contract.json` and `/meta`, not from macOS-local template-id heuristics.
- `distribution_compare` is compatibility-only and must never be emitted as a public template id; resolve it to `box`, `box_strip`, or `violin`, with `box` as the conservative fallback when source inspection is unavailable.
- `scripts/smoke_check.py` is expected to enforce public-surface guardrails, including contract lint plus a fixed style/theme/template render matrix over representative templates. Do not weaken that matrix when adding new templates or visual catalogs.

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
  - imported-state Plot inspector and Data Studio figure inspector snapshots are part of the canonical `InspectorLayoutPolicyTests` matrix and should keep exporting xcresult attachments for artifact-based visual QA.
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
   - clean
   - ruff
   - mypy
   - pytest
   - smoke_check
   - xcodebuild build/test
5. Confirm you can execute one complete end-to-end flow in each workbench:
   - Plot
   - Data Studio
   - Composer
   - Code Console
6. Before shipping any change, update the required docs:
   - `AGENTS.md` / `README.md` (if responsibilities, boundaries, workflow, or discoverability changed)
   - `docs/maintenance-governance.md` (if maintenance method, review gates, or documentation duties changed)
   - `docs/engineering-handoff.md` (every round, required)
