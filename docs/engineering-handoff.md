# Engineering Handoff

This public handoff replaces the private beta work log. It keeps only the current state needed by maintainers and contributors.

## Current Release Target

- Product name: SciPlot
- Release channel: `0.1.0-beta`
- Distribution model: source preview only; no signed or notarized macOS app bundle is published.
- Project extension: `.sciplot` only.

## Supported Architecture

- `app/macos`: native SwiftUI desktop frontend.
- `app/sidecar`: FastAPI sidecar and route surface.
- `src/rendering`: plot inspection, recommendation, preflight, rendering, cache, options, and IO.
- `src/data_studio`: Data Studio intake, template, workbook, and comparison services.
- `src/composer.py` and related composer modules: composition service surface.
- `src/code_console_service.py` and `src/code_console_runtime.py`: Code Console context and run service.

## Maintainer Notes

- Keep `src/plot_contract.json` as the single source of truth for public plot templates, styles, palettes, themes, defaults, and gallery metadata.
- Keep LabPlot-scale capability status flowing through `/meta`, sidecar schemas, `.sciplot` document graph nodes, and macOS decode models; do not add a second local capability table in Swift.
- Keep project open/save routed through sidecar schema normalization.
- Keep `.sciplot` self-contained: embedded sources and workbooks are the restore truth, not original absolute paths.
- Keep macOS as the only supported desktop frontend.
- Keep `Launch_SciPlot.command` as the source-run launcher for the beta.
- Keep LabPlot-inspired work clean-room while SciPlot remains Apache-2.0. `scripts/check_labplot_cleanroom.py` rejects copied LabPlot GPL source headers.

## LabPlot-Scale Runtime

LabPlot-scale runtime is product surface, not roadmap. The former roadmap has been retired into this handoff, `docs/product-architecture.md`, `docs/macos-frontend-design.md`, and `docs/labplot-technical-borrowing.md`.

### Clean-room policy

- SciPlot remains Apache-2.0; LabPlot remains a clean-room reference only.
- LabPlot can inspire taxonomy, object ownership, UX behavior, and fixture ideas.
- No LabPlot C++/Qt/NSL implementation, headers, or GPL source snippets may be copied, vendored, linked, or translated line-by-line.
- The executable guard is `scripts/check_labplot_cleanroom.py`, and the blocking gate keeps `labplot_cleanroom`.

### Capability status policy

- `enabled` means there is current runtime support behind the sidecar/macOS contract plus tests or explicit disabled/help behavior.
- `disabled` means the project intentionally records a currently unsupported capability and must surface a user-facing help explanation.
- `/meta` capability catalogs must not expose planning statuses such as `experimental` or `coming_soon`; unfinished items are either implemented or disabled with help.
- Swift must consume `/meta` and sidecar schemas instead of maintaining a second local capability table.

### Runtime surfaces

- `GET /meta` capability catalogs are built by `src/rendering/capability_registry.py`.
- `POST /source-table-preview` and `POST /fit-analysis` use shared `DataContainerPayload` helpers from `src/rendering/data_containers.py`.
- `POST /analysis-operation` runs the SciPlot-owned analysis envelope in `src/rendering/analysis_operations.py`.
- `POST /import-preview` dispatches explicit filter previews from `src/rendering/import_filters.py`.
- `POST /plot-edit-command/normalize` validates undoable plot edit commands in `src/rendering/plot_object_commands.py`.
- `POST /code-console/run` returns `notebook_outputs` and readonly notebook output containers for generated figure/table artifacts.

### SciPlotDocumentGraph

- `.sciplot` bundles carry `document_graph` for durable object identity, module roots, graph nodes, graph edges, selected nodes, and migration notes.
- The graph is internal persistence and command-model structure only; do not restore a global Project Explorer, shared rail, or global workbench shell.
- Plot graph nodes cover source, scene, series, axes, legend, guides, annotations, function layers, extra/broken axes, fit overlays, page, and plot area.
- Data Studio, Composer, and Code Console graph nodes cover workbook/group/table/matrix, pages/panels/assets, context bindings, runs, generated figures, and generated tables.

### Data containers

- `DataContainerPayload` is shared by Plot Data Workbook, Data Studio Analysis, import preview, fit/analysis results, and Code Console notebook outputs.
- Enabled container kinds are `table`, `matrix`, `transformed_view`, `statistics_summary`, `fit_result`, and `notebook_output`.
- Containers are readonly in macOS v1. Inline mutation must wait for command-backed container edits.
- Statistics, matrix dimensions, coordinate vectors, fit residual/result tables, and provenance are generated in sidecar, not Swift.

### Analysis operations

- `/analysis-operation` returns `AnalysisOperationResultPayload` with diagnostics, metrics, tables, overlays, and data containers.
- Enabled operations include smoothing, interpolation, differentiation, integration, FFT, Fourier filter, correlation, convolution, baseline correction, peak detection, KDE, statistical tests, distribution fitting, peak fitting, and growth models.
- Numerical implementation is SciPlot-owned NumPy/SciPy code. Do not copy LabPlot NSL algorithms.

### Import and export runtime

- Enabled import filters: CSV/TSV/TXT, Excel, JSON records/tables, and explicit binary/raw with dtype/shape.
- Disabled import filters: SQL, HDF5, NetCDF, FITS, ODS, ReadStat/SAS/Stata/SPSS, Origin/SciDAVis evaluation, and image digitizer. Each must return structured diagnostics and help.
- Export targets cover figure PDF/TIFF, data workbook, project bundle, comparison bundle, artifact manifest, and Code Console figure sets.
- Exported multi-file artifacts must be manifest-backed so restore, reveal, and future packaging have a single truth source.

### Plot object commands and UndoManager

- Plot durable edits use typed commands: add, edit, delete, reorder, rename, visibility, lock, and copy_settings.
- The sidecar normalizes commands and emits graph patches; macOS stores before/after payloads in native `UndoManager`.
- Inspector-local state must not be the only copy of a scientific edit.

### Code Console notebook bridge

- Keep Code Console notebook outputs inside the existing Code Console module. Do not add a fifth Notebook module.
- Generated figures become notebook figure outputs; generated CSV/JSON tables become readonly notebook output containers.
- Project restore uses embedded latest-run artifacts for UI continuity and does not rerun code as restore truth.

### Testing policy

- Capability status changes require `/meta` schema tests, route tests, Swift decoding tests, and docs updates.
- Numerical operations require deterministic fixtures with tolerances before they remain `enabled`.
- Disabled imports require structured diagnostic tests.
- Project graph and Code Console artifacts require `.sciplot` save/open roundtrip coverage.
- UI guardrails must keep Launcher plus four singleton module windows and forbid global Project Explorer/shared rail regressions.

## Validation

Recommended local gate:

```bash
.venv/bin/python scripts/blocking_gate.py
```

Useful component checks:

```bash
.venv/bin/python scripts/check_labplot_cleanroom.py
.venv/bin/python -m ruff check .
.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering
.venv/bin/python -m pytest tests
.venv/bin/python scripts/smoke_check.py
xcodebuild -project app/macos/SciPlot.xcodeproj -scheme SciPlotMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test
```

## Known Beta Limits

- No packaged app is published.
- App signing, hardened runtime, and notarization are not configured for external distribution.
- Project schema and some route payloads may still change before a stable release.
- Manual desktop smoke evidence is still required before calling a build ready for broader testers.
