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
