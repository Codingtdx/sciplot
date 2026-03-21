import { describe, expect, it } from "vitest";

import {
  backfillCodeConsoleOptions,
  defaultCodeConsoleTargetPath,
  DEFAULT_CODE_CONSOLE_DRAFT,
} from "./code-console";

describe("code console helpers", () => {
  it("backfills template and render options from the current plot session", () => {
    const resolved = backfillCodeConsoleOptions(DEFAULT_CODE_CONSOLE_DRAFT, {
      templateId: "point_line",
      options: {
        size: "120x55",
        style_preset: "nature",
        palette_preset: "mono",
      },
    });

    expect(resolved.templateId).toBe("point_line");
    expect(resolved.sizeId).toBe("120x55");
    expect(resolved.stylePreset).toBe("nature");
    expect(resolved.palettePreset).toBe("mono");
  });

  it("keeps full-data export opt-in disabled by default", () => {
    expect(DEFAULT_CODE_CONSOLE_DRAFT.includeFullDataBundle).toBe(false);
  });

  it("suggests a repo-native target path for custom plots", () => {
    expect(defaultCodeConsoleTargetPath("custom_plot", "curve")).toBe(
      "src/rendering/custom_curve_helper.py",
    );
    expect(defaultCodeConsoleTargetPath("patch_renderer", "curve")).toContain("src/rendering/");
  });
});
