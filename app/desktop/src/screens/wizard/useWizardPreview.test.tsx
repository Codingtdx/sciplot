import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { renderPreview } from "../../lib/api";
import type { PreviewItem, RenderOptionsPayload } from "../../lib/types";
import { useWizardPreview } from "./useWizardPreview";

vi.mock("../../lib/api", async () => {
  const actual = await vi.importActual<typeof import("../../lib/api")>("../../lib/api");
  return {
    ...actual,
    renderPreview: vi.fn(),
  };
});

const BASE_OPTIONS: RenderOptionsPayload = {
  size: "60x55",
  style_preset: "default",
  palette_preset: "colorblind_safe",
};

function preview(filename: string): PreviewItem[] {
  return [{ filename, png_base64: "ZmFrZQ==" }];
}

describe("useWizardPreview", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("debounces preview requests and only fires after the delay", async () => {
    const onPreviews = vi.fn();
    const previews = preview("debounce.pdf");
    vi.mocked(renderPreview).mockResolvedValue({
      template: "curve",
      sheet: 0,
      previews,
    });

    const { result } = renderHook(() =>
      useWizardPreview({
        enabled: true,
        inputPath: "/tmp/debounce-preview.csv",
        sheet: 0,
        template: "curve",
        options: BASE_OPTIONS,
        onPreviews,
      }),
    );

    expect(result.current.activity).toBe("scheduled");
    expect(renderPreview).not.toHaveBeenCalled();

    await act(async () => {
      vi.advanceTimersByTime(219);
    });
    expect(renderPreview).not.toHaveBeenCalled();

    await act(async () => {
      await vi.advanceTimersByTimeAsync(1);
    });

    expect(renderPreview).toHaveBeenCalledTimes(1);
    expect(onPreviews).toHaveBeenLastCalledWith(previews);
    expect(result.current.activity).toBe("ready");
  });

  it("aborts the previous in-flight request when inputs change", async () => {
    const onPreviews = vi.fn();
    const nextPreviews = preview("next.pdf");
    let firstSignal: AbortSignal | undefined;

    vi.mocked(renderPreview)
      .mockImplementationOnce((_path, _sheet, _template, _options, requestOptions = {}) => {
        firstSignal = requestOptions.signal;
        return new Promise((_resolve, reject) => {
          requestOptions.signal?.addEventListener("abort", () => {
            reject(new DOMException("The operation was aborted.", "AbortError"));
          });
        });
      })
      .mockResolvedValueOnce({
        template: "curve",
        sheet: 0,
        previews: nextPreviews,
      });

    const { rerender } = renderHook(
      ({ inputPath }) =>
        useWizardPreview({
          enabled: true,
          inputPath,
          sheet: 0,
          template: "curve",
          options: BASE_OPTIONS,
          onPreviews,
        }),
      {
        initialProps: { inputPath: "/tmp/cancel-preview-a.csv" },
      },
    );

    await act(async () => {
      await vi.advanceTimersByTimeAsync(220);
    });
    expect(renderPreview).toHaveBeenCalledTimes(1);

    rerender({ inputPath: "/tmp/cancel-preview-b.csv" });
    expect(firstSignal?.aborted).toBe(true);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(220);
    });

    expect(renderPreview).toHaveBeenCalledTimes(2);
    expect(vi.mocked(renderPreview).mock.calls[1]?.[0]).toBe("/tmp/cancel-preview-b.csv");
    expect(onPreviews).toHaveBeenLastCalledWith(nextPreviews);
  });

  it("serves cached previews for identical requests", async () => {
    const previews = preview("cached.pdf");
    vi.mocked(renderPreview).mockResolvedValue({
      template: "curve",
      sheet: 0,
      previews,
    });

    const firstOnPreviews = vi.fn();
    const first = renderHook(() =>
      useWizardPreview({
        enabled: true,
        inputPath: "/tmp/cached-preview.csv",
        sheet: 0,
        template: "curve",
        options: BASE_OPTIONS,
        onPreviews: firstOnPreviews,
      }),
    );

    await act(async () => {
      await vi.advanceTimersByTimeAsync(220);
    });
    expect(firstOnPreviews).toHaveBeenCalledWith(previews);
    expect(renderPreview).toHaveBeenCalledTimes(1);

    first.unmount();

    const secondOnPreviews = vi.fn();
    renderHook(() =>
      useWizardPreview({
        enabled: true,
        inputPath: "/tmp/cached-preview.csv",
        sheet: 0,
        template: "curve",
        options: BASE_OPTIONS,
        onPreviews: secondOnPreviews,
      }),
    );

    expect(secondOnPreviews).toHaveBeenCalledWith(previews);
    expect(renderPreview).toHaveBeenCalledTimes(1);
  });
});
