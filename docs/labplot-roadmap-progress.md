# LabPlot Roadmap Progress

This ledger records the durable implementation state for the LabPlot-informed SciPlot roadmap. The roadmap stays architectural; this file is the working memory for what has landed, what is active, and what must remain clean-room.

Last updated: 2026-05-17

## Current baseline

- Branch: `main`
- Baseline commit before Phase 3 work: `09db3e7 feat: add document graph and capability catalogs`
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

Status: in progress

- Active slice: one-run LabPlot-scale schema/catalog/project landing.
- V1 implementation target: readonly `table`, experimental `matrix`, `transformed_view`, and `fit_result` containers generated through existing sidecar routes.
- Shared consumers: Plot Data Workbook and Data Studio can consume the same sidecar container payload after UI wiring.
- Out of scope for runtime enablement: inline editing, unverified statistics sheets, unverified deep analysis operations, and unverified notebook output handoff.
- Verification anchor: `.venv/bin/python -m pytest tests/test_sidecar_render.py::test_source_table_preview_returns_readonly_table_container -q`

## Backlog notes

- `data.matrix` is experimental after the one-run batch; it still needs contour integration tests before becoming enabled.
- `data.transformed_view` should reuse `render_options.data_variables` and `render_options.data_transforms`; no Swift expression executor is allowed.
- `data.fit_result` now has the common analysis result envelope landing; downstream UI/export wiring remains.
- Code Console generated tables and figures have `data.notebook_output` schema/graph landing; context binding and project restore still need validation.

## Required verification before claiming progress

- `git status --short --branch`
- `.venv/bin/python scripts/check_labplot_cleanroom.py`
- `.venv/bin/python -m pytest tests/test_labplot_cleanroom_roadmap.py -q`
- Phase-specific backend tests for the active slice
- Swift schema decoding tests when response payloads change
