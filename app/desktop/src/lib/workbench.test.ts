import { afterEach, describe, expect, it, vi } from "vitest";

import {
  confirmReplaceComposerSession,
  confirmReplaceWizardSession,
  hasComposerSessionContent,
  hasWizardSessionContent,
} from "./workbench";

describe("workbench replacement guards", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("treats a populated wizard session as replaceable work", () => {
    expect(
      hasWizardSessionContent({
        inputPath: "/tmp/current.csv",
        inspection: { model: "curve_table" },
        template: "curve",
        outputs: ["/tmp/current.pdf"],
        exportResult: null,
      }),
    ).toBe(true);
  });

  it("does not prompt when reopening the same wizard data path", () => {
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(false);

    expect(
      confirmReplaceWizardSession(
        {
          inputPath: "/tmp/current.csv",
          inspection: { model: "curve_table" },
          template: "curve",
          outputs: ["/tmp/current.pdf"],
          exportResult: null,
        },
        "current.csv",
        "/tmp/current.csv",
      ),
    ).toBe(true);
    expect(confirmSpy).not.toHaveBeenCalled();
  });

  it("prompts before replacing a populated wizard session", () => {
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(false);

    expect(
      confirmReplaceWizardSession(
        {
          inputPath: "/tmp/current.csv",
          inspection: { model: "curve_table" },
          template: "curve",
          outputs: ["/tmp/current.pdf"],
          exportResult: null,
        },
        "new-data.xlsx",
        "/tmp/new-data.xlsx",
      ),
    ).toBe(false);
    expect(confirmSpy).toHaveBeenCalledWith(
      expect.stringContaining("replace the current Plot Builder session"),
    );
  });

  it("prompts before replacing a populated composer layout", () => {
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(false);

    expect(
      hasComposerSessionContent({
        regions: [{ id: "region-1" }],
        panels: [],
        texts: [],
      }),
    ).toBe(true);
    expect(
      confirmReplaceComposerSession(
        {
          regions: [{ id: "region-1" }],
          panels: [],
          texts: [],
        },
        "layout.plotproject.json",
      ),
    ).toBe(false);
    expect(confirmSpy).toHaveBeenCalledWith(
      expect.stringContaining("replace the current Composer layout"),
    );
  });
});
