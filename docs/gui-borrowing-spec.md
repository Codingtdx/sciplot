# SciPlot GUI Borrowing Spec

This document captures the desktop UI rules borrowed from the macOS 26 reference file and translates them into concrete implementation constraints for the SciPlot rebuild.

Reference basis:
- Source: macOS 26 community reference
- Scope used: one single screenshot read of the provided node
- Purpose: visual borrowing only, not workflow borrowing

## Borrow Directly

### Shell Structure

- Use a single floating desktop window with generous corner radius, soft shadow, and a clearly separated chrome region.
- Use a left sidebar as the only primary navigation surface.
- Keep one dominant workspace canvas to the right of the sidebar; no multi-column admin shell.
- Use a slim top toolbar inside the content window for contextual actions only, not module switching.
- Keep the shell centered inside a calm desktop backdrop with enough outer margin to preserve the desktop-app feeling.

### Window Chrome Language

- Use a dedicated titlebar band with macOS-style traffic lights at top left.
- Keep the titlebar visually light and quiet; it should frame the product rather than compete with content.
- Use subtle top-edge highlight and low-contrast separators instead of heavy borders.
- Use translucent or near-translucent chrome fills layered over a soft neutral background.

### Sidebar Behavior

- Sidebar width should feel fixed and stable, around a compact desktop-navigation width, not a collapsible web-app rail.
- Sidebar groups should be stacked with roomy vertical spacing and compact internal padding.
- Navigation items should use rounded-rectangle selection backgrounds, soft hover fills, and low-contrast icon + label pairs.
- Active state should be visibly filled and elevated, not only color-tinted text.
- Sidebar footer can host secondary destinations such as Settings, but these must remain visually subordinate.

### Surface Hierarchy

- Use a three-level surface stack:
- Level 0: outer desktop/window shell
- Level 1: primary workspace sheet
- Level 2: internal cards, inspectors, tables, and tool sections
- Prefer soft tonal contrast and shadow separation over border-heavy segmentation.
- Keep content regions large and calm; avoid tiling many equal cards across the screen.

### Spacing Rhythm

- Use a roomy desktop rhythm rather than dense productivity spacing.
- Favor 8 px as the base step, with 12, 16, 20, 24, 32 px used repeatedly.
- Keep outer shell padding larger than internal component padding.
- Use consistent panel gutters so the screen reads as a deliberate product surface rather than a stack of unrelated boxes.

### Typography Tone

- Use a macOS-like text hierarchy: quiet labels, medium-emphasis section titles, strong but not oversized page titles.
- Keep typography neutral and system-like; do not introduce expressive editorial typography in this pass.
- Use subdued secondary text for helper copy and metadata.
- Prefer hierarchy through weight, opacity, and spacing rather than large font jumps.

### Controls

- Buttons should be rounded, compact, slightly elevated, and clearly desktop-native rather than web-pill marketing buttons.
- Primary actions should use saturated accent fill with white text.
- Secondary actions should use soft filled neutrals, not outline-only buttons by default.
- Inputs, dropdowns, and segmented controls should sit on soft inset surfaces with subtle borders and inner padding.
- Popovers and sheets should feel like floating desktop layers with shadow, radius, and dense action grouping.

### Table Styling

- Use wide row height, soft grid separation, and strong alignment rather than dense spreadsheet visuals.
- Keep header rows quiet and utility-like.
- Selected rows should use filled highlight, not only a left border or checkmark.
- Treat tables as content panels inside the workspace, not as full-window spreadsheet replacements unless the screen specifically demands it.

### Inspector And Panel Styling

- Inspectors should be narrow, padded side panels with grouped sections and soft card subdivision.
- Group labels should be small and low emphasis.
- Inline settings should feel like native inspector rows, not form-builder stacks.
- Prefer toggles, dropdowns, steppers, and segmented controls over freeform raw input where possible.

## Do Not Borrow

- Do not copy Finder or System Settings information architecture.
- Do not copy multi-window OS workflows into the product.
- Do not copy desktop wallpaper or OS chrome as literal product background content.
- Do not use top-row app switching tabs as primary navigation.
- Do not inherit file-browser-first workflows when SciPlot needs dataset-first and chart-first flows.
- Do not reproduce empty demo windows or generic settings pages that weaken the product-specific flow.
- Do not overuse translucency if it reduces chart readability.

## Product Mapping

### AppShell

- Borrow the floating macOS-style window, titlebar, traffic lights, soft radius, shadow, and fixed left sidebar.
- Replace OS app categories with SciPlot navigation only: Start, Plot Import, Plot Template, Plot Refine.
- Keep the main workspace broad and calm, with optional right-side contextual inspector only when the screen needs one.

### Start

- Borrow the quiet workspace sheet, large breathing room, soft grouped action cards, and desktop empty-state tone.
- Do not make Start a dashboard.
- Use a single dominant start surface with recent datasets, primary entry actions, and lightweight onboarding cues.

### Plot Import

- Borrow Finder-like list/table clarity and panel calmness, but not Finder workflow structure.
- Center the screen on dataset intake: source selection, detected sheets, dataset summary, and import readiness.
- Keep the dominant area as a dataset browser/preview workspace with a compact context panel.

### Plot Template

- Borrow selection fills, grouped panels, and preference-sheet tone.
- Make recommendations the main content, with one clearly preferred template and a ranked set of alternatives beneath or beside it.
- Avoid gallery chaos; use fewer, larger recommendation cards.

### Plot Refine

- Borrow inspector rhythm, native control styling, and stable split-pane hierarchy.
- Make the chart preview the dominant surface.
- Put export inline in the chart workflow, not as a distant terminal step.
- Keep controls in a right inspector or bottom utility strip, but never overpower the preview canvas.

## Implementation Notes

- Start implementation from shell and component primitives, not from old SciPlot screens.
- Preserve the borrowed desktop language consistently across all screens before adding feature-specific variations.
- If a screen needs a new component, style it as if it belongs to the borrowed macOS desktop family first, then adapt for SciPlot semantics.
