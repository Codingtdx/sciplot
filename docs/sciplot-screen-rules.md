# SciPlot Screen Rules

This document defines screen-by-screen layout and behavior rules for the rebuilt SciPlot desktop GUI.

## Global Rules

- Left sidebar is the only primary navigation.
- Each screen must present one dominant workspace.
- No top-row module switching.
- No dashboard, admin, or workbench framing.
- Every screen should feel like a polished desktop tool built from the same shell language.

## AppShell

### Structure

- Titlebar with traffic lights at top left.
- Fixed left sidebar with primary destinations:
- Start
- Plot Import
- Plot Template
- Plot Refine
- Main workspace to the right.
- Optional contextual right inspector only when the current screen needs one.

### Behavior

- Sidebar selection changes the active screen.
- Titlebar actions are contextual only, such as open file, reveal export, or help.
- The shell must not expose legacy module categories or multi-workspace tabs.

## Start

### Purpose

- Fast entry into the plotting workflow.
- Reopen recent datasets or projects.
- Offer clear paths into importing data.

### Layout

- One dominant central sheet.
- Upper section: page title and short supporting line.
- Main block: primary actions such as open dataset, open recent, open sample.
- Secondary block: recent items list with file name, type, last opened, and quick action.
- Optional slim right panel: current environment hints or file-location help only if useful.

### Rules

- Do not turn Start into a dashboard with metrics.
- Do not show every product capability at once.
- Use large calm action cards and a recent-items list with desktop table styling.

## Plot Import

### Purpose

- Load a dataset and confirm what SciPlot detected before the user chooses a chart template.

### Layout

- Main workspace split into two areas:
- Primary content area for dataset source, sheet selection, and data preview
- Secondary context panel for inspection summary, detected structure, and readiness state
- Top of content area: source row with file picker and source metadata
- Middle: sheet selector and table preview
- Bottom: import confirmation area with next-step action

### Rules

- This screen is dataset-centric, not chart-centric.
- Keep the preview table large and readable.
- Treat schema detection and sheet detection as supportive explanations, not walls of diagnostics.
- If recommendations exist, mention them lightly but do not let them dominate this screen.

## Plot Template

### Purpose

- Choose the most suitable chart template from data-driven recommendations.

### Layout

- One dominant recommendation workspace.
- Hero recommendation card at the top or top-left with clear status:
- recommended template name
- confidence or suitability statement
- short reason
- direct continue action
- Alternative templates in a ranked list or secondary card row.
- Side panel or lower panel for data summary and why templates are compatible or disabled.

### Rules

- This screen is recommendation-first.
- Show fewer, larger options with stronger hierarchy.
- The best recommendation must be visually obvious within one glance.
- Disabled templates may appear, but they must read as unavailable and secondary.

## Plot Refine

### Purpose

- Refine a chosen chart and export it from the same screen.

### Layout

- Dominant chart preview area.
- Right-side inspector for refinement controls.
- Lightweight preview toolbar for zoom, fit, and quick export actions.
- Optional bottom strip for warnings, submission checks, or output summary.

### Inspector Sections

- Template summary
- Axes and scales
- Series styling
- Labels and legend
- Size, palette, and style
- Export settings

### Rules

- This screen is chart-centric.
- The preview must visually dominate the layout.
- Export must be inline and always nearby, not buried in a separate closing step.
- Controls should be grouped and calm; do not recreate a form-heavy wizard.

## Mapping Borrowed Desktop Rules To Screens

### Start

- Borrow the quiet sheet layout, soft action cards, muted list styling, and roomy spacing.

### Plot Import

- Borrow the Finder-like content calmness, table clarity, and sidebar-to-content balance.

### Plot Template

- Borrow preference-panel grouping, selected-surface styling, and native control rhythm.

### Plot Refine

- Borrow inspector panel hierarchy, split-pane stability, and compact desktop control styling.

## Prototype Flow

- Default flow:
- Start -> Plot Import -> Plot Template -> Plot Refine

### Prototype Expectations

- Start primary action moves to Plot Import.
- Successful dataset import moves to Plot Template.
- Choosing a recommended or alternate template moves to Plot Refine.
- Back navigation should preserve context where practical.

## Later Refinement Areas

- Detailed empty states
- Progress/loading states
- Error and replacement dialogs
- Keyboard shortcut affordances
- Chart-specific advanced inspector layouts
- High-density table variants for large datasets
