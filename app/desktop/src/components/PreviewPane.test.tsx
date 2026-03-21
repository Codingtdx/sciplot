import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { PreviewPane } from "./PreviewPane";

const TEST_PREVIEW = {
  filename: "curve.preview.png",
  png_base64: "ZmFrZQ==",
};

describe("PreviewPane", () => {
  it("routes plain wheel scrolling to the workspace scroll root instead of zooming", () => {
    const scrollBy = vi.fn();

    render(
      <div className="app-main" data-scroll-root="workspace">
        <PreviewPane
          busy={false}
          error={null}
          onChangeIndex={() => {}}
          previewIndex={0}
          previews={[TEST_PREVIEW]}
        />
      </div>,
    );

    const image = screen.getByRole("img", { name: TEST_PREVIEW.filename });
    const surface = image.closest(".preview-surface");
    const appMain = image.closest(".app-main");
    expect(surface).not.toBeNull();
    expect(appMain).not.toBeNull();

    Object.defineProperty(appMain as HTMLDivElement, "scrollBy", {
      configurable: true,
      value: scrollBy,
    });

    fireEvent.wheel(surface as Element, { deltaY: 160, deltaX: 0 });

    expect(scrollBy).toHaveBeenCalledWith({
      top: 160,
      left: 0,
      behavior: "auto",
    });
    expect(image).toHaveStyle({ width: "auto" });
  });

  it("zooms only on Ctrl/Cmd plus wheel and double click resets to fit", () => {
    render(
      <div className="app-main" data-scroll-root="workspace">
        <PreviewPane
          busy={false}
          error={null}
          onChangeIndex={() => {}}
          previewIndex={0}
          previews={[TEST_PREVIEW]}
        />
      </div>,
    );

    const image = screen.getByRole("img", { name: TEST_PREVIEW.filename });
    const surface = image.closest(".preview-surface");
    expect(surface).not.toBeNull();

    fireEvent.wheel(surface as Element, { ctrlKey: true, deltaY: -120 });
    expect(image).toHaveStyle({ width: "100%" });

    fireEvent.dblClick(image);
    expect(image).toHaveStyle({ width: "auto" });
  });
});
