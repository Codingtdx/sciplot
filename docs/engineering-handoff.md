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

### 2026-04-10 (Round X): Data Studio comparison export now includes per-group filtered workbooks

- Scope:
  - Extended Data Studio comparison export so one `Export` now produces:
    - the existing comparison workbook
    - one filtered standard workbook per included workbook group
    - the selected figure outputs
  - Added a dedicated filtered-workbook writer in `src/data_studio/workbooks.py` that emits standard Data Studio sheets:
    - `DataStudio_Metadata`
    - `Representative_Curve`
    - `All_Curves`
    - `All_Specimens`
    - `Summary`
    - per-metric `*_Replicates`
  - Filtered workbooks now persist source metadata plus representative-specimen identity so re-import / workbook-preview keeps the committed manual representative selection instead of silently re-auto-picking.
  - Extended sidecar/macOS comparison-export response handling so the export result UI lists the generated filtered workbooks alongside the comparison workbook and figure outputs.
- User-visible impact:
  - Data Studio export bundles now include one filtered standard workbook per included workbook group, not just the comparison workbook and figures.
  - Those filtered workbooks can be imported back into Data Studio and keep the committed representative curve choice.
  - Numeric cells in the new filtered workbooks are currently normalized to two decimal places for a consistent export surface.
- Risks:
  - The filtered-workbook writer currently assumes the source workbook can already materialize a standard `FilteredWorkbookContext`; future non-standard workbook families would need an explicit compatibility policy instead of silent schema drift.
  - Filtered-workbook numeric formatting is intentionally separate from the existing comparison workbook formatting; future requests to unify them should be handled deliberately, not by widening this path implicitly.
- Rollback points:
  - `src/data_studio/models.py`
  - `src/data_studio/__init__.py`
  - `src/data_studio/workbooks.py`
  - `src/data_studio/comparison.py`
  - `app/sidecar/schemas_data_studio.py`
  - `app/sidecar/schemas.py`
  - `app/sidecar/routes_data_studio.py`
  - `app/macos/Sources/Infrastructure/SidecarModelsDataStudio.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift`
  - `tests/test_data_studio.py`
  - `tests/test_sidecar_data_studio.py`
  - `app/macos/Tests/TestPayloads.swift`
  - `app/macos/Tests/DataStudioSessionTests.swift`
- Decision:
  - Reused the same committed `specimen_states` and `load_filtered_workbook_context(...)` path that already drives compare/export, instead of adding a second export-only state chain or a new endpoint.
  - Rejected alternatives:
    - exporting ad-hoc Excel sheets directly from the comparison workbook response: rejected because it would bypass the existing filtered workbook truth source and risk schema drift from normal Data Studio workbooks
    - adding a separate filtered-workbook export toggle or endpoint: rejected because one export action should reflect one committed compare state and emit the full artifact bundle
    - changing comparison workbook numeric formatting together with filtered-workbook formatting: rejected this round to keep scope tight and avoid changing an existing export contract unintentionally
  - Boundary:
    - only the new filtered-workbook artifacts normalize numeric cells to two decimal places
    - comparison workbook export behavior otherwise stays unchanged
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`175 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`104 tests`)

### 2026-04-10 (Round Y): Legacy tensile workbooks now recover stale curve sheets from raw source files

- Scope:
  - Hardened `src/data_studio/workbooks.py` specimen-bundle loading for `builtin/tensile` workbooks with `source_files` metadata.
  - When workbook `All_Curves` data is materially shorter than the original raw-source curve and also diverges from the specimen `Elongation` scalar, Data Studio now prefers the raw CSV curve recovered from `source_files`.
  - Added regression coverage for the exact legacy failure mode: a workbook whose `All_Curves`/`Representative_Curve` x-values were written too short even though the referenced raw tensile CSVs still contain the correct strain axis.
- User-visible impact:
  - Old tensile workbooks that previously drew visibly too-short curves in Data Studio can now self-heal on import as long as their `source_files` still exist.
  - Compare preview / representative-curve selection / export now use the repaired curves instead of the stale workbook curve sheet.
- Risks:
  - This repair path currently activates only for tensile workbooks with reachable `source_files`; if the raw files are missing, Data Studio still falls back to the workbook's stored curve sheets.
  - The repair heuristic intentionally favors raw curves only when they are clearly closer to the specimen elongation metric than the stored workbook curve, to avoid overriding healthy workbooks.
- Rollback points:
  - `src/data_studio/workbooks.py`
  - `tests/test_data_studio.py`
- Decision:
  - Repaired legacy curve-sheet drift at import time rather than mutating the workbook file on disk, because the app needs to render old workbooks correctly without destructive rewrite side effects.
  - Rejected alternatives:
    - treating the issue as a pure plotting bug: rejected because the renderer was faithfully plotting the stale curve data already stored in the workbook
    - always ignoring workbook curve sheets and always reparsing raw sources: rejected because prepared workbooks should remain self-contained when their stored curve data is already healthy
  - Boundary:
    - the self-heal applies only to specimen-level curve recovery for supported tensile workbooks
    - it does not silently rewrite the original workbook file contents
- Troubleshooting note:
  - Symptom:
    - tensile workbook `Elongation` summary shows `40%+`, but representative or specimen curves stop around `15%~20%`
  - Likely cause:
    - the workbook was generated by an older import path that wrote the wrong strain column into `All_Curves` / `Representative_Curve`
  - Fix:
    - if metadata `source_files` still point to the raw CSV exports, current Data Studio will now recover the correct curves automatically on import
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`176 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`104 tests`)

### 2026-04-10 (Round Z): Data Studio reverts raw-source curve recovery and treats workbook data as authoritative

- Scope:
  - Removed the temporary tensile-specific import-time fallback in `src/data_studio/workbooks.py` that reparsed raw `source_files` to replace stale workbook curve sheets.
  - Removed the matching regression test that asserted automatic curve recovery from raw source files.
  - Updated `README.md` and `AGENTS.md` so the boundary is explicit: once a workbook is imported, preview / compare / export consume workbook data only.
- User-visible impact:
  - Data Studio no longer silently repairs workbook curve data from raw `source_files`.
  - If a workbook stores an incorrect curve sheet, the UI will now reflect the workbook as-is instead of reaching back to the original CSV exports.
- Risks:
  - Legacy workbooks with stale `All_Curves` / `Representative_Curve` data remain stale until they are rebuilt or re-exported from a correct source.
  - This is intentional: correctness now means “faithful to workbook,” not “best-effort recovery from provenance metadata.”
- Rollback points:
  - `src/data_studio/workbooks.py`
  - `tests/test_data_studio.py`
  - `README.md`
  - `AGENTS.md`
- Decision:
  - Workbook contents are the only truth source after import. `source_files` are provenance metadata only and must not silently affect rendered curves or derived compare/export behavior.
  - Rejected alternatives:
    - keep best-effort raw-source repair for obviously broken workbooks: rejected because it violates the user's requirement that Data Studio read from workbook only
    - rewrite workbook files in place to “fix” stale curves: rejected because destructive mutation is even less acceptable than a silent fallback
  - Boundary:
    - if a workbook is wrong, the fix is to regenerate or replace that workbook, not to reach outside it during preview/import
- Troubleshooting note:
  - Symptom:
    - workbook summary metrics and workbook curve sheets appear inconsistent
  - Current policy:
    - Data Studio will still honor the workbook as imported
  - Fix:
    - regenerate the workbook from the correct raw inputs instead of expecting import-time healing from `source_files`
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`176 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`104 tests`)

## 6) Update Template (copy for next round)

### 2026-04-10 (Round W): Data Studio manual representative-curve selection inside specimen filter

- Scope:
  - Extended Data Studio specimen state payloads/models/schemas with `selected_as_representative` and kept the same single `specimen_states` chain for:
    - `src/data_studio/workbooks.py` filtered preview recomputation
    - `src/infrastructure/persistence/data_studio_comparison_contexts.py` context cache key invalidation
    - sidecar workbook-preview / comparison-context / comparison-preview / comparison-export request models
    - macOS session normalization / restore / compare-export request payloads
  - Kept existing filtered-statistics behavior and added regressions proving that committed specimen filters still recompute mean/std and that manual representative selection changes the actual exported representative curve.
  - Added macOS Data Studio filter-panel support in `Advanced` only:
    - draft/apply/revert semantics now cover representative-curve selection too
    - `Use Auto Representative` clears the manual pin and returns to automatic representative selection
    - session synchronization preserves the committed representative pin across preview refreshes instead of losing it when sidecar preview responses hydrate local state
- User-visible impact:
  - Data Studio specimen filter `Advanced` now lets users manually pin the representative curve from an included specimen.
  - Compare/export honor that manual representative curve after `Apply Changes`.
  - Default specimen-filter popover remains the ranked `Auto Keep 5` list and does not expose representative-curve copy outside `Advanced`.
- Risks:
  - Manual representative selection is only valid for included specimens with a curve preview; excluding the pinned specimen or losing its curve falls back to automatic representative selection.
  - Because the representative pin is now part of `specimen_states`, any future code that overwrites committed specimen state from preview payloads without preserving local flags can regress this behavior.
- Rollback points:
  - `src/data_studio/models.py`
  - `src/data_studio/session.py`
  - `src/data_studio/workbooks.py`
  - `src/infrastructure/persistence/data_studio_comparison_contexts.py`
  - `app/sidecar/schemas_data_studio.py`
  - `app/macos/Sources/Infrastructure/SidecarModelsDataStudio.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchSpecimenViews.swift`
  - `tests/test_data_studio.py`
  - `tests/test_sidecar_data_studio.py`
  - `app/macos/Tests/TestPayloads.swift`
  - `app/macos/Tests/DataStudioSessionTests.swift`
- Decision:
  - Reused committed `specimen_states` as the only persisted/requested source of truth for manual representative selection instead of introducing a second representative-only state list or a new endpoint.
  - Rejected alternatives:
    - a separate representative-selection endpoint: rejected because compare/export/cache invalidation would then need cross-endpoint state merging
    - macOS-only local representative state: rejected because it would drift from sidecar compare/export semantics and break save/open round-trips
  - Boundary:
    - baseline preview still stays purely for Auto Keep 5 ranking and Advanced scoring context
    - only committed `specimen_states` can affect compare/export/materialized context reuse
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`173 passed`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`104 tests`)

### 2026-04-10 (Round AA): Data Studio filtered workbook keeps workbook-only representative curves and exports curve sheets at four decimals

- Scope:
  - Split filtered-workbook numeric formatting in `src/data_studio/workbooks.py` so `Representative_Curve` and `All_Curves` export with four decimal places while specimen / summary / replicate tables remain at two decimal places.
  - Updated Python and sidecar regression coverage to assert the new mixed-format export contract.
  - Updated `README.md` and `AGENTS.md` to document the workbook-only representative-curve policy together with the new curve-sheet precision rule.
- User-visible impact:
  - Re-exported filtered workbooks now preserve more curve precision (`0.0000`, `2.0000`, etc.) without changing the two-decimal presentation of summary/specimen tables.
  - Manual representative selection still works from committed `specimen_states`, but the rendered representative line remains whatever curve is stored in the workbook for that specimen.
- Risks:
  - Users may still expect the displayed elongation metric to equal the curve endpoint; if a workbook stores inconsistent `All_Specimens` vs `All_Curves` data, Data Studio will still honor the workbook and show that inconsistency.
  - The mixed-format export contract is now intentional; widening four-decimal formatting to non-curve sheets later would be a user-visible change and should be treated as such.
- Decision:
  - Kept the workbook-only boundary intact: representative-curve rendering must follow the selected specimen's stored workbook curve, not the elongation metric cell and not the original raw source files.
  - Rejected alternatives:
    - “fix” the displayed line by stretching the curve to match the elongation metric: rejected because that would fabricate curve data not present in the workbook
    - widen all filtered-workbook numeric tables to four decimals: rejected because the user's ask was specifically about curve precision, while two-decimal summary tables remain easier to read
- Troubleshooting note:
  - Symptom:
    - a specimen row shows `Elongation` around `40%+`, but manually selecting it as representative still plots a curve that ends around `18%`
  - Likely cause:
    - the workbook stores inconsistent data: the specimen summary row and the matching `All_Curves` series disagree for that filename/specimen id
  - Current behavior:
    - Data Studio does select that specimen correctly, then renders the exact curve stored in the workbook for it
  - Fix:
    - regenerate or replace the workbook so `All_Specimens`, `All_Curves`, and `Representative_Curve` agree internally
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`175 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`104 tests`)

### 2026-04-10 (Round AB): macOS export UX unified around the Data Studio pattern

- Scope:
  - Unified macOS export interaction across `Plot`, `Composer`, and `Code Console` around the Data Studio inspector pattern: toolbar `Export` stays global, while inspectors now expose `Section("Actions")` with `Advanced -> Reveal Output / Latest Export`.
  - Added one shared macOS exported-file presentation model for flat latest-export lists and switched Plot / Composer / Code Console sessions to expose that state directly from their native session layer.
  - Switched Plot / Composer figure export to explicit `format -> destination` flow and kept single-file rename vs multi-file base-stem semantics intact.
  - Replaced `CodeConsoleSession.exportCurrentOutputs()` folder reveal behavior with real export of the latest run's generated PDF figure files only; managed output-folder reveal remains in the Outputs panel.
  - Updated macOS guide/help copy plus app-level export command/help text to describe workbench-specific export behavior.
- User-visible impact:
  - Plot / Composer / Code Console now export from the toolbar and inspector with the same Data Studio-style flow.
  - Plot / Composer / Code Console prompt for `PDF` or `300 dpi TIFF` before the destination chooser opens.
  - Code Console can now export the latest run's generated figures instead of only revealing the output folder.
  - Inspectors now show a flat `Latest Export` list for exported figure files and keep reveal actions inside `Advanced`.
- Risks:
  - Code Console export intentionally ignores non-PDF artifacts from the run output directory; if runtime-generated figure formats expand beyond PDF, macOS export logic must be updated in the same round.
  - Multi-output export naming now depends on the shared deterministic-suffix helper; changing that helper will affect both Plot and Code Console exported filenames.
  - The Outputs panel and inspector now intentionally distinguish managed outputs from user export destinations; future UI changes should not collapse those two concepts back together.
- Rollback points:
  - `app/macos/Sources/Shared/UI/StateViews.swift`
  - `app/macos/Sources/Shared/Utilities/NativePanels.swift`
  - `app/macos/Sources/App/AppModel.swift`
  - `app/macos/Sources/App/AppCommands.swift`
  - `app/macos/Sources/App/RootSplitView.swift`
  - `app/macos/Sources/Features/Plot/PlotSession.swift`
  - `app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
  - `app/macos/Sources/Features/Composer/ComposerSession.swift`
  - `app/macos/Sources/Features/Composer/ComposerInspectorView.swift`
  - `app/macos/Sources/Features/Composer/ComposerWorkbenchView.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleSession.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleContextView.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift`
  - `app/macos/Tests/PlotSessionTests.swift`
  - `app/macos/Tests/ComposerSessionTests.swift`
  - `app/macos/Tests/CodeConsoleSessionTests.swift`
  - `app/macos/Tests/AppModelTests.swift`
  - `README.md`
  - `AGENTS.md`
- Decision:
  - Reused Data Studio's inspector/export structure as the macOS export authority instead of introducing a second shared “export shell” abstraction or leaving Plot / Composer / Code Console on their older ad-hoc flows.
  - Rejected alternatives:
    - keep Code Console toolbar export as folder reveal and add a second figure-export button elsewhere: rejected because it preserves ambiguous export semantics and diverges from the user's requested unified flow
    - unify on a destination-first save panel for all workbenches: rejected because Data Studio already establishes format-first figure export semantics and the user explicitly asked to align around that model
    - export every Code Console artifact type: rejected for this round because the managed runner truth source currently treats PDF figure files as the supported figure-export surface, while csv/json/log outputs remain handoff artifacts
  - Boundary:
    - Data Studio keeps bundle export semantics as-is
    - Plot / Composer / Code Console share figure-export interaction only; no sidecar schema or backend contract changed
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests -only-testing:SciPlotGodMacTests/ComposerSessionTests -only-testing:SciPlotGodMacTests/CodeConsoleSessionTests -only-testing:SciPlotGodMacTests/AppModelTests`: passed (`51 tests`)
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`175 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`109 tests`)

### 2026-04-10 (Round AC): macOS GUI microcopy trim and header/layout tightening

- Scope:
  - Trimmed redundant inline microcopy across `app/macos` workbench surfaces for `Plot`, `Data Studio`, `Composer`, and `Code Console`, with matching cleanup of shared state/view models that only existed to feed deleted subtitle or caption text.
  - Updated shared placeholder/export primitives in `app/macos/Sources/Shared/UI/StateViews.swift` plus list helpers in `app/macos/Sources/Shared/UI/SortableSeriesListView.swift` so empty/busy states can render title-only and inspector export lists no longer repeat a nested `Latest Export` heading.
  - Collapsed Plot / Data Studio / Code Console top bars to single-row headers with icon-only live status affordances, removed template-rail/specimen-filter/import-sheet/footer/helper microcopy, and tightened Composer library / quick-action / inspector presentation to rely on primary labels, badges, and disabled-with-help behavior instead of explanatory footnotes.
  - Updated macOS regression tests to assert behavior/state (`liveStatusSymbol`, ranked keep rows, generated file availability, empty-state behavior) rather than removed copy strings.
- User-visible impact:
  - The supported macOS workbenches now render with materially less secondary caption text and fewer stacked subtitle rows.
  - Status narration like `Top 5`, `Latest Export`, prompt/output summaries, specimen-filter summaries, draft-warning paragraphs, and repeated empty-state descriptions no longer clutter the main surfaces.
  - Inspector/export/help affordances remain intact: toolbar `Help`, guide sheets, and `.help(...)` explanations still exist, while disabled actions still explain why they are unavailable.
- Risks:
  - Because several views now rely on title-only empty/busy states, any future surface that still depends on descriptive helper text for orientation will need an explicit decision instead of inheriting the old default.
  - The specimen-filter presentation model is slimmer; future UI work should not reintroduce a second summary string or draft-status paragraph outside the existing badge/help surfaces.
  - Manual visual verification for long filenames, popover spacing, and sheet layout was not executed in this terminal-only pass, so any remaining polish issues would most likely be purely visual rather than contract/runtime failures.
- Rollback points:
  - `app/macos/Sources/Shared/UI/StateViews.swift`
  - `app/macos/Sources/Shared/UI/SortableSeriesListView.swift`
  - `app/macos/Sources/App/Workbench.swift`
  - `app/macos/Sources/Features/Plot/PlotSession.swift`
  - `app/macos/Sources/Features/Plot/PlotSessionTypes.swift`
  - `app/macos/Sources/Features/Plot/PlotTemplateView.swift`
  - `app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
  - `app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `app/macos/Sources/Features/Plot/PlotRefineView.swift`
  - `app/macos/Sources/Features/Plot/PlotImportView.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchSpecimenViews.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift`
  - `app/macos/Sources/Features/Composer/ComposerSession.swift`
  - `app/macos/Sources/Features/Composer/ComposerAssetBrowserView.swift`
  - `app/macos/Sources/Features/Composer/ComposerCanvasView.swift`
  - `app/macos/Sources/Features/Composer/ComposerInspectorView.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleSession.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleContextView.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleEditorView.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift`
  - `app/macos/Tests/PlotSessionTests.swift`
  - `app/macos/Tests/DataStudioSessionTests.swift`
  - `app/macos/Tests/CodeConsoleSessionTests.swift`
- Decision:
  - Chose to remove redundant inline microcopy at the point of presentation and delete the matching derived-state helpers instead of introducing a new shared “copy suppression” abstraction.
  - Rejected alternatives:
    - keep the old subtitle/status strings but hide them conditionally: rejected because the extra state and copy plumbing would still exist and keep the UI model noisy
    - centralize a second layer of macOS-only presentation summaries: rejected because it would add another truth source for status/copy, directly against the current first-principles cleanup rules
  - Boundary:
    - this round is macOS-only and does not change sidecar routes, plot contract, or backend semantics
    - explicit help surfaces remain intentionally excluded from the trim
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`175 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`109 tests`)
  - Manual macOS UI verification for long filenames / popovers / import sheets / help tooltips: not executed in this terminal pass

### 2026-04-10 (Round AD): macOS workbench title deduplication

- Scope:
  - Removed the detail-pane fallback workbench title in `app/macos/Sources/App/RootSplitView.swift` so the selected sidebar item remains the only generic workbench label source.
  - Updated `app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`, `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`, and `app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift` to render their top headers only when real document context exists, instead of falling back to generic titles like `Plot`, `Data Studio`, or `Code Console`.
  - Kept the native sidebar application title (`SciPlot God`) and help-sheet navigation titles intact because they are utility/container labels rather than duplicated content headers.
- User-visible impact:
  - Plot / Composer / Data Studio / Code Console no longer show a second generic title in the main content area when no file or workbook context is selected.
  - When a real source file or focused workbook exists, the content header now shows only that contextual name, which matches the native macOS split-view pattern more closely.
- Risks:
  - This round was validated by build/test only; a manual visual pass was not run, so any remaining title-spacing issue would be presentation-only.
  - Plot / Data Studio / Code Console now rely on contextual document names for their top bars; if a future flow needs an always-visible header, that should be an explicit UX decision instead of reintroducing a generic fallback label.
- Rollback points:
  - `app/macos/Sources/App/RootSplitView.swift`
  - `app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift`
- Decision:
  - Adopted a single-title-source rule for workbench identity: sidebar selection owns the generic workbench label, while the detail pane may only show contextual document/workbook names.
  - Rejected alternatives:
    - keep both layers and restyle one of them smaller: rejected because it preserves duplicate semantics and still reads as noisy UI
    - replace the removed generic header with a second custom title bar: rejected because macOS already provides the split-view/sidebar identity affordance natively
  - Boundary:
    - this round does not change workflows, sidecar behavior, or inspector/export affordances
    - the sidebar app title and help/guide sheet titles remain intentionally unchanged
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`175 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`109 tests`)
  - Manual macOS UI verification for duplicate workbench titles: not executed in this terminal pass

### 2026-04-13 (Round AE): Data Studio launch cancellation no longer surfaces as an error

- Scope:
  - Updated `app/macos/Sources/Features/DataStudio/DataStudioSession.swift` so `refreshTemplates()` treats task cancellation as a non-user-facing control-flow event instead of copying `CancellationError.localizedDescription` into `errorMessage`.
  - Added `testRefreshTemplatesCancellationDoesNotSurfaceError` in `app/macos/Tests/DataStudioSessionTests.swift` to lock the startup behavior: cancelled template refresh leaves the session idle, empty, and error-free.
- User-visible impact:
  - Opening `Data Studio` and doing nothing no longer shows `The operation couldn’t be completed. (Swift.CancellationError error 1.)` when SwiftUI cancels the initial template-refresh task during view/task lifecycle changes.
  - Real template-loading failures still surface through the existing diagnostic banner.
- Risks:
  - This round only suppresses cancellation for the template bootstrap path; if future async entrypoints introduce the same mistake elsewhere, they still need their own explicit cancellation handling.
  - Manual UI verification against the exact launch sequence from the screenshot was not run after the fix; validation here is code-path and test based.
- Rollback points:
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `app/macos/Tests/DataStudioSessionTests.swift`
- Decision:
  - Treat `CancellationError`, URL cancellation, and user-cancelled Cocoa errors as lifecycle/control-flow signals, not actionable GUI failures, when the Data Studio template bootstrap task ends early.
  - Rejected alternatives:
    - keep surfacing the raw Swift cancellation text: rejected because it is implementation leakage rather than meaningful user feedback
    - blanket-suppress every Data Studio error: rejected because genuine template-fetch failures still need to stay visible
  - Boundary:
    - only the automatic template refresh path changed
    - no sidecar contract, import workflow, or comparison/export semantics changed
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/DataStudioSessionTests`: passed (`42 tests`)
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`175 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`110 tests`)
  - Manual macOS UI verification for the reported launch-only banner: not executed in this terminal pass

### 2026-04-14 (Round AF): Collapse duplicate grouped-bar semantics into canonical `bar`

- Scope:
  - Removed public `grouped_bar_error` from `src/plot_contract.json`, kept `bar` as the only public filled mean+error categorical template, and made both `grouped_bar_error` and `grouped_bar_compare` ingress-only compatibility ids that normalize immediately to `bar` through `src/rendering/template_lifecycle.py`.
  - Added explicit `presentation_kind` metadata to the plot contract and sidecar meta payloads so GUI thumbnail rendering consumes backend truth instead of inferring chart families from template-id substrings.
  - Simplified the Python rendering path by deleting the old grouped-bar renderer branch, folding recommendation/preflight/render/export behavior onto canonical `bar`, and removing the dead `run_code_console_script_legacy` wrapper from `src/code_console_service.py`.
  - Updated Data Studio recipe/session normalization and macOS Plot/Data Studio sessions so legacy grouped-bar ids migrate to `bar` before labels, thumbnails, recipe selection, export filenames, or persisted state are emitted.
  - Regenerated `docs/plot_contract.md` and updated `README.md`, `AGENTS.md`, and `docs/data-to-template-v1-handoff.md` to reflect the new public template surface and backend-driven presentation metadata.
- User-visible impact:
  - Plot and Data Studio no longer present `grouped_bar_error` as a separate public chart choice; the canonical mean+error categorical option is now just `bar`.
  - Legacy projects or saved selections that still reference `grouped_bar_error` / `grouped_bar_compare` are upgraded to `bar` during restore instead of round-tripping those removed public ids back into UI state or exported filenames.
  - Plot template thumbnails no longer collapse multiple stats templates into the same local guess based on name matching; they now follow explicit backend `presentation_kind` metadata.
  - Data Studio figure-template labels now come from backend recipe/template truth instead of a second hardcoded macOS label table.
- Risks:
  - `bar.allowed_sizes` now includes `120x55` to preserve historical grouped-bar wide-layout behavior under the canonical template id; future contract edits must keep that size if wide stats panels remain a supported workflow.
  - Compatibility ids remain intentionally accepted at ingress, so any future caller that bypasses canonicalization and persists raw requested ids can silently reintroduce duplicate public semantics.
  - Manual visual verification of the refreshed Plot template gallery and Data Studio figure picker was not run in this terminal-only pass; remaining risk is presentation polish, not backend/schema correctness.
- Rollback points:
  - `src/plot_contract.json`
  - `src/plot_contract.py`
  - `app/sidecar/schemas_meta.py`
  - `src/rendering/template_lifecycle.py`
  - `src/rendering/recommender.py`
  - `src/rendering/preflight.py`
  - `src/rendering/render_registry.py`
  - `src/rendering/render_stats.py`
  - `src/data_studio/comparison.py`
  - `src/data_studio/session.py`
  - `src/code_console_service.py`
  - `app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `app/macos/Sources/Features/Plot/PlotSession.swift`
  - `app/macos/Sources/Features/Plot/PlotTemplateView.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
- Decision:
  - Public chart semantics must map one-to-one to actual rendered behavior. Because `grouped_bar_error` and `bar` rendered the same default figure for the same replicate-table input, the duplicate id was removed from the public surface and retained only as a compatibility alias that normalizes at the boundary.
  - Rejected alternatives:
    - keep both ids public and “document the difference later”: rejected because the contract, recommendation payloads, thumbnails, and saved state would continue advertising a semantic distinction that the renderer does not actually honor
    - let macOS keep guessing thumbnail kind and label text locally: rejected because it creates a second business-meaning table outside the contract and had already drifted on grouped-bar templates
    - keep the grouped-bar renderer branch around “just in case”: rejected because it preserved dead-path complexity after canonicalization made the branch unreachable in supported flows
  - Boundary:
    - compatibility ids are still accepted at ingress, but they must not be emitted back out via `/meta`, `/plot-contract`, recommendation payloads, Data Studio recipes/exports, macOS gallery state, or persisted session state
    - `presentation_kind` is presentation metadata only; it does not create a second render contract or override the canonical template id
- Validation (executed):
  - `.venv/bin/python scripts/generate_plot_contract_docs.py`: passed
  - `.venv/bin/python -m pytest tests/test_plot_contract.py tests/test_sidecar_schema_contract.py tests/test_rendering_template_lifecycle.py tests/test_rendering_recommender.py tests/test_recommendation_policy.py tests/test_rendering_services.py tests/test_data_studio.py tests/test_sidecar_data_studio.py`: passed (`103 passed, 5 warnings`)
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/SchemaDecodingTests -only-testing:SciPlotGodMacTests/PlotSessionTests -only-testing:SciPlotGodMacTests/DataStudioSessionTests`: passed (`66 tests`)
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`176 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`114 tests`)
  - Manual macOS UI verification for the updated Plot gallery/Data Studio figure picker: not executed in this terminal pass

### 2026-04-14 (Round AG): Data Studio GUI presentation cleanup and session split

- Scope:
  - Replaced the remaining implicit Data Studio import/template-editor workflow toggles with the single typed `importFlow` state carried by `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`, and kept the sheet entrypoints (`beginImportFlow`, `goBackInImportWizard`, resolver/template-editor transitions, importer presentation) routed through that one state machine.
  - Added typed Data Studio presentation payloads in `app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift` so resolver/template-editor cards, preview captions, selected summary rows, suggestion location metadata, and button availability all come from session-built presentation instead of duplicated SwiftUI helper logic.
  - Split the large Data Studio session implementation into responsibility files:
    - `app/macos/Sources/Features/DataStudio/DataStudioSessionImportTemplate.swift`
    - `app/macos/Sources/Features/DataStudio/DataStudioSessionSpecimenFilter.swift`
    - `app/macos/Sources/Features/DataStudio/DataStudioSessionComparison.swift`
    - root `app/macos/Sources/Features/DataStudio/DataStudioSession.swift` now acts as the state shell, initializer, and shared undo/cancellation utility host
  - Split the oversized Data Studio view layer so import sheets and template-editor UI live outside `DataStudioWorkbenchView.swift`, via:
    - `app/macos/Sources/Features/DataStudio/DataStudioImportWorkflowViews.swift`
    - `app/macos/Sources/Features/DataStudio/DataStudioTemplateEditorViews.swift`
  - Unified suggestion-card chrome and removed dead location plumbing by having cards render backend/session-provided location text only when it exists, while the preview table now always surfaces the active preview caption.
  - Moved specimen-filter action gating onto typed `ActionAvailability` in session presentation so `Use Auto Keep 5`, `Turn Off`, `Apply Changes`, `Use Auto Representative`, and `Revert` all use the same disabled-reason source instead of view-local guard logic.
  - Added targeted regression coverage in `app/macos/Tests/DataStudioSessionTests.swift` for resolver/template-editor presentation text, import flow transitions, specimen-filter action availability reasons, and bulk auto-keep help text.
- User-visible impact:
  - Resolver and create-template sheets now give consistent disabled reasons for key actions instead of silently graying out buttons.
  - Data Studio suggestion cards show stable location metadata and the template-editor preview column now keeps its active caption visible.
  - `Auto Keep 5 All` now advertises how many workbook groups it will touch, matching the actual eligible session scope.
  - No sidecar endpoint, schema, or plot-contract payload changed in this round.
- Risks:
  - The session logic is now layered across multiple files, but it is still one large observable type; future refactors should avoid turning the new split into cross-file hidden coupling.
  - A few helpers that were formerly `private` are now module-visible to support the file split; future edits should keep them Data Studio-internal and avoid reusing them as generic app utilities.
  - Manual macOS visual verification of the restructured import/template/specimen-filter surfaces was not executed in this terminal pass, so residual risk is presentation polish rather than schema/runtime correctness.
- Rollback points:
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSessionImportTemplate.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSessionSpecimenFilter.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSessionComparison.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioImportWorkflowViews.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioTemplateEditorViews.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchSpecimenViews.swift`
  - `app/macos/Tests/DataStudioSessionTests.swift`
  - `app/macos/SciPlotGod.xcodeproj/project.pbxproj`
- Decision:
  - Data Studio GUI semantics now follow a single-source rule: import flow state lives in one typed state machine, and resolver/template/specimen-filter labels plus button gating live in typed session presentation models rather than being recomputed inside SwiftUI views.
  - Rejected alternatives:
    - keep `DataStudioSession.swift` as a 3000+ line omnibus file and only extract the obvious SwiftUI sheets: rejected because the view cleanup would still leave the business-flow ownership and presentation truth split across one massive file
    - keep specimen-filter disabled reasons as ad hoc `.help(...)` branches in `DataStudioWorkbenchSpecimenViews.swift`: rejected because the UI would still own business-meaning decisions that should stay with session state
    - preserve the older parallel import/template booleans and “just keep them in sync”: rejected because they encode an implicit state machine and make back/cancel/import-panel transitions harder to reason about and test
  - Boundary:
    - this round did not change sidecar endpoints, plot-contract data, or the canonical Plot/Data Studio workflow definitions
    - the file split is internal macOS structure work only; external saved-state and API semantics remain unchanged
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/DataStudioSessionTests`: passed (`47 tests`)
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`176 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`117 tests`)
  - Manual macOS visual QA checklist for this round (not executed in terminal pass):
    - empty session and non-empty session both enter the single import wizard correctly
    - resolver/create-template sheet titles, back chain, and disabled button explanations read cleanly
    - suggestion cards show hover/selected state, location metadata, and acceptable truncation for long labels
    - preview block table and advanced disclosure maintain clear hierarchy after the file split
    - inspector `Figure Template`, `Open in Plot`, and `Export Bundle` affordances still read consistently after the session split
    - specimen-filter primary and advanced buttons expose the expected disabled help text

### 2026-04-14 (Round AH): Plot / Composer / Code Console GUI parity cleanup

- Scope:
  - Brought the remaining three macOS workbenches in line with the Data Studio single-source/disabled-with-explanation rule without changing any sidecar or plot-contract surface.
  - Plot:
    - upgraded `app/macos/Sources/Features/Plot/PlotSessionTypes.swift` `PlotTemplateGalleryItem` into a real presentation payload carrying backend description, thumbnail kind, aspect ratio, and `ActionAvailability`
    - moved Plot template-card disabled reasons into `app/macos/Sources/Features/Plot/PlotSession.swift` so the gallery no longer guesses why templates are unavailable before inspect
    - added typed `resetSeriesOrderAvailability` so legend reset uses the same truth source as the reorderability decision, and removed the dead `latestExportDestinationDescription`
  - Composer:
    - added `ComposerInspectorEditPresentation` in `app/macos/Sources/Features/Composer/ComposerSessionTypes.swift`
    - centralized merge / unmerge / place / remove / manual-label gating in `app/macos/Sources/Features/Composer/ComposerSession.swift`
    - rewired both `ComposerInspectorView.swift` and the board quick-action popover in `ComposerCanvasView.swift` to consume those typed availabilities instead of scattered booleans
  - Code Console:
    - added typed editor/source/output presentations in `app/macos/Sources/Features/CodeConsole/CodeConsoleSession.swift`
    - rewired `CodeConsoleEditorView.swift`, `CodeConsoleContextView.swift`, `CodeConsoleOutputsView.swift`, and `CodeConsoleWorkbenchView.swift` to consume session-provided availability/help instead of local guard logic
    - removed the extra Outputs-panel `Reveal Output Folder` button so reveal/export affordances stay concentrated in the inspector `Actions -> Advanced` path as documented
    - tightened `revealManagedOutputFolder()` so Code Console reveal actions no longer silently fall back to the bound source file when no managed output exists
  - Added regression coverage in:
    - `app/macos/Tests/PlotSessionTests.swift`
    - `app/macos/Tests/ComposerSessionTests.swift`
    - `app/macos/Tests/CodeConsoleSessionTests.swift`
- User-visible impact:
  - Plot template cards now explain why they are unavailable before inspect, and legend reset explains when the current legend order is already canonical.
  - Composer merge/unmerge/place/remove/manual-label controls now disable with concrete help instead of leaving gray buttons with no reason.
  - Code Console `Refresh`, `Copy Prompt`, `Restore Starter`, `Run Script`, source open/reveal, generated-file open/reveal, and inspector `Reveal Output` now all share stable disabled reasons from session state.
  - Code Console no longer exposes a second reveal-output affordance in the Outputs panel; export/reveal stays anchored in the inspector `Actions` section as intended.
- Risks:
  - Plot/Composer/Code Console now rely more heavily on session-built presentation state; future GUI changes that bypass those payloads can easily reintroduce view-local business logic drift.
  - Code Console reveal semantics are now stricter: when no managed output exists, reveal no longer falls back to the bound source file. This matches the documented workflow, but any caller that implicitly relied on the old fallback will need to use the source buttons instead.
  - Manual visual verification of the refreshed Plot/Composer/Code Console surfaces was not run in this terminal pass, so the remaining risk is hover/help polish and layout feel rather than logic correctness.
- Rollback points:
  - `app/macos/Sources/Features/Plot/PlotSession.swift`
  - `app/macos/Sources/Features/Plot/PlotSessionTypes.swift`
  - `app/macos/Sources/Features/Plot/PlotTemplateView.swift`
  - `app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `app/macos/Sources/Features/Composer/ComposerSession.swift`
  - `app/macos/Sources/Features/Composer/ComposerSessionTypes.swift`
  - `app/macos/Sources/Features/Composer/ComposerInspectorView.swift`
  - `app/macos/Sources/Features/Composer/ComposerCanvasView.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleSession.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleEditorView.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleContextView.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift`
  - `app/macos/Tests/PlotSessionTests.swift`
  - `app/macos/Tests/ComposerSessionTests.swift`
  - `app/macos/Tests/CodeConsoleSessionTests.swift`
- Decision:
  - The remaining three workbenches now follow the same first-principles rule already applied to Data Studio: button enablement and explanation belong to session truth, not to ad hoc SwiftUI booleans or string branches.
  - Rejected alternatives:
    - only patch the visible disabled buttons in-place: rejected because that would preserve duplicated business rules in views and reopen drift the next time a second surface is added
    - keep Code Console’s Outputs-panel reveal button because it is convenient: rejected because it violates the existing inspector-centered export/reveal affordance rule and duplicates action ownership
    - preserve the old Code Console reveal-to-source fallback: rejected because it hides the difference between source navigation and managed output navigation
  - Boundary:
    - this round does not change sidecar endpoints, saved project schema, plot contract payloads, or canonical workflow definitions
    - the changes are internal macOS GUI/state cleanup only
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests -only-testing:SciPlotGodMacTests/ComposerSessionTests -only-testing:SciPlotGodMacTests/CodeConsoleSessionTests`: passed (`51 tests`)
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed
  - `.venv/bin/python -m pytest tests`: passed (`176 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`122 tests`)
  - Manual macOS visual QA checklist for this round (not executed in terminal pass):
    - Plot template gallery hover/help reads well before and after inspect, and legend reset explanation appears only when relevant
    - Composer inspector and board quick-action popover show consistent disabled reasons for merge/unmerge/place/remove/manual-label cases
    - Code Console prompt/editor/source/output buttons expose the expected help text for empty, loading, and ready states
    - Code Console inspector `Reveal Output` and Outputs panel no longer compete as duplicate action surfaces
    - Toolbar `Export` and inspector `Actions` copy still read consistently across Plot / Composer / Code Console

### 2026-04-14 (Round AI): Maintenance governance handbook

- Scope:
  - Added `docs/maintenance-governance.md` as the maintainer-facing governance handbook for this repo.
  - Defined document precedence, ownership boundaries, change taxonomy, review gates, rollback/incident duties, documentation responsibilities, and the 30-minute takeover standard without changing runtime behavior.
  - Updated `README.md` so the new handbook is discoverable from `More` and sits in the intended onboarding order between `AGENTS.md` and `docs/engineering-handoff.md`.
- User-visible impact:
  - No user-visible product behavior change.
  - Maintainers now have one explicit governance document for day-to-day change management instead of piecing the process together from `AGENTS.md`, `README.md`, and scattered handoff notes.
- Risks:
  - The new handbook intentionally summarizes and points to existing truth sources; if future rounds update `AGENTS.md` or runtime behavior without updating this handbook, the repo could drift at the process layer even while code remains correct.
  - This round does not create new CI or release automation; enforcement still depends on maintainers following the documented matrix and handoff duties.
- Rollback points:
  - `docs/maintenance-governance.md`
  - `README.md`
  - `docs/engineering-handoff.md`
- Decision:
  - The repo now treats maintenance governance as a separate document layer: runtime truth stays in code/schema/contract, hard engineering boundaries stay in `AGENTS.md`, onboarding stays in `README.md`, and round evidence stays in `docs/engineering-handoff.md`.
  - Rejected alternatives:
    - keep adding maintenance/process guidance only to `AGENTS.md`: rejected because it would continue mixing hard boundary rules with day-to-day governance and make takeover harder to scan
    - push the governance material into `README.md`: rejected because the README should stay concise and discovery-oriented rather than becoming a full operating manual
    - copy large rule blocks out of `AGENTS.md` into the new handbook: rejected because that would create a second rule catalog and increase drift risk
  - Boundary:
    - this round changes documentation structure only; there are no sidecar, schema, contract, runtime, or workflow changes
    - `AGENTS.md` remains the hard-rule truth source and was intentionally not rewritten in this round
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 34 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`176 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`122 tests`)

### 2026-04-14 (Round AJ): Quick Look race fix, Data Studio warning merge, and workbook seam split

- Scope:
  - Fixed the shared Quick Look thumbnail race in `app/macos/Sources/Shared/UI/QuickLookThumbnailView.swift` by adding per-request revision gating, clearing stale images when a new load starts, and introducing a loader seam that tests can drive deterministically.
  - Cleaned up Data Studio import and warning presentation:
    - removed the writable import bridge booleans from `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
    - rewired `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift` to consume `importFlow` directly
    - added typed focused-workbook notice presentation in `app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift`
    - centralized preview warning, workbook warning, and exclusion merging in `app/macos/Sources/Features/DataStudio/DataStudioSessionSpecimenFilter.swift`
  - Added macOS regression coverage for both bug fixes and a lightweight GUI renderability smoke path in:
    - `app/macos/Tests/DataStudioSessionTests.swift`
    - `app/macos/Tests/AppModelTests.swift`
    - `app/macos/Tests/InspectorLayoutPolicyTests.swift`
  - Split `src/data_studio/workbooks.py` into narrower internal seams without changing the public Python entry surface:
    - `src/data_studio/workbook_constants.py`
    - `src/data_studio/workbook_template_authoring.py`
    - `src/data_studio/workbook_building.py`
    - `src/data_studio/workbook_export.py`
    - `src/data_studio/workbooks.py` remains the façade and now delegates to those modules
- User-visible impact:
  - Rapid thumbnail selection changes in Composer and Code Console no longer leave the old preview on screen or let a slow older callback overwrite the latest file selection.
  - Data Studio `Focused Group` now surfaces preview warnings, workbook-level warnings, and exclusion notes together instead of silently dropping workbook warnings once preview warnings exist.
  - No intended sidecar/public API or canonical workflow change.
- Risks:
  - Quick Look now clears the previous thumbnail immediately when a new load begins, so users may briefly see an empty/loading state where they previously saw a stale image.
  - The new GUI smoke tests only verify that key views render to PNG successfully; they are not golden-image comparisons and will not catch subtle visual regressions by themselves.
  - The Data Studio Python split preserves the existing façade but adds new internal module boundaries; future edits that bypass the façade or duplicate helper ownership can reintroduce drift.
- Rollback points:
  - `app/macos/Sources/Shared/UI/QuickLookThumbnailView.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSessionSpecimenFilter.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - `app/macos/Tests/DataStudioSessionTests.swift`
  - `app/macos/Tests/AppModelTests.swift`
  - `app/macos/Tests/InspectorLayoutPolicyTests.swift`
  - `src/data_studio/workbooks.py`
  - `src/data_studio/workbook_constants.py`
  - `src/data_studio/workbook_template_authoring.py`
  - `src/data_studio/workbook_building.py`
  - `src/data_studio/workbook_export.py`
- Decision:
  - The shared thumbnail component now owns latest-write-wins protection itself rather than asking each consumer to invent its own stale-result guard. This keeps async image loading aligned with the repo-wide revision-gated task model.
  - Focused Group warnings are now composed in session truth instead of view-local helper logic so preview warnings cannot shadow workbook warnings or exclusions.
  - `src/data_studio/workbooks.py` remains the supported façade, but large internal responsibilities now live behind narrower modules so future Data Studio maintenance can change import/build/export behavior without reopening the entire monolith.
  - Rejected alternatives:
    - patch Quick Look behavior separately in Composer and Code Console: rejected because the bug lives in the shared thumbnail model and a per-consumer fix would duplicate async semantics
    - keep the Data Studio warning merge in `DataStudioWorkbenchView`: rejected because it had already drifted into a view-local rule that swallowed workbook warnings
    - fully rewrite the Data Studio backend seam in one step: rejected because the safer move this round is to carve out stable helpers while preserving the existing public façade and test matrix
  - Boundary:
    - this round does not add endpoints, change project schema, modify plot contract payloads, or alter canonical Plot/Data Studio/Composer/Code Console workflows
    - the Python split is internal-only and the new GUI smoke coverage is deliberately lightweight infrastructure, not a full visual diff system
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/DataStudioSessionTests -only-testing:SciPlotGodMacTests/AppModelTests -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests`: passed (`55 tests`)
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py src/data_studio/workbooks.py src/data_studio/workbook_building.py src/data_studio/workbook_export.py src/data_studio/workbook_template_authoring.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 34 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`176 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`123 tests`)
  - Manual macOS visual QA checklist for this round (not executed in terminal pass):
    - rapid thumbnail switching in Composer panel previews and Code Console outputs no longer feels stale or jumpy
    - Data Studio `Focused Group` shows preview warnings, workbook warnings, and exclusions together with clear ordering
    - import wizard presentation still opens/closes cleanly after the `importFlow` cleanup for both empty-session and existing-session entry points
    - Plot template gallery, Data Studio template editor/specimen filter, Composer board quick actions, and Code Console outputs all render cleanly under the new snapshot smoke harness

### 2026-04-17 (Round AK): Plot legend move availability, GUI fingerprint regression coverage, and session seam phase 2

- Scope:
  - Fixed the remaining Plot legend reorder GUI rule gap by moving per-row move availability into Plot session truth:
    - `app/macos/Sources/Features/Plot/PlotSessionPresentation.swift` now emits typed series-order rows with `move up` / `move down` availability and explanations
    - `app/macos/Sources/Shared/UI/SortableSeriesListView.swift` now renders those typed rows instead of relying on a raw `canEdit` boolean
    - `app/macos/Sources/Features/Plot/PlotInspectorView.swift` now consumes the typed row payload directly
  - Added a stronger macOS GUI regression layer in `app/macos/Tests/InspectorLayoutPolicyTests.swift`:
    - retained render-to-PNG smoke coverage for the canonical workbench scenes
    - added tolerant perceptual snapshot fingerprints for Plot template gallery, Data Studio template editor, Data Studio specimen filter, Composer quick-action canvas state, and Code Console outputs preview
    - added shared Quick Look stale-result regression tests to keep latest-write-wins thumbnail semantics locked down
  - Split the oversized macOS session monoliths into state shells plus focused seam files without changing their public observable type names:
    - Plot: `PlotSession.swift`, `PlotSessionImportInspect.swift`, `PlotSessionPresentation.swift`, `PlotSessionPreviewExport.swift`, `PlotSessionRestore.swift`
    - Composer: `ComposerSession.swift`, `ComposerSessionImportExport.swift`, `ComposerSessionPreviewUndo.swift`, `ComposerSessionSelectionPlacement.swift`
  - Continued Data Studio backend seam work by extracting the remaining heavy internal responsibilities out of `src/data_studio/workbooks.py`:
    - preview/filter/specimen scoring moved into `src/data_studio/workbook_previewing.py`
    - comparison-bundle recovery/materialization moved into `src/data_studio/workbook_comparison_bundle.py`
    - `src/data_studio/workbooks.py` remains the supported façade
- User-visible impact:
  - Plot legend reorder controls now explain why the first row cannot move up, why the last row cannot move down, and why reordering is unavailable for non-reorderable plots.
  - No intended sidecar/public API, schema, or canonical workflow change.
  - Internal GUI regressions should now get caught earlier because the repo has a deterministic fingerprint layer in addition to basic renderability smoke.
- Risks:
  - The new GUI regression layer is intentionally tolerant and fingerprint-based; it will catch obvious visual drift but is not a substitute for manual visual QA when layout details change significantly.
  - Plot and Composer session seam splits preserve behavior through tests, but future edits can still drift if new logic is pushed back into the root shell files instead of the focused seam files.
  - `src/data_studio/workbooks.py` is now thinner, but callers still rely on it as the façade; bypassing that façade or reintroducing direct helper coupling would recreate the old maintenance hotspot.
- Rollback points:
  - `app/macos/Sources/Shared/UI/SortableSeriesListView.swift`
  - `app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `app/macos/Sources/Features/Plot/PlotSession.swift`
  - `app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
  - `app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
  - `app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
  - `app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
  - `app/macos/Sources/Features/Composer/ComposerSession.swift`
  - `app/macos/Sources/Features/Composer/ComposerSessionImportExport.swift`
  - `app/macos/Sources/Features/Composer/ComposerSessionPreviewUndo.swift`
  - `app/macos/Sources/Features/Composer/ComposerSessionSelectionPlacement.swift`
  - `app/macos/Tests/InspectorLayoutPolicyTests.swift`
  - `app/macos/Tests/PlotSessionTests.swift`
  - `app/macos/SciPlotGod.xcodeproj/project.pbxproj`
  - `src/data_studio/workbooks.py`
  - `src/data_studio/workbook_export.py`
  - `src/data_studio/workbook_previewing.py`
  - `src/data_studio/workbook_comparison_bundle.py`
- Decision:
  - Row-level Plot legend move rules now live only in session truth. The shared sortable list view renders and explains those rules, but does not recompute business semantics locally.
  - GUI regression protection now uses deterministic perceptual fingerprints rather than exact golden PNG comparisons. This keeps the suite sensitive to meaningful drift without making the tests brittle to harmless rendering noise.
  - Plot and Composer root session files now act as ownership maps and state shells instead of continuing to absorb import, preview, export, undo, and presentation logic in one place.
  - `src/data_studio/workbooks.py` remains the stable façade while preview/filter and comparison-bundle internals evolve behind narrower modules.
  - Rejected alternatives:
    - keep the legend reorder explanation logic inside the shared view: rejected because it would recreate a second truth source for move rules
    - adopt exact snapshot goldens immediately: rejected because they would be too fragile for the current SwiftUI workbench surfaces and slow down routine maintenance
    - leave Plot/Composer/Data Studio seam debt in place until a future feature forces the split: rejected because new feature work would continue to pile onto the same monoliths
  - Boundary:
    - this round does not change sidecar routes, plot contract payloads, project schema, canonical workflows, or public Python entrypoints
    - the new GUI regression coverage is test infrastructure only; it does not alter runtime rendering behavior
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests -only-testing:SciPlotGodMacTests/ComposerSessionTests`: passed (`42 tests`)
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests`: passed (`5 tests`)
  - `.venv/bin/python -m pytest tests/test_data_studio.py tests/test_sidecar_data_studio.py`: passed (`28 passed, 5 warnings`)
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 34 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`176 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`129 tests`)
  - Manual macOS visual QA checklist for this round (not executed in terminal pass):
    - Plot legend reorder controls read naturally for first-row, last-row, and non-reorderable states
    - Plot template gallery, Data Studio template editor/specimen filter, Composer quick actions, and Code Console outputs still look intentional under real window sizing, not just the normalized test harness
    - Snapshot fingerprint updates are only required when the UI change is intentional and visually reviewed
    - Plot and Composer inspector/export flows still feel unchanged after the internal seam split
    - Data Studio preview/filter and comparison export still match previous behavior on real imported workbooks

### 2026-04-17 (Round AL): Manual macOS visual QA and targeted workbench polish

- Scope:
  - Executed the deferred macOS visual QA pass against the five canonical workbench scenes introduced in Round AK by using the normalized GUI smoke as an attachment-export harness:
    - Plot template gallery
    - Data Studio template editor
    - Data Studio specimen filter
    - Composer canvas selection / quick-action state
    - Code Console outputs preview
  - Polished `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchSpecimenViews.swift` so the specimen filter keeps its primary action row outside the scrolling content and expands the canonical popover height from `620` to `648`, preventing the footer action from feeling cramped or clipped in the default visual pass.
  - Polished `app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift` so preview routing now reflects actual document state:
    - missing generated files show an explicit `Preview unavailable` empty state
    - PDFs render through `PDFPreviewView`
    - non-PDF generated files render through `QuickLookThumbnailView`
  - Hardened `app/macos/Sources/Shared/UI/QuickLookThumbnailView.swift` for GUI validation and ready-state previews:
    - missing files now fail with a visible user-facing message instead of silently attempting Quick Look generation
    - tests can inject a deterministic thumbnail model and disable auto-load on appear without affecting production call sites
  - Strengthened `app/macos/Tests/InspectorLayoutPolicyTests.swift` so the canonical scene smoke can retain/export attachments, generate stable ready-state Code Console preview fixtures, and keep perceptual fingerprints aligned with the intended UI.
  - Declared the Composer drag payload UTI in `app/macos/Info.plist` (`com.codegod.composer-panel-drag`) to remove the runtime warning that surfaced during repeated GUI smoke and attachment-export runs.
- User-visible impact:
  - Data Studio specimen filter keeps its primary `Use Auto Keep 5` action visibly anchored below the ranked list instead of letting the footer compete with scroll content.
  - Code Console preview now distinguishes missing files, PDFs, and non-PDF outputs instead of always falling back to the same thumbnail path.
  - No intended sidecar/public API, schema, project format, or canonical workflow change.
- Risks:
  - The new `QuickLookThumbnailView` and `CodeConsoleOutputsView` injection hooks are test seams only; if future runtime code starts depending on them, that would blur the production/test boundary.
  - Attachment-based visual QA is materially better than “not executed,” but it is still not a substitute for real click-through interaction if a future round changes hover, focus, or sheet/popover behavior.
  - The specimen filter height/footer adjustment is tuned for the canonical scene; future content growth inside the `Advanced` section should still be reviewed manually before increasing default density again.
- Rollback points:
  - `app/macos/Sources/Features/DataStudio/DataStudioWorkbenchSpecimenViews.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift`
  - `app/macos/Sources/Shared/UI/QuickLookThumbnailView.swift`
  - `app/macos/Tests/InspectorLayoutPolicyTests.swift`
  - `app/macos/Info.plist`
- Decision:
  - When direct desktop automation is unavailable for `com.codegod.desktop`, the supported fallback for manual macOS visual QA is to export the canonical workbench scene attachments from `InspectorLayoutPolicyTests/testGuiSmokeRendersKeyWorkbenchViews` and inspect those rendered artifacts directly instead of marking the round as visually unverified.
  - Code Console preview semantics now follow the document state truth source: existence first, then explicit file type routing, rather than asking Quick Look to handle every generated file uniformly.
  - The Data Studio specimen filter keeps ranked content scrollable, but primary actions anchored, so the default Auto Keep flow stays readable and reachable without reopening a second pane or adding duplicate controls.
  - Rejected alternatives:
    - leave the specimen filter footer inside the scroll view: rejected because it made the default action feel visually unstable and easier to clip at canonical sizing
    - keep Code Console on a single Quick Look preview path: rejected because missing files and PDFs deserve clearer, more faithful preview behavior
    - continue recording “manual visual QA not executed”: rejected because the repo now has enough deterministic scene coverage to support a real artifact-based human pass
  - Boundary:
    - this round does not change sidecar routes, plot contract payloads, project schema, persistence semantics, or canonical workbench flows
    - the new preview injection hooks are internal test-support seams only
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData -resultBundlePath app/macos/.derivedData/visual-qa-result test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testGuiSmokeRendersKeyWorkbenchViews`: passed (`1 test`)
  - `xcrun xcresulttool export attachments --path app/macos/.derivedData/visual-qa-result --output-path app/macos/.derivedData/gui-attachments`: passed (`5 attachments exported`)
  - Manual inspection completed against exported PNG attachments in `app/macos/.derivedData/gui-attachments/` for:
    - Plot template gallery
    - Data Studio template editor
    - Data Studio specimen filter
    - Composer canvas selection
    - Code Console outputs preview
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 34 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`176 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`129 tests`)

Use this block for every new round:

```
### YYYY-MM-DD (Round X): <title>

- Scope:
- User-visible impact:
- Risks:
- Decision:
- Validation (commands + result):
```
