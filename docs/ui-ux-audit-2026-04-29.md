# SciPlot UI/UX Audit

Date: 2026-04-29

This audit reviews the current Pro workspace direction after the Launcher, Plot, Data Studio, Composer, and Code Console unification pass. It is intentionally observational: no extra implementation changes are bundled into this report.

## References Reviewed

- [Pixelmator Pro interface](https://support.apple.com/guide/pixelmator-pro/pixelmator-pro-interface-pix96e754af4/macos): welcome screen, canvas, layers/sidebar, right tools sidebar, contextual tool pane.
- [Origin](https://www.originlab.com/origin): workbook-first scientific graphing, compatible templates, auto-updating graphs and analysis.
- [GraphPad Prism](https://www.graphpad.com/scientific-software/prism/): research-first data, analysis, graph, and layout workflow with live updates.
- [DataGraph](https://apps.apple.com/us/app/datagraph/id407412840): macOS-native graph commands, function commands, curve fits, scalar fields, style/canvas settings.
- [Figma properties panel](https://help.figma.com/hc/en-us/articles/360039832014-Design-prototype-and-explore-layer-properties-in-the-right-sidebar): canvas-centered workspace with detached left/right panels.
- [Keynote sidebars](https://support.apple.com/guide/keynote/show-or-hide-sidebars-tan391376b09/mac): right inspector categories for Format, Animate, and Document.
- [VS Code user interface](https://code.visualstudio.com/docs/getstarted/userinterface): left context navigation, central editor, bottom outputs, optional sidebars.
- [JupyterLab interface](https://jupyterlab.readthedocs.io/en/stable/user/interface.html): main work area with left sidebar and document/activity tabs.

## Reasonable

- Plot now has the strongest interaction model: data/sheet and plot type on the left, white preview page in the middle, precise scientific adjustments on the right, and a far-right category rail. This matches the Pixelmator Pro grammar without inventing fake image tools.
- Data Studio is correctly narrowing toward data preparation. It should not own full plot styling long-term; its strongest role is import, workbook grouping, specimen selection, compare preview, and handoff into Plot.
- The independent singleton window model is a better fit than the old global module switcher. It gives each module a stable mental model and keeps Command-1/2/3/4 meaningful.
- Keeping import/export in the native toolbar is right. It avoids putting global document actions into local selection panels and keeps the Mac app feeling desktop-native.
- Composer's real model is panel library -> canvas -> inspector. The current structure maps cleanly onto Figma/Keynote-style object editing.
- Code Console's real model is context -> prompt/code -> outputs -> handoff. This aligns better with VS Code/Jupyter than with a plotting inspector.

## Needs attention

- Launcher now has the right borderless welcome-surface direction, but it still reads a little like a four-row list. The next refinement should raise contrast on the active action and give the module rows a more intentional hierarchy.
- Empty states in professional workspaces should be mostly quiet. Large bottom-left prompts such as import hints make the app feel like a tutorial instead of a tool.
- Data Studio's center preview is visually close to Plot, but the left rail still risks becoming a status bucket. Keep it strictly to workbook groups and figure choice.
- Plot preview clarity is improved by high-resolution PNG rendering, but the app still needs visual QA at common Retina window sizes to confirm text, ticks, and lines are crisp.
- Composer's canvas should eventually get the same stage polish as Plot: a stronger document boundary, quieter grid treatment, and less inspector dependence for basic selection feedback.
- Code Console still has the most utilitarian feel. It should remain denser than Plot, but the prompt/editor/output cards should align more with the Pro workspace surface rhythm.
- Toolbar icon grouping is a recurring risk. The primary action group should stay right-weighted and not accumulate module-specific clutter.
- Disabled controls are necessary, but they should explain themselves through help text rather than occupying first-screen visual space.

## Priority Recommendations

1. Keep Plot as the product-wide visual benchmark.
2. Treat Data Studio as a preparation surface that hands off to Plot as early as possible.
3. Keep Composer and Code Console visually aligned, but do not force a Plot-style adjustment rail unless their real workflows need one.
4. Reserve visible text for object labels, parameter labels, and document state. Avoid instructional copy in the primary workspace.
5. Continue comparing future changes against Pixelmator Pro for spatial grammar, Origin/Prism/DataGraph for scientific workflow, and VS Code/Jupyter for console ergonomics.
