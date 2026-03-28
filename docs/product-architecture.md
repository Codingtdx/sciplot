# SciPlot God Product Architecture

This document is the canonical app-level product architecture reference for future design and engineering work.

It is written for continuity, not marketing.

## Product Definition

SciPlot God is a desktop workflow system for turning scientific data into publication-ready figures, cleaned data workbooks, composed multi-panel layouts, and controlled code-driven outputs.

The retained app model contains four primary workbenches:

1. Plot
2. Data Cleanup
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
- `Data Cleanup`: `Import -> Review & Clean -> Compare -> Export / Open in Plot`
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

### Data Cleanup

Purpose:

- prepare incoming experimental data into plot-ready and compare-ready structured outputs

Canonical workflow:

- Intake
- Detect
- Clean
- Replicates
- QC Compare
- Export / Open in Plot

Normalization rules:

- user-facing name is `Data Cleanup / 数据整理`
- internal tensile-specific backend seams may remain
- the workbench should grow from tensile-only preparation toward broader cleanup framing without breaking current preprocessing flows

Default user-visible UI flow:

- `Import -> Review & Clean -> Compare -> Export / Open in Plot`

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

## App-Level IA

### Canonical Tree

- App
- Plot
- Data Cleanup
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

- Use `Data Cleanup / 数据整理` for product-facing references.
- Use `tensile` only where an implementation, route, schema, fixture, or scientific domain concept is specifically tensile-related.
- Avoid product copy that implies the whole app is a plot wizard or a plot-only tool.

## Utility vs Primary

### Primary

- Plot
- Data Cleanup
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
- Data Cleanup handoff into Plot
- Composer v2 geometry and export invariants
- controlled Code Console semantics when restored or expanded
- Tauri-only desktop hosting
- the protected current mock under `app/desktop/src/mock/**`
- the protected current mock mount in `app/desktop/src/main.tsx`

## Guidance For Future Mock Redesign

A future mock redesign should:

- use this document as the app-level IA truth
- leave the current protected mock untouched until a deliberate replacement lands
- design a true four-workbench shell rather than extrapolating from the protected plot-only mock
- keep utilities subordinate
- keep Plot steps inside Plot
- keep user-visible workflow simpler than canonical internal workflow
- merge hidden processing stages unless the user must meaningfully act there
- express Data Cleanup in product-facing language even if internal tensile seams remain

## Current Protected Mock Status

The current mock remains protected and runnable.

Important caveat:

- it demonstrates a Plot-only local flow
- it is not the authoritative whole-app navigation model
- it must not be used to justify reintroducing Start/Home, Project, or Settings as primary destinations
