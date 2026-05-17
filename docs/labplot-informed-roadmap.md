# LabPlot-Informed SciPlot Desktop Roadmap

This roadmap turns LabPlot research into SciPlot architecture work while preserving SciPlot's Apache-2.0 licensing and current desktop product model.

LabPlot is a strategic reference, not a vendored dependency. Its public behavior, SDK concepts, documentation, and user-facing workflows can guide SciPlot, but GPL-2.0-or-later source files from LabPlot must not be copied into this repository. New SciPlot behavior should be implemented clean-room in the existing Python sidecar, SwiftUI macOS app, and contract-backed rendering stack.

Persistent phase status is tracked in `docs/labplot-roadmap-progress.md`; this roadmap remains the long-term capability map.

Current implementation note: the one-run LabPlot-scale batch is moving every major capability into project structure as typed schema, `/meta` catalog entries, document graph nodes, macOS decode models, and progress documentation. Runtime support is still represented honestly with `landed`, `experimental`, `coming_soon`, or `disabled` status labels.

## Technical borrowing principles

This is not blind copying. The goal is to understand why LabPlot's mature C++/Qt codebase stays coherent under many data containers, plot objects, import filters, and analysis operations, then translate those principles into SciPlot's first-principles architecture.

The working rule is:

- Copy the problem framing: stable project objects, explicit ownership, undoable edits, structured import/filter status, common analysis result envelopes, and fixture-heavy numerical tests.
- Do not copy the implementation: no GPL C++ bodies, no Qt object model, no global LabPlot-style Project Explorer, and no NSL source port.
- Preserve SciPlot's product logic: sidecar authority, contract-backed payloads, SwiftUI native desktop windows, `.sciplot` project bundles, and the Launcher plus four singleton module windows.
- Prefer designs that make SciPlot better than a direct clone: stable public string ids instead of raw internal enum exposure, typed JSON schemas instead of hidden GUI constants, Python scientific libraries behind safe contracts instead of vendored GPL numerical code, and native `UndoManager` integration instead of importing LabPlot's command framework.

The code-level notes live in the LabPlot code study: `docs/labplot-technical-borrowing.md`.

## Clean-room policy

- SciPlot remains Apache-2.0 unless maintainers make an explicit future relicensing decision.
- LabPlot GPL source may be read for orientation, but implementation must be authored as SciPlot-native code.
- The executable guard for this boundary is `scripts/check_labplot_cleanroom.py`; the blocking gate runs it as `labplot_cleanroom`.
- Acceptable borrowing: feature taxonomy, UX principles, public behavior descriptions, test ideas, data-flow shapes, and architecture patterns.
- Not acceptable: copied LabPlot C/C++/Qt headers, implementation bodies, embedded GPL source modules, or static/dynamic linking to LabPlot core without a separate licensing decision.

## SciPlotDocumentGraph

LabPlot's project/aspect tree maps to a future module-scoped document graph, tentatively named `SciPlotDocumentGraph`.

The graph is not a global Project Explorer and must not restore a shared workbench shell. It is an internal persistence and command model stored through the existing `.sciplot` save/open schema path. Each product window owns its visible workflow, while the graph provides stable identities, dependencies, undoable edits, and project roundtripping.

Initial graph node families:

| LabPlot reference | SciPlot graph family | Owning module |
| --- | --- | --- |
| Spreadsheet/Matrix | Typed table, matrix, transformed view, variables, fit results | Data Studio and Plot Data Workbook |
| Worksheet/CartesianPlot | Plot scene, figure page, plot area, composer panel | Plot and Composer |
| Axis/Legend/XYCurve | Contract-backed plot objects and render options | Plot |
| Analysis curves/NSL | Fit, smooth, FFT, statistics, transforms | Sidecar services surfaced in Plot/Data Studio |
| Import filters | Source preview/import capability registry | Sidecar `/meta` and import routes |

## Contract and capability catalogs

All public capability expansion should continue the current contract pattern.

- Plot templates, styles, palettes, themes, defaults, editable options, gallery metadata, and smoke surface stay rooted in `src/plot_contract.json`.
- Runtime capability catalogs for data containers, plot objects, analysis operations, and import filters should be exposed through `/meta` or other explicit typed endpoints, not local macOS constants.
- Render/data extensions must use typed payloads like the existing `reference_guides`, `shape_annotations`, `data_transforms`, `fit-analysis`, analytical layers, axis breaks, and project bundle payloads.
- Unsupported capabilities should be disabled with help text in macOS and rejected with explicit sidecar validation errors in backend paths.

## Command and undo architecture

Large-app behavior should be command-oriented without importing LabPlot's Qt command framework.

- macOS emits typed edit commands for user intent: add object, bind data, edit axis, edit series style, reorder legend, create transform, place annotation, and update analysis settings.
- Sidecar validates and normalizes payloads before preview/export/project save uses them.
- Swift `UndoManager` stores reversible edits at the module session level, using the same typed payloads that sidecar accepts.
- Async refresh keeps the existing latest-write-wins pattern through `AsyncLatestTaskCoordinator` and `KeyedAsyncLatestTaskCoordinator`.
- Backend remains authoritative for data transforms, fit/function evaluation, validation, final export, and project restore.

## Desktop product boundary

SciPlot should grow into a large desktop plotting application without copying LabPlot's global shell.

- Preserve the Launcher plus four singleton module windows: Plot, Data Studio, Composer, and Code Console.
- Keep `Command-1/2/3/4` opening or focusing the corresponding module window.
- Do not introduce a global Project Explorer, shared left rail, or Start/Home/Project workspace as a primary product area.
- Module-local object lists are allowed only when they represent real current work: workbook groups in Data Studio, plot source/type selection in Plot, panels in Composer, and bindings/outputs in Code Console.
- Project save/open continues through `.sciplot` bundles and sidecar schema migration.

## Master implementation phases

### Phase 0: Checkpoint and guardrails

Status: started.

- Keep the baseline checkpoint commit before large LabPlot-inspired changes.
- Keep `scripts/check_labplot_cleanroom.py` in the blocking gate.
- Keep this roadmap and the LabPlot code study as the long-term entry point for future contributors.
- Add tests that fail if the roadmap forgets the clean-room rule or drops the code-level translation record.
- Never vendor LabPlot GPL sources, headers, NSL modules, Qt commands, or copied snippets.

Acceptance:

- `labplot_cleanroom` runs in `scripts/blocking_gate.py`.
- A copied LabPlot-style GPL header fixture fails the guard.
- This roadmap names the allowed and forbidden borrowing rules.

### Phase 1: SciPlotDocumentGraph

Goal: introduce the internal object model LabPlot proves is necessary, without exposing a global Project Explorer.

Initial graph payload:

- `schema_version`
- `nodes`
- `edges`
- `capabilities`
- `selected_nodes`
- `module_roots`
- `migration_notes`

Initial node families:

- Plot: source, table binding, scene, series, axis, legend, guide, annotation, function layer, extra axis, broken axis, fit overlay.
- Data Studio: workbook, workbook group, source file, template, normalized table, matrix, compare figure, specimen filter state.
- Composer: document, page, panel, embedded figure, asset, export artifact.
- Code Console: context binding, run, generated table, generated figure, output artifact.

Implementation rules:

- Persist through `ProjectBundlePayload.document_graph?: DocumentGraphPayload`.
- Generate graph snapshots during save/open migration when older projects do not yet contain one.
- Use stable public string ids and typed node payloads; never expose raw enum ordinals.
- Keep graph invisible in v1 UI except where module-local selection already exists.

Tests:

- Save/open roundtrip preserves graph nodes for Plot, Data Studio, Composer, and Code Console.
- Migration creates deterministic graph ids for existing project bundles.
- Missing or unknown node kinds produce typed migration warnings, not crashes.

### Phase 2: Capability catalogs

Goal: stop macOS from guessing what the backend supports.

Catalog groups:

- `data_containers`
- `plot_objects`
- `analysis_operations`
- `import_filters`
- `export_targets`
- `project_bundle_features`
- `native_preview_features`

Payload shape:

- `id`
- `label`
- `status`
- `owner`
- `surface`
- `typed_payload_schema`
- `help`
- `introduced_in`
- `test_requirements`

Implementation rules:

- `/meta` includes capability catalogs after schema version negotiation.
- macOS decodes catalog entries and uses `disabled + help` for unsupported entries.
- `src/plot_contract.json` remains the truth source for plot templates, styles, palettes, themes, gallery metadata, and default options.
- Sidecar routes remain authoritative for validation and must return explicit response models.

Tests:

- `/meta` returns every catalog group.
- macOS decoding accepts known statuses and safely ignores unknown future entries.
- No macOS file keeps a second hardcoded capability table for these groups.

### Phase 3: Data containers

Goal: make Spreadsheet/Matrix ideas SciPlot-native.

Container backlog:

- `data.table`: columns, roles, units, comments, profiles, statistics, source provenance.
- `data.matrix`: dimensions, scalar field metadata, coordinate vectors, units, missing-value policy.
- `data.transformed_view`: variables, transform chain, source hash, diagnostics.
- `data.fit_result`: model, parameters, errors/covariance, residuals, metrics, overlay binding.
- `data.notebook_output`: generated figures and tables from Code Console.

Implementation rules:

- Plot Data Workbook and Data Studio consume the same sidecar container payloads.
- v1 remains read-only in macOS; no inline cell editor until container mutations are command-backed.
- Transform previews use the existing typed `data_variables` and `data_transforms` route pattern.
- Statistics summaries are generated in sidecar, not Swift.

Tests:

- Source preview and transformed preview preserve column roles, units, and diagnostics.
- Matrix preview can feed `contour_field` without a macOS-side template guess.
- Variable/statistics sheets roundtrip through project save/open.

### Phase 4: Plot object model

Goal: make every durable plot object graph-addressable.

Object backlog:

- Series
- Axis
- Legend
- Reference guide line/region
- Text annotation
- Shape annotation
- Function layer
- Extra axis
- Broken axis
- Fit overlay
- Plot area/page

Implementation rules:

- Object selection routes the right inspector category in Plot.
- Edits write typed render payloads already accepted by sidecar, or newly added typed payloads.
- No inspector-only state for durable scientific options.
- Native preview hit-testing can select graph objects only when metadata exists.
- Unsupported object features stay cataloged as disabled with help.

Tests:

- Object create/edit/delete/reorder/rename/visibility/lock commands roundtrip.
- Undo/redo restores typed payloads and preview revision.
- Project restore lands on the same selected object where supported.

### Phase 5: Analysis engine expansion

Goal: add LabPlot-scale analysis through SciPlot-owned implementations.

Operation backlog:

- Smoothing
- Interpolation
- Differentiation
- Integration
- FFT
- Fourier filter
- Correlation/convolution
- Baseline correction
- Peak detection
- KDE
- Statistical tests
- Distribution fitting
- Peak fitting
- Growth models
- Data reduction and line simplification

Implementation rules:

- Every operation uses the common operation result envelope described in the code study.
- Expression-based operations reuse `src/rendering/expression_engine.py`.
- No free-form LabPlot/DataGraph command interpreter.
- SciPy/NumPy/statsmodels may be used behind sidecar contracts when license-compatible and testable.
- Result tables, residuals, transformed columns, and overlay payloads share one backend result.

Tests:

- Numerical fixtures with tolerances for each operation family.
- Fit expansion uses NIST-style reference checks before new UI exposure.
- Render/export integration confirms overlays and result tables use the same backend output.

### Phase 6: Import and export filters

Goal: turn file IO into a registry of explicit filters and targets.

Import backlog:

- CSV/TSV/TXT
- Excel
- JSON
- SQL
- HDF5
- NetCDF
- FITS
- ODS
- ReadStat-backed SAS/Stata/SPSS
- binary/raw
- Origin/SciDAVis-style project import evaluation
- image digitizer backlog

Export backlog:

- Figure PDF/TIFF
- Data worksheet/workbook
- Project bundle
- Comparison bundle
- Manifest-driven artifact set
- Code Console generated figure set

Implementation rules:

- Every import filter has preview, options schema, output container kind, warnings, and typed errors.
- Every export target declares allowed module, artifact kind, filename policy, and post-export metadata.
- Import failure messages are structured and visible, not generic tracebacks.

Tests:

- Malformed delimiter/header/encoding/ragged-row fixtures.
- Export manifest roundtrip and Finder reveal metadata.
- Project bundle import never depends on original absolute paths.

### Phase 7: Code Console and notebook bridge

Goal: map LabPlot notebook/CAS inspiration into the existing Code Console module.

Implementation rules:

- Keep Code Console as one of the four supported modules, not a fifth notebook product.
- Python-first runs use `POST /code-console/context` and `POST /code-console/run`.
- Generated figures and tables become graph nodes that can flow back to Plot or Composer.
- R/Julia/Maxima/Octave remain backlog until there is a verified runtime and project restore story.

Tests:

- Context id stability across mtime/signature changes.
- Generated figure/table outputs roundtrip in `.sciplot`.
- Plot/Composer handoff uses embedded project artifacts, not absolute temp paths.

### Phase 8: Large desktop UX polish

Goal: make the mature backend feel native and simple.

Implementation rules:

- Preserve Launcher plus four singleton module windows.
- Strengthen module-local object browsers only where they reflect real current work.
- Keep toolbar/menu parity and focused-module command routing.
- Keep Quick Help short and action-oriented.
- Keep Project Explorer concepts internal; do not restore the LabPlot global workbench shell.

Tests:

- `Command-1/2/3/4` focuses singleton module windows.
- Launcher remains the only entry surface and carries no module primary actions.
- No shared left rail or global Project Explorer UI returns.

## Capability backlog matrix

| Area | Current anchor | Backlog items | First engineering slice |
| --- | --- | --- | --- |
| Project model | `.sciplot`, sidecar save/open schemas | Graph nodes, graph edges, migrations, selected node state | Add optional `document_graph` payload and roundtrip tests |
| Commands | macOS `UndoManager`, typed payload edits | Command ledger, compound commands, command replay tests | Axis/guide/annotation edit commands |
| Data containers | `/source-table-preview`, `data_transforms` | Table, matrix, transformed view, statistics, fit result | Shared table/matrix profile schema |
| Plot objects | `render_options` typed payloads | Series, axis, legend, guide, annotation, function, advanced axes | Graph-addressed object ids in render options |
| Analysis | `/fit-analysis`, expression engine | Smooth, FFT, KDE, baseline, peak, statistical tests | Common operation result envelope |
| Import filters | inspect/source preview routes | CSV, Excel, JSON, HDF5, NetCDF, FITS, ReadStat, binary/raw | Import filter catalog in `/meta` |
| Export targets | preview/export/project bundle | Figure/data/project/comparison/artifact manifests | Export target catalog in `/meta` |
| Native preview | current backend bitmap/PDF preview | Contract-gated curve hit-testing and object selection | Feature catalog for native preview eligibility |

## Interface additions

Future payload names are intentionally explicit so schema work has a fixed target:

- `ProjectBundlePayload.document_graph?: DocumentGraphPayload`
- `DocumentGraphPayload.schema_version`
- `DocumentGraphPayload.nodes`
- `DocumentGraphPayload.edges`
- `DocumentGraphPayload.capabilities`
- `DocumentGraphNodePayload.id`
- `DocumentGraphNodePayload.kind`
- `DocumentGraphNodePayload.module`
- `DocumentGraphNodePayload.label`
- `DocumentGraphNodePayload.status`
- `DocumentGraphNodePayload.payload`
- `DocumentGraphEdgePayload.source`
- `DocumentGraphEdgePayload.target`
- `DocumentGraphEdgePayload.relationship`
- `CapabilityCatalogPayload.groups`
- `AnalysisOperationResultPayload.available`
- `AnalysisOperationResultPayload.valid`
- `AnalysisOperationResultPayload.status_code`
- `AnalysisOperationResultPayload.message`
- `AnalysisOperationResultPayload.diagnostics`

Existing routes remain authoritative:

- `POST /inspect-file`
- `POST /source-table-preview`
- `POST /fit-analysis`
- `POST /render-preview`
- `POST /save-project`
- `POST /open-project`
- `GET /meta`
- `GET /plot-contract`

## Engineering acceptance gates

- Clean-room: copied LabPlot GPL header fixture fails.
- Schema: project graph roundtrip passes for all four modules.
- Catalog: `/meta` returns capability catalogs and macOS decodes them.
- Commands: undo/redo tests cover plot objects, transforms, series styles, axes, guides, annotations, and function layers.
- Numerical: analysis operations have fixture tests before UI exposure.
- Import: filters expose preview/options/status and malformed-file fixtures.
- Export: project and artifact outputs are manifest-backed and restorable.
- UX: Launcher/four-window guardrails stay intact; no global Project Explorer or shared workbench shell returns.

## References

- LabPlot repository: https://github.com/KDE/labplot
- KDE Invent main repository: https://invent.kde.org/education/labplot
- LabPlot feature overview: https://docs.labplot.org/en/getting_started/features.html
- LabPlot Project Explorer: https://docs.labplot.org/en/interface/interface_project_explorer.html
- LabPlot AbstractAspect SDK concept: https://docs.labplot.org/en/sdk/python/api/abstract_classes/AbstractAspect.html
- LabPlot Spreadsheet concept: https://docs.labplot.org/en/data_containers/data_containers_spreadsheet.html
- LabPlot license metadata: https://github.com/KDE/labplot/blob/master/.reuse/dep5
