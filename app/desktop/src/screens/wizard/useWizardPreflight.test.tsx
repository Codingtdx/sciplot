import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { preflightRender } from "../../lib/api";
import type { RenderOptionsPayload } from "../../lib/types";
import { useWizardPreflight } from "./useWizardPreflight";

vi.mock("../../lib/api", async () => {
  const actual = await vi.importActual<typeof import("../../lib/api")>("../../lib/api");
  return {
    ...actual,
    preflightRender: vi.fn(),
  };
});

const BASE_OPTIONS: RenderOptionsPayload = {
  size: "60x55",
  style_preset: "default",
  palette_preset: "colorblind_safe",
};

function preflightPayload(summary: string) {
  return {
    input_path: "/tmp/preflight.csv",
    template: "curve" as const,
    sheet: 0,
    options: BASE_OPTIONS,
    preflight: {
      template: "curve" as const,
      warnings: [],
      errors: [],
      output_filenames: ["curve.pdf"],
      submission_report: {
        context: "preflight",
        readiness: "ready",
        summary,
        output_count: 1,
        output_filenames: ["curve.pdf"],
        blockers: [],
        checks: [],
      },
    },
  };
}

describe("useWizardPreflight", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("debounces preflight calls before issuing sidecar requests", async () => {
    const onPreflight = vi.fn();
    const onSubmissionReport = vi.fn();
    vi.mocked(preflightRender).mockResolvedValue(preflightPayload("Debounced"));

    const { result } = renderHook(() =>
      useWizardPreflight({
        enabled: true,
        inputPath: "/tmp/debounce-preflight.csv",
        sheet: 0,
        template: "curve",
        options: BASE_OPTIONS,
        onPreflight,
        onSubmissionReport,
      }),
    );

    expect(result.current.activity).toBe("scheduled");
    await act(async () => {
      vi.advanceTimersByTime(219);
    });
    expect(preflightRender).not.toHaveBeenCalled();

    await act(async () => {
      await vi.advanceTimersByTimeAsync(1);
    });
    expect(preflightRender).toHaveBeenCalledTimes(1);
    expect(onPreflight).toHaveBeenCalledWith(
      expect.objectContaining({ output_filenames: ["curve.pdf"] }),
    );
    expect(onSubmissionReport).toHaveBeenCalledWith(
      expect.objectContaining({ summary: "Debounced" }),
    );
    expect(result.current.activity).toBe("ready");
  });

  it("reuses cached preflight + submission report for identical input", async () => {
    const payload = preflightPayload("From cache");
    vi.mocked(preflightRender).mockResolvedValue(payload);

    const firstOnPreflight = vi.fn();
    const firstOnSubmissionReport = vi.fn();
    const first = renderHook(() =>
      useWizardPreflight({
        enabled: true,
        inputPath: "/tmp/cached-preflight.csv",
        sheet: 0,
        template: "curve",
        options: BASE_OPTIONS,
        onPreflight: firstOnPreflight,
        onSubmissionReport: firstOnSubmissionReport,
      }),
    );

    await act(async () => {
      await vi.advanceTimersByTimeAsync(220);
    });
    expect(firstOnSubmissionReport).toHaveBeenCalledWith(
      expect.objectContaining({ summary: "From cache" }),
    );
    expect(preflightRender).toHaveBeenCalledTimes(1);

    first.unmount();

    const secondOnPreflight = vi.fn();
    const secondOnSubmissionReport = vi.fn();
    renderHook(() =>
      useWizardPreflight({
        enabled: true,
        inputPath: "/tmp/cached-preflight.csv",
        sheet: 0,
        template: "curve",
        options: BASE_OPTIONS,
        onPreflight: secondOnPreflight,
        onSubmissionReport: secondOnSubmissionReport,
      }),
    );

    expect(secondOnPreflight).toHaveBeenCalledWith(
      expect.objectContaining({ output_filenames: ["curve.pdf"] }),
    );
    expect(secondOnSubmissionReport).toHaveBeenCalledWith(
      expect.objectContaining({ summary: "From cache" }),
    );
    expect(preflightRender).toHaveBeenCalledTimes(1);
  });
});
