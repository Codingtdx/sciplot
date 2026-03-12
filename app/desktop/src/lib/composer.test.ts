import { describe, expect, it } from "vitest";

import { extractComposerProject } from "./composer";

describe("extractComposerProject", () => {
  it("rejects wizard project payloads", () => {
    expect(() =>
      extractComposerProject({
        mode: "wizard",
        wizard: { input_path: "a.csv" },
      }),
    ).toThrow("这不是可识别的拼图器项目文件。");
  });

  it("accepts wrapped composer project payloads", () => {
    const project = extractComposerProject({
      mode: "composer",
      project: {
        version: 1,
        mode: "composer",
        canvas_width_mm: 180,
        canvas_height_mm: 170,
        grid_mm: 0.5,
        panels: [],
        texts: [],
        auto_labels: true,
      },
    });

    expect(project.mode).toBe("composer");
    expect(project.canvas_width_mm).toBe(180);
  });
});
