# SciPlot Design System Rules

This document defines the first-pass local design rules for the retained four-workbench desktop product model.

## Core Tokens

### Color Roles

- `window-bg`: soft cool-neutral base for the outer shell
- `chrome-bg`: slightly translucent light neutral for titlebar and sidebar
- `workspace-bg`: clean low-tint surface for the main content region
- `panel-bg`: slightly raised surface for cards, inspectors, tables, and utility panes
- `panel-bg-strong`: selected or emphasized card background
- `border-subtle`: low-contrast separator line
- `text-primary`: strong neutral text
- `text-secondary`: muted neutral text
- `text-tertiary`: quiet metadata text
- `accent`: primary interactive blue
- `accent-hover`: darker accent for hover and pressed state
- `accent-soft`: low-alpha accent fill for selected secondary surfaces
- `success`, `warning`, `danger`: restrained semantic status colors

### Radius

- Outer window: large radius
- Main cards and panels: medium radius
- Controls: medium-to-small radius
- Pills and chips: use sparingly

### Shadow

- Window shadow: broad, soft, low-opacity
- Floating panel shadow: tighter and slightly stronger than window internals
- Controls: minimal or none unless they are primary CTAs or popovers

### Spacing Scale

- Use `8` as the base unit
- Preferred steps: `8`, `12`, `16`, `20`, `24`, `32`
- Outer shell padding: `20` to `24`
- Main panel padding: `16` to `20`
- Compact row padding: `10` to `12`
- Vertical section gaps: `16` or `24`

## Layout Rules

### App Window

- Use one centered window frame, not an edge-to-edge browser layout.
- Keep titlebar, sidebar, and workspace visually continuous inside one rounded shell.
- Use sidebar on the left, dominant content on the right, optional inspector only when needed.

### Sidebar

- Fixed-width left column.
- Group only the four primary workbenches in the main navigation stack.
- Use icon-plus-label rows with filled active state.
- Keep utility actions visually subordinate to primary workbench navigation.

### Workspace

- Each workbench gets one dominant content region.
- Avoid equal-weight card mosaics.
- Prefer large sheets, split panes, canvases, and anchored inspectors over dashboard grids.

### Panels

- Panels should read as nested desktop surfaces.
- Use light separators and surface contrast before introducing borders.
- Every panel needs a clear internal title or role.

## Typography Rules

- Use the platform-neutral, system-like stack already available to the implementation environment.
- Page title: strong weight, compact line height.
- Section title: medium weight.
- Body copy: readable size with neutral contrast.
- Helper text: smaller or lower-contrast, never louder than section titles.
- Data labels, table headers, and inspector labels should be compact and quiet.

## Component Rules

### Buttons

- Primary button: filled accent, white label, medium radius, compact height.
- Secondary button: soft neutral fill, primary text, same height as primary.
- Tertiary button: text or ghost only for inline utility actions.
- Destructive button: only where needed, with restrained red treatment.

### Inputs

- Use soft filled or lightly bordered fields.
- Keep field height consistent across text input, dropdown, and combo controls.
- Use subtle inset feel, not harsh outlines.
- Labels should sit above or to the left depending on inspector density.

### Dropdowns And Menus

- Closed state should resemble native desktop pop-up buttons.
- Open menus should use floating rounded surfaces with shadow and tight vertical rhythm.
- Use checkmark or filled-row selection, not web-style chips.

### Segmented Controls

- Use for short-range local mode switching inside a workbench.
- Keep them compact and slightly inset.
- Never use segmented controls as the app's primary navigation.

### Checkboxes, Toggles, Steppers

- Keep them native-feeling and compact.
- Use toggles for persistent state, checkboxes for list options, steppers for small numeric adjustments.
- Avoid raw numeric text fields when a stepper or preset selector fits the task.

### Popovers And Sheets

- Use popovers for local option clusters or quick confirmations.
- Use sheets or modals for replacement warnings, destructive confirmation, and focused multi-step decisions.
- Keep modal copy short and action-oriented.

### Tables

- Use roomy row height and clear text alignment.
- De-emphasize grid lines.
- Keep headers muted.
- Support selected-row fill and hover highlight.
- Use status chips sparingly inside rows.

### Preview Pane

- Plot preview should sit on the calmest and brightest surface within Plot Refine.
- The preview frame can use subtle inset or shadow to separate it from surrounding controls.
- Toolbars attached to preview must remain lightweight.

### Inspector

- Inspector sections should stack vertically with `16` to `20` px gaps.
- Each section may contain small grouped cards or row clusters.
- Controls inside the inspector should align to a stable label/value rhythm.

## Interaction Rules

- Hover states should be soft fill or slight tonal lift.
- Pressed states should darken or inset slightly.
- Focus states should use a restrained accent ring.
- Selection states should be filled and obvious.
- Disabled states should lower contrast without disappearing.

## Screen-Level Usage

### Plot

- Use a dominant data-or-preview surface depending on the local step.
- Import should emphasize source binding, sheet selection, and data preview.
- Template should emphasize ranked compatible recommendations.
- Refine should give preview the most area and keep export nearby.

### Data Cleanup

- Use structured intake panels, readable compare tables, and explicit transformation stages.
- Present detection and cleanup guidance as workflow support, not as walls of diagnostics.
- Keep `Open in Plot` visible, but subordinate to the cleanup workflow itself.

### Composer

- Give the canvas the most area.
- Treat asset trays, layer lists, and inspectors as supporting surfaces around the canvas.
- Keep review and export tied closely to the composition surface.

### Code Console

- Give code and run results a strong, serious surface.
- Keep bound context and inspection visible, but secondary to the prompt/code and output loop.
- Outputs should clearly separate logs, generated files, and handoff actions.

### Utilities

- Quick open, recents, open/save, managed files, and runtime controls should use secondary placement and quieter styling.
- Do not style utilities like equal peers to the four workbenches.

## Non-Goals For This Pass

- No bespoke marketing skin.
- No ornamental gradient-heavy treatment inside work surfaces.
- No dashboard widgets unless required by a specific workflow.
- No restoration of `Start`, `Project`, or `Settings` as primary app destinations.
- No shell logic that treats the protected Plot mock as the whole product model.
