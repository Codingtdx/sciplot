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
- `POST /source-table-preview` returns shared `DataContainerPayload` helpers plus structured import diagnostics for encoding, delimiter, table structure, ragged rows, duplicate headers, and selected segments.
- `POST /analysis-operation` runs the SciPlot-owned analysis envelope in `src/rendering/analysis_operations.py`.
- `POST /import-preview` dispatches explicit filter previews from `src/rendering/import_filters.py` and returns `ImportFilterProfilePayload`, `ImportDiagnosticPayload`, available options, structure nodes, and readonly containers.
- `POST /plot-edit-command/normalize` validates undoable plot edit commands in `src/rendering/plot_object_commands.py`.
- `POST /command/normalize` and `POST /command/apply-preview` extend the command envelope across Plot, Data Studio, Composer, and Code Console graph objects.
- `POST /preview-scene` returns a contract-gated Swift-native realtime preview scene; `/render-preview` remains the authoritative bitmap/PDF correction path.
- `POST /live-source/update-now` refreshes enabled file-tail, folder-watch, or periodic-CSV sources into revisioned data containers.
- `POST /code-console/run` returns `notebook_outputs` and readonly notebook output containers for generated figure/table artifacts.

### SciPlotDocumentGraph

- `.sciplot` bundles carry `document_graph` for durable object identity, module roots, graph nodes, graph edges, selected nodes, visibility/lock state, revision numbers, events, and migration notes.
- The graph is internal persistence and command-model structure only; do not restore a global Project Explorer, shared rail, or global workbench shell.
- Plot graph nodes cover source, scene, series, axes, legend, guides, annotations, function layers, extra/broken axes, fit overlays, page, and plot area.
- Data Studio, Composer, and Code Console graph nodes cover workbook/group/table/matrix, pages/panels/assets, context bindings, runs, generated figures, and generated tables.
- Sidecar owns deterministic naming and graph revision metadata. Swift should not invent durable object names or accept stale preview updates after a newer graph revision.

### Data containers

- `DataContainerPayload` is shared by Plot Data Workbook, Data Studio Analysis, import preview, fit/analysis results, and Code Console notebook outputs.
- Enabled container kinds are `table`, `matrix`, `transformed_view`, `statistics_summary`, `fit_result`, and `notebook_output`.
- Columns carry stable ids, mode, role hints, unit, comment, format, dictionary/category hints, missing policy, source lineage, computed expression metadata, readonly status, and lifecycle event names.
- Containers are readonly in macOS v1. Inline mutation must wait for command-backed container edits.
- Statistics, matrix dimensions, coordinate vectors, fit residual/result tables, and provenance are generated in sidecar, not Swift.

### Analysis operations

- `/analysis-operation` returns `AnalysisOperationResultPayload` with diagnostics, metrics, tables, overlays, and data containers.
- Operation envelopes include settings, source binding, prepared-array summary, elapsed time, lineage, and artifact refs so results can become graph nodes and be restored without Swift recomputation.
- Enabled operations include smoothing, interpolation, differentiation, integration, FFT, Fourier filter, correlation, convolution, baseline correction, peak detection, KDE, statistical tests, distribution fitting, peak fitting, and growth models.
- Numerical implementation is SciPlot-owned NumPy/SciPy code. Do not copy LabPlot NSL algorithms.

### Import and export runtime

- Enabled import filters: CSV/TSV/TXT, Excel, JSON records/tables, and explicit binary/raw with dtype/shape.
- CSV/Excel previews use the shared source table import core. Data Studio must not maintain a separate encoding/delimiter/sheet/block parser.
- Disabled import filters: SQL, HDF5, NetCDF, FITS, ODS, ReadStat/SAS/Stata/SPSS, Origin/SciDAVis evaluation, and image digitizer. Dependency-backed filters report `dependency_missing` or policy diagnostics with help; they are not marked enabled until dependency, fixtures, schema decode, and UI consumption all exist.
- Data Studio raw import calls `/import-preview` before template recommendation. Template recommendation/preview may carry the selected import profile and diagnostics so template binding uses the same parsed source context the user saw.
- Export targets cover figure PDF/TIFF, data workbook, project bundle, comparison bundle, artifact manifest, and Code Console figure sets.
- Exported multi-file artifacts must be manifest-backed so restore, reveal, and future packaging have a single truth source.

### Plot object commands and UndoManager

- Durable edits use typed commands: add, edit, delete, reorder, rename, visibility, lock, copy_settings, bind_source, apply_template, import_container, and create_output_ref.
- Plot durable edits use typed commands, and the same envelope now extends to Data Studio, Composer, and Code Console graph actions.
- PlotSession records local before/after snapshots first, then calls `POST /command/normalize` followed by `POST /command/apply-preview`; the returned normalized command, graph revision, and graph patch replace the optimistic ledger entry.
- The sidecar normalizes commands, emits graph patches, rejects stale command revisions with diagnostics, and can apply preview-only graph patches; macOS stores before/after payloads in native `UndoManager`.
- Inspector-local state must not be the only copy of a scientific edit.
- Current Plot command coverage includes series style/offset, axes label/range/tick edits, legend order reset/reorder, reference guides, text annotations, shape annotations, analytical function layers, fit overlay selection metadata, visibility toggles, delete, rename, lock, and copy-settings payloads.
- Undo/redo restores the real render/fit snapshot and records a reversible `plot:session` command so the command ledger remains an audit trail instead of a UI-only history.

### Native realtime preview

- Native preview is admitted by `/meta` and `POST /preview-scene`, not by Swift template constants.
- PlotSession requests `/preview-scene` before `/render-preview`. The scene can be used immediately for Swift Canvas drawing and hit testing, then the backend bitmap/PDF corrects the publication preview.
- Supported scene data must include figure geometry, axis bbox/ranges, series samples, object ids, `bbox_pixels`, point arrays, payload refs, operations, and hit-test metadata for selection, guide/annotation drag, legend/series quick edit, and fallback reasons.
- The scene object surface covers series, x/y axes, legend, reference guide lines/regions, text annotations, shape annotations, function layers, and fit overlays. Each object carries visible/locked state and a `payload_ref` that routes the Plot inspector without a global Project Explorer.
- Unsupported templates, missing samples, invalid axes, advanced axis conflicts, or data over budget fall back to backend bitmap/PDF preview.
- `/render-preview`, export, save/open project, analysis, transforms, and import remain backend-authoritative.

### Live source foundation

- `/meta` records live-source capabilities for file tail, folder watch, and periodic CSV refresh as enabled catalog entries backed by `POST /live-source/update-now`, with MQTT/serial/socket disabled until sandbox and fixture policy exist.
- Live data updates must produce a data revision and preview invalidation path. They must not bypass document graph semantics.

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
