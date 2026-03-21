import { describe, expect, it } from "vitest";

import {
  buildCodeConsolePrompt,
  buildCodeConsoleScaffold,
  DEFAULT_CODE_CONSOLE_DRAFT,
} from "./code-console";
import { TEST_CONTRACT, TEST_META } from "../test/fixtures";

describe("code console prompt helpers", () => {
  it("builds a prompt that pins the task to project defaults and truth sources", () => {
    const prompt = buildCodeConsolePrompt({
      draft: {
        ...DEFAULT_CODE_CONSOLE_DRAFT,
        brief: "在现有曲线图中加一个箭头说明峰值位置。",
        intent: "annotation_tweak",
      },
      meta: TEST_META,
      contract: TEST_CONTRACT,
    });

    expect(prompt).toContain("唯一绘图事实源是 `src/plot_contract.json`");
    expect(prompt).toContain("style_preset：default");
    expect(prompt).toContain("palette_preset：colorblind_safe");
    expect(prompt).toContain("目标尺寸：60x55");
    expect(prompt).toContain("src/plot_style.py");
  });

  it("builds an annotation scaffold that reuses project style fields", () => {
    const scaffold = buildCodeConsoleScaffold({
      draft: {
        ...DEFAULT_CODE_CONSOLE_DRAFT,
        intent: "annotation_tweak",
      },
      meta: TEST_META,
    });

    expect(scaffold).toContain("style = plot_style.get_style_spec");
    expect(scaffold).toContain("\"lw\": style.stroke.line_width_pt");
    expect(scaffold).toContain("fontsize=style.typography.font_size_pt");
  });
});
