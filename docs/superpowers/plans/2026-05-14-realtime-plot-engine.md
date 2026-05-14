# Realtime Plot Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Hybrid Native realtime Plot preview path that feels like Origin/DataGraph for curve-family plots while keeping backend export authoritative.

**Architecture:** macOS may render supported curve-family previews natively from contract-fed metadata and typed render options. The backend remains the source of truth for inspect, data transforms, fit/function evaluation, validation, final PDF/TIFF export, and fallback rendering. Native preview is admitted per template only when selection, hit testing, style edits, and export parity checks exist.

**Tech Stack:** SwiftUI Canvas/gesture state, existing `PlotSession` and `RenderOptionsPayload`, FastAPI sidecar schemas, Python Matplotlib renderers, XCTest, pytest.

---

### Task 1: Update Guardrails

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/macos-frontend-design.md`

- [ ] Replace the absolute ban on Swift plotting semantics with an allowlist policy: native preview is allowed only for supported templates, using contract/default metadata rather than local template/style constants.
- [ ] State v1 scope explicitly: `curve`, `point_line`, `scatter`, `area_curve`, `step_line`, and `function_curve`.
- [ ] Keep backend `/render-preview` and export as fallback and final authority; native preview must self-disable when metadata is missing or unsupported features are active.

### Task 2: Add Realtime Preview Policy And Series Editing Tests

**Files:**
- Modify: `app/macos/Tests/PlotSessionTests.swift`

- [ ] Add tests proving native realtime is enabled for the v1 curve-family templates and disabled for unsupported templates.
- [ ] Add tests proving double-click series selection opens the series editing state and routes the inspector to `.series(id)`.
- [ ] Add tests proving a series style edit writes a typed render option and schedules a preview refresh.

### Task 3: Implement macOS Realtime State

**Files:**
- Modify: `app/macos/Sources/Features/Plot/PlotSessionTypes.swift`
- Modify: `app/macos/Sources/Features/Plot/PlotSession.swift`
- Modify: `app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
- Modify: `app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
- Modify: `app/macos/Sources/Features/Plot/PlotInteractivePreviewOverlay.swift`

- [ ] Add native realtime support policy for the v1 template set.
- [ ] Add selected-series popover state and an API for `openSeriesQuickEditor(seriesID:)`.
- [ ] Add line double-click handling in the overlay using interaction metadata series hit targets when present; fall back to current selection behavior when absent.
- [ ] Keep user edits in `RenderOptionsPayload`, not ad hoc view state.

### Task 4: Add Typed Series Style Payload

**Files:**
- Modify: `app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
- Modify: `app/sidecar/schemas_render.py`
- Modify: `app/sidecar/render_support.py`
- Modify: `src/rendering/models.py`
- Modify: `src/rendering/options.py`

- [ ] Add `series_styles` / `seriesStyles` as an optional list of typed style overrides keyed by `series_id`.
- [ ] Support v1 fields: `color`, `line_width`, `marker`, `enabled`, and `y_axis_target`.
- [ ] Preserve unknown/unsupported style edits by validation errors rather than silent no-op.

### Task 5: Apply Series Style Overrides In Curve Renderers

**Files:**
- Modify: `src/rendering/render_curve.py`
- Modify: `src/plotting_curves.py`
- Test: `tests/test_rendering_services.py`
- Test: `tests/test_sidecar_render.py`

- [ ] Apply color, line width, marker, enabled, and y-axis assignment overrides to the supported curve-family render path.
- [ ] Ensure disabled series are omitted from preview/export and QA.
- [ ] Add pytest coverage for sidecar accepting `series_styles` and renderer output reflecting the override.

### Task 6: Verification

**Commands:**
- `xcodebuild -project app/macos/SciPlot.xcodeproj -scheme SciPlotMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test`
- `.venv/bin/python -m pytest tests/test_sidecar_render.py tests/test_rendering_services.py`
- `.venv/bin/python scripts/check_macos_gui_presentation.py`

**Acceptance Criteria:**
- Native realtime policy chooses the Hybrid path only for the v1 curve-family templates.
- Double-clicking a series opens a local quick editor and selects the matching series in the right inspector.
- Series style overrides are durable render options and reach both preview and export requests.
- Unsupported templates continue to use backend bitmap/PDF preview without losing existing overlay behavior.
