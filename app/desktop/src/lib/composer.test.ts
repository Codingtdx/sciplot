import { describe, expect, it } from "vitest";

import {
  EMPTY_COMPOSER_PROJECT,
  alignDrawables,
  buildComposerClipboard,
  duplicateComposerSelection,
  drawableIdsInRect,
  distributeDrawables,
  expandSelectionWithGroups,
  extractComposerProject,
  groupDrawables,
  mergeCellsIntoFreeRegion,
  moveDrawablesByDelta,
  moveGraphSelectionByCells,
  moveRegion,
  normalizeComposerProject,
  nudgeDrawables,
  pasteComposerClipboard,
  placeDrawableInRect,
  ungroupDrawables,
} from "./composer";

function projectWithDrawables() {
  return normalizeComposerProject({
    ...EMPTY_COMPOSER_PROJECT,
    panels: [
      {
        id: "asset-1",
        file_path: "/tmp/asset-1.png",
        page_index: 0,
        x_mm: 10,
        y_mm: 20,
        w_mm: 20,
        h_mm: 10,
        locked: false,
        label: null,
        kind: "asset",
        z_index: 0,
        region_id: null,
        slot_id: null,
        crop_rect: { x: 0, y: 0, width: 1, height: 1 },
      },
      {
        id: "asset-2",
        file_path: "/tmp/asset-2.png",
        page_index: 0,
        x_mm: 45,
        y_mm: 32,
        w_mm: 12,
        h_mm: 12,
        locked: false,
        label: null,
        kind: "asset",
        z_index: 1,
        region_id: null,
        slot_id: null,
        crop_rect: { x: 0, y: 0, width: 1, height: 1 },
      },
      {
        id: "asset-3",
        file_path: "/tmp/asset-3.png",
        page_index: 0,
        x_mm: 80,
        y_mm: 24,
        w_mm: 20,
        h_mm: 10,
        locked: false,
        label: null,
        kind: "asset",
        z_index: 2,
        region_id: null,
        slot_id: null,
        crop_rect: { x: 0, y: 0, width: 1, height: 1 },
      },
    ],
    texts: [
      {
        id: "text-1",
        text: "Note",
        x_mm: 30,
        y_mm: 60,
        font_size_pt: 8,
        align: "left",
        z_index: 3,
        region_id: null,
        slot_id: null,
      },
    ],
  });
}

describe("extractComposerProject", () => {
  it("rejects wizard project payloads", () => {
    expect(() =>
      extractComposerProject({
        mode: "wizard",
        wizard: { input_path: "a.csv" },
      }),
    ).toThrow("这不是可识别的拼图器项目文件。");
  });

  it("rejects legacy composer v1 payloads", () => {
    expect(() =>
      extractComposerProject({
        mode: "composer",
        version: 1,
        project: {
          version: 1,
          mode: "composer",
          panels: [],
          texts: [],
        },
      }),
    ).toThrow("Composer 项目仅支持 version: 2");
  });

  it("accepts wrapped composer v2 payloads", () => {
    const project = extractComposerProject({
      mode: "composer",
      version: 2,
      project: {
        version: 2,
        mode: "composer",
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
        regions: [],
        panels: [],
        texts: [],
        auto_labels: true,
      },
    });

    expect(project.mode).toBe("composer");
    expect(project.version).toBe(2);
    expect(project.layout_grid.cell_height_mm).toBe(55);
  });
});

describe("mergeCellsIntoFreeRegion", () => {
  it("creates a free region from contiguous empty cells", () => {
    const project = normalizeComposerProject({
      version: 2,
      mode: "composer",
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
      regions: [],
      panels: [],
      texts: [],
      auto_labels: true,
    });

    const merged = mergeCellsIntoFreeRegion(project, [
      { col: 0, row: 1 },
      { col: 1, row: 1 },
    ]);

    expect(merged.regions).toHaveLength(1);
    expect(merged.regions[0]).toMatchObject({
      kind: "free",
      col: 0,
      row: 1,
      col_span: 2,
      row_span: 1,
    });
  });
});

describe("drawable layout helpers", () => {
  it("aligns free drawables to the same left edge", () => {
    const project = projectWithDrawables();

    const aligned = alignDrawables(project, ["asset-1", "asset-2", "text-1"], "left");

    expect(aligned.panels.find((panel) => panel.id === "asset-1")?.x_mm).toBe(10);
    expect(aligned.panels.find((panel) => panel.id === "asset-2")?.x_mm).toBe(10);
    expect(aligned.texts.find((text) => text.id === "text-1")?.x_mm).toBe(10);
  });

  it("distributes free drawables horizontally between first and last item", () => {
    const project = projectWithDrawables();

    const distributed = distributeDrawables(project, ["asset-1", "asset-2", "asset-3"], "horizontal");

    expect(distributed.panels.find((panel) => panel.id === "asset-1")?.x_mm).toBe(10);
    expect(distributed.panels.find((panel) => panel.id === "asset-2")?.x_mm).toBe(49);
    expect(distributed.panels.find((panel) => panel.id === "asset-3")?.x_mm).toBe(80);
  });

  it("nudges selected free drawables on the half-millimeter grid", () => {
    const project = projectWithDrawables();

    const nudged = nudgeDrawables(project, ["asset-1", "text-1"], 0.5, -1);

    expect(nudged.panels.find((panel) => panel.id === "asset-1")?.x_mm).toBe(10.5);
    expect(nudged.panels.find((panel) => panel.id === "asset-1")?.y_mm).toBe(19);
    expect(nudged.texts.find((text) => text.id === "text-1")?.x_mm).toBe(30.5);
    expect(nudged.texts.find((text) => text.id === "text-1")?.y_mm).toBe(59);
  });

  it("finds drawables intersecting a marquee rectangle", () => {
    const project = projectWithDrawables();

    const ids = drawableIdsInRect(project, {
      x_mm: 8,
      y_mm: 18,
      w_mm: 52,
      h_mm: 20,
    });

    expect(ids).toEqual(["asset-1", "asset-2"]);
  });

  it("places a drawable against the bound rect while keeping it inside horizontally", () => {
    const project = projectWithDrawables();

    const placed = placeDrawableInRect(
      normalizeComposerProject({
        ...project,
        panels: project.panels.map((panel) =>
          panel.id === "asset-2" ? { ...panel, x_mm: 55, y_mm: 10 } : panel,
        ),
      }),
      "asset-2",
      {
        x_mm: 0,
        y_mm: 2.5,
        w_mm: 60,
        h_mm: 55,
      },
      "bottom",
    );

    expect(placed.panels.find((panel) => panel.id === "asset-2")).toMatchObject({
      x_mm: 48,
      y_mm: 45.5,
    });
  });

  it("pins a drawable to the left edge of its bound rect while preserving vertical position", () => {
    const project = projectWithDrawables();

    const placed = placeDrawableInRect(
      normalizeComposerProject({
        ...project,
        panels: project.panels.map((panel) =>
          panel.id === "asset-2" ? { ...panel, x_mm: 55, y_mm: 18 } : panel,
        ),
      }),
      "asset-2",
      {
        x_mm: 0,
        y_mm: 2.5,
        w_mm: 60,
        h_mm: 55,
      },
      "left",
    );

    expect(placed.panels.find((panel) => panel.id === "asset-2")).toMatchObject({
      x_mm: 0,
      y_mm: 18,
    });
  });

  it("keeps locked free drawables fixed when nudging or placing inside a bound rect", () => {
    const project = normalizeComposerProject({
      ...projectWithDrawables(),
      panels: projectWithDrawables().panels.map((panel) =>
        panel.id === "asset-2" ? { ...panel, locked: true } : panel,
      ),
      texts: projectWithDrawables().texts.map((text) =>
        text.id === "text-1" ? { ...text, locked: true } : text,
      ),
    });

    const nudged = nudgeDrawables(project, ["asset-2", "text-1"], 5, -3);
    const placed = placeDrawableInRect(
      project,
      "asset-2",
      {
        x_mm: 0,
        y_mm: 2.5,
        w_mm: 60,
        h_mm: 55,
      },
      "bottom",
    );

    expect(nudged.panels.find((panel) => panel.id === "asset-2")).toMatchObject({
      x_mm: 45,
      y_mm: 32,
    });
    expect(nudged.texts.find((text) => text.id === "text-1")).toMatchObject({
      x_mm: 30,
      y_mm: 60,
    });
    expect(placed.panels.find((panel) => panel.id === "asset-2")).toMatchObject({
      x_mm: 45,
      y_mm: 32,
    });
  });

  it("ignores hidden drawables when marquee selecting", () => {
    const project = normalizeComposerProject({
      ...projectWithDrawables(),
      panels: projectWithDrawables().panels.map((panel) =>
        panel.id === "asset-2" ? { ...panel, hidden: true } : panel,
      ),
    });

    const ids = drawableIdsInRect(project, {
      x_mm: 8,
      y_mm: 18,
      w_mm: 52,
      h_mm: 20,
    });

    expect(ids).toEqual(["asset-1"]);
  });
});

describe("composer clipboard helpers", () => {
  it("duplicates a selected graph panel into the next available region slot", () => {
    const project = normalizeComposerProject({
      ...EMPTY_COMPOSER_PROJECT,
      regions: [
        {
          id: "region-1",
          kind: "graph",
          col: 0,
          row: 0,
          col_span: 1,
          row_span: 1,
          label: null,
          locked: false,
          slot_kind: null,
        },
      ],
      panels: [
        {
          id: "panel-1",
          file_path: "/tmp/figure.pdf",
          page_index: 0,
          x_mm: 0,
          y_mm: 2.5,
          w_mm: 60,
          h_mm: 55,
          locked: false,
          label: null,
          kind: "graph",
          z_index: 0,
          region_id: "region-1",
          slot_id: null,
          crop_rect: { x: 0, y: 0, width: 1, height: 1 },
        },
      ],
    });

    const duplicated = duplicateComposerSelection(project, null, ["panel-1"]);

    expect(duplicated.project.regions).toHaveLength(2);
    expect(duplicated.project.regions[1]).toMatchObject({
      kind: "graph",
      col: 1,
      row: 0,
    });
    expect(
      duplicated.project.panels.find((panel) => panel.id === duplicated.selectedObjectIds[0]),
    ).toMatchObject({
      kind: "graph",
      region_id: duplicated.project.regions[1]?.id,
      x_mm: 60,
      y_mm: 2.5,
    });
  });

  it("copies a selected free region together with its bound drawables", () => {
    const project = normalizeComposerProject({
      ...EMPTY_COMPOSER_PROJECT,
      regions: [
        {
          id: "region-1",
          kind: "free",
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
          file_path: "/tmp/asset.png",
          page_index: 0,
          x_mm: 8,
          y_mm: 10,
          w_mm: 24,
          h_mm: 18,
          locked: false,
          label: null,
          kind: "asset",
          z_index: 0,
          region_id: "region-1",
          slot_id: null,
          crop_rect: { x: 0, y: 0, width: 1, height: 1 },
        },
      ],
      texts: [
        {
          id: "text-1",
          text: "Legend",
          x_mm: 12,
          y_mm: 34,
          font_size_pt: 8,
          align: "left",
          z_index: 1,
          region_id: "region-1",
          slot_id: null,
        },
      ],
    });

    const clipboard = buildComposerClipboard(project, "region-1", []);
    expect(clipboard).not.toBeNull();

    const pasted = pasteComposerClipboard(project, clipboard!);
    const pastedRegion = pasted.project.regions.find((region) => region.id !== "region-1");
    const pastedAsset = pasted.project.panels.find((panel) => panel.id !== "asset-1");
    const pastedText = pasted.project.texts.find((text) => text.id !== "text-1");

    expect(pastedRegion).toMatchObject({ col: 1, row: 0, label: "Notes" });
    expect(pastedAsset?.region_id).toBe(pastedRegion?.id);
    expect(pastedText?.region_id).toBe(pastedRegion?.id);
  });
});

describe("group helpers", () => {
  it("expands selection to all members of the same group", () => {
    const project = normalizeComposerProject({
      ...projectWithDrawables(),
      panels: projectWithDrawables().panels.map((panel) =>
        panel.id === "asset-1" || panel.id === "asset-2"
          ? { ...panel, group_id: "group-1" }
          : panel,
      ),
    });

    expect(expandSelectionWithGroups(project, ["asset-1"])).toEqual(["asset-1", "asset-2"]);
  });

  it("groups and ungroups selected free drawables", () => {
    const project = projectWithDrawables();

    const grouped = groupDrawables(project, ["asset-1", "text-1"]);
    const groupId = grouped.panels.find((panel) => panel.id === "asset-1")?.group_id;

    expect(groupId).toBeTruthy();
    expect(grouped.texts.find((text) => text.id === "text-1")?.group_id).toBe(groupId);

    const ungrouped = ungroupDrawables(grouped, ["asset-1"]);
    expect(ungrouped.panels.find((panel) => panel.id === "asset-1")?.group_id).toBeNull();
    expect(ungrouped.texts.find((text) => text.id === "text-1")?.group_id).toBeNull();
  });

  it("moves grouped free drawables together by delta", () => {
    const project = normalizeComposerProject({
      ...projectWithDrawables(),
      panels: projectWithDrawables().panels.map((panel) =>
        panel.id === "asset-1" || panel.id === "asset-2"
          ? { ...panel, group_id: "group-1" }
          : panel,
      ),
    });

    const moved = moveDrawablesByDelta(project, ["asset-1", "asset-2"], 5, -2);

    expect(moved.panels.find((panel) => panel.id === "asset-1")).toMatchObject({
      x_mm: 15,
      y_mm: 18,
    });
    expect(moved.panels.find((panel) => panel.id === "asset-2")).toMatchObject({
      x_mm: 50,
      y_mm: 30,
    });
  });

  it("does not move a locked free region", () => {
    const project = normalizeComposerProject({
      ...EMPTY_COMPOSER_PROJECT,
      regions: [
        {
          id: "region-1",
          kind: "free",
          col: 0,
          row: 0,
          col_span: 1,
          row_span: 1,
          label: null,
          locked: true,
          slot_kind: null,
        },
      ],
    });

    const moved = moveRegion(project, "region-1", 1, 1);

    expect(moved.regions[0]).toMatchObject({ col: 0, row: 0 });
  });

  it("moves adjacent graph selections together without colliding with each other", () => {
    const project = normalizeComposerProject({
      ...EMPTY_COMPOSER_PROJECT,
      regions: [
        {
          id: "region-1",
          kind: "graph",
          col: 0,
          row: 0,
          col_span: 1,
          row_span: 1,
          label: null,
          locked: false,
          slot_kind: null,
        },
        {
          id: "region-2",
          kind: "graph",
          col: 1,
          row: 0,
          col_span: 1,
          row_span: 1,
          label: null,
          locked: false,
          slot_kind: null,
        },
      ],
      panels: [
        {
          id: "panel-1",
          file_path: "/tmp/panel-1.pdf",
          page_index: 0,
          x_mm: 0,
          y_mm: 2.5,
          w_mm: 60,
          h_mm: 55,
          locked: false,
          label: null,
          kind: "graph",
          z_index: 0,
          region_id: "region-1",
          slot_id: null,
          crop_rect: { x: 0, y: 0, width: 1, height: 1 },
        },
        {
          id: "panel-2",
          file_path: "/tmp/panel-2.pdf",
          page_index: 0,
          x_mm: 60,
          y_mm: 2.5,
          w_mm: 60,
          h_mm: 55,
          locked: false,
          label: null,
          kind: "graph",
          z_index: 1,
          region_id: "region-2",
          slot_id: null,
          crop_rect: { x: 0, y: 0, width: 1, height: 1 },
        },
      ],
    });

    const moved = moveGraphSelectionByCells(project, ["panel-1", "panel-2"], 1, 0);

    expect(moved.regions.find((region) => region.id === "region-1")).toMatchObject({
      col: 1,
      row: 0,
    });
    expect(moved.regions.find((region) => region.id === "region-2")).toMatchObject({
      col: 2,
      row: 0,
    });
    expect(moved.panels.find((panel) => panel.id === "panel-1")).toMatchObject({
      x_mm: 60,
      y_mm: 2.5,
    });
    expect(moved.panels.find((panel) => panel.id === "panel-2")).toMatchObject({
      x_mm: 120,
      y_mm: 2.5,
    });
  });
});
