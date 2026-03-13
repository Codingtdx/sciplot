import { describe, expect, it } from "vitest";

import { extractWizardProject } from "./projects";

describe("extractWizardProject", () => {
  it("accepts version 1 wizard payloads", () => {
    const project = extractWizardProject({
      version: 1,
      mode: "wizard",
      wizard: {
        input_path: "/tmp/demo.csv",
        sheet: "Summary",
        template: "curve",
        options: {
          size: "60x55",
          reverse_x: true,
        },
        outputs: ["/tmp/demo_curve.pdf"],
      },
    });

    expect(project.mode).toBe("wizard");
    expect(project.wizard.sheet).toBe("Summary");
    expect(project.wizard.options.reverse_x).toBe(true);
    expect(project.wizard.outputs).toEqual(["/tmp/demo_curve.pdf"]);
  });

  it("rejects non-wizard payloads", () => {
    expect(() =>
      extractWizardProject({
        version: 1,
        mode: "composer",
      }),
    ).toThrow("这不是可识别的绘图精灵项目文件。");
  });

  it("rejects missing input paths", () => {
    expect(() =>
      extractWizardProject({
        version: 1,
        mode: "wizard",
        wizard: {
          input_path: "",
        },
      }),
    ).toThrow("绘图项目文件缺少有效的数据路径。");
  });
});
