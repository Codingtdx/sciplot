# SciPlot Screen Rules

This document defines app-shell and workbench-level layout rules for the retained SciPlot desktop product model.

## Global Rules

- App-level primary navigation exposes only four workbenches: `Plot`, `Data Studio`, `Composer`, and `Code Console`.
- `Start`, `Home`, `Project`, and `Settings` are not primary destinations in the long-term IA.
- Utilities such as recents, open/save, managed files, and appearance/runtime controls stay secondary.
- Each workbench should present one dominant workspace rather than a dashboard mosaic.
- Canonical internal workflow and user-visible UI workflow are different layers.
- Hidden system steps may stay invisible or be merged into broader work surfaces when the user does not need to act there.
- Use local navigation inside a workbench when a workflow needs steps; do not promote local steps into app-level navigation.
- The shell must feel like one calm desktop tool, not a stack of unrelated modules.

## App Shell

### Structure

- Titlebar with traffic lights at top left.
- Fixed left sidebar with primary destinations:
- Plot
- Data Studio
- Composer
- Code Console
- Main workspace to the right.
- Optional contextual right inspector only when the current workbench needs one.
- Utility entry points may live in titlebar actions, sidebar footer, or lightweight overflow surfaces.

### Behavior

- Sidebar selection changes the active workbench.
- Plot local steps stay inside Plot.
- Data Studio local steps stay inside Data Studio.
- Composer and Code Console may expose local panes or tabs, but these remain workbench-local.
- The shell must not collapse into a Plot-only flow.

## Plot

### Purpose

- Turn a dataset into a publication-ready figure export bundle.

### Canonical Workflow

- Import
- Inspect
- Template
- Refine
- Preflight
- Export
- optional handoff to Composer

### Layout

- Main workspace is chart-workflow-centric, not dashboard-centric.
- Local navigation should clarify where the user is inside Plot without becoming top-level app chrome.
- Import should foreground data source, sheet selection, preview, and inspection summary.
- Template should foreground compatible recommendations and clearly disabled alternatives.
- Refine should foreground preview, refinement controls, inline readiness/preflight, and export.

### Rules

- Sheet selection belongs inside `Import`.
- Preview belongs inside `Refine`.
- Readiness and preflight belong inside `Refine`, not as app-level destinations.
- Export stays attached to the Plot workflow.
- Do not restore a product shell whose primary navigation is only `Start / Plot Import / Plot Template / Plot Refine`.

## Data Studio

### Purpose

- Turn raw experimental data into structured workbooks, comparison sets, and exportable figures.

### Canonical Workflow

- Choose Template
- Preview Source or Create Template
- Build Workbook
- Review
- Compare
- Export / Open in Plot

### Layout

- Main workspace is workbook-and-comparison-centric.
- The first decision should be template selection: choose an existing template for direct processing, or start template creation from one real sample file.
- Source preview should foreground detected structure, recommended regions, and candidate fields rather than blank schema forms.
- Compare should make figure previews, warnings, recipe selection, and bundle actions easy to review.

### Rules

- Use `Data Studio` in product-facing copy.
- Internal tensile-specific routes or schemas may remain underneath.
- Successful workbook build and comparison work should stay in this workbench until the user explicitly chooses `Open in Plot`.
- Do not frame this workbench as a tensile-only niche tool in user-facing IA.

## Composer

### Purpose

- Arrange graph exports, assets, and text on a controlled canvas for multi-panel output.

### Canonical Workflow

- Assets
- Layout
- Compose
- Inspect/Arrange
- Review
- Export

### Layout

- Composer is canvas-first.
- The canvas should dominate the screen.
- Asset trays, layer lists, and inspectors are supporting surfaces around the canvas.
- Review and export stay close to the composition surface, not in a disconnected wizard finish step.

### Rules

- Do not turn Composer into a form-first editor.
- Preserve layout-grid, crop, overlap, and export invariants.
- Project persistence may exist as a utility, but `Project` is not a primary workbench.

## Code Console

### Purpose

- Provide a serious scripting and controlled-runner surface for advanced figure work.

### Canonical Workflow

- Bind Context
- Inspect Inputs
- Prompt/Code
- Run
- Outputs
- Handoff

### Layout

- The workbench should balance code entry, structured context, run controls, and result review.
- Context binding and inspection should be visible, but should not crowd out the code/run surface.
- Outputs should make logs, artifacts, and handoff actions easy to inspect.

### Rules

- Code Console is a first-class workbench, not a secondary utility.
- Keep contract-bound context and controlled-runner semantics visible in the IA.
- Do not bury Console behind Plot-only utility affordances.
- Do not make the workbench a second giant configuration form.

## Utilities

### Purpose

- Support the four workbenches without becoming peers to them.

### Examples

- quick open
- recents
- open/save
- managed exports or managed runs
- reveal/open-path actions
- appearance/runtime controls

### Rules

- Utilities may appear in titlebar actions, menus, or secondary side surfaces.
- Utilities must not become top-level primary navigation peers.
- `Settings` can survive only as a utility surface if still needed for runtime management.

## Borrowed Desktop Mapping

### Plot

- Borrow the calm sheet layout, readable preview/table treatment, and stable inspector rhythm.

### Data Studio

- Borrow structured intake panels, comparison clarity, and desktop utility-panel calmness.

### Composer

- Borrow split-pane stability, panel hierarchy, and careful canvas framing.

### Code Console

- Borrow quiet inspector grouping, compact code/tool controls, and strong result-surface hierarchy.

## Flow Expectations

- App-level switch: user can move directly between the four workbenches.

### Canonical Internal Flows

- Plot: `Import -> Inspect -> Template -> Refine -> Preflight -> Export`
- Data Studio: `Choose Template -> Preview Source or Create Template -> Build Workbook -> Review -> Compare -> Export / Open in Plot`
- Composer: `Assets -> Layout -> Compose -> Inspect/Arrange -> Review -> Export`
- Code Console: `Bind Context -> Inspect Inputs -> Prompt/Code -> Run -> Outputs -> Handoff`

### User-Visible Mock Flows

- Plot: `Import -> Template -> Refine & Export`
- Data Studio: `Choose Template -> Import -> Workbook Review -> Compare -> Export / Open in Plot`
- Composer: `Assets -> Compose -> Review -> Export`
- Code Console: `Context -> Code -> Run -> Outputs`

## Future Mock Guidance

- Future IA iteration should keep a true four-workbench shell.
- Do not expose every internal system step as a separate screen or navigation item.
- Merge hidden processing stages unless the user must meaningfully orient, decide, review, adjust, confirm, export, or hand off there.
- Do not restore `Start`, `Project`, or `Settings` as primary destinations.
