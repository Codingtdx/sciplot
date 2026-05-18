# Sidecar API Surface

This document records public sidecar routes that macOS may call directly. Every route returns an explicit response model from `app/sidecar/schemas_*.py`; do not add naked dict routes.

## LabPlot-Scale Runtime Routes

- `GET /meta`: returns plot contract metadata plus capability catalogs. Catalog statuses are only `enabled` or `disabled`; disabled entries must include help text.
- `POST /source-table-preview`: previews raw or transformed source tables and returns shared `DataContainerPayload` values plus structured import diagnostics.
- `POST /fit-analysis`: runs fit analysis and returns the shared fit envelope plus fit result containers.
- `POST /analysis-operation`: runs SciPlot-owned numerical operations and returns `AnalysisOperationResultPayload`.
- `POST /import-preview`: dispatches import filters and returns a filter profile, available options, structure nodes, preview containers, and structured disabled diagnostics.
- `POST /plot-edit-command/normalize`: compatibility route for Plot-only object edit command normalization.
- `POST /command/normalize`: validates cross-module commands and returns a normalized reversible command with graph patch metadata.
- `POST /command/apply-preview`: applies a command against an in-memory graph snapshot and returns graph patch plus render invalidation metadata without saving project files; stale command revisions must be ignored with structured diagnostics.
- `POST /preview-scene`: returns the contract-gated native realtime preview scene for Swift Canvas before `/render-preview`; `/render-preview` remains the authoritative bitmap/PDF correction path.
- `POST /live-source/update-now`: refreshes enabled file-tail, folder-watch, or periodic-CSV live sources into revisioned data containers.
- `POST /code-console/run`: executes a Code Console run and returns generated files, notebook outputs, and notebook output containers.

## Next-Generation Runtime Payloads

- `DataContainerPayload` includes column ids, column mode/role/unit/comment/profile metadata, readonly policy, lifecycle event names, provenance, statistics, dimensions, and data revision.
- `ImportFilterProfilePayload` describes a filter's extensions, MIME types, dependency status, preview/read/write support, options schema, output container kinds, help, and test requirements. macOS consumes this payload instead of local format constants.
- `ImportDiagnosticPayload` carries structured status codes such as `encoding_detected`, `delimiter_detected`, `ragged_rows_detected`, `duplicate_headers_detected`, `dependency_missing`, and `policy_not_implemented`.
- `ImportOptionPayload` and `ImportStructureNodePayload` describe user-selectable import options and file/sheet/segment structure for Data Studio's import wizard.
- `AnalysisOperationResultPayload` includes settings, source binding, prepared-array summary, elapsed time, lineage, diagnostics, metrics, tables, overlays, artifact refs, and data containers.
- `PlotEditCommandPayload` is the shared command envelope for Plot, Data Studio, Composer, and Code Console. Supported kinds include `add`, `edit`, `delete`, `reorder`, `rename`, `visibility`, `lock`, `copy_settings`, `bind_source`, `apply_template`, `import_container`, and `create_output_ref`.
- `PreviewScenePayload` is a realtime approximation contract. It carries figure geometry, plot area geometry, axis metadata, series samples, style tokens, object ids, `bbox_pixels`, point arrays, payload refs, operation names, hit-test hints, budgets, and fallback diagnostics.
- `PreviewScenePayload.objects[]` is the Plot object hit-test contract. Object metadata must include stable id, kind, label, `bbox_pixels`, `points`, `payload_ref`, supported `operations`, and visible/locked state for series, axes, legend, reference guides, text annotations, shape annotations, function layers, and fit overlays.
- `LiveSourcePayload` is the controlled realtime-source contract for file tail, folder watch, and periodic CSV refresh. Network, serial, and socket sources stay disabled until sandbox and fixture policy exists.

## Plot Native Interaction Loop

- `POST /preview-scene` is requested before `POST /render-preview`. macOS may use a native Canvas path while the authoritative bitmap/PDF is loading, then keep the same scene metadata for hit testing and overlays after correction arrives.
- Native admission is explicit. Unsupported templates, missing samples, invalid axes, sample-budget overflow, enabled extra axes, and enabled broken axes must return `native_supported=false` with a structured fallback reason instead of asking Swift to guess.
- `POST /command/normalize` and `POST /command/apply-preview` are required for durable Plot edits, including series style/offset edits, guide/text/shape creation and drag edits, function layer edits, fit overlay changes, axis label/range edits, legend reorder, visibility, lock, rename, delete, and copy-settings.
- `POST /command/apply-preview` returns graph revision metadata and diagnostics only; it does not save project files. Stale command revisions must return a `stale_command_revision` diagnostic and no durable graph mutation.

## Status Policy

- `enabled`: the route or capability is currently implemented behind sidecar contracts and has tests.
- `disabled`: the capability is intentionally unavailable and must include visible help/diagnostics.
- Do not expose planning statuses such as `experimental` or `coming_soon` through `/meta`.

## Ownership

- Sidecar is authoritative for validation, transforms, analysis, import/export, project save/open, and project restore.
- macOS may cache decoded responses for UI state, but must not invent a second table of templates, styles, palettes, themes, or LabPlot-scale capability constants.
