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
