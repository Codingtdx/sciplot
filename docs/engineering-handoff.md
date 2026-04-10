# Engineering Handoff Runbook

This document is the persistent handoff ledger for SciPlot God.
Every development round must update this file.

## 1) Scope And Ownership

- Supported desktop runtime: `app/macos` only.
- Backend truth source: `app/sidecar`.
- Core rendering/data/composer truth source: `src/rendering`, `src/data_studio`, `src/composer.py`.
- Contract truth source: `src/plot_contract.json`.
- Project boundary rules and invariants: `AGENTS.md`.

## 2) First-Day Takeover Checklist

1. Read:
   - `AGENTS.md`
   - `README.md`
   - `docs/product-architecture.md`
2. Run full validation matrix:
   - `.venv/bin/python scripts/clean_repo.py`
   - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`
   - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`
   - `.venv/bin/python -m pytest tests`
   - `.venv/bin/python scripts/smoke_check.py`
   - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`
   - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`
3. Sanity-check one user flow in each workbench:
   - Plot: Import -> Inspect -> Template -> Refine -> Preflight -> Export
   - Data Studio: Import -> Group Review -> Compare Preview -> Export/Open in Plot
   - Composer: preview/export with layer/hidden/lock semantics
   - Code Console: context bind -> run -> outputs/reveal

## 3) Decision Records

### 2026-04-08: Single runtime + compatibility-layer removal

- Change:
  - Removed `app/desktop/**`.
  - Removed legacy sidecar endpoints and legacy inspection field.
  - Removed dual entry shell (`src/entry/**`).
- Why:
  - First principles: one product runtime, one backend surface, one source of truth.
  - Avoid duplicated maintenance surface and hidden compatibility cost.
- Rejected alternatives:
  - Keep legacy routes as fallback shim: rejected due to long-term complexity and unclear ownership.
  - Keep desktop as historical runnable shell: rejected due to divergence risk.
- Boundaries:
  - No restoration of deleted routes/chains unless there is a new supported product requirement.

### 2026-04-08: Runtime latency and native motion optimization

- Change:
  - Sidecar runtime now uses layered probing:
    - cold start: full compatibility probe
    - hot path: TTL health check -> fallback full probe only on failure
  - Bootstrap now fetches `/meta` and `/plot-contract` concurrently.
  - Preview decode path now reuses cached base64->Data and Data->Image decoding.
  - Added latest-write-wins protection/debounce/cancel behavior in high-frequency session paths.
  - Added subtle native motion tokens and lightweight transitions for state clarity.
- Why:
  - First principles: perceived responsiveness is dominated by avoiding redundant work and blocking.
  - Keep behavior unchanged while reducing request overhead and main-thread churn.
- Rejected alternatives:
  - Always run full compatibility probe per request: rejected for avoidable fixed overhead.
  - Heavy/long animations: rejected because they hurt task throughput and readability.
- Boundaries:
  - No API behavior changes.
  - Motion must remain short, low-amplitude, and non-blocking.

### 2026-04-08: Context-ID fast path + persistent runner + comparison context reuse

- Change:
  - Added in-memory LRU runtime cache (`src/infrastructure/runtime_cache.py`) and wired it into:
    - Plot preview route cache (`/render-preview`)
    - Code Console context cache by `context_id`
  - Code Console:
    - `/code-console/context` now emits stable `context_id` (input path + mtime + resolved options signature).
    - `/code-console/run` now accepts optional `context_id`; fast path reuses cached context.
    - Added persistent runner manager (`src/code_console_runner.py`) and subprocess auto-fallback on manager failure.
  - Data Studio comparison:
    - cache key now includes workbook mtimes.
    - comparison context directory reuse with manifest-based reuse.
    - removed repeated workbook parse/list calls in one comparison build path.
  - Sidecar schema hardening:
    - `/meta` and `/plot-contract` switched to explicit response models.
    - `DELETE /data-studio/templates/{id}` now returns typed `StatusResponse`.
    - composer/code-console/data-studio route errors now use contextual error mapping.
- Why:
  - First principles: throughput is dominated by duplicate parse/rebuild/cold-start costs.
  - Keep workflow/IA unchanged and reduce latency by reusing validated context and artifacts.
- Rejected alternatives:
  - Rebuild context and start a fresh subprocess for every Code Console run: rejected due repeated fixed costs.
  - Keep route responses as free-form dicts: rejected due schema drift and compatibility risk.
  - Rebuild Data Studio comparison workbook/context each preview call: rejected due avoidable repeated IO/parse.
- Boundaries:
  - `context_id` cache is process-local and invalidates on input mtime change.
  - If persistent runner manager is unstable, run path degrades to legacy subprocess path.
  - No contract semantic changes in `src/plot_contract.json`.

### 2026-04-08: Shared async orchestration kernel + three-layer macOS session split

- Change:
  - Added shared async orchestration primitives in `app/macos/Sources/Shared/Utilities/WorkspaceBridge.swift`:
    - `AsyncLatestTaskCoordinator`
    - `KeyedAsyncLatestTaskCoordinator<Key>`
  - Refactored `PlotSession` / `DataStudioSession` / `ComposerSession` / `CodeConsoleSession` to explicit internal layering:
    - state storage (`RuntimeState`)
    - async coordination (`AsyncCoordination`)
    - UI-derived logic (`DerivedState`)
  - Unified debounce/cancellation/revision gate/latest-write-wins semantics through shared coordinators, replacing ad-hoc per-session task+revision bookkeeping.
  - Added coordinator behavior tests in `app/macos/Tests/CodeConsoleSessionTests.swift`.
- Why:
  - First principles: stale async responses and duplicated orchestration logic are the highest recurring source of UI inconsistency/regression.
  - A shared kernel plus explicit layering minimizes copy-paste divergence and simplifies future session maintenance.
- Rejected alternatives:
  - Keep per-session task/revision implementations: rejected due drift risk and repeated bug surface.
  - Large immediate extraction into standalone state-store objects for all observable fields: rejected this round due migration risk and low short-term return.
- Boundaries:
  - No IA/workflow/shortcut/order changes.
- Session orchestration objects must remain `@MainActor` isolated.
- Path-scoped async work (for workbook previews) must use keyed latest-write-wins semantics.

### 2026-04-08: macOS first-principles GUI hardening (single import wizard + explainable actions + progressive inspector + undo)

- Change:
  - Data Studio import merged into one staged wizard sheet (`scope -> kind -> resolver -> create template`) on macOS.
  - Added shared `ActionAvailability` and wired export actions to `disabled + help` (toolbar + menu + key inspector actions).
  - Upgraded workbench error chips to expandable diagnostic cards (summary/detail/copy; retry hook supported).
  - Workbench top bars now prioritize document-state summaries (source/template-or-figure/latest output/latest failure).
  - Plot/Data Studio integrated native `UndoManager` for key reversible edits.
  - Plot/Data Studio inspector controls switched to progressive disclosure (`DisclosureGroup("Advanced")`).
- Why:
  - First principles: reduce cognitive load, remove dead-end/no-op interactions, and keep edits reversible.
  - Apple-native semantics: one modal context per task, explicit disabled reasons, compact default inspector.
- Rejected alternatives:
  - Keep Data Studio multi-modal import chain: rejected for repeated context switching and modal churn.
  - Keep guard-return no-op actions: rejected due hidden state and poor recoverability.
  - Keep full inspector expanded by default: rejected due scan overload for common tasks.
- Boundaries:
  - No sidecar/Python route or schema changes.
  - No app-level navigation expansion.
  - Undo scope remains key in-memory edits only (not long-running import/export side effects).

### 2026-04-09: Data Studio specimen filter popover + baseline/committed preview split

- Change:
  - Replaced the always-open Data Studio specimen filter pane with an anchored macOS popover.
  - Added two preview lanes in macOS session state:
    - baseline workbook preview without `specimen_states`
    - committed workbook preview with applied `specimen_states`
  - Added specimen score metadata to preview payloads:
    - `composite_signed_score`
    - `distance_from_mean_score`
    - `score_side`
    - `auto_rule_role`
    - `eligible_for_auto_filter`
  - Advanced manual filtering now uses local draft specimen state with explicit Apply/Revert semantics.
- Why:
  - First principles: the common user question is “is automatic convergence filtering on, and is the preview already using it?”, not “which exact specimen was removed?”
  - The automatic recommendation must stay stable and understandable, so it is always computed from the full workbook baseline rather than the currently filtered subset.
- Rejected alternatives:
  - Keep the persistent split-pane specimen list: rejected for scan overload, truncation, and low signal for the common path.
  - Recompute auto recommendation from the currently filtered subset: rejected because the rule becomes moving-target/opaque.
  - Add a dedicated sidecar endpoint for specimen filtering: rejected because `/data-studio/workbook-preview` already covers both baseline analysis and committed refresh.
- Boundaries:
  - The statistical rule itself is unchanged: one low-side and one high-side specimen are removed using the existing Strength/Modulus/Elongation z-score composite.
  - Compare/export continue to consume only committed `specimen_states`.
  - Default popover content must not enumerate removed specimen names; specimen-level inspection remains Advanced-only.

### 2026-04-09: Typed presentation-model derivation for specimen-filter UI

- Change:
  - Centralized Data Studio specimen-filter UI derivation into one typed presentation model (`DataStudioSpecimenFilterPresentation`) instead of scattering button labels, badges, summaries, help text, preview banners, and Advanced rows across many helpers.
  - Added explicit first-principles engineering guidance to `AGENTS.md` and `README.md` so future work starts from minimum state, one source of truth, and same-round dead-code removal.
- Why:
  - First principles: the hardest UI bugs in this area came from duplicated derived state, not from missing business logic.
  - A single presentation model keeps semantic state (`off / auto / manual / unavailable`) separate from view rendering and makes review easier because every displayed filter affordance comes from one derivation path.
- Rejected alternatives:
  - Keep many small UI helper methods near the session: rejected because the same counts/copy/branching drifted across call sites and made “是否已经应用” hard to reason about.
  - Move filter wording directly into SwiftUI views: rejected because views would then own business-state branching and become harder to test.
- Boundaries:
  - This pattern is for derived UI state, not for moving backend scoring logic into the client.
  - Necessary session semantics remain distinct: baseline preview, committed preview, and manual draft are still separate because they represent different truths, not accidental duplication.

### 2026-04-09: Auto Keep 5 + single-entry ranked popover

- Change:
  - Changed the default Data Studio automatic specimen filter from “drop one low-side and one high-side specimen” to a fixed `Auto Keep 5` rule using the same triad z-score distance metric.
  - Removed the duplicate left-rail filter trigger and kept one specimen-filter entrypoint in the `Focused Group` strip.
  - Simplified the default popover to open directly on the ranked keep/out list and moved filenames/manual specimen selection fully into `Advanced`.
- Why:
  - First principles: users care about the convergence outcome and ordering, not duplicate entrypoints or low-signal metadata like representative filename/workbook subtitle.
  - A fixed keep-count rule is easier to understand and easier to verify visually than a “drop both extremes” explanation.
- Rejected alternatives:
  - Keep both left-rail and focused-strip triggers: rejected because the same control appearing twice reads as duplication and increases scan cost.
  - Keep the previous “remove low/high” rule: rejected because the resulting kept count changes with input size and is harder to explain.
  - Keep the `Status / Rule / Effect` card stack: rejected because it repeats information and delays the ranked result the user actually wants to see.
- Boundaries:
  - Baseline preview is still the source of Auto Keep 5 ranking.
  - Compare/export still consume only committed `specimen_states`.
  - Default popover does not reveal filenames; specimen identity remains `Advanced`-only.

### 2026-04-09: Specimen filter prewarm + non-blocking popover close policy

- Change:
  - macOS Data Studio now preloads specimen filter baseline/committed previews during workbook upsert and focus switching, instead of waiting for first popover open.
  - Specimen filter popover close behavior is now lightweight: closing (or switching workbook anchor) discards draft manual edits directly, without confirmation dialogs.
  - Popover content now uses a fixed first-open size so loading-state and loaded-state remain immediately operable.
- Why:
  - First principles: this popover is a lightweight working affordance, so first interaction must be immediately usable and must not escalate into modal-style commit/discard friction.
  - Preloading removes avoidable first-click latency; fixed initial geometry removes first-open layout thrash.
- Rejected alternatives:
  - Keep close confirmation for draft edits: rejected because it over-weights a temporary popover state and interrupts flow.
  - Keep on-demand loading at first open: rejected because it makes the first click visually unstable and delays actionability.
- Boundaries:
  - Draft semantics are unchanged: only explicit Apply writes committed `specimen_states`; close/switch still reverts draft only.
  - Prewarm is opportunistic cache fill for existing preview endpoints; no new sidecar endpoint or scoring logic is introduced.
  - Failure condition: if preload requests fail, popover still opens and shows the existing loading/error affordance.

### 2026-04-09: Data Studio figure switches must not inherit unsaved manual axis overrides

- Change:
  - macOS `PlotSession` now resets figure-scoped render options back to the target template defaults/recommendations when Data Studio opens an external figure without saved `preferredOptions`.
  - Saved per-figure manual axis overrides continue to restore through Data Studio `figurePreferences`; unsaved figures now start from their own template defaults instead of inheriting the previously focused figure's `x/y min/max`, baseline, or legend order.
- Why:
  - First principles: manual axis bounds are figure-specific authoring state, not a global workspace preference.
  - Reusing the previous figure's bounds silently changes the meaning of a newly focused figure and makes the shared `Advanced -> X range / Y range` inspector unreliable as a recovery path.
- Rejected alternatives:
  - Add a second Data Studio-only custom-axis UI: rejected because the shared inspector already exposes the right controls, and duplicating them would create a second state path.
  - Keep inheriting the prior figure state until the user edits again: rejected because it couples unrelated figure families and hides the true template default behavior.
- Boundaries:
  - Cross-figure carry-over is still allowed for still-valid style, palette, and theme choices.
  - This round does not change Python rendering contracts, sidecar schemas, or cache-key semantics.
  - Failure condition: if a future template switch path bypasses `shouldResetRenderOptions`, unsaved figure switches can regress to state leakage again.

### 2026-04-09: Single public style + explicit template semantics cleanup

- Change:
  - Plot contract public style surface now exposes only `nature`, with legacy style ids normalized immediately to `nature` at ingress.
  - Public template/catalog/recommendation surfaces now expose only explicit template ids; legacy aliases remain input-compatible only through normalization/migration.
  - `distribution_compare` is now compatibility-only and resolves to `box`, `box_strip`, or `violin` before validation, recommendation, preflight, render, export manifest generation, and session hydration.
  - Data Studio tensile recipes/exports and macOS session migration now use canonical explicit ids and no longer round-trip removed public ids.
- Why:
  - First principles: one visible semantic should map to one real behavior. `default` and `nature` were effectively the same publication profile, while several template ids were either unreachable or misleading labels for more specific chart shapes.
  - Keeping those ids public made `/meta`, `/plot-contract`, recommendations, exports, and saved session state look richer than the actual supported product surface.
- Rejected alternatives:
  - Keep `default` as a second public label for `nature`: rejected because it preserves semantic duplication and encourages a fake style picker.
  - Keep alias/family template ids publicly visible but “documented as legacy”: rejected because recommend/export/gallery surfaces would still advertise names that are not the real rendered chart types.
  - Keep `distribution_compare` as a user-visible family selector id: rejected because Plot and Data Studio were already resolving it to different concrete shapes, which made exports and UI labels inaccurate.
- Boundaries:
  - Visual themes remain supported and are still the only soft visual variation layer.
  - Legacy ids are still accepted at ingress for compatibility, but they must normalize immediately and must never be emitted back out through public payloads or persisted state.
  - If source inspection is unavailable during `distribution_compare` migration, `box` is the conservative fallback.

### 2026-04-10: Data Studio comparison-preview PDF cache by materialized context key

- Change:
  - Added an in-memory LRU cache for Data Studio comparison preview PDFs in `src/data_studio/comparison.py`.
  - Cache key now derives from `materialized_context.cache_key + recipe identity` (`recipe_id`, `template_id`, `sheet_name`), so unchanged compare context reuses the exact preview PDF bytes without re-rendering matplotlib figures.
  - Added regression coverage for:
    - cache hit on unchanged context
    - cache invalidation when `specimen_states` changes (context key changes).
- Why:
  - First principles: repeated rendering of the same preview is pure recomputation and dominates latency despite stable workbook/context state.
  - Existing context materialization already emits a stable invalidation key with workbook mtime + filter states, so preview cache can piggyback on that source of truth safely.
- Rejected alternatives:
  - Cache in macOS view/session layer only: rejected because duplicate preview requests can come from multiple clients and sidecar is the single source of recomputation.
  - Cache raw `RenderedPlot`/`Figure` objects: rejected due heavyweight lifecycle/close semantics and memory risk.
- Boundaries:
  - Cache is process-local and non-persistent; restart clears it.
  - Cache only applies to `/data-studio/comparison-preview` path; export still renders independently.
  - Invalidation is bounded by `materialized_context.cache_key`; if future context key omits a semantic input, preview cache can become stale.

### 2026-04-10: Rendering inspection + normalized-dataset cache de-dup

- Change:
  - Added process-local LRU caches in rendering hot paths:
    - `build_normalized_dataset(...)` now reuses immutable normalized snapshots by `(resolved_path, mtime_ns, sheet, model)` in `src/rendering/dataset_models.py`.
    - `inspect_input_file(...)` now reuses inspection/recommendation payloads by `(resolved_path, mtime_ns, sheet)` in `src/rendering/recommendation.py`.
  - Added explicit cache clear hooks:
    - `clear_normalized_dataset_cache()`
    - `clear_inspection_cache()`
  - Added regression tests to lock cache hit/invalidation behavior against file mtime updates.
- Why:
  - First principles: export/inspect/preflight paths were repeatedly recomputing deterministic model detection and recommendation payloads for unchanged inputs.
  - Removing duplicate inference work in shared rendering services is safer and more reusable than adding one-off route-level short-circuits.
- Rejected alternatives:
  - Add ad-hoc cache only inside `/export-render`: rejected because `inspect-file`, preflight-linked flows, and future callers would still pay duplicate compute.
  - Drop inspection artifact generation during export: rejected because it changes artifact contract and downstream diagnosability.
- Boundaries:
  - Caches are process-local and non-persistent.
  - Invalidation depends on `(path, mtime, sheet[, model])`; external mutation that preserves mtime can still produce stale reuse.
  - Cached values are immutable dataclasses only; no figure handles are cached in this layer.

## 4) Troubleshooting Playbook

### Symptom: `xcodebuild` fails with Swift 6 concurrency safety errors

- Typical cause:
  - non-Sendable static shared state or UI transition tokens not actor-isolated.
- Fix pattern:
  - mark UI token containers as `@MainActor`.
  - isolate cache helpers that use `NSCache` to `@MainActor` or wrap safely.
  - avoid cross-actor capture of non-Sendable protocol existential in `async let`; use an explicit sendable wrapper if needed.

### Symptom: runtime `ensureRunning` restarts too often

- Typical cause:
  - health probe fails repeatedly and full probe cannot recover.
- Check:
  - inspect `SidecarRuntime` logs for:
    - health probe status
    - route compatibility failures
    - `/meta` or `/plot-contract` decode/shape failures
- Fix:
  - verify local sidecar process and payload shape.
  - ensure required route set stays aligned with current backend surface.

### Symptom: Data Studio preview flashes/reverts during rapid specimen toggles

- Typical cause:
  - stale async response overwriting newer state.
- Check:
  - verify revision guard + task cancellation for workbook preview refresh path.
- Fix:
  - keep latest-write-wins guard and do not remove per-workbook revision tracking.

### Symptom: `xcodebuild test` fails after API model field additions

- Typical cause:
  - test payload factories and session tests were not updated for new required fields (`context_id`).
- Fix pattern:
  - update `TestPayloads` and tests constructing `CodeConsoleContextResponse` to include `contextID`.
  - rerun `xcodebuild test` after test fixture updates.

### Symptom: Data Studio macOS tests time out after figure-family switch and no preview request arrives

- Typical cause:
  - `MockSidecarClient.inspectFile` fell back to `TestPayloads.inspectFile()` with its default hard-coded `inputPath`, so the returned inspection payload no longer matched the comparison workbook path under test.
  - `PlotSession.needsInspection` then stayed true, which blocked preview rendering and made figure-switch/open-in-plot assertions wait forever.
- Check:
  - confirm `client.inspectRequests.last?.inputPath` matches the workbook path currently loaded into `PlotSession`.
  - if tests use comparison workbooks or exported `.xlsx` paths, verify the mocked inspect response echoes `request.inputPath`.
- Fix:
  - in affected tests, set `client.inspectHandler = { request in TestPayloads.inspectFile(path: request.inputPath) }`.
  - rerun the targeted `DataStudioSessionTests` / `PlotSessionTests` slice before the full macOS suite.

### Symptom: Swift compile error `main actor-isolated default value in a nonisolated context`

- Typical cause:
  - shared coordinator holder type creates `@MainActor`-isolated coordinator instances from a non-isolated type context.
- Fix pattern:
  - mark the holder type (`AsyncCoordination`) as `@MainActor` when it owns `AsyncLatestTaskCoordinator` / `KeyedAsyncLatestTaskCoordinator`.
  - keep coordinator lifecycle owned by `@MainActor` sessions only.

### Symptom: Data Studio import kind is clickable but native file picker does not appear

- Typical cause:
  - `fileImporter` is requested while the staged Data Studio wizard sheet is still presented, creating modal presentation contention.
- Check:
  - verify `chooseImportKind` first dismisses wizard state (`isImportWizardPresented = false`) before any importer presentation flag is toggled.
  - verify there is no state where `isImportWizardPresented == true` and `isImportPresented == true` at the same time.
- Fix pattern:
  - centralize importer presentation into a small deferred scheduler (`Task { @MainActor ... }`) that runs after wizard dismissal on the next main-actor turn.
  - keep cancel behavior explicit: import panel cancel should reset import flow state and exit the flow.

### Symptom: `xcodebuild build` or `xcodebuild test` fails with `build.db: database is locked`

- Typical cause:
  - two `xcodebuild` processes were launched concurrently against the same `-derivedDataPath` (`app/macos/.derivedData`), so Xcode's build database stayed locked.
- Check:
  - confirm there is no overlapping `xcodebuild build` still running when `xcodebuild test` starts.
  - prefer one serial invocation at a time for the shared derived-data directory.
- Fix pattern:
  - rerun the failed command serially after the previous build fully exits.
  - if parallel CI is ever needed, give each job an isolated `-derivedDataPath`.

### Symptom: Data Studio representative tensile curve preview shows scattered per-series labels instead of a compact legend

- Typical cause:
  - small-panel curve candidate selection preferred direct edge labels for tensile-like curves when series count reached comparison-size groups.
- Check:
  - confirm rendered QA autofixes include `direct_series_labels` for `curve` previews where `preserve_stress_label` is true and group count is high.
- Fix pattern:
  - keep direct labels enabled for normal small-panel curves, but suppress direct-label candidates for tensile-preserved axis labeling when series count is 4+ so preview falls back to legend-based candidates.

### Symptom: Preview card left edge/corner looks jagged after PDF preview appears

- Typical cause:
  - mixed rounded-shape styles and missing anti-aliased clipping around `NSViewRepresentable` PDF preview content.
- Check:
  - verify `PlotRefineView` and base64 preview wrappers all use the same `RoundedRectangle(cornerRadius: 18, style: .continuous)` shape and that clipping happens before overlay stroke.
- Fix pattern:
  - apply a single continuous rounded shape for clip + background + border, and keep border drawing anti-aliased (`strokeBorder(..., antialiased: true)`).

## 5) Round Change Log

### 2026-04-08 (Round A): Repository simplification and legacy removal

- Scope:
  - Removed historical desktop/runtime compatibility layers and old routes.
  - Consolidated canonical entrypoints and backend fields.
- User-visible impact:
  - None on supported macOS workflow.
- Risks:
  - stale docs/tests referencing deleted legacy surfaces.
- Validation:
  - full Python + macOS matrix passed at merge time.

### 2026-04-08 (Round B): Performance + native motion optimization

- Scope:
  - Sidecar runtime layered probe, bootstrap concurrency, preview decode caching, session concurrency guards, subtle native motion.
- User-visible impact:
  - Faster click-to-feedback in hot paths and smoother state transitions.
  - No workflow, IA, or API changes.
- Risks:
  - Swift 6 concurrency constraints around shared static state.
  - potential stale-response overwrite if revision guards are removed.
- Added test coverage:
  - `SidecarRuntimeTests`: hot-path probe cache + fallback probe recovery.
  - `DataStudioSessionTests`: latest response wins under rapid specimen toggles.
  - `PDFPreviewViewTests`/decoder tests: decode cache reuse and PDF signature gate.
- Validation (executed):
  - Python:
    - `clean_repo.py`: passed
    - `ruff`: passed
    - `mypy`: passed
    - `pytest`: 143 passed
    - `smoke_check.py`: passed
  - macOS:
    - `xcodebuild build`: passed
    - `xcodebuild test`: 76 passed

### 2026-04-08 (Round C): First-principles full-project optimization sweep

- Scope:
  - Plot/Data Studio/Code Console/Sidecar/macOS 同轮优化，保持 IA 与 canonical workflows 不变。
  - Added plot preview cache, Data Studio context reuse and mtime invalidation, Code Console `context_id` fast path, persistent runner manager + subprocess fallback, explicit sidecar response models, and contextualized error surfaces.
  - macOS wired `contextID` through Code Console models/session run request.
- User-visible impact:
  - Code Console repeated runs become near-instant when `context_id` is reused.
  - Data Studio comparison context/preview and Plot preview avoid repeated rebuild in steady state.
  - No workflow or navigation changes.
- Risks:
  - In-memory caches are process-local and can go stale if external mutation bypasses mtime changes.
  - persistent runner regression risk on specific machines.
  - sidecar response schema tightening can expose hidden client payload assumptions.
- Rollback points:
  - Code Console runner fallback path: disable persistent path by reverting `src/code_console_runner.py` integration in `src/code_console_service.py`.
  - Context-id API rollback: route/schema changes in `app/sidecar/schemas_code_console.py` + `app/sidecar/routes_code_console.py`.
  - Meta/contract response model rollback: `app/sidecar/routes_meta.py` + `app/sidecar/schemas_meta.py`.
  - Data Studio comparison reuse rollback: `src/data_studio/comparison.py` + `src/infrastructure/persistence/data_studio_comparison_contexts.py`.
- Performance tactile targets and conclusion:
  - Target:
    - `data_studio.context p95 <= 0.20s`
    - `data_studio.preview p95 <= 0.50s`
    - `plot.preview p95 <= 0.22s`
    - `plot.export p95 <= 0.30s`
    - `code_console.run p95 <= 0.55s`
  - Benchmark command:
    - `.venv/bin/python scripts/benchmark_workbench_perf.py --samples 20 --warmup 3 --output docs/performance/benchmark-2026-04-08.json`
  - Baseline (provided):
    - `plot.preview p95≈0.27s`
    - `plot.export p95≈0.34s`
    - `data_studio.context p95≈0.41s`
    - `data_studio.preview p95≈0.71s`
    - `code_console.run p95≈0.93s`
  - This round measured p95:
    - `plot.preview p95=0.0008s`
    - `plot.export p95=0.2776s`
    - `data_studio.context p95=0.0013s`
    - `data_studio.preview p95=0.2924s`
    - `code_console.run p95=0.0031s`
  - Notes:
    - benchmark runs in-process via `TestClient`; numbers are comparable only with same harness but validate target-direction and cache/runner gains.
- Added protective tests:
  - `tests/test_sidecar_code_console.py::test_code_console_run_prefers_context_id_fast_path`
  - `tests/test_code_console_service.py::test_code_console_run_falls_back_to_subprocess_when_runner_fails`
  - `tests/test_code_console_service.py::test_persistent_runner_recovers_after_timeout`
  - `tests/test_sidecar_render.py::test_render_preview_uses_cache_and_invalidates_when_options_change`
  - `tests/test_data_studio.py::test_preview_data_studio_comparison_context_invalidates_on_workbook_mtime`
  - `tests/test_data_studio.py::test_preview_data_studio_comparison_context_avoids_duplicate_workbook_imports`
  - `tests/test_sidecar_schema_contract.py::test_meta_and_plot_contract_responses_match_explicit_models`
  - `tests/test_sidecar_schema_contract.py::test_delete_data_studio_template_returns_status_response`
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`152 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`76 tests`)

### 2026-04-08 (Round D): macOS session-layer deep refactor completion

- Scope:
  - Completed macOS Session-layer deep refactor for all workbenches while keeping public workflows unchanged.
  - `PlotSession` / `DataStudioSession` / `ComposerSession` / `CodeConsoleSession` now consistently use:
    - `RuntimeState` for private mutable storage
    - `AsyncCoordination` for async orchestration lanes
    - `DerivedState` for UI-derived state logic
  - Unified async orchestration semantics via shared coordinators in `WorkspaceBridge.swift`.
  - Added protective coordinator behavior tests under `CodeConsoleSessionTests`.
- User-visible impact:
  - 无（行为等价）；主要收益是并发路径稳定性与后续维护可读性提升。
- Risks:
  - refactor touches multiple central session files; accidental stale-state regressions are possible if revision guards are bypassed later.
  - Swift actor-isolation annotations are required for coordination holders.
- Rollback points:
  - Revert session internal layering changes in:
    - `app/macos/Sources/Features/Plot/PlotSession.swift`
    - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
    - `app/macos/Sources/Features/Composer/ComposerSession.swift`
    - `app/macos/Sources/Features/CodeConsole/CodeConsoleSession.swift`
  - Revert shared orchestrator primitives in:
    - `app/macos/Sources/Shared/Utilities/WorkspaceBridge.swift`
  - Revert protective tests in:
    - `app/macos/Tests/CodeConsoleSessionTests.swift`
- Added protective tests:
  - `CodeConsoleSessionTests::testAsyncLatestTaskCoordinatorExecutesLatestOperationOnly`
  - `CodeConsoleSessionTests::testKeyedAsyncLatestTaskCoordinatorMaintainsPerKeyLatestWriteWins`
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`152 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`78 tests`)

### 2026-04-08 (Round E): macOS GUI interaction hardening (Apple-native)

- Scope:
  - Data Studio import moved to a single staged wizard sheet.
  - Export actions now expose explicit availability reasons via `ActionAvailability`.
  - Plot/Data Studio inspector switched to progressive disclosure for low-frequency controls.
  - Plot/Data Studio/Code Console top bars now report document-state summaries.
  - Plot/Data Studio key edits integrated with native Undo/Redo.
  - Added macOS tests for wizard state, export availability mapping, and undo restore coverage.
- User-visible impact:
  - Data Studio import stays in one continuous sheet context.
  - Export buttons no longer silently no-op; disabled state explains why.
  - Inspector defaults are less crowded with advanced controls available on demand.
  - Error details are expandable/copyable in-place.
  - Plot/Data Studio edits can be undone/redone with native shortcuts.
- Risks:
  - Import wizard step/legacy state sync can regress if future edits change one side only.
  - Undo currently covers selected key edits, not every mutating path.
  - Document-state summary strings are dense and may need future copy tuning.
- Rollback points:
  - Wizard/UI state: `app/macos/Sources/Features/DataStudio/DataStudioSession.swift` and `DataStudioWorkbenchView.swift`.
  - Availability wiring: `app/macos/Sources/Shared/UI/StateViews.swift`, `AppModel.swift`, `RootSplitView.swift`, `AppCommands.swift`.
  - Undo wiring: `app/macos/Sources/Features/Plot/PlotSession.swift` and `DataStudioSession.swift`.
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`152 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`86 tests`)

### 2026-04-09 (Round F): Data Studio native importer sequencing fix + full interface audit

- Scope:
  - Fixed Data Studio import modal sequencing in macOS session layer so import kind selection always dismisses wizard first, then presents native `fileImporter`.
  - Added importer presentation scheduler path in `DataStudioSession` to avoid sheet/importer modal contention.
  - Added regression tests for wizard -> importer transition and cancel-reset behavior.
  - Performed static sidecar interface audit between macOS `SidecarClient` and `app/sidecar/routes_*.py` route surface.
- User-visible impact:
  - Data Studio `Raw Files` / `Existing Workbook` now reliably opens the native file picker.
  - Canceling the file picker exits the import flow cleanly without stale wizard/import states.
- Risks:
  - Import presentation now depends on deferred main-actor scheduling; future direct toggles of `isImportPresented` from new paths can bypass this safeguard.
- Rollback points:
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift` (`chooseImportKind` + deferred importer scheduler).
  - `app/macos/Tests/DataStudioSessionTests.swift` and `app/macos/Tests/AppModelTests.swift` (new transition regression coverage).
- Interface audit result:
  - `SidecarClient` endpoint strings and sidecar route registrations are fully aligned (`client_paths=25`, `route_paths=25`, no missing paths after dynamic template-id normalization).
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`152 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`89 tests`)

### 2026-04-09 (Round G): Data Studio specimen filter popover + score metadata remediation

- Scope:
  - Extended Data Studio workbook preview models/schemas with specimen score metadata and wired `src/data_studio/workbooks.py` to emit signed score, distance, side, auto-role, and eligibility fields without changing the exclusion rule.
  - Reworked macOS Data Studio specimen filtering from a persistent pane into an anchored popover with default `Status / Rule / Effect / Actions` content and an Advanced disclosure for score-sorted manual overrides.
  - Split macOS session filter state into baseline preview, committed preview, and draft specimen states; added `off / auto / manual / unavailable` mode inference, dirty-close confirmation, edited row badges, and explicit preview filter status messaging.
  - Added regression coverage across Python, sidecar JSON payloads, and macOS session behavior for score fields, baseline-vs-committed previews, filter mode inference, manual draft semantics, and unsaved-close confirmation.
  - Updated `README.md` and `AGENTS.md` so future work keeps the popover interaction and baseline-vs-committed preview contract intact.
- User-visible impact:
  - Data Studio filtering is now lighter and clearer: users get a small popover with one-click auto filter, a compact effect summary, and an explicit preview-applied status line instead of a cramped always-open specimen pane.
  - Advanced users can inspect distance-from-mean ordering and manually override inclusion, but those edits stay draft-only until `Apply Manual Filter`.
- Risks:
  - Filter clarity now depends on baseline preview refresh succeeding; if that request fails, the popover cannot show a stable automatic recommendation.
  - Draft manual edits are intentionally session-local and are not persisted through session normalization/restore.
- Rollback points:
  - Python/sidecar score metadata rollout: `src/data_studio/models.py`, `src/data_studio/workbooks.py`, `app/sidecar/schemas_data_studio.py`.
  - macOS popover/session state: `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`, `app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift`, `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`, `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchSpecimenViews.swift`.
  - Regression fixtures/tests: `tests/test_data_studio.py`, `tests/test_sidecar_data_studio.py`, `app/macos/Tests/TestPayloads.swift`, `app/macos/Tests/DataStudioSessionTests.swift`.
- Decision:
  - Default specimen filtering is popover-based automatic convergence filtering.
  - Specimen-level inspection/manual selection is Advanced-only.
  - Baseline recommendation is computed from the full workbook preview without `specimen_states`, while compare/export continue consuming only committed `specimen_states`.
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`152 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`93 tests`)

### 2026-04-09 (Round H): Data Studio specimen filter implementation cleanup

- Scope:
  - Removed dead Data Studio specimen filter helpers that were no longer referenced after the popover migration.
  - Collapsed duplicated specimen-state upsert logic in macOS session code into one helper.
  - Added a small `DataStudioSpecimenFilterAnchor.retargeted(to:)` helper so workbook-focus changes no longer repeat anchor-switch branching.
- User-visible impact:
  - None. This round is internal cleanup only.
- Risks:
  - Low. The cleanup only touched duplicated/dead macOS session paths and kept filter semantics unchanged.
- Rollback points:
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift`
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/DataStudioSessionTests`: passed (`33 tests`)

### 2026-04-09 (Round I): Specimen filter first-principles cleanup and maintainability hardening

- Scope:
  - Replaced scattered specimen-filter UI helper branches in macOS session code with one `DataStudioSpecimenFilterPresentation` derivation path for mode, summary, help copy, row badges, preview banner text, busy state, and Advanced rows.
  - Updated specimen-filter SwiftUI views and tests to consume the presentation model instead of reconstructing filter state at each call site.
  - Fixed the unsupported-filter preview banner so unsupported workbooks explicitly say filtering is unavailable instead of falsely implying the preview already applied a filter.
  - Added first-principles engineering guidance to `AGENTS.md` and `README.md`, and documented the `xcodebuild` derived-data lock failure mode in this runbook.
- User-visible impact:
  - No workflow change. The specimen-filter UI is the same feature, but copy/status messaging is now more consistent and unsupported workbooks explain themselves correctly.
- Risks:
  - The presentation model becomes the main filter UI derivation path; future edits that bypass it can reintroduce state drift.
  - The new first-principles guidance only helps if future rounds actually delete dead code instead of layering around it.
- Rollback points:
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchSpecimenViews.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - `app/macos/Tests/DataStudioSessionTests.swift`
  - `AGENTS.md`
  - `README.md`
- Decision:
  - Derived filter UI state must flow through a typed presentation model rather than ad-hoc helper scattering.
  - Keep semantic state separation only where it represents different truths (`baseline`, `committed`, `draft`); remove all accidental duplication around it.
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`152 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`94 tests`)

### 2026-04-09 (Round J): Data Studio Auto Keep 5 simplification and GUI de-duplication

- Scope:
  - Changed the Python specimen-filter recommendation rule to `Auto Keep 5`, keeping the five eligible specimens with the smallest `distance_from_mean_score`.
  - Updated preview payload semantics so `auto_rule_role` now means final recommendation state (`keep / exclude / ineligible`) instead of low/high-edge labels.
  - Removed the duplicate left-rail filter trigger on macOS, deleted the redundant preview filter banner, and redesigned the popover so the default view is just the ranked keep/out list with a visible cutoff.
  - Kept filenames and manual specimen selection inside `Advanced`, updated macOS tests to lock the new titles/order/cutoff behavior, and synced `README.md` / `AGENTS.md` to the new interaction contract.
- User-visible impact:
  - Data Studio filtering is now simpler and more direct: one entrypoint, `Auto Keep 5`, no repeated status panels, and a default ranked list that immediately shows what stays in or drops out.
- Risks:
  - Auto-mode inference now depends on baseline `suggested_exclusion_ids` matching the full non-kept set; future backend changes must preserve that contract.
  - Default UI intentionally hides specimen identity; any future request to expose names in the default view would need a deliberate IA decision instead of a quick patch.
- Rollback points:
  - Python auto-filter rule and preview semantics: `src/data_studio/workbooks.py`, `src/data_studio/models.py`, `app/sidecar/schemas_data_studio.py`
  - macOS filter presentation and popover UI: `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`, `app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift`, `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchSpecimenViews.swift`, `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - Regression fixtures/tests: `tests/test_data_studio.py`, `tests/test_sidecar_data_studio.py`, `app/macos/Tests/TestPayloads.swift`, `app/macos/Tests/DataStudioSessionTests.swift`
- Decision:
  - Default specimen filtering is `Auto Keep 5`, not “drop one low + one high”.
  - Default filter UI is single-entry, ranking-first, and anonymous; filenames/manual overrides are `Advanced`-only.
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`153 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: first attempt failed with `build.db` lock when run concurrently against the same derived-data path; reran serially and passed (`95 tests`)

### 2026-04-09 (Round K): Specimen filter first-open UX stabilization

- Scope:
  - Removed Data Studio specimen-filter close confirmation flow in macOS session/view paths and switched to close/switch = draft revert.
  - Added specimen-filter preview prewarm for workbook upsert/focus so first popover open does not block on cold fetch.
  - Set fixed popover initial dimensions for loading and loaded states to avoid first-open undersized layout.
  - Updated Data Studio macOS tests:
    - replaced pending-draft close test to assert direct discard without confirmation
    - added preload regression test that verifies preview/baseline are ready before popover opens
- User-visible impact:
  - First click on `Specimen Filter` is consistently operable (stable size + preloaded data path).
  - Closing the popover no longer shows disruptive “Discard Changes” confirmation.
- Risks:
  - Draft manual edits are now intentionally easy to drop when the popover closes; this is desired UX but can surprise users who expected a confirmation wall.
  - Prewarm introduces extra background preview requests; future throttling edits must preserve latest-write-wins semantics.
- Rollback points:
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchSpecimenViews.swift`
  - `app/macos/Tests/DataStudioSessionTests.swift`
- Decision:
  - Specimen filter popover is treated as low-ceremony operational UI: no modal close confirmation, and first-open readiness is prioritized via prewarm + stable geometry.
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`153 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/DataStudioSessionTests`: passed (`36 tests`)
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`96 tests`)

### 2026-04-09 (Round L): Data Studio manual axis isolation across figure switches

- Scope:
  - Updated macOS `PlotSession` external-figure loading so a figure without saved `preferredOptions` explicitly resets figure-scoped render options back to the target template defaults/recommendations instead of inheriting the previous figure's manual axis state.
  - Kept Data Studio `figurePreferences` as the only persisted figure-level source of truth and added regressions covering:
    - external figure loads without preferred options
    - figure-family switching between saved and unsaved manual axis overrides
    - `Open in Plot` / export bundle carrying the current figure's manual axis range
  - Expanded macOS test fixtures so shared inspector `Advanced -> X range / Y range` controls are exposed for curve and box templates in tests.
- User-visible impact:
  - Data Studio manual axis edits are now isolated per figure family/template.
  - Switching to a figure that has no saved custom range returns to that figure's default/recommended axis bounds instead of leaking the previous figure's bounds.
  - The existing shared inspector custom-axis controls remain the only fallback entry, but they now behave reliably across figure switches.
- Risks:
  - Any future load path that stages an external figure without going through the template-reset branch can reintroduce cross-figure render-option leakage.
  - Preserving theme while resetting figure-scoped options assumes the current theme remains compatible with the active metadata payload.
- Rollback points:
  - `app/macos/Sources/Features/Plot/PlotSession.swift`
  - `app/macos/Tests/PlotSessionTests.swift`
  - `app/macos/Tests/DataStudioSessionTests.swift`
  - `app/macos/Tests/TestPayloads.swift`
- Decision:
  - Data Studio figure switches must treat manual axis bounds as figure-specific state, restored only from saved `figurePreferences` and otherwise reset to the target template defaults/recommendations.
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`153 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests -only-testing:SciPlotGodMacTests/DataStudioSessionTests`: passed (`50 tests`)
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`98 tests`)

### 2026-04-09 (Round M): Batch Auto Keep 5 + smart tick-label controls + axis tick cleanup

- Scope:
  - Added shared render-option contract fields for smart tick labeling:
    - `x_tick_density`, `y_tick_density`
    - `x_tick_edge_labels`, `y_tick_edge_labels`
  - Wired those fields through Python render models, sidecar schemas/routes, macOS `RenderOptionsPayload`, Data Studio session normalization/export/open-in-plot payloads, and generated contract docs.
  - Added shared macOS inspector controls under `Axis -> Advanced -> Tick Labels`:
    - `Density`: `Auto / Sparse / Dense`
    - `Edge labels`: `Auto / Hide Min / Hide Max / Hide Both`
  - Added Data Studio `Workbook Groups` header action `Auto Keep 5 All`, with one committed batch apply path, `disabled + help`, single undo registration, and one debounced comparison-context rebuild after the batch update.
  - Updated shared plotting primitives so numeric axes apply the new major-label density and edge-label hiding rules after bounds are resolved, while standard numeric minor ticks default to a sparser policy.
  - Cleaned up categorical statistics x-axes so grouped labels remain visible but x-axis tick marks are suppressed and x-axis minor ticks stay off for categorical stats templates.
  - Hardened `scripts/generate_plot_contract_docs.py` so the documented direct-script invocation works without manually setting `PYTHONPATH`.
- User-visible impact:
  - Data Studio now has a one-click `Auto Keep 5 All` action for every eligible workbook group in the current session.
  - Plot and Data Studio inspectors now expose smarter axis-label controls without requiring raw numeric tick entry.
  - Users can hide boundary labels like `-10` while keeping the actual axis range unchanged.
  - Bar/box/violin-style categorical plots no longer show awkward x-axis tick marks, and minor ticks across standard numeric axes are less visually dense.
- Risks:
  - Any future template that forgets to advertise the new editable tick options in `src/plot_contract.json` will silently lose the shared inspector controls even though the render stack supports them.
  - The `Dense` major-label policy intentionally stays conservative; if a future template also adds aggressive formatter overrides, label overlap protection may still collapse back toward `Auto`.
  - Batch `Auto Keep 5 All` deliberately overwrites prior manual specimen filtering for eligible workbooks; if product semantics change toward mixed per-group preservation, `DataStudioSession.applySuggestedExclusionsToAllWorkbooks()` is the rollback point.
- Rollback points:
  - `src/plot_contract.json`
  - `src/plotting_primitives.py`
  - `src/plotting_curves.py`
  - `src/plotting_stats.py`
  - `src/rendering/models.py`
  - `src/rendering/options.py`
  - `src/rendering/render_curve.py`
  - `src/rendering/render_stats.py`
  - `app/sidecar/schemas_render.py`
  - `app/sidecar/render_support.py`
  - `app/sidecar/routes_render.py`
  - `app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - `scripts/generate_plot_contract_docs.py`
- Decision:
  - Smart axis labeling remains a shared inspector capability, not a Data Studio-only fallback, because density/edge-label visibility is render semantics rather than workbench-local UI state.
  - Batch specimen filtering is implemented as a committed session-wide operation with one undo step so compare/export/open-in-plot all observe the same single source of truth.
- Validation (executed):
  - `.venv/bin/python scripts/generate_plot_contract_docs.py`: passed
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`159 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`100 tests`)

### 2026-04-09 (Round N): Tick-label regressions + categorical x-axis minor-tick fix + external figure preview reset hardening

- Scope:
  - Updated shared plotting primitives so `Hide Min / Hide Max / Hide Both` blank the first/last resolved major tick labels using the final visible major-tick sequence, rather than relying on formatter-time value comparisons.
  - Changed categorical statistics x-axis cleanup to remove only x-axis minor ticks; major tick marks and group labels remain visible for bar/box/box-strip/violin-style categorical plots.
  - Hardened macOS `PlotSession.finishLoadingStagedExternalFigure(...)` so inspect-triggered stale preview work is cancelled before applying preferred render options or resetting an unsaved external figure back to template defaults.
  - Added regression coverage for:
    - curve `x_tick_edge_labels="hide_min"` with manual `x_min`
    - sidecar preview-cache invalidation when only `x_tick_edge_labels` changes
    - Data Studio family switching between two metric families that reuse the same template (`box_strip`)
  - Expanded macOS test fixtures to include `box_strip` in test meta/contract payloads and a shared-template Data Studio comparison-set fixture.
- User-visible impact:
  - `Hide Min` now actually suppresses the leftmost x-axis boundary label on representative/curve plots.
  - Categorical statistics plots keep their x-axis major ticks, but no longer show the unwanted x-axis minor ticks.
  - Data Studio external-figure switching is less likely to flash or retain stale axis ranges while the correct figure-specific reset/apply cycle completes.
- Risks:
  - The new fixed-label edge-hiding path assumes major tick locations are resolved before formatter replacement; future code that swaps major locators after `_apply_numeric_axis_tick_preferences(...)` would bypass the blanked edge labels.
  - `PlotSession.finishLoadingStagedExternalFigure(...)` now explicitly cancels stale preview work for unsaved/preferred external loads; future async changes in that method must preserve latest-write-wins semantics or external figure previews can regress.
- Rollback points:
  - `src/plotting_primitives.py`
  - `src/plotting_stats.py`
  - `tests/test_plotting.py`
  - `tests/test_sidecar_render.py`
  - `app/macos/Sources/Features/Plot/PlotSession.swift`
  - `app/macos/Tests/DataStudioSessionTests.swift`
  - `app/macos/Tests/TestPayloads.swift`
- Decision:
  - Boundary label hiding is now defined against the final rendered major-tick list, not against raw numeric comparisons during formatter callbacks, because the rendered tick list is the only stable cross-axis truth once density and locator policies have been applied.
  - External-figure preview recovery prefers cancelling stale inspect-triggered preview work and issuing one final correct preview request over letting intermediate previews race with a later reset/apply step.
- Validation (executed):
  - `.venv/bin/python -m pytest tests/test_plotting.py tests/test_rendering_services.py tests/test_sidecar_render.py`: passed (`72 passed`)
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests -only-testing:SciPlotGodMacTests/DataStudioSessionTests`: passed (`53 tests`)
  - `.venv/bin/python scripts/generate_plot_contract_docs.py`: passed
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`160 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`101 tests`)

### 2026-04-09 (Round O): Manual axis ranges now recompute a fresh major-tick grid

- Scope:
  - Reworked shared linear-axis override handling in `src/plotting_primitives.py` so manual `x_min/x_max/y_min/y_max` no longer append override endpoints onto an old major-tick sequence.
  - Manual linear range edits now derive a fresh evenly spaced major-tick grid from the final visible axis bounds, using the larger of the existing policy step and the new range-driven nice step.
  - Kept the change inside the shared plotting helper so curve / representative-curve and categorical stats plots both pick up the fix without adding any new Data Studio state or UI.
  - Added regressions for:
    - curve manual `x_min=-10` + `Hide Min` using the final recomputed major ticks
    - curve manual `x_min=-5` not introducing an odd extra short interval
    - box/box-strip style manual `y_min/y_max` ranges redistributing to a uniform major-tick sequence
- User-visible impact:
  - Editing axis min/max in Plot or Data Studio now causes the major ticks to be redistributed cleanly instead of showing a one-off `-5` / `-10` tick jammed into the old grid.
  - Manual ranges like `20 -> 60` on stats plots now reallocate to an even sequence such as `20, 30, 40, 50, 60`.
  - `Hide Min` continues to act on the first actually rendered major tick after the recomputed grid is in place.
- Risks:
  - The recomputed linear override grid is intentionally aligned to the shared “nice” grid inside the visible bounds, so manual display bounds are not guaranteed to also become labeled major ticks.
  - Future code that bypasses `_apply_major_ticks_with_override(...)` for linear manual ranges can reintroduce the old “append endpoint to old grid” bug.
- Rollback points:
  - `src/plotting_primitives.py`
  - `tests/test_plotting.py`
- Decision:
  - Manual axis range edits are now treated as display-bound overrides that trigger a fresh major-tick solve, instead of as instructions to force the overridden endpoints into the preexisting tick list, because the latter produced nonuniform spacing and stale grid reuse across both curve and stats families.
- Validation (executed):
  - `.venv/bin/python -m pytest tests/test_plotting.py tests/test_rendering_services.py tests/test_sidecar_render.py`: passed (`74 passed`)
  - `.venv/bin/python scripts/generate_plot_contract_docs.py`: passed
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`163 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`101 tests`)

### 2026-04-09 (Round P): Single `nature` style + explicit template/public-surface cleanup

- Scope:
  - Reduced the public plot contract style surface to a single preset, `nature`, and added immediate normalization for legacy style ids such as `default`, `lab_default`, `science_editorial`, `jacs_analytical`, and `advanced_materials_spacious`.
  - Removed `scatter_with_fit`, `replicate_curves_with_band`, `grouped_bar_compare`, and `distribution_compare` from the public contract/meta/template catalog/recommendation surfaces while keeping ingress compatibility through `src/rendering/template_lifecycle.py`.
  - Moved explicit template resolution ahead of validation, option normalization, preflight, render dispatch, export manifest generation, Data Studio recipe/export paths, and Data Studio/macOS session hydration so canonical ids are what downstream consumers persist and emit.
  - Removed dead alias renderer registrations and old public implementation helpers from the rendering layer, updated smoke assertions to expect normalized style behavior, and updated Python/macOS fixtures/tests to the single-style contract.
  - Regenerated `docs/plot_contract.md` and updated `README.md`, `AGENTS.md`, `docs/data-to-template-v1-handoff.md`, and this handoff ledger to describe the new single-style + explicit-template rule.
- User-visible impact:
  - Plot and Data Studio now expose only one public publication style, `nature`.
  - Template galleries, `/meta`, `/plot-contract`, and recommendation payloads no longer advertise misleading alias ids; users see the concrete chart types that actually render.
  - Data Studio tensile export no longer labels a plain box-based figure as `distribution_compare`; explicit outputs such as `box_strip_compare.pdf` now line up with the rendered figure type.
  - Opening legacy sessions/projects rewrites removed style/template ids to canonical ids instead of round-tripping them back into saved state.
- Risks:
  - Legacy `distribution_compare` entries that are migrated without inspectable source data fall back to `box`, which is conservative but may not match the exact historical auto-variant that would have been chosen with source access.
  - Any future caller that assumes `requested_template_id` and emitted/exported `template` ids must always match can regress if it bypasses the canonicalization layer.
  - Hidden reintroduction of alias ids in UI fixtures, Data Studio recipes, or recommendation copy would silently re-expand the public surface and needs contract/meta tests to stay in place.
- Rollback points:
  - `src/plot_contract.json`
  - `src/rendering/template_lifecycle.py`
  - `src/rendering/options.py`
  - `src/rendering/preflight.py`
  - `src/rendering/render_service.py`
  - `src/rendering/recommender.py`
  - `app/sidecar/routes_render.py`
  - `app/sidecar/export_manifest.py`
  - `src/data_studio/session.py`
  - `src/data_studio/comparison.py`
  - `src/data_studio/builtin/tensile.py`
  - `app/macos/Sources/Features/Plot/PlotSession.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
- Decision:
  - Public style/template surfaces must describe the real supported product semantics, while compatibility for legacy ids belongs only at the boundary normalization layer.
- Validation (executed):
  - `.venv/bin/python scripts/generate_plot_contract_docs.py`: passed
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`162 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`101 tests`)

### 2026-04-09 (Round Q): Native TIFF export orientation fix

- Scope:
  - Fixed the macOS native TIFF export rasterization path so PDF pages are drawn into the bitmap context without the extra translate + negative-Y scale that was vertically mirroring exported TIFF files.
  - Added a focused macOS regression test that generates a known red-top / blue-bottom PDF probe, exports it through `NativeExportCoordinator`, and samples the resulting TIFF pixels to ensure the exported image preserves vertical orientation.
  - Hardened the new test against AppKit bitmap coordinate confusion by sampling `NSBitmapImageRep` with its top-left origin and by using pure RGB probe colors instead of semantic system colors.
- User-visible impact:
  - TIFF exports from Plot now preserve the same top/bottom orientation as the PDF preview instead of appearing mirrored vertically in downstream viewers.
- Risks:
  - The native TIFF path still assumes single-page PDF export input; future multipage TIFF support would need explicit page-selection semantics rather than extending the current helper implicitly.
  - Any later reintroduction of a manual Core Graphics Y-axis flip inside `writeSinglePageTIFF(...)` can silently regress export orientation unless the new regression test remains in the suite.
- Rollback points:
  - `app/macos/Sources/Shared/Utilities/NativePanels.swift`
  - `app/macos/Tests/PlotSessionTests.swift`
- Decision:
  - Native TIFF export should preserve the PDF page coordinate orientation directly and let the bitmap/image destination own TIFF row ordering, because duplicating an extra Core Graphics Y-axis flip was the source of the mirrored output.
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests/testNativeTIFFExportPreservesPDFVerticalOrientation`: passed
  - Local AppKit bitmap sampling probe for `NSBitmapImageRep.colorAt(x:y:)` origin: confirmed `y=0` is top row
  - Manual source inspection of `NativeExportCoordinator.writeSinglePageTIFF(...)`: confirmed the mirrored export came from the removed translate + negative-Y scale pair

### 2026-04-09 (Round R): TIFF orientation metadata hardening + Data Studio inspector template recovery

- Scope:
  - Hardened native TIFF export by writing explicit top-left orientation metadata (`Orientation = 1`) alongside the already-correct rasterization transform, so downstream viewers do not have to infer TIFF row orientation.
  - Added a PlotSession regression assertion that reads TIFF metadata back through `CGImageSource` and checks both the general image orientation and the TIFF-specific orientation tag.
  - Added a PlotSession `effectiveTemplateID` fallback chain so inspector controls and preview refresh can recover the active template from staged external context or the latest preview/preflight/export payloads even if `selectedTemplateID` drifts to `nil`.
  - Synced Data Studio figure selection into the embedded `PlotSession` during family/template reconciliation and added a regression test that simulates the lost-template state while ensuring representative-curve axis controls still render and send updates with template `curve`.
- User-visible impact:
  - TIFF exports now carry an explicit upright orientation tag in addition to the corrected image buffer, reducing the chance that Preview or other TIFF consumers display the figure mirrored.
  - The Data Studio right inspector once again keeps the curve figure’s axis/style controls visible and editable instead of falling back to “Choose a template to edit figure controls.”
- Risks:
  - `effectiveTemplateID` is intentionally a recovery path, so future changes that leave stale preview/preflight payloads attached after a source swap could accidentally keep an old template visible longer than intended if preview context invalidation regresses.
  - TIFF metadata now declares orientation explicitly; if a future exporter starts generating already-tagged TIFFs upstream, double-normalization rules would need to stay consistent.
- Rollback points:
  - `app/macos/Sources/Shared/Utilities/NativePanels.swift`
  - `app/macos/Sources/Features/Plot/PlotSession.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `app/macos/Tests/PlotSessionTests.swift`
  - `app/macos/Tests/DataStudioSessionTests.swift`
- Decision:
  - Recoverable UI/editor state should derive from the latest authoritative render context rather than a single fragile selection slot, and TIFF outputs should declare the intended upright orientation explicitly instead of relying on viewer inference.
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests/testNativeTIFFExportPreservesPDFVerticalOrientation -only-testing:SciPlotGodMacTests/DataStudioSessionTests/testRepresentativeCurveInspectorControlsRecoverFromPreviewTemplateWhenSelectionStateDrifts`: passed
  - Local visual probe of a generated TIFF export: confirmed red top / blue bottom / upright text after conversion

### 2026-04-10 (Round S): Data Studio specimen filter shows elongation-first ranking

- Scope:
  - Reworked the macOS Data Studio specimen filter presentation so the default ranked list resolves a primary inspection metric from the active figure family and otherwise falls back to `Elongation`, instead of always foregrounding distance-from-mean.
  - Kept the Auto Keep 5 keep/out grouping intact, but changed the within-group order to sort by the resolved metric value so the default popover surfaces specimen values people actually compare against when deciding what to keep.
  - Simplified the advanced table by removing `Distance` and `Side` as first-class columns, moving filename into de-emphasized status text, and putting elongation / strength / modulus values first while the advanced list itself is now directly sorted by the resolved inspection metric.
  - Added a macOS regression assertion that the specimen filter now prefers elongation ordering on the tensile fixture and keeps the keep/out cutoff block stable.
- User-visible impact:
  - The specimen filter popover now shows tensile elongation values directly instead of making users infer them from filename, distance, and side fields.
  - Auto Keep 5 suggestions still behave the same, but the popover is easier to use because the visible rows are ordered around the metric the figure is focused on, with elongation as the default tensile fallback.
  - The Advanced section is less noisy: the triad values lead, while filename is still available as supporting context instead of dominating the row.
- Risks:
  - The current sort fallback assumes `Elongation` is the most useful default tensile inspection metric when no explicit figure metric is selected; if future workbook families need a different default, the fallback chain will need to become family-aware rather than tensile-biased.
  - Keep/out grouping is still driven by the baseline auto-filter recommendation, so users looking for a single globally sorted numeric list may still need the advanced manual override flow for edge cases.
- Rollback points:
  - `app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchSpecimenViews.swift`
  - `app/macos/Tests/DataStudioSessionTests.swift`
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`162 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`103 tests`)

### 2026-04-10 (Round T): Data Studio tensile legend de-scatter + inspector de-dup + preview edge smoothing

- Scope:
  - Updated curve candidate selection in `src/rendering/render_curve.py` so tensile-preserved small-panel curves with 4+ series do not prefer direct edge labels, preventing scattered label rendering in representative comparison previews.
  - Added a rendering regression test that locks the new behavior for small tensile curve panels with four series.
  - Removed the duplicate `Figure -> Type` control from `DataStudioInspectorView`, keeping figure-family switching only in the preview context bar chips.
  - Unified preview card clipping/shape usage across `PlotRefineView`, `Base64PDFPreviewView`, and `Base64PreviewImageView` with continuous rounded corners and anti-aliased border drawing to avoid left-edge corner artifacts after preview loads.
- User-visible impact:
  - Data Studio representative tensile comparisons now keep legend information in a centralized legend layout instead of floating per-curve labels.
  - The right inspector no longer repeats the top figure-family selector.
  - Preview card edges render smoothly after preview updates, including the left corner/edge path.
- Risks:
  - Tensile direct-label suppression is intentionally scoped to 4+ series; future recipes that want direct labels for high-count tensile overlays would need an explicit override path.
  - Inspector type removal assumes the top context-bar family chips remain visible and authoritative in all Data Studio preview states.
- Rollback points:
  - `src/rendering/render_curve.py`
  - `app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift`
  - `app/macos/Sources/Features/Plot/PlotRefineView.swift`
  - `app/macos/Sources/Shared/UI/PDFPreviewView.swift`
  - `app/macos/Sources/Shared/UI/Base64PreviewImageView.swift`
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`163 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`103 tests`)

### 2026-04-10 (Round U): Data Studio comparison-preview hot-path caching + regression guard

- Scope:
  - Added Data Studio comparison preview PDF cache (`LRUCache`) keyed by materialized comparison context key + recipe identity in `src/data_studio/comparison.py`.
  - Eliminated repeated re-rendering for unchanged compare previews by short-circuiting `preview_comparison_recipe(...)` to cached base64 PDF payload.
  - Added two protective tests in `tests/test_data_studio.py`:
    - `test_preview_data_studio_comparison_reuses_cached_pdf_for_same_context`
    - `test_preview_data_studio_comparison_cache_invalidates_on_specimen_state_change`
  - Produced benchmark before/after reports:
    - `docs/performance/benchmark-2026-04-10-before.json`
    - `docs/performance/benchmark-2026-04-10-after.json`
- User-visible impact:
  - Repeated Data Studio compare preview refreshes with unchanged group/specimen state become effectively instant.
  - No workflow or payload schema changes.
- Risks:
  - Process-local cache means no cross-process reuse.
  - If future context-key construction misses a semantic dependency, cache staleness risk appears.
- Rollback points:
  - `src/data_studio/comparison.py`
  - `tests/test_data_studio.py`
  - `docs/performance/benchmark-2026-04-10-before.json`
  - `docs/performance/benchmark-2026-04-10-after.json`
- Performance tactile target + conclusion:
  - Target:
    - `data_studio.preview p95 <= 0.01s` for unchanged repeated requests in the existing in-process benchmark harness.
  - Benchmark command:
    - `.venv/bin/python scripts/benchmark_workbench_perf.py --samples 30 --warmup 5 --output docs/performance/benchmark-2026-04-10-before.json`
    - `.venv/bin/python scripts/benchmark_workbench_perf.py --samples 30 --warmup 5 --output docs/performance/benchmark-2026-04-10-after.json`
  - Before:
    - `data_studio.preview p95=0.2549s`
  - After:
    - `data_studio.preview p95=0.0012s`
  - Conclusion:
    - target achieved with >99% p95 reduction on repeated unchanged preview path.
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`165 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`103 tests`)

### 2026-04-10 (Round V): Rendering inspection/dataset cache de-dup + export-path micro-optimization

- Scope:
  - Added rendering-layer runtime caches:
    - `src/rendering/dataset_models.py`: cached normalized dataset snapshots + `clear_normalized_dataset_cache`.
    - `src/rendering/recommendation.py`: cached input inspection/recommendation payloads + `clear_inspection_cache`.
    - `src/rendering/__init__.py`: exported the new cache-clear hooks.
  - Added regression tests in `tests/test_rendering_cache.py` for:
    - normalized-dataset cache hit on unchanged input
    - normalized-dataset cache invalidation on mtime change
    - inspect cache hit on unchanged input
    - inspect cache invalidation on mtime change
  - Captured benchmark reports:
    - `docs/performance/benchmark-2026-04-10-round-v-before.json`
    - `docs/performance/benchmark-2026-04-10-round-v-after.json`
- User-visible impact:
  - No workflow or payload schema change.
  - Repeated inspect/export paths avoid duplicate deterministic inference work for unchanged files; `plot.export` p95 improved in the in-process benchmark harness.
- Risks:
  - Cache invalidation still depends on file mtime; out-of-band edits that keep mtime unchanged can yield stale reuse.
  - Cache scope is process-local and is cleared on sidecar restart.
- Rollback points:
  - `src/rendering/dataset_models.py`
  - `src/rendering/recommendation.py`
  - `src/rendering/__init__.py`
  - `tests/test_rendering_cache.py`
  - `docs/performance/benchmark-2026-04-10-round-v-before.json`
  - `docs/performance/benchmark-2026-04-10-round-v-after.json`
- Performance tactile target + conclusion:
  - Target:
    - `plot.export p95 <= 0.245s` in the same in-process benchmark harness.
  - Benchmark command:
    - `.venv/bin/python scripts/benchmark_workbench_perf.py --samples 30 --warmup 5 --output docs/performance/benchmark-2026-04-10-round-v-before.json`
    - `.venv/bin/python scripts/benchmark_workbench_perf.py --samples 30 --warmup 5 --output docs/performance/benchmark-2026-04-10-round-v-after.json`
  - Before:
    - `plot.export p95=0.2463s`
  - After:
    - `plot.export p95=0.2427s`
  - Conclusion:
    - target achieved with a small but stable p95 reduction while preserving behavior and test matrix.
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`169 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`103 tests`)

## 6) Update Template (copy for next round)

Use this block for every new round:

```
### YYYY-MM-DD (Round X): <title>

- Scope:
- User-visible impact:
- Risks:
- Decision:
- Validation (commands + result):
```
