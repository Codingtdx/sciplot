# LabPlot Roadmap Progress

This ledger records the durable implementation state for the LabPlot-informed SciPlot roadmap. The roadmap stays architectural; this file is the working memory for what has landed, what is active, and what must remain clean-room.

Last updated: 2026-05-17

## Current baseline

- Branch: `main`
- Baseline commit before Phase 3 work: `09db3e7 feat: add document graph and capability catalogs`
- Schema/catalog scaffolding commit: `142c088 feat: land labplot-scale capability scaffolding`
- Runtime landing commits: `2aac3c7 feat: add labplot runtime landing endpoints`, `ba9ef5b feat: bridge runtime payloads into macos and code console`
- Branch cleanup target: local merged branches `codex/gate-stabilization` and `codex/data-studio-template-stability`
- Clean-room rule: LabPlot GPL source is not vendored; SciPlot may use LabPlot behavior, public APIs, UX flows, and test inspiration only.

## One-run LabPlot-scale implementation batch

Status: landed in the `feat: land labplot-scale capability scaffolding` batch.

This batch converts the roadmap from planning-only text into schema/catalog/project landing code. The goal is schema/catalog/project landing for every LabPlot-inspired capability, with honest runtime status labels.

This batch extends the typed Data Containers preview foundation instead of replacing it: table, matrix, transformed view, fit result, statistics summary, and notebook output now share one explicit payload family.

| Capability area | Project landing | Runtime status | Follow-up validation |
| --- | --- | --- | --- |
| Data table containers | `/source-table-preview` readonly table payload | landed | UI wiring into Plot/Data Studio workbook views |
| Matrix containers | XYZ preview matrix payload and catalog entry | experimental | contour integration, missing-value policy tests, performance hardening |
| Transformed views | typed transform preview container | landed | variable diagnostics and project restore coverage |
| Statistics summaries | schema and catalog landing | experimental | numerical fixture coverage and workbook UI wiring |
| Fit result containers | `/fit-analysis` result container and analysis envelope | landed | shared result-table UI and export integration |
| Notebook outputs | schema, graph node, and catalog landing | experimental | Code Console artifact restore and Plot/Composer handoff tests |
| Plot objects | graph-addressable plot object payload and document graph nodes | landed | inspector selection and native preview hit-testing |
| Edit commands | typed command schema | experimental | native `UndoManager` command replay tests |
| Analysis operations | common result envelope and full operation catalog | experimental / coming_soon | numerical fixture coverage for each operation |
| Import filters | full filter catalog and typed filter payload | coming_soon / disabled | preview/options schemas and malformed-file fixtures |
| Export targets | full target catalog and typed target payload | landed / experimental / coming_soon | manifest roundtrip and Finder reveal checks |
| Code Console bridge | notebook output schema and graph nodes | experimental | UI wiring and embedded artifact restore |

The `coming_soon` and `disabled` entries are intentional: they are real project landing points, not claims of runtime support. Follow-up work must add numerical fixture coverage, UI wiring, and performance hardening before changing those statuses.

## Runtime landing batch

Status: landed as the first long-run execution batch after the scaffolding commit.

This batch moves the LabPlot-scale landing from "schema/catalog exists" to "sidecar runtime has typed entry points and macOS can decode/consume them." It still marks unfinished numerical and UX areas honestly as `experimental`, `coming_soon`, or `disabled`.

| Surface | Route or file | Status | Notes |
| --- | --- | --- | --- |
| Capability registry | `src/rendering/capability_registry.py`, `GET /meta` | landed | `/meta` now delegates LabPlot-scale catalogs to the SciPlot-owned registry module. |
| Data containers | `src/rendering/data_containers.py`, `POST /source-table-preview`, `POST /fit-analysis` | landed / experimental | Table containers are enabled; matrix, transformed, statistics, fit, and notebook containers have runtime helpers and typed payloads. |
| Analysis operations | `POST /analysis-operation`, `src/rendering/analysis_operations.py` | experimental | Smoothing, interpolation, differentiation, integration, FFT, Fourier filter, correlation/convolution, baseline, peak detection, KDE, statistical tests, distribution fitting, peak fitting, and growth models return one envelope. |
| Import preview | `POST /import-preview`, `src/rendering/import_filters.py` | enabled / experimental / coming_soon | CSV/Excel reuse source preview, JSON and explicit binary/raw are experimental, dependency-heavy formats return structured help. |
| Export manifests | `src/rendering/export_targets.py` | experimental | Manifest-backed artifact set helper is in place for figure/data/project outputs. |
| Plot edit commands | `POST /plot-edit-command/normalize`, `src/rendering/plot_object_commands.py` | experimental | Add/edit/delete/reorder/rename/visibility/lock commands normalize to reversible graph patches. |
| Code Console bridge | `POST /code-console/run` | experimental | Generated figures become notebook outputs; CSV/JSON generated tables become readonly notebook output containers. |
| macOS decode and minimal consumption | `SidecarModelsRender.swift`, `SidecarClient.swift`, module views | landed | Swift decodes all new payloads, calls the new runtime routes, and surfaces summaries without adding a fifth notebook module or global Project Explorer. |

Runtime verification anchors:

- `.venv/bin/python -m pytest tests/test_analysis_operations.py tests/test_import_export_registries.py tests/test_plot_object_commands.py tests/test_runtime_landing_surfaces.py tests/test_sidecar_code_console.py -q`
- `.venv/bin/python -m ruff check app/sidecar src tests/test_analysis_operations.py tests/test_import_export_registries.py tests/test_plot_object_commands.py tests/test_runtime_landing_surfaces.py tests/test_sidecar_code_console.py`
- `xcodebuild test -project app/macos/SciPlot.xcodeproj -scheme SciPlotMac -destination 'platform=macOS' -only-testing:SciPlotMacTests/SchemaDecodingTests`

## Phase status

### Phase 0: Checkpoint and guardrails

Status: landed

- Baseline checkpoint and roadmap commits are in `main`.
- `scripts/check_labplot_cleanroom.py` remains the executable guardrail.
- The blocking gate includes the LabPlot clean-room check.
- Verification anchor: `.venv/bin/python scripts/check_labplot_cleanroom.py`

### Phase 1: SciPlotDocumentGraph

Status: landed

- `ProjectBundlePayload.document_graph` is present in the project bundle schema.
- `.sciplot` save/open paths can preserve or generate document graph payloads.
- The graph is internal persistence and command-model foundation, not a global Project Explorer UI.
- Verification anchor: `.venv/bin/python -m pytest tests/test_project_bundle_graph.py -q`

### Phase 2: Capability catalogs

Status: landed

- `/meta` exposes capability catalog groups for data containers, plot objects, analysis operations, import filters, export targets, project bundle features, and native preview features.
- macOS can decode the catalog payload without keeping a second capability table.
- `src/plot_contract.json` remains the truth source for templates, styles, palettes, themes, and defaults.
- Verification anchor: `.venv/bin/python -m pytest tests/test_sidecar_schema_contract.py tests/test_plot_contract.py -q`

### Phase 3: Data containers

Status: in progress (runtime foundation landed, hardening continues)

- Active slice: one-run LabPlot-scale runtime landing.
- V1 implementation target: readonly `table`, experimental `matrix`, `transformed_view`, `statistics_summary`, `fit_result`, and `notebook_output` containers generated through sidecar helpers.
- Shared consumers: Plot Data Workbook, Data Studio Analysis, and Code Console Outputs can decode or display the same sidecar container payloads.
- Out of scope for runtime enablement: inline editing, unverified statistics sheets, unverified deep analysis operations, and unverified notebook output handoff.
- Verification anchor: `.venv/bin/python -m pytest tests/test_sidecar_render.py::test_source_table_preview_returns_readonly_table_container -q`

### Phase 4: Plot object commands

Status: command normalization foundation landed

- Plot objects remain graph-addressable typed payloads rather than a restored global Project Explorer.
- `POST /plot-edit-command/normalize` validates add/edit/delete/reorder/rename/visibility/lock commands and returns reversible graph patches.
- macOS `SidecarClient` can call the normalizer; full module-session `UndoManager` replay remains the next hardening task.
- Verification anchor: `.venv/bin/python -m pytest tests/test_plot_object_commands.py -q`

### Phase 5: Analysis engine expansion

Status: experimental runtime landed

- `POST /analysis-operation` returns `AnalysisOperationResultPayload` for the first broad operation set.
- Implemented operations use SciPlot-owned NumPy/SciPy code, not LabPlot/NSL source.
- Operations remain `experimental` until numerical fixture coverage, UI parameter editors, performance limits, and export overlays are hardened.
- Verification anchor: `.venv/bin/python -m pytest tests/test_analysis_operations.py -q`

### Phase 6: Import/export filters

Status: registry and first runtimes landed

- `POST /import-preview` dispatches through the import registry.
- CSV/Excel reuse the existing source table preview engine; JSON records and explicit binary/raw matrix preview are experimental.
- HDF5, NetCDF, FITS, ODS, ReadStat, SQL, Origin/SciDAVis evaluation, and image digitizer remain `coming_soon` or `disabled` with help.
- Export target work has a manifest-backed helper; full route-level export targets remain a later slice.
- Verification anchor: `.venv/bin/python -m pytest tests/test_import_export_registries.py -q`

### Phase 7: Code Console notebook bridge

Status: experimental runtime landed

- `CodeConsoleRunResponse` now carries `notebook_outputs` and `data_containers`.
- Latest run PDF/PNG/JPEG/TIFF artifacts become figure outputs; CSV/JSON artifacts become readonly notebook output containers.
- `.sciplot` graph-level restore of those artifacts still needs more project bundle tests before this becomes enabled UI.
- Verification anchor: `.venv/bin/python -m pytest tests/test_sidecar_code_console.py -q`

## Backlog notes

- `data.matrix` is experimental after the one-run batch; it still needs contour integration tests before becoming enabled.
- `data.transformed_view` should reuse `render_options.data_variables` and `render_options.data_transforms`; no Swift expression executor is allowed.
- `data.fit_result` now has the common analysis result envelope landing; downstream UI/export wiring remains.
- Code Console generated tables and figures have `data.notebook_output` runtime output landing; context binding and project restore still need validation.
- Analysis operations need fixture expansion from smoke coverage to reference numerical datasets before any operation status changes from `experimental` to `enabled`.
- Import filters for HDF5/NetCDF/FITS/ODS/ReadStat need dependency decisions, malformed-file fixtures, and explicit options schemas before runtime enablement.
- Plot edit commands need native `UndoManager` replay tests that prove before/after payloads are the durable state, not inspector-local state.

## Required verification before claiming progress

- `git status --short --branch`
- `.venv/bin/python scripts/check_labplot_cleanroom.py`
- `.venv/bin/python -m pytest tests/test_labplot_cleanroom_roadmap.py -q`
- `.venv/bin/python -m pytest tests/test_analysis_operations.py tests/test_import_export_registries.py tests/test_plot_object_commands.py -q`
- Phase-specific backend tests for the active slice
- Swift schema decoding tests when response payloads change
