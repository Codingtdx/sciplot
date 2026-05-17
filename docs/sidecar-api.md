# Sidecar API Surface

This document records public sidecar routes that macOS may call directly. Every route returns an explicit response model from `app/sidecar/schemas_*.py`; do not add naked dict routes.

## LabPlot-Scale Runtime Routes

- `GET /meta`: returns plot contract metadata plus capability catalogs. Catalog statuses are only `enabled` or `disabled`; disabled entries must include help text.
- `POST /source-table-preview`: previews raw or transformed source tables and returns shared `DataContainerPayload` values.
- `POST /fit-analysis`: runs fit analysis and returns the shared fit envelope plus fit result containers.
- `POST /analysis-operation`: runs SciPlot-owned numerical operations and returns `AnalysisOperationResultPayload`.
- `POST /import-preview`: dispatches import filters and returns preview containers or structured disabled diagnostics.
- `POST /plot-edit-command/normalize`: compatibility route for Plot-only object edit command normalization.
- `POST /command/normalize`: validates cross-module commands and returns a normalized reversible command with graph patch metadata.
- `POST /command/apply-preview`: applies a command against an in-memory graph snapshot and returns graph patch plus render invalidation metadata without saving project files.
- `POST /preview-scene`: returns the contract-gated native realtime preview scene for Swift Canvas; `/render-preview` remains the authoritative bitmap/PDF correction path.
- `POST /live-source/update-now`: refreshes enabled file-tail, folder-watch, or periodic-CSV live sources into revisioned data containers.
- `POST /code-console/run`: executes a Code Console run and returns generated files, notebook outputs, and notebook output containers.

## Next-Generation Runtime Payloads

- `DataContainerPayload` includes column ids, column mode/role/unit/comment/profile metadata, readonly policy, lifecycle event names, provenance, statistics, dimensions, and data revision.
- `AnalysisOperationResultPayload` includes settings, source binding, prepared-array summary, elapsed time, lineage, diagnostics, metrics, tables, overlays, artifact refs, and data containers.
- `PlotEditCommandPayload` is the shared command envelope for Plot, Data Studio, Composer, and Code Console. Supported kinds include `add`, `edit`, `delete`, `reorder`, `rename`, `visibility`, `lock`, `copy_settings`, `bind_source`, `apply_template`, `import_container`, and `create_output_ref`.
- `PreviewScenePayload` is a realtime approximation contract. It carries plot area geometry, axis metadata, series samples, style tokens, object ids, hit-test hints, budgets, and fallback diagnostics.
- `LiveSourcePayload` is the controlled realtime-source contract for file tail, folder watch, and periodic CSV refresh. Network, serial, and socket sources stay disabled until sandbox and fixture policy exists.

## Status Policy

- `enabled`: the route or capability is currently implemented behind sidecar contracts and has tests.
- `disabled`: the capability is intentionally unavailable and must include visible help/diagnostics.
- Do not expose planning statuses such as `experimental` or `coming_soon` through `/meta`.

## Ownership

- Sidecar is authoritative for validation, transforms, analysis, import/export, project save/open, and project restore.
- macOS may cache decoded responses for UI state, but must not invent a second table of templates, styles, palettes, themes, or LabPlot-scale capability constants.
