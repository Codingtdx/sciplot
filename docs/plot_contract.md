# CodeGod Plot Contract

- Version: `1`
- Default style: `default`
- Default palette: `colorblind_safe`

## Global Frame

- Standard panel: `60.0 x 55.0 mm`
- Margins: left `14.0 mm`, right `4.5 mm`, bottom `11.0 mm`, top `5.5 mm`

## Templates

### `curve` / 曲线

- Category: `single_panel`
- Default size: `60x55`
- Allowed sizes: `60x55`, `120x55`
- Editable options: `size`, `xscale`, `yscale`, `reverse_x`, `palette_preset`
- Description: 普通单图曲线。
- Hard rules: `single_panel_axis_frame`, `non_blank_pdf`
- Soft rules: None

### `point_line` / 点线

- Category: `single_panel`
- Default size: `60x55`
- Allowed sizes: `60x55`, `120x55`
- Editable options: `size`, `xscale`, `yscale`, `reverse_x`, `palette_preset`
- Description: 带 marker 的普通单图曲线。
- Hard rules: `single_panel_axis_frame`, `non_blank_pdf`
- Soft rules: `multi_output_bundle_notice`

### `stacked_curve` / 堆叠曲线

- Category: `stacked_spectrum`
- Default size: `60x55`
- Allowed sizes: `60x55`
- Editable options: `size`, `reverse_x`, `baseline`, `palette_preset`
- Description: 光谱类的单列堆叠曲线。
- Hard rules: `non_blank_pdf`
- Soft rules: None

### `segmented_stacked_curve` / 分段堆叠曲线

- Category: `wide_nmr`
- Default size: `60x110`
- Allowed sizes: `60x110`
- Editable options: `size`, `reverse_x`, `baseline`, `palette_preset`, `use_sidecar`
- Description: wide NMR 双高面板，左右底对齐，顶部预留结构式区域。
- Hard rules: `wide_nmr_horizontal_alignment`, `wide_nmr_structure_reserve`, `wide_nmr_segment_alignment`, `non_blank_pdf`
- Soft rules: None

### `bar` / 柱状

- Category: `single_panel`
- Default size: `60x55`
- Allowed sizes: `60x55`
- Editable options: `size`, `palette_preset`
- Description: 统计类柱状图。
- Hard rules: `single_panel_axis_frame`, `non_blank_pdf`
- Soft rules: `dense_group_label_warning`

### `box` / 箱线

- Category: `single_panel`
- Default size: `60x55`
- Allowed sizes: `60x55`
- Editable options: `size`, `palette_preset`
- Description: 统计类箱线图。
- Hard rules: `single_panel_axis_frame`, `non_blank_pdf`
- Soft rules: `dense_group_label_warning`

### `violin` / 小提琴

- Category: `single_panel`
- Default size: `60x55`
- Allowed sizes: `60x55`
- Editable options: `size`, `palette_preset`
- Description: 统计类小提琴图。
- Hard rules: `single_panel_axis_frame`, `non_blank_pdf`
- Soft rules: `dense_group_label_warning`

### `scatter` / 散点

- Category: `single_panel`
- Default size: `60x55`
- Allowed sizes: `60x55`, `120x55`
- Editable options: `size`, `xscale`, `yscale`, `reverse_x`, `palette_preset`
- Description: 单图散点图。
- Hard rules: `single_panel_axis_frame`, `non_blank_pdf`
- Soft rules: None

### `heatmap` / 热图

- Category: `heatmap`
- Default size: `60x55`
- Allowed sizes: `60x55`, `120x55`
- Editable options: `size`, `show_colorbar`, `palette_preset`
- Description: 主热图区与普通单图共用轴框，顶部水平色带独立放置。
- Hard rules: `single_panel_axis_frame`, `heatmap_main_frame`, `heatmap_horizontal_colorbar`, `heatmap_colorbar_inside_canvas`, `non_blank_pdf`
- Soft rules: None

## Validation Rules

- `single_panel_axis_frame`: 标准单图轴框对齐 (error, tolerance `0.05 mm`) - 标准单图模板必须共享同一物理轴框。
- `wide_nmr_horizontal_alignment`: wide NMR 左右底对齐 (error, tolerance `0.05 mm`) - wide NMR 只要求左、右、底与标准单图共用锚点。
- `wide_nmr_structure_reserve`: wide NMR 顶部结构区 (error, tolerance `1.00 mm`) - wide NMR 必须保留顶部结构式预留区。
- `wide_nmr_segment_alignment`: wide NMR 分段轴对齐 (error, tolerance `0.05 mm`) - wide NMR 的分段轴必须共享统一的上下边界。
- `heatmap_main_frame`: Heatmap 主图区轴框 (error, tolerance `0.05 mm`) - Heatmap 主图区必须与标准单图共用同一轴框。
- `heatmap_horizontal_colorbar`: Heatmap 顶部水平色带 (error, tolerance `0.05 mm`) - Heatmap 必须使用顶部水平色带，不得挤压主图区。
- `heatmap_colorbar_inside_canvas`: Heatmap 色带在画布内 (error, tolerance `0.20 mm`) - Heatmap 色带和 z 标签必须完整落在画布内。
- `non_blank_pdf`: 导出 PDF 非空白 (error) - 每个输出 PDF 都必须存在可见内容并能正确栅格化。
- `multi_output_bundle_notice`: 多输出提醒 (warning) - 多输出 bundle 应给出输出张数提醒。
- `dense_group_label_warning`: 分组过多提醒 (warning) - 统计图分组较多时应提醒横轴标签可能拥挤。
