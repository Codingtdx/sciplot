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
   - Launcher: choose each module and verify the primary action opens the real module workflow
   - Plot: Import -> Inspect -> Template -> Refine -> Preflight -> Export
   - Data Studio: Import -> Group Review -> Compare Preview -> Export/Open in Plot
   - Composer: preview/export with layer/hidden/lock semantics
   - Code Console: context bind -> run -> outputs/reveal

## 3) Decision Records

### 2026-04-28: Plot micro-polish v4 and Pro workspace alignment

- Change:
  - Tightened Plot's Pixelmator-style workspace without changing the backend contract, project schema, or preview PNG/PDF semantics.
  - Moved Plot's primary data/workbook utility out of the left panel: `Data Workbook` is now a toolbar icon action that opens the workbook sheet on `Source Data` by default.
  - Simplified `PlotSourceTypePanel` to a compact sheet picker plus five recommended plot-type thumbnail cards from `session.templateGalleryItems`.
  - Added `PlotTypeChooserSheet` and `PlotTypeCard`: `More` opens a searchable native sheet backed by `session.plotTypeItems`, and choosing an item still calls the existing `chooseTemplate` path.
  - Removed the left-panel file name, Import/Open button, source helper copy, and default `Data Tables / Source Data / Transformed / Variables / Fit` rows.
  - Added shared Pro workspace corner metrics so outer glass panels use a consistent larger radius and inner rows/cards use a smaller radius.
  - Lightly aligned other modules with the same layout grammar:
    - Data Studio left rail now includes figure family/template choice near `Workbook Groups`.
    - Composer keeps its real asset library / canvas / inspector split and continues routing import through toolbar/menu.
    - Code Console left rail now stays focused on bound context; `Open Source` and `Reveal Source` moved to inspector `Advanced`.
  - Strengthened `scripts/check_macos_gui_presentation.py` and `tests/test_check_macos_gui_presentation.py` so Plot cannot regress to left-panel imports, file names, Data Table rows, or right-rail popover creation.

- User-visible impact:
  - Plot's left side is calmer and closer to the requested drawing order: pick sheet, pick one of five likely chart types, or open `More` for the full catalog.
  - Import/Open/Export/Help/Inspector stay in the right-side native toolbar cluster, and Data Workbook is a single utility icon instead of four persistent left-panel entries.
  - Data Studio, Composer, and Code Console now read more like sibling Pro workspaces without adding fake Pixelmator tools or changing their business flows.

- Decision Record:
  - First-principles motivation: the left panel should answer the user's immediate setup question, “which sheet and which chart type?”, while the right inspector answers refinement questions. Putting import buttons, file names, and workbook tabs in the same panel made the left side feel like a mixed dashboard rather than a selection surface.
  - Rejected keeping Data Workbook tab rows in the left panel because they duplicate right-side adjustment categories and pull data-preparation utilities into the primary plotting choice surface.
  - Rejected showing all chart types by default because it reduces thumbnail legibility and makes the recommendation payload feel less useful; the full list remains one click away in `More`.
  - Current boundary: other modules received layout-grammar alignment only. Their deeper interaction taxonomy should be handled in module-specific follow-up rounds.
  - Failure condition: if Plot's left panel regains Import/Open, filename copy, `Data Tables` rows, or if `More` becomes a rail popover instead of a chooser sheet, the v4 model has regressed.

- Risks and rollback points:
  - Plot type selection now has two presentation surfaces: five-card default and searchable full chooser. Rollback points are `PlotWorkbenchView.swift` and `PlotTemplateView.swift`.
  - Toolbar Data Workbook behavior now defaults to `Source Data`; inspector-specific workbook links still pass their explicit tabs. Rollback points are `PlotSession.swift`, `AppModel.swift`, `RootSplitView.swift`, and `PlotInspectorView.swift`.
  - Data Studio figure choice moved from the center context bar to the left rail. Rollback point is `DataStudioWorkbenchView.swift` if preview refresh or focus state feels less discoverable.
  - Code Console source open/reveal moved to inspector `Advanced`. Rollback points are `CodeConsoleWorkbenchView.swift` and `CodeConsoleContextView.swift`.

- Actual regression results:
  - `git diff --check`: passed.
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py -q`: passed, 3 tests.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests/testOpeningDataWorkbookDefaultsToSourceDataFromToolbar -only-testing:SciPlotGodMacTests/AppModelTests/testPlotDataWorkbookToolbarActionOpensSourceDataTab`: passed, 2 tests.
  - `.venv/bin/python -m pytest tests`: passed, 277 tests.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed, 197 tests.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
  - Gate details: `clean_repo`, `ruff`, `mypy`, `pytest` 277 tests, `smoke_check`, `macos_gui_presentation`, `xcodebuild build`, and `xcodebuild test` 197 tests all passed.
  - Known environment warning: Xcode reports CoreSimulator service/version warnings during hosted macOS operations; macOS build and tests still passed.
  - Manual inner-beta evidence remains pending and unenforced: Plot import/preview/export, Data Studio import/open Plot, and overlay save/reopen must not be marked complete without a real evidence bundle.

### 2026-04-28: Plot interaction model v3, data/type left and adjustment rail right

- Change:
  - Replaced Plot's left object/layer panel with `PlotSourceTypePanel`.
  - Left Plot panel now owns Import/Open, current file, sheet switching, full contract/backend-fed plot type selection, and `Data Workbook` tab entry points (`Source Data`, `Transformed`, `Variables`, `Fit`).
  - Replaced the far-right popover tool palette with `PlotAdjustmentRail`.
  - Right rail categories are fixed to `Figure`, `Axes`, `Legend`, `Guides`, `Fit`, `Functions`, `Annotations`, and `Advanced Axes`; clicking a category switches the right inspector instead of opening a popover.
  - Added `PlotAdjustmentCategory`, `PlotAdjustmentRailItem`, `PlotSession.selectedPlotAdjustmentCategory`, and `PlotSession.plotTypeItems`.
  - Retained `PlotTool` only as a keyboard/menu compatibility layer; tool shortcuts route into adjustment categories and do not create objects.
  - Moved guide/function/text/shape creation into inline controls inside the corresponding inspector category.
  - Strengthened `scripts/check_macos_gui_presentation.py` and `tests/test_check_macos_gui_presentation.py` to forbid the old object left panel, floating tool palette, and right-rail popovers.

- User-visible impact:
  - Plot now reads as a plotting workflow: choose data/sheet/type on the left, refine figure/axes/legend/guides/fit/functions/annotations/advanced axes on the right.
  - The right rail no longer behaves like a generic drawing tools strip, and it no longer opens small creation popovers.
  - `Data Cursor` remains hidden until hit-testing metadata exists.

- Decision Record:
  - First-principles motivation: scientific plotting starts from data shape and figure type, then proceeds through refinement categories. The previous layer/tool arrangement copied Pixelmator's spatial shell but gave Plot the wrong interaction hierarchy.
  - Rejected keeping overlay objects in the left panel because it made the left side compete with plot type and sheet choice.
  - Rejected popover-based creation on the right rail because category buttons should select inspector state, matching the native sidebar/inspector pattern already working well.
  - Current boundary: this round is front-end interaction restructuring only. It does not change sidecar APIs, render contract, project schema, or preview PNG/PDF semantics.
  - Failure condition: if the far-right rail starts creating objects directly, showing popovers, or if the left panel regains fit/function/guide/text/shape object rows, the v3 model has regressed.

- Risks and rollback points:
  - Plot category routing is now split between `PlotInspectorMode.swift`, `PlotSession.swift`, and `PlotInspectorView.swift`; rollback these with `PlotWorkbenchView.swift` if the inspector fails to follow right-rail selection.
  - `plotTypeItems` intentionally exposes the full contract/recommendation list while the old gallery remains compact; rollback point is `PlotSessionPresentation.swift` if a legacy compact template surface depends on the previous behavior.
  - Presentation gate rollback lives in `scripts/check_macos_gui_presentation.py` and `tests/test_check_macos_gui_presentation.py`.

- Actual regression results:
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py -q`: passed, 3 tests.
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests/testActivatingPlotToolsDoesNotCreatePlotObjects -only-testing:SciPlotGodMacTests/PlotSessionTests/testFunctionToolShortcutRoutesToFunctionAdjustmentWhenTemplateSupportsIt -only-testing:SciPlotGodMacTests/PlotSessionTests/testPlotTypeItemsExposeFullContractFedListBeforeImport`: passed, 3 tests.
  - `.venv/bin/python -m pytest tests`: passed, 277 tests.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed, 195 tests.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
  - Gate details: `clean_repo`, `ruff`, `mypy`, `pytest` 277 tests, `smoke_check`, `macos_gui_presentation`, `xcodebuild build`, and `xcodebuild test` 195 tests all passed.
  - Known environment warning: Xcode reports CoreSimulator service/version warnings during hosted macOS operations; macOS tests still passed.
  - Manual inner-beta evidence remains pending and unenforced: Plot import/preview/export, Data Studio import/open Plot, and overlay save/reopen were not marked complete without a real evidence bundle.

### 2026-04-28: Pixelmator-Pro window model and Plot GUI rebuild v2

- Change:
  - Replaced the old single-window global workbench shell with one default Launcher window plus four singleton module windows:
    - `WindowGroup("SciPlot God", id: "launcher")`
    - `Window("Plot", id: Workbench.plot.windowSceneID)`
    - `Window("Data Studio", id: Workbench.dataStudio.windowSceneID)`
    - `Window("Composer", id: Workbench.composer.windowSceneID)`
    - `Window("Code Console", id: Workbench.codeConsole.windowSceneID)`
  - Added `Workbench.windowSceneID` and focused command routing so `Command-1/2/3/4`, Import/Open, Export, Save Project, Help, and Inspector act on the focused module window instead of a visible global module switcher.
  - Rebuilt the Launcher as a clean glass opener: module list plus real actions, with no blue accent line, central sketch, fake visual preview, or decorative Pixelmator tool inventory.
  - Rebuilt Plot as a Pixelmator-Pro grammar workspace:
    - left `PlotLayerPanel`
    - central white preview stage
    - right `PlotInlineInspectorPanel`
    - far-right `PlotVerticalToolRail`
  - Removed the old module-window path through `NavigationSplitView`, `WorkbenchSidebarRail`, `WorkbenchContentShell`, and `InspectorChromeRoot`.
  - Kept `AppCommands` attached exactly once so the app menu no longer repeats `Workbench` / `Plot Tools` for every scene.
  - Tightened GUI presentation checks so module windows cannot restore the old shell, and Plot's left panel cannot restore `Source` / `Objects` / `Templates` section labels or `No source` empty copy.
  - Added a presentation gate test that rejects duplicate command attachment.
  - Kept backend sidecar API, plot contract, PNG/PDF preview payloads, and `.sciplotgod` project schema unchanged.

- User-visible impact:
  - Opening the app shows only the Launcher. Choosing Plot, Data Studio, Composer, or Code Console opens/focuses that module in its own window.
  - Module windows no longer show a far-left module switcher or stacked project/module/content headers.
  - Plot now follows the requested Pixelmator-style spatial layout: layers/objects left, figure page center, scientific inspector right, tools on the far right.
  - Data Studio, Composer, and Code Console keep their existing internal workflows but live in independent module windows.

- Decision Record:
  - First-principles motivation: module choice is an app-level opening action, not persistent navigation inside every module. Once a user enters Plot, the screen should spend pixels on Plot concepts rather than cross-module switching.
  - Rejected keeping `RootSplitView` as the visual owner because it forces a shared shell and multi-header shape that directly conflicts with the Pixelmator reference.
  - Rejected copying Pixelmator's editing tools because they are not SciPlot domain concepts; the far-right rail only exposes real Plot typed actions.
  - Current boundary: this round changes front-end scene/layout/command routing only. Data Studio, Composer, Code Console deep redesign and a Swift-native plotting engine remain out of scope.
  - Failure condition: if commands start acting on the wrong focused module window, or `selectedWorkbench` becomes visible navigation again, the window model has regressed.

- Risks and rollback points:
  - Window routing now depends on focused values and `openWindow`; rollback points are `app/macos/Sources/App/SciPlotGodApp.swift`, `app/macos/Sources/App/AppCommands.swift`, `app/macos/Sources/App/AppModel.swift`, and `app/macos/Sources/App/RootSplitView.swift`.
  - Launcher primary actions now open/focus module windows before triggering the real workflow; rollback point is `app/macos/Sources/App/LauncherView.swift`.
  - Plot's left panel is no longer the previous template rail. Roll back `app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`, `PlotRefineView.swift`, and `PlotInspectorMode.swift` if object selection or template choice regresses.
  - Presentation gate rollback lives in `scripts/check_macos_gui_presentation.py` and `tests/test_check_macos_gui_presentation.py`.

- Actual regression results:
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py -q`: passed, 3 tests.
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/AppModelTests/testWorkbenchWindowIDsAreStableSingletonSceneIDs -only-testing:SciPlotGodMacTests/AppModelTests/testExplicitWorkbenchActionsDoNotNeedVisibleWorkbenchSwitching -only-testing:SciPlotGodMacTests/AppModelTests/testLauncherStartsPresentedAndRoutesModuleActionsToRealSessions`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test`: passed, 193 tests.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
  - Gate details: `clean_repo`, `ruff`, `mypy`, `pytest` 277 tests, `smoke_check`, `macos_gui_presentation`, `xcodebuild build`, and `xcodebuild test` 193 tests all passed.
  - Lightweight desktop smoke after the final build:
    - Launching `app/macos/.derivedData/Build/Products/Debug/SciPlot God.app` produced one onscreen `SciPlot God` Launcher window.
    - The menu bar exposed one set of `Workbench` and `Plot Tools` menus.
    - Choosing `Workbench -> Plot` produced an onscreen `Plot` singleton window while keeping the Launcher onscreen.
  - Computer Use accessibility lookup could not attach to this debug app window (`cgWindowNotFound`), so visual smoke used the system CoreGraphics window list instead.
  - Known environment warning: Xcode reports CoreSimulator service/version warnings during hosted macOS operations; macOS build still passed.
  - Manual inner-beta evidence remains pending and unenforced: Plot import/preview/export, Data Studio import/open Plot, and overlay save/reopen were not marked complete without a real evidence bundle.

### 2026-04-28: Pixelmator-style Launcher, Plot shell, and PNG live preview

- Change:
  - Added a native Launcher-first entry surface in `app/macos/Sources/App/LauncherView.swift` and routed it through `AppModel.isLauncherPresented`.
  - Launcher module actions are real workflow entrypoints:
    - Plot import/open project through the existing Plot importer
    - Data Studio raw import wizard
    - Composer import menu
    - Code Console context importer
  - Reworked Plot into a dark pro workspace:
    - left Plot library contains Source/Data Workbook utility, Templates, and Objects/Layers
    - center stage shows a white figure/page preview
    - tool dock uses existing real Plot tools only; `Data Cursor` stays out of the main dock
    - right inspector remains contextual scientific editing
  - Added Plot PNG live preview payloads:
    - `PreviewItemResponse.png_base64` in sidecar schema
    - Matplotlib `/render-preview` now serializes both PDF and 160 dpi PNG
    - macOS `PreviewItemResponse.pngBase64` decodes the optional PNG and Plot preview prefers it before PDF fallback
  - Updated GUI presentation gate and tests to require Launcher + Plot dark workspace + denser inspector policy.
  - Updated `README.md` and `AGENTS.md` to remove the old no-launcher / templates-only rail / `360 / 400 / 460` inspector conflicts.
  - Added GUI smoke snapshot coverage for Launcher, Plot empty workspace, and Plot imported workspace while preserving existing imported inspector/data workbook/Data Studio figure snapshots.

- User-visible impact:
  - App opens to a Launcher where users choose Plot, Data Studio, Composer, or Code Console.
  - Plot now feels closer to a pro macOS graphics workspace without adding fake Pixelmator tools.
  - Plot preview can update from a lighter bitmap payload while PDF remains the exact export-grade fallback.
  - Inspector is denser at `320 / 360 / 420`.

- Decision Record:
  - First-principles motivation: module choice is now a real first interaction, and Plot needs one coherent authoring space where source, templates, and scientific objects sit next to the figure stage.
  - Rejected copying Pixelmator tool inventory because those tools are not SciPlot domain concepts.
  - Rejected a Swift-native plotting rewrite for v1 because Swift Charts/Canvas would duplicate contract-owned style, axes, broken axes, overlays, and export semantics.
  - Current boundary: PNG preview is a live-view optimization only. PDF export and backend Matplotlib rendering remain authoritative.
  - Failure condition: if future Swift UI starts recomputing plot geometry/style locally, preview/export/project replay can diverge from sidecar semantics.

- Risks and rollback points:
  - `PreviewItemResponse` now carries optional PNG; older comparison-preview paths omit it intentionally. Roll back `app/sidecar/schemas_common.py`, `app/sidecar/schemas_render.py`, and `app/macos/Sources/Infrastructure/SidecarModelsCommon.swift` if clients cannot tolerate the added field.
  - Launcher-first state changes app startup semantics. Roll back `LauncherView.swift`, `RootSplitView.swift`, and `AppModel.swift` if launch restoration or document open routing regresses.
  - Plot library is broader than the previous templates-only rail. Roll back `PlotWorkbenchView.swift`, `PlotRefineView.swift`, and `PlotInspectorMode.swift` if the new spatial grouping interferes with import/template/refine flow.
  - GUI gate rollback lives in `scripts/check_macos_gui_presentation.py` and `tests/test_check_macos_gui_presentation.py`.

- Actual regression results:
  - `.venv/bin/python -m pytest tests/test_sidecar_render.py::test_render_preview_returns_png_live_preview_payload tests/test_check_macos_gui_presentation.py -q`: passed, 3 tests.
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/SchemaDecodingTests/testDecodePreviewItemPayloadKeepsPNGAndPDFPreviews -only-testing:SciPlotGodMacTests/AppModelTests/testLauncherStartsPresentedAndRoutesModuleActionsToRealSessions -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testUnifiedInspectorColumnWidthPolicyStaysStable`: passed.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
  - Gate details: `clean_repo`, `ruff`, `mypy`, `pytest` 276 tests, `smoke_check`, `macos_gui_presentation`, `xcodebuild build`, and `xcodebuild test` 191 tests all passed.
  - Known environment warning: Xcode reports CoreSimulator service/version warnings during hosted macOS tests; macOS build and tests still passed.
  - Manual smoke checklist remains pending and unenforced without `--require-manual` evidence bundle.

### 2026-04-28: Global shell baseline alignment and Plot templates-only rail

- Change:
  - Added shared native shell header metrics:
    - `WorkbenchHeaderMetrics.height = 56`
    - `WorkbenchContentShell`
    - `InspectorHeaderTabs`
  - Wrapped every workbench detail in the same center header shell, so center workspace header and right inspector header share height and divider placement.
  - Updated `InspectorChromeRoot` to use the same 56pt header and bottom divider as the center workspace.
  - Replaced the separate right-edge inspector reveal affordance and duplicate inspector-header hide button with a single standard toolbar `sidebar.right` toggle in the global action group.
  - Let `NavigationSplitView` own the native left sidebar toggle again instead of adding a second custom left-toggle toolbar item, eliminating the system `More` / `>>` overflow menu.
  - Grouped toolbar actions as global document actions (`Import`, `Export`) followed by utility controls (`Help`, `Inspector`) with a divider.
  - Removed duplicate primary Export buttons from Data Studio, Composer, and Code Console inspectors; those inspectors now keep export follow-up actions under Advanced only.
  - Converted Plot inner rail from Source/Objects/Data/Templates to Templates-only:
    - removed Source section
    - removed sheet picker
    - removed Data Workbook row
    - removed empty source file glyph
    - kept recommended templates plus All Templates popover
  - Strengthened `scripts/check_macos_gui_presentation.py` so the aligned shell, templates-only rail, and no-chevron toolbar rules are hard gates.
  - Updated `README.md` and `AGENTS.md` to match the new Plot interaction boundary.

- User-visible impact:
  - The center workspace and inspector now use matching 56pt headers with aligned bottom dividers.
  - Plot's left inner panel no longer shows `SOURCE`, sheet controls, or a file-placeholder icon; it only presents templates.
  - Import/Export no longer visually compete with panel-specific controls in the left rail or inspector body.
  - The right inspector toggle uses a standard sidebar icon instead of a `>>`-style overflow glyph, and the top toolbar no longer exposes a `More` overflow menu in the four primary workbenches checked.

- Risks:
  - Removing Source/Sheet/Data Workbook from the Plot inner rail makes those utilities less spatially close to template selection. This is intentional for this round; future Data Workbook access should be reintroduced through a clearly scoped command/menu/utility affordance, not the template rail.
  - Moving the workbench title from navigation title semantics into the content header changes the exact native toolbar title presentation; the tradeoff is stronger cross-panel baseline alignment.
  - The toolbar action group is now a custom grouped SwiftUI toolbar item; if macOS toolbar layout changes, the group may need another small placement pass.

- Rollback points:
  - Global shell / toolbar:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/StateViews.swift`
  - Plot template rail:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
  - Presentation gate:
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`
  - Inspector export cleanup:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleContextView.swift`
  - Documentation:
    - `/Users/dongxutian/Documents/codegod/README.md`
    - `/Users/dongxutian/Documents/codegod/AGENTS.md`

- Decision Record:
  - Why:
    - The screenshot problem was a shell/grid problem more than a local inspector control problem: center content and inspector needed one shared header metric.
    - Pixelmator-style pro apps separate global document actions, canvas/workspace, and contextual inspection; DataGraph-style plotting benefits from clean template selection without duplicating source and data controls in the same rail.
  - Rejected alternatives:
    - Keep Source/Switch Sheet/Data Workbook in the Plot inner rail: rejected because it mixes data preparation with template selection and reproduces the circled screenshot clutter.
    - Keep inspector reveal on the right edge or duplicated inside the inspector header: rejected because the requested interaction puts the right-panel toggle in one top action group with a standard sidebar icon.
    - Keep a custom left sidebar toolbar item: rejected after desktop acceptance showed that it caused a system `More` overflow entry; the native `NavigationSplitView` toggle is cleaner and controls the same far-left workbench sidebar.
    - Recreate a React/Tailwind shell: rejected because this repo's supported frontend is native SwiftUI/macOS.
  - Boundaries:
    - No sidecar route changed.
    - No render payload changed.
    - No project schema changed.
    - No plot contract or `nature` metrics changed.
    - Inspector width policy remains `360 / 400 / 460`.

- Validation:
  - `git diff --check`: passed.
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py tests/test_blocking_gate.py -q`: passed, 6 tests.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test`: passed, 189 tests.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
  - Gate details: `clean_repo`, `ruff`, `mypy`, `pytest` 275 tests, `smoke_check`, `macos_gui_presentation`, `xcodebuild build`, and `xcodebuild test` 189 tests all passed.
  - Known environment warning: Xcode still reports CoreSimulator framework version mismatch; macOS build and hosted macOS tests pass.
  - Manual smoke checklist remains pending and unenforced without `--require-manual` evidence bundle.
  - Desktop GUI acceptance with Computer Use:
    - Finder baseline capture worked.
    - `open -n app/macos/.derivedData/Build/Products/Debug/SciPlot God.app`: launched without terminal error.
    - Empty Plot: center header and inspector header share the same visual baseline; Plot inner rail shows Templates only, with no `SOURCE`, sheet picker, Data Workbook row, or file placeholder.
    - Data Studio, Composer, and Code Console: shared center/inspector header structure is visible, toolbar has no `More` / `>>` overflow, and right inspector stays controlled by the single `sidebar.right` toolbar button.
    - Inspector toolbar toggle was clicked: it hid and restored the inspector; no duplicate inspector-header hide button remains.

### 2026-04-28: Plot scientific object editing closure

- Change:
  - Tightened the Plot interaction model around scientific exact editing instead of drag/nudge defaults.
  - Removed the user-facing Plot Source rail hide/show state:
    - deleted app-level `plotSourceRailPresented`
    - removed `PlotSourceRailEdgeButton`
    - kept Source visible by default
    - added automatic regular/compact density through `PlotSourceRailDensity`
  - Reduced Plot Source panel copy:
    - empty Source is now icon-only
    - central empty preview hint text is gone
    - Objects rows keep object name, icon, visibility, and delete only
  - Replaced the canvas bottom-right overlay HUD with a single selection-inspector path.
  - Upgraded the Guide tool popover from two Add buttons to an exact creation form:
    - Line / Region
    - Axis
    - Value or Start/End
    - optional label
  - Refocused the selected Guide inspector to exact controls:
    - Kind
    - Axis
    - Value or Start/End
    - Label
    - Visible
    - Delete
  - Removed old default Arrange/nudge inspector UI for reference guides and removed unused canvas movable-overlay presentation state.
  - Strengthened the macOS GUI presentation gate so the old Source hide button, bottom HUD, hero empty text, and guide nudge editor cannot return accidentally.
  - Synchronized `/Users/dongxutian/Documents/codegod/README.md` and `/Users/dongxutian/Documents/codegod/AGENTS.md` so future work follows the same Plot interaction rule: tools create/select objects, the left rail manages source/objects/templates, and the right inspector owns exact scientific parameters.

- User-visible impact:
  - The Source rail no longer exposes an awkward secondary hide icon; it stays available and becomes compact automatically in tighter layouts.
  - Empty Plot is quieter and no longer repeats low-value `No Source` / `Preview` text.
  - Adding a reference line/region now starts with numeric coordinates, which matches scientific plotting expectations.
  - The preview no longer competes with the right inspector by showing a second floating edit panel for the same selected object.
  - The right inspector is the single default place to refine selected plot objects.

- Risks:
  - Very narrow windows now show a compact icon rail instead of allowing Source to be fully hidden; if future users need a document-only presentation mode, that should be added as a deliberate View menu command rather than an edge glyph.
  - Existing backend nudge methods remain for tests and typed payload durability, but the default GUI no longer exposes them for Guide editing.
  - The Guide popover uses simple numeric text parsing; invalid numbers disable creation instead of surfacing a validation banner.
  - The toolbar still shows a system overflow affordance in the launched app window captured by Computer Use; this was not part of this specific Source/Guide/HUD closure and should be considered in the next toolbar pass if it remains visually objectionable.

- Rollback points:
  - Plot source rail:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppModel.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
  - Plot tool creation / selected object editing:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorMode.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSelectedLayerEditorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotRefineView.swift`
  - Presentation gate:
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`
  - Interaction documentation:
    - `/Users/dongxutian/Documents/codegod/README.md`
    - `/Users/dongxutian/Documents/codegod/AGENTS.md`

- Decision Record:
  - Why:
    - Pixelmator-style tools are still useful as object creation/selection entry points, but scientific plot references must be parameter-first because a line or region usually encodes a meaningful x/y coordinate.
    - A single selection inspector avoids contradictory controls between the canvas HUD and the right panel.
    - Source rail hiding was a layout workaround, not a user-level concept in this workflow.
  - Rejected alternatives:
    - Keep the bottom HUD for quick movement: rejected because it made guide editing look drag-first and duplicated the inspector.
    - Hide the Source rail manually: rejected because the chosen behavior is default visible with automatic compact density.
    - Add true PDF click-to-place: rejected for this round because it needs hit-test metadata and would cross the current presentation-only boundary.
  - Boundaries:
    - No sidecar route changed.
    - No render payload changed.
    - No project schema changed.
    - No plot contract or `nature` metrics changed.
    - Inspector width policy remains `360 / 400 / 460`.

- Validation:
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py tests/test_blocking_gate.py -q`: passed, 6 tests.
  - `git diff --check`: passed.
  - `.venv/bin/python scripts/clean_repo.py`: passed, reclaimed about `209.4 MB`.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test`: passed, 189 tests.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
  - Gate details: `clean_repo`, `ruff`, `mypy`, `pytest` 275 tests, `smoke_check`, `macos_gui_presentation`, `xcodebuild build`, and `xcodebuild test` 189 tests all passed.
  - After README/AGENTS synchronization:
    - `git diff --check`: passed.
    - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
    - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py tests/test_blocking_gate.py -q`: passed, 6 tests.
  - Final full gate after documentation sync:
    - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
    - Gate details: `clean_repo` reclaimed about `240.5 MB`; `ruff`, `mypy`, `pytest` 275 tests, `smoke_check`, `macos_gui_presentation`, `xcodebuild build`, and `xcodebuild test` 189 tests all passed.
    - Xcode still reports the known CoreSimulator out-of-date warning; macOS build/test completed successfully.
  - Manual smoke checklist remains pending and unenforced without `--require-manual` evidence bundle.
  - Desktop GUI acceptance:
    - `open -n app/macos/.derivedData/Build/Products/Debug/SciPlot God.app`: launched without terminal error.
    - `Computer Use get_app_state("com.codegod.desktop")`: succeeded for empty Plot; Source showed only the header plus icon, and the old Source hide button / `No Source` / `Preview` text were absent.
    - `open -a app/macos/.derivedData/Build/Products/Debug/SciPlot God.app examples/curve_table.csv`: opened imported Plot.
    - `Computer Use`: confirmed imported Source/Object/Templates rail remained visible, Guide popover exposed Line/Region + Axis + Value form, Add Line created a guide, selected the object, and right inspector showed exact Guide controls without bottom HUD.

### 2026-04-28: Plot left/right layout usability closure

- Change:
  - Tightened the Plot left/right layout in `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`:
    - `PlotSourceLibraryView` now lives behind an app-owned `plotSourceRailPresented` binding.
    - The Plot source rail uses a compact `224 / 250 / 286` width policy.
    - The source rail auto-collapses below the usable detail-width threshold so the canvas and `360 / 400 / 460` inspector are protected first.
    - The Plot source rail hide/show affordance sits on the source edge rather than in the global toolbar.
  - Updated `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/SciPlotGodApp.swift` so the main window has a larger professional default/minimum geometry:
    - minimum `1440 x 780`
    - default `1520 x 900`
    - `.windowResizability(.contentMinSize)`
  - Strengthened `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`:
    - `NavigationSplitView(columnVisibility:)` remains the app shell owner.
    - `WindowToolbarConfigurator` now repeatedly removes SwiftUI's duplicate split-view toolbar item during the short rebuild window after layout changes.
    - The toolbar remains global-only: `Import`, `Export`, `Quick Help`; no right-top inspector toggle and no workbench segmented picker.
  - Refined `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`:
    - empty Source state is only `No Source`
    - data preparation is a compact collapsed `Data` disclosure
    - templates show the current/recommended short list, with all templates moved into a popover
  - Replaced remaining Plot `textformat` SF Symbols in object rows and canvas HUD with `character.cursor.ibeam` to avoid localized "格式" text rendering.
  - Strengthened `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py` and `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py` so these layout and icon rules stay gated.

- User-visible impact:
  - Narrower windows should preserve the plot canvas and right inspector before the left source rail.
  - The left rail is less heavy before import and less wasteful after import.
  - Right inspector content is not internally width-capped by `InspectorChromeRoot`; the native inspector owns column width.
  - The canvas/object text tool no longer risks displaying the localized word "格式" instead of a tool icon.
  - Global toolbar actions remain clean and unambiguous.

- Risks:
  - The duplicate-toolbar cleanup is a tiny AppKit bridge over SwiftUI toolbar behavior. It is intentionally narrow, but it relies on SwiftUI's current `navigationSplitView.toggleSidebar` toolbar identifier shape.
  - The Plot source rail collapse threshold is presentation-only and based on available detail width; if the product later adds another persistent side surface, the threshold may need retuning.
  - Hosted macOS XCTest still logs an AppKit split-view safe-area constraint recovery warning. Tests pass and the app-level minimum/default window geometry was increased, but this remains worth watching in future native layout work.
  - Desktop GUI acceptance was blocked this run: `Computer Use get_app_state("com.codegod.desktop")` returned `Apple event error -10005: cgWindowNotFound`, Finder capture timed out, and a system screenshot showed the Mac lock screen. No manual smoke pass was claimed.

- Rollback points:
  - App shell/window geometry:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppModel.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/SciPlotGodApp.swift`
  - Plot left/source rail:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
  - Plot tool/icon surfaces:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorMode.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotRefineView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorLayerListView.swift`
  - Shared inspector chrome:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/StateViews.swift`
  - Regression gate:
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`

- Decision Record:
  - Why:
    - The user's screenshot showed the left/source side and right inspector fighting the canvas. The first-principles fix is layout priority, not another inspector style pass.
    - Pixelmator-style pro tools protect the editing canvas and contextual inspector; source/library panels are useful but should be easy to collapse and should not consume the window when space is tight.
  - Rejected alternatives:
    - Put source-rail visibility into the global toolbar: rejected because panel visibility belongs at the corresponding edge and would recreate the ambiguous right-top toolbar cluster.
    - Keep source rail state as local view storage: rejected because toolbar/layout rebuilds could reintroduce stale split-view toolbar state after source collapse.
    - Remove the source rail entirely: rejected because Source, Objects, Data, and Templates are the right pre-plot/object context layer; the problem was priority and density.
  - Boundaries:
    - No sidecar route changed.
    - No render payload changed.
    - No project schema changed.
    - No plot contract or `nature` metrics changed.
    - Inspector width policy remains `360 / 400 / 460`.

- Validation (executed):
  - `git diff --check`: passed.
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py tests/test_blocking_gate.py`: passed (`6 passed`).
  - `.venv/bin/python scripts/clean_repo.py`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test`: passed (`189 tests`).
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix:
    - `clean_repo`
    - `ruff`
    - `mypy`
    - `pytest` (`275 passed`, 5 warnings)
    - `smoke_check`
    - `macos_gui_presentation`
    - `xcodebuild build`
    - `xcodebuild test` (`189 tests`)
  - Manual smoke checklist remains pending and unenforced without `--require-manual` evidence.
  - Xcode still reports the existing CoreSimulator out-of-date warning; macOS build/test completed successfully.

### 2026-04-28: Plot native toolbar, inspector, and canvas tool closure

- Change:
  - Reworked `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift` so `NavigationSplitView` owns column visibility and the right inspector is wrapped by `InspectorChromeRoot`.
  - Removed the global toolbar inspector toggle; inspector hide now lives in the inspector header, and restore uses a right-edge reveal button.
  - Kept global toolbar actions to `Import`, `Export`, and `Quick Help`; the left sidebar toggle is a left navigation item only.
  - Added a narrow AppKit toolbar configurator to disable toolbar customization/autosave and remove SwiftUI's duplicate hidden split-view toggle from the overflow menu.
  - Replaced the Plot preview's capsule tool strip plus persistent options bar with `PlotFloatingToolPalette` and per-tool popovers for `Guide`, `Text`, `Shape`, and `Function`.
  - Updated `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py` and `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py` to guard the new toolbar/inspector/tool-palette structure.

- User-visible impact:
  - The ambiguous right-top inspector/overflow cluster is gone in the tested window state.
  - Left sidebar visibility is controlled from the left side; right inspector visibility is controlled from the inspector itself or the right edge.
  - The inspector opens at the stable `360 / 400 / 460` width policy and starts with a `Figure` header instead of another form-like title.
  - Canvas tools now feel like one native floating palette; add actions live in local popovers instead of a second long pill.

- Risks:
  - The AppKit cleanup targets SwiftUI's current raw toolbar identifier `com.apple.SwiftUI.navigationSplitView.toggleSidebar`; if Apple changes that identifier, the duplicate overflow item may need another tiny bridge update.
  - True canvas hit-testing is still out of scope; popovers add typed overlays and immediately select them, while exact placement remains controlled by existing typed overlay editors/nudging.
  - Toolbar customization is intentionally disabled for this window to prevent hidden stale items from reappearing.

- Rollback points:
  - App shell and toolbar:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppModel.swift`
  - Shared inspector chrome:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/StateViews.swift`
  - Plot canvas tools:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorMode.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotRefineView.swift`
  - Regression gate:
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`

- Decision Record:
  - Why:
    - The previous toolbar mixed global actions, sidebar state, inspector state, and system overflow into one right-side cluster; that contradicted the Pixelmator/Apple model where side panels are controlled at their own edges.
    - The canvas tool strip should be an object-operation palette, not another form surface.
  - Rejected alternatives:
    - Keep SwiftUI's automatic sidebar toggle: rejected because Computer Use showed it was placed in the right overflow menu in this window.
    - Put inspector toggle back in the toolbar: rejected because it recreated the exact ambiguous cluster called out by the user.
    - Keep the persistent tool options bar: rejected because it duplicated the inspector and created mismatched rounded geometry.
  - Boundaries:
    - No sidecar route changed.
    - No render payload changed.
    - No project schema changed.
    - No plot contract or `nature` metrics changed.
    - Inspector width policy remains `360 / 400 / 460`.

- Validation (executed):
  - `git diff --check`: passed.
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py tests/test_blocking_gate.py`: passed (`6 passed`).
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test`: passed (`189 tests`).
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
  - Computer Use desktop acceptance:
    - `get_app_state("com.codegod.desktop")`: succeeded.
    - Confirmed toolbar has left sidebar button plus `Import / Export / Help`; no right-side `more toolbar items` overflow after removing the duplicate SwiftUI split-view toggle.
    - Confirmed inspector header hide button collapses the inspector.
    - Confirmed right-edge reveal button restores the inspector.
  - Xcode still reports the existing CoreSimulator out-of-date warning; macOS build/test completed successfully.

### 2026-04-27: Plot chrome de-duplication follow-up

- Change:
  - Removed the top toolbar workbench segmented picker from `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`; workbench switching remains in the native left sidebar.
  - Simplified the Plot empty Source section in `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift` so it shows only one `Import Data` button instead of both explanatory import text and an import button.
  - Updated `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py` and `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py` to prevent reintroducing the duplicated top workbench picker or the duplicated left import empty state.

- User-visible impact:
  - The titlebar is cleaner and no longer duplicates the sidebar navigation.
  - The Plot left rail Source area is less noisy before import.
  - No sidecar, render payload, project schema, or workflow contract changes.

- Risks:
  - Users now switch workbenches only from the sidebar/menu, which matches the user's requested cleanup but removes one redundant toolbar shortcut.

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
  - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`

- Validation (executed):
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `git diff --check`: passed.
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py tests/test_blocking_gate.py`: passed (`6 passed`).
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed.
  - Computer Use GUI acceptance: passed; top toolbar workbench picker is gone and Source shows only `Import Data`.

### 2026-04-27: Plot macOS Pro information architecture reset

- Change:
  - Reworked Plot around a clearer professional macOS tool-window hierarchy:
    - global actions stay in the system toolbar (`Import`, `Export`, `Quick Help`, `Inspector`)
    - data preparation moved into the Plot left rail
    - the right inspector is contextual editing only
  - Added `PlotSourceLibraryView` in `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift` with three explicit left-rail regions:
    - `Source`: current file, sheet, and `Data Workbook`
    - `Data Preparation`: `Source Data`, `Transformed`, `Variables`, `Fit`
    - `Templates`: compact template library rows
  - Removed Plot sheet picker / Data Workbook controls from the app toolbar by deleting the per-workbench toolbar content path in `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`.
  - Removed Plot export actions from `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`; export remains available through toolbar/menu.
  - Lightened Plot empty/preview stage copy so the central canvas no longer repeats the left Source import instruction.
  - Added source-level GUI presentation checks to prevent regressing `Sheet` / `Data Workbook` into the global toolbar or `Export` into Plot inspector.

- User-visible impact:
  - Plot now separates `Import/Export` from `Sheet/Data Workbook` and from contextual figure editing.
  - The left rail is no longer a mostly empty template-only area; it owns source selection, data workbook access, preparation tabs, and templates.
  - Imported Plot state shows the figure preview as the main object while the inspector edits `Figure / Data / Layers / Arrange` context.
  - No sidecar contract, render payload, project schema, or inspector width policy changes.

- Risks:
  - Data Studio analysis and Code Console sheet shortcuts were removed from the global toolbar along with the previous per-workbench toolbar path; if future UX wants them, they should be placed in their own workbench surfaces rather than the app-global action cluster.
  - Plot preview still uses the existing PDFKit preview component; this round removed the extra SwiftUI outer preview shell but did not redesign PDFKit scaling behavior.

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotRefineView.swift`
  - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`

- Decision Record:
  - Why:
    - first-principles 动机是把 Plot 的三种层级拆清楚：toolbar 是全局流程端点，left rail 是导入后的数据准备与模板选择，inspector 是当前对象属性编辑。
    - Pixelmator Pro / Final Cut Pro 式复杂工具不是把功能全堆进 inspector，而是用 source/library/layer/context 分区控制复杂度。
  - Rejected alternatives:
    - 继续微调右侧 inspector 字体：拒绝，因为用户指出的问题是交互层级错位，不是字重或 spacing 的单点问题。
    - 把 Sheet / Data Workbook 留在 toolbar：拒绝，因为它们属于画图前的数据准备层，不是全局 import/export 端点。
    - 在 Plot inspector 保留 Export：拒绝，因为这会让 contextual inspector 继续承担全局结束动作。
  - Boundaries:
    - 只改 macOS presentation architecture and view composition.
    - 不改 sidecar routes、render payload、project schema、plot contract、Python data/fit semantics。
    - 右侧 inspector 宽度继续使用 `360 / 400 / 460`。

- Validation (executed):
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `git diff --check`: passed.
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py tests/test_blocking_gate.py`: passed (`6 passed`).
  - `.venv/bin/python scripts/clean_repo.py`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test`: passed (`188 tests, 0 failures`).
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix; manual smoke remained pending by design.
  - Computer Use GUI acceptance:
    - empty Plot state: passed; toolbar only shows global actions, left rail shows `Source / Data Preparation / Templates`, central stage only shows a small `Preview` hint, inspector has no Export section.
    - imported Plot state with `/Users/dongxutian/Documents/codegod/examples/curve_table.csv`: passed; left rail shows source/sheet/data workbook/prep/templates, central preview renders, toolbar export is enabled, inspector remains contextual.

### 2026-04-26: Merged `codex/plot-data-boundary-hardening` into `main`

- Change:
  - Realigned local `main` to `origin/main` and merged `codex/plot-data-boundary-hardening` with a non-squash merge so the boundary-hardening history stays intact.
  - Resolved merge overlap by keeping the newer transform-aware inspect/recommendation path, Plot Data Workbook extraction, strict inner-beta gate tooling, and the existing `custom_function` fit/bounds payload support together on the merged `main`.
  - Carried forward the branch-side updates to:
    - Plot transform-aware inspect/source-preview/fit consistency
    - Plot Data Workbook / data-pipeline presentation split
    - inner-beta gate tooling and heterogeneous Data Studio regression coverage
    - README / AGENTS / product architecture documentation

- User-visible impact:
  - No new GUI redesign in this round.
  - `main` now contains the full boundary-hardening package that was previously only on `codex/plot-data-boundary-hardening`.

- Risks:
  - This round is an integration merge; the main risk was semantic drift between `origin/main` custom-fit work and branch-side transform/data-workbook/gate work.
  - Future merge work touching `fit_analysis`, Plot session restore payloads, or gate scripts should continue to preserve both the typed transform path and the bounded `custom_function` path together.

- Rollback points:
  - Merge commit created from this round on `main`
  - Prior branch tip: `codex/plot-data-boundary-hardening` at `6ea3406`
  - Remote baseline used for `main`: `origin/main` at `39241bf` before merge

- Decision Record:
  - Why:
    - first-principles 动机是先把底层边界收敛到单一 `main` 线，再继续后续 GUI 重构，避免在 GUI 轮次里同时背负一条未合并的底层实现分叉。
    - 保留普通 merge commit 而不是 squash，是为了留下这组边界加固工作的集成节点和回滚锚点。
  - Rejected alternatives:
    - 直接在未合并的功能分支上继续 GUI：拒绝，因为会把 GUI 重构和底层边界加固继续缠在一起。
    - 保留本地旧 `main` 提交 `eff92c6` 作为基线：拒绝，因为本轮目标明确要求先对齐 `origin/main`。
  - Boundaries:
    - 本轮只做分支收敛与冲突整合，不新增 GUI 行为、不改 public contract surface、不改单独的 inner-beta evidence 语义。

- Validation (executed):
  - `git diff --check`: passed
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python scripts/blocking_gate.py`: passed
    - `ruff`: passed
    - `mypy`: passed
    - `pytest tests`: passed (`272 passed, 5 warnings`)
    - `scripts/smoke_check.py`: passed
    - `xcodebuild ... build`: passed
    - `xcodebuild ... test`: passed (`190 tests, 0 failures`)
  - Manual checks remained informational because strict manual enforcement was not requested during this merge round.

### 2026-04-26: Inner-beta manual smoke completed + project payload decode hardening

- Change:
  - Ran the three required interactive manual smoke flows and recorded an auditable evidence bundle at `/tmp/sciplot_inner_beta_manual/evidence.json` with attached screenshots/files.
  - During `overlay_drag_save_reopen`, uncovered a real macOS decode bug after `Save Project`: the sidecar wrote the project successfully, but Swift failed to decode acronym/ID-heavy fields from the `/save-project` and `/open-project` JSON payload.
  - Added real snake_case decoding regression coverage in `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift` for:
    - `testDecodeSaveProjectResponsePreservesPlotSourceSHA256`
    - `testDecodeOpenProjectResponsePreservesEmbeddedWorkbookSHA256`
  - Fixed `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift` by giving explicit `CodingKeys` raw values to acronym/ID fields that do not round-trip cleanly under `.convertFromSnakeCase`:
    - `sourceSHA256 -> sourceSha256`
    - `selectedTemplateID -> selectedTemplateId`
    - `workbookSHA256 -> workbookSha256`
    - `comparisonRecipeIDs -> comparisonRecipeIds`

- User-visible impact:
  - Real manual smoke evidence now exists for:
    - `plot_import_preview_export`
    - `data_studio_import_open_plot`
    - `overlay_drag_save_reopen`
  - Plot `Save Project` / `Open Project` no longer surfaces the false decode error caused by acronym-key mismatch when the sidecar returns a valid saved project payload.
  - No public contract, sidecar schema, `.sciplotgod` bundle structure, template surface, or `nature` metric changes.

- Risks:
  - The regression fix is intentionally scoped to Swift decoding of saved/opened project payloads; if future payload structs add new acronym-style fields, they need the same explicit-key review.
  - The overlay manual evidence bundle proves the tested path works in this environment, but it should still be refreshed for future release-signoff rounds rather than treated as permanent proof.

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
  - `/Users/dongxutian/Documents/codegod/docs/engineering-handoff.md`

- Decision Record:
  - Why:
    - first-principles 动机是让 inner beta 的“Save Project -> Reopen”证据反映真实产品行为，而不是被客户端 JSON 解码细节误报为失败。
    - mock 直接构造 Swift model 的测试没有覆盖真实 snake_case payload，因此必须补一条实际 decode 路径的回归测试。
  - Rejected alternatives:
    - 只记录 manual smoke blocked 然后跳过：拒绝，因为 evidence 已经表明 sidecar 真正写出了 `.sciplotgod` 文件，阻断点在 macOS decode 层，应该当场修掉。
    - 依赖 `.convertFromSnakeCase` 的隐式推导继续赌 acronym 字段：拒绝，因为 `SHA256` / `ID` 这类字段已经证明会在保存/打开项目链路上产生假失败。
  - Boundaries:
    - 只修 Swift payload decode，不改 Python 保存逻辑、不改 `.sciplotgod` 结构、不改 sidecar public schema。
    - manual smoke evidence 继续按真实结果记录；若未来 Computer Use/native panel 再阻塞，仍应标记 `blocked` 或 `failed`，不能假装通过。

- Validation (executed):
  - RED:
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/SchemaDecodingTests/testDecodeSaveProjectResponsePreservesPlotSourceSHA256 -only-testing:SciPlotGodMacTests/SchemaDecodingTests/testDecodeOpenProjectResponsePreservesEmbeddedWorkbookSHA256`: failed before the fix with missing `sourceSHA256` / `comparisonRecipeIDs`.
  - GREEN:
    - same targeted `xcodebuild ... test -only-testing:...SchemaDecodingTests/...`: passed after the fix.
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed.
  - Manual evidence:
    - `.venv/bin/python scripts/manual_smoke_evidence.py validate --input /tmp/sciplot_inner_beta_manual/evidence.json --require-all`: passed.
    - `.venv/bin/python scripts/blocking_gate.py --require-manual --manual-evidence /tmp/sciplot_inner_beta_manual/evidence.json`: passed.
  - Evidence bundle:
    - `/tmp/sciplot_inner_beta_manual/evidence.json`
    - `/tmp/sciplot_inner_beta_manual/plot_preview.png`
    - `/tmp/sciplot_inner_beta_manual/data_studio_open_in_plot.png`
    - `/tmp/sciplot_inner_beta_manual/overlay_reopened_project.png`
    - `/tmp/sciplot_inner_beta_manual/overlay_saved_no_error.png`

### 2026-04-26: Inner-beta manual smoke evidence gate

- Change:
  - Added `/Users/dongxutian/Documents/codegod/scripts/manual_smoke_evidence.py` with:
    - `init --output PATH` to create an empty evidence bundle
    - `record --input PATH --check ... --status ... --note ... --evidence-file ...` to append structured smoke evidence
    - `validate --input PATH --require-all` to enforce that all three required checks are `passed` and every evidence file exists
  - Extended `/Users/dongxutian/Documents/codegod/scripts/blocking_gate.py` with `--manual-evidence PATH`, so strict manual gating can consume a structured evidence bundle instead of relying only on assertion flags.
  - Updated `README.md` and `AGENTS.md` so inner-beta sign-off now points to the evidence path first, while keeping `--manual-check` as the explicit human-assertion fallback.

- User-visible impact:
  - No Plot/Data Studio/Composer/Code Console GUI changes.
  - No public contract, sidecar schema, `.sciplotgod` bundle, template surface, or `nature` metric changes.
  - Inner-beta manual readiness can now be audited from a JSON bundle plus attached files instead of a bare command-line flag.

- Risks:
  - This gate proves that evidence artifacts exist and were recorded consistently; it does not replace real human judgment about whether the desktop flow was acceptable.
  - Computer Use or native save/open panels may still leave a check in `blocked`; that is expected and should be recorded honestly rather than overridden to `passed`.

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/scripts/manual_smoke_evidence.py`
  - `/Users/dongxutian/Documents/codegod/scripts/blocking_gate.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_manual_smoke_evidence.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_blocking_gate.py`
  - `/Users/dongxutian/Documents/codegod/README.md`
  - `/Users/dongxutian/Documents/codegod/AGENTS.md`

- Decision Record:
  - Why:
    - first-principles 动机是把 inner beta manual gate 从“口头确认”升级成“带结构化证据的准入凭证”，避免只靠 `--manual-check` 就宣称真实桌面流已通过。
    - 三条关键流是产品级稳定性证据，不应该只存在于聊天记录、临时备注或一次性终端输出里。
  - Rejected alternatives:
    - 继续只靠 `--manual-check`：拒绝，因为它只能表达人工声称，不能留存可审计 artifact。
    - 把 Computer Use 截图成功与否当成唯一通过条件：拒绝，因为原生 panel 和 ScreenCaptureKit 阻塞是环境问题，不应直接等同于产品失败。
  - Boundaries:
    - evidence gate 只加在流程工具层，不改产品 GUI、public contract、public schema、`.sciplotgod` 结构或 `nature` 指标。
    - `--manual-check` 仍保留兼容，但 inner beta 推荐走 evidence bundle。

- Validation (executed):
  - `.venv/bin/python -m pytest tests/test_manual_smoke_evidence.py tests/test_blocking_gate.py -q`: passed (`6 passed`).
  - `tmp evidence bundle` strict path:
    - `.venv/bin/python scripts/manual_smoke_evidence.py init --output /tmp/sciplot_inner_beta_evidence.json`
    - `.venv/bin/python scripts/manual_smoke_evidence.py record --input /tmp/sciplot_inner_beta_evidence.json --check plot_import_preview_export --status passed --note "test artifact" --evidence-file /tmp/sciplot_inner_beta_plot.txt`
    - `.venv/bin/python scripts/manual_smoke_evidence.py record --input /tmp/sciplot_inner_beta_evidence.json --check data_studio_import_open_plot --status passed --note "test artifact" --evidence-file /tmp/sciplot_inner_beta_data_studio.txt`
    - `.venv/bin/python scripts/manual_smoke_evidence.py record --input /tmp/sciplot_inner_beta_evidence.json --check overlay_drag_save_reopen --status passed --note "test artifact" --evidence-file /tmp/sciplot_inner_beta_overlay.txt`
    - `.venv/bin/python scripts/manual_smoke_evidence.py validate --input /tmp/sciplot_inner_beta_evidence.json --require-all`: passed.
    - `.venv/bin/python scripts/blocking_gate.py --require-manual --manual-evidence /tmp/sciplot_inner_beta_evidence.json`: passed.
  - `git diff --check`: passed.

### 2026-04-26: Inner Beta Readiness Gate Attempt

- Change:
  - Closed the previous backend stability hardening package as commit `59d8dff` (`chore: harden inner beta backend gates`) on `codex/plot-data-boundary-hardening`, providing a clean rollback point before readiness evidence collection.
  - Documented the manual-smoke rule in `README.md` and `AGENTS.md`: `--manual-check` may only be used after the corresponding real desktop flow is actually completed.

- Readiness evidence:
  - Automated gate before commit: `.venv/bin/python scripts/blocking_gate.py` passed (`pytest` `263 passed, 5 warnings`; `smoke_check` passed; `xcodebuild build` passed; `xcodebuild test` `181 tests, 0 failures`; manual checks pending).
  - Interactive Plot smoke partial: launched `app/macos/.derivedData/Build/Products/Debug/SciPlot God.app`, imported `/tmp/sciplot_inner_beta_smoke/curve.csv`, observed Plot recommendation/preview render, and reached the native export-format dialog.
  - Interactive export was not confirmed: Computer Use hit `SCStreamErrorDomain Code=-3811` and then timed out while the native save panel was open. No exported PDF was created in `/tmp/sciplot_inner_beta_smoke`, so `plot_import_preview_export` remains incomplete.
  - Artifact fallback attempted: `xcodebuild ... test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testGuiSmokeRendersKeyWorkbenchViews` passed and produced xcresult attachments at `app/macos/.derivedData/Logs/Test/Test-SciPlotGodMac-2026.04.26_00-35-24-+0800.xcresult`, but this is snapshot evidence only, not a replacement for interactive manual smoke.
  - Strict manual gate: `.venv/bin/python scripts/blocking_gate.py --require-manual` passed the automated matrix again (`pytest` `263 passed, 5 warnings`; `xcodebuild test` `181 tests, 0 failures`) and then correctly failed with exit code `2` because no manual checks were honestly marked complete.

- Current beta status:
  - Backend/rendering/macOS automated readiness is green.
  - Inner-beta interactive readiness is not fully signed off yet because all three required real desktop flows are still pending or blocked.
  - GUI redesign remains out of scope for this readiness gate.

- Risks:
  - Native macOS save/open panels can outlive or destabilize Computer Use capture in this environment; do not interpret that as a product export failure unless the same failure reproduces with direct human interaction.
  - Passing GUI snapshot tests proves canonical views render, but does not prove file-picker, export destination, or save/reopen interactions.

- Rollback points:
  - Readiness documentation only: `/Users/dongxutian/Documents/codegod/docs/engineering-handoff.md`, `/Users/dongxutian/Documents/codegod/README.md`, `/Users/dongxutian/Documents/codegod/AGENTS.md`.
  - Backend stability package rollback point: commit `59d8dff`.

- Next action:
  - Run the three manual smoke flows with a human at the Mac or a stable desktop automation session.
  - Only after each flow is actually completed, rerun:
    - `.venv/bin/python scripts/blocking_gate.py --require-manual --manual-check plot_import_preview_export --manual-check data_studio_import_open_plot --manual-check overlay_drag_save_reopen`

### 2026-04-25: Inner-beta backend stability gate hardening

- Change:
  - Hardened `scripts/smoke_check.py` so any error-level validation report with `passed=false` fails the smoke command instead of only appearing in `figures/debug_outputs/smoke_report.json`.
  - Cleaned advanced overlay smoke semantics: PDF raster sanity remains `non_blank_pdf`; axis break / split / shape / annotation checks now use direct smoke assertions with explicit failure messages.
  - Made Data Studio template recommendations refuse templates with no `match_conditions`, preventing unknown files from being auto-matched to manual-only user templates.
  - Reused transform-aware inspect presentation for export artifacts, so `/inspect-file` and `/export-render` produce the same transformed recommendation summary when `data_variables/data_transforms` are active.
  - Added backend regression coverage for Excel selected-sheet import, no-default template recommendation, curve+metric mixed workbook output, failed-smoke gating, and transform-aware render-route consistency.

- User-visible impact:
  - No public contract, template, `.sciplotgod`, or `nature` metric changes.
  - Release/smoke automation is stricter: failed error-level validations now stop the run.
  - Unknown Data Studio files stay unselected unless a template actually matches, preserving explicit manual resolution.

- Risks:
  - Smoke failures from advanced overlay checks now fail immediately with assertions instead of appearing as report rows; this is intentional but changes where the failure is surfaced.
  - Templates intentionally meant for manual-only use need explicit selection in the UI; they will not appear as weak recommendations without match conditions.

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/scripts/smoke_check.py`
  - `/Users/dongxutian/Documents/codegod/src/data_studio/ingest.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_smoke_check.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_data_studio_import_templates_v2.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_sidecar_render.py`

- Decision Record:
  - Why:
    - first-principles 动机是让内测前底层门禁表达真实失败，而不是把 error-level validation 写进报告后仍然返回成功。
    - Data Studio 推荐器应只表达有证据的匹配；无条件模板是可手动选择的模板，不是自动推荐。
    - Plot transform-aware routes must share one transformed-table semantic path across inspect, preview, fit, preflight, render, export artifacts, and later project restore.
  - Rejected alternatives:
    - 继续把 overlay 检查塞进 `non_blank_pdf`：拒绝，因为 PDF 非空和 overlay 语义是两类检查，会掩盖真实失败。
    - 保留 no-condition template 的 0.1 弱匹配：拒绝，因为这等价于 unknown source fallback，和 v2 resolver “无推荐则显式选择”原则冲突。
    - 只修 `/inspect-file` 不修 export artifact：拒绝，因为导出包会重新落回 raw inspection，形成同一图件不同元数据语义。
  - Boundaries:
    - 不改 `src/plot_contract.json`、sidecar public schema、public templates、`.sciplotgod` bundle 结构或 `nature` 冻结指标。
    - 不引入 Swift/前端表达式执行器；transform 语义仍由后端 typed data engine 执行。

- Validation (executed):
  - `.venv/bin/python -m pytest tests/test_smoke_check.py::test_error_validation_fails_smoke_report_gate -q`: failed before implementation, then passed.
  - `.venv/bin/python -m pytest tests/test_sidecar_render.py::test_transform_options_stay_consistent_across_render_routes -q`: failed before implementation, then passed.
  - `.venv/bin/python -m pytest tests/test_data_studio_import_templates_v2.py::test_excel_multi_sheet_template_preview_builds_selected_sheet tests/test_data_studio_import_templates_v2.py::test_unknown_source_does_not_default_to_unmatched_user_template -q`: failed before implementation, then passed.
  - `.venv/bin/python -m pytest tests/test_smoke_check.py tests/test_sidecar_render.py tests/test_data_studio_import_templates_v2.py -q`: passed (`23 passed`).
  - `.venv/bin/python scripts/smoke_check.py`: passed (`24` PDFs, `7` validations, `0` failed error-level validations).
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix (`clean_repo` reclaimed approx `237.2 MB`; `ruff` passed; `mypy` passed; `pytest` `263 passed, 5 warnings`; `smoke_check` passed; `xcodebuild build` passed; `xcodebuild test` `181 tests, 0 failures`). Manual smoke checklist remained pending because `--require-manual` was not used.
  - `git diff --check`: passed.
  - Manual GUI smoke: pending by plan; `--require-manual` not run in this round.

### 2026-04-25: Plot DataGraph-style data inspector split and pipeline summary seam

- Change:
  - Split `PlotDataTransformInspectorView` out of `PlotFunctionLayerInspectorView.swift` into its own Plot feature file and added it to the macOS Xcode target.
  - Added `PlotDataPipelineSummary` as a small presentation seam on `PlotSession` so the DataGraph-style variables/transforms pipeline can be summarized from one place instead of each UI surface recounting it.
  - Added a compact Pipeline/Status row to the Plot inspector Data disclosure so the existing typed variables/transforms editor has a clearer state surface without changing the backend contract or `nature` metrics.
  - Added macOS regression coverage for empty, active, and disabled data-pipeline summary states.
- User-visible impact:
  - Plot's Advanced Plot -> Data section now shows whether source data is used directly or how many variables/transforms are active.
  - No route, contract, renderer, default-style, or project-file schema changes.
- Decision Record:
  - First-principles motivation: the DataGraph-style data engine should become a productized workflow through typed presentation seams, not more controls piled into a mixed function/data inspector file.
  - Alternatives rejected: leaving the Data inspector embedded in the function-layer file, or adding UI-local recounting in each future Data Workbook pane. Both would keep structure debt in the path of the next Data Workbook v2 work.
  - Current boundary: this is a macOS structure/presentation cleanup only. Variables and transforms remain backend-owned typed payloads, and Swift still does not evaluate expressions.
  - Failure conditions: future Data Workbook or inspector panes can drift again if they compute their own variable/transform counts rather than using `dataPipelineSummary`.
- Risk / rollback:
  - Roll back `PlotDataTransformInspectorView.swift` and the Xcode project membership if target membership or SwiftUI compile behavior regresses.
  - Roll back `PlotDataPipelineSummary` and the inspector summary rows independently if the state copy proves too noisy.
- Actual regression results:
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests/testDataPipelineSummaryCountsVariablesAndActiveTransforms`: failed before implementation because `PlotSession` had no `dataPipelineSummary`, then passed.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix (`clean_repo` reclaimed approx `236.6 MB`; `ruff` passed; `mypy` passed; `pytest` `258 passed, 5 warnings`; `smoke_check` passed; `xcodebuild build` passed; `xcodebuild test` `180 tests, 0 failures`). Manual smoke checklist remained pending because `--require-manual` was not used.
  - Known environment noise: Xcode still reports the existing CoreSimulator out-of-date warning; macOS platform build/test passed.

### 2026-04-25: Plot/Data Studio boundary and transform-aware inspection hardening

- Change:
  - Fixed transform-aware Plot inspection so `/inspect-file` can build recommendations from the transformed table without first requiring the original raw source to match a supported shape.
  - Added a shared sidecar `data_engine_options_from_payload` helper so `/inspect-file`, `/source-table-preview`, and `/fit-analysis` consume `render_options.data_variables / data_transforms` through one payload conversion path.
  - Fixed curve and mean-band render model detection so `src/rendering/render_curve.py` passes current render options into `build_normalized_dataset`, preventing transform-enabled renders from falling back to raw-source model detection.
  - Updated `docs/product-architecture.md` to remove stale `/data-studio/source-preview` wording and add a Plot/Data Studio boundary note: Plot owns single-figure recommendation/refinement/render/export; Data Studio owns intake/workbook/comparison; `Open in Plot` is the explicit handoff.
  - Updated `README.md` and `AGENTS.md` to document that transform-aware inspect/recommendation is based on the transformed table while no-options import remains the fast raw-source path.
- User-visible impact:
  - Data transformed into a compact aggregate table can now enter normal recommendation and surface `table_figure` even if the original long raw table is not directly recognized.
  - Transform-enabled curve and mean-band rendering now use the same model-detection view as preview/fit/source-table paths.
  - No GUI workflow change; existing Data Studio `Open in Plot` affordances and tests already cover render/fit handoff payloads.
- Decision Record:
  - First-principles motivation: DataGraph-style data preparation only works as a durable engine if inspect/recommend, render, fit, and source preview all observe the same transformed table. Raw-first inspection created a hidden precondition that contradicted the typed data-engine contract.
  - Alternatives rejected: adding a new transform-inspect endpoint, letting macOS infer transformed shapes locally, or keeping renderer-specific fallbacks. Each would create a second recommendation/data semantic source.
  - Current boundary: transforms are still opt-in. Without options, `/inspect-file` continues to use the raw-source fast path. Data Studio remains the workbook/comparison owner and only crosses into Plot via `Open in Plot`.
  - Failure conditions: future renderers that call raw cached loaders for transform-enabled options can still diverge; add a regression near that renderer before extending it.
- Risk / rollback:
  - Roll back `app/sidecar/render_support.py` helper extraction and `app/sidecar/routes_render.py` inspect branching if transform-aware inspect errors regress ordinary imports.
  - Roll back the two `src/rendering/render_curve.py` option-passing changes if rheology bundle routing regresses, then replace with a narrower transform-only condition.
  - Documentation changes are safe to revert independently if product wording changes again.
- Actual regression results:
  - `.venv/bin/python -m pytest tests/test_rendering_services.py::test_curve_render_model_detection_uses_transform_options tests/test_rendering_services.py::test_mean_band_render_model_detection_uses_transform_options tests/test_sidecar_render.py::test_inspect_file_recommends_table_figure_after_aggregate_transform -q`: failed before implementation, then passed (`3 passed`, existing SWIG deprecation warnings only).
  - `.venv/bin/python -m pytest tests/test_sidecar_render.py tests/test_rendering_services.py::test_contour_field_preflight_and_render_with_pivot_transform tests/test_rendering_services.py::test_new_datagraph_templates_preflight_and_render tests/test_rendering_services.py::test_curve_render_model_detection_uses_transform_options tests/test_rendering_services.py::test_mean_band_render_model_detection_uses_transform_options tests/test_sidecar_active_routes.py -q`: passed (`15 passed`, existing warnings only).
  - `.venv/bin/python -m ruff check app/sidecar/routes_render.py app/sidecar/render_support.py app/sidecar/server_utils.py src/rendering/render_curve.py tests/test_rendering_services.py tests/test_sidecar_render.py`: passed.
  - `.venv/bin/python -m mypy src/rendering/render_curve.py app/sidecar/routes_render.py app/sidecar/render_support.py app/sidecar/server_utils.py`: passed.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix (`pytest` `258 passed, 5 warnings`; `smoke_check` passed; `xcodebuild build` passed; `xcodebuild test` `179 tests, 0 failures`; manual smoke checklist listed as pending but not enforced).
  - `.venv/bin/python scripts/smoke_check.py`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed (CoreSimulator out-of-date warning only).
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`179 tests, 0 failures`; CoreSimulator out-of-date warning only).

### 2026-04-25: DataGraph-style typed data engine expansion

- Change:
  - Added shared backend expression kernel in `src/rendering/expression_engine.py` for function layers, typed data transforms, variables, and custom fit expressions.
  - Expanded `render_options.data_variables` and `render_options.data_transforms` as the durable DataGraph-style data engine surface. Variables support enabled scalar and expression values; transforms now cover `derived_column`, `row_filter`, `mask_filter`, `sort_rows`, `select_columns`, `type_cast`, `bin_column`, `aggregate_summary`, `rolling_window`, and `pivot_matrix` with `xyz_long` or matrix output.
  - Wired transform-aware data preparation through inspect/recommendation, source-table preview, render/preflight/export loaders, fit analysis, Data Workbook `Transformed`/`Variables`, and `.sciplotgod` project save/open normalization.
  - Extended shared fit analysis to `exponential`, `logarithmic`, `power_law`, `gaussian`, `logistic`, and backend-only `custom_function` in addition to the existing linear/polynomial models.
  - Added macOS Codable/schema coverage and basic Plot inspector controls for variables, masks, binning, aggregate, and smoothing without adding Swift math execution or a DataGraph command-stack UI.
- User-visible impact:
  - Plot can now keep reusable variables and richer table transforms with the figure state; transformed data can drive recommendations, preview/export, fitting, and project restore.
  - Users can access more fit models from the same fit surface; custom functions remain backend-owned and typed.
  - Data Workbook can inspect source, transformed data, variables, and fit output as separate read-only views.
- Decision Record:
  - First-principles motivation: DataGraph's transferable value is a durable data/variable layer underneath graph commands. This round makes that layer typed and replayable while preserving SciPlot God's recommendation-first Plot flow.
  - Alternatives rejected: a free-form command interpreter, arbitrary Python, Swift-side expression evaluation, or renderer-local temporary table mutation. Each would create a second semantic source and make project replay less trustworthy.
  - Current boundary: variables are scalar-only, custom fit is bounded by explicit expression and parameter payloads, transforms are single-table operations, and the GUI remains a basic typed-payload editor. Joins, full spreadsheet editing, animation, and a final DataGraph-style command UI remain out of scope.
  - Failure conditions: if future renderers bypass the transform-aware preparation path, Data Workbook, fit, preview/export, and inspect recommendations can diverge. If future GUI code starts evaluating expressions locally, backend error semantics and saved project replay will drift.
- Risk / rollback:
  - Roll back `src/rendering/expression_engine.py`, expanded `src/rendering/data_transforms.py`, fit model additions, sidecar schema fields, and macOS data inspector additions if transform-aware rendering or project restore regresses.
  - The no-options import path remains the containment point for ordinary quick-plot recommendation performance.
- Actual regression results:
  - `.venv/bin/python -m pytest tests/test_expression_engine.py tests/test_data_transforms.py tests/test_rendering_services.py tests/test_sidecar_render.py tests/test_plot_project_routes.py tests/test_rendering_recommender.py -q`: passed (`126 passed`, existing warnings only).
  - `.venv/bin/python -m ruff check src/rendering/expression_engine.py src/rendering/data_transforms.py src/rendering/analytical_layers.py src/rendering/fit_analysis.py src/rendering/dataset_models.py src/rendering/cache.py src/rendering/options.py app/sidecar/routes_render.py app/sidecar/schemas_render.py app/sidecar/render_support.py app/sidecar/project_bundle.py tests/test_expression_engine.py tests/test_data_transforms.py tests/test_sidecar_render.py tests/test_plot_project_routes.py`: passed.
  - `.venv/bin/python -m mypy src/rendering src/data_loader.py`: passed.
  - `xcodebuild ... test -only-testing:SciPlotGodMacTests/SchemaDecodingTests/testDecodeRenderRequestWithExtraAxes -only-testing:SciPlotGodMacTests/PlotSessionTests/testDataTransformEditsRefreshPreviewUndoAndPersistIntoProjectPayload -only-testing:SciPlotGodMacTests/PlotSessionTests/testDataWorkbookTransformedTabRequestsTransformAwarePreview`: passed (`3 tests, 0 failures`; CoreSimulator out-of-date warning only).
  - `.venv/bin/python scripts/clean_repo.py`: passed.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix (`ruff` passed, `mypy` passed, `pytest` `255 passed, 5 warnings`, `smoke_check` passed, `xcodebuild build` passed, `xcodebuild test` `179 tests, 0 failures`; manual smoke checklist listed as pending but was not enforced).
  - `.venv/bin/python scripts/smoke_check.py`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`179 tests, 0 failures`; CoreSimulator out-of-date warning only).
  - `git diff --check`: passed.

### 2026-04-25: Typed Data Transform v1 backend path

- Change:
  - Added backend-owned `render_options.data_transforms` with typed v1 transform kinds: `derived_column`, `row_filter`, and `pivot_matrix`.
  - Implemented `src/rendering/data_transforms.py` with safe column-expression evaluation, explicit user-facing transform errors, row filtering, and `pivot_matrix` output normalized to heatmap-compatible XYZ long-table raw rows.
  - Added transform-aware raw/curve/replicate/heatmap loader seams in `src/rendering/cache.py`; no-transform requests keep the existing cached loader path.
  - Wired transforms through `RenderOptions`, sidecar render schemas, `/render-preview`, `/export-render`, `/preflight-render`, `/fit-analysis`, `/source-table-preview`, and `.sciplotgod` save/open normalization.
  - Added macOS `RenderOptionsPayload.dataTransforms`, basic `Advanced Plot -> Data` editing, undo/preview refresh persistence, and Data Workbook `Transformed` tab.
  - Reduced repeated Data Workbook table cell rendering by sharing one cell helper while keeping SwiftUI `TableColumn` static columns required by the framework.
- User-visible impact:
  - Plot users can add simple backend-applied data transforms before rendering, fitting, exporting, and saving projects.
  - Data Workbook can show the original source table or the transformed table without Swift executing math expressions.
- Decision Record:
  - First-principles motivation: DataGraph-style derived data should be a durable typed data-preparation layer, not renderer-local mutations or GUI-side spreadsheet logic.
  - Alternatives rejected: a free-form command interpreter or Swift expression evaluator would duplicate backend semantics and break project reproducibility; writing transformed temporary files would create hidden state and cache ambiguity.
  - Current boundary: v1 supports only single-table derivation/filter/pivot. No joins, groupby aggregation, arbitrary Python, spreadsheet editing, or animation. Column expressions are currently identifier-oriented; complex column names should be referenced through stable simple headers or column aliases in a later pass.
  - Failure conditions: if future renderers call `load_*_table_cached` directly for transform-enabled options, preview/export/fit can diverge from Data Workbook `Transformed`.
- Risk / rollback:
  - Roll back `src/rendering/data_transforms.py`, transform-aware cache wrappers, sidecar schema fields, and macOS `Data` inspector additions if transformed preview/export causes loader regressions.
  - The no-transform path remains on existing cached loaders, which is the main containment point.
- Actual regression results:
  - `.venv/bin/python -m pytest tests/test_data_transforms.py tests/test_rendering_services.py::test_contour_field_preflight_and_render_with_pivot_transform tests/test_sidecar_render.py::test_source_table_preview_accepts_data_transforms tests/test_sidecar_render.py::test_fit_analysis_accepts_data_transforms tests/test_plot_project_routes.py::test_save_open_project_roundtrip_preserves_data_transforms -q`: passed (`9 passed`, existing SWIG deprecation warnings).
  - `.venv/bin/python -m ruff check app/sidecar src/rendering src/data_loader.py tests/test_data_transforms.py tests/test_rendering_services.py tests/test_sidecar_render.py tests/test_plot_project_routes.py`: passed.
  - `.venv/bin/python -m mypy src/rendering src/data_loader.py`: passed.
  - `xcodebuild ... test -only-testing:SciPlotGodMacTests/SchemaDecodingTests/testDecodeRenderRequestWithExtraAxes -only-testing:SciPlotGodMacTests/PlotSessionTests/testDataTransformEditsRefreshPreviewUndoAndPersistIntoProjectPayload -only-testing:SciPlotGodMacTests/PlotSessionTests/testDataWorkbookTransformedTabRequestsTransformAwarePreview`: passed (`3 tests, 0 failures`; CoreSimulator out-of-date warning only).
  - `.venv/bin/python scripts/blocking_gate.py`: passed (`248 passed`, existing warnings only; `xcodebuild build` passed; `xcodebuild test` passed with `179 tests, 0 failures`; manual checks listed as pending but not enforced).
  - `.venv/bin/python scripts/smoke_check.py`: passed.
  - `git diff --check`: passed.

### 2026-04-25: Advanced template discovery and recommendation closure

- Change:
  - Extended backend source/dataset recognition so XYZ long tables and numeric matrix scalar fields are treated as `heatmap_table` with `matrix + scalar_field` shapes.
  - Added ranked recommendation coverage for `contour_field`, `polar_curve`, and `table_figure` without adding routes, legacy ids, or macOS-local template heuristics.
  - `POST /source-table-preview` now preserves `z` candidate roles for XYZ scalar inputs while still paginating source rows.
  - Tightened preflight/render guardrails: `polar_curve` requires theta/radius semantics, `contour_field` requires finite X/Y/Z with at least two distinct X and Y coordinates, and `table_figure` is bounded to compact tables.
  - Added `src/rendering/datagraph_inputs.py` so polar/table input semantics are shared by preflight and render instead of duplicated.
  - Added macOS tests proving scalar-field role decoding and backend-owned function expression errors are surfaced rather than recomputed in Swift.
- User-visible impact:
  - Importing scalar-field data now naturally offers contour output alongside heatmap output.
  - Importing theta/radius curve tables now promotes polar output.
  - Compact mixed tables now get a table-figure path; large sheets remain Data Workbook/source-table material instead of being forced into a figure.
- Risks and rollback points:
  - Roll back `src/data_loader.py` matrix support if legacy heatmap parsing regresses.
  - Roll back `src/rendering/dataset_models.py` / `src/rendering/recommender.py` if recommendation ranking becomes too aggressive for ordinary curve or replicate tables.
  - Roll back `src/rendering/preflight.py` / `src/rendering/render_datagraph.py` if table-size or polar validation blocks valid user files too narrowly.
- Actual regression results:
  - Baseline `.venv/bin/python scripts/smoke_check.py`: passed before changes.
  - `.venv/bin/python -m pytest tests/test_rendering_recommender.py -q`: passed (`13 passed`).
  - `.venv/bin/python -m pytest tests/test_rendering_services.py::test_normalized_dataset_builder_reuses_model_and_shape_signals tests/test_rendering_services.py::test_new_datagraph_templates_preflight_and_render tests/test_rendering_services.py::test_datagraph_template_preflight_reports_shape_specific_errors tests/test_rendering_services.py::test_function_curve_preflight_and_render_with_analytical_layer -q`: passed (`8 passed`).
  - `.venv/bin/python -m pytest tests/test_sidecar_render.py -q`: passed (`3 passed`, third-party SWIG deprecation warnings only).
  - `.venv/bin/python -m ruff check src/data_loader.py src/rendering/dataset_models.py src/rendering/recommender.py src/rendering/render_datagraph.py src/rendering/preflight.py src/rendering/source_table_preview.py tests/test_rendering_recommender.py tests/test_rendering_services.py tests/test_sidecar_render.py`: passed.
  - `.venv/bin/python -m mypy src/data_loader.py src/rendering/dataset_models.py src/rendering/recommender.py src/rendering/render_datagraph.py src/rendering/preflight.py src/rendering/source_table_preview.py`: passed.
  - `xcodebuild ... test -only-testing:SciPlotGodMacTests/SchemaDecodingTests/testDecodeSourceTablePreviewKeepsScalarFieldRoles -only-testing:SciPlotGodMacTests/PlotSessionTests/testAnalyticalFunctionLayerPreviewSurfacesBackendExpressionErrors`: passed (`2 tests, 0 failures`; CoreSimulator out-of-date warnings only).
  - `.venv/bin/python scripts/clean_repo.py`: passed.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix (`239 passed, 5 warnings`; macOS `177 tests, 0 failures`; manual checklist informational because `--require-manual` was not used).
  - `git diff --check`: passed.
- Decision:
  - First principles: after v1 render capability existed, the missing product value was discoverability through the same ranked recommendation path that makes this app faster than DataGraph for first plots.
  - Rejected alternative: macOS-side column-name sniffing for contour/polar/table affordances, because that would create a second recommendation source and drift from sidecar/contract truth.
  - Current boundary: this round improves data-shape recognition and validation only; final DataGraph-style GUI authoring remains a separate UI pass.

### 2026-04-25: DataGraph-inspired typed analytical layers and advanced templates

- Change:
  - Added explicit public templates in `src/plot_contract.json`: `function_curve`, `contour_field`, `polar_curve`, and `table_figure`; regenerated `docs/plot_contract.md`.
  - Added backend-owned `render_options.analytical_layers` with a bounded `function` v1 payload (`expression`, domain, sample count, target y-axis, label, enabled).
  - Implemented safe AST expression parsing/sampling in `src/rendering/analytical_layers.py`; no frontend math execution and no free-form command interpreter.
  - Wired the payload through render option normalization, render preview/export, sidecar schemas, `.sciplotgod` save/open normalization, macOS Codable models, PlotSession undo/redo path, and a basic `Advanced Plot -> Functions` inspector.
  - Added DataGraph-inspired renderers for function overlays, contour fields, polar curves, and compact table figures through `render_registry` and explicit preflight/output naming.
- User-visible impact:
  - Plot can now render safe analytic function overlays through a typed function layer on `function_curve`.
  - New public templates appear through contract/meta surfaces for contour, polar, and table figures.
  - Basic macOS inspector controls can add/edit/remove function layers; final GUI polish is intentionally left for a later UI-focused pass.
- Risks and rollback points:
  - Roll back `src/plot_contract.json` plus generated `docs/plot_contract.md` to remove the new public templates.
  - Roll back `src/rendering/analytical_layers.py`, `src/rendering/render_datagraph.py`, and registry/schema/project wiring if function/template rendering regresses.
  - Contour/polar/table renderers are intentionally v1 implementations; future GUI work may need richer role mapping without changing the typed backend contract.
  - Manual GUI smoke was not enforced in this terminal run; automated macOS build/test and session tests passed.
- Actual regression results:
  - `.venv/bin/python scripts/generate_plot_contract_docs.py`: passed.
  - `.venv/bin/python -m pytest tests/test_plot_contract.py tests/test_rendering_services.py::test_function_curve_preflight_and_render_with_analytical_layer tests/test_rendering_services.py::test_new_datagraph_templates_preflight_and_render tests/test_sidecar_render.py::test_render_preview_accepts_analytical_function_layers tests/test_plot_project_routes.py::test_save_open_project_roundtrip_preserves_analytical_layers -q`: passed (`8 passed`).
  - `xcodebuild ... test -only-testing:SciPlotGodMacTests/SchemaDecodingTests -only-testing:SciPlotGodMacTests/PlotSessionTests/testAnalyticalFunctionLayerEditsRefreshPreviewAndPersistIntoProjectPayload`: passed (`8 tests, 0 failures`).
  - `.venv/bin/python scripts/clean_repo.py`: passed.
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed.
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed.
  - `.venv/bin/python -m pytest tests`: passed (`234 passed, 5 warnings`).
  - `.venv/bin/python scripts/smoke_check.py`: passed.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix; manual checklist remained informational because `--require-manual` was not used.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed inside blocking gate.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed inside blocking gate (`175 tests, 0 failures`).
  - `git diff --check`: passed.
- Decision:
  - First principles: DataGraph's transferable value here is durable table/graph state and replayable drawing semantics, not a second free-form scripting surface.
  - Rejected alternative: a DataGraph-like arbitrary command stack or frontend expression evaluator, because it would duplicate backend semantics and weaken project durability.
  - Current boundary: `analytical_layers` supports only safe sampled functions; expression columns, masks, pivot transforms, and animation remain future explicit typed capabilities.

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

### 2026-04-24: Data Studio import template auto-adoption must be recommendation-driven

- Change:
  - Added `POST /data-studio/template-recommendations` (typed request/response) and wired it through sidecar runtime critical-route compatibility checks.
  - macOS Data Studio resolver now consumes ranked template recommendations and preselects only the top recommended template.
  - Removed resolver behavior that silently defaulted to builtin template on raw import when no recommendation existed.
  - Template-creation flow now generates minimal `match_conditions` from current source preview hints so newly created user templates can participate in later recommendation matching.
  - Recommendation ranking now prefers higher confidence first, and for equal confidence prefers user templates over builtin templates.
- Why:
  - First principles: the “template selected by default” state must come from one backend-owned semantic source, not from frontend hardcoded fallback.
  - The broken user experience (“create succeeded but no effect”) was a post-creation adoption failure, not a create-template failure.
- Rejected alternatives:
  - Keep default fallback to builtin tensile when recommendation is empty: rejected because it silently applies incorrect parsing semantics for non-tensile sources.
  - Reintroduce legacy `/data-studio/source-preview` candidate path: rejected because v2 template/recommendation flow already has a typed source of truth and legacy path is removed by policy.
  - Add frontend-local recommendation heuristics: rejected because it creates a second rule engine outside Python ingest truth source.
- Boundaries:
  - No change to Data Studio staged wizard structure.
  - No restoration of removed legacy endpoints.
  - Resolver auto-selection only occurs when sidecar recommendation payload is non-empty; otherwise selection must remain explicit/manual.

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

### Symptom: Swift compile error `cannot find '<helper>' in scope` right after adding a new shared utility file

- Typical cause:
  - the new Swift file exists on disk but was not added to `app/macos/SciPlotGod.xcodeproj`, so Xcode never compiled it into the app target.
- Check:
  - confirm the file appears in `project.pbxproj` as both a `PBXFileReference` and a `PBXBuildFile`.
  - confirm it is listed under the shared `Sources` group and the app target `PBXSourcesBuildPhase`.
- Fix pattern:
  - add the file to the Xcode project and app target membership, then rerun the smallest meaningful `xcodebuild` scope first.
  - if the missing helper is only referenced from tests, still prefer compiling it through the main app target instead of duplicating the helper in test-only code.

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

### 2026-04-19 (Round AM): Make GUI workspace actions fail visibly and close silent desktop no-ops

- Scope:
  - Hardened `app/macos/Sources/Shared/Utilities/WorkspaceBridge.swift` so desktop `open` and `reveal` actions validate target existence and throw visible, user-facing errors instead of silently returning.
  - Routed Plot, Data Studio, Composer, and Code Console file/open/reveal helpers through that throwing bridge so missing exports, missing sources, and missing managed output folders now surface into each session's `errorMessage`.
  - Added shared `revealOutputAvailability` state where needed and wired menu/inspector enablement to that state so `Reveal in Finder` is disabled when the current workbench has nothing valid to reveal.
  - Moved runtime bootstrap failure presentation to `app/macos/Sources/App/RootSplitView.swift` so sidecar/bootstrap errors remain visible across Plot, Data Studio, Composer, and Code Console rather than disappearing outside Plot.
  - Added a top-level Composer workbench diagnostic card and removed inspector-only error rendering so Composer failures remain visible even when the inspector is hidden.
  - Added targeted macOS regression coverage in `app/macos/Tests/AppModelTests.swift`, `PlotSessionTests.swift`, `ComposerSessionTests.swift`, `DataStudioSessionTests.swift`, `CodeConsoleSessionTests.swift`, and new `WorkspaceBridgeTests.swift` for the new visible-failure semantics.
- User-visible impact:
  - `File > Reveal in Finder` and inspector `Reveal Output` actions now disable with the correct explanation when there is nothing to reveal, instead of doing nothing.
  - Failed file-open, Finder-reveal, and latest-export actions now show a concrete error message when the target file or folder is gone.
  - Sidecar/bootstrap startup failures now stay visible no matter which primary workbench is active.
  - Composer import/export/placement failures stay visible in the main workbench even if the inspector is closed.
- Risks:
  - Existing tests covered the success paths more than the desktop failure surface, so this round intentionally changed user-facing error timing for missing files and folders; future UX cleanup should preserve the new visible-failure behavior rather than reintroducing guard-return no-ops.
  - The global runtime error card now appears above every workbench detail. If a future round adds another app-level diagnostic surface, those surfaces should be reconciled instead of stacked independently.
- Rollback points:
  - `app/macos/Sources/Shared/Utilities/WorkspaceBridge.swift`
  - `app/macos/Sources/App/AppModel.swift`
  - `app/macos/Sources/App/AppCommands.swift`
  - `app/macos/Sources/App/RootSplitView.swift`
  - `app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
  - `app/macos/Sources/Features/DataStudio/DataStudioSessionComparison.swift`
  - `app/macos/Sources/Features/Composer/ComposerSessionImportExport.swift`
  - `app/macos/Sources/Features/Composer/ComposerWorkbenchView.swift`
  - `app/macos/Sources/Features/CodeConsole/CodeConsoleSession.swift`
  - `app/macos/Tests/WorkspaceBridgeTests.swift`
- Decision:
  - Desktop file-system actions must share one explicit failure contract: validate availability first, disable and explain when there is nothing actionable, and surface a visible error when a previously actionable path becomes invalid.
  - Runtime bootstrap failure is app-level state, not Plot-only state, so the supported presentation surface now lives at the shared workbench detail layer instead of a single feature workbench.
  - Rejected alternatives:
    - leave `NSWorkspace` failures silent and only tune inspector button disablement: rejected because menu actions and stale paths would still fail without visible feedback
    - keep bootstrap errors local to Plot and duplicate equivalent banners elsewhere later: rejected because it would recreate the same runtime truth in multiple workbenches
    - keep Composer error feedback inside the inspector: rejected because hiding the inspector also hid the only failure surface
  - Boundary:
    - this round does not change sidecar routes, plot contract payloads, project schema, persistence format, or canonical workbench flows
    - the new availability/error plumbing is macOS UI/runtime behavior only
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`135 tests`)
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 34 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`176 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `git diff --check`: passed
  - Manual desktop verification before implementation:
    - `Computer Use` confirmed on 2026-04-19 that empty Plot state left `File > Reveal in Finder` enabled while `Export` was already disabled
    - Additional `Computer Use` exploration was stopped once the native macOS automation session lost window handles during system open-panel interaction, per this round's instruction to stop on permission/automation issues

### 2026-04-19 (Round AN): Independent theme + palette defaults with `nature` metrics frozen

- Scope:
  - Expanded `src/plot_contract.json` with three new public palettes, `infographic`, `roma`, and `macarons`, and added per-template recommended `default_options.visual_theme_id` while keeping public `style_preset` limited to `nature`.
  - Added matching soft visual themes in `src/rendering/themes.py` and extended rendering/recommendation option resolution so missing `palette_preset` / `visual_theme_id` fall back to the active template defaults instead of silently forcing workspace-global carry-over.
  - Updated Plot/Data Studio macOS session restore/reset paths and tests so:
    - template switch/reset loads the current template's recommended theme + palette when the current figure has no explicit saved override
    - user edits remain independent, so changing theme does not rewrite palette and vice versa
    - reopened saved figures keep persisted values and only fall back when values are missing or invalid
  - Regenerated `docs/plot_contract.md` and updated `README.md` plus `AGENTS.md` so the documented public surface matches the shipped contract.
- User-visible impact:
  - Plot and Data Studio now expose new ECharts-inspired visual options through independent `Theme` and `Palette` controls while still showing a single public hard style, `Nature`.
  - New figures and template resets now start from the selected template's recommended theme/palette pair instead of inheriting the last unsaved figure's still-valid visual combination.
  - Saved/opened figures preserve their explicit theme/palette choices.
  - Typography, stroke widths, spacing, axis frame, and export metrics remain unchanged from `nature`.
- Risks:
  - Every public template now depends on contract-owned `default_options.palette_preset` and `default_options.visual_theme_id`; future templates must populate both or macOS will fall back to broader meta defaults.
  - This round intentionally changed unsaved figure reset behavior for palette/theme. Future macOS session refactors should preserve the new figure-scoped default semantics instead of reintroducing workspace carry-over.
  - Direct `Computer Use` automation could not obtain a live `SciPlot God` window handle in this environment (`cgWindowNotFound`), so the final visual pass used exported GUI smoke attachments as the fallback artifact source.
- Rollback points:
  - `src/plot_contract.json`
  - `src/rendering/themes.py`
  - `src/rendering/options.py`
  - `src/rendering/recommendation.py`
  - `src/rendering/recommender.py`
  - `src/rendering/render_service.py`
  - `src/code_console_service.py`
  - `app/macos/Sources/Features/Plot/PlotSession.swift`
  - `app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
  - `app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
  - `app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
  - `app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `app/macos/Tests/TestPayloads.swift`
  - `app/macos/Tests/PlotSessionTests.swift`
  - `app/macos/Tests/DataStudioSessionTests.swift`
  - `app/macos/Tests/SchemaDecodingTests.swift`
  - `tests/test_plot_contract.py`
  - `tests/test_rendering_services.py`
  - `tests/test_sidecar_schema_contract.py`
- Decision:
  - Template-recommended theme and palette are figure-scoped defaults, not a second workspace-global preference layer. When the active figure context changes without explicit saved overrides, the supported behavior is to re-seed from the target template's contract defaults.
  - Public visual variety now grows through independent `palette_preset` and `visual_theme_id`, while hard publication style remains a single `nature` profile. This keeps fonts, line widths, spacing, and export metrics frozen while still giving users more visual range.
  - Rejected alternatives:
    - add a second public `style_preset`: rejected because that would fork the hard publication metrics the product is intentionally keeping frozen
    - auto-bind theme and palette as one combined preset after selection: rejected because it would break the existing independent-control inspector model and make user overrides unpredictable
    - preserve the previous figure's valid theme/palette during template reset: rejected because visual defaults are part of the new figure's template identity, not the last figure's unsaved local state
  - Boundary:
    - this round does not add new public schema fields or change saved render-option shape
    - this round does not alter `nature` typography, stroke, spacing, axis frame, export settings, or QA thresholds
    - soft visual themes remain limited to allowed background/grid/legend/panel styling
- Validation (executed):
  - `.venv/bin/python scripts/generate_plot_contract_docs.py`: passed
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 34 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`177 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests -only-testing:SciPlotGodMacTests/DataStudioSessionTests -only-testing:SciPlotGodMacTests/SchemaDecodingTests`: passed (`78 tests`)
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`138 tests`)
  - `xcrun xcresulttool export attachments --path app/macos/.derivedData/Logs/Test/Test-SciPlotGodMac-2026.04.19_19-16-50-+0800.xcresult --output-path app/macos/.derivedData/gui-attachments`: passed (`5 attachments exported`)
  - `Computer Use` visual QA:
    - direct automation against `SciPlot God` returned `cgWindowNotFound` for the live app window
    - fallback inspection succeeded by opening exported GUI smoke attachments in Preview and visually checking:
      - `Plot template gallery`
      - `Data Studio template editor`

### 2026-04-19 (Round AO): Public multi-style surface, ECharts-inspired visual families, and new curve templates

- Scope:
  - Superseded the same-day Round AN assumption that public hard style must remain single-`nature`; the public contract now exposes `nature`, `editorial`, `presentation`, and `poster`, while still normalizing every legacy ingress alias back to `nature`.
  - Expanded [src/plot_contract.json](/Users/dongxutian/Documents/codegod/src/plot_contract.json) with two more official ECharts-inspired palette/theme families, `shine` and `vintage`, and added two new explicit public templates, `area_curve` and `step_line`.
  - Kept `style_preset`, `palette_preset`, and `visual_theme_id` as independent persisted controls across sidecar, rendering, export manifest, Plot, and Data Studio. Template defaults now recommend all three, but changing one control never rewrites the other two.
  - Added rendering support, recommendation support, output naming, QA/test coverage, and macOS gallery/test fixtures for `area_curve` and `step_line` without reintroducing local template heuristics or a second GUI constant table.
- User-visible impact:
  - Plot and Data Studio now expose four public hard styles instead of just `Nature`; `Nature` stays the frozen publication baseline, while `Editorial`, `Presentation`, and `Poster` intentionally vary font size, line width, marker size, and related hard metrics.
  - Users can still change palette/theme while staying on `Nature`, so the frozen `Nature` preset no longer blocks softer visual variation.
  - Plot gallery now includes `Area curve` and `Step line` as first-class template choices with dedicated thumbnails and backend-owned defaults.
  - New visual families now include `infographic`, `roma`, `macarons`, `shine`, and `vintage`, with template-specific recommendations instead of one global carry-over look.
- Risks:
  - Adding multiple public style ids means future contract edits must keep the non-`nature` style metrics intentional and documented; accidental drift is now a broader regression surface than the previous single-style model.
  - `area_curve` and `step_line` reuse the standard curve pipeline; future curve refactors must keep their fill/drawstyle behavior, bundle output naming, and recommender eligibility in sync rather than treating them as plain `curve` aliases.
  - The live app visual check reached Plot/Data Studio empty states and Plot import flow, but the richer Data Studio figure-inspector picker state was still verified through shared `PlotInspectorView` tests plus exported GUI smoke attachments rather than a fully interactive manual session.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/src/plot_contract.json`
  - `/Users/dongxutian/Documents/codegod/src/plot_style.py`
  - `/Users/dongxutian/Documents/codegod/src/plotting_curves.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/common.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/constants.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/preflight.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/qa.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/recommender.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_curve.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_registry.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/template_catalog.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/themes.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
  - `/Users/dongxutian/Documents/codegod/README.md`
  - `/Users/dongxutian/Documents/codegod/AGENTS.md`
  - `/Users/dongxutian/Documents/codegod/docs/plot_contract.md`
- Decision:
  - First-principles motivation: the product needs independent control over chart template, hard style, palette, and soft theme. Freezing `nature` alone is useful for a publication-safe baseline, but it should not block users from opting into other deliberate hard styles when they want a different presentation density or stage scale.
  - `nature` remains the compatibility anchor and frozen publication profile. Legacy style aliases still collapse into `nature`, while the newly public non-`nature` styles are explicit product semantics rather than hidden private presets.
  - ECharts inspiration is now applied in two layers:
    - official palette/theme mood via `infographic`, `roma`, `macarons`, `shine`, and `vintage`
    - explicit chart-type inspiration via `area_curve` and `step_line`
  - Rejected alternatives:
    - keep public style fixed to `nature` and only add palettes/themes: rejected because it still blocks intentional hard-style variation that the user explicitly approved
    - bind each style to a single palette/theme bundle: rejected because the current product model requires independent picker control with template recommendations only
    - treat `area_curve` and `step_line` as hidden aliases of `curve`: rejected because users asked for visible chart-type templates aligned with the rest of the gallery
  - Boundary:
    - `nature` typography, line widths, spacing, axis frame, and export settings remain frozen
    - visual themes still cannot override protected rcParams, even for non-`nature` styles
    - this round adds no new route shapes or saved project schema fields; it only expands the allowed public catalog values
- Validation (executed):
  - `.venv/bin/python scripts/generate_plot_contract_docs.py`: passed
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 34 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`180 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`139 tests`)
  - `git diff --check`: passed
  - `Computer Use` visual QA:
    - launched the locally built `/Users/dongxutian/Documents/codegod/app/macos/.derivedData/Build/Products/Debug/SciPlot God.app`
    - confirmed the live Plot gallery shows `Curve`, `Point line`, `Area curve`, `Step line`, and `Stacked curve` with distinct thumbnails
    - confirmed the live Data Studio empty-state shell still uses the shared workbench/inspector structure
    - exported GUI smoke attachments from `/Users/dongxutian/Documents/codegod/app/macos/.derivedData/Logs/Test/Test-SciPlotGodMac-2026.04.19_19-51-35-+0800.xcresult` and used them as the artifact fallback for Data Studio template/specimen views

### 2026-04-20 (Round AP): Public-surface guardrails, second-wave templates, imported-state GUI smoke, and shared cancellation cleanup

- Scope:
  - Expanded the public contract/rendering surface with two more explicit templates that reuse existing data shapes:
    - `stacked_area` for curve-like grouped traces
    - `density_area` for replicate-table density distributions
  - Updated `src/plot_contract.json`, `src/plot_contract.py`, `src/rendering/*`, recommendation logic, preflight/output naming, and Plot/Data Studio gallery metadata so the new templates are first-class contract-backed entries rather than aliases.
  - Strengthened `scripts/smoke_check.py` with:
    - public-template contract lint for required `default_options.style_preset / palette_preset / visual_theme_id`
    - a fixed style/theme/template render matrix over representative `curve / area_curve / step_line / bar / scatter / heatmap`
  - Extended macOS GUI smoke/fingerprint coverage in `app/macos/Tests/InspectorLayoutPolicyTests.swift` to include imported-state inspector snapshots for:
    - `Plot imported inspector`
    - `Data Studio figure inspector`
  - Added the shared macOS cancellation helper `app/macos/Sources/Shared/Utilities/UserCancellation.swift` and routed Plot import/preview, Data Studio template refresh, Code Console context refresh, and app bootstrap through the same cancellation-as-control-flow check.
  - Updated `README.md`, `AGENTS.md`, generated `docs/plot_contract.md`, fixtures, mocks, and regression tests so the documented surface matches the new guardrails.
- User-visible impact:
  - Plot/Data Studio can now expose `stacked_area` and `density_area` as real contract-backed templates with their own recommendations, output naming, and gallery thumbnails.
  - Imported-state inspector coverage is now part of the shipped macOS regression harness, so visual regressions in the real Plot/Data Studio picker state should get caught earlier.
  - Plot, Code Console, and app bootstrap flows now suppress cancellation noise consistently instead of surfacing implementation-level failure text when lifecycle work is cancelled.
  - No new explanatory microcopy or extra inspector controls were added.
- Risks:
  - `stacked_area` and `density_area` now widen the explicit public template surface; future changes must keep contract/catalog/recommender/preflight/render/output naming/macOS thumbnail coverage in sync.
  - The new smoke matrix is intentionally fixed and representative rather than exhaustive; weakening or deleting it will reduce coverage exactly where the public surface is now broadest.
  - Shared cancellation handling depends on `UserCancellation.swift` staying in the Xcode target; future file moves must preserve target membership.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/src/plot_contract.json`
  - `/Users/dongxutian/Documents/codegod/src/plot_contract.py`
  - `/Users/dongxutian/Documents/codegod/src/plotting_curves.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/common.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/preflight.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/qa.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/recommender.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_curve.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_registry.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_stats.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/template_catalog.py`
  - `/Users/dongxutian/Documents/codegod/scripts/smoke_check.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/Utilities/UserCancellation.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/MockSidecarClient.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/DataStudioSessionTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/CodeConsoleSessionTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/AppModelTests.swift`
  - `/Users/dongxutian/Documents/codegod/README.md`
  - `/Users/dongxutian/Documents/codegod/AGENTS.md`
  - `/Users/dongxutian/Documents/codegod/docs/plot_contract.md`
- Decision:
  - First-principles motivation: once style/theme/palette/template surfaces become broader, the dominant product risk shifts from “missing one more option” to “combinations drift silently.” That makes fixed guardrails more valuable than immediately adding even more templates.
  - Public second-wave templates were limited to existing data shapes on purpose. `stacked_area` reuses grouped curve semantics, and `density_area` reuses replicate-table density semantics, so this round expands visible choices without opening a second raw-schema migration.
  - Imported-state GUI smoke now treats the inspector itself as a canonical product surface. Artifact-based xcresult attachments remain the preferred visual QA source instead of inventing a parallel screenshot pipeline.
  - Rejected alternatives:
    - keep adding ECharts-inspired templates without strengthening smoke/contract lint first: rejected because regressions would be more likely than net product improvement
    - do imported-state visual QA only by ad-hoc manual clicking: rejected because the critical states must be reproducible in automated regression runs
    - keep per-workbench cancellation filtering as one-off conditionals: rejected because lifecycle cancellation is a shared runtime concern, not feature-local copy
  - Boundary:
    - this round does not introduce a new raw data schema
    - this round does not loosen `nature`'s frozen publication metrics
    - the smoke matrix is representative coverage, not a requirement to render every style/theme/template combination in one run
- Troubleshooting note:
  - During implementation, `xcodebuild` initially failed because `UserCancellation.swift` existed on disk but was not yet in the Xcode project target. Future shared utilities should be checked for PBX file reference + sources-phase membership as soon as Swift reports a helper missing from scope.
- Validation (executed):
  - `.venv/bin/python scripts/generate_plot_contract_docs.py`: passed
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 34 source files`)
  - `.venv/bin/python -m pytest tests/test_plot_contract.py tests/test_sidecar_schema_contract.py tests/test_rendering_services.py tests/test_rendering_recommender.py tests/test_recommendation_policy.py`: passed (`81 passed, 5 warnings`)
  - `.venv/bin/python -m pytest tests`: passed (`186 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests`: passed (`5 tests`)
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests -only-testing:SciPlotGodMacTests/DataStudioSessionTests -only-testing:SciPlotGodMacTests/CodeConsoleSessionTests -only-testing:SciPlotGodMacTests/AppModelTests -only-testing:SciPlotGodMacTests/SchemaDecodingTests`: passed (`104 tests`)
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`144 tests`)
  - `git diff --check`: passed
  - Imported-state GUI artifact pass:
    - exported snapshot PNGs during the focused inspector run to `/tmp/sciplot-gui-snapshots`
    - full `InspectorLayoutPolicyTests` fingerprint/smoke coverage now includes `Plot imported inspector` and `Data Studio figure inspector`

### 2026-04-21 (Round AQ): Plot self-contained project bundles, Data Workbook, and linear fit v1

- Scope:
  - Added Plot project-file persistence through sidecar schema normalization and zip-bundle IO:
    - `POST /save-project`
    - `POST /open-project`
    - bundle structure:
      - `project.json`
      - `sources/primary/<original-filename>`
      - `artifacts/manifest.json`
  - Added Plot data-analysis routes:
    - `POST /source-table-preview`
    - `POST /fit-analysis`
  - Introduced shared backend fit analysis in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/fit_analysis.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/render_curve.py`
    - linear fit now uses one `statsmodels.OLS`-backed helper for both `scatter_fit` rendering and Data Workbook fit summaries.
  - Added app-managed restored source persistence in:
    - `/Users/dongxutian/Documents/codegod/src/infrastructure/persistence/plot_projects.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
  - Extended macOS Plot session/client/runtime wiring so Plot can:
    - open raw source files or `.sciplotgod`
    - save `Save Project…` / `Save Project As…`
    - track `projectURL` and `isProjectDirty`
    - restore source file, sheet, template, style/palette/theme, and render options from a saved Plot project
  - Replaced the old hidden `Source Inspector` with `PlotDataWorkbookSheet` in `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`:
    - `Source Data` tab: paged read-only table
    - `Fit` tab: linear equation, slope, intercept, `R²`, `RMSE`, point count, and derived rows
  - Updated `README.md`, `AGENTS.md`, snapshot fixtures, and new Python/macOS regression coverage for the new project/file-analysis surface.
- User-visible impact:
  - Plot can now save a self-contained `.sciplotgod` file that embeds the original csv/xlsx/xlsm bytes together with durable Plot state; reopening the project returns to the same Plot starting point even if the original source path is gone.
  - Plot now exposes a discoverable `Data` affordance that opens `Data Workbook` instead of the old hidden diagnostic sheet.
  - `Data Workbook` v1 lets users inspect paged source rows and run a linear fit with equation/statistics output directly inside Plot.
  - Plot command menus now expose `Save Project…` and `Save Project As…`.
  - No inline spreadsheet editing, autosave, or non-linear fitting was added in this round.
- Risks:
  - `.sciplotgod` is now a binary zip bundle with embedded source bytes; large workbook inputs will increase project-file size, and future schema changes must continue to go through sidecar normalization rather than direct client JSON edits.
  - Data Workbook v1 intentionally caps the visible SwiftUI table to the index column plus the first nine source columns because of the current macOS `Table` builder limits; wide sheets remain paged by row but not fully horizontally exhaustive yet.
  - Fit analysis is linear-only in v1; expanding to polynomial/custom models must keep the shared helper path intact or the rendered fit line, displayed equation, and derived rows can drift apart again.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
  - `/Users/dongxutian/Documents/codegod/src/infrastructure/persistence/plot_projects.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/fit_analysis.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_curve.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSession.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionTypes.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppCommands.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppModel.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarClient.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/Utilities/FileTypeCatalog.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/Utilities/NativePanels.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Info.plist`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/MockSidecarClient.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
  - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_sidecar_active_routes.py`
  - `/Users/dongxutian/Documents/codegod/README.md`
  - `/Users/dongxutian/Documents/codegod/AGENTS.md`
- Decision:
  - First-principles motivation: “open project and return to the same work starting point” is impossible if Plot only persists source paths. The durable state therefore has to be coupled to the original source bytes, not just to a JSON pointer.
  - Chose one self-contained zip bundle over a path-only JSON file:
    - accepted because it is portable, lets Plot recover after the original source path disappears, and keeps schema migration centralized in sidecar
    - rejected path-only persistence because moving/deleting the original csv/xlsx would break the core restore promise
  - Chose a read-only SwiftUI `Table` workbook v1 over an editable spreadsheet surface:
    - accepted because the immediate product need is inspection + fit analysis, not cell editing
    - rejected AppKit/NSTableView editing in this round because it would widen scope and runtime complexity before the fit/project-file loop is proven
  - Boundary:
    - Plot workflow remains `Import -> Inspect -> Template -> Refine -> Preflight -> Export`; `Data Workbook` is a utility affordance, not a new app-level stage
    - v1 project restore covers Plot durable work state only, not undo history, temporary errors, export history, or transient sheet/popup UI
    - v1 fit analysis is linear-only
- Troubleshooting note:
  - SwiftUI macOS `Table` column builders remain fragile here:
    - dynamic `ForEach` over `TableColumn` content did not compile cleanly in this project setup
    - the builder also effectively caps one table declaration at ten columns
    - if Data Workbook wide-sheet work resumes later, prefer either an AppKit bridge or another explicit typed presentation strategy instead of trying to push a more dynamic `TableColumnBuilder` shape through the current view
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 35 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`190 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`147 tests`)
  - `git diff --check`: passed

Use this block for every new round:

```
### YYYY-MM-DD (Round X): <title>

- Scope:
- User-visible impact:
- Risks:
- Decision:
- Validation (commands + result):
```

### 2026-04-22 (Round AR): Data Studio analysis, shared multi-model fit, and app-level project bundles

- Scope:
  - Expanded `.sciplotgod` from a Plot-only bundle into an app-level project file in:
    - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_projects.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_projects.py`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppModel.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppCommands.swift`
  - New bundle layout now supports:
    - `project.json`
    - `sources/plot/primary/<filename>` optional
    - `sources/data_studio/workbooks/<filename>` optional
    - `artifacts/manifest.json`
  - Added typed Data Studio project persistence so `selected_workbench=data_studio` can embed workbook bytes plus normalized session state and restore through the existing session pipeline instead of rebuilding from raw import paths.
  - Promoted fit analysis into a shared rendering service in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/fit_analysis.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/render_curve.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
  - Shared fit service now supports:
    - `linear`
    - `polynomial_2`
    - `polynomial_3`
    and returns per-series summaries, diagnostics, equations, and derived rows for both Plot and Data Studio.
  - Added Data Studio `Analysis` utility in:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionComparison.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarClient.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `Analysis` supports two scopes:
    - `Focused Workbook`
    - `Current Figure`
    with `Source Data` and `Fit` tabs, paging via `POST /source-table-preview`, and fit inspection via shared `POST /fit-analysis`.
  - Extended Data Studio figure persistence so `render_options` and `fit_options` are kept independently by template/family and flow through preview, export, Open in Plot, save project, and restore project.
  - Updated regression fixtures and tests in:
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/DataStudioSessionTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
    - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_sidecar_active_routes.py`
  - Refreshed `README.md` and `AGENTS.md` to document the app-level bundle shape, shared fit routes, and Data Studio analysis surface.
- User-visible impact:
  - Data Studio can now save and reopen a self-contained `.sciplotgod` project that restores the same workbook-backed session even after the original workbook path is removed.
  - Opening a saved Data Studio project returns directly to the Data Studio workbench instead of falling back to Plot first.
  - Data Studio now exposes an `Analysis` utility for workbook rows and curve fitting without leaving the workbench.
  - Curve-like figures in Data Studio can apply `linear`, `polynomial_2`, or `polynomial_3` fits, carry those fit settings into export and Open in Plot, and restore them from saved session/project state.
  - Metric families remain unchanged in this round; fitting is intentionally limited to curve-like figure families.
- Risks:
  - `.sciplotgod` now has two embedded-source modes; future schema changes must continue to go through sidecar normalization and migration or Plot/Data Studio restore behavior can diverge.
  - Data Studio restore now trusts embedded workbook bytes rather than `imported_paths`; any future optimization that bypasses materialization risks breaking the “reopen exactly where you left off” guarantee.
  - Shared multi-model fit is now part of both analysis and renderer overlay paths; if one caller bypasses `src/rendering/fit_analysis.py`, displayed equations and exported fit lines can drift again.
  - `Current Figure` fit remains intentionally bounded to curve-like contexts; widening it to metric families will need explicit UX and schema work instead of silent enablement.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_projects.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_projects.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/fit_analysis.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_curve.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppModel.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppCommands.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionComparison.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionProjects.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarClient.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsProjects.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/DataStudioSessionTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
  - `/Users/dongxutian/Documents/codegod/README.md`
  - `/Users/dongxutian/Documents/codegod/AGENTS.md`
- Decision:
  - First-principles motivation: Data Studio’s true work state is the workbook-backed compare/filter/figure session, not just a rendered figure snapshot. If the project file cannot restore that workbook-backed session from embedded bytes, it does not meet the “reopen exactly where you left off” requirement.
  - Chose one app-level `.sciplotgod` bundle over separate Plot-only and Data Studio-only formats:
    - accepted because one schema and one save/open route keep workbench restore behavior centralized in sidecar
    - rejected separate per-workbench formats because they would duplicate migration logic and drift on restore semantics
  - Chose fit as a shared orthogonal capability instead of duplicating `*_fit` recipes:
    - accepted because Plot rendering, Data Studio analysis, export overlays, and Open in Plot all need the same coefficients, equations, and diagnostics
    - rejected family-specific fit recipe duplication because it would multiply template ids and drift the backend math
  - Boundary:
    - Data Studio projects embed workbook files, not original raw files
    - fitting remains limited to curve-like figure families
    - no autosave, no multi-workbench concurrent editing conflict handling, and no user-defined formulas in this round
- Troubleshooting note:
  - New Data Studio project-save tests can fail if the mock normalize endpoint returns a stale canned session response instead of the session’s current fit-option state.
  - The durable fix is to override `dataStudioNormalizeSessionHandler` in the test and synthesize the response from the live session state; otherwise project-save assertions can look like persistence regressions even when the runtime path is correct.
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 35 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`191 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/DataStudioSessionTests`: passed (`54 tests`)
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`151 tests`)
- `git diff --check`: passed

### 2026-04-22 (Round AS): Plot fit overlay productization and project persistence

- Scope:
  - Productized the existing Plot fit path instead of adding a new advanced-layer framework in:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSession.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
  - Plot now exposes one typed fit state (`FitOptionsPayload`) through the whole durable path in:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
  - Save/open project now preserves Plot fit state through `.sciplotgod` normalization and restore, rather than treating fit as a transient workbook-only utility.
  - Plot tests and fixtures were extended in:
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
    - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
  - Refreshed `/Users/dongxutian/Documents/codegod/README.md` and `/Users/dongxutian/Documents/codegod/AGENTS.md` so Plot guidance matches the shipped behavior.
- User-visible impact:
  - Plot inspector now shows an `Advanced Plot` section for `curve`, `point_line`, and `scatter`.
  - Users can enable a fit overlay and choose `Linear`, `Polynomial 2`, or `Polynomial 3` from the inspector without leaving the main Plot workflow.
  - `Data Workbook -> Fit` now uses the same selected model, exposes the same multi-model fit surface, and allows series selection when multiple series are present.
  - Saving and reopening a Plot `.sciplotgod` project now restores the selected fit model and whether the overlay is enabled.
- Risks:
  - Plot overlay and workbook fit are now coupled through shared `fit_options`; if a future caller bypasses this typed path, overlay state and workbook analysis can drift again.
  - `Advanced Plot` availability is intentionally limited to `curve`, `point_line`, and `scatter`; adding new curve-like templates later must update the same availability seam instead of sprinkling local exceptions.
  - Multi-series selection remains a workbook-analysis viewing state, not durable project state; if that ever needs persistence, it should be added explicitly rather than inferred from the last response.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSession.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
  - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
  - `/Users/dongxutian/Documents/codegod/README.md`
  - `/Users/dongxutian/Documents/codegod/AGENTS.md`
- Decision:
  - First-principles motivation: Plot already had the important pieces of an advanced fitting capability, but they lived as partly separate affordances. The fastest low-risk way to move toward DataGraph-style refinement was to make fit one typed, durable capability that is shared by overlay, workbook analysis, undo/redo, export, and project restore.
  - Chose typed `fit_options` productization over a new generic advanced-layer schema:
    - accepted because it reuses the existing shared backend fit helper and keeps Plot on one source of truth
    - rejected a new free-form advanced-layer stack in this round because it would add schema/UI complexity before we had even shipped the first durable advanced control
  - Boundary:
    - this round only productizes fit
    - no new contract surface in `src/plot_contract.json`
    - no changes to frozen `nature` metrics, fonts, line widths, spacing, or export specs
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 35 source files`)
- `.venv/bin/python -m pytest tests/test_plot_project_routes.py`: passed (`5 passed, 5 warnings`)
- `.venv/bin/python -m pytest tests`: passed (`191 passed, 5 warnings`)
- `.venv/bin/python scripts/smoke_check.py`: passed
- `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests`: passed (`31 tests`)
- `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
- `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`152 tests`)

### 2026-04-22 (Round AT): Plot reference guides as typed advanced overlays

- Scope:
  - Added typed Plot reference-guide payloads in:
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
    so `reference_line` and `reference_band` now travel through the same explicit schema path as other Plot render options.
  - Added normalized reference-guide rendering in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/reference_guides.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/render_service.py`
    so preview/export/project restore all apply the same line/band overlay semantics, including log-axis positive-value validation.
  - Wired the typed payloads through sidecar/project persistence in:
    - `/Users/dongxutian/Documents/codegod/app/sidecar/render_support.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
    - `/Users/dongxutian/Documents/codegod/src/data_studio/comparison.py`
  - Extended Plot macOS state and inspector wiring in:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSession.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    so `Advanced Plot` now edits line/band overlays through durable `render_options` instead of ad hoc local view state.
  - Updated regression coverage and fixtures in:
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
    - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
  - Refreshed `/Users/dongxutian/Documents/codegod/README.md` and `/Users/dongxutian/Documents/codegod/AGENTS.md` so `Advanced Plot` docs now include the typed reference-guide path.
- User-visible impact:
  - Plot inspector `Advanced Plot` now includes a `Reference Guides` disclosure with `Line` and `Band` controls.
  - Reference guides render in preview/export and are restored from saved `.sciplotgod` projects together with the rest of Plot render options.
  - Fit remains curve-only, but reference guides are available whenever Plot has an imported source and resolved template.
  - Non-positive line/band values are rejected on log axes before rendering instead of silently drawing invalid overlays.
- Risks:
  - Reference guides now live inside durable `render_options`; if a future caller stores guide state outside this typed path, preview/export/project restore can drift.
  - Guides intentionally reuse current palette/style/theme semantics and introduce no new styling constants; future per-guide styling must not be added as frontend-local knobs.
  - Log-axis validation only enforces positive values in this round; any future clipping or coercion behavior should be explicit and shared, not silently improvised by one caller.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/src/rendering/reference_guides.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_service.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/models.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/render_support.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
  - `/Users/dongxutian/Documents/codegod/src/data_studio/comparison.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSession.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
  - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
  - `/Users/dongxutian/Documents/codegod/README.md`
  - `/Users/dongxutian/Documents/codegod/AGENTS.md`
- Decision:
  - First-principles motivation: after fit overlay productization, the next DataGraph-style capability should be another durable refinement control that improves plotting power without introducing a free-form advanced-layer state machine.
  - Chose typed `reference_line` / `reference_band` overlays over a generic command stack:
    - accepted because they reuse the current render pipeline, save/open schema, and inspector model with low migration risk
    - rejected a generic advanced-layer stack in this round because it would widen schema/UI complexity before there is a proven bounded tool set
  - Boundary:
    - no `src/plot_contract.json` changes
    - no new style/theme/axis constants
    - no drift to frozen `nature` fonts, line widths, spacing, or export metrics
    - fit remains shared through `fit_options`, while guides remain shared through `render_options`
- Troubleshooting note:
  - When testing log-axis reference-guide validation, use fixtures whose underlying axis data is already strictly positive.
  - Otherwise core dataset log-axis validation fires first and masks the intended guide-validation assertion.
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 36 source files`)
  - `.venv/bin/python -m pytest tests/test_plot_project_routes.py tests/test_rendering_services.py`: passed (`69 passed, 5 warnings`)
  - `.venv/bin/python -m pytest tests`: passed (`193 passed, 5 warnings`)
- `.venv/bin/python scripts/smoke_check.py`: passed
- `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests`: passed (`32 tests`)
- `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
- `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`153 tests`)

### 2026-04-22 (Round AU): Style-led visual defaults, typed text annotations, and unit superscript recovery

- Scope:
  - Extended the plotting contract in:
    - `/Users/dongxutian/Documents/codegod/src/plot_contract.json`
    - `/Users/dongxutian/Documents/codegod/src/plot_contract.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_meta.py`
    so every public style now declares `recommended_palette_preset` and `recommended_visual_theme_id`, and `/meta` plus `/plot-contract` expose those style-level recommendations as first-class data.
  - Strengthened soft visual-theme differentiation in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/themes.py`
    so `nature` keeps a plain white publication surface, while `editorial`, `presentation`, and `poster` now present visibly different background/grid/legend moods without touching frozen `nature` hard metrics.
  - Updated backend render-option resolution in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
    so an explicit style change now seeds that style’s recommended palette/theme pair when palette/theme were not explicitly overridden.
  - Reworked Plot macOS style semantics in:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSession.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    so the inspector now treats style as the primary visual direction, applies the style-recommended palette/background on selection, and still preserves later independent palette/background edits.
  - Added typed Plot text-annotation overlays in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/text_annotations.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/models.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/render_service.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/render_support.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
    so `render_options.text_annotations` is now the single durable path for preview, export, save project, and open project.
  - Restored shared unit superscript formatting in:
    - `/Users/dongxutian/Documents/codegod/src/text_normalization.py`
    so unit-like inputs such as `kJ/m2` and `J g-1 K-1` once again normalize to mathtext exponent labels before plotting.
  - Updated regression coverage and fixtures in:
    - `/Users/dongxutian/Documents/codegod/tests/test_plot_contract.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_plotting.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_sidecar_schema_contract.py`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/DataStudioSessionTests.swift`
  - Refreshed:
    - `/Users/dongxutian/Documents/codegod/README.md`
    - `/Users/dongxutian/Documents/codegod/AGENTS.md`
    - `/Users/dongxutian/Documents/codegod/docs/plot_contract.md`
    so the shipped behavior, contract docs, and handoff guidance all match.
- User-visible impact:
  - Plot style selection now has a clearer product meaning: `nature` lands on a colorblind-safe palette with a plain white background, while `editorial`, `presentation`, and `poster` switch to visibly different visual moods instead of feeling interchangeable.
  - Palette and background remain independently editable after style selection, but changing style now gives a coherent recommended starting point instead of leaving users with three unrelated knobs.
  - Plot `Advanced Plot` now includes durable `Text Annotations`, so users can place figure notes that survive preview refreshes, export, and `.sciplotgod` save/open.
  - Axis labels once again render unit exponents as superscripts for common spreadsheet inputs such as `kJ/m2`.
- Risks:
  - Style-level recommendations now exist alongside template `default_options`; if future contract edits change one without the other, style selection and template reset semantics can drift.
  - Visual themes are still intentionally soft-only. Any future attempt to make a theme also change font size, stroke width, spacing, axis frame, or export metrics would violate the current contract model.
  - `text_annotations` intentionally ships without a second style system. If later rounds add per-annotation typography/color controls, they must be added through the same typed payload and shared renderer rather than local SwiftUI-only state.
  - Generic unit exponent recovery uses a unit-shaped heuristic; if callers start feeding free-form prose into `normalize_unit`, non-unit text could be over-formatted.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/src/plot_contract.json`
  - `/Users/dongxutian/Documents/codegod/src/plot_contract.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/themes.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/text_annotations.py`
  - `/Users/dongxutian/Documents/codegod/src/text_normalization.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_meta.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/render_support.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSession.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/tests/test_plotting.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
  - `/Users/dongxutian/Documents/codegod/README.md`
  - `/Users/dongxutian/Documents/codegod/AGENTS.md`
- Decision:
  - First-principles motivation: DataGraph’s useful lesson here is not its exact UI, but that choosing a plotting “mode” should immediately put the figure in a coherent visual regime and that advanced refinements should be durable layers, not transient inspector state. Our product still keeps style, palette, and background independently editable, but the style control now owns the initial recommendation instead of acting like a cosmetic label.
  - Chose style-led recommendations with independent overrides over fully coupling the three controls:
    - accepted because it gives the user a clear visual jump when switching style while preserving the repo’s explicit requirement that palette/theme remain separately editable
    - rejected hard-coupled preset bundles because they would erase the independent-control model the product already committed to
  - Chose typed `text_annotations` overlays over a generic annotation command stack:
    - accepted because it keeps preview/export/project persistence on one explicit schema path and matches the bounded-advanced-tool approach used for fit and reference guides
    - rejected a free-form command/recipe layer in this round because it would widen schema/UI complexity before we had shipped the next concrete advanced capability
  - Boundary:
    - `nature` hard metrics remain frozen
    - style controls only seed palette/theme recommendations; later user overrides still win
    - text annotations currently cover placement and visibility only, not a second typography/styling subsystem
    - unit superscript repair is limited to shared label normalization and does not introduce frontend-local formatting fallbacks
- Troubleshooting note:
  - Swift payload decoding with `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase` does not reliably map new snake-case fields that end in `..._id` onto Swift properties spelled with a trailing `ID`.
  - The concrete fix for this round was to add explicit `CodingKeys` in `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift` and map `recommendedVisualThemeID` to `recommendedVisualThemeId`; otherwise `/meta` decoding fails even when the JSON payload is correct.
- Validation (executed):
  - `.venv/bin/python scripts/generate_plot_contract_docs.py`: passed
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 37 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`198 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`155 tests`)

### 2026-04-22 (Round AV): DataGraph-inspired extra axes with durable conversion semantics

- Scope:
  - Extended the plotting contract in:
    - `/Users/dongxutian/Documents/codegod/src/plot_contract.json`
    - `/Users/dongxutian/Documents/codegod/src/plot_contract.py`
    - `/Users/dongxutian/Documents/codegod/docs/plot_contract.md`
    so numeric public templates now explicitly advertise `extra_x_axis` / `extra_y_axis` as editable options through the same contract surface consumed by sidecar and macOS.
  - Added typed extra-axis normalization and rendering in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/extra_axes.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/models.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/render_service.py`
    so a figure can carry one extra X axis and one extra Y axis with `data_value -> display_value` conversion, optional label/unit text, and support for both linear and log parent axes.
  - Wired sidecar schema, preview/export, and project persistence through:
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/render_support.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
    so `render_options.extra_x_axis` and `render_options.extra_y_axis` are now durable request/project fields instead of view-local state.
  - Extended macOS render payloads and Plot session plumbing in:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    so Plot inspector now exposes `Extra Axes` editing under `Axis -> Advanced`, with availability/help driven by contract editable options and with save/open/undo/redo semantics preserved.
  - Hardened regression coverage in:
    - `/Users/dongxutian/Documents/codegod/tests/test_plot_contract.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
    - `/Users/dongxutian/Documents/codegod/scripts/smoke_check.py`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
    and refreshed:
    - `/Users/dongxutian/Documents/codegod/README.md`
    - `/Users/dongxutian/Documents/codegod/AGENTS.md`
    so docs, smoke guardrails, project round-trip tests, and macOS schema decoding all reflect the new advanced capability.
- User-visible impact:
  - Plot inspector `Advanced Plot` now includes durable `Extra Axes`, so users can add a converted top/bottom X axis and/or a left/right Y axis without leaving the existing quick-plot workflow.
  - Secondary-axis edits survive preview refreshes, export, and `.sciplotgod` save/open because they ride the same typed render-options path as fit, guides, and annotations.
  - Converted secondary axes also work when the parent X axis is log-scaled.
  - `Split Axis` is still not shipped; this round intentionally stops at DataGraph-style secondary axes rather than introducing multi-panel split/join layout semantics.
- Risks:
  - Current conversion semantics are scale-only (`display = data * ratio`). If a future use case needs affine or nonlinear transforms, this payload will need a versioned extension instead of ad hoc frontend math.
  - Contract exposure is intentionally limited to numeric templates. If more templates should support extra axes later, update the same contract editable-option path and the same macOS availability seam instead of adding local exceptions.
  - Matplotlib secondary axes are attached as `child_axes`, not extra entries in `figure.axes`; future tests and QA helpers must not assume otherwise.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/src/plot_contract.json`
  - `/Users/dongxutian/Documents/codegod/src/rendering/extra_axes.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_service.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
  - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
  - `/Users/dongxutian/Documents/codegod/scripts/smoke_check.py`
  - `/Users/dongxutian/Documents/codegod/README.md`
  - `/Users/dongxutian/Documents/codegod/AGENTS.md`
- Decision:
  - First-principles motivation: among DataGraph’s advanced plotting ideas, `Extra Axis` is the highest-value feature that fits our existing one-figure quick-plot architecture. It materially improves refinement power without forcing us to redesign layout, template ownership, or export geometry.
  - Chose typed `extra_x_axis` / `extra_y_axis` payloads over a generic advanced-command stack:
    - accepted because it keeps preview/export/project persistence on one explicit schema path and matches the bounded-advanced-tool approach already established by fit, reference guides, and text annotations
    - rejected a free-form recipe layer in this round because it would widen UI/schema complexity before we had shipped the next concrete plotting capability
  - Chose DataGraph-style secondary axes over `Split Axis` for this round:
    - accepted because secondary axes map cleanly onto one existing figure, one axis frame, and one export surface
    - rejected `Split Axis` because it would require multi-axis layout partitioning, join/split semantics, gap controls, and per-series axis ownership that the current Plot pipeline does not model
  - Boundary:
    - one extra X axis and one extra Y axis per figure
    - conversion is scale-only, not arbitrary formula evaluation
    - no change to frozen `nature` fonts, line widths, spacing, axis frame, or export metrics
    - no split-axis or multi-figure advanced layout in this round
- Troubleshooting note:
  - Matplotlib `secondary_xaxis` / `secondary_yaxis` do not append ordinary axes into `Figure.axes`; they materialize as `SecondaryAxis` children under the primary axis’s `child_axes`.
  - The concrete test/smoke fix for this round was to assert against `figure.axes[0].child_axes` and collect labels from primary plus child axes, otherwise the overlay renders correctly but regression checks still fail.
  - Swift-side render option decoding also needed an explicit defaulting path in `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`.
  - Without `decodeIfPresent(... ) ?? default` in `RenderOptionsPayload.init(from:)`, schema tests that intentionally send partial snake-case `options` payloads fail on omitted legacy fields such as `reverse_x` even though the new extra-axis fields are correct.
- Validation (executed):
  - `.venv/bin/python scripts/generate_plot_contract_docs.py`: passed
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 38 source files`)
  - `.venv/bin/python -m pytest tests/test_plot_contract.py tests/test_sidecar_schema_contract.py tests/test_plot_project_routes.py tests/test_rendering_services.py`: passed (`82 passed, 5 warnings`)
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests -only-testing:SciPlotGodMacTests/SchemaDecodingTests`: passed (`41 tests`)
  - `.venv/bin/python -m pytest tests`: passed (`202 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`157 tests`)

### 2026-04-22 (Round AW): DataGraph-inspired double-Y series ownership on top of typed extra axes

- Scope:
  - Extended typed extra-axis payload normalization in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/extra_axes.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
    so `extra_x_axis / extra_y_axis` now carry `binding_mode` plus `series_ids`, with `extra_x_axis` explicitly pinned to `conversion` and `extra_y_axis` allowed to express DataGraph-style double-Y series ownership.
  - Implemented secondary-Y series ownership in the curve renderer in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/render_curve.py`
    so `curve`, `point_line`, and `scatter` can move a selected subset of series onto an independent left/right secondary Y axis instead of only creating a scaled conversion axis.
  - Kept preview/export/project persistence on the same durable path through:
    - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    so double-Y selection survives preview refresh, export, save/open project, and template sanitization without adding a GUI-local advanced-plot state machine.
  - Routed fit overlay onto the correct physical axis by extending the shared curve-fit overlay path in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/render_curve.py`
    so a series assigned to the secondary Y axis receives its fit line on that same axis instead of on the primary axis.
  - Hardened regressions and smoke coverage in:
    - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
    - `/Users/dongxutian/Documents/codegod/scripts/smoke_check.py`
    and refreshed:
    - `/Users/dongxutian/Documents/codegod/README.md`
    - `/Users/dongxutian/Documents/codegod/AGENTS.md`
    so the new DataGraph-inspired capability is covered across Python rendering, project round-trip, Swift decoding, Plot session persistence, and public docs.
- User-visible impact:
  - Plot inspector `Axis -> Advanced -> Extra Axes` now lets users switch `extra y axis` between `Conversion` and `Double Y`.
  - In `Double Y`, users can select which series move onto the secondary Y axis for `curve`, `point_line`, and `scatter`, choose left/right placement, and keep that state through preview/export and `.sciplotgod` save/open.
  - Fit overlays now follow the assigned Y axis, so the visual analysis layer stays numerically and visually aligned with the actual series axis ownership.
  - `extra x axis` remains a conversion-only axis; this round does not expose split-axis layout, matrix split/join, or free-form command replay.
- Risks:
  - Secondary-Y routing currently rebuilds the moved series as new matplotlib artists after the primary figure is rendered, so future curve-only embellishments that attach extra per-series artists must update the same rebinding seam or they will stay on the primary axis.
  - `Double Y` is intentionally bounded to `curve / point_line / scatter`; `area_curve`, `step_line`, `stacked_*`, `heatmap`, and other templates still only support conversion-style extra axes.
  - `reference line / band` and `text annotations` still target the primary axis semantics from the existing typed overlay path; they are not yet axis-addressable overlays.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/src/rendering/extra_axes.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_curve.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
  - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
  - `/Users/dongxutian/Documents/codegod/scripts/smoke_check.py`
  - `/Users/dongxutian/Documents/codegod/README.md`
  - `/Users/dongxutian/Documents/codegod/AGENTS.md`
- Decision:
  - First-principles motivation: DataGraph’s biggest next-step lesson for our product was not full `Split Axis` layout, but the much more common and immediately useful ability to give different series independent Y-axis ownership on one figure. That increases analytical range without forcing a redesign of template selection, export geometry, or the single-figure quick-plot workflow that is already a product strength here.
  - Chose typed `binding_mode=series_assignment` on `extra_y_axis` over introducing a new advanced-plot command family:
    - accepted because it extends an already durable request/project field and keeps preview/export/save-open behavior on one schema path
    - rejected a new standalone “axis assignment” subsystem because it would duplicate state with `extra_y_axis` and reopen the exact front-end/local-logic drift we have been removing
  - Chose double-Y series ownership before `Split Axis`:
    - accepted because it captures the most valuable DataGraph refinement move while staying inside one axis frame and one figure export surface
    - rejected full split/join layout because it would require per-command axis ownership, panel partitioning, gap controls, and new persistence semantics that the current Plot pipeline still does not model
  - Boundary:
    - `extra_x_axis` remains conversion-only
    - `extra_y_axis.binding_mode=series_assignment` is only valid on `curve`, `point_line`, and `scatter`
    - at least one series must remain on the primary axis; selecting all series falls back to the existing single-axis render path
    - `nature` metrics remain frozen
- Troubleshooting note:
  - Do not run `xcodebuild ... build` and `xcodebuild ... test` in parallel against the same `-derivedDataPath`.
  - The concrete failure here was `unable to attach DB ... build.db: database is locked`; the fix was simply to rerun `test` after `build` finished instead of debugging code that was already correct.
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 38 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`206 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`157 tests`)
  - `git diff --check`: passed

### 2026-04-22 (Round AX): DataGraph-inspired stacked guides and callout annotations while preserving recommendation-led workflow

- Scope:
  - Reworked advanced plot overlays into a durable typed layer in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/reference_guides.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/text_annotations.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/advanced_plot_axes.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/extra_axes.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/render_curve.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/render_service.py`
    so Plot now supports stacked DataGraph-style `line / region` guides, note/callout annotations with connectors, and secondary-axis-aware placement without introducing a second recommendation system.
  - Normalized the sidecar schema and project path in:
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/render_support.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
    - `/Users/dongxutian/Documents/codegod/src/data_studio/comparison.py`
    so `reference_guides` and richer `text_annotations` travel through preview, export, Data Studio compare, and `.sciplotgod` save/open on one typed payload.
  - Updated macOS consumers in:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    so Plot inspector now exposes stacked guide editing plus `note / callout` creation while keeping template recommendation and quick-plot flow as the primary workflow.
  - Refreshed regressions and docs in:
    - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
    - `/Users/dongxutian/Documents/codegod/README.md`
    - `/Users/dongxutian/Documents/codegod/AGENTS.md`
    and corrected the malformed `SchemaDecodingTests` fixture that had made the full macOS suite look hung even though the product code path was correct.
- User-visible impact:
  - Plot inspector `Advanced Plot` now supports multiple guides instead of a single line/band toggle.
  - Each guide can be a `Line` or `Region`, can target `x`, `primary y`, or `secondary y`, and persists through preview/export/project reopen.
  - Text annotations now support both plain notes and DataGraph-style callouts with optional connectors and secondary-Y-aware placement.
  - Template recommendation, recommended defaults, and quick-plot dominance stay unchanged; advanced overlays remain a refinement layer rather than becoming the primary authoring model.
- Risks:
  - Conversion-style secondary Y guides are rendered onto the primary matplotlib axis after value conversion because `SecondaryAxis` does not support `axhline` / `axhspan`; future overlay code must preserve that seam.
  - This round still does not introduce split-axis layout, generic command replay, or a second GUI-local recommendation engine.
  - The new advanced layer is intentionally Plot-first; further Data Studio or Composer adoption should reuse the same typed overlay path instead of forking semantics.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/src/rendering/advanced_plot_axes.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/reference_guides.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/text_annotations.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/extra_axes.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_curve.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_service.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/render_support.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
  - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
- Decision:
  - First-principles motivation: the most useful DataGraph borrowing for this product was not a full recipe engine, but a durable stack of advanced refinement layers that can sit underneath our stronger recommendation-led quick-plot workflow.
  - Chose typed stacked overlays over a generic advanced-command interpreter:
    - accepted because it preserves one explicit render/project schema path and keeps backend truth in Python/sidecar rather than recreating command semantics in Swift
    - rejected a free-form recipe interpreter in this round because it would reduce the current product’s recommendation authority and widen persistence/UI complexity too early
  - Chose to keep recommendation dominance explicit:
    - template selection, default style/palette/theme, and quick-plot remain recommendation-first
    - advanced guides/callouts are opt-in refinement tools after template choice, not a replacement workflow
- Troubleshooting note:
  - A malformed JSON fixture in `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift` closed `text_annotations` with `}` instead of `]`.
  - The observable symptom was full `xcodebuild ... test` appearing to hang inside the host app after `SchemaDecodingTests`.
  - The durable debugging path was:
    - narrow the scope with `-only-testing:SciPlotGodMacTests/SchemaDecodingTests/testDecodeRenderRequestWithExtraAxes`
    - temporarily print the decode error instead of letting XCTest symbolicate it
    - fix the fixture and rerun the focused case before returning to the full suite
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 39 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`207 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/SchemaDecodingTests/testDecodeRenderRequestWithExtraAxes`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`157 tests`)

### 2026-04-23 (Round AY): DataGraph-inspired broken-axis overlays inside the recommendation-first Plot pipeline

- Scope:
  - Added typed broken-axis payloads in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/models.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/axis_breaks.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/render_service.py`
    so Plot now has durable `x_axis_breaks / y_axis_breaks` render options instead of view-local state or ad hoc matplotlib edits.
  - Extended contract, sidecar schema, and project round-trip in:
    - `/Users/dongxutian/Documents/codegod/src/plot_contract.json`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/render_support.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
    so preview, export, and `.sciplotgod` save/open all consume the same broken-axis payload and sanitization path.
  - Reused the same broken-axis coordinate transform inside advanced overlays in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/reference_guides.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/text_annotations.py`
    so guides, bands, notes, and callouts automatically skip hidden spans or remap into compressed visible space instead of drifting out of alignment.
  - Added macOS durable editing and sanitization in:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    so `Axis -> Advanced -> Broken Axes` edits survive preview refresh, export, save/open project, and undo/redo without introducing a second frontend-only state machine.
  - Hardened coverage and public docs in:
    - `/Users/dongxutian/Documents/codegod/tests/test_plot_contract.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
    - `/Users/dongxutian/Documents/codegod/scripts/smoke_check.py`
    - `/Users/dongxutian/Documents/codegod/README.md`
    - `/Users/dongxutian/Documents/codegod/AGENTS.md`
    so the new capability is covered across contract surface, rendering, project persistence, Swift decoding, session sanitization, smoke guardrails, and handoff docs.
- User-visible impact:
  - Plot inspector `Axis -> Advanced` now supports durable `Broken Axes` on selected numeric templates (`curve`, `point_line`, `step_line`, `scatter`, `bubble_scatter`, `scatter_fit`).
  - Broken-axis edits survive preview refreshes, export, and `.sciplotgod` save/open because they travel through the same typed render-options payload as fit overlays, extra axes, guides, and annotations.
  - Reference guides, guide bands, notes, and callouts now stay aligned with broken axes instead of rendering into hidden regions.
  - Recommendation-first template selection, style/theme/palette recommendations, and frozen `nature` metrics remain unchanged; broken axes ship strictly as an advanced refinement layer.
- Risks:
  - Current broken-axis semantics are compressed overlays inside one physical axis frame, not true split/join multi-panel layout. If a future requirement needs independent panel bounds, joined legends, or per-panel series routing, that should be a new capability instead of stretching this payload ad hoc.
  - Broken axes are intentionally limited to linear axes and cannot coexist with enabled extra axes in this release. If later rounds need DataGraph-style mixed extra-axis plus broken-axis authoring, the normalization and inspector availability logic must be versioned together.
  - Artist remapping currently covers standard line/scatter/text plus our existing guide/annotation overlay paths. Future renderers that add new data-space artists must opt into the same axis-break transform seam or they will render against the uncompressed coordinate space.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/src/rendering/axis_breaks.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_service.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/reference_guides.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/text_annotations.py`
  - `/Users/dongxutian/Documents/codegod/src/plot_contract.json`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionRestore.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
  - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
  - `/Users/dongxutian/Documents/codegod/scripts/smoke_check.py`
  - `/Users/dongxutian/Documents/codegod/README.md`
  - `/Users/dongxutian/Documents/codegod/AGENTS.md`
- Decision:
  - First-principles motivation: among DataGraph’s remaining advanced plot ideas, broken axes add meaningful refinement power while still fitting our strongest product constraint, namely one recommendation-led quick-plot flow that keeps the main authoring path simple and opinionated.
  - Chose typed compressed broken-axis overlays over full split/join layout:
    - accepted because it keeps preview/export/project persistence on one explicit payload path and preserves the existing one-figure export geometry
    - rejected multi-panel split layout in this round because it would require new panel ownership, legend/join semantics, export geometry rules, and likely a second UI model
  - Chose to make guides and annotations reuse the same transform:
    - accepted because otherwise broken axes would immediately desynchronize the rest of the advanced plot stack
    - rejected leaving overlay paths untouched because “axis breaks work but annotation/guide placement is wrong” would be a visible regression against the durability standard we already established
  - Boundary:
    - only linear axes
    - no coexistence with enabled extra axes
    - no change to frozen `nature` typography, line width, spacing, axis frame, or export metrics
    - no new recommendation engine or template-selection path in macOS
- Troubleshooting note:
  - `scripts/smoke_check.py` can fail even when rendering is correct if a validation payload includes `numpy.bool_` or other numpy scalar types and the smoke report is written directly with `json.dumps(...)`.
  - The concrete symptom this round was every PDF rendering successfully, followed by `TypeError: Object of type bool is not JSON serializable` while writing `/Users/dongxutian/Documents/codegod/figures/debug_outputs/smoke_report.json`.
  - The durable fix was to coerce validation `passed` values to native `bool` and add a small `_json_safe(...)` normalization step before report serialization, rather than weakening the new broken-axis smoke coverage.
  - Swift build also needed one access-control correction: `PlotAxisSelection` could no longer stay `private` once the new broken-axis mutators in `PlotSessionImportInspect.swift` reused the same axis enum across files.
- Validation (executed):
  - `.venv/bin/python scripts/generate_plot_contract_docs.py`: passed
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 40 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`212 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`158 tests`)
  - `git diff --check`: passed
  - `git diff --check`: passed

### 2026-04-24 (Round AZ): DataGraph-inspired shape annotations as durable region/bracket overlays

- Scope:
  - Added a new durable advanced-plot overlay layer in:
    - `/Users/dongxutian/Documents/codegod/src/rendering/shape_annotations.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/models.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/render_service.py`
    so Plot now supports typed `shape_annotations` instead of ad hoc local drawing state.
  - Wired sidecar schema and project round-trip in:
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/render_support.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
    so `shape_annotations` flow through preview, export, and `.sciplotgod` save/open on the same typed render-options path as fit overlays, extra axes, broken axes, guides, and text annotations.
  - Updated macOS durable editing in:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    so Plot inspector `Advanced Plot` now exposes `Shape Annotations` as durable UI state rather than view-local overlays.
  - Extended regression coverage and docs in:
    - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
    - `/Users/dongxutian/Documents/codegod/scripts/smoke_check.py`
    - `/Users/dongxutian/Documents/codegod/README.md`
    - `/Users/dongxutian/Documents/codegod/AGENTS.md`
    so the new DataGraph-inspired capability is covered across Python rendering, Swift decoding, project persistence, smoke guardrails, and handoff docs.
- User-visible impact:
  - Plot inspector `Advanced Plot` now includes `Shape Annotations` with `Rectangle`, `Ellipse`, and `Bracket`.
  - These overlays survive preview refreshes, export, undo/redo, and `.sciplotgod` save/open because they travel through durable `render_options.shape_annotations`.
  - Shape annotations reuse the same broken-axis and split-panel coordinate mapping as existing guides/annotations, and can target `primary y` or `secondary y`.
  - Recommendation-first template selection, style/theme/palette defaults, and frozen `nature` metrics remain unchanged; shape annotations ship strictly as an advanced refinement layer.
- Risks:
  - This is intentionally not a generic free-form command engine. The current payload only supports `rectangle / ellipse / bracket`, one optional label, and bounded axis-aware geometry.
  - Shape annotations are Plot-only in this round. If Data Studio or Composer later need similar overlays, they should reuse this typed payload instead of forking a second overlay model.
  - Brackets are axis-aligned overlays, not arbitrary rotated or bezier callouts. Future requests for richer authoring should extend the same typed layer carefully rather than bypassing it in Swift.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/src/rendering/shape_annotations.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/models.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/options.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_service.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/render_support.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/project_bundle.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/tests/test_rendering_services.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
  - `/Users/dongxutian/Documents/codegod/scripts/smoke_check.py`
  - `/Users/dongxutian/Documents/codegod/README.md`
  - `/Users/dongxutian/Documents/codegod/AGENTS.md`
- Decision:
  - First-principles motivation: DataGraph’s useful lesson here was not “copy the whole app,” but to make visual refinement tools durable, typed, and replayable underneath the primary quick-plot workflow. `Region` and `Bracket` were the highest-value next borrow that fit our current architecture.
  - Chose typed `shape_annotations` over a generic advanced-command interpreter:
    - accepted because it keeps preview/export/project persistence on one explicit schema path and preserves backend ownership of geometry semantics
    - rejected a free-form command stack because it would immediately weaken recommendation authority, expand persistence complexity, and reopen GUI-local business logic drift
  - Chose to reuse the existing broken-axis and secondary-Y mapping seams:
    - accepted because it keeps all advanced overlays aligned when axis transforms are active
    - rejected view-local drawing or duplicate transform helpers because that would cause the same figure state to render differently across preview/export/project reopen
  - Boundary:
    - no change to frozen `nature` typography, line width, spacing, axis frame, or export metrics
    - no second recommendation engine
    - no new front-end-local geometry constants
- Troubleshooting note:
  - When Swift payload types are decoded with `.convertFromSnakeCase`, hand-written snake_case `CodingKeys` can silently defeat the decoder and make values fall back to defaults.
  - The concrete symptom here was `AxisBreakPayload.displayMode` decoding to `"compress"` even when the JSON fixture said `"split"`, which made `SchemaDecodingTests` look like a rendering regression instead of a key-mapping bug.
  - The durable fix was to keep `CodingKeys` in camelCase for `AxisBreakPayload` and `ShapeAnnotationPayload`, then verify with focused `SchemaDecodingTests` before rerunning the full suite.
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/SchemaDecodingTests -only-testing:SciPlotGodMacTests/PlotSessionTests`: passed (`42 tests`)
  - `.venv/bin/python -m pytest tests/test_rendering_services.py tests/test_plot_project_routes.py -q`: passed
  - `.venv/bin/python scripts/clean_repo.py`: passed
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 41 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`216 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`158 tests`)

## 2026-04-24 - DataGraph-Inspired Cleanup Refactor

- Scope:
  - Cleaned generated artifacts with `/Users/dongxutian/Documents/codegod/scripts/clean_repo.py` before regression, reclaiming about `230.2 MB` from caches and derived data without touching source.
  - Consolidated Plot preview/export request rendering through a single normalized `RenderOptions` path:
    - `/Users/dongxutian/Documents/codegod/app/sidecar/render_support.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/render_service.py`
    - `/Users/dongxutian/Documents/codegod/src/core/application/render.py`
  - Added `/Users/dongxutian/Documents/codegod/src/rendering/overlay_coordinates.py` as the shared coordinate helper for broken-axis panels, interval clipping, mapped anchors, pixel offsets, and secondary-Y conversion scale.
  - Updated reference guide, text annotation, and shape annotation overlays to reuse the shared coordinate helper instead of carrying duplicate mapping snippets:
    - `/Users/dongxutian/Documents/codegod/src/rendering/reference_guides.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/text_annotations.py`
    - `/Users/dongxutian/Documents/codegod/src/rendering/shape_annotations.py`
  - Split Plot shape annotation controls out of the oversized inspector into `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotShapeAnnotationInspectorView.swift`, and added it to the macOS Xcode target.
  - Updated `/Users/dongxutian/Documents/codegod/tests/test_sidecar_render.py` so the preview cache guard patches the new `build_rendered_plots_from_options` route seam instead of the removed route-local old render symbol.
- User-visible impact:
  - No intentional UI or plotting behavior change.
  - Shape annotation controls remain in `Advanced Plot -> Shape Annotations`; the same `PlotSession` durable state, undo/redo path, preview/export path, and project persistence semantics are preserved.
  - Preview/export normalized artifacts may now carry the normalized fit-options payload in the same render options object used for actual rendering.
- Performance and structure note:
  - Target: remove avoidable per-preview/per-export payload explosion and duplicate overlay normalization while keeping render output stable.
  - Protective coverage: route preview cache test, full rendering/project route pytest suite, `scripts/smoke_check.py`, and macOS Plot session tests.
  - This is a structural efficiency cleanup, not a benchmarked rendering-speed claim.
- Risks:
  - `build_rendered_plots_from_options` is now the lower-level render seam; any future sidecar render route should pass already-normalized `RenderOptions` through this path instead of re-expanding payload fields.
  - `overlay_coordinates.py` owns reusable geometry helpers only; overlay-specific drawing style, labels, and QA autofix markers remain in their respective modules.
  - The new Swift subview duplicates a small amount of inspector binding boilerplate to keep shape annotation ownership local. Further inspector cleanup should extract common binding helpers deliberately instead of adding another large all-purpose view.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/sidecar/render_support.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/server_utils.py`
  - `/Users/dongxutian/Documents/codegod/src/core/application/render.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/render_service.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/overlay_coordinates.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/reference_guides.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/text_annotations.py`
  - `/Users/dongxutian/Documents/codegod/src/rendering/shape_annotations.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotShapeAnnotationInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/SciPlotGod.xcodeproj/project.pbxproj`
  - `/Users/dongxutian/Documents/codegod/tests/test_sidecar_render.py`
- Decision Record:
  - Motivation: the current DataGraph-inspired overlay feature set was functionally in place, but the implementation was starting to thicken around repeated render-option normalization and repeated broken-axis coordinate math. The cleanup keeps the product model typed and contract-first while reducing future overlay/refinement debt.
  - Accepted: introduce `build_rendered_plots_from_options` as the low-level render entry once a request has been normalized; keep `build_rendered_plots` as the public compatibility entry for CLI, tests, smoke, and Data Studio callers that still pass keyword options.
  - Rejected: preserve route-local `build_rendered_plots` aliases just to satisfy old tests. The route test now patches the new route seam directly, so no dead compatibility symbol remains in the route module.
  - Accepted: centralize overlay coordinate helpers in Python rendering, where preview/export/project reopen already converge.
  - Rejected: moving geometry into Swift or adding a generic DataGraph command interpreter in this cleanup. That would create a second drawing semantics source and weaken the current typed payload boundary.
  - Boundaries: no change to frozen `nature` typography, line width, spacing, axis frame, or export metrics; no new public template/style/palette contract surface; no restored legacy sidecar route.
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed, reclaimed approx `230.2 MB`
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 42 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`216 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`158 tests`)
  - `git diff --check`: passed

## 2026-04-24 - Data Studio Import Template v2 With Rheology Fixtures

- Scope:
  - Rebuilt Data Studio user import templates as v2 no-code table mappings in:
    - `/Users/dongxutian/Documents/codegod/src/data_studio/models.py`
    - `/Users/dongxutian/Documents/codegod/src/data_studio/template_store.py`
    - `/Users/dongxutian/Documents/codegod/src/data_studio/import_templates_v2.py`
    - `/Users/dongxutian/Documents/codegod/src/data_studio/workbook_building.py`
  - Added segment-aware raw table preview in `/Users/dongxutian/Documents/codegod/src/rendering/source_table_preview.py` and wired `POST /source-table-preview` to accept encoding, delimiter, header/unit/data-start row, and segment parameters.
  - Removed the legacy `POST /data-studio/source-preview` route and added `POST /data-studio/template-preview` for unsaved draft parsing.
  - Updated sidecar request/response models, critical route compatibility checks, and macOS client models in:
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_data_studio.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_data_studio.py`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarClient.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsDataStudio.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarRuntime.swift`
  - Reworked the macOS staged import sheet in:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionImportTemplate.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioTemplateEditorViews.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioImportWorkflowViews.swift`
  - Added fixture copies for rheology and tensile samples under `/Users/dongxutian/Documents/codegod/tests/fixtures/data_studio_import_v2/`.
  - Added and updated backend/sidecar/macOS regression coverage, including route removal assertions, v2 save/load, template preview errors, rheology role defaults, all output shapes, unsupported compare recipes, and import wizard state tests.
- User-visible impact:
  - Data Studio import now previews metadata-heavy UTF-16 tab-delimited rheology files correctly instead of collapsing them into one column.
  - The create-template stage shows source segments, paged table rows, encoding/delimiter, and X/Y/metric role mapping before saving.
  - Rheology `Result` / `Interval data` blocks can be treated as one series source by default.
  - Saved v2 templates can output curve+metric workbooks, metric-only workbooks, or matrix/heatmap workbooks.
  - Builtin tensile behavior is preserved as the regression baseline.
  - Unsupported compare figure entries are disabled with reasons when a workbook lacks the required curve or metric shape.
- Risks:
  - v2 intentionally does not preserve the old user-template parser or the old source-preview candidate workflow. Existing user templates need to be recreated through the new mapper.
  - The first macOS UI pass covers segment selection and column role mapping; richer row-role editing can extend the same `source_format` / `segment_selectors` payload instead of adding another endpoint.
  - Matrix/heatmap output is supported at workbook-shape level, but downstream figure families should stay gated by explicit compare recipe support.
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/src/rendering/source_table_preview.py`
  - `/Users/dongxutian/Documents/codegod/src/data_studio/import_templates_v2.py`
  - `/Users/dongxutian/Documents/codegod/src/data_studio/models.py`
  - `/Users/dongxutian/Documents/codegod/src/data_studio/template_store.py`
  - `/Users/dongxutian/Documents/codegod/src/data_studio/service.py`
  - `/Users/dongxutian/Documents/codegod/src/data_studio/workbook_building.py`
  - `/Users/dongxutian/Documents/codegod/src/data_studio/comparison.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_data_studio.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_render.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_data_studio.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_render.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionImportTemplate.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioTemplateEditorViews.swift`
  - `/Users/dongxutian/Documents/codegod/tests/test_data_studio_import_templates_v2.py`
  - `/Users/dongxutian/Documents/codegod/tests/fixtures/data_studio_import_v2/`
- Decision Record:
  - Motivation: the broken behavior came from treating every CSV-like file as a simple table. The user-provided rheology files showed the actual first-principles requirement: import must first identify file encoding, delimiter, metadata rows, table segments, and column roles before applying a saved parser.
  - Accepted: make `/source-table-preview` the shared raw-table preview and extend it with source-format and segment controls.
  - Rejected: restoring `/data-studio/source-preview`, because that would create a second raw-preview route and keep the old candidate parser alive.
  - Accepted: add `/data-studio/template-preview` for draft templates so the wizard can validate real normalized output before saving.
  - Rejected: letting `build-workbook` consume arbitrary draft payloads, because saved template ids remain the durable workbook provenance boundary.
  - Accepted: model output shape explicitly as `curve_metrics`, `metric_table`, and `matrix_heatmap`.
  - Rejected: silently forcing unsupported workbooks through tensile-style compare recipes, because compare/export should disable unavailable figures with explicit reasons.
  - Boundaries: no second template manager in this round, no legacy user parser, no front-end-only parsing semantics, and no change to Plot style/theme/palette contract behavior.
- Troubleshooting note:
  - When an XCTest assertion fails inside the macOS app-hosted test process, Xcode can spend a long time symbolizing before printing the failure message.
  - Sampling the app process with `sample <pid> 2 -file /tmp/sciplot_sample.txt` quickly identified the exact failing Swift test line while the `xcodebuild` stream was silent.
  - The concrete failures this round were expected test drift from the new Data Studio template editor summary and snapshot fingerprint, not runtime deadlocks.
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed, reclaimed approx `290.2 MB`
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 43 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`225 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`158 tests`)

### 2026-04-24 (Round BA): Data Studio 新建模板“创建后没生效”修复闭环

- Scope:
  - Sidecar 新增模板推荐接口并接入既有 ingest 推荐链路：
    - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_data_studio.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_data_studio.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas.py`
    - `/Users/dongxutian/Documents/codegod/src/data_studio/service.py`
    - `/Users/dongxutian/Documents/codegod/src/data_studio/ingest.py`
  - 路由兼容门禁同步更新（sidecar + macOS runtime）：
    - `/Users/dongxutian/Documents/codegod/app/sidecar/server.py`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarRuntime.swift`
  - macOS Data Studio resolver 改为推荐驱动预选，不再硬编码默认 builtin：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionImportTemplate.swift`
  - 模板创建草稿补最小 `match_conditions`，避免“创建成功但后续无法命中推荐”。
  - 同步更新 client/model/mock/test 及 sidecar/macOS 回归：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarClient.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsDataStudio.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/MockSidecarClient.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/DataStudioSessionTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SidecarRuntimeTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/AppModelTests.swift`
    - `/Users/dongxutian/Documents/codegod/tests/test_sidecar_data_studio.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_sidecar_active_routes.py`
  - 文档契约同步：
    - `/Users/dongxutian/Documents/codegod/README.md`
    - `/Users/dongxutian/Documents/codegod/AGENTS.md`
- User-visible impact:
  - Data Studio 新建模板后，后续同类原始文件导入会进入推荐链路并可自动预选新模板，不再体感“保存了但没生效”。
  - 当没有可靠推荐时，resolver 明确要求手动选择模板并给出禁用原因，不再默认落到 `builtin/tensile`。
  - 推荐区展示真实推荐结果，且避免和“其他模板”重复显示。
- Risks:
  - 若模板草稿生成的最小 `match_conditions` 过弱，可能导致低置信度泛匹配；当前通过 `minimum_score` 与字段类型约束减小风险。
  - 导入时新增一次模板推荐请求，sidecar 异常时会回落到“手动选择模板”，不会再静默误选。
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionImportTemplate.swift`
  - `/Users/dongxutian/Documents/codegod/src/data_studio/ingest.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_data_studio.py`
  - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_data_studio.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarClient.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsDataStudio.swift`
- Validation (executed):
  - `.venv/bin/python scripts/clean_repo.py`: passed, reclaimed approx `234.0 MB`
  - `.venv/bin/python -m ruff check --fix app/sidecar/routes_data_studio.py tests/test_sidecar_data_studio.py`: passed (auto-fixed 2 import-order issues)
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed (`Success: no issues found in 43 source files`)
  - `.venv/bin/python -m pytest tests`: passed (`226 passed, 5 warnings`)
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed (`159 tests`)

### 2026-04-24 (Round BB): Data Studio 模板预览解码修复（`template_id` -> `templateID`）

- Scope:
  - 修复 macOS 端 `DataStudioTemplatePreviewResponse` 的字段解码映射，显式补 `CodingKeys`，确保 sidecar 返回 `template_id` 时可稳定解码：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsDataStudio.swift`
  - 增加回归测试，锁定 `template_id` payload 能正确落到 `templateID`：
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
  - 侧边车客户端 decode 失败提示补充 endpoint/path 语义，便于后续快速定位：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarClient.swift`
- User-visible impact:
  - Data Studio 导入向导里点击 `Save Template and Continue Import` 不再无效返回。
  - 左上角不再出现由该解码失败触发的 `unexpected response` 提示。
  - 现在会进入 `Save Data Studio Workbook` 保存面板并继续导入链路。
- Risks:
  - 本轮仅修复解码字段映射，不改变模板推荐/排序规则；若后端再次变更字段命名，仍需同步更新 Swift model 与解码测试。
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsDataStudio.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarClient.swift`
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/SchemaDecodingTests -only-testing:SciPlotGodMacTests/DataStudioSessionTests -only-testing:SciPlotGodMacTests/SidecarRuntimeTests -only-testing:SciPlotGodMacTests/AppModelTests`: passed (`79 tests`)

### 2026-04-24 (Round BC): Data Studio Resolver 增加模板改名/删除管理

- Scope:
  - 在 Data Studio `Resolve Parse Template` 导入 resolver sheet 增加 `Template Management` 区块，支持：
    - 模板名编辑 + `Rename`
    - `Delete`（二次确认 dialog）
  - 模板管理动作可用性改为显式 presentation 字段，并在 builtin / 未选择场景下禁用并解释原因：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionImportTemplate.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioImportWorkflowViews.swift`
  - 新增会话回归测试覆盖 resolver 可用性与 user template 改名/删除行为：
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/DataStudioSessionTests.swift`
- User-visible impact:
  - 现在不需要离开导入 resolver，就能直接对 user 模板改名和删除。
  - 删除动作会先弹确认；builtin 模板不会允许改名/删除，且会显示明确禁用原因。
- Risks:
  - 当前模板改名是按 `label` 更新；若后续引入额外命名约束（例如跨 family 唯一性策略变化），需要同步扩展前端提示文案。
  - 删除后当前选中模板会回落到列表中的下一个可用模板；如果策略需要“删除后强制手动重选”，需额外修改会话选择逻辑。
- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioImportWorkflowViews.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionImportTemplate.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionTypes.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/DataStudioSessionTests.swift`
- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/DataStudioSessionTests`: passed (`58 tests`)

### 2026-04-24 (Round BD): Data Studio `Curves` 默认仅曲线，勾选后启用对比结构

- Scope:
  - Data Studio v2 模板新增 `comparison_enabled` 字段，并贯穿 dataclass/store/service/sidecar schema+route：
    - `/Users/dongxutian/Documents/codegod/src/data_studio/models.py`
    - `/Users/dongxutian/Documents/codegod/src/data_studio/template_store.py`
    - `/Users/dongxutian/Documents/codegod/src/data_studio/service.py`
    - `/Users/dongxutian/Documents/codegod/src/data_studio/import_templates_v2.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/schemas_data_studio.py`
    - `/Users/dongxutian/Documents/codegod/app/sidecar/routes_data_studio.py`
  - `curve_metrics` 工作簿输出改为可切换：
    - `comparison_enabled=false`：只写 `All_Curves`
    - `comparison_enabled=true`：保持 representative + metrics compare 结构
    - 两种模式都不再写 `DataStudio_Metadata` sheet
  - 旧模板兼容：
    - 历史 payload 缺省 `comparison_enabled` 且 `output_kind=curve_metrics` 时默认按 `true` 读取。
  - macOS 模板创建 UI：
    - `Output` 文案改为 `Curves`
    - 新增 `Enable Comparison` 开关（默认关闭）
    - 仅开启后显示 metrics 选择，并在无 metric 时 `Save/Save and Continue` 禁用并解释
    - 新增按已选 Y 列逐项确认样品名输入框，默认值为源文件名（可编辑）
    - 模板请求显式发送 `comparison_enabled`
  - workbook import 偏好页修正：
    - 无 `Representative_Curve` 时优先回落到 `All_Curves`，避免再次导入时落到不存在 sheet。
  - 文档同步：
    - `/Users/dongxutian/Documents/codegod/AGENTS.md`
    - `/Users/dongxutian/Documents/codegod/README.md`

- User-visible impact:
  - Data Studio 创建 `Curves` 模板时，默认行为是“整理原始列直接用于画曲线”，不再默认进入 Tensile 风格指标/代表曲线链路。
  - 只有用户主动勾选 `Enable Comparison` 才生成 compare 所需 workbook 结构，且缺 metric 列会直接阻止保存并给原因。
  - 模板编辑页可逐项确认/修改曲线样品名；默认不再拼 segment 文案，直接使用源文件名。
  - 通过 v2 模板生成的 workbook 不再出现 `DataStudio_Metadata` sheet。
  - 仅曲线工作簿在 compare recipe 中继续以“禁用并解释”方式处理 metric/representative recipe。

- Risks:
  - 旧 `curve_metrics` 模板如果历史上没有 metric 绑定且未来被编辑为 `comparison_enabled=true`，会在模板校验阶段收到“缺 metric”错误（这是有意的 guardrail）。
  - `comparison_enabled=false` 的曲线工作簿不支持 representative/metric compare recipe；这是产品语义，不是回归。

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/src/data_studio/import_templates_v2.py`
  - `/Users/dongxutian/Documents/codegod/src/data_studio/template_store.py`
  - `/Users/dongxutian/Documents/codegod/src/data_studio/workbooks.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioTemplateEditorViews.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionImportTemplate.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsDataStudio.swift`

- Validation (executed):
  - `.venv/bin/python -m ruff check src/data_studio/import_templates_v2.py src/data_studio/service.py src/data_studio/workbooks.py app/sidecar/routes_data_studio.py app/sidecar/schemas_data_studio.py tests/test_data_studio_import_templates_v2.py tests/test_data_studio.py tests/test_sidecar_data_studio.py tests/test_sidecar_schema_contract.py`: passed
  - `.venv/bin/python -m pytest tests/test_data_studio_import_templates_v2.py tests/test_data_studio.py tests/test_sidecar_data_studio.py tests/test_sidecar_schema_contract.py`: passed (`44 passed, 5 warnings`)
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/DataStudioSessionTests -only-testing:SciPlotGodMacTests/SchemaDecodingTests -only-testing:SciPlotGodMacTests/SidecarRuntimeTests -only-testing:SciPlotGodMacTests/AppModelTests`: passed (`84 tests`)

### 2026-04-24 (Round BE): 无对比 Data Studio 导入自动切到 Plot

- Scope:
  - 在 Data Studio 导入链路（现有 workbook 导入 + raw build workbook）补自动分流：
    - comparison context 重建后，若没有任何 `supported` recipe，则自动调用既有 `openInPlotHandler`。
    - 打开对象使用当前 focused workbook，sheet 使用该 workbook 的 `preferredSheet`，template/options/fitOptions 由 Plot 侧常规 inspect/recommend 链路处理。
  - 具体代码：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionImportTemplate.swift`
  - 回归测试新增：
    - `testCurveOnlyWorkbookImportAutoOpensFocusedWorkbookInPlot`
    - `testCurveOnlyRawWorkbookBuildAutoOpensInPlot`
    - 文件：`/Users/dongxutian/Documents/codegod/app/macos/Tests/DataStudioSessionTests.swift`
  - 文档同步：
    - `/Users/dongxutian/Documents/codegod/AGENTS.md`
    - `/Users/dongxutian/Documents/codegod/README.md`

- User-visible impact:
  - 对于“无对比可做”的 Data Studio 结果（如 curve-only rheology workbook），导入完成后会自动切到 Plot，不再停在 Data Studio 无法继续绘图的状态。
  - 若 compare 可用（存在 supported recipe），保持当前 Data Studio compare 工作流不变。

- Risks:
  - 自动切换会复用现有 `Open in Plot` 行为；当 Plot 已有内容时，仍可能触发替换确认弹窗（符合当前全局策略）。
  - 触发条件依赖 comparison context 的 `supported` 标记；若后端未来改变 supported 语义，需要同步校准此分流条件。

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionImportTemplate.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/DataStudioSessionTests.swift`

- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/DataStudioSessionTests`: passed (`63 tests`)

### 2026-04-24 (Round BF): Runtime/Overlay 稳定性守门与阻断门禁脚本

- Scope:
  - Runtime 可观测性补强（保持现有产品语义）：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarRuntime.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppModel.swift`
  - Data Studio -> Plot 自动分流防回归测试补强（有 supported recipe 时禁止误切）：
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/DataStudioSessionTests.swift`
  - Plot Overlay 编辑流升级为统一“可选中 + 拖拽/微调（nudge）”：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSession.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotShapeAnnotationInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotOverlayTransformControls.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/SciPlotGod.xcodeproj/project.pbxproj`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
  - Runtime 失败可见性回归测试补强：
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SidecarRuntimeTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/AppModelTests.swift`
  - 阻断门禁落地（自动化矩阵 + 手工 smoke 清单）：
    - `/Users/dongxutian/Documents/codegod/scripts/blocking_gate.py`
    - `/Users/dongxutian/Documents/codegod/README.md`
    - `/Users/dongxutian/Documents/codegod/AGENTS.md`

- User-visible impact:
  - sidecar 启动/探针失败时，runtime 错误卡片会附带最近 runtime log tail，定位更直接，不再只有笼统失败提示。
  - Plot 的 `reference_guides / text_annotations / shape_annotations` 现在支持统一选中态与拖拽/箭头微调，且仍走同一 typed payload 保存/重开链路。
  - Data Studio 导入后在“有可用 compare recipe”的场景保持停留 Data Studio，不会被误切到 Plot。

- Risks:
  - Overlay 微调步长目前按坐标空间和控件默认值设定；极端数据尺度下可能需要后续再调节步长策略。
  - runtime log tail 直接拼入诊断详情，若未来日志量增大，可能需要再引入裁剪/格式策略。
  - `scripts/blocking_gate.py` 默认不强制手工 smoke；若团队希望强制，需统一改用 `--require-manual`。

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarRuntime.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppModel.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotShapeAnnotationInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/scripts/blocking_gate.py`

- Decision Record:
  - Why:
    - first-principles 动机是把“运行时阻断问题”定位成本降到最低，同时保证 Overlay 迭代继续沿单一 typed payload 真相源前进，不新增 GUI 本地语义分叉。
  - Rejected alternatives:
    - 只在失败时显示一句通用错误，不附 runtime 日志：被拒绝，因为重复排查时缺关键上下文。
    - 先做前端局部拖拽状态再异步映射回 payload：被拒绝，因为会产生第二套几何语义并破坏 save/open/export 一致性。
    - 继续依赖人工逐条执行验证命令：被拒绝，因为门禁不稳定、漏项概率高。
  - Boundaries:
    - 不引入 legacy route/fallback，不改变 `nature` 冻结指标，不在前端重建 style/palette/theme 默认值系统。
    - overlay 编辑仅复用 `render_options.reference_guides / text_annotations / shape_annotations` 现有链路。

- Validation (executed):
  - `.venv/bin/python scripts/blocking_gate.py`: passed（自动化矩阵全通过；脚本输出的手工 smoke 清单为 pending，未启用 `--require-manual`）
  - `.venv/bin/python scripts/clean_repo.py`: passed（reclaimed approx `295.7 MB`）
  - `.venv/bin/python -m ruff check app/sidecar make_plot.py src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering tests scripts/smoke_check.py`: passed
  - `.venv/bin/python -m mypy src/composer.py src/plot_contract.py src/data_loader.py src/tensile_replicates.py src/rendering`: passed（`Success: no issues found in 43 source files`）
  - `.venv/bin/python -m pytest tests`: passed（`230 passed, 5 warnings`）
  - `.venv/bin/python scripts/smoke_check.py`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed（`173 tests`）

### 2026-04-25 (Round BG): macOS GUI 一阶段原生化升级（统一 Quick Help + 去噪收敛）

- Scope:
  - 四工作台帮助入口统一为 app-level `Quick Help`：
    - 新增 `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/QuickHelpSheet.swift`
    - `AppModel` 改为统一持有 help sheet 状态（`isQuickHelpPresented` / `quickHelpWorkbench`），`showHelpForActiveWorkbench()` 打开统一 Quick Help：
      - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppModel.swift`
    - `RootSplitView` 统一挂载 Quick Help sheet：
      - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
    - 删除各 feature 的 `GuideSheet` 与对应 session guide 状态/方法：
      - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSession.swift`
      - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
      - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSession.swift`
      - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
      - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerSession.swift`
      - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerWorkbenchView.swift`
      - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleSession.swift`
      - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift`
  - 共享状态文案去噪与原生化收敛：
    - 新增短句化 copy 规则 `StatusCopy.short(...)`，统一作用于 `EmptyStateCard` / `ErrorStateCard` / `BusyStateCard` / `InspectorEmptyState`：
      - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/StateViews.swift`
    - 清理大块装饰背景：移除部分主区 `.quinary.opacity` 包裹，保留状态强调最小必要样式：
      - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift`
      - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - 状态文案压缩（状态 + 下一步）：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/Base64PreviewImageView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/PDFPreviewView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift`
  - 文档边界同步（帮助面板与去噪约束）：
    - `/Users/dongxutian/Documents/codegod/AGENTS.md`
    - `/Users/dongxutian/Documents/codegod/README.md`

- User-visible impact:
  - toolbar `Help` 现在在四个 workbench 都打开统一的 `Quick Help`（短提示、动作导向），不再弹出长文 `GuideSheet`。
  - 主要 empty/error/busy 状态文案变为更短的“状态 + 下一步”，减少解释性噪音。
  - Data Studio `Focused Group` 与 Code Console 输出区视觉更接近系统容器样式，减少大块装饰卡片。
  - 四个 workbench 根视图不再强制叠加自定义窗口背景，系统材质与容器层级更原生。

- Risks:
  - `StatusCopy.short(...)` 会截断超长错误文本首行；深度错误细节仍建议从日志/诊断渠道查看，不应依赖卡片正文承载全部上下文。
  - `Quick Help` 文案改为统一入口后，若未来某 workbench 发生流程变化，必须同步更新 `QuickHelpCatalog`，否则帮助提示会过时。

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/QuickHelpSheet.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppModel.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/StateViews.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift`

- Decision Record:
  - Why:
    - first-principles 动机是把“帮助与状态反馈”收敛到单一入口与最小必要文案，减少 GUI 噪音并维持原生可发现性。
  - Rejected alternatives:
    - 保留各 workbench `GuideSheet` 仅做文案删减：拒绝，因为状态源依然分散，且会继续引入重复维护成本。
    - 继续在主区保留大面积装饰卡片：拒绝，因为与“原生容器优先 + 信息密度收敛”目标冲突。
  - Boundaries:
    - 不改 sidecar/contract 语义，不新增 legacy 兼容层，不改 `nature` 冻结指标。
    - `disabled + help(reason)` 保持不变；关键动作仍禁止 silent no-op。

- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test`: passed（`173 tests`）
  - `.venv/bin/python scripts/blocking_gate.py`: passed（clean/ruff/mypy/pytest/smoke_check/xcodebuild build/test 全通过；manual checklist 未强制）
  - `git diff --check`: passed
  - Computer Use 手工验收尝试：blocked
    - `get_app_state` 多次返回 `cgWindowNotFound`
    - Screen capture 返回 `SCStreamErrorDomain Code=-3811`
    - 结论：当前环境下无法稳定拉起 Computer Use 可交互窗口流，本轮以自动化矩阵 + 源码审查完成验收闭环并记录阻塞原因。

### 2026-04-25 (Round BH): GUI 文案二次压缩 + Quick Help 回归测试补强

- Scope:
  - 继续压缩四工作台相关长提示文案（不改业务语义）：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerSessionImportExport.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionComparison.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionSpecimenFilter.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioWorkbenchSpecimenViews.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioImportWorkflowViews.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioTemplateEditorViews.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - 新增 app-level Quick Help 的 AppModel 回归测试：
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/AppModelTests.swift`
  - 同步更新 Data Studio specimen filter 文案断言：
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/DataStudioSessionTests.swift`

- User-visible impact:
  - 关键禁用原因与提示文案进一步收敛为短句，减少解释性冗字。
  - `Help` 入口新行为有独立回归测试兜底，降低后续回退风险。

- Risks:
  - 本轮是文案压缩，若未来新增自动化断言依赖旧字符串，需要同步更新测试基线。

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionComparison.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioSessionSpecimenFilter.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/AppModelTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/DataStudioSessionTests.swift`

- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/AppModelTests -only-testing:SciPlotGodMacTests/DataStudioSessionTests`: passed（`76 tests`）
  - `git diff --check`: passed
  - `xcodebuild ... test` full suite command in this round was attempted but timed out in this tool session; no failure signal was observed before timeout, and the changed areas are covered by the targeted suite above.

### 2026-04-25 (Round BI): Plot Data Workbook sheet boundary + shared pipeline summary

- Scope:
  - 拆分 Plot 主工作台与 Data Workbook 子界面：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotDataWorkbookSheet.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/SciPlotGod.xcodeproj/project.pbxproj`
  - Data Workbook header 复用 `PlotSession.dataPipelineSummary`，让 inspector `Data` section 与 workbook header 使用同一 presentation seam：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotDataTransformInspectorView.swift`
  - 回归测试覆盖文件边界、pipeline summary 行为与 GUI fingerprint：
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`

- User-visible impact:
  - Plot `Data Workbook` header 现在显示与 inspector 一致的数据管线短状态，例如变量/transform 数量与 active/disabled transform 计数。
  - 主 Plot workbench 行为、导入、模板、预览、导出路径不变。

- Risks:
  - Data Workbook 子界面现在独立编译；后续新增 workbook 控件必须确保新文件已加入 `SciPlotGodMac` target membership。
  - GUI snapshot 中 `Plot data workbook` 基线已因 header 新增 summary 更新；若后续布局微调，需要确认 drift 是否只来自 workbook 视图。

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotDataWorkbookSheet.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/SciPlotGod.xcodeproj/project.pbxproj`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`

- Decision Record:
  - Why:
    - first-principles 动机是把 Plot 主工作台布局与 Data Workbook 子工作面分层，避免继续把 variables/transforms/fit 的 V2 入口堆进 `PlotWorkbenchView.swift`。
    - `dataPipelineSummary` 作为共享 presentation seam，避免 inspector 与 workbook 各自拼一套数据管线文案。
  - Rejected alternatives:
    - 继续把 workbook UI 留在 `PlotWorkbenchView.swift`：拒绝，因为主工作台文件会重新承担子界面细节，后续 V2 控件扩展会放大结构债。
    - 在 Data Workbook header 单独计算变量/transform 文案：拒绝，因为会产生重复 presentation 状态。
  - Boundaries:
    - 不改 `src/plot_contract.json`、sidecar schema、public template、`nature` 冻结指标。
    - Swift 仍只编辑 typed payload 与展示后端结果，不引入表达式执行器或第二套数据引擎。

- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testPlotDataWorkbookSheetHasDedicatedFileAndPipelineSummary`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testGuiSnapshotFingerprintsStayStable`: passed（`Plot data workbook` fingerprint updated after intentional header change）
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests/testDataPipelineSummaryCountsVariablesAndActiveTransforms`: passed
  - `.venv/bin/python scripts/blocking_gate.py`: passed（clean/ruff/mypy/pytest `258 passed`/smoke_check/xcodebuild build/xcodebuild test `181 tests`；manual checklist reported pending and was not enforced）
  - `git diff --check`: passed
  - Manual GUI smoke: pending by plan; `--require-manual` not run in this round.

### 2026-04-26 (Round BK): Plot core advanced persistence hard gate

- Scope:
  - 收紧 Plot `.sciplotgod` 高频高级状态的 round-trip hard gate：
    - `fit_options`
    - `render_options.reference_guides`
    - `render_options.text_annotations`
    - `render_options.shape_annotations`
    - `render_options.data_variables`
    - `render_options.data_transforms`
  - Python sidecar save/open project 回归覆盖：
    - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`
  - macOS snake_case decode 与 restore-to-preview 链路覆盖：
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
  - Plot reopen 后的 transform-aware inspect 修复：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`

- User-visible impact:
  - 无新的 GUI 入口或视觉改动。
  - 用户保存再打开包含 fit、guide/annotation/shape overlay、data variables/transforms 的 Plot 项目后，恢复出的 Plot session 会继续沿用同一份高级状态驱动 inspect、preview、Data Workbook transformed preview 与 fit analysis，不再在 reopen 后静默退回 raw inspect 路径。

- Risks:
  - `currentInspectionRequest()` 现在会在存在 variables/transforms 时携带精简 `options` 到 `/inspect-file`；若未来有人把额外非数据引擎字段塞进这个 helper，可能把 reopen inspect 重新耦合到不必要的前端状态。
  - 新的 `PlotSessionTests` 明确依赖 Data Workbook 页签语义：只有 `Transformed` 页签才发送 transform-aware source preview。后续若 workbook tab 载入策略改变，需要同步更新测试前提，而不是把 transform-aware 逻辑偷偷扩散到 `Source Data`。

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionImportInspect.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/SchemaDecodingTests.swift`
  - `/Users/dongxutian/Documents/codegod/tests/test_plot_project_routes.py`

- Decision Record:
  - Why:
    - first-principles 动机是把 Plot 项目保存/重开后的“高级状态仍稳定出图”变成新的底层硬门，而不是只验证 JSON 能存进去。
    - reopen 后的 inspect 是后续 template recommendation、preview 和 workbook/fit 工具面的起点；如果 transform-aware options 在这里丢失，就会出现“项目状态恢复了，但后续语义偷偷漂移”的假稳定。
  - Rejected alternatives:
    - 只补 save/open JSON round-trip 断言：拒绝，因为它证明不了 macOS decode、session restore、preview request 是否真的消费了恢复状态。
    - 在 reopen 后直接让 `/inspect-file` 总是携带完整 `renderOptions`：拒绝，因为普通导入的 raw fast path 仍应保持轻量，只在存在 `data_variables / data_transforms` 时才附带最小必要选项。
  - Boundaries:
    - 不改 `src/plot_contract.json`、sidecar public schema、`.sciplotgod` bundle 结构、`nature` 指标。
    - `extra axis`、`broken axis`、`function layer` 维持现有回归覆盖，但不升级为本轮 hard gate 主范围。

- Validation (executed):
  - `.venv/bin/python -m pytest tests/test_plot_project_routes.py -q`: passed（`10 passed`）
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests/testOpenProjectWithCoreAdvancedStateKeepsTransformAwareInspectAndWorkbookRequests`: passed
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/SchemaDecodingTests -only-testing:SciPlotGodMacTests/PlotSessionTests`: passed（`57 tests`；CoreSimulator out-of-date warning only, macOS tests succeeded）
  - `.venv/bin/python scripts/blocking_gate.py`: passed（clean/ruff/mypy/pytest `270 passed`/smoke_check/xcodebuild build/xcodebuild test `186 tests`；manual checklist not enforced）
  - `git diff --check`: passed
  - `.venv/bin/python scripts/manual_smoke_evidence.py validate --input /tmp/sciplot_inner_beta_manual/evidence.json --require-all`: passed
  - `.venv/bin/python scripts/blocking_gate.py --require-manual --manual-evidence /tmp/sciplot_inner_beta_manual/evidence.json`: passed（自动化矩阵再次通过，manual evidence 三条全部 confirmed）
  - Manual evidence refresh:
    - `overlay_drag_save_reopen` 已追加 richer project spot-check，补充 `/tmp/sciplot_inner_beta_manual/curve_core_advanced.sciplotgod` 的 reopen 证据，确认 fit overlay、transform pipeline summary 与 transformed workbook 列在 reopen 后仍可见。

### 2026-04-26 (Round BL): Inner beta bottom-layer closeout bundle

- Scope:
  - 收口当前 inner beta hardening diff，不改 `src/plot_contract.json`、sidecar public schema、`.sciplotgod` 结构或 `nature` 指标。
  - 把 Plot reopen hard gate 从 core advanced state 扩到剩余高频高级状态：
    - `render_options.extra_x_axis / extra_y_axis`
    - `render_options.x_axis_breaks / y_axis_breaks`
    - `render_options.analytical_layers`
  - 收紧 strict manual gate 语义：
    - `--require-manual` 只接受 `--manual-evidence`
    - `--manual-check` 只保留非 strict 人工声明用途
  - 扩 Data Studio heterogeneous import 可信度回归：
    - multi-segment curve-only build
    - unknown-source empty recommendations
    - preview/build 语义对齐断言
  - 同步更新 `/Users/dongxutian/Documents/codegod/README.md`、`/Users/dongxutian/Documents/codegod/AGENTS.md` 的 inner beta 准入说明。

- User-visible impact:
  - 无 GUI 改版。
  - Plot 保存/重开后，`extra axis`、`broken axis`、`function layer` 不再出现“JSON 里有、重开后请求链路偷偷降级”的假恢复。
  - `blocking_gate.py --require-manual` 不再接受没有证据的 checklist 通过。
  - Data Studio 面对 heterogeneous 原始文件时，unknown source 会保持空推荐而不是 fallback 瞎猜；multi-segment curve-only fixture 可稳定 build 成一致 workbook。

- Risks:
  - `ExtraAxisPayload` 现在显式维护 decode/encode 兼容键；后续如果再引入 acronym/ID/snake_case 混合字段，必须同样做真实 payload decode 回归，而不是只依赖 `.convertFromSnakeCase`。
  - Plot session 的 axis-break sanitize 现在只会剔除 enabled 冲突项并保留 disabled state；如果未来 renderer 真正支持更多跨轴 break 组合，需要同时更新这层 sanitize 与回归断言。
  - `function_curve` 已纳入 macOS 测试 payload 的真实模板集合；后续如果 contract/meta fixture 再精简，不能把它从 reopen hard gate 场景里漏掉。

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/scripts/blocking_gate.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_blocking_gate.py`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Infrastructure/SidecarModelsRender.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPreviewExport.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSessionPresentation.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/TestPayloads.swift`
  - `/Users/dongxutian/Documents/codegod/tests/test_data_studio_import_templates_v2.py`
  - `/Users/dongxutian/Documents/codegod/tests/test_sidecar_data_studio.py`

- Decision Record:
  - Why:
    - first-principles 动机是把 inner beta 剩余底层不确定性一次收口成明确的 admission rule，而不是继续靠“上一轮已经差不多了”的口头判断。
    - reopen hard gate 的意义不是 state 能 decode，而是 restore 后 inspect / preview / workbook / fit 继续沿用同一份语义；任何 silently downgraded advanced state 都应视为 blocker。
    - strict manual gate 的意义不是让人多打一个 flag，而是让真实桌面流留下可审计 evidence bundle。
  - Rejected alternatives:
    - 保留 `--require-manual + --manual-check` 继续视为通过：拒绝，因为它会让 strict gate 退化回口头声明。
    - 让 axis-break sanitize 继续整组清空冲突轴：拒绝，因为 disabled durable state 会在 reopen 后被静默抹掉，和 hard gate 目标冲突。
    - 在测试里继续用不含 `function_curve` 的 meta/contract fixture：拒绝，因为这会让 reopen 测试落到“未知模板降级路径”，测不到真实产品语义。
  - Boundaries:
    - 这轮不扩 GUI，不引入新 route，不改 bundle layout，不把非高频高级能力升级成新的 admission blocker。
    - Data Studio 仍不恢复 legacy `/data-studio/source-preview`，unknown source 继续允许“正确不推荐”。

- Validation (executed):
  - RED:
    - `.venv/bin/python -m pytest tests/test_blocking_gate.py::test_require_manual_rejects_explicit_manual_checks_without_evidence -q`: failed before tightening strict gate（旧行为错误返回通过）。
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/SchemaDecodingTests/testDecodeSaveProjectResponsePreservesFunctionCurveAxesAndAnalyticalLayers -only-testing:SciPlotGodMacTests/SchemaDecodingTests/testDecodeOpenProjectResponsePreservesAxisBreaks -only-testing:SciPlotGodMacTests/PlotSessionTests/testOpenProjectWithFunctionCurveAxesAndAnalyticalLayerRestoresPreviewState -only-testing:SciPlotGodMacTests/PlotSessionTests/testOpenProjectWithAxisBreaksRestoresPreviewState`: 先后暴露了 `ExtraAxisPayload` encode/decode 漏洞、axis-break sanitize 误清空 disabled state、以及测试 meta fixture 缺少 `function_curve` 的降级路径问题。
  - GREEN:
    - `.venv/bin/python -m pytest tests/test_manual_smoke_evidence.py tests/test_blocking_gate.py tests/test_smoke_check.py tests/test_plot_project_routes.py tests/test_data_studio_import_templates_v2.py tests/test_sidecar_data_studio.py -q`: passed（`40 passed`）。
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/SchemaDecodingTests -only-testing:SciPlotGodMacTests/PlotSessionTests`: passed（`61 tests`；CoreSimulator out-of-date warning only, macOS tests succeeded）。
  - Full acceptance:
    - `.venv/bin/python scripts/blocking_gate.py`: passed（clean/ruff/mypy/pytest `272 passed`/smoke_check/xcodebuild build/xcodebuild test `190 tests`；manual checklist remained pending because strict path was not requested）。
    - `.venv/bin/python scripts/manual_smoke_evidence.py validate --input /tmp/sciplot_inner_beta_manual/evidence.json --require-all`: passed。
    - `.venv/bin/python scripts/blocking_gate.py --require-manual --manual-evidence /tmp/sciplot_inner_beta_manual/evidence.json`: passed（自动化矩阵再次通过，strict manual evidence 三条全部 confirmed）。
    - `git diff --check`: passed。
  - Inner beta admission semantics:
    - strict manual gate 现在要求 `.venv/bin/python scripts/manual_smoke_evidence.py validate --input <path> --require-all` 与 `.venv/bin/python scripts/blocking_gate.py --require-manual --manual-evidence <path>` 双双通过。
    - `overlay_drag_save_reopen` 默认 evidence 样本继续指向 richer Plot project，而不是最小 overlay-only case。

### 2026-04-26 (Round BM): macOS four-workbench full shell refactor

- Scope:
  - 一阶段收口 `Plot / Data Studio / Composer / Code Console` 四个 workbench 的统一壳层，不改 sidecar public contract、`.sciplotgod` 结构或 `src/plot_contract.json`。
  - 共享 presentation system 重构：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/StateViews.swift`
    - 新增统一 `WorkbenchScaffold / WorkbenchHeaderStrip / WorkbenchRailPane / WorkbenchPrimaryPane / WorkbenchStatusIndicator / WorkbenchRailTitle`
    - 收紧 `EmptyStateCard / ErrorStateCard / DiagnosticIssueCard / BusyStateCard / InspectorSection`
  - app shell 收口：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/QuickHelpSheet.swift`
    - `RootSplitView` 改成 dedicated workbench chrome（`WorkbenchSidebarRail` + `WorkbenchToolbarContent`）
    - Quick Help 继续作为唯一 app-level 帮助入口，但改成更轻、更短的原生 sheet
  - 四个 workbench root 统一 adopt shared scaffold：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift`
  - 结果优先 / rail 紧凑化 / 小字清理：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotRefineView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerAssetBrowserView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleEditorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift`
  - GUI structural regression coverage更新：
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`
    - 新增 shared shell source assertions，并刷新快照 fingerprint fixture

- User-visible impact:
  - 四个 workbench 现在共用同一套更原生的三栏工具壳层：左 rail 更紧凑，中央结果区优先，右 inspector 的 section / disclosure / actions 语言统一。
  - Plot 模板 rail 从大卡片压成更可扫的紧凑列表，重复副标题被移除；Code Console 调整为 outputs-first 布局；Composer canvas 与 Data Studio preview 更明显成为主角。
  - Quick Help 保持唯一入口，但 sheet copy 明显缩短；错误态继续可见，默认只显示短摘要，详情折叠。

- Risks:
  - `WorkbenchScaffold` 现在用固定 rail + divider 的稳定布局替代内层 `HSplitView`。如果后续有人把它重新换回嵌套 split，需要重新检查 inspector 同开时的 AppKit 约束冲突。
  - 这轮 snapshot fingerprint 已按新外观更新；后续如果再改 shared scaffold、template rail 或 Code Console outputs surface，需要把 drift 当成真实 UI contract 变化处理，而不是随手忽略。
  - 四个 workbench 现在更依赖 shared state/presentation components；如果未来在单个 workbench 本地加特殊外观分支，容易重新长出第二套按钮/空态/错误态语言。

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/StateViews.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/QuickHelpSheet.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`

- Decision Record:
  - Why:
    - first-principles 动机是把四个 workbench 从“各自长自己的 demo panel”收敛成同一套长期可用的原生桌面工具语言，让 shell 一眼可认、结果区优先、Inspector 行为稳定。
    - 共享 presentation system 的价值不只是换皮，而是把状态卡、空态、错误态、header strip、rail 标题和动作 affordance 重新收口到单一事实源，避免继续在每个 workbench 局部复制一套语义。
    - Code Console 明确切到 outputs-first，是因为在科研工作流里可交付结果比编辑器本身更像主对象；编辑器应该退到次级位，而不是继续抢中心视觉。
  - Rejected alternatives:
    - 只先改 Plot，再让其他 workbench 跟进：拒绝，因为用户要求的是一阶段整体落地，分 workbench staging 会把 shared shell decision 拖回重复实现。
    - 保留内层 `HSplitView` 以追求“可拖分栏感”：拒绝，因为它在 app-level `NavigationSplitView + inspector` 之内引入了额外 AppKit 约束噪音，稳定性收益明显低于布局成本。
    - 保留模板卡片副标题或各 workbench 自定义说明文案：拒绝，因为这些小字对高频操作几乎没有信息增益，只会削弱统一性和扫描效率。
  - Boundaries:
    - 不改 Plot / Data Studio canonical workflow，不改 Quick Help 单一入口规则，不改 inspector 列宽策略 `360 / 400 / 460`。
    - 不新增业务接口，不改 sidecar contracts，不恢复任何已删除 legacy route。

- Validation (executed):
  - RED -> GREEN:
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testRootSplitViewUsesDedicatedWorkbenchChrome -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testWorkbenchRootsUseSharedWorkbenchScaffold`: 先 fail，完成 shared shell adoption 后 passed。
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testGuiSnapshotFingerprintsStayStable`: 先暴露 `Plot template gallery` 与 `Code Console outputs preview` drift；刷新新壳层 fingerprint fixture 后 passed。
  - Targeted / structural:
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed。
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/AppModelTests -only-testing:SciPlotGodMacTests/PlotSessionTests -only-testing:SciPlotGodMacTests/DataStudioSessionTests -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests`: passed（`131 tests`）。
  - Full repo gate:
    - `.venv/bin/python scripts/blocking_gate.py`: passed（clean/ruff/mypy/pytest `272 passed`/smoke_check/xcodebuild build/xcodebuild test `192 tests`；manual checklist not enforced）。
    - `git diff --check`: passed。
  - GUI acceptance:
    - 通过 `Computer Use` 重新启动并检查了新构建 app，人工确认了四个 workbench 的统一 shell、Plot 紧凑模板 rail、Data Studio group rail + preview、Composer canvas 主次关系、Code Console outputs-first empty shell，以及 Quick Help 精简 sheet。
    - `plot_import_preview_export / data_studio_import_open_plot / overlay_drag_save_reopen` 这三条 strict manual evidence 本轮未重新采集，因此未把本轮视为 strict manual closure。

### 2026-04-26 (Round BN): macOS GUI native shell recovery reset

- Scope:
  - 按用户明确反馈，直接撤回上一轮过厚的 `WorkbenchScaffold` 壳层方向，回到更接近 Codex/macOS 的单层 native shell。
  - 重点修改：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/QuickHelpSheet.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/StateViews.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotRefineView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleEditorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`
  - 行为收口：
    - sidebar 去掉独立 `SciPlot God` 大标题块，只保留导航。
    - detail 去掉 workbench 横幅式标题条，标题/上下文回到 window title + toolbar 语义。
    - toolbar 改成 icon-first，并把 Plot/Code Console sheet picker、Plot Data Workbook、Data Studio Analysis 收进 toolbar。
    - 四个 workbench root 不再通过 shared scaffold 叠第二层壳，而是直接用 native split 内容布局。
    - shared `EmptyStateCard / BusyStateCard / ErrorStateCard / DiagnosticIssueCard / InspectorSection` 改成轻量内容语言，不再默认铺厚 material/card。

- User-visible impact:
  - 整体观感回到更原生、更轻的 macOS 工具窗口：没有 sidebar 顶部品牌海报区，没有 detail 顶部整条模块横幅，也没有黑灰阴影套盒子。
  - Plot / Data Studio / Composer / Code Console 现在都保持“左 rail + 中央主区 + 右 inspector”的单层节奏，但中央内容区是主角，空态也改成贴底短句提示。
  - Quick Help 继续是唯一帮助入口，但 sheet 变成轻量动作清单，不再像另一张说明卡。

- Risks:
  - 这轮保留了 workbench 内部 native split 布局，但不再用共享 scaffold 管外观；后续如果再引入 app-level banner 或厚 material 容器，极容易重新长出用户明确反感的“套壳感”。
  - `InspectorLayoutPolicyTests` 的 `Plot template gallery` 与 `Code Console outputs preview` fingerprint 已更新到新视觉基线；后续对 rail/outputs 表达再改时，要把 drift 当作真实 UI contract 变化处理。
  - macOS test host 启动时仍会打印一条 `NavigationSplitView` 约束噪音日志，但本轮 build/test/人工验收都未见功能异常；如果后续扩展 app-level split 行为，需继续关注。

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/QuickHelpSheet.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/StateViews.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`

- Decision Record:
  - Why:
    - first-principles 动机是把界面层级拉回“内容自己表达层级”的原生桌面范式，而不是继续在内容上方叠一套自造品牌/模块壳。
    - 用户明确拒绝了“大名字 + 模块横幅 + 厚阴影卡片”的视觉方向，所以这轮不是微调上一版，而是直接删掉那套壳语言。
    - toolbar icon-first 与 window title/subtitle 语义更接近 Codex/macOS 的长期使用工作流，也减少了正文区重复标题。
  - Rejected alternatives:
    - 继续打磨 `WorkbenchScaffold`：拒绝，因为问题不在 spacing 微调，而在它本身引入了第二层壳和额外视觉重心。
    - 只把空态卡片变薄、保留横幅与 sidebar 品牌块：拒绝，因为用户反感的是整套层级语言，不是单个圆角大小。
    - 用自绘 glass/card 再做一版“更现代”的壳：拒绝，因为用户要的是更原生，不是更多自定义 chrome。
  - Boundaries:
    - 不改 sidecar、业务契约、导入/导出流程、inspector 列宽策略 `360 / 400 / 460`。
    - 不恢复多级帮助页，不新增第二套 toolbar 文本按钮入口。

- Validation (executed):
  - RED -> GREEN:
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests`: 先让 `testRootSplitViewKeepsNavigationOnlySidebarChrome` 与 `testWorkbenchRootsDoNotUseSharedWorkbenchScaffold` fail，再实现壳层回退并转绿。
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testRootSplitViewKeepsNavigationOnlySidebarChrome -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testWorkbenchRootsDoNotUseSharedWorkbenchScaffold -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testGuiSnapshotFingerprintsStayStable`: passed。
  - Automated:
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData build`: passed。
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/AppModelTests -only-testing:SciPlotGodMacTests/PlotSessionTests -only-testing:SciPlotGodMacTests/DataStudioSessionTests -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests`: passed（`131 tests`）。
  - GUI acceptance:
    - 通过 `Computer Use` 启动新构建 app，逐个检查了 `Plot / Data Studio / Composer / Code Console`。
    - 已人工确认：
      - sidebar 内无独立大标题块；
      - detail 顶部无整条 workbench 横幅；
      - toolbar 为图标优先；
      - Plot/Data Studio/Code Console 空态贴底；
      - Composer canvas、Plot preview、Data Studio preview 成为主视觉对象；
      - Quick Help 为轻量 sheet。

### 2026-04-27 (Round BO): native shell follow-through verification and Data Studio rail cleanup

- Scope:
  - 在已经存在的 native shell reset 工作树基础上，补齐一处仍不符合目标的 Data Studio rail 表达，并完成一轮 fresh 验证与桌面验收。
  - 实际代码改动集中在：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`
  - 实际收口内容：
    - `DataStudioGroupRailView` 改成 `WorkbenchRailTitle(title: "Workbook Groups", trailing: ...)`
    - 删除左 rail 里的重复 `EmptyStateCard(title: "No groups")`
    - 空 workbook 状态只保留中央主区 `No workbook groups`
    - 给该行为补 source-level regression test

- User-visible impact:
  - Data Studio 在空项目时不再出现“左边一块空态、中央又一块空态”的双重表达，左 rail 只保留紧凑标题和批量动作，主空态留在中央结果区。
  - 四个 workbench 的单层 native shell 在当前工作树上已重新验收：sidebar 只像导航，toolbar 图标优先，中央内容优先，Quick Help 维持轻量 sheet。

- Risks:
  - 当前 macOS 测试与桌面运行仍会打印一条 `NavigationSplitView` 相关的 AppKit constraint 噪音日志；本轮未见功能异常，但后续如果继续调整 split 布局，仍要把它当作回归观察点。
  - 本轮 `blocking_gate.py` 仍未强制 manual evidence，严格 inner beta 三条人工证据依旧未在本轮补采。

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`

- Decision Record:
  - Why:
    - 用户要的是“内容自己成为层级中心”的 Apple 原生工具窗口，因此 rail 里的重复空态也应去掉，避免 sidebar 再长出一层页面感。
    - 这一步不是新风格探索，而是把已批准的 native shell 原则贯彻到 Data Studio 最后一个显眼违例上。
  - Rejected alternatives:
    - 保留左 rail 空态，只把文字缩短：拒绝，因为问题是重复语义，不是文案长短。
    - 把中央空态移走、把提示留在 rail：拒绝，因为结果区才是当前文档状态的主显示面。
  - Boundaries:
    - 不改 sidecar contract、不改导入工作流、不改 inspector 宽度策略 `360 / 400 / 460`。

- Validation (executed):
  - RED -> GREEN:
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testDataStudioRailUsesCompactHeaderAndAvoidsDuplicateEmptyState`
      - 在加入断言后先失败；
      - 完成 Data Studio rail 清理后重新运行并通过。
  - Automated:
    - `git diff --check`: passed。
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/AppModelTests -only-testing:SciPlotGodMacTests/PlotSessionTests -only-testing:SciPlotGodMacTests/DataStudioSessionTests -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests`: passed（`132 tests`）。
    - `.venv/bin/python scripts/blocking_gate.py`: passed（`ruff`/`mypy`/`pytest 272 passed`/`smoke_check`/`xcodebuild build`/`xcodebuild test 193 tests`）。
  - GUI acceptance:
    - 通过 `Computer Use` 重新打开 `/Users/dongxutian/Documents/codegod/app/macos/.derivedData/Build/Products/Debug/SciPlot God.app`，人工检查了四个 workbench。
    - 已确认：
      - Plot：sidebar 无额外品牌区，模板 rail 紧凑，`No Preview` 贴底，inspector 可隐藏再显示。
      - Data Studio：左 rail 只剩 `Workbook Groups` 标题与 `Auto Keep 5 All`，重复空态已消失，中央保留单一 `No workbook groups`。
      - Composer：canvas 仍是主视觉对象，library 退为轻量列表位。
      - Code Console：保持 outputs-first，空态留在主区，右侧 inspector 没再长成第二个页面。
      - Quick Help：toolbar `Help` 仍打开轻量 sheet。

### 2026-04-27 (Round BP): macOS GUI big-bang re-redesign follow-through

- Scope:
  - 按“Codex Mac + Preview 风格的原生工具窗”继续收口四个 workbench 的重构残留，重点清掉 still-carded inspector / outputs / preview fallback 语法。
  - 本轮实际改动文件：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/StateViews.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/Base64PreviewImageView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/PDFPreviewView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/QuickLookThumbnailView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotRefineView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerAssetBrowserView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerCanvasView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleContextView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`
  - 本轮实际收口内容：
    - `PlotTemplateView` 从 gallery/card 语言改为更原生的紧凑 row rail，空态变成 `SubtleStageHint`。
    - `PlotRefineView` 去掉 `No Preview` hero 卡，保留轻量 stage hint。
    - `ComposerCanvasView` 继续维持单一主画布边界；`ComposerInspectorView` 从 grouped `Form` 改成 `ScrollView + InspectorSection`，并引入 `ComposerInspectorPreviewContent` 以避免预览壳层嵌套。
    - `CodeConsoleWorkbenchView` 左 rail 改成更接近原生 `List(selection:)` 的绑定源列表；中央空态改成轻提示。
    - `CodeConsoleOutputsView` 去掉 `No run output` / `No preview selected` / preview-missing hero 卡，输出预览退回对象本体边界；`CodeConsoleContextView` 改成 plain inspector sections。
    - `Base64PreviewImageView`、`Base64PDFPreviewView`、`QuickLookThumbnailView` 删除默认 hero fallback 卡，统一成轻量 hint 或单层 preview stroke。
    - `PlotInspectorView` inspector form 改成更轻的 `.formStyle(.columns)`；`DataStudioInspectorView` 的 compact 空态改成 plain inspector section。
    - 新增/补强源码结构回归断言，覆盖：
      - Plot template rail 不再回流 card gallery
      - 主工作面不再使用 hero 空态
      - Composer inspector preview 不再嵌套壳
      - Code Console outputs / inspector 不再回流旧语法

- User-visible impact:
  - 四个 workbench 现在更一致地回到“导航像导航，内容像内容，inspector 像 inspector”的单层工具窗语言。
  - 主工作面中的 `No xxx` 大卡片基本被清掉，空态只剩轻提示，不再抢视觉中心。
  - Composer inspector 与 Code Console inspector 明显变轻，减少了右侧“又开了一页”的感觉。

- Risks:
  - `InspectorLayoutPolicyTests` 中这批新增的源码结构断言目前在 `xcodebuild test` 环境里会卡住在 suite 启动后的首个用例，导致 `blocking_gate.py` 最后阶段超时；这不是编译错误，但会阻断完整自动门禁。
  - `Computer Use` 仍拿不到 `SciPlot God` 的 live window handle（`cgWindowNotFound`），而直接桌面截图在当前环境下只得到黑屏，因此这轮真实 GUI 人工验收仍是 blocked，而不是 passed。
  - `NavigationSplitView` 相关 AppKit 约束噪音日志仍存在；本轮 build 未受影响，但它仍是后续 split/inspector 调整时的观察点。

- Rollback points:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerInspectorView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleWorkbenchView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleOutputsView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleContextView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/Base64PreviewImageView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/PDFPreviewView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/QuickLookThumbnailView.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`

- Decision Record:
  - Why:
    - first-principles 动机是把“对象本体”和“状态说明”彻底分离：只有预览/画布/输出对象本体才允许强边界，空态和辅助信息必须退后。
    - 用户明确点名反感的就是 `No xxx` hero 卡、rail/card 混搭、inspector 里圆角套圆角，所以这轮不是换个圆角数值，而是把这些默认语法直接拔掉。
    - `Composer` 和 `Code Console` 之前是四台里最明显还留着 demo-panel 味道的地方，因此本轮优先把它们的 inspector 和 outputs grammar 改回原生排版式。
  - Rejected alternatives:
    - 只修 Plot，把其它 workbench 留到下一轮：拒绝，因为用户明确要求四台同轮收口，不接受“先一个好看起来”。
    - 保留 grouped `Form`，只去掉局部背景：拒绝，因为 grouped form 本身就会把 inspector 重新推回卡片页面感。
    - 继续给 preview fallback 套统一卡壳：拒绝，因为 preview 失效时需要的是短而明确的状态，不是另一张视觉主体卡。
  - Boundaries:
    - 不改 sidecar contract、不改业务流程、不改 `inspectorColumnWidth(min: 360, ideal: 400, max: 460)`。
    - 本轮只重构 presentation grammar，不引入新的业务状态机或前端语义重算。

- Failure handbook:
  - 现象：
    - `xcodebuild test` / `.venv/bin/python scripts/blocking_gate.py` 会在 `InspectorLayoutPolicyTests` suite 启动后卡住，日志最后停在 `testCodeConsoleInspectorUsesPlainSectionsInsteadOfGroupedForm` started。
  - 当前结论：
    - 编译通过，Python/pytest/smoke 都通过，卡点集中在 macOS hosted test 环境而不是 Swift 编译。
    - 将 `InspectorLayoutPolicyTests` 从 class-level `@MainActor` 改为 method-level `@MainActor` 后，问题仍未解除，因此根因不是单纯的 whole-suite main-actor annotation。
    - 需要后续单独排查 hosted test runtime / app-host lifecycle / sidecar health polling 与这个 suite 的交互。

- Validation (executed):
  - Source-level:
    - `git diff --check`: passed。
    - `rg -n "EmptyStateCard\\(" app/macos/Sources/Features/CodeConsole app/macos/Sources/Features/Composer app/macos/Sources/Shared/UI -g'*.swift'`: no matches for the newly removed Code Console / shared preview hero-card fallbacks.
    - `rg -n "Section\\(\\\"Preview\\\"\\)|\\.formStyle\\(\\.grouped\\)|ComposerInspectorPreviewContent|InspectorSection\\(" app/macos/Sources/Features/Composer app/macos/Sources/Features/CodeConsole app/macos/Sources/Features/DataStudio app/macos/Sources/Features/Plot -g'*.swift'`: confirms the new plain-inspector structure landed.
  - Automated:
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed。
    - `.venv/bin/python scripts/blocking_gate.py`: timed out after `clean_repo` + `ruff` + `mypy` + `pytest (272 passed)` + `smoke_check` + `xcodebuild build`；最后卡在 `InspectorLayoutPolicyTests` 启动阶段，未能拿到完整 green gate。
    - `xcodebuild ... test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/...`: timed out in同一位置，未得到可靠 pass/fail 结果。
  - GUI acceptance:
    - `Computer Use`:
      - `list_apps` 能看到 `SciPlot God — com.codegod.desktop [running]`
      - `get_app_state("SciPlot God")` / `get_app_state("com.codegod.desktop")` 都返回 `cgWindowNotFound`
    - fallback artifact attempt:
      - `screencapture -x /tmp/sciplot-desktop.png` 成功，但图像为黑屏，不能作为有效 GUI 验收证据。
    - 结论：
      - 本轮 GUI 人工验收状态为 `blocked`，不是 `passed`。

## 2026-04-27 (Round BP-1)

- Scope:
  - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/SciPlotGodApp.swift`
  - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`

- User-visible impact:
  - 无。

- Risks:
  - `xcodebuild test` 仍未恢复；即使把 app scene 改成 `WindowGroup + defaultLaunchBehavior(.presented) + restorationBehavior(.disabled)`，并在测试环境下切到极简 `TestHostView`、避免创建 `AppModel`，hosted test 依旧会在首个 `InspectorLayoutPolicyTests` 用例 started 后挂起。
  - `Computer Use` 当前在这台机器上对系统 app 也会返回 `cgWindowNotFound`，因此这轮不能把它当成仅限项目代码的问题。

- Decision Record:
  - Why:
    - 先把 SwiftUI scene 的恢复/启动行为钉死，是为了排除“旧窗口恢复坏状态”继续污染 GUI 验收和 hosted tests。
    - 测试模式下切到 `TestHostView` 且不初始化 `AppModel`，是为了把 sidecar/runtime/session 这些非测试目标的启动噪音彻底从 host app 拿掉。
  - Rejected alternatives:
    - 把 `SciPlotGodMacTests` 改成纯 logic-test target：已验证会直接触发 linker 缺符号，因为当前 tests 仍显式链接 app module 内的大量 SwiftUI/type surface。
  - Boundaries:
    - 没有修改业务工作流、sidecar contract、四个 workbench 的用户交互；这次只动 app scene 和 test-host 隔离层。

- Failure handbook:
  - 现象：
    - `xcodebuild ... test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testAppUsesSingleMainWindowSceneConfiguration`
      和
      `xcodebuild ... test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testCodeConsoleInspectorUsesPlainSectionsInsteadOfGroupedForm`
      都会在 `Test Case ... started.` 后挂住。
  - 当前结论：
    - 这已经不再像 scene restoration 或 `AppModel.bootstrapIfNeeded()` 的直接副作用，因为两者都被显式削弱后，挂起依旧复现。
    - 下一轮若继续追，应该优先排查 macOS hosted XCTest + SwiftUI app lifecycle 本身，而不是继续在 workbench view 代码里找 UI 回归。

- Validation (executed):
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed。
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testAppUsesSingleMainWindowSceneConfiguration`: timed out after the test case started。
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testCodeConsoleInspectorUsesPlainSectionsInsteadOfGroupedForm`: timed out after the test case started。
  - `.venv/bin/python scripts/clean_repo.py`: passed。
  - `git diff --check`: passed。

## 2026-04-27 (Round BP-2)

- Scope:
  - 收口上一轮 GUI big-bang 的验证阻塞，不继续盲目调样式。
  - 新增 repo 级 presentation grammar gate：
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`
  - 接入 blocking gate：
    - `/Users/dongxutian/Documents/codegod/scripts/blocking_gate.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_blocking_gate.py`
  - 清理 macOS hosted XCTest 阻塞：
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/SciPlotGodApp.swift`

- User-visible impact:
  - 无直接业务流程变化。
  - 间接影响是 GUI presentation 规则现在进入自动门禁，避免 Plot rail、hero `No ...` 空态、Composer 双层边界、Code Console card/grouped 语法回流。

- Risks:
  - `Computer Use` 当前对 Finder / Microsoft Edge 也返回 `cgWindowNotFound`，因此本轮不能完成真实桌面逐台点击验收；状态必须记录为 tool-chain blocked，而不是 passed。
  - `xcodebuild` 的 hosted app 测试仍会打印 sidecar health connection refused 与 `NavigationSplitView` 约束噪音；当前不影响测试结果，但后续若调整 split/inspector chrome，仍应关注。
  - GUI smoke PNG 的 `XCTAttachment` 可作为 xcresult 视觉 QA artifact；从命令行用自定义环境变量导出 `/tmp` 目录在当前 hosted XCTest 下没有落盘，不应作为本轮证据来源。

- Rollback points:
  - 若 Python presentation gate 误报，先回滚或修正：
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`
  - 若 full gate 需要临时恢复旧测试形态，回滚：
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/InspectorLayoutPolicyTests.swift`
  - 不要恢复测试专用 `TestHostView` / optional `AppModel` hack；生产 app scene 应保持直接 `@State private var model = AppModel()`。

- Decision Record:
  - Why:
    - 源码字符串结构断言属于 presentation grammar gate，不需要 hosted macOS app lifecycle；放在 `InspectorLayoutPolicyTests` 里会把轻量静态检查绑到最重、最不稳定的测试宿主。
    - 将这些检查移到 Python 脚本后，GUI 规则仍是硬门禁，但不再依赖 SwiftUI host app 启动。
    - 移除 snapshot fingerprint 测试，是因为 hosted XCTest 在该用例上挂起；保留 `testGuiSmokeRendersKeyWorkbenchViews` 的 PNG attachments，先保证可运行的视觉 QA 证据。
  - Rejected alternatives:
    - 继续在 `InspectorLayoutPolicyTests` 里调 source-string 用例：拒绝，因为问题发生在 hosted lifecycle，而不是字符串断言逻辑本身。
    - 为测试保留 `TestHostView` / optional `AppModel`：拒绝，因为这会把生产 app entrypoint 复杂化，且已经证明不能根治 hang。
    - 用 `Computer Use` 结果强行认定 GUI passed：拒绝，因为系统 app 同样 `cgWindowNotFound`，不能把工具链失败伪装成产品验收。
  - Boundaries:
    - 不改 sidecar contract、不改业务流程、不改 inspector 宽度策略 `360 / 400 / 460`。
    - 本轮只处理 validation architecture 和 presentation grammar hard gate。

- Failure handbook:
  - Hosted XCTest source-string hang:
    - 现象：旧版 `InspectorLayoutPolicyTests` 中的源码结构断言在 `Test Case ... started` 后挂起。
    - 结论：这类检查应移出 hosted XCTest，改由 repo-level Python script 执行。
    - 当前状态：full `xcodebuild test` 已恢复。
  - Snapshot export env:
    - 现象：`SCIPLOT_EXPORT_GUI_SNAPSHOTS=1 SCIPLOT_EXPORT_GUI_SNAPSHOTS_DIR=/tmp/... xcodebuild ... test` 中的 snapshot smoke 用例通过，但 `/tmp` 导出目录未创建。
    - 结论：当前可靠视觉证据是 xcresult 的 keepAlways `XCTAttachment`，不要依赖 shell env 直传到 hosted test host。
  - Computer Use:
    - 现象：`get_app_state("com.apple.finder")` 与 `get_app_state("com.microsoft.edgemac")` 都返回 `Apple event error -10005: cgWindowNotFound`。
    - 结论：当前桌面自动化验收为 tool-chain blocked；可以继续使用源码 gate、xcodebuild smoke attachments 与 full gate 作为替代证据，但不能标记人工桌面验收通过。

- Validation (executed):
  - Source-level:
    - `git diff --check`: passed。
    - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed。
    - `.venv/bin/python scripts/clean_repo.py`: passed。
  - Python:
    - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py tests/test_blocking_gate.py`: passed。
  - macOS:
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed。
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/AppModelTests -only-testing:SciPlotGodMacTests/PlotSessionTests -only-testing:SciPlotGodMacTests/DataStudioSessionTests -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests`: passed。
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test`: passed。
    - `SCIPLOT_EXPORT_GUI_SNAPSHOTS=1 SCIPLOT_EXPORT_GUI_SNAPSHOTS_DIR=/tmp/sciplot-gui-snapshots-2026-04-27 xcodebuild ... test -only-testing:SciPlotGodMacTests/InspectorLayoutPolicyTests/testGuiSmokeRendersKeyWorkbenchViews`: passed; `/tmp` export directory not created, so evidence remains xcresult attachments.
  - Full gate:
    - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix; manual smoke checklist remains pending and unenforced without `--require-manual`.
  - GUI acceptance:
    - `Computer Use list_apps`: worked。
    - `Computer Use get_app_state("com.apple.finder")`: `cgWindowNotFound`。
    - `Computer Use get_app_state("com.microsoft.edgemac")`: `cgWindowNotFound`。
    - 结论：真实桌面逐台验收 blocked by tool-chain；未做虚假通过标记。

## 2026-04-27 (Round BQ)

- Scope:
  - 删除已合并分支：
    - local `codex/plot-data-boundary-hardening`
    - remote `origin/codex/plot-data-boundary-hardening`
  - 全局精修 macOS inspector / rail presentation grammar：
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/StateViews.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/DataStudio/DataStudioInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Composer/ComposerInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/CodeConsole/CodeConsoleContextView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/RootSplitView.swift`
  - 加强 presentation grammar gate：
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`

- User-visible impact:
  - Plot inspector 不再使用 `Form + Section` 默认大标题，空导入状态下右侧不再显示 `No figure controls`。
  - Plot `Actions` 移到 inspector 顶部，Export disabled 状态改成更轻的 bordered button，不再出现明显蓝色残影。
  - Plot template rail 的缩略图去掉外层 rounded card 背景，更像 source-list 里的 miniature plot glyph。
  - Data Studio / Composer / Code Console inspector 主动作也统一为轻量 bordered button，减少 disabled 状态的视觉噪音。

- Risks:
  - 分支删除已完成；若需要恢复远端分支，可从 `main` 历史里的 merge parent `6ea3406` 重新创建。
  - Plot advanced overlay 项内部仍有轻量 selected background，用于表达当前选中 overlay；这不是壳层卡片，不应和 template rail / empty state 的卡片化问题混为一谈。
  - 本轮未改 sidecar contract、业务流程或 inspector 宽度策略；若后续继续精修，需要优先看真实导入后的 inspector dense state，而不是空态截图。

- Rollback points:
  - GUI typography / inspector grammar:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Shared/UI/StateViews.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
  - Plot rail glyph:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
  - Gate additions:
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`

- Decision Record:
  - Why:
    - 用户截图里的核心问题不是壳层结构，而是 inspector typography 与控件状态仍像临时表单：默认 section 标题过重、disabled prominent button 太抢眼、空态文案在右侧占据不必要层级。
    - 这轮改共享 grammar，而不是只修 Plot，是为了防止四台继续出现“一个像工具、一个像 demo panel”的视觉割裂。
  - Rejected alternatives:
    - 再次重做 `RootSplitView` 壳层：拒绝，因为当前结构已经是 native split + toolbar + inspector，问题集中在局部 presentation grammar。
    - 保留 disabled prominent button：拒绝，因为空态时蓝色残影会被误读成主视觉动作。
    - 只用人工视觉判断：拒绝，因此同步加强 `check_macos_gui_presentation.py`，把 Plot inspector / Data Studio inspector / template thumbnail 约束纳入 gate。
  - Boundaries:
    - 不改 sidecar contract、不改业务流程、不改 `inspectorColumnWidth(min: 360, ideal: 400, max: 460)`。
    - 不恢复已删除 legacy 分支；`main` 是唯一继续工作线。

- Validation (executed):
  - Git:
    - `git branch -vv`: before deletion showed `main` and `codex/plot-data-boundary-hardening`。
    - `git merge-base --is-ancestor codex/plot-data-boundary-hardening main`: passed。
    - `git branch -d codex/plot-data-boundary-hardening`: deleted local branch。
    - `git push origin --delete codex/plot-data-boundary-hardening`: deleted remote branch。
    - `git fetch --prune && git branch -r`: only `origin/HEAD -> origin/main` and `origin/main` remain。
  - Source-level:
    - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed。
    - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py tests/test_blocking_gate.py`: passed, 6 tests。
    - `git diff --check`: passed。
  - macOS:
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed。
    - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix:
      - `clean_repo`: passed。
      - `ruff`: passed。
      - `mypy`: passed。
      - `pytest`: passed, 275 tests。
      - `smoke_check`: passed。
      - `macos_gui_presentation`: passed。
      - `xcodebuild build`: passed。
      - `xcodebuild test`: passed, 188 tests。
      - manual smoke checklist remains pending and unenforced without `--require-manual` evidence bundle。
  - GUI acceptance:
    - `Computer Use get_app_state("com.codegod.desktop")`: worked after launching the rebuilt Debug app.
    - Observed Plot empty-state inspector now shows only `Actions` / disabled `Export` / `Advanced`; `No figure controls` is gone and the disabled Export button is no longer prominent.

## 2026-04-27 (Round BR)

- Scope:
  - Pixelmator-style Plot inspector interaction refactor only; no sidecar contract, render payload, project schema, or inspector width changes.
  - Reworked Plot inspector from one long advanced form into mode-based presentation:
    - `Figure`
    - `Data`
    - `Layers`
    - `Arrange`
  - Added app-only presentation types and subviews:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorMode.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotDataPipelineInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorLayerListView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSelectedLayerEditorView.swift`
  - Slimmed legacy Plot advanced inspector files into wrappers so old full-list editors no longer define the primary interaction:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotDataTransformInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotFunctionLayerInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotShapeAnnotationInspectorView.swift`
  - Strengthened source-level GUI gate:
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`

- User-visible impact:
  - Plot inspector now starts with `Actions`, then a compact mode picker.
  - `Figure` mode holds canvas/style/palette/theme, fit overlay, axis, and legend controls.
  - `Data` mode shows a pipeline summary, add buttons, a variable/transform list, and one selected editor instead of expanding every variable and transform.
  - `Layers` mode shows editable plot objects as a single list: fit overlay, function layers, reference guides, text annotations, shape annotations, and legend entries.
  - `Arrange` mode only shows nudge/drag controls for the selected movable overlay.
  - Text annotations, guides, functions, shapes, and transforms no longer appear as repeated full editor blocks in one vertical scroll.

- Risks:
  - Selection state for data pipeline and non-overlay layer rows is macOS presentation-only and not persisted, by design.
  - Existing reference/text/shape overlay selection fields are still the real session selection for on-canvas operations.
  - Data Studio embeds `PlotInspectorView` for figure styling, so it explicitly disables the Plot mode picker to avoid changing Data Studio IA in this round.
  - Manual desktop GUI acceptance was attempted but blocked by Computer Use window capture instability; do not treat this as a manual smoke pass.

- Rollback points:
  - Mode shell:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorMode.swift`
  - Data mode:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotDataPipelineInspectorView.swift`
  - Layer/Arrange mode:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorLayerListView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSelectedLayerEditorView.swift`
  - Gate additions:
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`

- Decision Record:
  - Why:
    - The imported Plot inspector had become a feature dump: transforms, annotations, guides, functions, axis breaks, and fit controls all competed in one scroll.
    - Pixelmator-style interaction solves this by separating task mode, object list, and selected object editor. That maps better to scientific plot editing because the user edits one current object at a time.
  - Rejected alternatives:
    - Keep tuning fonts/spacing in the old advanced form: rejected because it does not solve interaction complexity.
    - Add another nested disclosure layer inside `Advanced Plot`: rejected because it preserves the form-dump mental model.
    - Persist inspector mode/selection into `.sciplotgod`: rejected because this is view presentation state, not project truth.
  - Boundaries:
    - No sidecar routes changed.
    - No `render_options` payload fields changed.
    - No Python rendering semantics changed.
    - Inspector width policy remains `360 / 400 / 460`.

- Validation (executed):
  - Source-level:
    - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
    - `git diff --check`: passed.
    - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py tests/test_blocking_gate.py`: passed, 6 tests.
  - macOS:
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed after fixing one SwiftUI `ShapeStyle` conditional.
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test`: passed, 188 tests.
  - Full gate:
    - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix:
      - `clean_repo`: passed.
      - `ruff`: passed.
      - `mypy`: passed.
      - `pytest`: passed, 275 tests.
      - `smoke_check`: passed.
      - `macos_gui_presentation`: passed.
      - `xcodebuild build`: passed.
      - `xcodebuild test`: passed, 188 tests.
      - manual smoke checklist remains pending and unenforced without `--require-manual` evidence bundle.
  - GUI acceptance:
    - `Computer Use list_apps`: worked and showed `SciPlot God — com.codegod.desktop` running.
    - `Computer Use get_app_state("com.codegod.desktop")`: failed with `Apple event error -10005: cgWindowNotFound`.
    - `Computer Use get_app_state("com.apple.finder")`: timed out after 120s.
    - Conclusion: real desktop acceptance is tool-chain blocked in this run; no manual smoke pass was claimed.

## 2026-04-27 - Plot Tool-Driven Interaction Refactor

- Scope:
  - Replaced Plot's primary inspector mode picker with a tool-driven editing model.
  - Added app-only Plot presentation state:
    - `PlotTool`
    - `PlotCanvasSelection`
    - `PlotObjectListItem`
  - Added a central Plot tool strip for select, pan, fit, guide, text, shape, function, axis break, and secondary-axis tasks.
  - Expanded the Plot left rail from `Source / Data Preparation / Templates` to `Source / Objects / Data Preparation / Templates`.
  - Reworked the Plot inspector into a selection-driven editor. Figure selection shows figure/axis basics; object selection shows one active object editor; movable overlays also show arrange controls.
  - Removed unused wrapper views that preserved the previous list-heavy inspector path:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotDataTransformInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotFunctionLayerInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotShapeAnnotationInspectorView.swift`

- User-visible impact:
  - Plot no longer exposes `Figure / Data / Layers / Arrange` as the main inspector interaction.
  - Import remains a toolbar/menu-level global action; the Plot left rail no longer repeats an `Import Data` button.
  - Left rail now provides a plot object list for Figure, Fit Overlay, function layers, guides, text annotations, shape annotations, and series entries.
  - The central preview has a compact native tool strip, making common editing tasks visible near the figure instead of buried in the inspector.
  - The inspector follows the selected object and avoids showing data pipeline or layer-management lists by default.

- Risks:
  - `PlotCanvasSelection` and `selectedPlotTool` are presentation state only and intentionally not persisted to `.sciplotgod`.
  - The first direct-manipulation pass still uses existing overlay add/select/nudge APIs; true PDF curve hit-testing is not implemented in this round.
  - `Data Cursor` is present as a disabled tool with help because plot hit-testing metadata is not yet part of the public render contract.
  - Data Studio still embeds `PlotInspectorView` with the legacy figure-only path, so this round does not redesign Data Studio internals.

- Rollback points:
  - Tool and selection model:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorMode.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSession.swift`
  - Left rail:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
  - Center stage:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotRefineView.swift`
  - Inspector:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorView.swift`
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotSelectedLayerEditorView.swift`
  - Presentation gate:
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`

- Decision Record:
  - Why:
    - The previous Pixelmator-inspired mode picker improved organization but still forced users into small inspector controls and long property editing.
    - A professional plot editor should follow `tool -> object -> contextual properties`: choose a task near the canvas, select a plot object from the object list, and only then refine the selected object.
  - Rejected alternatives:
    - Make the inspector controls larger: rejected because it preserves the form-first model.
    - Move every advanced feature into left rail buttons: rejected because object properties belong in an inspector.
    - Add PDF curve hit-testing now: rejected because it would require a new render metadata contract and is outside this presentation-only round.
  - Boundaries:
    - No sidecar route changed.
    - No render payload changed.
    - No project schema changed.
    - No plot contract or `nature` metrics changed.
    - Inspector width policy remains `360 / 400 / 460`.

- Validation (executed):
  - Source-level:
    - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py -q`: passed, 2 tests.
    - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
    - `git diff --check`: passed.
    - `.venv/bin/python scripts/clean_repo.py`: passed, reclaimed about 261.5 MB on first run.
    - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py tests/test_blocking_gate.py -q`: passed, 6 tests.
  - macOS:
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed.
    - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test`: passed, 188 tests.
  - Full gate:
    - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
    - Gate details: `clean_repo`, `ruff`, `mypy`, `pytest` 275 tests, `smoke_check`, `macos_gui_presentation`, `xcodebuild build`, and `xcodebuild test` all passed.
    - Manual smoke checklist remains pending and unenforced without `--require-manual` evidence bundle.
  - GUI acceptance:
    - `Computer Use list_apps`: worked and showed `SciPlot God - com.codegod.desktop` running.
    - `Computer Use get_app_state("com.codegod.desktop")`: failed with `Apple event error -10005: cgWindowNotFound`.
    - `Computer Use get_app_state("com.apple.finder")`: timed out after 120s, indicating a tool-chain/window-capture issue rather than a SciPlot-only failure.
    - Local fallback `screencapture -x /tmp/sciplot_tool_interaction_acceptance.png`: produced a black capture, so desktop visual acceptance remains blocked.
    - No manual smoke pass was claimed.

## 2026-04-27 - Plot Canvas Overlay Controls

- Scope:
  - Added a canvas-level floating overlay control HUD in Plot preview.
  - The HUD appears only when the current `PlotCanvasSelection` is a movable overlay:
    - reference guide / region
    - text annotation / callout
    - shape annotation
  - The HUD provides direct nudge controls, delete, and finish-edit actions without requiring the user to move to the right inspector.
  - Strengthened the source-level GUI presentation gate so Plot preview must keep both the tool strip and canvas overlay controls.

- User-visible impact:
  - After adding or selecting a guide, text annotation, or shape, users can move it from the canvas surface using a compact native material HUD.
  - Deleting the selected overlay is now available near the object being edited.
  - The right inspector remains the precise property editor; the canvas HUD handles quick manipulation.

- Risks:
  - Movement still uses existing typed overlay nudge APIs and does not implement PDF hit testing.
  - The HUD is intentionally limited to movable overlays; fit overlay, function layers, and series entries still use the object list and selection inspector.

- Rollback points:
  - Canvas HUD:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotRefineView.swift`
  - Presentation gate:
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`

- Decision Record:
  - Why:
    - The previous tool-driven refactor moved task entry out of the inspector, but selected overlays still required inspector-side arrange controls for quick movement.
    - Pixelmator-style editing expects the selected object to expose immediate contextual controls near the canvas.
  - Rejected alternatives:
    - Put another Arrange toolbar in the right inspector: rejected because it keeps the click-heavy inspector-first loop.
    - Add true drag handles on the rendered PDF: rejected for this round because it requires hit-test/render metadata not currently in the public contract.
  - Boundaries:
    - No sidecar route changed.
    - No render payload changed.
    - No project schema changed.
    - No plot contract or `nature` metrics changed.

- Validation (executed so far):
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py -q`: passed, 2 tests.
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `git diff --check`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
  - Gate details: `clean_repo`, `ruff`, `mypy`, `pytest` 275 tests, `smoke_check`, `macos_gui_presentation`, `xcodebuild build`, and `xcodebuild test` all passed.
  - Desktop GUI acceptance remains blocked by the same window capture/tool-chain failure recorded above.

## 2026-04-27 - Plot Tool Command Validation Fix

- Scope:
  - Reviewed the recent Pixelmator-style Plot tool interaction for macOS-native command behavior.
  - Fixed an interaction bug where tool buttons used bare single-key shortcuts (`V/H/F/...`) directly on toolbar buttons.
  - Moved Plot tool shortcuts into a native `Plot Tools` command menu using `Command + Option` combinations.
  - Kept the on-canvas tool strip as visible pointer UI only, so text fields in the Tool Options Bar and inspector are less likely to lose typed characters to tool switching.
  - Centralized Plot tool availability and activation in `PlotSession`:
    - `plotToolAvailability(for:)`
    - `activatePlotTool(_:)`

- User-visible impact:
  - Plot tools are now discoverable through the macOS menu bar, matching desktop pro-app expectations.
  - Tool shortcuts no longer use bare character keys that can conflict with text/function input.
  - Disabled tool commands follow the same availability rules as the visible tool strip.

- Bug / unreasonable behavior found:
  - Bare tool shortcuts were too aggressive for a macOS document/editor surface because Plot also has text-entry fields for annotations, functions, labels, and numeric controls.
  - `Command + Option + I` was already owned by the app-level inspector toggle, so `Data Cursor` intentionally has no command shortcut until hit-testing exists.

- Rollback points:
  - Tool command routing:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/App/AppCommands.swift`
  - Tool activation / availability:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorMode.swift`
  - Presentation gate:
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`

- Decision Record:
  - Why:
    - Apple-style Mac apps expose pro actions through commands and menus; bare key shortcuts should not steal ordinary text input.
    - Centralizing activation avoids future drift between toolbar buttons and menu commands.
  - Rejected alternatives:
    - Keep bare keys and rely on focus behavior: rejected because SwiftUI button shortcuts can still behave too broadly in text-heavy surfaces.
    - Hide shortcuts entirely: rejected because pro tools benefit from command discoverability and keyboard workflows.
    - Implement a custom responder-chain keyboard router immediately: rejected for this round because native commands solve the verified conflict with less AppKit surface.
  - Boundaries:
    - No sidecar route changed.
    - No render payload changed.
    - No project schema changed.
    - No plot contract or `nature` metrics changed.

- Validation (executed so far):
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py -q`: passed, 2 tests.
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `git diff --check`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
  - Gate details: `clean_repo`, `ruff`, `mypy`, `pytest` 275 tests, `smoke_check`, `macos_gui_presentation`, `xcodebuild build`, and `xcodebuild test` 188 tests all passed.
  - Manual smoke checklist remains pending and unenforced without `--require-manual` evidence bundle.
  - Desktop GUI acceptance:
    - `open -n app/macos/.derivedData/Build/Products/Debug/SciPlot God.app`: launched without terminal error.
    - `Computer Use list_apps`: showed `SciPlot God - com.codegod.desktop` running.
    - `Computer Use get_app_state("com.codegod.desktop")`: failed with `Apple event error -10005: cgWindowNotFound`.
    - `Computer Use get_app_state("com.apple.finder")`: failed with `errAETimeout`, so the capture issue is not isolated to SciPlot God.
    - No manual GUI smoke pass was claimed.

## 2026-04-27 - Plot Tool Options Bar

- Scope:
  - Added a lightweight canvas-level Tool Options Bar below the Plot tool strip.
  - Added single-key shortcuts to the Plot tool strip:
    - `V` Select
    - `H` Pan
    - `I` Cursor
    - `F` Fit
    - `G` Guide
    - `T` Text
    - `S` Shape
    - `U` Function
    - `B` Axis Break
    - `Y` Secondary Y
  - Tool options are intentionally contextual and short:
    - `Fit`: visibility and model
    - `Guide`: line/region and axis target
    - `Text`: text value and text/callout style
    - `Shape`: rectangle/ellipse/bracket
    - `Function`: expression and Y-axis target
    - `Axis Break`: add X/Y break
    - `Secondary Y`: enable/disable secondary Y axis
  - Strengthened the GUI presentation gate so the Plot preview must retain the tool options bar and keyboard shortcut affordances.

- User-visible impact:
  - Plot editing moves another step away from the right-inspector-first loop.
  - Choosing a tool now exposes the small set of choices needed for that tool near the canvas, while the inspector remains the precise selected-object editor.
  - Common Plot tool selection is available from the keyboard, matching pro Mac editor expectations.

- Risks:
  - Tool shortcuts are single-key SwiftUI shortcuts scoped to the visible tool buttons; future command-menu integration may be needed if global routing becomes necessary.
  - The Tool Options Bar edits existing typed payload fields only; it still does not add PDF hit-testing or direct drag handles.

- Rollback points:
  - Tool shortcuts:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorMode.swift`
  - Tool options bar:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotRefineView.swift`
  - Presentation gate:
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`

- Decision Record:
  - Why:
    - Pixelmator-style tools are not just icons; the active tool exposes a small contextual option surface near the canvas.
    - This reduces tiny inspector hunting without duplicating global Import/Export or moving business workflow into the canvas.
  - Rejected alternatives:
    - Put these controls back into the right inspector: rejected because it preserves the form-first workflow.
    - Add a large permanent toolbar across the stage: rejected because it would recreate chrome clutter.
    - Add true object hit testing now: rejected because it needs a render metadata contract and is not presentation-only.
  - Boundaries:
    - No sidecar route changed.
    - No render payload changed.
    - No project schema changed.
    - No plot contract or `nature` metrics changed.
    - Inspector width policy remains `360 / 400 / 460`.

- Validation (executed so far):
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py -q`: passed, 2 tests.
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `git diff --check`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
  - Gate details: `clean_repo`, `ruff`, `mypy`, `pytest` 275 tests, `smoke_check`, `macos_gui_presentation`, `xcodebuild build`, and `xcodebuild test` 188 tests all passed.
  - Manual smoke checklist remains pending and unenforced without `--require-manual` evidence bundle.
  - Desktop GUI acceptance:
    - `open -n app/macos/.derivedData/Build/Products/Debug/SciPlot God.app`: launched without terminal error.
    - `Computer Use list_apps`: showed `SciPlot God - com.codegod.desktop` running.
    - `Computer Use get_app_state("com.codegod.desktop")`: failed with `Apple event error -10005: cgWindowNotFound`.
    - `Computer Use get_app_state("com.apple.finder")`: failed with `errAETimeout`, so the capture issue is not isolated to SciPlot God.
    - No manual GUI smoke pass was claimed.

## 2026-04-27 - Plot Overlay Keyboard Nudge

- Scope:
  - Extended the Plot canvas overlay HUD for movable overlays:
    - reference guides / regions
    - text annotations / callouts
    - shape annotations
  - Added `Option + Arrow` keyboard nudging to the HUD's directional controls.
  - Added a compact monospaced position readout inside the HUD:
    - guide value or region span
    - text annotation x/y
    - shape center x/y
  - Strengthened the GUI presentation gate so the Plot preview must retain keyboard nudge affordances and position feedback.

- User-visible impact:
  - Selected overlays can now be nudged from the keyboard without moving attention to the right inspector.
  - The HUD gives immediate positional feedback without turning the canvas into another dense form.
  - The right inspector remains the exact editor for detailed values.

- Risks:
  - Keyboard nudge is routed through SwiftUI button shortcuts and is scoped to the HUD being present.
  - Text fields in the tool options bar may still capture normal typing focus; the nudge shortcut intentionally uses `Option + Arrow` to reduce conflict.
  - This still uses existing typed nudge APIs and does not add PDF/object hit-testing metadata.

- Rollback points:
  - Canvas HUD:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotRefineView.swift`
  - Presentation gate:
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`
    - `/Users/dongxutian/Documents/codegod/tests/test_check_macos_gui_presentation.py`

- Decision Record:
  - Why:
    - Pixelmator-style direct manipulation is partly keyboard-driven: once an object is selected, small movement should not require inspector hopping.
    - `Option + Arrow` gives a conservative pro-editor shortcut without colliding with normal arrow-key caret movement as aggressively as bare arrows.
  - Rejected alternatives:
    - Bare arrow nudging: rejected because it would conflict more often with text fields and native focus movement.
    - Delete-key deletion: rejected for this round because destructive object removal deserves a more explicit confirmation/command model before becoming a keyboard shortcut.
    - True drag handles: still rejected until render hit-test metadata exists.
  - Boundaries:
    - No sidecar route changed.
    - No render payload changed.
    - No project schema changed.
    - No plot contract or `nature` metrics changed.
    - Inspector width policy remains `360 / 400 / 460`.

- Validation (executed so far):
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py -q`: passed, 2 tests.
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `git diff --check`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData build`: passed.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
  - Gate details: `clean_repo`, `ruff`, `mypy`, `pytest` 275 tests, `smoke_check`, `macos_gui_presentation`, `xcodebuild build`, and `xcodebuild test` 188 tests all passed.
  - Manual smoke checklist remains pending and unenforced without `--require-manual` evidence bundle.
  - Desktop GUI acceptance remains blocked by the same window capture/tool-chain failure recorded above.

## 2026-04-27 - Plot Tool Acceptance Sweep

- Scope:
  - Audited the Plot tool-driven interaction for user-visible bugs and unreasonable behavior.
  - Fixed the biggest issue found in source/test validation: Plot tool activation no longer creates or enables plot objects by itself.
  - Moved object creation behind explicit tool option actions:
    - `Add Guide`
    - `Add Text`
    - `Add Shape`
    - `Add Function`
  - Kept `Fit`, `Axis Break`, and `Secondary Y` as edit tools with explicit toggle/add controls, instead of creating payload on shortcut/tool selection.
  - Removed redundant empty Plot chrome:
    - The central tool strip is hidden until a Plot source exists.
    - The left Plot rail now shows only the `Source` hint before import; `Objects`, `Data Preparation`, and `Templates` appear after a source exists.
  - Replaced the invalid `axis.arrow` SF Symbol with `arrow.left.and.right`.

- User-visible impact:
  - Pressing a Plot tool shortcut or clicking a tool no longer silently adds overlays/functions/axis features.
  - The empty Plot state is quieter and no longer repeats the import prompt across several sections.
  - Axis Break now has a valid system icon.
  - The tool options bar exposes object creation as an intentional action, closer to the Pixelmator-style distinction between choosing a tool and creating/editing an object.

- Risks:
  - Because true PDF/object hit testing is still out of scope, adding an overlay still happens through an explicit `Add` control rather than direct click-to-place on the canvas.
  - Existing imported-state workflows should be preserved, but users who expected one-click tool creation will now use the Add button.
  - Hosted XCTest still logs an AppKit split-view constraint warning around inspector safe-area geometry; tests pass, and the required `360 / 400 / 460` inspector width policy was not changed.

- Rollback points:
  - Tool model and icon:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotInspectorMode.swift`
  - Canvas tool options and empty-state visibility:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotRefineView.swift`
  - Left source/library rail:
    - `/Users/dongxutian/Documents/codegod/app/macos/Sources/Features/Plot/PlotTemplateView.swift`
  - Regression coverage:
    - `/Users/dongxutian/Documents/codegod/app/macos/Tests/PlotSessionTests.swift`
    - `/Users/dongxutian/Documents/codegod/scripts/check_macos_gui_presentation.py`

- Decision Record:
  - Why:
    - Tool activation and object creation are different user intents in pro macOS editors. Conflating them made keyboard shortcuts and repeated clicks dangerous.
    - Empty states should describe only the next useful step, not duplicate the same import state in every panel.
  - Rejected alternatives:
    - Keep one-click tool creation: rejected because it silently mutates the figure and can create duplicates.
    - Add true click-to-place now: rejected because it needs reliable canvas/PDF hit testing metadata and would cross the current presentation-only boundary.
    - Remove tool shortcuts entirely: rejected because native command shortcuts are useful once they are side-effect-free.
  - Boundaries:
    - No sidecar route changed.
    - No render payload changed.
    - No project schema changed.
    - No plot contract or `nature` metrics changed.
    - Inspector width policy remains `360 / 400 / 460`.

- Validation (executed so far):
  - `.venv/bin/python -m pytest tests/test_check_macos_gui_presentation.py -q`: passed, 2 tests.
  - `.venv/bin/python scripts/check_macos_gui_presentation.py`: passed.
  - `git diff --check`: passed.
  - `xcodebuild -project app/macos/SciPlotGod.xcodeproj -scheme SciPlotGodMac -destination 'platform=macOS,arch=arm64' -derivedDataPath app/macos/.derivedData test -only-testing:SciPlotGodMacTests/PlotSessionTests/testActivatingPlotToolsDoesNotCreatePlotObjects`: passed, 1 test.
  - The rerun no longer emitted the invalid `axis.arrow` SF Symbol warning.
  - `.venv/bin/python scripts/blocking_gate.py`: passed automated matrix.
  - Gate details: `clean_repo`, `ruff`, `mypy`, `pytest` 275 tests, `smoke_check`, `macos_gui_presentation`, `xcodebuild build`, and `xcodebuild test` 189 tests all passed.
  - Manual smoke checklist remains pending and unenforced without `--require-manual` evidence bundle.
  - Desktop GUI acceptance:
    - `open -n app/macos/.derivedData/Build/Products/Debug/SciPlot God.app`: launched without terminal error.
    - `Computer Use list_apps`: showed `SciPlot God — com.codegod.desktop` running.
    - `Computer Use get_app_state("com.apple.finder")`: timed out after 120 seconds.
    - `Computer Use get_app_state("com.codegod.desktop")`: failed with `Apple event error -10005: cgWindowNotFound`.
    - Manual desktop acceptance remains blocked by the window capture tool chain; no manual smoke pass was claimed.
