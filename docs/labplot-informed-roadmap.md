# LabPlot-Informed SciPlot Desktop Roadmap

This roadmap turns LabPlot research into SciPlot architecture work while preserving SciPlot's Apache-2.0 licensing and current desktop product model.

LabPlot is a strategic reference, not a vendored dependency. Its public behavior, SDK concepts, documentation, and user-facing workflows can guide SciPlot, but GPL-2.0-or-later source files from LabPlot must not be copied into this repository. New SciPlot behavior should be implemented clean-room in the existing Python sidecar, SwiftUI macOS app, and contract-backed rendering stack.

## Clean-room policy

- SciPlot remains Apache-2.0 unless maintainers make an explicit future relicensing decision.
- LabPlot GPL source may be read for orientation, but implementation must be authored as SciPlot-native code.
- The executable guard for this boundary is `scripts/check_labplot_cleanroom.py`; the blocking gate runs it as `labplot_cleanroom`.
- Acceptable borrowing: feature taxonomy, UX principles, public behavior descriptions, test ideas, data-flow shapes, and architecture patterns.
- Not acceptable: copied LabPlot C/C++/Qt headers, implementation bodies, embedded GPL source modules, or static/dynamic linking to LabPlot core without a separate licensing decision.

## SciPlotDocumentGraph

LabPlot's project/aspect tree maps to a future module-scoped document graph, tentatively named `SciPlotDocumentGraph`.

The graph is not a global Project Explorer and must not restore a shared workbench shell. It is an internal persistence and command model stored through the existing `.sciplot` save/open schema path. Each product window owns its visible workflow, while the graph provides stable identities, dependencies, undoable edits, and project roundtripping.

Initial graph node families:

| LabPlot reference | SciPlot graph family | Owning module |
| --- | --- | --- |
| Spreadsheet/Matrix | Typed table, matrix, transformed view, variables, fit results | Data Studio and Plot Data Workbook |
| Worksheet/CartesianPlot | Plot scene, figure page, plot area, composer panel | Plot and Composer |
| Axis/Legend/XYCurve | Contract-backed plot objects and render options | Plot |
| Analysis curves/NSL | Fit, smooth, FFT, statistics, transforms | Sidecar services surfaced in Plot/Data Studio |
| Import filters | Source preview/import capability registry | Sidecar `/meta` and import routes |

## Contract and capability catalogs

All public capability expansion should continue the current contract pattern.

- Plot templates, styles, palettes, themes, defaults, editable options, gallery metadata, and smoke surface stay rooted in `src/plot_contract.json`.
- Runtime capability catalogs for data containers, plot objects, analysis operations, and import filters should be exposed through `/meta` or other explicit typed endpoints, not local macOS constants.
- Render/data extensions must use typed payloads like the existing `reference_guides`, `shape_annotations`, `data_transforms`, `fit-analysis`, analytical layers, axis breaks, and project bundle payloads.
- Unsupported capabilities should be disabled with help text in macOS and rejected with explicit sidecar validation errors in backend paths.

## Command and undo architecture

Large-app behavior should be command-oriented without importing LabPlot's Qt command framework.

- macOS emits typed edit commands for user intent: add object, bind data, edit axis, edit series style, reorder legend, create transform, place annotation, and update analysis settings.
- Sidecar validates and normalizes payloads before preview/export/project save uses them.
- Swift `UndoManager` stores reversible edits at the module session level, using the same typed payloads that sidecar accepts.
- Async refresh keeps the existing latest-write-wins pattern through `AsyncLatestTaskCoordinator` and `KeyedAsyncLatestTaskCoordinator`.
- Backend remains authoritative for data transforms, fit/function evaluation, validation, final export, and project restore.

## Desktop product boundary

SciPlot should grow into a large desktop plotting application without copying LabPlot's global shell.

- Preserve the Launcher plus four singleton module windows: Plot, Data Studio, Composer, and Code Console.
- Keep `Command-1/2/3/4` opening or focusing the corresponding module window.
- Do not introduce a global Project Explorer, shared left rail, or Start/Home/Project workspace as a primary product area.
- Module-local object lists are allowed only when they represent real current work: workbook groups in Data Studio, plot source/type selection in Plot, panels in Composer, and bindings/outputs in Code Console.
- Project save/open continues through `.sciplot` bundles and sidecar schema migration.

## Phasing

1. **Foundation:** keep this roadmap, clean-room guard, and blocking-gate integration in place.
2. **Document graph schema:** introduce internal typed graph snapshots behind existing project save/open payloads, with no visible global Project Explorer.
3. **Capability catalogs:** move import/data/analysis capability surfaces into explicit sidecar metadata consumed by macOS.
4. **Plot object model:** represent axes, legends, series, guides, annotations, functions, and advanced axes as graph-addressable typed objects.
5. **Analysis expansion:** add SciPlot-owned smooth, FFT, statistics, baseline, data reduction, and import filter capabilities behind typed sidecar APIs.
6. **Large-app polish:** deepen native undo, object selection, inspector routing, project restore, and cross-module handoff while preserving the four-window model.

## References

- LabPlot repository: https://github.com/KDE/labplot
- KDE Invent main repository: https://invent.kde.org/education/labplot
- LabPlot feature overview: https://docs.labplot.org/en/getting_started/features.html
- LabPlot Project Explorer: https://docs.labplot.org/en/interface/interface_project_explorer.html
- LabPlot AbstractAspect SDK concept: https://docs.labplot.org/en/sdk/python/api/abstract_classes/AbstractAspect.html
- LabPlot Spreadsheet concept: https://docs.labplot.org/en/data_containers/data_containers_spreadsheet.html
- LabPlot license metadata: https://github.com/KDE/labplot/blob/master/.reuse/dep5
