# SciPlot God

SciPlot God is a desktop publication workflow tool for scientific figures.

The product is organized around four retained primary workbenches:

1. Plot
2. Data Cleanup
3. Composer
4. Code Console

These are the only workbenches that should shape app-level information architecture going forward.

## Canonical Vs User-Visible Workflow

- Canonical workflows describe the full product logic, including hidden processing, validation, normalization, mapping, and handoff stages.
- User-visible UI workflows should expose only the surfaces where the user must orient, decide, review, adjust, confirm, export, or hand off work.
- Internal system steps may stay hidden or be merged into a broader work surface.
- The mock should not turn every backend step into a page or primary navigation item.

Default user-visible flow examples for future mock work:

- `Plot`: `Import -> Template -> Refine & Export`
- `Data Cleanup`: `Import -> Review & Clean -> Compare -> Export / Open in Plot`
- `Composer`: `Assets -> Compose -> Review -> Export`
- `Code Console`: `Context -> Code -> Run -> Outputs`

## Core Workbenches

### Plot

Canonical workflow:

`Import -> Inspect -> Template -> Refine -> Preflight -> Export -> optional handoff to Composer`

Notes:

- Sheet selection belongs inside `Import`.
- Preview belongs inside `Refine`.
- Readiness and preflight belong inside `Refine`, not as separate app-level destinations.

### Data Cleanup

Canonical workflow:

`Intake -> Detect -> Clean -> Replicates -> QC Compare -> Export / Open in Plot`

Notes:

- User-facing language is `Data Cleanup / 数据整理`.
- Current v1 backend may still be powered by tensile-oriented routes and terminology.
- Future UI and docs should present this as a broader cleanup and preparation workbench, not a tensile-only product area.

### Composer

Canonical workflow:

`Assets -> Layout -> Compose -> Inspect/Arrange -> Review -> Export`

Notes:

- Composer is canvas-first.
- Keep layout, crop, overlap, and export invariants intact.
- Project files may still exist as utility persistence, but `Project` is not a primary product area.

### Code Console

Canonical workflow:

`Bind Context -> Inspect Inputs -> Prompt/Code -> Run -> Outputs -> Handoff`

Notes:

- Code Console is a first-class workbench, not a secondary utility.
- It should preserve contract-bound context and controlled runner semantics.
- It is the scripting and AI-control surface for advanced work, not a side panel bolted onto Plot.

## App-Level IA Principles

- Primary app navigation should expose only the four retained workbenches.
- `Start`, `Home`, and other launchpad-style destinations are not part of the long-term primary IA.
- `Project`, `Settings`, recents, managed files, appearance controls, open/save actions, and similar affordances are utilities, not primary workbenches.
- Plot may still have its own local multi-step workflow, but those local steps are not top-level app destinations.
- The supported desktop frontend is the native macOS app under `app/macos`.
- The current protected mock under `app/desktop/src/mock/**` is a plot-flow-only reference and is not the authoritative whole-app IA.

## Desktop Development

- Use `Launch_Plotter.command` to build and open the supported native macOS frontend.
- For direct validation, run:
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' build`
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' test`
- Treat `app/desktop` as a legacy/reference area for the protected mock and migration history, not as the supported desktop runtime.

## Utilities, Not Primary Workbenches

The following concepts may remain in the codebase as supporting utilities:

- recent files and session recovery
- open/save actions
- managed export folders and managed run artifacts
- appearance/runtime controls
- project persistence where still useful for Composer or specialized flows

These utilities must remain visually and structurally subordinate to the four primary workbenches.

## Deprecated From Active Product Scope

The following concepts should not return as first-class app areas:

- Start/Home as a primary destination
- Project as a primary destination
- Settings as a primary destination
- product framing that implies the whole app is only a staged Plot wizard

## Guidance For Future Mock Redesign

Any future mock redesign should:

- preserve the protected current mock until deliberately replaced
- treat the four-workbench model as the app-level IA truth
- keep Plot local steps inside Plot
- distinguish canonical internal workflow from simplified user-visible workflow
- merge hidden/system stages into broader decision-oriented work surfaces when the user does not need to act on them
- present Data Cleanup with product-facing naming, even if tensile-specific backend seams remain underneath
- keep utilities subordinate rather than promoting them into sidebar peers

## More Detail

See [docs/product-architecture.md](docs/product-architecture.md) for the detailed product architecture, workflow normalization rules, repo-grounded workbench action inventory, IA tree, and deprecation guidance.
