import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { useCodeConsoleStore } from "../lib/store";
import { TEST_CONTRACT, TEST_META } from "../test/fixtures";
import { CodeConsoleScreen } from "./CodeConsoleScreen";

describe("CodeConsoleScreen", () => {
  const writeText = vi.fn().mockResolvedValue(undefined);

  beforeEach(() => {
    useCodeConsoleStore.getState().reset();
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: {
        writeText,
      },
    });
  });

  afterEach(() => {
    writeText.mockClear();
  });

  it("copies the generated AI prompt with project defaults baked in", async () => {
    render(<CodeConsoleScreen contract={TEST_CONTRACT} meta={TEST_META} />);

    fireEvent.change(screen.getByLabelText("Code console brief"), {
      target: { value: "给 point_line 图加一个箭头和注释。" },
    });

    fireEvent.click(screen.getByRole("button", { name: "Copy AI prompt" }));

    await waitFor(() => expect(writeText).toHaveBeenCalledTimes(1));
    expect(writeText.mock.calls[0]?.[0]).toContain("style_preset：default");
    expect(writeText.mock.calls[0]?.[0]).toContain("palette_preset：colorblind_safe");
    expect(writeText.mock.calls[0]?.[0]).toContain("给 point_line 图加一个箭头和注释");
  });

  it("updates the scaffold when switching to annotation tweak mode", async () => {
    render(<CodeConsoleScreen contract={TEST_CONTRACT} meta={TEST_META} />);

    fireEvent.click(screen.getByRole("button", { name: "Annotation tweak" }));

    await act(async () => {
      await Promise.resolve();
    });

    expect(screen.getByLabelText("Generated Python scaffold")).toHaveTextContent(
      "style.stroke.line_width_pt",
    );
  });
});
