# SciPlot Design System Rules

This document defines the first-pass local design rules for rebuilding SciPlot with the borrowed macOS 26 desktop language.

## Core Tokens

### Color Roles

- `window-bg`: soft cool-neutral base for the outer shell
- `chrome-bg`: slightly translucent light neutral for titlebar and sidebar
- `workspace-bg`: clean low-tint surface for the main content region
- `panel-bg`: slightly raised surface for cards, inspectors, and tables
- `panel-bg-strong`: selected or emphasized card background
- `border-subtle`: low-contrast separator line
- `text-primary`: strong neutral text
- `text-secondary`: muted neutral text
- `text-tertiary`: quiet metadata text
- `accent`: primary interactive blue
- `accent-hover`: darker accent for hover/pressed state
- `accent-soft`: low-alpha accent fill for selected secondary surfaces
- `success`, `warning`, `danger`: semantic status colors with restrained saturation

### Radius

- Outer window: large radius
- Main cards and panels: medium radius
- Controls: medium-to-small radius
- Pills and selection chips: pill radius only where explicitly needed

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

- Use one centered window frame, not edge-to-edge browser layout.
- Keep titlebar, sidebar, and workspace visually continuous inside one rounded shell.
- Use sidebar on the left, dominant content on the right, optional inspector only when needed.

### Sidebar

- Fixed-width left column.
- Group primary destinations in one clear stack.
- Use icon plus label rows with filled active state.
- Keep sidebar content vertically aligned with titlebar and workspace padding.

### Workspace

- Each screen gets one dominant content region.
- Avoid equal-weight card mosaics.
- Prefer large sheets, split panes, and anchored inspectors over dashboard grids.

### Panels

- Panels should read as nested desktop surfaces.
- Use light separators and surface contrast before introducing borders.
- Every panel needs a clear internal title or role.

## Typography Rules

- Use the platform-neutral, system-like stack already available to the implementation environment.
- Page title: strong weight, compact line height.
- Section title: medium weight.
- Body copy: standard readable size with neutral contrast.
- Helper text: smaller or lower-contrast, never louder than section titles.
- Data labels and inspector labels should be compact and quiet.

## Component Rules

### Buttons

- Primary button: filled accent, white label, medium radius, compact height.
- Secondary button: soft neutral fill, primary text, same height as primary.
- Tertiary button: text or ghost only for inline utility actions.
- Destructive button: only where needed, use restrained red fill or text.

### Inputs

- Use soft filled or lightly bordered fields.
- Keep field height consistent across text input, dropdown, and combo controls.
- Use subtle inset feel, not harsh outlines.
- Labels should sit above or to the left depending on inspector density.

### Dropdowns And Menus

- Closed state should resemble native desktop pop-up buttons.
- Open menus should use floating rounded surfaces with shadow and tight vertical rhythm.
- Use checkmark or filled-row selection, not web-style menu chips.

### Segmented Controls

- Use for binary or short-range mode switching inside a screen.
- Keep them compact and slightly inset.
- Never use segmented controls as the app’s primary navigation.

### Checkboxes, Toggles, Steppers

- Keep them native-feeling and compact.
- Use toggles for persistent state, checkboxes for list options, steppers for small numeric adjustments.
- Avoid raw numeric text fields when a stepper or preset selector fits the task.

### Popovers And Sheets

- Use popovers for local option clusters or quick confirmations.
- Use sheets/modals for file replacement, destructive confirmation, and focused multi-step decisions.
- Keep modal copy short and action-oriented.

### Tables

- Use roomy row height and clear text alignment.
- De-emphasize grid lines.
- Keep headers muted.
- Support selected-row fill and hover highlight.
- Use status chips sparingly inside rows.

### Preview Pane

- Preview should sit on the calmest and brightest surface on Plot Refine.
- The preview frame can use a subtle inset or shadow to separate it from surrounding controls.
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

### Start

- Use large launch cards, recent items list, and one clear primary action.
- Avoid metrics, analytics, or admin widgets.

### Plot Import

- Use one dominant dataset intake region with structured source rows, dataset preview, and import action.
- Treat sheet and dataset metadata as organized supporting panels.

### Plot Template

- Use recommendation cards with clear hierarchy: top recommendation first, alternates second.
- Use side notes for rationale and compatibility.

### Plot Refine

- Give the chart preview the most area.
- Attach export to the preview workflow with visible but non-intrusive placement.
- Use inspector controls for axes, styling, legend, labels, and output settings.

## Non-Goals For This Pass

- No bespoke brand visual language yet.
- No ornamental gradient-heavy marketing treatment inside work surfaces.
- No dashboard widgets unless required by a specific workflow.
- No legacy GUI structure carried forward only for familiarity.
