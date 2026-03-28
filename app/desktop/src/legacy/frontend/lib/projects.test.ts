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
          style_preset: "nature",
          visual_theme_id: "soft_grid",
        },
        outputs: ["/tmp/demo_curve.pdf"],
      },
    });

    expect(project.mode).toBe("wizard");
    expect(project.wizard.sheet).toBe("Summary");
    expect(project.wizard.options.reverse_x).toBe(true);
    expect(project.wizard.options.style_preset).toBe("nature");
    expect(project.wizard.options.visual_theme_id).toBe("soft_grid");
    expect(project.wizard.outputs).toEqual(["/tmp/demo_curve.pdf"]);
  });

  it("rejects non-wizard payloads", () => {
    expect(() =>
      extractWizardProject({
        version: 1,
        mode: "composer",
      }),
    ).toThrow("This is not a recognizable Plot Builder project file.");
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
    ).toThrow("The Plot Builder project file is missing a valid data path.");
  });
});
