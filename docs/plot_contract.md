# CodeGod Plot Contract

- Version: `3`
- Default style: `default`
- Default palette: `colorblind_safe`

## Global Frame

- Standard panel: `60.0 x 55.0 mm`
- Margins: left `14.0 mm`, right `4.5 mm`, bottom `11.0 mm`, top `5.5 mm`

## Axis Policy

- Linear axis nice steps: `1`, `2`, `5`
- Linear outer padding: `5.0%` on standard axes
- Force labeled linear endpoints visible: `True`
- Log display steps: `1`, `2`, `5`
- Log label mode: `decade_only`
- Log allows unlabeled outer padding: `True`
- Bar zero-baseline lower padding disabled: `True`
- Tensile y-axis includes zero: `True`
- Stacked x-axis uses standard endpoint policy: `True`

## Templates

## QA Profiles

- `alignment`: `preserve_shared_axis_frame`=True, `single_panel_width_mm`=60.0, `single_panel_height_mm`=55.0, `double_panel_width_mm`=120.0
- `curve`: `small_panel_width_mm`=60.0, `small_panel_height_mm`=55.0, `direct_label_max_series`=4, `compact_direct_label_inset_fraction`=0.04, `compact_direct_label_offset_pt`=4.0, `compact_direct_label_search_band_fraction`=0.12, `compact_tick_width_scale`=0.82, `compact_tick_length_scale`=0.88, `compact_legend_max_series`=3, `compact_legend_columns`=2, `compact_legend_font_scale`=0.92, `compact_legend_handlelength`=1.35, `compact_legend_handletextpad`=0.35, `compact_legend_columnspacing`=0.8, `compact_legend_borderpad`=0.15, `legend_area_ratio_warn`=0.055, `legend_area_ratio_fail`=0.07, `dense_marker_point_threshold`=24, `dense_markevery_min`=2, `dense_markevery_max`=6, `dense_marker_scale`=0.88, `dense_tick_width_scale`=0.85, `dense_tick_length_scale`=0.9, `dense_line_width_scale`=0.96, `stroke_hierarchy_target`=0.3, `label_collision_margin_px`=3.0
- `heatmap`: `small_panel_width_mm`=60.0, `small_panel_height_mm`=55.0, `colorbar_x_offset_fraction`=0.29, `colorbar_width_fraction`=0.56, `colorbar_y_offset_fraction`=0.2, `colorbar_height_fraction`=0.1, `colorbar_tick_count`=4, `label_gap_pt`=6.0, `min_label_gap_px`=6.0, `safe_sequential_palettes`=['colorblind_safe', 'deep', 'muted', 'bright', 'mono', 'okabe_ito', 'tol_muted', 'materials_warm']
- `stats`: `min_bar_width`=0.28, `max_bar_width`=0.42, `min_spacing_scale`=1.0, `max_spacing_scale`=1.18, `raw_point_max_groups`=6, `raw_point_max_replicates`=10, `raw_point_size`=11.0, `raw_point_alpha`=0.75, `bar_width_ratio_warn`=0.34, `bar_width_ratio_fail`=0.42, `error_cap_ratio_target`=0.22
- `stacked`: `label_density_warn_per_axis`=5.0, `reserve_tolerance_mm`=1.0
- `composer`: `min_text_size_pt`=6.0, `text_overlap_margin_mm`=1.0, `canvas_margin_mm`=0.5, `binding_overflow_tolerance_mm`=0.25

### `curve` / Curve

- Category: `single_panel`
- Default size: `60x55`
- Allowed sizes: `60x55`, `120x55`
- Editable options: `size`, `xscale`, `yscale`, `reverse_x`, `style_preset`, `palette_preset`
- Description: Standard single-panel curve plot.
- Hard rules: `single_panel_axis_frame`, `non_blank_pdf`
- Soft rules: None

### `point_line` / Point line

- Category: `single_panel`
- Default size: `60x55`
- Allowed sizes: `60x55`, `120x55`
- Editable options: `size`, `xscale`, `yscale`, `reverse_x`, `style_preset`, `palette_preset`
- Description: Standard single-panel curve plot with markers.
- Hard rules: `single_panel_axis_frame`, `non_blank_pdf`
- Soft rules: `multi_output_bundle_notice`

### `stacked_curve` / Stacked curve

- Category: `stacked_spectrum`
- Default size: `60x55`
- Allowed sizes: `60x55`
- Editable options: `size`, `reverse_x`, `baseline`, `style_preset`, `palette_preset`
- Description: Single-column stacked curves for spectrum-like figures.
- Hard rules: `non_blank_pdf`
- Soft rules: None

### `segmented_stacked_curve` / Segmented stacked curve

- Category: `wide_nmr`
- Default size: `60x110`
- Allowed sizes: `60x110`
- Editable options: `size`, `reverse_x`, `baseline`, `style_preset`, `palette_preset`, `use_sidecar`
- Description: Wide NMR double-height panel with left/right/bottom alignment and a reserved structure area on top.
- Hard rules: `wide_nmr_horizontal_alignment`, `wide_nmr_structure_reserve`, `wide_nmr_segment_alignment`, `non_blank_pdf`
- Soft rules: None

### `bar` / Bar

- Category: `single_panel`
- Default size: `60x55`
- Allowed sizes: `60x55`
- Editable options: `size`, `style_preset`, `palette_preset`
- Description: Statistical bar chart.
- Hard rules: `single_panel_axis_frame`, `non_blank_pdf`
- Soft rules: `dense_group_label_warning`

### `box` / Box

- Category: `single_panel`
- Default size: `60x55`
- Allowed sizes: `60x55`
- Editable options: `size`, `style_preset`, `palette_preset`
- Description: Statistical box plot.
- Hard rules: `single_panel_axis_frame`, `non_blank_pdf`
- Soft rules: `dense_group_label_warning`

### `violin` / Violin

- Category: `single_panel`
- Default size: `60x55`
- Allowed sizes: `60x55`
- Editable options: `size`, `style_preset`, `palette_preset`
- Description: Statistical violin plot.
- Hard rules: `single_panel_axis_frame`, `non_blank_pdf`
- Soft rules: `dense_group_label_warning`

### `scatter` / Scatter

- Category: `single_panel`
- Default size: `60x55`
- Allowed sizes: `60x55`, `120x55`
- Editable options: `size`, `xscale`, `yscale`, `reverse_x`, `style_preset`, `palette_preset`
- Description: Single-panel scatter plot.
- Hard rules: `single_panel_axis_frame`, `non_blank_pdf`
- Soft rules: None

### `heatmap` / Heatmap

- Category: `heatmap`
- Default size: `60x55`
- Allowed sizes: `60x55`, `120x55`
- Editable options: `size`, `show_colorbar`, `style_preset`, `palette_preset`
- Description: Heatmap with the main frame aligned to standard single-panel plots and an independent top colorbar.
- Hard rules: `single_panel_axis_frame`, `heatmap_main_frame`, `heatmap_horizontal_colorbar`, `heatmap_colorbar_inside_canvas`, `non_blank_pdf`
- Soft rules: None

## Validation Rules

- `single_panel_axis_frame`: Single-panel axis frame alignment (error, tolerance `0.05 mm`) - Standard single-panel templates must share the same physical axis frame.
- `wide_nmr_horizontal_alignment`: Wide NMR left/right/bottom alignment (error, tolerance `0.05 mm`) - Wide NMR only requires the left, right, and bottom edges to share anchors with the standard single-panel frame.
- `wide_nmr_structure_reserve`: Wide NMR top structure reserve (error, tolerance `1.00 mm`) - Wide NMR must keep a reserved structure area at the top.
- `wide_nmr_segment_alignment`: Wide NMR segmented-axis alignment (error, tolerance `0.05 mm`) - Wide NMR segmented axes must share the same top and bottom bounds.
- `heatmap_main_frame`: Heatmap main-frame alignment (error, tolerance `0.05 mm`) - The heatmap main frame must share the same axis frame as standard single-panel plots.
- `heatmap_horizontal_colorbar`: Heatmap top horizontal colorbar (error, tolerance `0.05 mm`) - Heatmaps must use a top horizontal colorbar without squeezing the main frame.
- `heatmap_colorbar_inside_canvas`: Heatmap colorbar inside canvas (error, tolerance `0.20 mm`) - The heatmap colorbar and z label must stay fully inside the canvas.
- `non_blank_pdf`: Non-blank exported PDF (error) - Every exported PDF must contain visible content and rasterize correctly.
- `multi_output_bundle_notice`: Multi-output notice (warning) - Multi-output bundles should warn how many files will be exported.
- `dense_group_label_warning`: Dense group-label warning (warning) - Statistical plots should warn that x-axis labels may become crowded when many groups are present.
