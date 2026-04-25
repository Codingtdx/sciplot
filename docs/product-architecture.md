# SciPlot God Product Architecture

This document is the canonical app-level product architecture reference for future design and engineering work.

It is written for continuity, not marketing.

## Product Definition

SciPlot God is a desktop workflow system for turning scientific data into publication-ready figures, cleaned data workbooks, composed multi-panel layouts, and controlled code-driven outputs.

The retained app model contains four primary workbenches:

1. Plot
2. Data Studio
3. Composer
4. Code Console

Everything else is utility.

## Canonical Internal Workflow Vs User-Visible UI Workflow

Canonical workflow and user-visible UI workflow are different layers.

- Canonical internal workflow may include hidden processing stages for detection, normalization, mapping, validation, handoff, automation, or artifact management.
- User-visible UI workflow should surface only the points where the user must orient, decide, review, adjust, confirm, export, or hand off work.
- Internal system steps may stay hidden or be merged into a broader work surface.
- Mock or navigation design must not mirror backend pipelines one step for one screen.

Default user-visible workflow compression for future mock work:

- `Plot`: `Import -> Template -> Refine & Export`
- `Data Studio`: `Import -> Group Review -> Compare Preview -> Export / Open in Plot`
- `Composer`: `Assets -> Compose -> Review -> Export`
- `Code Console`: `Context -> Code -> Run -> Outputs`

## Primary Workbenches

### Plot

Purpose:

- turn a bound dataset into a publication-ready figure export bundle

Canonical workflow:

- Import
- Inspect
- Template
- Refine
- Preflight
- Export
- optional handoff to Composer

Normalization rules:

- sheet selection lives inside `Import`
- preview lives inside `Refine`
- readiness and preflight live inside `Refine`
- export is the close of the Plot workflow, not a separate app-level workbench

Default user-visible UI flow:

- `Import -> Template -> Refine & Export`

### Data Studio

Purpose:

- turn raw experimental files into structured workbooks, comparison sets, and exportable figures inside one workbench

Canonical workflow:

- Choose Template
- Preview Source or Create Template
- Build Workbook
- Review
- Compare
- Export / Open in Plot

Normalization rules:

- user-facing name is `Data Studio`
- the workbench is template-first: `Use Existing Template` is the fast daily path, while `Create Template` should start from one real sample file plus recommended regions
- internal tensile-specific seams may remain as one built-in template family, but they must not define the product semantics
- the native shell should mirror Plot-level density: top source bar, left selection rail, one central focused preview surface, and a compact right inspector
- focused workbook controls the main preview; primary workbook controls Plot handoff and stays a separate visible state
- compare/export outputs should remain in compact inspector surfaces or native open/reveal actions rather than taking over the main canvas

Default user-visible UI flow:

- `Import -> Group Review -> Compare Preview -> Export / Open in Plot`

### Plot / Data Studio Boundary

Plot and Data Studio share sidecar services, but they do not own the same product job.

- Plot owns single-figure work: source inspect, ranked template recommendation, typed data variables/transforms, figure refinement, preflight, preview/export, and Plot project durability.
- Data Studio owns intake and workbook work: raw-source template mapping, workbook creation/import, specimen filtering, comparison context, comparison figure export, and Data Studio project durability.
- `Open in Plot` is the explicit boundary crossing. Data Studio passes a workbook URL, preferred sheet, selected template, render options, and fit options into Plot; Plot then resumes its normal inspect/preview path instead of using a Data Studio-only renderer.
- Curve-only or no-compare Data Studio outputs may auto-open Plot. Compare-capable workbooks stay in Data Studio unless the user explicitly opens a figure in Plot.

### Composer

Purpose:

- arrange graph exports, assets, and text on a controlled multi-panel canvas

Canonical workflow:

- Assets
- Layout
- Compose
- Inspect/Arrange
- Review
- Export

Normalization rules:

- canvas-first, not form-first
- preserve grid, crop, overlap, review, and export invariants
- keep editable PDF export behavior intact

Default user-visible UI flow:

- `Assets -> Compose -> Review -> Export`

### Code Console

Purpose:

- provide a serious scripting and controlled-runner surface for advanced figure work

Canonical workflow:

- Bind Context
- Inspect Inputs
- Prompt/Code
- Run
- Outputs
- Handoff

Normalization rules:

- Code Console is primary, not secondary
- it should inherit contract-bound context from Plot or direct data binding
- prompt generation, runner context, and run outputs must stay repo-native and controlled

Default user-visible UI flow:

- `Context -> Code -> Run -> Outputs`

## Repo-Grounded Action Inventory

This section is the maintainer-facing action and control inventory for mock completion and future UI restoration work.

It distinguishes current confirmed support from recent integrated history and from actions that should not be assumed.

### Plot

Confirmed in current repo/docs/tests:

- import a data file and choose a sheet
- inspect input structure through `/inspect-file`
- use ranked recommendation payload returned by `/inspect-file` for template selection
- preview the active figure through `/render-preview`
- run export validation through `/preflight-render`
- export the figure bundle through `/export-render`
- adjust only contract-backed render options such as size, scale, style, palette, reverse-x, baseline, and colorbar where supported

Strongly implied by recent integrated history:

- reveal or review managed export artifacts after export
- optional handoff from Plot into Composer after the figure is ready

Do not assume without new evidence:

- user-facing legend-order controls
- user-facing figure-component ordering controls
- a separate preflight page outside the refine/export surface

### Data Studio

Confirmed in current repo/docs/tests:

- list, create, update, and delete reusable templates through `/data-studio/templates`
- preview raw source structure and recommended fields through `/source-table-preview`
- validate unsaved template drafts through `/data-studio/template-preview`
- build a workbook from raw files through `/data-studio/build-workbook`
- import an existing workbook through `/data-studio/import-workbook`
- preview comparison figures through `/data-studio/comparison-preview`
- export comparison figures through `/data-studio/comparison-export`
- normalize saved session payloads through `/data-studio/session/normalize`
- explicitly hand workbook outputs into Plot through `Open in Plot`

Strongly implied by recent integrated history:

- mixed intake of raw `csv/txt/tsv/xls/xlsx/xlsm` files and already-built workbooks in one workbench
- tensile remains the default built-in template family and should still auto-match existing tensile raw fixtures
- template creation should start from recommended regions rather than blank schema entry

Do not assume without new evidence:

- inline spreadsheet-style editing
- exposed detect/map/normalize toggles as separate user controls
- ordering or sorting controls beyond the prepared comparison outputs themselves

### Composer

Confirmed in current repo/docs/tests:

- import graph or asset files through `/composer/import-panels`
- preview the composition through `/compose-preview`
- export the composition PDF through `/compose-export`
- generate compact presets through `/composer/three-up` and `/composer/two-up-editorial`
- request panel thumbnails through `/panel-thumbnail`
- preserve drawable order through `z_index` and sorted drawable rendering
- preserve automatic graph panel labels through `auto_labels`

Strongly implied by recent integrated history:

- add graph, add asset, and add text/label actions in the workbench surface
- layer-order controls for `Forward`, `Back`, `To front`, and `To back`
- custom labels, binding, crop, lock, and hide controls for selected drawables

Do not assume without new evidence:

- a broader preset gallery beyond the shipped preset helpers
- multi-page export
- arbitrary figure-numbering schemes beyond `auto_labels` and custom labels

### Code Console

Confirmed in current repo/docs/tests:

- bind current data and Plot context into the workbench
- import a data file directly into Code Console
- generate fixed prompt/context bundles for external AI use
- edit code on one controlled runner surface
- run repo-native Python
- show runner status, stdout, stderr, exit code, duration, generated files, and previews
- open the managed output folder
- review outputs on a dedicated output surface

Strongly implied by recent integrated history:

- hand generated outputs back into Plot or Composer

Do not assume without new evidence:

- chat-style interaction
- arbitrary shell access
- package-install controls
- persistent background run management beyond controlled managed outputs

## App-Level IA

### Canonical Tree

- App
- Plot
- Data Studio
- Composer
- Code Console
- Utilities
- Quick open
- Recent files
- Open/save actions
- Managed files
- Appearance/runtime controls

### IA Principles

- Sidebar primary navigation should expose only the four retained workbenches.
- Plot local stages are local to Plot and must not reappear as global app destinations.
- UI surfaces should stay decision-oriented and must not expose every internal system stage.
- Utilities may exist, but must stay secondary in naming, placement, and visual hierarchy.
- Start/Home is not a retained destination in the long-term IA.
- Project is not a primary product concept.
- Settings is not a primary product concept.

## Naming Rules

- Use `Data Studio` for product-facing references.
- Use `tensile` only where an implementation, route, schema, fixture, or scientific domain concept is specifically tensile-related.
- Avoid product copy that implies the whole app is a plot wizard or a plot-only tool.

## Utility vs Primary

### Primary

- Plot
- Data Studio
- Composer
- Code Console

### Utility

- recents
- open/save
- managed storage
- appearance/runtime controls
- project persistence where still useful for Composer or specialized flows
- data-template helpers and reveal/open-path actions if reintroduced

Utilities support workbenches. They do not define the app.

## Deprecated From Active Product Scope

These concepts are deprecated from active product scope and should not drive future IA:

- Start/Home as a persistent primary destination
- Project as a top-level product area
- Settings as a top-level product area
- app shells that present only Plot substeps as the whole product
- mock or docs that imply the app is effectively a single plot wizard with extra tools hanging off it

## Preserved Foundations

The following foundations must be preserved for future implementation work:

- contract-first metadata from `/meta` and `/plot-contract`
- Plot export bundles and submission report artifacts
- Data Studio handoff into Plot
- Composer v2 geometry and export invariants
- controlled Code Console semantics when restored or expanded
- native macOS hosting in `app/macos`

## Guidance For Future UI Iteration

A future IA/UI iteration should:

- use this document as the app-level IA truth
- preserve the four-workbench shell
- keep utilities subordinate
- keep Plot steps inside Plot
- keep user-visible workflow simpler than canonical internal workflow
- merge hidden processing stages unless the user must meaningfully act there
- express Data Studio as the template-first workbook and comparison workbench even if internal tensile seams remain
