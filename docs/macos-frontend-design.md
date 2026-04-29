# macOS Frontend Design Handoff

Date: 2026-04-29

This note describes the supported macOS frontend direction for SciPlot God. It is meant as a handoff guide: use it to understand why the UI is arranged this way, then apply the same principles to future changes without copying any one screenshot literally.

## Product Shape

SciPlot God starts with a lightweight `Launcher` welcome surface. It opens or focuses four singleton module windows: `Plot`, `Data Studio`, `Composer`, and `Code Console`.

The module windows are not tabs inside a global workbench. Each module owns its own window and toolbar context. `Command-1/2/3/4` opens or focuses the matching module, while menu commands route through the currently focused module context.

## Pro Workspace Grammar

The shared spatial model is:

```text
left selection / library  ->  center work area  ->  right inspector
```

Plot adds one extra far-right category rail because it has a real set of adjustment categories. The other modules should not gain a rail until they have genuine category switching that helps the workflow.

The point of this grammar is ordering, not decoration:

- Left: choose the current object or input set.
- Center: do the main work and preview the result.
- Right: refine the selected context and perform follow-up actions.
- Toolbar: own global window/document actions such as import, export, help, launcher, and inspector visibility.

## Launcher

Launcher is a borderless glass welcome surface, not a fake window inside another window. It should stay visually calm: one surface, clear module rows, one real primary action per module, and a custom close affordance.

Launcher must not bootstrap the sidecar just to appear. It should open immediately; sidecar startup belongs to real module work or real actions.

Launcher is also not the owner of Plot's replacement state. If a user starts a Plot import from Launcher while Plot already has content, Launcher opens/focuses Plot and Plot hosts the replacement confirmation. Returning to the welcome surface is an explicit `New Project` action, not a side effect of importing a file.

## Plot

Plot is the visual benchmark. It follows a Pixelmator-Pro-like arrangement while keeping SciPlot concepts:

- Left panel: sheet picker, five recommended plot types from `templateGalleryItems`, and a `More` chooser backed by `plotTypeItems`.
- Center: white figure/page preview. The page stays white in both light and dark app themes so scientific output remains truthful.
- Right inspector: scientific editing, ordered by drawing workflow: Figure, Axes, Legend, Guides, Fit, Functions, Annotations, Advanced Axes.
- Far-right rail: category switcher only. It never creates objects through popovers.

Plot preview uses the backend renderer. Swift displays high-resolution PNG for live preview and keeps PDF as the exact/export-grade fallback; do not recreate plotting semantics in Swift Charts or Canvas.

Legend is a good example of the interaction principle: if the category has one primary useful action, show it directly. `Legend order` and `Reset Series Order` belong at the top level of the Legend inspector. Do not bury them in an `Advanced` disclosure just to make every inspector category look symmetrical.

## Data Studio

Data Studio is a data preparation surface, not a second full plotting app. Its flow is `Import -> Group Review -> Compare Preview -> Export / Open in Plot`.

- Left: workbook groups and figure family/template choice.
- Center: compare/figure preview, focused group status, and the single specimen-filter entry.
- Right: current figure summary, `Open in Plot`, `Analysis`, and output follow-up actions.

When a workflow reaches plot styling or publication-grade graph adjustment, hand it to Plot through the existing `Open in Plot` path.

## Composer

Composer follows `Assets -> Layout -> Compose -> Inspect -> Export`.

- Left: real panel library with `All / Graphs / Assets` filtering and object status.
- Center: composition canvas as the only main object.
- Right: selection, placement, panel state, actions, and preview.

Canvas-local quick actions may remain when they describe the current selection. Global import/export belongs in the toolbar or menu.

## Code Console

Code Console follows `Bind Context -> Prompt/Code -> Run -> Outputs -> Handoff`.

- Left: bound context and sheet picker.
- Center: prompt, code editor, run controls, and output previews/logs.
- Right: binding summary, runner status, output handoff, and advanced source/output reveal actions.

Run, Copy Prompt, Refresh, and Restore Starter are part of the center working surface because they operate on the code being edited.

## Light And Dark Theme

The app defaults to `Follow System` and can be overridden from `View > Appearance`.

Light mode should feel like Codex light: near-white, slightly warm, low gray, and quiet. Avoid large cool-gray stages. Dark mode keeps the current dark professional workspace.

Theme tokens live in `ProWorkspaceTheme`. Do not hard-code theme fills inside module views. If a new view needs a panel, rail, or row surface, use the shared shaped helpers:

- `proGlassPanel(theme:cornerRadius:)`
- `proGlassRail(theme:cornerRadius:)`
- `proGlassRow(theme:isSelected:cornerRadius:)`

These helpers keep fill, clipping, outline, and `glassEffect` on the same rounded shape. This prevents the square background behind rounded panels that appears when a raw `.background(theme.panelFill)` is applied before glass clipping.

## Liquid Glass Rules

Use native SwiftUI glass and system materials first. Custom surfaces are acceptable for the Pro workspace panels, but they must stay shaped and sparse.

Do:

- Use `GlassEffectContainer` when related glass surfaces sit together.
- Pass an explicit rounded shape to `glassEffect`.
- Keep text and control density appropriate for a professional macOS tool.

Avoid:

- Raw rectangular `.background(theme.panelFill)` or `.background(theme.rowFill)` on module panels.
- Hand-rolled blur layers.
- Decorative glass just to make a screen look busier.

## App Icon

The app icon lives in `app/macos/Assets.xcassets/AppIcon.appiconset`. The source artwork is `docs/assets/sciplot-god-app-icon.svg`, and `scripts/generate_app_icon.py` regenerates the PNG sizes.

The concept is an abstract native-style glass squircle with a luminous data-flow curve, small data nodes, and a very soft field/ring hint. It intentionally avoids a literal document, white chart page, window shell, or text so the Dock and App Switcher versions read as an app icon rather than a screenshot.

## Change Checklist

When changing the macOS frontend:

1. Keep module actions real; do not invent fake tools to match another app.
2. Preserve the left / center / right responsibility split.
3. Route global actions through toolbar/menu command context.
4. Use `ProWorkspaceTheme` and shaped glass helpers for custom surfaces.
5. Keep Plot's page preview white across themes.
6. Keep common or sole category actions visible; reserve `Advanced` for real advanced or follow-up work.
7. Run `scripts/check_macos_gui_presentation.py` before considering the UI structure ready.
