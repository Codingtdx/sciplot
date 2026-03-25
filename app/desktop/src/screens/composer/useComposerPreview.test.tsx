import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { composePreviewWithOptions } from "../../lib/api";
import type { ComposerProject } from "../../lib/types";
import { useComposerPreview } from "./useComposerPreview";

vi.mock("../../lib/api", async () => {
  const actual = await vi.importActual<typeof import("../../lib/api")>("../../lib/api");
  return {
    ...actual,
    composePreviewWithOptions: vi.fn(),
  };
});

const BASE_PROJECT: ComposerProject = {
  version: 2,
  mode: "composer",
  canvas_width_mm: 180,
  canvas_height_mm: 170,
  grid_mm: 5,
  layout_grid: {
    columns: 3,
    rows: 3,
    cell_width_mm: 60,
    cell_height_mm: 55,
    frame_x_mm: 0,
    frame_y_mm: 0,
    frame_width_mm: 180,
    frame_height_mm: 165,
  },
  regions: [],
  panels: [],
  texts: [],
  auto_labels: true,
};

function previewResponse(base64: string) {
  return {
    valid: true,
    validation_error: null,
    png_base64: base64,
    qa: null,
    submission_report: null,
    suggested_project_patch: [],
  };
}

describe("useComposerPreview", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("debounces preview requests before calling sidecar", async () => {
    const onPreview = vi.fn();
    vi.mocked(composePreviewWithOptions).mockResolvedValue(previewResponse("debounced"));

    renderHook(() => useComposerPreview(BASE_PROJECT, onPreview));

    expect(composePreviewWithOptions).not.toHaveBeenCalled();
    await act(async () => {
      vi.advanceTimersByTime(119);
    });
    expect(composePreviewWithOptions).not.toHaveBeenCalled();

    await act(async () => {
      await vi.advanceTimersByTimeAsync(1);
    });
    expect(composePreviewWithOptions).toHaveBeenCalledTimes(1);
    expect(onPreview).toHaveBeenLastCalledWith(
      expect.objectContaining({ png_base64: "debounced" }),
      null,
    );
  });

  it("aborts the previous preview request when project changes", async () => {
    const onPreview = vi.fn();
    let firstSignal: AbortSignal | undefined;

    vi.mocked(composePreviewWithOptions)
      .mockImplementationOnce((_project, options = {}) => {
        firstSignal = options.signal;
        return new Promise((_resolve, reject) => {
          options.signal?.addEventListener("abort", () => {
            reject(new DOMException("The operation was aborted.", "AbortError"));
          });
        });
      })
      .mockResolvedValueOnce(previewResponse("next"));

    const { rerender } = renderHook(
      ({ project }) => useComposerPreview(project, onPreview),
      { initialProps: { project: BASE_PROJECT } },
    );

    await act(async () => {
      await vi.advanceTimersByTimeAsync(120);
    });
    expect(composePreviewWithOptions).toHaveBeenCalledTimes(1);

    rerender({
      project: {
        ...BASE_PROJECT,
        auto_labels: false,
      },
    });
    expect(firstSignal?.aborted).toBe(true);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(120);
    });
    expect(composePreviewWithOptions).toHaveBeenCalledTimes(2);
    expect(onPreview).toHaveBeenLastCalledWith(
      expect.objectContaining({ png_base64: "next" }),
      null,
    );
  });

  it("uses cached preview for an identical project payload", async () => {
    const onPreview = vi.fn();
    vi.mocked(composePreviewWithOptions).mockResolvedValue(previewResponse("cached"));

    const { rerender } = renderHook(
      ({ project }) => useComposerPreview(project, onPreview),
      { initialProps: { project: BASE_PROJECT } },
    );
    await act(async () => {
      await vi.advanceTimersByTimeAsync(120);
    });
    expect(onPreview).toHaveBeenCalledWith(
      expect.objectContaining({ png_base64: "cached" }),
      null,
    );
    expect(composePreviewWithOptions).toHaveBeenCalledTimes(1);

    rerender({
      project: {
        ...BASE_PROJECT,
      },
    });

    expect(onPreview).toHaveBeenCalledWith(
      expect.objectContaining({ png_base64: "cached" }),
      null,
    );
    expect(composePreviewWithOptions).toHaveBeenCalledTimes(1);
  });
});
