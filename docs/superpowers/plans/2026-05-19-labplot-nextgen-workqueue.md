# LabPlot Nextgen Workqueue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the remaining LabPlot-informed engineering pushes in one ordered, persistent queue so each batch can be implemented, merged, and then removed from this file.

**Architecture:** SciPlot keeps the current `app/macos + app/sidecar + src/*` architecture. LabPlot remains a clean-room reference for object lifecycle, import/analysis discipline, artifact ownership, and desktop workflow maturity; SciPlot does not copy GPL source and does not restore LabPlot's global Project Explorer shell.

**Tech Stack:** Python/FastAPI sidecar, SciPlot rendering/data/composer/code services, `.sciplot` project bundles, SwiftUI macOS frontend, Xcode tests, pytest, ruff, smoke and clean-room gates.

---

## Queue Rules

- This file is the active work queue, not a historical changelog.
- Implement from top to bottom. Do not skip to a later batch unless the user explicitly reorders the queue.
- Each batch gets its own `codex/*` branch from latest `main`.
- Each batch must end with: targeted Python tests, targeted Swift tests when macOS changes, clean-room check, smoke or route-level smoke, merge commit into `main`, push, and deletion of the merged feature branch.
- When a batch is fully merged into `main`, delete that batch section from this file in the same closeout PR or follow-up commit.
- Product facts from completed work belong in `docs/engineering-handoff.md`, `docs/sidecar-api.md`, `docs/macos-frontend-design.md`, and focused architecture docs. Do not leave completed roadmap prose here.
- Disabled features are allowed only with `disabled + help` diagnostics and tests proving the disabled state is visible.

## Active Work Queue

### Task 1: Data Studio Analysis Object Loop

**Branch:** `codex/labplot-analysis-object-loop`

**Goal:** Turn Data Studio analysis from a utility readout into a persistent, graph-backed analysis object lifecycle shared with Plot.

**Why this is next:** Plot interaction is now command-backed, and Data Studio import/template/workbook binding is now stable. The next LabPlot-level maturity jump is making fit, smooth, FFT, statistics, baseline, peak detection, and result overlays behave like durable scientific objects instead of one-shot calculations.

**Files:**
- Modify: `src/rendering/analysis_operations.py`
- Modify: `src/rendering/data_containers.py`
- Modify: `src/rendering/capability_registry.py`
- Modify: `src/data_studio/service.py`
- Modify: `src/data_studio/models.py`
- Modify: `app/sidecar/schemas_analysis.py`
- Modify: `app/sidecar/schemas_data_studio.py`
- Modify: `app/sidecar/routes_analysis.py`
- Modify: `app/sidecar/routes_data_studio.py`
- Modify: `app/sidecar/project_bundle.py`
- Modify: `app/macos/Sources/Infrastructure/SidecarModelsDataStudio.swift`
- Modify: `app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
- Modify: `app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
- Modify: `app/macos/Sources/Features/DataStudio/DataStudioSessionAnalysis.swift`
- Modify: `app/macos/Sources/Features/DataStudio/DataStudioView.swift`
- Modify: `docs/engineering-handoff.md`
- Modify: `docs/sidecar-api.md`
- Modify: `docs/macos-frontend-design.md`
- Test: `tests/test_analysis_operations.py`
- Test: `tests/test_sidecar_data_studio.py`
- Test: `tests/test_plot_project_routes.py`
- Test: `app/macos/Tests/SchemaDecodingTests.swift`
- Test: `app/macos/Tests/DataStudioSessionTests.swift`

- [ ] **Step 1: Create the branch and baseline**

Run:

```bash
git checkout main
git pull --ff-only origin main
git checkout -b codex/labplot-analysis-object-loop
git status --short --branch
```

Expected: clean branch at latest `origin/main`.

- [ ] **Step 2: Add failing Python tests for persistent analysis nodes**

Add tests that prove:

- `POST /analysis-operation` returns a stable `operation_id`, `operation_node`, result containers, diagnostics, and lineage.
- Data Studio focused workbook analysis calls the shared `/analysis-operation` envelope rather than recomputing in Swift or a second Python path.
- `.sciplot` save/open preserves `data.analysis_operation`, `data.analysis_result`, result table containers, and optional plot overlay refs.

Run:

```bash
.venv/bin/python -m pytest tests/test_analysis_operations.py tests/test_sidecar_data_studio.py tests/test_plot_project_routes.py -q
```

Expected: fail only on missing analysis object lifecycle fields and graph persistence.

- [ ] **Step 3: Implement sidecar analysis object payloads**

Add explicit schema fields for:

- `operation_id`
- `operation_kind`
- `source_binding`
- `settings`
- `status`
- `metrics`
- `diagnostics`
- `elapsed_ms`
- `lineage`
- `result_containers`
- `overlay_refs`
- `artifact_refs`
- `graph_node_id`
- `recalculate_policy`

Keep the response model explicit; do not return naked dictionaries from sidecar routes.

- [ ] **Step 4: Persist Data Studio analysis graph nodes**

Generate deterministic graph nodes for focused workbook analysis:

- `data.analysis_operation`
- `data.analysis_result`
- `data.analysis_table`
- `plot.analysis_overlay` when a result can be opened in Plot

Project restore must use embedded workbook/result payloads as truth, not original raw source paths.

- [ ] **Step 5: Wire macOS Data Studio Analysis consumption**

Update `DataStudioSession` so Analysis:

- uses focused workbook/current figure state as the source binding,
- calls sidecar analysis routes,
- stores the returned envelope and containers,
- displays status, diagnostics, metrics, and result containers,
- disables custom function in Data Studio with help until a real custom-function editor exists,
- does not compute fit, FFT, statistics, baseline, or peak detection in Swift.

- [ ] **Step 6: Add typed commands for analysis object edits**

Use the shared command envelope for:

- add analysis operation,
- edit settings,
- delete result,
- recalculate,
- bind result to Plot,
- toggle overlay visibility.

UndoManager restores session state and records reversible command metadata.

- [ ] **Step 7: Update docs**

Update:

- `docs/engineering-handoff.md`: analysis object lifecycle is product fact.
- `docs/sidecar-api.md`: analysis request/response fields and graph persistence.
- `docs/macos-frontend-design.md`: Data Studio Analysis UI responsibility and disabled/help policy.

- [ ] **Step 8: Verify and close Task 1**

Run:

```bash
.venv/bin/python -m pytest tests/test_analysis_operations.py tests/test_sidecar_data_studio.py tests/test_plot_project_routes.py -q
.venv/bin/python -m ruff check app/sidecar src tests scripts
.venv/bin/python scripts/check_labplot_cleanroom.py
.venv/bin/python scripts/smoke_check.py
xcodebuild test -project app/macos/SciPlot.xcodeproj -scheme SciPlotMac -destination 'platform=macOS' -only-testing:SciPlotMacTests/SchemaDecodingTests -only-testing:SciPlotMacTests/DataStudioSessionTests
git diff --check
git status --short --branch
```

Then commit, push, merge to `main`, delete the merged feature branch, and remove this Task 1 section from the queue.

### Task 2: Composer Linked Artifacts And Export Preflight

**Branch:** `codex/labplot-composer-linked-artifacts`

**Goal:** Make Composer consume Plot/Data Studio/Code Console outputs through graph artifact references and add export preflight diagnostics.

**Why this follows analysis:** Composer should compose stable artifacts. Plot outputs, Data Studio workbook/analysis outputs, and Code Console outputs need durable graph/container identities before Composer can reliably link, refresh, and export them.

**Files:**
- Modify: `src/composer.py`
- Modify: `src/rendering/export_targets.py`
- Modify: `src/infrastructure/persistence`
- Modify: `app/sidecar/schemas_composer.py`
- Modify: `app/sidecar/routes_composer.py`
- Modify: `app/sidecar/project_bundle.py`
- Modify: `app/macos/Sources/Infrastructure/SidecarModelsComposer.swift`
- Modify: `app/macos/Sources/Features/Composer`
- Modify: `docs/engineering-handoff.md`
- Modify: `docs/sidecar-api.md`
- Modify: `docs/macos-frontend-design.md`
- Test: `tests/test_composer_*.py`
- Test: `tests/test_plot_project_routes.py`
- Test: `app/macos/Tests/SchemaDecodingTests.swift`

- [ ] **Step 1: Create branch from latest main**

Run:

```bash
git checkout main
git pull --ff-only origin main
git checkout -b codex/labplot-composer-linked-artifacts
```

- [ ] **Step 2: Add failing tests for linked artifacts**

Tests must prove Composer can reference:

- Plot figure artifacts,
- Data Studio figure/workbook/analysis artifacts,
- Code Console generated figures,
- missing artifact diagnostics,
- project save/open continuity.

- [ ] **Step 3: Implement `ComposerAssetRefPayload`**

Asset refs must include:

- `asset_id`,
- `source_module`,
- `source_graph_node_id`,
- `artifact_manifest_id`,
- `label`,
- `kind`,
- `mime_type`,
- `sha256`,
- `embedded_path`,
- `refresh_policy`,
- `preflight_status`.

- [ ] **Step 4: Add export preflight**

Preflight must report:

- missing asset,
- low-resolution raster,
- unsupported format,
- missing font risk,
- page bleed risk,
- PDF/TIFF parity issue,
- stale linked source.

Unsupported states must be disabled with help, not silent no-op.

- [ ] **Step 5: Wire macOS Composer**

Composer UI remains module-local. It may show linked asset status and refresh/reveal actions, but must not add a global Project Explorer or shared rail.

- [ ] **Step 6: Verify and close Task 2**

Run targeted Composer/Python/Swift gates, merge to `main`, delete the branch, and remove this Task 2 section from the queue.

### Task 3: Code Console Notebook Artifact Roundtrip

**Branch:** `codex/labplot-code-console-artifact-roundtrip`

**Goal:** Make Code Console outputs durable notebook-style artifacts that can roundtrip through `.sciplot` and feed Plot/Composer without rerunning code.

**Why this follows Composer:** Once Composer understands linked artifacts, Code Console can become a reliable artifact producer for tables, figures, logs, and model outputs.

**Files:**
- Modify: `src/code_console_service.py`
- Modify: `src/code_console_runtime.py`
- Modify: `src/rendering/data_containers.py`
- Modify: `app/sidecar/schemas_code_console.py`
- Modify: `app/sidecar/routes_code_console.py`
- Modify: `app/sidecar/project_bundle.py`
- Modify: `app/macos/Sources/Infrastructure/SidecarModelsCodeConsole.swift`
- Modify: `app/macos/Sources/Features/CodeConsole`
- Modify: `docs/engineering-handoff.md`
- Modify: `docs/sidecar-api.md`
- Modify: `docs/macos-frontend-design.md`
- Test: `tests/test_sidecar_code_console.py`
- Test: `tests/test_plot_project_routes.py`
- Test: `app/macos/Tests/SchemaDecodingTests.swift`
- Test: `app/macos/Tests/CodeConsoleSessionTests.swift`

- [ ] **Step 1: Create branch from latest main**

Run:

```bash
git checkout main
git pull --ff-only origin main
git checkout -b codex/labplot-code-console-artifact-roundtrip
```

- [ ] **Step 2: Add failing artifact roundtrip tests**

Tests must prove:

- generated PNG/PDF/TIFF files become figure outputs,
- generated CSV/JSON files become readonly notebook output containers,
- logs become log artifacts,
- `.sciplot` embeds latest-run artifacts,
- restore shows prior outputs without rerunning code,
- Plot/Composer handoff uses artifact refs.

- [ ] **Step 3: Implement notebook artifact manifest**

Each output must include:

- `output_id`,
- `kind`,
- `label`,
- `source_run_id`,
- `artifact_manifest_id`,
- `embedded_path`,
- `sha256`,
- `created_at`,
- `data_container_id` when applicable,
- `graph_node_id`.

- [ ] **Step 4: Wire macOS Code Console**

Outputs view displays tables, figures, logs, and handoff actions. Code Console remains one of the four existing modules; do not create a fifth Notebook module.

- [ ] **Step 5: Verify and close Task 3**

Run targeted Code Console/Python/Swift gates, merge to `main`, delete the branch, and remove this Task 3 section from the queue.

### Task 4: Live Data And Realtime Source Foundation

**Branch:** `codex/labplot-live-source-foundation`

**Goal:** Add a conservative live-data foundation for file tail, folder watch, and periodic CSV refresh with graph revisions and latest-write-wins preview invalidation.

**Why this is last in this queue:** Live data changes project state repeatedly. It should come after analysis/artifact/restore semantics are stable enough to absorb data revisions without corrupting Plot, Data Studio, Composer, or Code Console state.

**Files:**
- Modify: `src/rendering/live_sources.py`
- Modify: `src/rendering/import_filters.py`
- Modify: `src/rendering/data_containers.py`
- Modify: `src/rendering/capability_registry.py`
- Modify: `app/sidecar/schemas_live_source.py`
- Modify: `app/sidecar/routes_live_source.py`
- Modify: `app/sidecar/server.py`
- Modify: `app/sidecar/project_bundle.py`
- Modify: `app/macos/Sources/Infrastructure/SidecarModelsLiveSource.swift`
- Modify: `app/macos/Sources/Features/Plot`
- Modify: `app/macos/Sources/Features/DataStudio`
- Modify: `docs/engineering-handoff.md`
- Modify: `docs/sidecar-api.md`
- Modify: `docs/macos-frontend-design.md`
- Test: `tests/test_live_sources.py`
- Test: `tests/test_sidecar_active_routes.py`
- Test: `tests/test_plot_project_routes.py`
- Test: `app/macos/Tests/SchemaDecodingTests.swift`

- [ ] **Step 1: Create branch from latest main**

Run:

```bash
git checkout main
git pull --ff-only origin main
git checkout -b codex/labplot-live-source-foundation
```

- [ ] **Step 2: Add failing live-source tests**

Tests must prove:

- file tail appends new rows,
- folder watch discovers new CSV files,
- periodic CSV refresh supports append and replace policies,
- pause/resume and update-now are explicit state transitions,
- every refresh emits data revision metadata,
- stale refresh responses are ignored by macOS.

- [ ] **Step 3: Implement `LiveSourcePayload`**

Payload must include:

- `source_id`,
- `kind`,
- `path`,
- `poll_interval_ms`,
- `sample_window`,
- `append_policy`,
- `paused`,
- `last_revision`,
- `last_update_at`,
- `last_diagnostic`,
- `container_ids`,
- `graph_node_id`.

- [ ] **Step 4: Wire routes and capability catalog**

Add routes for:

- `POST /live-source/update-now`,
- `POST /live-source/pause`,
- `POST /live-source/resume`.

Keep MQTT, serial, and socket disabled with help until sandbox, fixtures, and UI policy exist.

- [ ] **Step 5: Wire macOS status only**

macOS shows source status, pause/resume, and update-now. It does not parse files locally and does not bypass sidecar import diagnostics.

- [ ] **Step 6: Verify and close Task 4**

Run targeted live-source/Python/Swift gates, merge to `main`, delete the branch, and remove this Task 4 section from the queue. When this is the final section, either delete this file or replace it with a one-line pointer saying the queue is empty and current facts live in handoff docs.

## Final Queue Exit Criteria

The queue is done when:

- all four task sections have been removed after successful merge,
- `docs/engineering-handoff.md` contains the durable product facts,
- `docs/sidecar-api.md` contains the stable route contracts,
- `docs/macos-frontend-design.md` contains the frontend responsibility boundaries,
- `git branch --all` shows no stale `codex/labplot-*` branch for completed work,
- `git status --short --branch` is clean on `main...origin/main`.

## Current Order Rationale

1. **Data Studio Analysis Object Loop** first because import/workbook state is now stable and analysis is the next core scientific maturity layer.
2. **Composer Linked Artifacts And Export Preflight** second because Composer should consume stable Plot/Data Studio/analysis artifacts.
3. **Code Console Notebook Artifact Roundtrip** third because Code Console becomes a producer of graph artifacts after artifact consumers are ready.
4. **Live Data And Realtime Source Foundation** fourth because repeated data revisions need the graph, analysis, and artifact lifecycle to be stable first.
