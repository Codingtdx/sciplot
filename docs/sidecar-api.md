# Sidecar API Surface

This document records public sidecar routes that macOS may call directly. Every route returns an explicit response model from `app/sidecar/schemas_*.py`; do not add naked dict routes.

## LabPlot-Scale Runtime Routes

- `GET /meta`: returns plot contract metadata plus capability catalogs. Catalog statuses are only `enabled` or `disabled`; disabled entries must include help text.
- `POST /source-table-preview`: previews raw or transformed source tables and returns shared `DataContainerPayload` values.
- `POST /fit-analysis`: runs fit analysis and returns the shared fit envelope plus fit result containers.
- `POST /analysis-operation`: runs SciPlot-owned numerical operations and returns `AnalysisOperationResultPayload`.
- `POST /import-preview`: dispatches import filters and returns preview containers or structured disabled diagnostics.
- `POST /plot-edit-command/normalize`: validates plot object edit commands and returns a normalized reversible command with graph patch metadata.
- `POST /code-console/run`: executes a Code Console run and returns generated files, notebook outputs, and notebook output containers.

## Status Policy

- `enabled`: the route or capability is currently implemented behind sidecar contracts and has tests.
- `disabled`: the capability is intentionally unavailable and must include visible help/diagnostics.
- Do not expose planning statuses such as `experimental` or `coming_soon` through `/meta`.

## Ownership

- Sidecar is authoritative for validation, transforms, analysis, import/export, project save/open, and project restore.
- macOS may cache decoded responses for UI state, but must not invent a second table of templates, styles, palettes, themes, or LabPlot-scale capability constants.
