# LabPlot Technical Borrowing Study

This document records the code-level lessons SciPlot should take from LabPlot without copying LabPlot GPL implementation code. It is a clean-room engineering translation guide, not a porting plan.

Studied reference checkout: `KDE/labplot` at `4fe3311` on 2026-05-16, read outside this repository at `/tmp/labplot-readonly`.

No LabPlot C++ implementation is vendored, copied, linked, or rewritten line-by-line in SciPlot. Class names and file names below are references for architecture discussion only.

## Core finding

LabPlot feels more mature because its backend has a strong object discipline:

- Project items are explicit objects with identity, ownership, children, visibility, selection, and status.
- User edits flow through command objects that know how to undo, redo, emit model events, and transfer ownership safely.
- Import filters are explicit capability objects with typed file families, import modes, warnings, progress, and structured failure status.
- Analysis curves share a common source binding, data preparation, result status, recalculation, and output-column lifecycle.
- Numerical correctness is protected with fixture-driven numerical tests, including NIST fit fixtures.

SciPlot translation: keep the macOS app native and simpler on the surface, but make the backend contract and document model more explicit underneath. The user should not feel a random pile of panels; every visible thing should map to a stable graph object, typed payload, reversible command, or sidecar capability.

Current SciPlot implementation note: the first next-generation foundation is now product code, not only guidance. The sidecar exposes `/command/normalize`, `/command/apply-preview`, and `/preview-scene`; data containers carry column semantics and data revisions; analysis envelopes carry source binding, settings, lineage, and elapsed time; `/meta` includes command, native preview, and live source capability groups. Future work should deepen those surfaces rather than adding parallel UI-local state.

## Source map

| LabPlot source area | What was inspected | SciPlot translation |
| --- | --- | --- |
| `src/backend/core/AbstractAspect.h` and `.cpp` | `AbstractAspect`, `AspectType`, child ownership, unique naming, selection/status/hidden signals | `SciPlotDocumentGraph` nodes with stable ids, typed node kinds, parent/child edges, status, selection, visibility, and deterministic unique-name generation |
| `src/backend/core/aspectcommands.h` | `aspectcommands` for add, remove, move, reparent, rename | A typed command ledger that macOS can undo through `UndoManager` while sidecar validates and normalizes payloads |
| `src/backend/datasources/filters/AbstractFileFilter.h` | `AbstractFileFilter`, file types, import mode, preview/read/write shape, warnings, progress | Sidecar import filter registry with preview, options schema, status codes, warnings, and typed source containers |
| `src/backend/datasources/filters/FilterStatus.h` | `FilterStatus` error categories for delimiter/header/column/encoding failures | Structured import diagnostics surfaced through `/source-table-preview`, Data Studio template preview, and future import catalog metadata |
| `src/backend/worksheet/plots/cartesian/XYAnalysisCurve.h` and `XYAnalysisCurvePrivate.h` | `XYAnalysisCurve`, common `Result`, source binding, `recalculateSpecific`, reset and temporary column lifecycle | Analysis operation framework with an operation result envelope, source binding, diagnostics, output columns, elapsed time, and project-restorable settings |
| `src/backend/worksheet/plots/cartesian/CartesianPlot.h` | Plot object graph, ranges, breaks, legends, cursor/navigation/edit modes | Graph-addressable plot scene objects behind SciPlot's Plot inspector and preview payloads |
| `src/backend/worksheet/plots/cartesian/Axis.h` | Axis object depth: range, ticks, labels, grids, custom label columns, style state | First-class axis objects with typed style/data-link payloads instead of scattered inspector-only state |
| `tests/analysis/fit/FitTest.cpp` | `FitTest`, NIST datasets, exact parameter/statistic checks and tolerances | Fixture-driven numerical tests for SciPlot fit, smooth, FFT, statistics, transforms, and import/export edge cases |

## What to learn, not copy

LabPlot's `AbstractAspect` tree is valuable because it gives every project thing a place in the model. SciPlot should not restore a global Project Explorer UI, but it does need the same internal seriousness: a Plot series, axis, legend, guide, function layer, Data Studio workbook, Composer panel, and Code Console run should have graph identity and lifecycle.

LabPlot's internal `AspectType` enum is useful for in-process routing, but SciPlot should not expose raw enum ordinals. Public and persisted SciPlot graph nodes should use versioned string ids such as `plot.axis`, `plot.series`, `data.table`, `analysis.fit`, and `code.run.output`.

LabPlot's signal fan-out shows why large apps remain synchronized: child objects announce changes upward. SciPlot's equivalent should be sidecar-normalized graph snapshots plus module-local event streams or revision tokens. macOS views should subscribe to state, not rediscover object relationships by string-matching local UI fields.

## Command and undo translation

LabPlot's `aspectcommands` are a reminder that undo is not a button bolted on after the fact. Add, remove, move, rename, reparent, and property edits are model operations.

SciPlot should introduce a typed command ledger with these properties:

- `command_id`, `target_node_id`, `kind`, `payload`, `before`, `after`, `created_at`, and `source_module`.
- Sidecar validation before the command mutates project state or preview state.
- Native `UndoManager` registration in macOS using the same typed command envelope.
- Revision gates so async preview refresh cannot resurrect a command that was undone.
- Compound commands for multi-object edits such as paste settings, reorder legend entries, apply template defaults, or import a workbook and bind its first figure.

This gives SciPlot the LabPlot-level reliability while keeping our Swift/Python architecture.

## Import/filter translation

LabPlot's `AbstractFileFilter` and `FilterStatus` show that importing is a product surface, not just `pandas.read_*` wrapped in a try/except.

SciPlot import filters should become cataloged capabilities:

- `id`, `label`, `status`, `source_extensions`, `source_mime_types`, `preview_supported`, `write_supported`, `options_schema`, `output_container_kinds`, and `help`.
- A preview method that returns detected encoding, delimiter, header rows, units, segments, column profiles, warnings, and typed error codes.
- A read method that produces a typed table, matrix, workbook, image source, or project import candidate.
- A write/export method only where we can test roundtrip behavior.

The first implementation should keep current CSV/Excel/JSON behavior, but shape it as registry entries so HDF5, NetCDF, FITS, ODS, SQL, ReadStat formats, binary/raw, image digitizer, and Origin/SciDAVis-style project import can be added without changing macOS constants.

## Analysis translation

LabPlot's `XYAnalysisCurve` hierarchy is the most useful bottom-code lesson. The specific NSL algorithms are GPL-covered and should not be copied, but the operation shape is excellent.

SciPlot should define an analysis operation framework:

- Common request: `operation_id`, `source_binding`, `range`, `parameters`, `output_policy`, `enabled`.
- Common operation result envelope: `available`, `valid`, `status_code`, `message`, `warnings`, `elapsed_ms`, `source_points`, `output_points`, `diagnostics`, and optional `artifact_refs`.
- Common data outputs: fitted/smoothed/transformed x/y columns, residual/rough columns, parameter tables, statistics tables, and render overlay payloads.
- Common lifecycle: validate source columns, prepare clean numeric arrays, run the SciPlot-owned implementation, attach output containers, update graph nodes, and trigger preview/export refresh.

`recalculateSpecific` is the idea to translate: each operation owns its math, but validation, source binding, result status, and output storage are common. In SciPlot this should live under `src/rendering` or a sibling analysis service using NumPy/SciPy/statsmodels where appropriate, never a free command interpreter.

## Plot object translation

LabPlot has deep `CartesianPlot`, `Axis`, legend, and curve objects. SciPlot already has typed render payloads for guides, annotations, analytical layers, axis breaks, extra axes, transforms, and fit analysis. The missing piece is stable object identity.

The next SciPlot plot model should make these graph-addressable:

- `plot.scene`
- `plot.series`
- `plot.axis.x`
- `plot.axis.y`
- `plot.legend`
- `plot.guide.line`
- `plot.guide.region`
- `plot.annotation.text`
- `plot.annotation.shape`
- `plot.layer.function`
- `plot.axis.break`
- `plot.axis.extra`

This is what makes selection, inspector routing, copy settings, lock/visibility, reorder, undo/redo, project restore, and future native hit-testing feel solid. The macOS UI can stay cleaner than LabPlot, but the backend object model needs comparable depth.

## Data container translation

LabPlot's Spreadsheet/Matrix/Workbook model points to typed data containers, not ad hoc tables.

SciPlot containers should describe:

- `data.table`: columns, roles, units, comments, profiles, statistics, source provenance.
- `data.matrix`: dimensions, x/y coordinate vectors or generated coordinates, scalar field metadata, units, missing-value policy.
- `data.transformed_view`: variable bindings, transform chain, source hash, transform diagnostics.
- `data.fit_result`: model, parameters, covariance/errors, residuals, metrics, source binding, overlay link.
- `data.notebook_output`: generated tables/figures from Code Console runs.

This lets Plot Data Workbook and Data Studio share backend truth without creating a second table model in Swift.

## Test translation

LabPlot's test suite is a product lesson. Mature plotting software needs more than smoke screenshots.

SciPlot should add fixture-driven numerical tests for:

- Fit models against NIST-style reference datasets and published expected values.
- Smooth/interpolate/integrate/differentiate operations against small deterministic arrays.
- FFT/filter/KDE/statistics operations with explicit tolerances.
- Import filters with malformed delimiter, encoding, header, unit, ragged rows, and empty-column cases.
- Project graph roundtrip for Plot, Data Studio, Composer, and Code Console.
- Undo/redo command replay for plot object edits, transform edits, axis edits, series styles, annotations, and guide placement.

These tests are how we get stability from LabPlot-level ideas while keeping a SciPlot-owned implementation.

## Why SciPlot can feel weird today

The current app can feel inconsistent when object identity lives in the UI or payload fragments instead of one shared model. Symptoms include inspector state that does not obviously map to a persisted object, backend capabilities that are implied by view code, generic import failures, and edit flows that are hard to undo cleanly.

The fix is not more panels. The fix is a first-principles architecture:

- Every durable thing has a graph id.
- Every edit is a typed command.
- Every backend capability is cataloged.
- Every import failure is structured.
- Every analysis result uses the same envelope.
- Every numerical feature earns fixtures before it becomes a polished UI control.

## Better-than-LabPlot direction

SciPlot should borrow LabPlot's engineering discipline while keeping the product simpler:

- Keep Launcher plus four native singleton windows instead of a global workbench shell.
- Keep `src/plot_contract.json` and `/meta` as public capability truth instead of duplicating constants in macOS.
- Keep sidecar authority for validation, transforms, analysis, export, and project restore.
- Use Python scientific libraries through typed contracts rather than porting GPL C/C++ algorithms.
- Use SwiftUI and native `UndoManager` for desktop feel, with sidecar-normalized payloads for correctness.
- Keep `.sciplot` as a self-contained bundle with embedded truth sources.

This is the path to make SciPlot feel smoother than LabPlot on macOS while growing a backend that can carry LabPlot-scale scientific plotting work.
