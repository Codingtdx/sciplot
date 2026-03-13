import { TEST_CONTRACT, TEST_META } from "../src/test/fixtures";

export { TEST_CONTRACT, TEST_META };

export const BLANK_PNG_BASE64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+WZ2QAAAAASUVORK5CYII=";

export const COMPOSER_E2E_PROJECT = {
  version: 2,
  mode: "composer" as const,
  canvas_width_mm: 180,
  canvas_height_mm: 170,
  grid_mm: 0.5,
  layout_grid: {
    columns: 3,
    rows: 3,
    cell_width_mm: 60,
    cell_height_mm: 55,
    frame_x_mm: 0,
    frame_y_mm: 2.5,
    frame_width_mm: 180,
    frame_height_mm: 165,
  },
  regions: [
    {
      id: "region-1",
      kind: "free" as const,
      col: 0,
      row: 0,
      col_span: 1,
      row_span: 1,
      label: "Notes",
      locked: false,
      slot_kind: null,
    },
  ],
  panels: [
    {
      id: "asset-1",
      file_path: "/tmp/e2e-asset-1.png",
      page_index: 0,
      x_mm: 10,
      y_mm: 20,
      w_mm: 24,
      h_mm: 12,
      locked: false,
      hidden: false,
      label: null,
      kind: "asset" as const,
      z_index: 0,
      group_id: null,
      region_id: "region-1",
      slot_id: null,
      crop_rect: { x: 0, y: 0, width: 1, height: 1 },
    },
    {
      id: "asset-2",
      file_path: "/tmp/e2e-asset-2.png",
      page_index: 0,
      x_mm: 55,
      y_mm: 100,
      w_mm: 18,
      h_mm: 12,
      locked: false,
      hidden: false,
      label: null,
      kind: "asset" as const,
      z_index: 1,
      group_id: null,
      region_id: null,
      slot_id: null,
      crop_rect: { x: 0, y: 0, width: 1, height: 1 },
    },
  ],
  texts: [],
  auto_labels: true,
};
